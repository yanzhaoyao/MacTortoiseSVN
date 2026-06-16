import Cocoa
import CoreTypes
import FinderSync
import FinderSyncBridge
import OSLog
import StatusService
import StatusServiceXPC

private final class FinderMenuActionsBox: @unchecked Sendable {
    var actions: [FinderMenuActionDescriptor]

    init(actions: [FinderMenuActionDescriptor]) {
        self.actions = actions
    }
}

private struct FinderSelectionContext {
    var menuKind: FIMenuKind
    var selectedURLPaths: [String]
    var targetedPath: String?
    var candidatePaths: [String]
    var selectedPaths: [String]
    var rootPath: String?
}

private actor FinderStatusSnapshotCache {
    private let resolver = FinderBadgeResolver()
    private var stores: [String: SQLiteStatusCacheStore] = [:]
    private var snapshots: [String: (snapshot: BadgeSnapshot?, loadedAt: Date)] = [:]
    // Finder issues one requestBadgeIdentifier call per visible item, so a short
    // TTL avoids re-reading the SQLite cache for every file in a directory.
    private let snapshotTTL: TimeInterval = 2

    func snapshot(rootPath: String) async -> BadgeSnapshot? {
        if
            let cached = snapshots[rootPath],
            Date().timeIntervalSince(cached.loadedAt) < snapshotTTL
        {
            return cached.snapshot
        }

        let snapshot = await loadSnapshot(rootPath: rootPath)
        snapshots[rootPath] = (snapshot, Date())
        return snapshot
    }

    func assignments(rootPath: String, visiblePaths: [String]) async -> [FinderBadgeAssignment] {
        guard let snapshot = await snapshot(rootPath: rootPath) else {
            return []
        }
        return resolver.assignments(for: visiblePaths, snapshot: snapshot)
    }

    func invalidate() {
        snapshots.removeAll()
    }

    private func loadSnapshot(rootPath: String) async -> BadgeSnapshot? {
        let store: SQLiteStatusCacheStore
        if let existing = stores[rootPath] {
            store = existing
        } else {
            let databaseURL = StatusServiceConfiguration
                .development(repositoryRoot: rootPath)
                .databaseURL
            guard let created = try? SQLiteStatusCacheStore(databaseURL: databaseURL, readOnly: true) else {
                return nil
            }
            stores[rootPath] = created
            store = created
        }

        return (try? await store.loadSnapshot(for: rootPath)) ?? nil
    }
}

@objc(FinderSyncExtension)
public final class FinderSyncExtension: FIFinderSync {
    private let logger = Logger(
        subsystem: "com.morningstar.MacTortoiseSVN.FinderSync",
        category: "extension"
    )
    private let finderController = FIFinderSyncController.default()
    private let monitoredRootsStore = MacSVNMonitoredRootsStore()
    private let workbenchCommandStore = MacSVNWorkbenchCommandStore()
    private let statusSnapshotCache = FinderStatusSnapshotCache()
    private let menuBuilder = FinderContextMenuBuilder()
    private var cachedMonitoredRoots: [String] = []
    private var lastMenuSelectionContext: FinderSelectionContext?

