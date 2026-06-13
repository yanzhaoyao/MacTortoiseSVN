import Foundation

public final class MacSVNSecurityScopedAccess: @unchecked Sendable {
    public let url: URL

    private let isSecurityScoped: Bool
    private var isActive = true

    init(url: URL, isSecurityScoped: Bool = true) {
        self.url = url
        self.isSecurityScoped = isSecurityScoped
    }

    public func stop() {
        guard isActive else {
            return
        }
        isActive = false
        if isSecurityScoped {
            url.stopAccessingSecurityScopedResource()
        }
    }

    deinit {
        stop()
    }
}

private struct SecurityScopedBookmarkRecord: Codable, Hashable {
    var path: String
    var bookmarkData: Data
}

public struct MacSVNSecurityScopedBookmarkStore: Sendable {
    private static let userDefaultsKey = "MacSVNSecurityScopedBookmarks"

    public init() {
    }

    public func saveBookmark(for url: URL) {
        let standardizedURL = url.standardizedFileURL
        guard standardizedURL.isFileURL else {
            return
        }
        // Security-scoped bookmark creation throws outside the App Sandbox;
        // fall back to a regular bookmark so the path is still remembered.
        let bookmarkData = (try? standardizedURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )) ?? (try? standardizedURL.bookmarkData())
        guard let bookmarkData else {
            return
        }

        save(record: SecurityScopedBookmarkRecord(
            path: standardizedURL.path,
            bookmarkData: bookmarkData
        ))
    }

    public func removeBookmark(forPath path: String) {
        let normalizedPath = standardizedPath(path)
        var records = loadRecords()
        records.removeAll { $0.path == normalizedPath }
        persist(records)
    }

    public func startAccessing(path: String) -> MacSVNSecurityScopedAccess? {
        let normalizedPath = standardizedPath(path)
        guard let record = bestMatchingRecord(for: normalizedPath) else {
            return nil
        }

        var isStale = false
        var isSecurityScoped = true
        var resolvedURL = try? URL(
            resolvingBookmarkData: record.bookmarkData,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        if resolvedURL == nil {
            isSecurityScoped = false
            isStale = false
            resolvedURL = try? URL(
                resolvingBookmarkData: record.bookmarkData,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        }
        guard let resolvedURL else {
            return nil
        }

        if isStale {
            saveBookmark(for: resolvedURL)
        }

        if isSecurityScoped {
            isSecurityScoped = resolvedURL.startAccessingSecurityScopedResource()
        }

        return MacSVNSecurityScopedAccess(url: resolvedURL, isSecurityScoped: isSecurityScoped)
    }

    public func hasBookmark(forPath path: String) -> Bool {
        bestMatchingRecord(for: standardizedPath(path)) != nil
    }

    private func bestMatchingRecord(for path: String) -> SecurityScopedBookmarkRecord? {
        loadRecords()
            .filter { path == $0.path || path.hasPrefix($0.path + "/") }
            .max(by: { $0.path.count < $1.path.count })
    }

    private func save(record: SecurityScopedBookmarkRecord) {
        var records = loadRecords()
        records.removeAll { $0.path == record.path }
        records.append(record)
        records.sort { $0.path < $1.path }
        persist(records)
    }

    private func loadRecords() -> [SecurityScopedBookmarkRecord] {
        if
            let sharedDefaults = UserDefaults(suiteName: MacSVNLanguageStore.appGroupSuiteName),
            let data = sharedDefaults.data(forKey: Self.userDefaultsKey),
            let records = try? JSONDecoder().decode([SecurityScopedBookmarkRecord].self, from: data)
        {
            return records
        }

        guard
            let storageURL,
            let data = try? Data(contentsOf: storageURL),
            let records = try? JSONDecoder().decode([SecurityScopedBookmarkRecord].self, from: data)
        else {
            return []
        }

        return records
    }

    private func persist(_ records: [SecurityScopedBookmarkRecord]) {
        if
            let sharedDefaults = UserDefaults(suiteName: MacSVNLanguageStore.appGroupSuiteName),
            let data = try? JSONEncoder().encode(records)
        {
            sharedDefaults.set(data, forKey: Self.userDefaultsKey)
        }

        guard let storageURL else {
            return
        }
        let fileManager = FileManager.default
        let directoryURL = storageURL.deletingLastPathComponent()

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
            let data = try JSONEncoder().encode(records)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            return
        }
    }

    private var storageURL: URL? {
        macSVNSharedAppSupportDirectory()?
            .appending(path: "security-scoped-bookmarks.json")
    }
}
