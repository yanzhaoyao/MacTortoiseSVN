@testable import StatusService
import CoreTypes
import Foundation
import SVNCore
import XCTest

private actor MockStatusClient: SVNClient {
    private let items: [WorkingCopyItem]
    private(set) var receivedStatusRequests: [(rootPath: String, includeUnversioned: Bool)] = []

    init(items: [WorkingCopyItem]) {
        self.items = items
    }

    func status(
        at rootPath: String,
        options: StatusQueryOptions,
        context: SVNCommandContext
    ) async throws -> [WorkingCopyItem] {
        receivedStatusRequests.append((rootPath, options.includeUnversioned))
        return items
    }

    func commit(
        candidates: [CommitCandidate],
        message: String,
        context: SVNCommandContext
    ) async throws -> Int64 {
        0
    }

    func add(
        paths: [String],
        depth: SVNDepth,
        force: Bool,
        context: SVNCommandContext
    ) async throws {
    }

    func shelve(
        paths: [String],
        name: String,
        context: SVNCommandContext
    ) async throws {
    }

    func unshelve(
        name: String,
        context: SVNCommandContext
    ) async throws {
    }

    func log(
        path: String,
        revision: Int64,
        limit: Int,
        context: SVNCommandContext
    ) async throws -> [SVNHistoryEntry] {
        []
    }

    func statusRequests() -> [(rootPath: String, includeUnversioned: Bool)] {
        receivedStatusRequests
    }
}

private actor MockWatcher: WorkingCopyEventWatching {
    private var handler: (any WorkingCopyEventHandling)?
    private var startedRoots: [String] = []
    private var stoppedRoots: [String] = []

    func setEventHandler(_ handler: (any WorkingCopyEventHandling)?) async {
        self.handler = handler
    }

    func startMonitoring(rootPath: String) async throws {
        startedRoots.append(rootPath)
    }

    func stopMonitoring(rootPath: String) async throws {
        stoppedRoots.append(rootPath)
    }

    func emit(_ event: WorkingCopyFileSystemEvent) async {
        guard let handler else {
            return
        }
        await handler.handle(event: event)
    }

    func rootsStarted() -> [String] {
        startedRoots
    }

    func rootsStopped() -> [String] {
        stoppedRoots
    }
}

final class StatusServiceHostTests: XCTestCase {
    func testSQLiteStorePersistsSnapshotsAndDirtyState() async throws {
        let store = try SQLiteStatusCacheStore(databaseURL: temporaryDatabaseURL())
        let snapshot = BadgeSnapshot(
            rootPath: "/repo",
            generatedAt: Date(timeIntervalSince1970: 123),
            entries: [
                "/repo/README.md": .modified,
                "/repo/notes.txt": .unversioned,
            ]
        )

        try await store.save(snapshot: snapshot)
        try await store.markDirty(rootPath: "/repo", paths: ["/repo/README.md", "/repo/notes.txt"])

        let loadedSnapshot = try await store.loadSnapshot(for: "/repo")
        let dirtyState = try await store.loadDirtyState(for: "/repo")

        XCTAssertEqual(loadedSnapshot, snapshot)
        XCTAssertEqual(dirtyState?.paths, ["/repo/README.md", "/repo/notes.txt"])
        XCTAssertEqual(dirtyState?.requiresFullRefresh, false)
    }

    func testSQLiteStoreReadOnlyModeLoadsExistingSnapshotsButCannotWrite() async throws {
        let databaseURL = temporaryDatabaseURL()
        let writableStore = try SQLiteStatusCacheStore(databaseURL: databaseURL)
        let snapshot = BadgeSnapshot(
            rootPath: "/repo",
            generatedAt: Date(timeIntervalSince1970: 123),
            entries: ["/repo/README.md": .modified]
        )
        try await writableStore.save(snapshot: snapshot)

        let readOnlyStore = try SQLiteStatusCacheStore(databaseURL: databaseURL, readOnly: true)
        let loadedSnapshot = try await readOnlyStore.loadSnapshot(for: "/repo")

        XCTAssertEqual(loadedSnapshot, snapshot)
        do {
            try await readOnlyStore.save(snapshot: snapshot)
            XCTFail("Read-only SQLite store should reject writes.")
        } catch {
            XCTAssertNotNil(error as? SQLiteStatusCacheError)
        }
    }