    override init() {
        super.init()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleMonitoredRootsDidChange(_:)),
            name: MacSVNMonitoredRootsStore.distributedNotificationName,
            object: nil
        )
        registerKnownBadges()
        reloadMonitoredRoots()
        DistributedNotificationCenter.default().post(
            name: MacSVNMonitoredRootsStore.distributedRequestNotificationName,
            object: nil
        )
        diagnosticLog("init loaded cached monitored roots and requested refresh")
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    public override func beginObservingDirectory(at url: URL) {
        diagnosticLog("beginObservingDirectory path=\(url.path)")
    }

    public override func endObservingDirectory(at url: URL) {
        diagnosticLog("endObservingDirectory path=\(url.path)")
    }

    public override func requestBadgeIdentifier(for url: URL) {
        diagnosticLog("requestBadgeIdentifier path=\(url.path)")
        let path = url.standardizedFileURL.path
        guard let rootPath = rootPathForURL(url) else {
            diagnosticLog("requestBadgeIdentifier skipped: no rootPath")
            finderController.setBadgeIdentifier("", for: url)
            return
        }

        let statusSnapshotCache = self.statusSnapshotCache
        Task { [statusSnapshotCache] in
            let assignments = await statusSnapshotCache.assignments(
                rootPath: rootPath,
                visiblePaths: [path]
            )
            let badgeIdentifier = assignments.first?.badgeIdentifier ?? ""

            await MainActor.run {
                FIFinderSyncController.default().setBadgeIdentifier(
                    badgeIdentifier,
                    for: url
                )
            }
        }
    }

    public override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let language = MacSVNLanguageStore().loadLanguage()
        let localizer = MacSVNLocalizer(language: language)
        let menu = NSMenu(title: localizer.finderMenuTitle)
        let context = resolvedSelectionContext(menuKind: menuKind)
        lastMenuSelectionContext = context
        diagnosticLog(
            "menu kind=\(menuKindDescription(menuKind)) raw=\(menuKind.rawValue) " +
            "selectedURLs=\(summarizePaths(context.selectedURLPaths)) " +
            "targeted=\(context.targetedPath ?? "nil") " +
            "candidates=\(summarizePaths(context.candidatePaths)) " +
            "selected=\(summarizePaths(context.selectedPaths)) " +
            "root=\(context.rootPath ?? "nil")"
        )

        guard context.rootPath != nil else {
            let fallbackItem = NSMenuItem(
                title: localizer.title(for: .openInWorkbench),
                action: #selector(handleOpenInWorkbenchMenuItem(_:)),
                keyEquivalent: ""
            )
            fallbackItem.target = self
            menu.addItem(fallbackItem)
            return menu
        }

        let resolvedActions = resolveMenuActions(for: context, language: language)
        diagnosticLog(
            "menu actions count=\(resolvedActions.count) states=" +
            resolvedActions
                .map { "\($0.command.rawValue)=\($0.isEnabled)" }
                .joined(separator: "|")
        )

        for action in resolvedActions {
            let item = NSMenuItem(
                title: action.title,
                action: selector(for: action.command),
                keyEquivalent: ""
            )
            item.target = self
            item.isEnabled = action.isEnabled
            menu.addItem(item)
        }
        return menu
    }

    @objc
    private func handleUpdateWorkingCopyMenuItem(_ sender: NSMenuItem) {
        handleMenuCommand(.updateWorkingCopy, sender: sender)
    }

    @objc
    private func handleCommitSelectedMenuItem(_ sender: NSMenuItem) {
        handleMenuCommand(.commitSelected, sender: sender)
    }

    @objc
    private func handleDiffSelectedMenuItem(_ sender: NSMenuItem) {
        handleMenuCommand(.diffSelected, sender: sender)
    }

    @objc
    private func handleRefreshNowMenuItem(_ sender: NSMenuItem) {
        handleMenuCommand(.refreshNow, sender: sender)
    }

    @objc
    private func handleOpenInWorkbenchMenuItem(_ sender: NSMenuItem) {
        handleMenuCommand(.openInWorkbench, sender: sender)
    }

    private func handleMenuCommand(_ command: FinderMenuCommand, sender: NSMenuItem) {
        diagnosticLog(
            "handleMenuItem invoked command=\(command.rawValue) title=\(sender.title)"
        )
        let context = lastMenuSelectionContext ?? resolvedSelectionContext(menuKind: .contextualMenuForItems)
        let selectedPaths = context.selectedPaths
        let rootPath = context.rootPath
        diagnosticLog(
            "handleMenuItem command=\(command.rawValue) selected=\(selectedPaths.count) root=\(rootPath ?? "nil")"
        )

        switch command {
        case .refreshNow:
            guard let rootPath else {
                return
            }
            // The extension cannot reach the app-embedded XPC service; saving the
            // command posts a distributed notification the workbench reacts to.
            workbenchCommandStore.saveCommand(
                MacSVNWorkbenchCommand(
                    command: .refreshNow,
                    rootPath: rootPath,
                    selectedPaths: selectedPaths
                )
            )
            let statusSnapshotCache = self.statusSnapshotCache
            Task { [statusSnapshotCache] in
                await statusSnapshotCache.invalidate()
            }
        case .openInWorkbench, .updateWorkingCopy, .commitSelected, .diffSelected:
            openHostApp(command: command, rootPath: rootPath, selectedPaths: selectedPaths)
        }
    }

    private func registerKnownBadges() {
        for badge in FinderBadgeKind.allCases {
            let imageName: NSImage.Name
            switch badge {
            case .modified, .descendantDirty:
                imageName = NSImage.Name("NSStatusPartiallyAvailable")
            case .added:
                imageName = NSImage.Name("NSStatusAvailable")
            case .deleted:
                imageName = NSImage.Name("NSStatusUnavailable")
            case .conflicted:
                imageName = NSImage.Name("NSCaution")
            case .unversioned:
                imageName = NSImage.Name("NSAddTemplate")
            }

            finderController.setBadgeImage(
                NSImage(named: imageName) ?? finderStatusBadgeImage(for: badge),
                label: badge.badgeLabel,
                forBadgeIdentifier: badge.badgeIdentifier
            )
        }
    }

    private func finderStatusBadgeImage(for badge: FinderBadgeKind) -> NSImage {
        let size = NSSize(width: 64, height: 64)
        let image = NSImage(size: size)
        image.lockFocus()

        NSGraphicsContext.current?.imageInterpolation = .high
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let badgeRect = NSRect(x: 6, y: 6, width: 52, height: 52)
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 7
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)

        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        let basePath = NSBezierPath(ovalIn: badgeRect)
        badge.fillColor.setFill()
        basePath.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.94).setStroke()
        basePath.lineWidth = 5
        basePath.stroke()

        drawSymbol(for: badge, in: badgeRect.insetBy(dx: 12, dy: 12))

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func drawSymbol(for badge: FinderBadgeKind, in rect: NSRect) {
        let symbol = badge.symbol as NSString
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: CGFloat(badge.symbolFontSize), weight: .black),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ]
        let symbolSize = symbol.size(withAttributes: attributes)
        let textRect = NSRect(
            x: rect.midX - symbolSize.width / 2,
            y: rect.midY - symbolSize.height / 2 - CGFloat(badge.symbolBaselineOffset),
            width: symbolSize.width,
            height: symbolSize.height
        )
        symbol.draw(in: textRect, withAttributes: attributes)
    }

    @objc
    private func handleMonitoredRootsDidChange(_ notification: Notification) {
        diagnosticLog("handleMonitoredRootsDidChange")
        reloadMonitoredRoots()
    }

    private func reloadMonitoredRoots() {
        applyMonitoredRoots(monitoredRootsStore.loadRoots())
    }

    private func applyMonitoredRoots(_ monitoredRoots: [String]) {
        let normalizedRoots = Array(
            Set(monitoredRoots.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        ).sorted()
        let directoryURLs = normalizedRoots.map(URL.init(fileURLWithPath:))
        cachedMonitoredRoots = normalizedRoots

        if normalizedRoots.isEmpty {
            diagnosticLog("applyMonitoredRoots empty")
        } else {
            diagnosticLog("applyMonitoredRoots count=\(normalizedRoots.count)")
        }

        diagnosticLog(
            "reloadMonitoredRoots roots=\(normalizedRoots.joined(separator: ",")) " +
            "effective=\(directoryURLs.map { $0.path }.joined(separator: ","))"
        )
        finderController.directoryURLs = Set(directoryURLs)
    }

    private func resolveMenuActions(
        for context: FinderSelectionContext,
        language: MacSVNLanguage
    ) -> [FinderMenuActionDescriptor] {
        let fallbackActions = fallbackMenuActions(
            selectedPaths: context.selectedPaths,
            rootPath: context.rootPath,
            language: language
        )

        guard
            let rootPath = context.rootPath,
            !context.selectedPaths.isEmpty
        else {
            return fallbackActions
        }

        let semaphore = DispatchSemaphore(value: 0)
        let actionsBox = FinderMenuActionsBox(actions: fallbackActions)
        let startedAt = DispatchTime.now()
        let statusSnapshotCache = self.statusSnapshotCache
        let menuBuilder = self.menuBuilder
        let selectedPaths = context.selectedPaths

        Task { [statusSnapshotCache, actionsBox] in
            if let snapshot = await statusSnapshotCache.snapshot(rootPath: rootPath) {
                let resolvedActions = menuBuilder.actions(
                    for: selectedPaths,
                    snapshot: snapshot,
                    language: language
                )
                if !resolvedActions.isEmpty {
                    actionsBox.actions = resolvedActions
                }
            }
            semaphore.signal()
        }

        let didResolve = semaphore.wait(timeout: .now() + 0.3) == .success
        let elapsedMs = Int(
            Double(DispatchTime.now().uptimeNanoseconds - startedAt.uptimeNanoseconds) / 1_000_000
        )
        diagnosticLog(
            "menu resolution kind=\(menuKindDescription(context.menuKind)) " +
            "didResolve=\(didResolve) elapsedMs=\(elapsedMs)"
        )
        return actionsBox.actions
    }

    private func fallbackMenuActions(
        selectedPaths: [String],
        rootPath: String?,
        language: MacSVNLanguage
    ) -> [FinderMenuActionDescriptor] {
        let localizer = MacSVNLocalizer(language: language)
        let hasSelection = !selectedPaths.isEmpty
        let canOperate = hasSelection && rootPath != nil

        return [
            FinderMenuActionDescriptor(
                command: .updateWorkingCopy,
                title: localizer.title(for: .updateWorkingCopy),
                isEnabled: rootPath != nil
            ),
            FinderMenuActionDescriptor(
                command: .commitSelected,
                title: localizer.title(for: .commitSelected),
                isEnabled: canOperate
            ),
            FinderMenuActionDescriptor(
                command: .diffSelected,
                title: localizer.title(for: .diffSelected),
                isEnabled: canOperate && selectedPaths.count <= 2
            ),
            FinderMenuActionDescriptor(
                command: .refreshNow,
                title: localizer.title(for: .refreshNow),
                isEnabled: rootPath != nil
            ),
            FinderMenuActionDescriptor(
                command: .openInWorkbench,
                title: localizer.title(for: .openInWorkbench)
            ),
        ]
    }

    private func resolvedSelectionContext(menuKind: FIMenuKind) -> FinderSelectionContext {
        let selectedURLs = (finderController.selectedItemURLs() ?? [])
            .map(\.standardizedFileURL)
        let targetedURL = finderController.targetedURL()?.standardizedFileURL

        let candidateURLs: [URL]
        if !selectedURLs.isEmpty {
            candidateURLs = selectedURLs
        } else if let targetedURL {
            candidateURLs = [targetedURL]
        } else {
            candidateURLs = []
        }

        let selectedPaths = candidateURLs.map(\.path)
        let rootPath = candidateURLs.first.flatMap(rootPathForURL(_:))

        return FinderSelectionContext(
            menuKind: menuKind,
            selectedURLPaths: selectedURLs.map(\.path),
            targetedPath: targetedURL?.path,
            candidatePaths: candidateURLs.map(\.path),
            selectedPaths: selectedPaths,
            rootPath: rootPath
        )
    }

    private func rootPathForURL(_ url: URL) -> String? {
        let standardizedURL = url.standardizedFileURL
        let path = standardizedURL.hasDirectoryPath
            ? standardizedURL.path
            : standardizedURL.deletingLastPathComponent().path
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        return cachedMonitoredRoots
            .filter { standardizedPath == $0 || standardizedPath.hasPrefix($0 + "/") }
            .max(by: { $0.count < $1.count })
    }

    private func openHostApp(
        command: FinderMenuCommand,
        rootPath: String?,
        selectedPaths: [String]
    ) {
        guard let hostAppURL = hostAppURL() else {
            return
        }

        workbenchCommandStore.saveCommand(
            MacSVNWorkbenchCommand(
                command: command,
                rootPath: rootPath,
                selectedPaths: selectedPaths
            )
        )

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let bundleIdentifier = MacSVNXPCConstants.workbenchBundleIdentifier

        if let runningApp = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).first {
            diagnosticLog("openHostApp activatingRunningApp bundleIdentifier=\(bundleIdentifier)")
            runningApp.activate(options: [.activateAllWindows])
            return
        }

        let logger = self.logger
        NSWorkspace.shared.openApplication(at: hostAppURL, configuration: configuration) {
            runningApp, error in
            if let error {
                Self.diagnosticLog(
                    "openHostApp failed error=\(error.localizedDescription)",
                    logger: logger
                )
                return
            }

            Self.diagnosticLog(
                "openHostApp completed pid=\(runningApp?.processIdentifier ?? 0) " +
                "bundleIdentifier=\(runningApp?.bundleIdentifier ?? "nil")",
                logger: logger
            )
        }
    }

    private func hostAppURL() -> URL? {
        Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func diagnosticLog(_ message: String) {
        Self.diagnosticLog(message, logger: logger)
    }

    private static func diagnosticLog(_ message: String, logger: Logger) {
        logger.info("\(message, privacy: .public)")
        writeDiagnosticLog(message)
    }

    private static func writeDiagnosticLog(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        guard let logURL = macSVNDiagnosticLogURL(fileName: "finder-sync-debug.log") else {
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            guard let data = line.data(using: .utf8) else {
                return
            }
            if FileManager.default.fileExists(atPath: logURL.path),
               let handle = try? FileHandle(forWritingTo: logURL) {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: logURL, options: .atomic)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: logURL.path
                )
            }
        } catch {
            return
        }
    }

    private func menuKindDescription(_ menuKind: FIMenuKind) -> String {
        switch menuKind {
        case .contextualMenuForItems:
            return "items"
        case .contextualMenuForContainer:
            return "container"
        case .contextualMenuForSidebar:
            return "sidebar"
        case .toolbarItemMenu:
            return "toolbar"
        @unknown default:
            return "unknown"
        }
    }

    private func summarizePaths(_ paths: [String], limit: Int = 4) -> String {
        guard !paths.isEmpty else {
            return "[]"
        }

        let normalizedPaths = paths.map { $0.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
        let displayed = normalizedPaths.prefix(limit).joined(separator: " | ")
        if normalizedPaths.count > limit {
            return "[\(displayed) | +\(normalizedPaths.count - limit) more]"
        }
        return "[\(displayed)]"
    }

    private func selector(for command: FinderMenuCommand) -> Selector {
        switch command {
        case .updateWorkingCopy:
            return #selector(handleUpdateWorkingCopyMenuItem(_:))
        case .commitSelected:
            return #selector(handleCommitSelectedMenuItem(_:))
        case .diffSelected:
            return #selector(handleDiffSelectedMenuItem(_:))
        case .refreshNow:
            return #selector(handleRefreshNowMenuItem(_:))
        case .openInWorkbench:
            return #selector(handleOpenInWorkbenchMenuItem(_:))
        }
    }
}

private extension FinderBadgeKind {
    var fillColor: NSColor {
        switch self {
        case .modified, .descendantDirty:
            return NSColor(calibratedRed: 246 / 255, green: 166 / 255, blue: 35 / 255, alpha: 1)
        case .added:
            return NSColor(calibratedRed: 52 / 255, green: 199 / 255, blue: 89 / 255, alpha: 1)
        case .deleted:
            return NSColor(calibratedRed: 255 / 255, green: 69 / 255, blue: 58 / 255, alpha: 1)
        case .conflicted:
            return NSColor(calibratedRed: 191 / 255, green: 90 / 255, blue: 242 / 255, alpha: 1)
        case .unversioned:
            return NSColor(calibratedRed: 0 / 255, green: 122 / 255, blue: 255 / 255, alpha: 1)
        }
    }
}
