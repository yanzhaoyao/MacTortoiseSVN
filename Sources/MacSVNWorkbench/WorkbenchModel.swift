import AppKit
import CoreTypes
import FinderSyncBridge
import Foundation
import IntegrationKit
import StatusCenter
import StatusService
import StatusServiceXPC
import SVNCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class WorkbenchModel: NSObject, ObservableObject {
    enum DiffPreviewMode: String, CaseIterable, Identifiable {
        case workingCopy
        case historyRevision

        var id: String {
            rawValue
        }
    }

    private enum DiffPreviewRequestKey: Hashable {
        case workingCopy(
            rootPath: String,
            targetPath: String,
            status: VersionControlStatus,
            propertyModified: Bool,
            contentStamp: DiffContentStamp
        )
        case historyRevision(rootPath: String, revision: Int64)
    }

    private struct DiffContentStamp: Hashable {
        var modificationTime: TimeInterval?
        var fileSize: Int?
    }

    private struct AddPreviewConfirmation {
        var paths: [String]
        var depth: SVNDepth
    }

    private struct TextPromptField {
        var label: String
        var value: String = ""
        var isSecure: Bool = false
    }

    struct UpdateActivity: Equatable {
        enum State: Equatable {
            case running
            case completed
            case failed(String)
        }

        var state: State
        var rootPath: String
        var displayPaths: [String]
        var revision: Int64?
        var hasConflicts: Bool
        var startedAt: Date
        var completedAt: Date?
        var rawOutput: String
    }

    struct Entry: Identifiable, Hashable {
        let item: WorkingCopyItem
        let relativePath: String

        var id: String { item.path }
        var status: VersionControlStatus { item.status }
        var isDirectory: Bool { item.isDirectory }
        var isActionable: Bool { item.status.isDirty || item.status == .unversioned || item.propertyModified }
        var canAdd: Bool { item.status == .unversioned }
        var canCommit: Bool { item.status.isDirty || item.propertyModified }
        var canRevert: Bool { item.status.isDirty || item.propertyModified }
        var canResolve: Bool { item.status == .conflicted }
        var canLock: Bool { item.status != .unversioned && item.status != .locked }
        var canUnlock: Bool { item.status == .locked }
        var canRename: Bool { item.status != .unversioned }
        var canBlame: Bool { item.status != .unversioned && !isDirectory }
        var canCreatePatch: Bool { item.status.isDirty }
        var canShowProperties: Bool { item.status != .unversioned }
        var canShowLog: Bool { item.status != .unversioned }
    }

    @Published var rootPath: String
    @Published var commitMessage = ""
    @Published var language: MacSVNLanguage {
        didSet {
            if oldValue != language {
                languageStore.saveLanguage(language)
            }
        }
    }
    @Published private(set) var entries: [Entry] = []
    @Published var treeNodes: [ChangeTreeNode] = []
    @Published private(set) var selectedPaths: Set<String> = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isRefreshScheduled = false
    @Published private(set) var isMonitoring = false
    @Published private(set) var badgeEntryCount = 0
    @Published private(set) var dirtyCount = 0
    @Published private(set) var unversionedCount = 0
    @Published private(set) var lastRefreshDate: Date?
    @Published private(set) var repositorySummary: SVNRepositorySummary?
    @Published private(set) var repositoryBrowserListing: SVNRepositoryBrowserListing?
    @Published private(set) var repositoryBrowserRootURL: String?
    @Published private(set) var repositoryBrowserWorkingCopyURL: String?
    @Published private(set) var isLoadingRepositoryBrowser = false
    @Published private(set) var repositoryBrowserError: String?
    @Published private(set) var selectedRepositoryBrowserEntry: SVNRepositoryBrowserEntry?
    @Published private(set) var repositoryBrowserPreviewText: String?
    @Published private(set) var repositoryBrowserPreviewMessage: String?
    @Published private(set) var repositoryBrowserPreviewError: String?
    @Published private(set) var isLoadingRepositoryBrowserPreview = false
    @Published private(set) var recentHistory: [SVNHistoryEntry] = []
    @Published private(set) var recentHistoryError: String?
    @Published private(set) var isLoadingRecentHistory = false
    @Published private(set) var selectedHistoryRevision: Int64?
    @Published private(set) var selectedHistoryEntryDetail: SVNHistoryEntryDetail?
    @Published private(set) var isLoadingHistoryDetail = false
    @Published var preferredDiffPreviewMode: DiffPreviewMode = .workingCopy
    @Published private(set) var selectedDiffText: String?
    @Published private(set) var isLoadingDiffPreview = false
    @Published private(set) var diffPreviewMessage: String?
    @Published private(set) var diffPreviewError: String?
    @Published private(set) var isLaunchingExternalDiff = false
    @Published private(set) var statusNotice: WorkbenchNotice
    @Published private(set) var lastError: String?
    @Published private(set) var updateActivitiesByRoot: [String: UpdateActivity] = [:]
    @Published private(set) var externalTools: [ExternalToolProfile] = []
    @Published var refreshStatusAfterCommit = true
    @Published private(set) var isRunningWorkspaceOperation = false
    @Published var defaultWindowPreset: WorkbenchWindowPreset {
        didSet {
            guard oldValue != defaultWindowPreset else {
                return
            }
            savePresentationPreferences()
            requestWindowPresentationRefresh()
        }
    }
    @Published var hideDiffPreviewInCompactWindow: Bool {
        didSet {
            guard oldValue != hideDiffPreviewInCompactWindow else {
                return
            }
            savePresentationPreferences()
        }
    }
    @Published var backendMode: WorkbenchBackendMode {
        didSet {
            guard oldValue != backendMode else { return }
            resetConfiguredServicesForPreferenceChange()
            savePresentationPreferences()
        }
    }
    @Published var preserveModificationTimes: Bool {
        didSet {
            guard oldValue != preserveModificationTimes else { return }
            resetConfiguredServicesForPreferenceChange()
            savePresentationPreferences()
        }
    }
    @Published var maxConcurrentOperations: Int {
        didSet {
            maxConcurrentOperations = min(max(maxConcurrentOperations, 1), 8)
            guard oldValue != maxConcurrentOperations else { return }
            resetConfiguredServicesForPreferenceChange()
            savePresentationPreferences()
        }
    }
    @Published var badgeEntryLimit: Int {
        didSet {
            badgeEntryLimit = min(max(badgeEntryLimit, 256), 50000)
            guard oldValue != badgeEntryLimit else { return }
            resetConfiguredServicesForPreferenceChange()
            savePresentationPreferences()
        }
    }
    @Published var maxIncrementalDirtyPaths: Int {
        didSet {
            maxIncrementalDirtyPaths = min(max(maxIncrementalDirtyPaths, 16), 4096)
            guard oldValue != maxIncrementalDirtyPaths else { return }
            resetConfiguredServicesForPreferenceChange()
            savePresentationPreferences()
        }
    }
    @Published var selectedExternalDiffToolID: String {
        didSet {
            guard oldValue != selectedExternalDiffToolID else { return }
            savePresentationPreferences()
        }
    }
    @Published private(set) var windowPresentationRevision = UUID()

    enum NavigationItem: String, CaseIterable, Identifiable {
        case changes
        case repoBrowser
        case history

        var id: String { rawValue }
    }

    @Published var activeNavigation: NavigationItem = .changes
    @Published var bookmarks: [WorkspaceBookmark] = []
    @Published var visibilityPrefs: WorkbenchPresentationPreferences {
        didSet {
            guard oldValue != visibilityPrefs else { return }
            if isSidebarVisible != visibilityPrefs.showSidebar {
                isSidebarVisible = visibilityPrefs.showSidebar
            }
            savePresentationPreferences()
        }
    }
    @Published var isSidebarVisible = true {
        didSet {
            guard oldValue != isSidebarVisible else { return }
            if visibilityPrefs.showSidebar != isSidebarVisible {
                visibilityPrefs.showSidebar = isSidebarVisible
                return
            }
            savePresentationPreferences()
        }
    }

    @Published private(set) var blameLines: [BlameLine] = []
    @Published private(set) var isLoadingBlame = false
    @Published private(set) var blameError: String?
    @Published var isBlamePresented = false
    @Published var blameTargetPath: String?

    @Published private(set) var propertyList: [SVNPropertyEntry] = []
    @Published private(set) var isLoadingProperties = false
    @Published private(set) var propertiesError: String?
    @Published var isPropertiesPresented = false
    @Published var propertiesTargetPath: String?

    @Published var isRenamePresented = false
    @Published var renameTargetPath: String?
    @Published var renameNewName = ""

    private var host: StatusServiceHost?
    private var xpcClient: StatusServiceXPCClient?
    private var client: RustCommandBridgeSVNClient?
    private var workspaceOperator: SubversionWorkspaceOperator?
    private var repositoryInspector: SubversionRepositoryInspector?
    private var diffInspector: SubversionDiffInspector?
    private var hasQueuedRefresh = false
    private var queuedRefreshNeedsFullRescan = false
    private var scheduledRefreshNeedsFullRescan = false
    private var configuredRootPath: String?
    private var pendingWorkbenchCommand: MacSVNWorkbenchCommand?
    private var lastHandledWorkbenchCommandID: UUID?
    private let runtimePaths: MacSVNRuntimePaths
    private let languageStore = MacSVNLanguageStore()
    private let monitoredRootsStore = MacSVNMonitoredRootsStore()
    private let workbenchCommandStore = MacSVNWorkbenchCommandStore()
    private let presentationPreferencesStore = WorkbenchPresentationPreferencesStore()
    private let bookmarkStore = WorkspaceBookmarkStore()
    private let securityScopedBookmarkStore = MacSVNSecurityScopedBookmarkStore()
    private let registry = ExternalToolRegistry()
    private let externalToolLauncher = ExternalToolLauncher()
    private let runner = ProcessSubversionRunner()
    private var entryByPath: [String: Entry] = [:]
    private var diffPreviewTask: Task<Void, Never>?
    private var diffPreviewDebounceTask: Task<Void, Never>?
    private var repositoryBrowserPreviewTask: Task<Void, Never>?
    private var updateWorkingCopyTask: Task<Void, Never>?
    private var lastDiffPreviewRequest: DiffPreviewRequestKey?
    private let externalDiffArtifactsRootURL: URL
    private var externalDiffArtifactDirectories: [URL] = []
    private var rootSecurityScopedAccess: MacSVNSecurityScopedAccess?
    private var isRecentHistoryRequestRunning = false
    private var historyDetailRequestRevision: Int64?

    override init() {
        let initialCommand = MacSVNWorkbenchCommandStore().loadCommand()
        let initialRoot = initialCommand?.rootPath
            ?? CommandLine.arguments.dropFirst().first
            ?? ""
        let initialLanguage = MacSVNLanguageStore().loadLanguage()
        let initialPresentationPreferences = WorkbenchPresentationPreferencesStore().load()
        self.rootPath = initialRoot
        self.language = initialLanguage
        self.defaultWindowPreset = initialPresentationPreferences.defaultWindowPreset
        self.hideDiffPreviewInCompactWindow = initialPresentationPreferences.hideDiffPreviewInCompactWindow
        self.backendMode = initialPresentationPreferences.backendMode
        self.preserveModificationTimes = initialPresentationPreferences.preserveModificationTimes
        self.maxConcurrentOperations = initialPresentationPreferences.maxConcurrentOperations
        self.badgeEntryLimit = initialPresentationPreferences.badgeEntryLimit
        self.maxIncrementalDirtyPaths = initialPresentationPreferences.maxIncrementalDirtyPaths
        self.selectedExternalDiffToolID = initialPresentationPreferences.selectedExternalDiffToolID
        self.visibilityPrefs = initialPresentationPreferences
        self.isSidebarVisible = initialPresentationPreferences.showSidebar
        self.bookmarks = WorkspaceBookmarkStore().load()
        self.runtimePaths = MacSVNRuntimePaths.currentProcess()
        self.statusNotice = .chooseWorkingCopyPrompt
        self.pendingWorkbenchCommand = initialCommand
        self.externalDiffArtifactsRootURL = FileManager.default.temporaryDirectory
            .appending(path: "MacTortoiseSVN-ExternalDiff")
            .appending(path: UUID().uuidString)
        super.init()

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleMonitoredRootsRequest(_:)),
            name: MacSVNMonitoredRootsStore.distributedRequestNotificationName,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleWorkbenchCommandDidChange(_:)),
            name: MacSVNWorkbenchCommandStore.distributedNotificationName,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive(_:)),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )

        diagnosticLog(
            "init initialRoot=\(initialRoot) initialCommand=\(initialCommand?.command.rawValue ?? "nil")"
        )
        if let initialCommand {
            statusNotice = .processingFinderCommand(
                command: initialCommand.command,
                pathCount: max(initialCommand.selectedPaths.count, 1)
            )
        }

        if initialCommand?.rootPath != nil {
            broadcastCurrentMonitoredRoot()
            requestRefresh(forceFullRefresh: true)
        }

        Task {
            let profiles = await registry.bootstrapDefaultProfiles()
            externalTools = profiles
            if selectedExternalDiffToolID.isEmpty, let firstProfile = profiles.first {
                selectedExternalDiffToolID = firstProfile.id
            }
        }
    }

    var selectedCount: Int {
        selectedPaths.count
    }

    var selectedEntries: [Entry] {
        selectedPaths.compactMap { entryByPath[$0] }
            .sorted { lhs, rhs in
                lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
            }
    }

    var primarySelectedEntry: Entry? {
        selectedEntries.first
    }

    var selectedHistoryEntry: SVNHistoryEntry? {
        guard let selectedHistoryRevision else {
            return nil
        }

        return recentHistory.first(where: { $0.revision == selectedHistoryRevision })
    }

    var availableDiffPreviewModes: [DiffPreviewMode] {
        var modes: [DiffPreviewMode] = []
        if primarySelectedEntry != nil {
            modes.append(.workingCopy)
        }
        if selectedHistoryRevision != nil {
            modes.append(.historyRevision)
        }
        return modes
    }

    var effectiveDiffPreviewMode: DiffPreviewMode? {
        if availableDiffPreviewModes.contains(preferredDiffPreviewMode) {
            return preferredDiffPreviewMode
        }

        return availableDiffPreviewModes.first
    }

    var preferredWindowContentSize: CGSize {
        defaultWindowPreset.defaultContentSize
    }

    var canRefresh: Bool {
        !normalizedRootInput.isEmpty && !isRefreshing && !isRefreshScheduled && !isRunningWorkspaceOperation
    }

    var canUpdateWorkingCopy: Bool {
        !normalizedRootInput.isEmpty && !isBusy
    }

    var canCleanupWorkingCopy: Bool {
        !normalizedRootInput.isEmpty && !isBusy
    }

    var canAddSelected: Bool {
        selectedEntries.contains(where: \.canAdd) && !isBusy
    }

    var canCommitSelected: Bool {
        selectedEntries.contains(where: \.canCommit)
            && !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isBusy
    }

    var canShelveSelected: Bool {
        selectedEntries.contains(where: { $0.canCommit || $0.canRevert }) && !isBusy
    }

    var canUnshelve: Bool {
        !normalizedRootInput.isEmpty && !isBusy
    }

    var canRevertSelected: Bool {
        selectedEntries.contains(where: \.canRevert) && !isBusy
    }

    var canResolveSelected: Bool {
        selectedEntries.contains(where: \.canResolve) && !isBusy
    }

    var isBusy: Bool {
        isRefreshing || isRunningWorkspaceOperation
    }

    var canBrowseRepositoryRoot: Bool {
        repositoryBrowserRootURL != nil && !isLoadingRepositoryBrowser
    }

    var canBrowseWorkingCopyLocation: Bool {
        repositoryBrowserWorkingCopyURL != nil && !isLoadingRepositoryBrowser
    }

    var canBrowseParentRepositoryDirectory: Bool {
        repositoryBrowserParentURL != nil && !isLoadingRepositoryBrowser
    }

    var repositoryBrowserCurrentURLText: String {
        repositoryBrowserListing?.baseURL ?? localizer.repositoryBrowserEmptyDescription
    }

    var repositoryBrowserParentURL: String? {
        guard
            let currentURLString = repositoryBrowserListing?.baseURL,
            let currentURL = URL(string: currentURLString),
            let rootURLString = repositoryBrowserRootURL,
            let rootURL = URL(string: rootURLString)
        else {
            return nil
        }

        let normalizedCurrent = currentURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let normalizedRoot = rootURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard normalizedCurrent != normalizedRoot else {
            return nil
        }

        let parentURL = currentURL.deletingLastPathComponent()
        let normalizedParent = parentURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard normalizedParent.count >= normalizedRoot.count else {
            return nil
        }
        guard normalizedParent.hasPrefix(normalizedRoot) else {
            return nil
        }
        return parentURL.absoluteString
    }

    var externalToolSummary: String {
        if externalTools.isEmpty {
            return localizer.loadingDiffProfiles
        }

        return externalTools.map(\.displayName).joined(separator: "  |  ")
    }

    var statusMessage: String {
        statusNotice.text(using: localizer)
    }

    var updateActivity: UpdateActivity? {
        guard let key = currentUpdateActivityKey else {
            return nil
        }

        return updateActivitiesByRoot[key]
    }

    var localizer: MacSVNLocalizer {
        MacSVNLocalizer(language: language)
    }

    func applyPreferredWindowPresentation(to window: NSWindow) {
        window.title = localizer.appTitle
        window.minSize = CGSize(width: 780, height: 560)
        window.setContentSize(preferredWindowContentSize)
    }

    func requestWindowPresentationRefresh() {
        windowPresentationRevision = UUID()
    }

    func chooseWorkingCopy() {
        let panel = NSOpenPanel()
        panel.message = localizer.chooseWorkingCopyPanelMessage
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            securityScopedBookmarkStore.saveBookmark(for: url)
            rootPath = url.standardizedFileURL.path
            broadcastCurrentMonitoredRoot()
        }
    }

    func toggleSelection(for path: String) {
        guard entryByPath[path]?.isActionable == true else {
            return
        }

        if selectedPaths.contains(path) {
            selectedPaths.remove(path)
        } else {
            selectedPaths.insert(path)
        }

        preferredDiffPreviewMode = .workingCopy
        refreshDiffPreview()
    }

    func setSelection(for paths: [String], isSelected: Bool) {
        let normalizedPaths = Set(paths.filter { entryByPath[$0]?.isActionable == true })
        guard !normalizedPaths.isEmpty else {
            return
        }

        if isSelected {
            selectedPaths.formUnion(normalizedPaths)
        } else {
            selectedPaths.subtract(normalizedPaths)
        }

        preferredDiffPreviewMode = .workingCopy
        refreshDiffPreview()
    }

    func selectAllActionable() {
        selectedPaths = Set(entryByPath.values.lazy.filter(\.isActionable).map(\.id))
        preferredDiffPreviewMode = .workingCopy
        refreshDiffPreview()
    }

    func clearSelection() {
        selectedPaths.removeAll()
        refreshDiffPreview()
    }

    func refreshSnapshot(forceFullRefresh: Bool) {
        guard canRefresh else {
            diagnosticLog(
                "refreshSnapshot ignored root=\(normalizedRootInput) forceFullRefresh=\(forceFullRefresh) " +
                "isRefreshing=\(isRefreshing) isRefreshScheduled=\(isRefreshScheduled) " +
                "isRunningWorkspaceOperation=\(isRunningWorkspaceOperation)"
            )
            return
        }

        requestRefresh(forceFullRefresh: forceFullRefresh)
    }

    func showHistory() {
        activeNavigation = .history
        loadRecentHistoryIfNeeded()
    }

    func loadRecentHistoryIfNeeded() {
        guard !isRecentHistoryRequestRunning, recentHistory.isEmpty, recentHistoryError == nil else {
            return
        }

        refreshRecentHistory()
    }

    func refreshRecentHistory() {
        guard !isRecentHistoryRequestRunning else {
            return
        }

        isRecentHistoryRequestRunning = true
        isLoadingRecentHistory = true
        Task {
            await performRefreshRecentHistory()
        }
    }

    func toggleMonitoring() {
        Task {
            await performToggleMonitoring()
        }
    }

    func addSelected() {
        Task {
            await performAddSelected()
        }
    }

    func shelveSelected() {
        Task {
            await performShelveSelected()
        }
    }

    func unshelveNamedShelf() {
        Task {
            await performUnshelveNamedShelf()
        }
    }

    func checkoutWorkingCopy() {
        guard
            let values = promptTextValues(
                title: localizer.checkoutWorkingCopy,
                fields: [
                    TextPromptField(label: localizer.repositoryURLPrompt),
                    TextPromptField(label: localizer.destinationPathPrompt),
                ]
            )
        else {
            return
        }

        Task {
            await performCheckoutWorkingCopy(
                repositoryURL: values[0],
                destinationPath: values[1]
            )
        }
    }

    func importToRepository() {
        guard
            let values = promptTextValues(
                title: localizer.importToRepository,
                fields: [
                    TextPromptField(label: localizer.sourcePathPrompt, value: normalizedRootInput),
                    TextPromptField(label: localizer.repositoryURLPrompt),
                    TextPromptField(label: localizer.importMessagePrompt),
                ]
            )
        else {
            return
        }

        Task {
            await performImportToRepository(
                sourcePath: values[0],
                repositoryURL: values[1],
                message: values[2]
            )
        }
    }

    func exportWorkingCopy() {
        guard
            let values = promptTextValues(
                title: localizer.exportWorkingCopy,
                fields: [
                    TextPromptField(label: localizer.sourcePathPrompt, value: normalizedRootInput),
                    TextPromptField(label: localizer.destinationPathPrompt),
                ]
            )
        else {
            return
        }

        Task {
            await performExportWorkingCopy(
                source: values[0],
                destinationPath: values[1]
            )
        }
    }

    func switchWorkingCopy() {
        guard
            let values = promptTextValues(
                title: localizer.switchWorkingCopy,
                fields: [
                    TextPromptField(label: localizer.repositoryURLPrompt),
                ]
            )
        else {
            return
        }

        Task {
            await performSwitchWorkingCopy(repositoryURL: values[0])
        }
    }

    func relocateWorkingCopy() {
        guard
            let values = promptTextValues(
                title: localizer.relocateWorkingCopy,
                fields: [
                    TextPromptField(label: localizer.fromRepositoryURLPrompt, value: repositorySummary?.repositoryRootURL ?? ""),
                    TextPromptField(label: localizer.toRepositoryURLPrompt),
                ]
            )
        else {
            return
        }

        Task {
            await performRelocateWorkingCopy(
                fromURL: values[0],
                toURL: values[1]
            )
        }
    }

    func updateWorkingCopy() {
        cancelUpdateWorkingCopy(markAsCancelled: false)
        updateWorkingCopyTask = Task { @MainActor [weak self] in
            await self?.performUpdateWorkingCopy()
        }
    }

    func cancelUpdateWorkingCopy(markAsCancelled: Bool = true) {
        updateWorkingCopyTask?.cancel()
        updateWorkingCopyTask = nil

        guard markAsCancelled || isRunningWorkspaceOperation else {
            return
        }

        isRunningWorkspaceOperation = false
        if markAsCancelled {
            lastError = localizer.updateCancelled
            statusNotice = .updateFailed
        }

        if let key = currentUpdateActivityKey,
           let activity = updateActivitiesByRoot[key],
           case .running = activity.state
        {
            setUpdateActivity(
                UpdateActivity(
                    state: .failed(markAsCancelled ? localizer.updateCancelled : (lastError ?? localizer.updateFailed)),
                    rootPath: activity.rootPath,
                    displayPaths: [],
                    revision: nil,
                    hasConflicts: false,
                    startedAt: activity.startedAt,
                    completedAt: Date(),
                    rawOutput: ""
                ),
                for: activity.rootPath
            )
        }
    }

    func revertSelected() {
        let revertablePaths = collapsedPaths(
            selectedEntries.filter(\.canRevert).map(\.id)
        )
        guard !revertablePaths.isEmpty else {
            lastError = localizer.selectModifiedToRevertError
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = localizer.confirmRevertTitle
        alert.informativeText = localizer.confirmRevertMessage(pathCount: revertablePaths.count)
        alert.addButton(withTitle: localizer.confirmRevertButtonTitle)
        alert.addButton(withTitle: localizer.cancelTitle)

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        Task {
            await performRevertSelected(paths: revertablePaths)
        }
    }

    func cleanupWorkingCopy() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = localizer.confirmCleanupTitle
        alert.informativeText = localizer.confirmCleanupMessage
        alert.addButton(withTitle: localizer.confirmCleanupButtonTitle)
        alert.addButton(withTitle: localizer.cancelTitle)

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        Task {
            await performCleanupWorkingCopy()
        }
    }

    func resolveSelected() {
        let resolvablePaths = collapsedPaths(
            selectedEntries.filter(\.canResolve).map(\.id)
        )
        guard !resolvablePaths.isEmpty else {
            lastError = localizer.selectConflictedToResolveError
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = localizer.confirmResolveTitle
        alert.informativeText = localizer.confirmResolveMessage(pathCount: resolvablePaths.count)
        alert.addButton(withTitle: localizer.confirmResolveButtonTitle)
        alert.addButton(withTitle: localizer.cancelTitle)

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        Task {
            await performResolveSelected(paths: resolvablePaths)
        }
    }

    func commitSelected() {
        Task {
            await performCommitSelected()
        }
    }

    func showHistoryDetail(for revision: Int64) {
        guard !(isLoadingHistoryDetail && selectedHistoryRevision == revision) else {
            return
        }

        beginHistoryDetailRequest(for: revision, preferDiffPreview: true)
        Task {
            await loadHistoryDetail(for: revision)
        }
    }

    func setPreferredDiffPreviewMode(_ mode: DiffPreviewMode) {
        preferredDiffPreviewMode = mode
        refreshDiffPreview(forceReload: true)
    }

    func browseRepositoryRoot() {
        guard let repositoryBrowserRootURL else {
            return
        }
        Task {
            await loadRepositoryBrowserListing(url: repositoryBrowserRootURL)
        }
    }

    func browseWorkingCopyRepositoryLocation() {
        guard let repositoryBrowserWorkingCopyURL else {
            return
        }
        Task {
            await loadRepositoryBrowserListing(url: repositoryBrowserWorkingCopyURL)
        }
    }

    func browseParentRepositoryDirectory() {
        guard let repositoryBrowserParentURL else {
            return
        }
        Task {
            await loadRepositoryBrowserListing(url: repositoryBrowserParentURL)
        }
    }

    func refreshRepositoryBrowser() {
        guard let currentURL = repositoryBrowserListing?.baseURL ?? repositoryBrowserWorkingCopyURL else {
            return
        }
        Task {
            await loadRepositoryBrowserListing(url: currentURL)
        }
    }

    func openRepositoryBrowserEntry(_ entry: SVNRepositoryBrowserEntry) {
        guard entry.isDirectory else {
            return
        }
        Task {
            await loadRepositoryBrowserListing(url: entry.fullURL)
        }
    }

    func selectRepositoryBrowserEntry(_ entry: SVNRepositoryBrowserEntry) {
        if entry.isDirectory {
            openRepositoryBrowserEntry(entry)
            return
        }

        Task {
            await loadRepositoryBrowserFilePreview(for: entry)
        }
    }

    func openCurrentRepositoryBrowserLocationInBrowser() {
        guard let urlString = repositoryBrowserListing?.baseURL ?? repositoryBrowserWorkingCopyURL else {
            return
        }
        openRepositoryURLInBrowser(urlString)
    }

    func copyCurrentRepositoryBrowserLocation() {
        guard let urlString = repositoryBrowserListing?.baseURL ?? repositoryBrowserWorkingCopyURL else {
            return
        }
        copyRepositoryURL(urlString)
    }

    func openRepositoryBrowserEntryInBrowser(_ entry: SVNRepositoryBrowserEntry) {
        openRepositoryURLInBrowser(entry.fullURL)
    }

    func copyRepositoryBrowserEntryURL(_ entry: SVNRepositoryBrowserEntry) {
        copyRepositoryURL(entry.fullURL)
    }

    func openSelectedEntryInExternalDiff(using profile: ExternalToolProfile) {
        preferredDiffPreviewMode = .workingCopy
        Task {
            await performOpenSelectedEntryInExternalDiff(using: profile)
        }
    }

    func isHistoryEntrySelected(_ entry: SVNHistoryEntry) -> Bool {
        selectedHistoryRevision == entry.revision
    }

    func actionablePaths(for node: ChangeTreeNode) -> [String] {
        let prefix = node.absolutePath + "/"
        return entries.compactMap { entry in
            guard entry.isActionable else {
                return nil
            }
            guard entry.id == node.absolutePath || entry.id.hasPrefix(prefix) else {
                return nil
            }
            return entry.id
        }
    }

    // MARK: - Single-File Context Menu Operations

    func revertPath(_ path: String) {
        guard let entry = entryByPath[path], entry.canRevert else {
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = localizer.confirmRevertTitle
        alert.informativeText = localizer.confirmRevertMessage(pathCount: 1)
        alert.addButton(withTitle: localizer.confirmRevertButtonTitle)
        alert.addButton(withTitle: localizer.cancelTitle)

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        Task {
            await performRevertSelected(paths: [path])
        }
    }

    func addPath(_ path: String) {
        guard let entry = entryByPath[path], entry.canAdd else {
            return
        }

        Task {
            guard !isBusy else {
                return
            }

            do {
                _ = try await configureServicesIfNeeded()
                guard let client else {
                    throw WorkbenchError.notConfigured
                }
                guard let confirmation = confirmAddPreview(for: [entry]) else {
                    return
                }
                guard !confirmation.paths.isEmpty else {
                    lastError = localizer.selectUnversionedToAddError
                    return
                }

                isRunningWorkspaceOperation = true
                defer { isRunningWorkspaceOperation = false }
                try await client.add(
                    paths: confirmation.paths,
                    depth: confirmation.depth,
                    force: false,
                    context: .foreground
                )
                statusNotice = .addedPaths(confirmation.paths.count)
                lastError = nil
                await enqueueRefresh(forceFullRefresh: true)
            } catch {
                lastError = localizedErrorMessage(for: error)
                statusNotice = .addFailed
            }
        }
    }

    func resolvePath(_ path: String) {
        guard let entry = entryByPath[path], entry.canResolve else {
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = localizer.confirmResolveTitle
        alert.informativeText = localizer.confirmResolveMessage(pathCount: 1)
        alert.addButton(withTitle: localizer.confirmResolveButtonTitle)
        alert.addButton(withTitle: localizer.cancelTitle)

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        Task {
            await performResolveSelected(paths: [path])
        }
    }

    func deletePath(_ path: String) {
        let displayName = (path as NSString).lastPathComponent
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = localizer.contextDeleteConfirmTitle
        alert.informativeText = localizer.contextDeleteConfirmMessage(displayName)
        alert.addButton(withTitle: localizer.contextDeleteConfirmButton)
        alert.addButton(withTitle: localizer.cancelTitle)

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        Task {
            do {
                _ = try await configureServicesIfNeeded()
                let isUnversioned = entryByPath[path]?.status == .unversioned
                if isUnversioned {
                    try FileManager.default.removeItem(atPath: path)
                } else {
                    guard client != nil else {
                        throw WorkbenchError.notConfigured
                    }
                    let runner = ProcessSubversionRunner()
                    let request = SubversionCLIInvocationRequest(
                        arguments: ["delete", "--force", "--", path],
                        workingDirectory: normalizedRootInput
                    )
                    let result = try await runner.run(request)
                    guard result.exitCode == 0 else {
                        throw WorkbenchError.operationFailed(result.stderr)
                    }
                }
                statusNotice = .deletedPath(displayName)
                lastError = nil
                await enqueueRefresh(forceFullRefresh: true)
            } catch {
                lastError = localizedErrorMessage(for: error)
            }
        }
    }

    func ignorePath(_ path: String) {
        Task {
            do {
                _ = try await configureServicesIfNeeded()
                let fileName = (path as NSString).lastPathComponent
                let parentDir = (path as NSString).deletingLastPathComponent
                let runner = ProcessSubversionRunner()

                let getRequest = SubversionCLIInvocationRequest(
                    arguments: ["propget", "--", "svn:ignore", parentDir],
                    workingDirectory: normalizedRootInput
                )
                let getResult = try await runner.run(getRequest)
                var ignoreList = getResult.exitCode == 0
                    ? getResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    : ""

                let existingEntries = Set(ignoreList.split(separator: "\n").map(String.init))
                guard !existingEntries.contains(fileName) else {
                    statusNotice = .ignoredPath(fileName)
                    return
                }

                if !ignoreList.isEmpty && !ignoreList.hasSuffix("\n") {
                    ignoreList += "\n"
                }
                ignoreList += fileName + "\n"

                let setRequest = SubversionCLIInvocationRequest(
                    arguments: ["propset", "--", "svn:ignore", ignoreList, parentDir],
                    workingDirectory: normalizedRootInput
                )
                let setResult = try await runner.run(setRequest)
                guard setResult.exitCode == 0 else {
                    throw WorkbenchError.operationFailed(setResult.stderr)
                }

                statusNotice = .ignoredPath(fileName)
                lastError = nil
                await enqueueRefresh(forceFullRefresh: true)
            } catch {
                lastError = localizedErrorMessage(for: error)
            }
        }
    }

    func rollbackPath(_ path: String, revision: Int64? = nil) {
        guard let entry = entryByPath[path] else {
            return
        }

        Task {
            do {
                _ = try await configureServicesIfNeeded()
                guard let workspaceOperator else {
                    throw WorkbenchError.notConfigured
                }

                let pathsToRollback: [String]
                let revisionArgument: String?

                if let revision {
                    // Rollback to specific revision
                    pathsToRollback = [path]
                    revisionArgument = String(revision)
                } else {
                    // Get recent history from the repository
                    let fallbackRoot = normalizedRootInput
                    let root = configuredRootPath ?? (fallbackRoot.isEmpty ? "" : Self.standardizedPath(fallbackRoot))
                    guard !root.isEmpty else {
                        lastError = localizer.rollbackNoHistoryError
                        return
                    }

                    guard let repositoryInspector else {
                        throw WorkbenchError.notConfigured
                    }

                    let history = try await repositoryInspector.recentHistory(
                        at: root,
                        limit: 10,
                        context: .foreground
                    )

                    guard history.count >= 2 else {
                        lastError = localizer.rollbackNoHistoryError
                        return
                    }

                    let prevRevision = history[1].revision
                    pathsToRollback = [path]
                    revisionArgument = String(prevRevision)
                }

                let result = try await workspaceOperator.rollback(
                    paths: pathsToRollback,
                    revision: Int64(revisionArgument ?? "BASE") ?? 0,
                    recursive: entry.isDirectory,
                    context: .foreground
                )

                lastError = nil
                statusNotice = .revertedPaths(result.revertedPaths.count)
                await enqueueRefresh(forceFullRefresh: true)
            } catch {
                lastError = localizedErrorMessage(for: error)
                statusNotice = .revertFailed
            }
        }
    }

    func ignoreDirectory(_ path: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = localizer.ignoreDirectoryTitle
        alert.informativeText = localizer.ignoreDirectoryDescription
        alert.addButton(withTitle: localizer.confirmDeleteButtonTitle)  // Reuse
        alert.addButton(withTitle: localizer.cancelTitle)

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        Task {
            ignorePath(path)
        }
    }

    func revealInFinder(_ path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyPathToClipboard(_ path: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
    }

    func selectAndShowDiff(for path: String) {
        guard entryByPath[path] != nil else {
            return
        }
        selectedPaths = [path]
        preferredDiffPreviewMode = .workingCopy
        refreshDiffPreview()
    }

    // MARK: - Bookmark Management

    func switchToBookmark(_ bookmark: WorkspaceBookmark) {
        cancelUpdateWorkingCopy(markAsCancelled: true)
        rootPath = bookmark.path
        clearLoadedEntries()
        var updated = bookmarks
        if let index = updated.firstIndex(where: { $0.id == bookmark.id }) {
            updated[index].lastAccessedAt = Date()
        }
        bookmarks = updated
        bookmarkStore.save(bookmarks)
        broadcastCurrentMonitoredRoot()
        requestRefresh(forceFullRefresh: true)
    }

    func addCurrentPathAsBookmark() {
        let trimmed = normalizedRootInput
        guard !trimmed.isEmpty else { return }
        let standardized = URL(fileURLWithPath: trimmed).standardizedFileURL.path
        guard !bookmarks.contains(where: { $0.path == standardized }) else { return }
        let bookmark = WorkspaceBookmark(path: standardized)
        bookmarks.append(bookmark)
        bookmarkStore.save(bookmarks)
        broadcastCurrentMonitoredRoot()
    }

    func addBookmarkFromPicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = localizer.addWorkingCopyMessage
        guard panel.runModal() == .OK, let url = panel.url else { return }
        securityScopedBookmarkStore.saveBookmark(for: url)
        let standardized = url.standardizedFileURL.path
        guard !bookmarks.contains(where: { $0.path == standardized }) else {
            if let existing = bookmarks.first(where: { $0.path == standardized }) {
                switchToBookmark(existing)
            }
            return
        }
        let bookmark = WorkspaceBookmark(path: standardized)
        bookmarks.append(bookmark)
        bookmarkStore.save(bookmarks)
        switchToBookmark(bookmark)
    }

    func removeBookmark(id: UUID) {
        bookmarks.removeAll { $0.id == id }
        bookmarkStore.save(bookmarks)
        broadcastCurrentMonitoredRoot()
    }

    func reorderBookmarks(from source: IndexSet, to destination: Int) {
        bookmarks.move(fromOffsets: source, toOffset: destination)
        bookmarkStore.save(bookmarks)
    }

    func renameBookmark(id: UUID, newName: String) {
        guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        bookmarks[index].displayName = newName.isEmpty ? nil : newName
        bookmarkStore.save(bookmarks)
    }

    // MARK: - New SVN Operations

    func showLogForPath(_ path: String) {
        showHistory()
    }

    func blamePath(_ path: String) {
        blameTargetPath = path
        isBlamePresented = true
        blameLines = []
        blameError = nil
        isLoadingBlame = true
        Task {
            do {
                _ = try await configureServicesIfNeeded()
                let runner = ProcessSubversionRunner()
                let request = SubversionCLIInvocationRequest(
                    executablePath: "svn",
                    arguments: ["blame", "--xml", "--", path],
                    workingDirectory: normalizedRootInput
                )
                let result = try await runner.run(request)
                guard result.exitCode == 0 else {
                    throw WorkbenchError.operationFailed(result.stderr)
                }
                blameLines = BlameXMLParser.parse(result.stdout)
                isLoadingBlame = false
            } catch {
                blameError = localizedErrorMessage(for: error)
                isLoadingBlame = false
            }
        }
    }

    func lockPath(_ path: String) {
        Task {
            do {
                _ = try await configureServicesIfNeeded()
                let runner = ProcessSubversionRunner()
                let request = SubversionCLIInvocationRequest(
                    executablePath: "svn",
                    arguments: ["lock", "--", path],
                    workingDirectory: normalizedRootInput
                )
                let result = try await runner.run(request)
                guard result.exitCode == 0 else {
                    throw WorkbenchError.operationFailed(result.stderr)
                }
                statusNotice = .lockedPath((path as NSString).lastPathComponent)
                lastError = nil
                await enqueueRefresh(forceFullRefresh: true)
            } catch {
                lastError = localizedErrorMessage(for: error)
            }
        }
    }

    func unlockPath(_ path: String) {
        Task {
            do {
                _ = try await configureServicesIfNeeded()
                let runner = ProcessSubversionRunner()
                let request = SubversionCLIInvocationRequest(
                    executablePath: "svn",
                    arguments: ["unlock", "--", path],
                    workingDirectory: normalizedRootInput
                )
                let result = try await runner.run(request)
                guard result.exitCode == 0 else {
                    throw WorkbenchError.operationFailed(result.stderr)
                }
                statusNotice = .unlockedPath((path as NSString).lastPathComponent)
                lastError = nil
                await enqueueRefresh(forceFullRefresh: true)
            } catch {
                lastError = localizedErrorMessage(for: error)
            }
        }
    }

    func renamePath(_ path: String) {
        renameTargetPath = path
        renameNewName = (path as NSString).lastPathComponent
        isRenamePresented = true
    }

    func performRename() {
        guard let sourcePath = renameTargetPath else { return }
        let newName = renameNewName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { return }
        // Reject names that could cause path traversal or option injection
        guard !newName.hasPrefix("-") else {
            lastError = "Name cannot start with '-'"
            return
        }
        guard !newName.contains("..") else {
            lastError = "Name cannot contain '..'"
            return
        }
        guard !newName.contains("/") else {
            lastError = "Name cannot contain '/'"
            return
        }
        let parentDir = (sourcePath as NSString).deletingLastPathComponent
        let destinationPath = (parentDir as NSString).appendingPathComponent(newName)
        // Verify destination stays within the working copy root
        let normalizedDest = URL(fileURLWithPath: destinationPath).standardizedFileURL.path
        let normalizedRoot = normalizedRootInput
        guard normalizedDest.hasPrefix(normalizedRoot + "/") || normalizedDest == normalizedRoot else {
            lastError = "Destination path is outside the working copy"
            return
        }
        isRenamePresented = false

        Task {
            do {
                _ = try await configureServicesIfNeeded()
                let runner = ProcessSubversionRunner()
                let request = SubversionCLIInvocationRequest(
                    executablePath: "svn",
                    arguments: ["move", "--", sourcePath, destinationPath],
                    workingDirectory: normalizedRootInput
                )
                let result = try await runner.run(request)
                guard result.exitCode == 0 else {
                    throw WorkbenchError.operationFailed(result.stderr)
                }
                statusNotice = .renamedPath((sourcePath as NSString).lastPathComponent, newName)
                lastError = nil
                await enqueueRefresh(forceFullRefresh: true)
            } catch {
                lastError = localizedErrorMessage(for: error)
            }
        }
    }

    func createPatchForPath(_ path: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "patch") ?? .data]
        panel.nameFieldStringValue = "\((path as NSString).lastPathComponent).patch"
        guard panel.runModal() == .OK, let outputURL = panel.url else { return }
        securityScopedBookmarkStore.saveBookmark(for: outputURL.deletingLastPathComponent())

        Task {
            do {
                _ = try await configureServicesIfNeeded()
                let runner = ProcessSubversionRunner()
                let request = SubversionCLIInvocationRequest(
                    executablePath: "svn",
                    arguments: ["diff", "--", path],
                    workingDirectory: normalizedRootInput
                )
                let result = try await runner.run(request)
                guard result.exitCode == 0 else {
                    throw WorkbenchError.operationFailed(result.stderr)
                }
                try result.stdout.write(to: outputURL, atomically: true, encoding: .utf8)
                statusNotice = .createdPatch((path as NSString).lastPathComponent)
                lastError = nil
            } catch {
                lastError = localizedErrorMessage(for: error)
            }
        }
    }

    func showPropertiesForPath(_ path: String) {
        propertiesTargetPath = path
        isPropertiesPresented = true
        propertyList = []
        propertiesError = nil
        isLoadingProperties = true
        Task {
            do {
                _ = try await configureServicesIfNeeded()
                let runner = ProcessSubversionRunner()
                let request = SubversionCLIInvocationRequest(
                    executablePath: "svn",
                    arguments: ["proplist", "-v", "--xml", "--", path],
                    workingDirectory: normalizedRootInput
                )
                let result = try await runner.run(request)
                guard result.exitCode == 0 else {
                    throw WorkbenchError.operationFailed(result.stderr)
                }
                propertyList = SVNPropertyXMLParser.parse(result.stdout)
                isLoadingProperties = false
            } catch {
                propertiesError = localizedErrorMessage(for: error)
                isLoadingProperties = false
            }
        }
    }

    func setProperty(path: String, name: String, value: String) {
        Task {
            do {
                _ = try await configureServicesIfNeeded()
                let runner = ProcessSubversionRunner()
                let request = SubversionCLIInvocationRequest(
                    executablePath: "svn",
                    arguments: ["propset", "--", name, value, path],
                    workingDirectory: normalizedRootInput
                )
                let result = try await runner.run(request)
                guard result.exitCode == 0 else {
                    throw WorkbenchError.operationFailed(result.stderr)
                }
                showPropertiesForPath(path)
                await enqueueRefresh(forceFullRefresh: true)
            } catch {
                lastError = localizedErrorMessage(for: error)
            }
        }
    }

    func deleteProperty(path: String, name: String) {
        Task {
            do {
                _ = try await configureServicesIfNeeded()
                let runner = ProcessSubversionRunner()
                let request = SubversionCLIInvocationRequest(
                    executablePath: "svn",
                    arguments: ["propdel", "--", name, path],
                    workingDirectory: normalizedRootInput
                )
                let result = try await runner.run(request)
                guard result.exitCode == 0 else {
                    throw WorkbenchError.operationFailed(result.stderr)
                }
                showPropertiesForPath(path)
                await enqueueRefresh(forceFullRefresh: true)
            } catch {
                lastError = localizedErrorMessage(for: error)
            }
        }
    }

    private var normalizedRootInput: String {
        rootPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentUpdateActivityKey: String? {
        let root = normalizedRootInput
        guard !root.isEmpty else {
            return nil
        }

        return Self.standardizedPath(root)
    }

    private func setUpdateActivity(_ activity: UpdateActivity, for rootPath: String) {
        var activities = updateActivitiesByRoot
        activities[Self.standardizedPath(rootPath)] = activity
        updateActivitiesByRoot = activities
    }

    private func updateActivityStartedAt(for rootPath: String) -> Date {
        updateActivitiesByRoot[Self.standardizedPath(rootPath)]?.startedAt ?? Date()
    }

    private func copyRepositoryURL(_ urlString: String) {
        guard !urlString.isEmpty else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(urlString, forType: .string) else {
            lastError = localizer.repositoryBrowserCopyFailed
            return
        }

        lastError = nil
        statusNotice = .copiedRepositoryLocation
    }

    private func openRepositoryURLInBrowser(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            lastError = localizer.repositoryBrowserOpenFailed
            return
        }

        guard NSWorkspace.shared.open(url) else {
            lastError = localizer.repositoryBrowserOpenFailed
            return
        }

        lastError = nil
        statusNotice = .openedRepositoryLocation
    }

    private func requestRefresh(forceFullRefresh: Bool) {
        if isRefreshing {
            hasQueuedRefresh = true
            queuedRefreshNeedsFullRescan = queuedRefreshNeedsFullRescan || forceFullRefresh
            diagnosticLog(
                "performRefresh queued root=\(normalizedRootInput) forceFullRefresh=\(forceFullRefresh) " +
                "queuedForceFullRefresh=\(queuedRefreshNeedsFullRescan)"
            )
            return
        }

        if isRefreshScheduled {
            scheduledRefreshNeedsFullRescan = scheduledRefreshNeedsFullRescan || forceFullRefresh
            diagnosticLog(
                "performRefresh merged scheduled request root=\(normalizedRootInput) forceFullRefresh=\(forceFullRefresh) " +
                "scheduledForceFullRefresh=\(scheduledRefreshNeedsFullRescan)"
            )
            return
        }

        isRefreshScheduled = true
        scheduledRefreshNeedsFullRescan = forceFullRefresh
        Task { [weak self] in
            await self?.runScheduledRefresh()
        }
    }

    private func runScheduledRefresh() async {
        let forceFullRefresh = scheduledRefreshNeedsFullRescan
        scheduledRefreshNeedsFullRescan = false
        isRefreshScheduled = false
        await enqueueRefresh(forceFullRefresh: forceFullRefresh)
    }

    private func enqueueRefresh(forceFullRefresh: Bool) async {
        if isRefreshing {
            hasQueuedRefresh = true
            queuedRefreshNeedsFullRescan = queuedRefreshNeedsFullRescan || forceFullRefresh
            diagnosticLog(
                "performRefresh queued root=\(normalizedRootInput) forceFullRefresh=\(forceFullRefresh) " +
                "queuedForceFullRefresh=\(queuedRefreshNeedsFullRescan)"
            )
            return
        }

        await performRefresh(forceFullRefresh: forceFullRefresh)
    }

    private func performRefresh(forceFullRefresh: Bool) async {
        let requestedRootInput = normalizedRootInput
        guard !requestedRootInput.isEmpty else {
            lastError = localizer.selectWorkingCopyFirstError
            statusNotice = .noWorkingCopySelected
            diagnosticLog("performRefresh skipped: empty root")
            return
        }

        isRefreshing = true
        lastError = nil
        var shouldPerformFinderUpdateAfterRefresh = false
        diagnosticLog(
            "performRefresh start root=\(normalizedRootInput) forceFullRefresh=\(forceFullRefresh) " +
            "pendingCommand=\(pendingWorkbenchCommand?.command.rawValue ?? "nil")"
        )
        defer {
            let shouldRunQueuedRefresh = hasQueuedRefresh
            let queuedForceFullRefresh = queuedRefreshNeedsFullRescan
            hasQueuedRefresh = false
            queuedRefreshNeedsFullRescan = false
            isRefreshing = false

            if shouldPerformFinderUpdateAfterRefresh {
                diagnosticLog("performRefresh launching deferred Finder update root=\(normalizedRootInput)")
                Task { [weak self] in
                    await self?.performUpdateWorkingCopy()
                }
            } else if shouldRunQueuedRefresh {
                diagnosticLog(
                    "performRefresh draining queued refresh root=\(normalizedRootInput) " +
                    "forceFullRefresh=\(queuedForceFullRefresh)"
                )
                requestRefresh(forceFullRefresh: queuedForceFullRefresh)
            }
        }

        do {
            let root = try await configureServicesIfNeeded()
            guard let client else {
                throw WorkbenchError.notConfigured
            }

            let snapshot = try await withTimeout(seconds: 12) {
                try await self.refreshSnapshotFromService(
                    rootPath: root,
                    forceFullRefresh: forceFullRefresh
                )
            }

            let workingCopyItems = try await withTimeout(seconds: 12) {
                try await client.status(
                    at: root,
                    options: .commitSheet,
                    context: .foreground
                )
            }
            let mergedWorkingCopyItems = workbenchStatusItems(
                from: workingCopyItems,
                snapshot: snapshot,
                rootPath: root
            )

            guard isCurrentRoot(root) else {
                diagnosticLog("performRefresh discarded stale status root=\(root) current=\(normalizedRootInput)")
                requestRefresh(forceFullRefresh: forceFullRefresh)
                return
            }

            badgeEntryCount = snapshot.entries.count
            let freshEntries = workbenchEntries(from: mergedWorkingCopyItems, rootPath: root)
            applyLoadedEntries(freshEntries, rootPath: root)
            let appliedCommand = pendingWorkbenchCommand
            selectedPaths = selectionForFreshEntries(freshEntries, rootPath: root)
            refreshDiffPreview()
            lastRefreshDate = snapshot.generatedAt
            if let appliedCommand {
                statusNotice = finderReadyNotice(
                    for: appliedCommand,
                    selectedCount: selectedPaths.count
                )
                shouldPerformFinderUpdateAfterRefresh = appliedCommand.command == .updateWorkingCopy
            } else {
                statusNotice = .loadedEntries(
                    entryCount: entries.count,
                    badgeCount: badgeEntryCount
                )
            }
            diagnosticLog(
                "performRefresh completed root=\(root) items=\(mergedWorkingCopyItems.count) " +
                "entries=\(entries.count) badges=\(badgeEntryCount) selected=\(selectedPaths.count) " +
                "appliedCommand=\(appliedCommand?.command.rawValue ?? "nil")"
            )

            Task { [weak self] in
                await self?.refreshRepositoryInsightsIfCurrent(rootPath: root)
            }
        } catch {
            lastError = localizedErrorMessage(for: error)
            statusNotice = .refreshFailed
            diagnosticLog("performRefresh failed error=\(error.localizedDescription)")
        }
    }

    private func performToggleMonitoring() async {
        guard !normalizedRootInput.isEmpty else {
            lastError = localizer.chooseBeforeWatcherError
            return
        }

        do {
            let root = try await configureServicesIfNeeded()

            if isMonitoring {
                try await stopMonitoring(rootPath: root)
                isMonitoring = false
                statusNotice = .watcherStopped
            } else {
                try await startMonitoring(rootPath: root)
                isMonitoring = true
                statusNotice = .watcherStarted
                await enqueueRefresh(forceFullRefresh: false)
            }
        } catch {
            lastError = localizedErrorMessage(for: error)
            statusNotice = .watcherUpdateFailed
        }
    }

    private func performAddSelected() async {
        guard !isBusy else {
            return
        }

        do {
            _ = try await configureServicesIfNeeded()
            guard let client else {
                throw WorkbenchError.notConfigured
            }

            guard let confirmation = confirmAddPreview(for: selectedEntries) else {
                return
            }
            guard !confirmation.paths.isEmpty else {
                lastError = localizer.selectUnversionedToAddError
                return
            }

            isRunningWorkspaceOperation = true
            defer { isRunningWorkspaceOperation = false }
            try await client.add(
                paths: confirmation.paths,
                depth: confirmation.depth,
                force: false,
                context: .foreground
            )
            statusNotice = .addedPaths(confirmation.paths.count)
            lastError = nil
            await enqueueRefresh(forceFullRefresh: true)
        } catch {
            lastError = localizedErrorMessage(for: error)
            statusNotice = .addFailed
        }
    }

    private func performShelveSelected() async {
        guard !isBusy else {
            return
        }

        let paths = collapsedPaths(selectedEntries.filter { $0.canCommit || $0.canRevert }.map(\.id))
        guard !paths.isEmpty else {
            lastError = localizer.selectModifiedToCommitError
            return
        }
        guard let name = promptShelfName(
            title: localizer.shelveNameTitle,
            message: localizer.shelveNamePrompt,
            actionTitle: localizer.shelveConfirmButton,
            defaultName: defaultShelfName()
        ) else {
            return
        }

        do {
            _ = try await configureServicesIfNeeded()
            guard let client else {
                throw WorkbenchError.notConfigured
            }

            isRunningWorkspaceOperation = true
            defer { isRunningWorkspaceOperation = false }
            try await client.shelve(paths: paths, name: name, context: .foreground)
            lastError = nil
            statusNotice = .shelvedPaths(pathCount: paths.count, name: name)
            await enqueueRefresh(forceFullRefresh: true)
        } catch {
            lastError = localizedErrorMessage(for: error)
            statusNotice = .shelveFailed
        }
    }

    private func performUnshelveNamedShelf() async {
        guard !isBusy else {
            return
        }
        guard let name = promptShelfName(
            title: localizer.unshelveSelected,
            message: localizer.unshelveNamePrompt,
            actionTitle: localizer.unshelveConfirmButton,
            defaultName: "shelf"
        ) else {
            return
        }

        do {
            _ = try await configureServicesIfNeeded()
            guard let client else {
                throw WorkbenchError.notConfigured
            }

            isRunningWorkspaceOperation = true
            defer { isRunningWorkspaceOperation = false }
            try await client.unshelve(name: name, context: .foreground)
            lastError = nil
            statusNotice = .unshelved(name)
            await enqueueRefresh(forceFullRefresh: true)
        } catch {
            lastError = localizedErrorMessage(for: error)
            statusNotice = .unshelveFailed
        }
    }

    private func performCheckoutWorkingCopy(repositoryURL: String, destinationPath: String) async {
        let repositoryURL = repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let destinationPath = Self.standardizedPath(destinationPath.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !isBusy, !repositoryURL.isEmpty, !destinationPath.isEmpty else {
            return
        }

        isRunningWorkspaceOperation = true
        statusNotice = .checkingOutWorkingCopy
        defer { isRunningWorkspaceOperation = false }

        do {
            let checkoutOperator = SubversionWorkspaceOperator()
            let result = try await checkoutOperator.checkout(
                repositoryURL: repositoryURL,
                destinationPath: destinationPath,
                context: .foreground
            )
            securityScopedBookmarkStore.saveBookmark(for: URL(fileURLWithPath: destinationPath))
            rootPath = destinationPath
            lastError = nil
            statusNotice = .checkedOutWorkingCopy(path: destinationPath, revision: result.revision)
            await enqueueRefresh(forceFullRefresh: true)
        } catch {
            lastError = localizedErrorMessage(for: error)
            statusNotice = .checkoutFailed
        }
    }

    private func performImportToRepository(sourcePath: String, repositoryURL: String, message: String) async {
        let sourcePath = Self.standardizedPath(sourcePath.trimmingCharacters(in: .whitespacesAndNewlines))
        let repositoryURL = repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isBusy, !sourcePath.isEmpty, !repositoryURL.isEmpty, !message.isEmpty else {
            return
        }

        isRunningWorkspaceOperation = true
        statusNotice = .importingPath
        defer { isRunningWorkspaceOperation = false }

        do {
            let importOperator = SubversionWorkspaceOperator()
            let result = try await importOperator.importPath(
                sourcePath: sourcePath,
                repositoryURL: repositoryURL,
                message: message,
                context: .foreground
            )
            lastError = nil
            statusNotice = .importedPath(revision: result.revision)
        } catch {
            lastError = localizedErrorMessage(for: error)
            statusNotice = .importFailed
        }
    }

    private func performExportWorkingCopy(source: String, destinationPath: String) async {
        let source = Self.standardizedPath(source.trimmingCharacters(in: .whitespacesAndNewlines))
        let destinationPath = Self.standardizedPath(destinationPath.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !isBusy, !source.isEmpty, !destinationPath.isEmpty else {
            return
        }

        isRunningWorkspaceOperation = true
        statusNotice = .exportingWorkingCopy
        defer { isRunningWorkspaceOperation = false }

        do {
            let exportOperator = SubversionWorkspaceOperator()
            let result = try await exportOperator.export(
                source: source,
                destinationPath: destinationPath,
                context: .foreground
            )
            securityScopedBookmarkStore.saveBookmark(for: URL(fileURLWithPath: destinationPath).deletingLastPathComponent())
            lastError = nil
            statusNotice = .exportedWorkingCopy(path: result.destinationPath)
        } catch {
            lastError = localizedErrorMessage(for: error)
            statusNotice = .exportFailed
        }
    }

    private func performSwitchWorkingCopy(repositoryURL: String) async {
        let repositoryURL = repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isBusy, !repositoryURL.isEmpty else {
            return
        }

        isRunningWorkspaceOperation = true
        statusNotice = .switchingWorkingCopy
        defer { isRunningWorkspaceOperation = false }

        do {
            let root = try await configureServicesIfNeeded()
            guard let workspaceOperator else {
                throw WorkbenchError.notConfigured
            }
            let result = try await workspaceOperator.switchWorkingCopy(
                workingCopyPath: root,
                repositoryURL: repositoryURL,
                context: .foreground
            )
            lastError = nil
            statusNotice = .switchedWorkingCopy(revision: result.revision)
            await enqueueRefresh(forceFullRefresh: true)
        } catch {
            lastError = localizedErrorMessage(for: error)
            statusNotice = .switchFailed
        }
    }

    private func performRelocateWorkingCopy(fromURL: String, toURL: String) async {
        let fromURL = fromURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let toURL = toURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isBusy, !fromURL.isEmpty, !toURL.isEmpty else {
            return
        }

        isRunningWorkspaceOperation = true
        statusNotice = .relocatingWorkingCopy
        defer { isRunningWorkspaceOperation = false }

        do {
            let root = try await configureServicesIfNeeded()
            guard let workspaceOperator else {
                throw WorkbenchError.notConfigured
            }
            _ = try await workspaceOperator.relocate(
                workingCopyPath: root,
                fromURL: fromURL,
                toURL: toURL,
                context: .foreground
            )
            lastError = nil
            statusNotice = .relocatedWorkingCopy
            await enqueueRefresh(forceFullRefresh: true)
        } catch {
            lastError = localizedErrorMessage(for: error)
            statusNotice = .relocateFailed
        }
    }

    private func promptShelfName(
        title: String,
        message: String,
        actionTitle: String,
        defaultName: String
    ) -> String? {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: actionTitle)
        alert.addButton(withTitle: localizer.addPreviewCancelButton)

        let textField = NSTextField(string: defaultName)
        textField.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = textField

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }
        let name = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private struct SVNCredentialPromptResult {
        var username: String
        var password: String
    }

    private func promptSVNCredentials(
        repositoryURL: String
    ) async -> SVNCredentialPromptResult? {
        let defaultUsername = MacSVNSVNConfigManager.importedUsername(
            matchingRepositoryURL: repositoryURL
        ) ?? ""

        guard
            let values = await promptTextValuesAsync(
                title: localizer.svnAuthenticationTitle,
                informativeText: localizer.svnAuthenticationMessage(repositoryURL: repositoryURL),
                fields: [
                    TextPromptField(label: localizer.svnUsernamePrompt, value: defaultUsername),
                    TextPromptField(label: localizer.svnPasswordPrompt, isSecure: true),
                ]
            )
        else {
            return nil
        }

        return SVNCredentialPromptResult(username: values[0], password: values[1])
    }

    private func resolveRepositoryURL(rootPath: String, fallback: String) async -> String {
        if let url = repositorySummary?.repositoryURL ?? repositorySummary?.repositoryRootURL,
           !url.isEmpty
        {
            return url
        }

        if let url = try? await macSVNWorkingCopyRepositoryURL(workingCopyPath: rootPath) {
            return url
        }

        return fallback
    }

    private func ensureSVNCredentials(
        repositoryURL: String,
        workingCopyPath: String
    ) async -> Bool {
        if MacSVNSVNConfigManager.hasStoredCredentials(matchingRepositoryURL: repositoryURL) {
            return true
        }

        guard let credentials = await promptSVNCredentials(repositoryURL: repositoryURL) else {
            lastError = localizer.svnAuthenticationCancelled
            return false
        }

        do {
            try await macSVNStoreCredentials(
                username: credentials.username,
                password: credentials.password,
                workingCopyPath: workingCopyPath
            )
            return true
        } catch {
            lastError = localizedErrorMessage(for: error)
            return false
        }
    }

    private func promptTextValuesAsync(
        title: String,
        informativeText: String? = nil,
        fields: [TextPromptField]
    ) async -> [String]? {
        await MainActor.run {
            promptTextValues(
                title: title,
                informativeText: informativeText,
                fields: fields
            )
        }
    }

    private func promptTextValues(
        title: String,
        informativeText: String? = nil,
        fields: [TextPromptField]
    ) -> [String]? {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        if let informativeText {
            alert.informativeText = informativeText
        }
        alert.addButton(withTitle: localizer.runButtonTitle)
        alert.addButton(withTitle: localizer.cancelTitle)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let textFields = fields.map { field in
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8

            let label = NSTextField(labelWithString: field.label)
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.widthAnchor.constraint(equalToConstant: 132).isActive = true

            let textField: NSTextField
            if field.isSecure {
                textField = NSSecureTextField(string: field.value)
            } else {
                textField = NSTextField(string: field.value)
            }
            textField.font = .systemFont(ofSize: 12)
            textField.widthAnchor.constraint(equalToConstant: 360).isActive = true

            row.addArrangedSubview(label)
            row.addArrangedSubview(textField)
            stack.addArrangedSubview(row)
            return textField
        }

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: max(34, fields.count * 34)))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),
        ])
        alert.accessoryView = container

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }

        let values = textFields.map { $0.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard values.allSatisfy({ !$0.isEmpty }) else {
            lastError = localizer.invalidWorkingCopyRoot
            return nil
        }

        return values
    }

    private func defaultShelfName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "shelf-\(formatter.string(from: Date()))"
    }

    private func confirmAddPreview(for candidates: [Entry]) -> AddPreviewConfirmation? {
        let addableEntries = candidates.filter(\.canAdd)
        let skippedEntries = candidates.filter { !$0.canAdd }
        let directoryEntries = addableEntries.filter(\.isDirectory)
        let addablePaths = addableEntries.map(\.id).sorted()
        guard !addablePaths.isEmpty else {
            return nil
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = localizer.addPreviewTitle
        alert.informativeText = localizer.addPreviewMessage(
            addableCount: addableEntries.count,
            skippedCount: skippedEntries.count,
            directoryCount: directoryEntries.count
        )
        alert.addButton(withTitle: localizer.addPreviewConfirmButton)
        alert.addButton(withTitle: localizer.addPreviewCancelButton)

        let depthPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        let depths: [SVNDepth] = [.empty, .files, .immediates, .infinity]
        for depth in depths {
            depthPopup.addItem(withTitle: localizer.svnDepthTitle(depth))
        }
        depthPopup.selectItem(at: 1)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let depthRow = NSStackView()
        depthRow.orientation = .horizontal
        depthRow.alignment = .centerY
        depthRow.spacing = 8
        depthRow.addArrangedSubview(Self.dialogLabel(localizer.addPreviewDepthTitle))
        depthRow.addArrangedSubview(depthPopup)
        stack.addArrangedSubview(depthRow)

        stack.addArrangedSubview(Self.dialogLabel(
            previewSectionText(title: localizer.addPreviewAddableTitle, entries: addableEntries)
        ))
        if !directoryEntries.isEmpty {
            stack.addArrangedSubview(Self.dialogLabel(
                previewSectionText(title: localizer.addPreviewDirectoriesTitle, entries: directoryEntries)
            ))
        }
        if !skippedEntries.isEmpty {
            stack.addArrangedSubview(Self.dialogLabel(
                previewSectionText(title: localizer.addPreviewSkippedTitle, entries: skippedEntries)
            ))
        }

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 1))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            depthPopup.widthAnchor.constraint(equalToConstant: 160),
        ])
        alert.accessoryView = container

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }

        let selectedDepth = depths[max(0, min(depthPopup.indexOfSelectedItem, depths.count - 1))]
        return AddPreviewConfirmation(paths: addablePaths, depth: selectedDepth)
    }

    private func previewSectionText(title: String, entries: [Entry]) -> String {
        let visible = entries.prefix(10).map { "• \($0.relativePath)" }
        let extraCount = max(0, entries.count - visible.count)
        let suffix = extraCount > 0 ? "\n… +\(extraCount)" : ""
        return ([title] + visible).joined(separator: "\n") + suffix
    }

    private static func dialogLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 12
        return label
    }

    private func performUpdateWorkingCopy() async {
        guard !isBusy else {
            return
        }

        let requestedRoot = normalizedRootInput
        guard !requestedRoot.isEmpty else {
            lastError = localizer.selectWorkingCopyFirstError
            statusNotice = .noWorkingCopySelected
            return
        }

        let configuredRoot: String
        do {
            configuredRoot = try await configureServicesIfNeeded()
        } catch {
            lastError = localizedErrorMessage(for: error)
            statusNotice = .updateFailed
            return
        }

        let repositoryURL = await resolveRepositoryURL(
            rootPath: configuredRoot,
            fallback: requestedRoot
        )
        guard await ensureSVNCredentials(
            repositoryURL: repositoryURL,
            workingCopyPath: configuredRoot
        ) else {
            statusNotice = .updateFailed
            return
        }

        isRunningWorkspaceOperation = true
        statusNotice = .updatingWorkingCopy
        setUpdateActivity(
            UpdateActivity(
                state: .running,
                rootPath: Self.standardizedPath(requestedRoot),
                displayPaths: [],
                revision: nil,
                hasConflicts: false,
                startedAt: Date(),
                completedAt: nil,
                rawOutput: ""
            ),
            for: requestedRoot
        )
        defer {
            isRunningWorkspaceOperation = false
            updateWorkingCopyTask = nil
        }

        var shouldRetryAfterAuthentication = true
        while !Task.isCancelled {
            do {
                let root = try await configureServicesIfNeeded()
                guard let workspaceOperator else {
                    throw WorkbenchError.notConfigured
                }

                let result = try await withTimeout(seconds: 90) {
                    try await workspaceOperator.update(
                        rootPath: root,
                        context: .foreground
                    )
                }
                try Task.checkCancellation()
                lastError = nil
                statusNotice = .updatedWorkingCopy(
                    pathCount: result.updatedPaths.count,
                    revision: result.resultingRevision,
                    hasConflicts: result.hasConflicts
                )
                setUpdateActivity(
                    UpdateActivity(
                        state: .completed,
                        rootPath: root,
                        displayPaths: displayPathsForUpdate(result.updatedPaths, rootPath: root),
                        revision: result.resultingRevision,
                        hasConflicts: result.hasConflicts,
                        startedAt: updateActivityStartedAt(for: root),
                        completedAt: Date(),
                        rawOutput: result.rawOutput
                    ),
                    for: root
                )
                await enqueueRefresh(forceFullRefresh: true)
                return
            } catch is CancellationError {
                lastError = localizer.updateCancelled
                statusNotice = .updateFailed
                setUpdateActivity(
                    UpdateActivity(
                        state: .failed(localizer.updateCancelled),
                        rootPath: Self.standardizedPath(requestedRoot),
                        displayPaths: [],
                        revision: nil,
                        hasConflicts: false,
                        startedAt: updateActivityStartedAt(for: requestedRoot),
                        completedAt: Date(),
                        rawOutput: ""
                    ),
                    for: requestedRoot
                )
                return
            } catch {
                if let workbenchError = error as? WorkbenchError,
                   case .operationFailed(let message) = workbenchError,
                   message.contains("超时") || message.lowercased().contains("timeout")
                {
                    lastError = localizer.updateTimedOut
                    statusNotice = .updateFailed
                    setUpdateActivity(
                        UpdateActivity(
                            state: .failed(localizer.updateTimedOut),
                            rootPath: Self.standardizedPath(requestedRoot),
                            displayPaths: [],
                            revision: nil,
                            hasConflicts: false,
                            startedAt: updateActivityStartedAt(for: requestedRoot),
                            completedAt: Date(),
                            rawOutput: ""
                        ),
                        for: requestedRoot
                    )
                    return
                }

                if shouldRetryAfterAuthentication,
                   macSVNIsAuthenticationError(error),
                   let credentials = await promptSVNCredentials(
                       repositoryURL: repositorySummary?.repositoryURL
                           ?? repositorySummary?.repositoryRootURL
                           ?? requestedRoot
                   )
                {
                    shouldRetryAfterAuthentication = false
                    do {
                        let root = try await configureServicesIfNeeded()
                        try await macSVNStoreCredentials(
                            username: credentials.username,
                            password: credentials.password,
                            workingCopyPath: root
                        )
                        continue
                    } catch {
                        lastError = localizedErrorMessage(for: error)
                    }
                } else {
                    lastError = localizedErrorMessage(for: error)
                }

                statusNotice = .updateFailed
                setUpdateActivity(
                    UpdateActivity(
                        state: .failed(lastError ?? localizer.updateFailed),
                        rootPath: Self.standardizedPath(requestedRoot),
                        displayPaths: [],
                        revision: nil,
                        hasConflicts: false,
                        startedAt: updateActivityStartedAt(for: requestedRoot),
                        completedAt: Date(),
                        rawOutput: ""
                    ),
                    for: requestedRoot
                )
                return
            }
        }
    }

    private func performCleanupWorkingCopy() async {
        guard !isBusy else {
            return
        }

        isRunningWorkspaceOperation = true
        statusNotice = .cleaningWorkingCopy
        defer { isRunningWorkspaceOperation = false }

        do {
            let root = try await configureServicesIfNeeded()
            guard let workspaceOperator else {
                throw WorkbenchError.notConfigured
            }

            _ = try await workspaceOperator.cleanup(
                rootPath: root,
                context: .foreground
            )
            lastError = nil
            statusNotice = .cleanedWorkingCopy
            await enqueueRefresh(forceFullRefresh: true)
        } catch {
            lastError = localizedErrorMessage(for: error)
            statusNotice = .cleanupFailed
        }
    }

    private func performRevertSelected(paths: [String]) async {
        guard !isBusy else {
            return
        }

        isRunningWorkspaceOperation = true
        statusNotice = .revertingPaths(pathCount: paths.count)
        defer { isRunningWorkspaceOperation = false }

        do {
            _ = try await configureServicesIfNeeded()
            guard let workspaceOperator else {
                throw WorkbenchError.notConfigured
            }

            let result = try await workspaceOperator.revert(
                paths: paths,
                context: .foreground
            )
            lastError = nil
            statusNotice = .revertedPaths(result.revertedPaths.count)
            await enqueueRefresh(forceFullRefresh: true)
        } catch {
            lastError = localizedErrorMessage(for: error)
            statusNotice = .revertFailed
        }
    }

    private func performResolveSelected(paths: [String]) async {
        guard !isBusy else {
            return
        }

        isRunningWorkspaceOperation = true
        statusNotice = .resolvingPaths(pathCount: paths.count)
        defer { isRunningWorkspaceOperation = false }

        do {
            _ = try await configureServicesIfNeeded()
            guard let workspaceOperator else {
                throw WorkbenchError.notConfigured
            }

            let result = try await workspaceOperator.resolve(
                paths: paths,
                accept: "working",
                context: .foreground
            )
            lastError = nil
            statusNotice = .resolvedPaths(result.resolvedPaths.count)
            await enqueueRefresh(forceFullRefresh: true)
        } catch {
            lastError = localizedErrorMessage(for: error)
            statusNotice = .resolveFailed
        }
    }

    private func performCommitSelected() async {
        guard !isBusy else {
            return
        }

        do {
            _ = try await configureServicesIfNeeded()
            guard let client else {
                throw WorkbenchError.notConfigured
            }

            let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else {
                lastError = localizer.emptyCommitMessageError
                return
            }

            let candidates = selectedEntries
                .filter(\.canCommit)
                .map {
                    CommitCandidate(
                        path: $0.id,
                        status: $0.status,
                        isExplicitlySelected: true
                    )
                }

            guard !candidates.isEmpty else {
                lastError = localizer.selectModifiedToCommitError
                return
            }

            isRunningWorkspaceOperation = true
            defer { isRunningWorkspaceOperation = false }

            let revision = try await client.commit(
                candidates: candidates,
                message: message,
                context: .foreground
            )
            commitMessage = ""
            lastError = nil
            statusNotice = .committedPaths(
                pathCount: candidates.count,
                revision: revision
            )
            if refreshStatusAfterCommit {
                await enqueueRefresh(forceFullRefresh: true)
            }
        } catch {
            lastError = localizedErrorMessage(for: error)
            statusNotice = .commitFailed
        }
    }

    private func configureServicesIfNeeded() async throws -> String {
        let rawRoot = normalizedRootInput
        guard !rawRoot.isEmpty else {
            throw WorkbenchError.invalidWorkingCopyRoot
        }
        let root = URL(fileURLWithPath: rawRoot).standardizedFileURL.path
        updateSecurityScopedRootAccess(for: root)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root, isDirectory: &isDirectory) else {
            throw WorkbenchError.workingCopyPathNotFound(root)
        }
        guard isDirectory.boolValue else {
            throw WorkbenchError.workingCopyPathIsNotDirectory(root)
        }

        if
            configuredRootPath == root,
            client != nil,
            repositoryInspector != nil,
            diffInspector != nil,
            (host != nil || xpcClient != nil)
        {
            return root
        }

        if isMonitoring, let configuredRootPath, configuredRootPath != root {
            try? await stopMonitoring(rootPath: configuredRootPath)
            isMonitoring = false
        }

        let defaultConfiguration = runtimePaths.statusServiceConfiguration(repositoryRoot: root)
        let statusCenterConfiguration = StatusCenterConfiguration(
            fullRefreshDebounceSeconds: defaultConfiguration.statusCenterConfiguration.fullRefreshDebounceSeconds,
            changedPathBatchSize: maxIncrementalDirtyPaths,
            badgeEntryLimit: badgeEntryLimit,
            maxConcurrentRoots: maxConcurrentOperations
        )
        let clientConfiguration = SVNClientConfiguration(
            preferredBackend: backendMode.svnBackendKind,
            preserveModificationTimes: preserveModificationTimes,
            maxConcurrentOperations: maxConcurrentOperations,
            enableLargeWorkingCopyOptimizations: true
        )
        let baseConfiguration = StatusServiceConfiguration(
            repositoryRoot: root,
            databaseURL: defaultConfiguration.databaseURL,
            maxIncrementalDirtyPaths: maxIncrementalDirtyPaths,
            bridgeConfiguration: defaultConfiguration.bridgeConfiguration,
            clientConfiguration: clientConfiguration,
            statusCenterConfiguration: statusCenterConfiguration
        )

        // Prefer the in-process host in the main app: it already has user-selected
        // file access and avoids brittle XPC helper communication during refresh.
        host = try StatusServiceHost(
            configuration: baseConfiguration
        )
        xpcClient = runtimePaths.hasBundledStatusService ? StatusServiceXPCClient() : nil
        client = RustCommandBridgeSVNClient(
            configuration: baseConfiguration.clientConfiguration,
            bridgeConfiguration: runtimePaths.bridgeConfiguration
        )
        workspaceOperator = SubversionWorkspaceOperator()
        repositoryInspector = SubversionRepositoryInspector()
        diffInspector = SubversionDiffInspector()
        broadcastCurrentMonitoredRoot()
        configuredRootPath = root
        badgeEntryCount = 0
        clearLoadedEntries()
        return root
    }

    private func refreshSnapshotFromService(
        rootPath: String,
        forceFullRefresh: Bool
    ) async throws -> BadgeSnapshot {
        if let host {
            if forceFullRefresh {
                return try await host.refresh(rootPath: rootPath, forceFullRefresh: true)
            }
            return try await host.refreshIfNeeded(rootPath: rootPath)
        }

        guard let xpcClient else {
            throw WorkbenchError.notConfigured
        }

        return try await xpcClient.refresh(
            rootPath: rootPath,
            forceFullRefresh: forceFullRefresh
        )
    }

    private func startMonitoring(rootPath: String) async throws {
        if let host {
            try await host.startMonitoring(rootPath: rootPath)
            return
        }

        guard let xpcClient else {
            throw WorkbenchError.notConfigured
        }
        try await xpcClient.startMonitoring(rootPath: rootPath)
    }

    private func stopMonitoring(rootPath: String) async throws {
        if let host {
            try await host.stopMonitoring(rootPath: rootPath)
            return
        }

        guard let xpcClient else {
            throw WorkbenchError.notConfigured
        }
        try await xpcClient.stopMonitoring(rootPath: rootPath)
    }

    private func localizedErrorMessage(for error: Error) -> String {
        if let workbenchError = error as? WorkbenchError {
            return workbenchError.localizedText(using: localizer)
        }

        return error.localizedDescription
    }

    private nonisolated func withTimeout<T: Sendable>(
        seconds: UInt64,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw WorkbenchError.operationFailed("操作超时，请稍后重试。")
            }

            guard let result = try await group.next() else {
                throw WorkbenchError.operationFailed("操作超时，请稍后重试。")
            }
            group.cancelAll()
            return result
        }
    }

    private func refreshRepositoryInsightsIfCurrent(rootPath: String) async {
        guard isCurrentRoot(rootPath) else {
            diagnosticLog("refreshRepositoryInsights skipped stale root=\(rootPath) current=\(normalizedRootInput)")
            return
        }

        await refreshRepositoryInsights(rootPath: rootPath)
    }

    private func refreshRepositoryInsights(rootPath: String) async {
        guard let repositoryInspector else {
            repositorySummary = nil
            repositoryBrowserListing = nil
            repositoryBrowserRootURL = nil
            repositoryBrowserWorkingCopyURL = nil
            isLoadingRepositoryBrowser = false
            repositoryBrowserError = nil
            clearRepositoryBrowserFilePreview()
            recentHistory = []
            recentHistoryError = nil
            isLoadingRecentHistory = false
            selectedHistoryRevision = nil
            selectedHistoryEntryDetail = nil
            isLoadingHistoryDetail = false
            return
        }

        do {
            let summary = try await repositoryInspector.summary(
                at: rootPath,
                context: .foreground
            )
            repositorySummary = summary
            repositoryBrowserRootURL = summary.repositoryRootURL ?? summary.repositoryURL
            repositoryBrowserWorkingCopyURL = summary.repositoryURL

            let preferredBrowserURL = preferredRepositoryBrowserURL(
                summary: summary,
                currentListingURL: repositoryBrowserListing?.baseURL
            )
            await loadRepositoryBrowserListing(
                url: preferredBrowserURL,
                using: repositoryInspector
            )
        } catch {
            diagnosticLog("refreshRepositoryInsights summary failed error=\(error.localizedDescription)")
            repositorySummary = nil
            repositoryBrowserListing = nil
            repositoryBrowserRootURL = nil
            repositoryBrowserWorkingCopyURL = nil
            isLoadingRepositoryBrowser = false
            repositoryBrowserError = localizedErrorMessage(for: error)
            clearRepositoryBrowserFilePreview()
            recentHistory = []
            recentHistoryError = nil
            isLoadingRecentHistory = false
            selectedHistoryRevision = nil
            selectedHistoryEntryDetail = nil
            isLoadingHistoryDetail = false
            return
        }

        isLoadingRecentHistory = true
        do {
            diagnosticLog("refreshRepositoryInsights history request rootPath=\(rootPath)")
            let history = try await repositoryInspector.recentHistory(
                at: rootPath,
                limit: 8,
                context: .foreground
            )
            diagnosticLog(
                "refreshRepositoryInsights history loaded rootPath=\(rootPath) revisions=\(history.map { $0.revision })"
            )
            recentHistory = history
            recentHistoryError = nil
            isLoadingRecentHistory = false

            guard !history.isEmpty else {
                selectedHistoryRevision = nil
                selectedHistoryEntryDetail = nil
                isLoadingHistoryDetail = false
                return
            }

            let preferredRevision = history.contains { $0.revision == selectedHistoryRevision }
                ? selectedHistoryRevision
                : history.first?.revision

            if let preferredRevision {
                beginHistoryDetailRequest(for: preferredRevision, preferDiffPreview: false)
                await loadHistoryDetail(for: preferredRevision)
            }
        } catch {
            diagnosticLog("refreshRepositoryInsights history failed error=\(error.localizedDescription)")
            recentHistory = []
            recentHistoryError = localizedErrorMessage(for: error)
            isLoadingRecentHistory = false
            selectedHistoryRevision = nil
            selectedHistoryEntryDetail = nil
            isLoadingHistoryDetail = false
        }
    }

    private func performRefreshRecentHistory() async {
        guard isRecentHistoryRequestRunning else {
            return
        }

        do {
            let root = try await configureServicesIfNeeded()
            guard let repositoryInspector else {
                throw WorkbenchError.notConfigured
            }

            isLoadingRecentHistory = true
            recentHistoryError = nil
            diagnosticLog("refreshRecentHistory request rootPath=\(root)")
            let history = try await repositoryInspector.recentHistory(
                at: root,
                limit: 8,
                context: .foreground
            )
            diagnosticLog(
                "refreshRecentHistory loaded rootPath=\(root) revisions=\(history.map { $0.revision })"
            )
            recentHistory = history
            isLoadingRecentHistory = false
            isRecentHistoryRequestRunning = false

            guard !history.isEmpty else {
                selectedHistoryRevision = nil
                selectedHistoryEntryDetail = nil
                isLoadingHistoryDetail = false
                return
            }

            let preferredRevision = history.contains { $0.revision == selectedHistoryRevision }
                ? selectedHistoryRevision
                : history.first?.revision

            if let preferredRevision {
                beginHistoryDetailRequest(for: preferredRevision, preferDiffPreview: false)
                await loadHistoryDetail(for: preferredRevision)
            }
        } catch {
            diagnosticLog("refreshRecentHistory failed error=\(error.localizedDescription)")
            recentHistory = []
            recentHistoryError = localizedErrorMessage(for: error)
            isLoadingRecentHistory = false
            isRecentHistoryRequestRunning = false
            selectedHistoryRevision = nil
            selectedHistoryEntryDetail = nil
            isLoadingHistoryDetail = false
        }
    }

    private func preferredRepositoryBrowserURL(
        summary: SVNRepositorySummary,
        currentListingURL: String?
    ) -> String {
        if let currentListingURL, !currentListingURL.isEmpty {
            return currentListingURL
        }
        return summary.repositoryURL
    }

    private func loadRepositoryBrowserListing(
        url: String,
        using repositoryInspector: SubversionRepositoryInspector? = nil
    ) async {
        guard !url.isEmpty else {
            repositoryBrowserListing = nil
            repositoryBrowserError = nil
            clearRepositoryBrowserFilePreview()
            return
        }

        guard let repositoryInspector = repositoryInspector ?? self.repositoryInspector else {
            repositoryBrowserListing = nil
            repositoryBrowserError = nil
            clearRepositoryBrowserFilePreview()
            return
        }

        isLoadingRepositoryBrowser = true
        repositoryBrowserError = nil
        do {
            let listing = try await repositoryInspector.browse(
                url: url,
                context: .foreground
            )
            repositoryBrowserListing = listing
            repositoryBrowserError = nil

            if
                let selectedRepositoryBrowserEntry,
                let refreshedEntry = listing.entries.first(where: { $0.id == selectedRepositoryBrowserEntry.id }),
                !refreshedEntry.isDirectory
            {
                await loadRepositoryBrowserFilePreview(for: refreshedEntry)
            } else {
                clearRepositoryBrowserFilePreview()
            }
        } catch {
            clearRepositoryBrowserFilePreview()
            repositoryBrowserError = localizedErrorMessage(for: error)
            diagnosticLog("loadRepositoryBrowserListing failed url=\(url) error=\(error.localizedDescription)")
        }
        isLoadingRepositoryBrowser = false
    }

    private func loadHistoryDetail(for revision: Int64) async {
        guard let repositoryInspector else {
            finishHistoryDetailRequest(for: revision)
            return
        }

        let fallbackRoot = normalizedRootInput
        let root = configuredRootPath ?? (fallbackRoot.isEmpty ? "" : Self.standardizedPath(fallbackRoot))
        guard !root.isEmpty else {
            finishHistoryDetailRequest(for: revision)
            return
        }

        guard historyDetailRequestRevision == revision else {
            return
        }

        selectedHistoryRevision = revision
        isLoadingHistoryDetail = true
        refreshDiffPreview(forceReload: true)
        do {
            diagnosticLog("loadHistoryDetail request root=\(root) revision=\(revision)")
            let detail = try await repositoryInspector.logDetail(
                at: root,
                revision: revision,
                context: .foreground
            )
            guard historyDetailRequestRevision == revision else {
                return
            }

            selectedHistoryEntryDetail = detail
            diagnosticLog("loadHistoryDetail loaded root=\(root) revision=\(revision) changedPaths=\(detail.changedPaths.count)")
        } catch {
            guard historyDetailRequestRevision == revision else {
                return
            }

            selectedHistoryEntryDetail = nil
            diagnosticLog("loadHistoryDetail failed root=\(root) revision=\(revision) error=\(error.localizedDescription)")
        }
        finishHistoryDetailRequest(for: revision)
    }

    private func beginHistoryDetailRequest(for revision: Int64, preferDiffPreview: Bool) {
        selectedHistoryRevision = revision
        selectedHistoryEntryDetail = nil
        historyDetailRequestRevision = revision
        isLoadingHistoryDetail = true
        if preferDiffPreview {
            preferredDiffPreviewMode = .historyRevision
        }
    }

    private func finishHistoryDetailRequest(for revision: Int64) {
        guard historyDetailRequestRevision == revision else {
            return
        }

        historyDetailRequestRevision = nil
        isLoadingHistoryDetail = false
    }

    private func loadRepositoryBrowserFilePreview(for entry: SVNRepositoryBrowserEntry) async {
        guard !entry.isDirectory else {
            clearRepositoryBrowserFilePreview()
            return
        }

        guard let repositoryInspector else {
            clearRepositoryBrowserFilePreview()
            return
        }

        repositoryBrowserPreviewTask?.cancel()
        repositoryBrowserPreviewTask = nil
        selectedRepositoryBrowserEntry = entry
        repositoryBrowserPreviewText = nil
        repositoryBrowserPreviewMessage = nil
        repositoryBrowserPreviewError = nil
        isLoadingRepositoryBrowserPreview = true

        repositoryBrowserPreviewTask = Task { [weak self] in
            do {
                let preview = try await repositoryInspector.fileContents(
                    url: entry.fullURL,
                    context: .foreground
                )

                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    guard let self, self.selectedRepositoryBrowserEntry?.id == entry.id else {
                        return
                    }

                    self.isLoadingRepositoryBrowserPreview = false
                    self.repositoryBrowserPreviewError = nil

                    if preview.isBinary {
                        self.repositoryBrowserPreviewText = nil
                        self.repositoryBrowserPreviewMessage = self.localizer.repositoryBrowserBinaryPreview(
                            entry.name,
                            byteCount: preview.byteCount
                        )
                    } else if let text = preview.text {
                        let truncated = self.truncateRepositoryBrowserPreviewText(text)
                        self.repositoryBrowserPreviewText = truncated.text
                        self.repositoryBrowserPreviewMessage = truncated.wasTruncated
                            ? self.localizer.repositoryBrowserPreviewTruncated(
                                entry.name,
                                byteCount: preview.byteCount
                            )
                            : nil
                    } else {
                        self.repositoryBrowserPreviewText = nil
                        self.repositoryBrowserPreviewMessage = self.localizer.repositoryBrowserEmptyPreview(
                            entry.name
                        )
                    }

                    self.repositoryBrowserPreviewTask = nil
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    guard let self, self.selectedRepositoryBrowserEntry?.id == entry.id else {
                        return
                    }

                    self.isLoadingRepositoryBrowserPreview = false
                    self.repositoryBrowserPreviewText = nil
                    self.repositoryBrowserPreviewMessage = nil
                    self.repositoryBrowserPreviewError = self.localizedErrorMessage(for: error)
                    self.repositoryBrowserPreviewTask = nil
                }
            }
        }
    }

    private func clearRepositoryBrowserFilePreview() {
        repositoryBrowserPreviewTask?.cancel()
        repositoryBrowserPreviewTask = nil
        selectedRepositoryBrowserEntry = nil
        repositoryBrowserPreviewText = nil
        repositoryBrowserPreviewMessage = nil
        repositoryBrowserPreviewError = nil
        isLoadingRepositoryBrowserPreview = false
    }

    private func truncateRepositoryBrowserPreviewText(_ text: String) -> (text: String, wasTruncated: Bool) {
        let maxCharacters = 48_000
        guard text.count > maxCharacters else {
            return (text, false)
        }

        let truncated = String(text.prefix(maxCharacters))
        return (truncated, true)
    }

    private func refreshDiffPreview(forceReload: Bool = false) {
        diffPreviewDebounceTask?.cancel()
        diffPreviewDebounceTask = nil

        if forceReload {
            loadDiffPreview(forceReload: true)
            return
        }

        diffPreviewDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled, let self else {
                return
            }
            self.loadDiffPreview(forceReload: false)
        }
    }

    private func loadDiffPreview(forceReload: Bool) {
        guard let diffInspector else {
            clearDiffPreview(message: nil)
            return
        }

        let fallbackRoot = normalizedRootInput
        let root = configuredRootPath ?? (fallbackRoot.isEmpty ? "" : Self.standardizedPath(fallbackRoot))
        guard !root.isEmpty else {
            clearDiffPreview(message: nil)
            return
        }

        guard let mode = effectiveDiffPreviewMode else {
            clearDiffPreview(message: nil)
            return
        }

        let requestKey: DiffPreviewRequestKey
        let emptyMessage: String?

        switch mode {
        case .workingCopy:
            guard let entry = primarySelectedEntry else {
                clearDiffPreview(message: nil)
                return
            }

            if entry.status == .unversioned {
                clearDiffPreview(
                    message: localizer.diffPreviewUnavailableForUnversioned(entry.displayName)
                )
                return
            }

            requestKey = .workingCopy(
                rootPath: root,
                targetPath: entry.id,
                status: entry.status,
                propertyModified: entry.item.propertyModified,
                contentStamp: diffContentStamp(for: entry.id)
            )
            emptyMessage = localizer.diffPreviewNoChanges(entry.displayName)
        case .historyRevision:
            guard let selectedHistoryRevision else {
                clearDiffPreview(message: nil)
                return
            }

            requestKey = .historyRevision(
                rootPath: root,
                revision: selectedHistoryRevision
            )
            emptyMessage = localizer.historyDiffNoChanges(selectedHistoryRevision)
        }

        guard forceReload || lastDiffPreviewRequest != requestKey else {
            return
        }

        diffPreviewTask?.cancel()
        diffPreviewTask = nil
        lastDiffPreviewRequest = requestKey
        if shouldClearDiffPreview(for: requestKey) {
            selectedDiffText = nil
        }
        diffPreviewMessage = nil
        diffPreviewError = nil
        isLoadingDiffPreview = true

        diffPreviewTask = Task { [weak self] in
            do {
                let preview: SVNDiffPreview
                switch requestKey {
                case let .workingCopy(rootPath, targetPath, _, _, _):
                    preview = try await diffInspector.workingCopyDiff(
                        at: targetPath,
                        workingCopyRoot: rootPath,
                        context: .foreground
                    )
                case let .historyRevision(rootPath, revision):
                    preview = try await diffInspector.revisionDiff(
                        at: rootPath,
                        revision: revision,
                        context: .foreground
                    )
                }

                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    guard
                        let self,
                        self.lastDiffPreviewRequest == requestKey
                    else {
                        return
                    }

                    self.isLoadingDiffPreview = false
                    self.diffPreviewError = nil

                    if preview.isEmpty {
                        self.selectedDiffText = nil
                        self.diffPreviewMessage = emptyMessage
                    } else {
                        self.selectedDiffText = preview.rawText
                        self.diffPreviewMessage = nil
                    }

                    self.diffPreviewTask = nil
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    guard
                        let self,
                        self.lastDiffPreviewRequest == requestKey
                    else {
                        return
                    }

                    self.isLoadingDiffPreview = false
                    self.selectedDiffText = nil
                    self.diffPreviewMessage = nil
                    self.diffPreviewError = self.localizedErrorMessage(for: error)
                    self.diffPreviewTask = nil
                }
            }
        }
    }

    private func diffContentStamp(for path: String) -> DiffContentStamp {
        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return DiffContentStamp(
            modificationTime: values?.contentModificationDate?.timeIntervalSince1970,
            fileSize: values?.fileSize
        )
    }

    private func shouldClearDiffPreview(for requestKey: DiffPreviewRequestKey) -> Bool {
        guard let lastDiffPreviewRequest else {
            return true
        }

        switch (lastDiffPreviewRequest, requestKey) {
        case let (.workingCopy(_, lastPath, _, _, _), .workingCopy(_, path, _, _, _)):
            return lastPath != path
        case let (.historyRevision(_, lastRevision), .historyRevision(_, revision)):
            return lastRevision != revision
        default:
            return true
        }
    }

    private func clearDiffPreview(message: String?) {
        diffPreviewDebounceTask?.cancel()
        diffPreviewDebounceTask = nil
        diffPreviewTask?.cancel()
        diffPreviewTask = nil
        lastDiffPreviewRequest = nil
        selectedDiffText = nil
        diffPreviewMessage = message
        diffPreviewError = nil
        isLoadingDiffPreview = false
    }

    private func performOpenSelectedEntryInExternalDiff(using profile: ExternalToolProfile) async {
        guard !isLaunchingExternalDiff else {
            return
        }

        guard let entry = primarySelectedEntry else {
            lastError = localizer.externalDiffSelectEntryFirst
            return
        }

        guard entry.status != .unversioned else {
            lastError = localizer.externalDiffUnavailableForUnversioned(entry.displayName)
            return
        }

        var stagedArtifactDirectory: URL?
        do {
            _ = try await configureServicesIfNeeded()
            guard let repositoryInspector else {
                throw WorkbenchError.notConfigured
            }

            isLaunchingExternalDiff = true
            let artifactDirectory = try createExternalDiffArtifactDirectory(for: entry)
            stagedArtifactDirectory = artifactDirectory
            let leftURL = try await prepareExternalDiffLeftHandSide(
                for: entry,
                in: artifactDirectory,
                using: repositoryInspector
            )
            let rightPath = entry.id

            try await externalToolLauncher.launch(
                profile: profile,
                leftPath: leftURL.path,
                rightPath: rightPath,
                isDirectory: entry.isDirectory
            )

            externalDiffArtifactDirectories.append(artifactDirectory)
            stagedArtifactDirectory = nil
            if externalDiffArtifactDirectories.count > 12 {
                let staleDirectories = externalDiffArtifactDirectories.dropLast(12)
                for directory in staleDirectories {
                    try? FileManager.default.removeItem(at: directory)
                }
                externalDiffArtifactDirectories = Array(externalDiffArtifactDirectories.suffix(12))
            }

            lastError = nil
            statusNotice = .openedExternalDiff(profile.displayName)
        } catch {
            if let stagedArtifactDirectory {
                try? FileManager.default.removeItem(at: stagedArtifactDirectory)
            }
            lastError = localizedErrorMessage(for: error)
            statusNotice = .externalDiffLaunchFailed
        }

        isLaunchingExternalDiff = false
    }

    private func createExternalDiffArtifactDirectory(for entry: Entry) throws -> URL {
        try FileManager.default.createDirectory(
            at: externalDiffArtifactsRootURL,
            withIntermediateDirectories: true
        )

        let sanitizedName = entry.displayName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let artifactDirectory = externalDiffArtifactsRootURL
            .appending(path: UUID().uuidString + "-" + sanitizedName)
        try FileManager.default.createDirectory(
            at: artifactDirectory,
            withIntermediateDirectories: true
        )
        return artifactDirectory
    }

    private func prepareExternalDiffLeftHandSide(
        for entry: Entry,
        in artifactDirectory: URL,
        using repositoryInspector: SubversionRepositoryInspector
    ) async throws -> URL {
        if entry.isDirectory {
            let baseDirectory = artifactDirectory.appending(path: "BASE-\(entry.displayName)")
            try await repositoryInspector.exportWorkingCopyBase(
                at: entry.id,
                to: baseDirectory.path,
                context: .foreground
            )
            return baseDirectory
        }

        let preview = try await repositoryInspector.workingCopyBaseContents(
            at: entry.id,
            context: .foreground
        )
        let baseFileURL = artifactDirectory.appending(path: "BASE-\(entry.displayName)")
        try preview.data.write(to: baseFileURL, options: .atomic)
        return baseFileURL
    }

    private func applyLoadedEntries(_ freshEntries: [Entry], rootPath: String) {
        entries = freshEntries
        entryByPath = Dictionary(uniqueKeysWithValues: freshEntries.map { ($0.id, $0) })
        treeNodes = ChangeTreeNode.build(from: freshEntries, rootPath: rootPath)
        dirtyCount = freshEntries.reduce(0) { count, entry in
            count + (entry.canCommit ? 1 : 0)
        }
        unversionedCount = freshEntries.reduce(0) { count, entry in
            count + (entry.canAdd ? 1 : 0)
        }
    }

    private func clearLoadedEntries() {
        entries = []
        treeNodes = []
        selectedPaths = []
        dirtyCount = 0
        unversionedCount = 0
        repositorySummary = nil
        repositoryBrowserListing = nil
        repositoryBrowserRootURL = nil
        repositoryBrowserWorkingCopyURL = nil
        isLoadingRepositoryBrowser = false
        repositoryBrowserError = nil
        clearRepositoryBrowserFilePreview()
        recentHistory = []
        recentHistoryError = nil
        isLoadingRecentHistory = false
        selectedHistoryRevision = nil
        selectedHistoryEntryDetail = nil
        isLoadingHistoryDetail = false
        entryByPath = [:]
        clearDiffPreview(message: nil)
    }

    private func collapsedPaths(_ paths: [String]) -> [String] {
        let sortedPaths = Array(Set(paths.map(Self.standardizedPath))).sorted {
            if $0.count != $1.count {
                return $0.count < $1.count
            }
            return $0.localizedStandardCompare($1) == .orderedAscending
        }

        var collapsed: [String] = []
        for path in sortedPaths {
            if collapsed.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
                continue
            }
            collapsed.append(path)
        }
        return collapsed
    }

    private func savePresentationPreferences() {
        var prefs = visibilityPrefs
        prefs.defaultWindowPreset = defaultWindowPreset
        prefs.hideDiffPreviewInCompactWindow = hideDiffPreviewInCompactWindow
        prefs.backendMode = backendMode
        prefs.preserveModificationTimes = preserveModificationTimes
        prefs.maxConcurrentOperations = maxConcurrentOperations
        prefs.badgeEntryLimit = badgeEntryLimit
        prefs.maxIncrementalDirtyPaths = maxIncrementalDirtyPaths
        prefs.selectedExternalDiffToolID = selectedExternalDiffToolID
        presentationPreferencesStore.save(prefs)
    }

    private func resetConfiguredServicesForPreferenceChange() {
        host = nil
        xpcClient = nil
        client = nil
        configuredRootPath = nil
    }

    private func workbenchEntries(from items: [WorkingCopyItem], rootPath: String) -> [Entry] {
        items
            .sorted { lhs, rhs in
                if lhs.isDirty != rhs.isDirty {
                    return lhs.isDirty && !rhs.isDirty
                }
                if lhs.status == .unversioned, rhs.status != .unversioned {
                    return true
                }
                if rhs.status == .unversioned, lhs.status != .unversioned {
                    return false
                }
                return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
            }
            .map {
                Entry(
                    item: $0,
                    relativePath: Self.relativePath(for: $0.path, rootPath: rootPath)
                )
            }
    }

    private func workbenchStatusItems(
        from statusItems: [WorkingCopyItem],
        snapshot: BadgeSnapshot,
        rootPath: String
    ) -> [WorkingCopyItem] {
        var itemsByPath = Dictionary(uniqueKeysWithValues: statusItems.map { ($0.path, $0) })
        var recoveredCount = 0

        for (path, status) in snapshot.entries where itemsByPath[path] == nil {
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            itemsByPath[path] = WorkingCopyItem(
                path: path,
                isDirectory: isDirectory.boolValue,
                status: status,
                propertyModified: false
            )
            recoveredCount += 1
        }

        if recoveredCount > 0 {
            diagnosticLog(
                "performRefresh recovered \(recoveredCount) workbench items from snapshot root=\(rootPath)"
            )
        }

        return Array(itemsByPath.values)
    }

    private func retainedSelection(for entries: [Entry]) -> Set<String> {
        let validPaths = Set(entries.filter(\.isActionable).map(\.id))
        let retained = selectedPaths.intersection(validPaths)
        if !retained.isEmpty {
            return retained
        }

        return []
    }

    private func selectionForFreshEntries(_ entries: [Entry], rootPath: String) -> Set<String> {
        guard let pendingWorkbenchCommand else {
            return retainedSelection(for: entries)
        }

        guard pendingWorkbenchCommand.rootPath == nil || pendingWorkbenchCommand.rootPath == rootPath else {
            return retainedSelection(for: entries)
        }

        lastHandledWorkbenchCommandID = pendingWorkbenchCommand.id
        self.pendingWorkbenchCommand = nil
        workbenchCommandStore.clearCommand()

        let requestedSelection = selectedPaths(
            matching: pendingWorkbenchCommand.selectedPaths,
            in: entries
        )
        if !requestedSelection.isEmpty {
            return requestedSelection
        }

        return retainedSelection(for: entries)
    }

    private func selectedPaths(
        matching requestedPaths: [String],
        in entries: [Entry]
    ) -> Set<String> {
        guard !requestedPaths.isEmpty else {
            return []
        }

        let actionableEntries = entries.filter(\.isActionable)
        let availablePaths = Set(actionableEntries.map(\.id))
        var resolvedSelection: Set<String> = []

        for requestedPath in Set(requestedPaths.map(Self.standardizedPath)) {
            if availablePaths.contains(requestedPath) {
                resolvedSelection.insert(requestedPath)
                continue
            }

            let prefix = requestedPath.hasSuffix("/") ? requestedPath : requestedPath + "/"
            let descendants = actionableEntries
                .map(\.id)
                .filter { $0.hasPrefix(prefix) }
            resolvedSelection.formUnion(descendants)
        }

        return resolvedSelection
    }

    private static func relativePath(for path: String, rootPath: String) -> String {
        let rootURL = URL(fileURLWithPath: rootPath)
        let pathURL = URL(fileURLWithPath: path)
        let relative = pathURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
        return relative.isEmpty ? "." : relative
    }

    private func displayPathsForUpdate(_ paths: [String], rootPath: String) -> [String] {
        Array(Set(paths.map { path in
            path.hasPrefix("/")
                ? Self.relativePath(for: Self.standardizedPath(path), rootPath: rootPath)
                : path
        })).sorted { lhs, rhs in
            lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    private static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func broadcastCurrentMonitoredRoot() {
        let roots = monitoredWorkspaceRoots(checkFileSystem: false)
        monitoredRootsStore.saveRoots(roots)
        diagnosticLog("broadcastMonitoredRoots count=\(roots.count) roots=\(roots.joined(separator: ","))")
    }

    private func monitoredWorkspaceRoots(checkFileSystem: Bool) -> [String] {
        var roots = monitoredRootsStore.loadRoots()
        roots.append(contentsOf: bookmarks.map(\.path))
        let trimmedRoot = rootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedRoot.isEmpty {
            roots.append(trimmedRoot)
        }

        let standardizedRoots = Set(roots.map(Self.standardizedPath))
        guard checkFileSystem else {
            return Array(standardizedRoots).sorted()
        }

        return Array(standardizedRoots.filter { path in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }).sorted()
    }

    private func isCurrentRoot(_ root: String) -> Bool {
        let currentRoot = normalizedRootInput
        guard !currentRoot.isEmpty else {
            return false
        }

        return Self.standardizedPath(currentRoot) == Self.standardizedPath(root)
    }

    private func updateSecurityScopedRootAccess(for rootPath: String) {
        if configuredRootPath != rootPath {
            rootSecurityScopedAccess?.stop()
            rootSecurityScopedAccess = nil
        }

        guard rootSecurityScopedAccess == nil else {
            return
        }

        rootSecurityScopedAccess = securityScopedBookmarkStore.startAccessing(path: rootPath)
    }

    @objc
    private func handleMonitoredRootsRequest(_ notification: Notification) {
        broadcastCurrentMonitoredRoot()
    }

    @objc
    private func handleWorkbenchCommandDidChange(_ notification: Notification) {
        diagnosticLog("handleWorkbenchCommandDidChange notification")
        guard let command = ingestPendingWorkbenchCommand(reason: "distributed-notification") else {
            return
        }
        guard command.rootPath != nil else {
            diagnosticLog("handleWorkbenchCommandDidChange skipped refresh for nil root command")
            consumePendingWorkbenchCommandWithoutRefresh()
            return
        }
        requestRefresh(forceFullRefresh: true)
    }

    @objc
    private func handleAppDidBecomeActive(_ notification: Notification) {
        diagnosticLog("handleAppDidBecomeActive")
        _ = ingestPendingWorkbenchCommand(reason: "app-did-become-active")
    }

    private func ingestPendingWorkbenchCommand(reason: String) -> MacSVNWorkbenchCommand? {
        guard let command = workbenchCommandStore.loadCommand() else {
            diagnosticLog("ingestPendingWorkbenchCommand(\(reason)) no command")
            return nil
        }
        guard command.id != pendingWorkbenchCommand?.id else {
            diagnosticLog("ingestPendingWorkbenchCommand(\(reason)) ignored pending duplicate \(command.id)")
            return nil
        }
        guard command.id != lastHandledWorkbenchCommandID else {
            diagnosticLog("ingestPendingWorkbenchCommand(\(reason)) ignored handled duplicate \(command.id)")
            return nil
        }

        pendingWorkbenchCommand = command
        if let rootPath = command.rootPath, self.rootPath != rootPath {
            self.rootPath = rootPath
        }
        statusNotice = .processingFinderCommand(
            command: command.command,
            pathCount: max(command.selectedPaths.count, 1)
        )
        lastError = nil
        diagnosticLog(
            "ingestPendingWorkbenchCommand(\(reason)) command=\(command.command.rawValue) " +
            "root=\(command.rootPath ?? "nil") selected=\(command.selectedPaths.count)"
        )
        requestWindowPresentationRefresh()
        return command
    }

    private func consumePendingWorkbenchCommandWithoutRefresh() {
        guard let pendingWorkbenchCommand else {
            return
        }

        lastHandledWorkbenchCommandID = pendingWorkbenchCommand.id
        self.pendingWorkbenchCommand = nil
        workbenchCommandStore.clearCommand()
    }

    private func finderReadyNotice(
        for command: MacSVNWorkbenchCommand,
        selectedCount: Int
    ) -> WorkbenchNotice {
        switch command.command {
        case .updateWorkingCopy:
            return .finderCommandReady(command: command.command, selectedCount: selectedCount)
        case .commitSelected:
            return .finderCommitReady(selectedCount: selectedCount)
        case .diffSelected:
            return .finderDiffReady(selectedCount: selectedCount)
        case .openInWorkbench, .refreshNow:
            return .finderCommandReady(command: command.command, selectedCount: selectedCount)
        }
    }

    private func diagnosticLog(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) \(message)\n"
        let logURL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library")
            .appending(path: "Application Support")
            .appending(path: "MacTortoiseSVN")
            .appending(path: "workbench-debug.log")

        do {
            try FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: nil,
                    attributes: [.posixPermissions: 0o600])
            }
            let handle = try FileHandle(forWritingTo: logURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
            try handle.close()
        } catch {
            return
        }
    }

    deinit {
        rootSecurityScopedAccess?.stop()
        diffPreviewTask?.cancel()
        repositoryBrowserPreviewTask?.cancel()
        try? FileManager.default.removeItem(at: externalDiffArtifactsRootURL)
        DistributedNotificationCenter.default().removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

}