    func testSQLiteStoreReadOnlyModeDoesNotCreateMissingDatabase() {
        let databaseURL = temporaryDatabaseURL()

        XCTAssertThrowsError(try SQLiteStatusCacheStore(databaseURL: databaseURL, readOnly: true))
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path))
    }

    func testDefaultDatabaseURLUsesStableHashFilename() {
        let firstCollisionCandidate = StatusServiceConfiguration.defaultDatabaseURL(for: "/tmp/a_b")
        let secondCollisionCandidate = StatusServiceConfiguration.defaultDatabaseURL(for: "/tmp/a/b")
        let standardizedFirst = StatusServiceConfiguration.defaultDatabaseURL(for: "/tmp/project/../project")
        let standardizedSecond = StatusServiceConfiguration.defaultDatabaseURL(for: "/tmp/project")

        XCTAssertNotEqual(firstCollisionCandidate.lastPathComponent, secondCollisionCandidate.lastPathComponent)
        XCTAssertEqual(standardizedFirst.lastPathComponent, standardizedSecond.lastPathComponent)
        XCTAssertLessThan(firstCollisionCandidate.lastPathComponent.count, 255)
        XCTAssertTrue(firstCollisionCandidate.lastPathComponent.hasSuffix(".sqlite3"))
    }

    func testStatusServicePromotesLargeDirtySetsToFullRefresh() async throws {
        let store = try SQLiteStatusCacheStore(databaseURL: temporaryDatabaseURL())
        let client = MockStatusClient(
            items: [
                WorkingCopyItem(path: "/repo/README.md", isDirectory: false, status: .modified),
            ]
        )
        let configuration = StatusServiceConfiguration(
            repositoryRoot: "/repo",
            databaseURL: temporaryDatabaseURL(),
            maxIncrementalDirtyPaths: 2,
            bridgeConfiguration: .development(repositoryRoot: "/repo")
        )
        let host = StatusServiceHost(configuration: configuration, client: client, store: store)

        try await host.markDirty(
            rootPath: "/repo",
            paths: ["/repo/a", "/repo/b", "/repo/c"]
        )

        let pendingRoots = try await host.pendingRefreshRoots()

        XCTAssertEqual(pendingRoots.count, 1)
        XCTAssertTrue(pendingRoots[0].requiresFullRefresh)
        XCTAssertTrue(pendingRoots[0].paths.isEmpty)
    }

    func testRefreshStoresSnapshotAndClearsDirtyState() async throws {
        let store = try SQLiteStatusCacheStore(databaseURL: temporaryDatabaseURL())
        let client = MockStatusClient(
            items: [
                WorkingCopyItem(path: "/repo/README.md", isDirectory: false, status: .modified),
                WorkingCopyItem(
                    path: "/repo/project.xcodeproj",
                    isDirectory: true,
                    status: .normal,
                    propertyModified: true
                ),
            ]
        )
        let configuration = StatusServiceConfiguration(
            repositoryRoot: "/repo",
            databaseURL: temporaryDatabaseURL(),
            maxIncrementalDirtyPaths: 4,
            bridgeConfiguration: .development(repositoryRoot: "/repo")
        )
        let host = StatusServiceHost(configuration: configuration, client: client, store: store)

        try await host.markDirty(
            rootPath: "/repo",
            paths: ["/repo/README.md", "/repo/project.xcodeproj"]
        )
        let snapshot = try await host.refresh(rootPath: "/repo")
        let cachedSnapshot = try await host.snapshot(for: "/repo")
        let pendingRoots = try await host.pendingRefreshRoots()
        let requests = await client.statusRequests()

        XCTAssertEqual(snapshot.entries["/repo/README.md"], .modified)
        XCTAssertEqual(snapshot.entries["/repo/project.xcodeproj"], .modified)
        XCTAssertEqual(cachedSnapshot, snapshot)
        XCTAssertTrue(pendingRoots.isEmpty)
        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requests[0].includeUnversioned)
    }

    func testStartMonitoringRegistersWatcherAndWatcherEventsBecomeDirtyRoots() async throws {
        let store = try SQLiteStatusCacheStore(databaseURL: temporaryDatabaseURL())
        let client = MockStatusClient(
            items: [
                WorkingCopyItem(path: "/repo/README.md", isDirectory: false, status: .modified),
            ]
        )
        let watcher = MockWatcher()
        let configuration = StatusServiceConfiguration(
            repositoryRoot: "/repo",
            databaseURL: temporaryDatabaseURL(),
            maxIncrementalDirtyPaths: 4,
            bridgeConfiguration: .development(repositoryRoot: "/repo")
        )
        let host = StatusServiceHost(
            configuration: configuration,
            client: client,
            store: store,
            watcher: watcher
        )

        try await host.startMonitoring(rootPath: "/repo")
        _ = try await host.refresh(rootPath: "/repo", forceFullRefresh: true)
        await watcher.emit(.incremental(rootPath: "/repo", changedPaths: ["/repo/src/main.swift"]))

        let pendingRoots = try await host.pendingRefreshRoots()
        let startedRoots = await watcher.rootsStarted()

        XCTAssertEqual(startedRoots, ["/repo"])
        XCTAssertEqual(pendingRoots.count, 1)
        XCTAssertEqual(pendingRoots[0].rootPath, "/repo")
        XCTAssertFalse(pendingRoots[0].requiresFullRefresh)
        XCTAssertEqual(pendingRoots[0].paths, ["/repo/src/main.swift"])
    }

    func testFullRefreshWatcherEventSchedulesFullRefresh() async throws {
        let store = try SQLiteStatusCacheStore(databaseURL: temporaryDatabaseURL())
        let client = MockStatusClient(items: [])
        let watcher = MockWatcher()
        let configuration = StatusServiceConfiguration(
            repositoryRoot: "/repo",
            databaseURL: temporaryDatabaseURL(),
            maxIncrementalDirtyPaths: 4,
            bridgeConfiguration: .development(repositoryRoot: "/repo")
        )
        let host = StatusServiceHost(
            configuration: configuration,
            client: client,
            store: store,
            watcher: watcher
        )

        try await host.startMonitoring(rootPath: "/repo")
        _ = try await host.refresh(rootPath: "/repo", forceFullRefresh: true)
        await watcher.emit(.fullRefresh(rootPath: "/repo"))

        let pendingRoots = try await host.pendingRefreshRoots()

        XCTAssertEqual(pendingRoots.count, 1)
        XCTAssertTrue(pendingRoots[0].requiresFullRefresh)
        XCTAssertTrue(pendingRoots[0].paths.isEmpty)
    }
}

private func temporaryDatabaseURL() -> URL {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "MacTortoiseSVN-Tests")
        .appending(path: UUID().uuidString)
    return directory.appending(path: "status-cache.sqlite3")
}
