# MacTortoiseSVN

MacTortoiseSVN is a native macOS SVN client inspired by TortoiseSVN, but rebuilt around macOS app, extension, sandbox, and process-boundary constraints.

The project goal is not just to clone the Windows UI. It is to provide a fast standalone SVN workbench, thin Finder integration, cached badge status, and a service-oriented backend that can handle large working copies without making Finder do heavy work.

## Feature tree

```text
MacTortoiseSVN
├── Standalone Workbench App
│   ├── Native SwiftUI macOS interface
│   ├── Working copy picker
│   ├── Commit-oriented change list
│   ├── Modified / unversioned / conflicted status display
│   ├── Partial selection for commits
│   ├── Commit message editor
│   ├── Add selected paths
│   ├── Update working copy
│   ├── Revert / resolve / cleanup-oriented workflow hooks
│   ├── Recent history and revision detail views
│   ├── Repository browser surfaces
│   ├── Property / blame / diff-related UI surfaces
│   ├── External diff tool integration points
│   ├── Window layout presets and compact mode
│   └── Chinese / English localization foundation
│
├── Finder Integration
│   ├── Finder Sync extension bundle
│   ├── Context menu commands
│   │   ├── Open in Workbench
│   │   ├── Commit selected
│   │   ├── Add selected
│   │   ├── Diff selected
│   │   └── Refresh now
│   ├── Badge resolution from cached status snapshots
│   ├── App Group shared command handoff
│   ├── DistributedNotification refresh signaling
│   └── Quick Actions fallback surface
│
├── Status Pipeline
│   ├── StatusServiceHost service-layer core
│   ├── SQLite-backed badge snapshot cache
│   ├── Persistent dirty-path tracking
│   ├── Incremental dirty refresh scheduling
│   ├── Full-refresh promotion for noisy roots
│   ├── FSEvents working-copy watcher
│   ├── Cache location outside working copies
│   └── Finder-safe constant-time badge reads
│
├── XPC / Process Boundaries
│   ├── Bundled StatusService.xpc target
│   ├── NSXPC protocol and client scaffold
│   ├── Client validation foundation
│   ├── Host app owns heavyweight workflow UI
│   ├── Finder extension avoids recursive SVN scans
│   └── Target path for app / extension / service separation
│
├── SVN Backend
│   ├── SVNCore abstraction layer
│   ├── Command-line svn compatibility backend
│   ├── Rust process bridge through mtsvn-rs
│   ├── status / snapshot bridge commands
│   ├── add / commit bridge commands
│   ├── XML-based svn log parsing
│   ├── Process + arguments execution, no shell interpolation
│   └── -- option terminators for positional SVN operands
│
├── Rust Phase 1 Core
│   ├── rust/svn_backend typed command wrapper
│   ├── rust/status_engine dirty-root and badge pipeline
│   ├── mtsvn-rs verification CLI
│   ├── Swift-to-Rust process bridge
│   └── Future path toward stable IPC or lower-level bridge
│
├── Security / macOS Integration
│   ├── App Group storage for app / extension shared state
│   ├── Security-scoped bookmark storage for selected roots
│   ├── FinderSync fails closed when App Group is unavailable
│   ├── FinderSync opens SQLite cache read-only
│   ├── Notification payloads are treated as signals, not trusted data
│   ├── Stable hashed SQLite cache filenames
│   ├── Sandboxed Finder extension boundary
│   └── Signing-aware permission behavior documentation
│
├── Packaging
│   ├── Local .app bundle assembly script
│   ├── Embedded Rust helper binary
│   ├── Embedded FinderSync .appex
│   ├── Embedded StatusService .xpc
│   ├── App icon generation script
│   ├── Local codesign flow
│   └── Install script for local testing
│
└── Tests
    ├── Swift package unit tests
    ├── StatusCenter tests
    ├── StatusService SQLite and dirty-state tests
    ├── SVNCore command construction tests
    ├── FinderSyncBridge tests
    ├── Real local-SVN integration tests
    └── Rust cargo tests
```

## Current architecture

MacTortoiseSVN deliberately separates Finder-facing work from heavy SVN operations.

```text
Finder
└── MacSVNFinderSync.appex
    ├── Reads monitored roots from App Group storage
    ├── Reads cached badge snapshots from App Group SQLite
    ├── Sends refresh signals through DistributedNotification
    └── Forwards commands to the standalone app

MacTortoiseSVN.app
├── SwiftUI Workbench UI
├── Commit / add / update / diff workflows
├── Finder command ingestion
├── Security-scoped root access
├── SVNCore client calls
└── Status cache publishing

StatusServiceHost / StatusService.xpc
├── Owns refresh scheduling direction
├── Maintains badge snapshots and dirty paths
├── Uses FSEvents for working-copy invalidation
├── Talks to SVNCore / Rust bridge
└── Represents the target background-service boundary

Rust Core
├── svn_backend wraps command-line svn
├── status_engine builds badge snapshots
└── mtsvn-rs exposes bridge commands for Swift
```

### Current FinderSync data path

Today, FinderSync does **not** directly depend on the XPC service for badge reads. The current implemented path is:

```text
MacTortoiseSVN.app / service side
    └── writes badge snapshots and dirty state
        └── App Group SQLite cache
            └── FinderSync reads read-only snapshots
```

`DistributedNotification` is only a refresh signal. Notification payloads are not trusted as the source of monitored roots or badge state.

### Target direction

The long-term target is an authenticated app / extension / XPC service split where FinderSync asks a background status service for compact cached payloads, while the service owns refresh scheduling and cache writes.

## Implemented highlights

- Native standalone macOS workbench executable: `MacTortoiseSVN`.
- Local app bundle packaging under `dist/MacTortoiseSVN.app`.
- Finder Sync extension target and packaged `.appex`.
- Quick Actions fallback target.
- Bundled `StatusService.xpc` target and NSXPC protocol scaffold.
- SQLite persistent status cache.
- Read-only FinderSync status cache access.
- FSEvents-backed working-copy watcher.
- Rust-backed phase-one status bridge.
- Command-line `svn` backend with argument-array execution.
- Security hardening around SVN option injection.
- Stable hashed cache filenames to avoid path collisions.
- Security-scoped bookmark storage for user-selected working-copy roots.
- Generated app icon and local signing flow.

## Repository layout

```text
.
├── Apps
│   ├── MacSVNApp
│   ├── MacSVNFinderSync
│   ├── MacSVNQuickActions
│   └── MacSVNStatusService
├── Docs
│   ├── Architecture.md
│   ├── CompetitiveRequirements.md
│   ├── RustPhase1.md
│   ├── SECURITY_AUDIT.md
│   └── Assets
├── Sources
│   ├── CoreTypes
│   ├── FinderSyncBridge
│   ├── IntegrationKit
│   ├── MacSVNWorkbench
│   ├── StatusCenter
│   ├── StatusService
│   ├── StatusServiceXPC
│   └── SVNCore
├── Tests
├── rust
├── scripts
└── dist
```

## Build and verify

```sh
# Rust tests
cd rust && /opt/homebrew/bin/cargo test

# Swift package tests
env \
  HOME=$PWD/.tmp-home \
  CLANG_MODULE_CACHE_PATH=$PWD/.build/ModuleCache.noindex \
  SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build/ModuleCache.noindex \
  swift test

# Build local app bundle
./scripts/build_workbench_app.sh

# Install locally for testing
./scripts/install_workbench_app.sh
```

The packaged app bundle is created at:

```text
dist/MacTortoiseSVN.app
```

## macOS permissions and signing

macOS file permissions are tied to app identity. With ad-hoc signing, each rebuild can appear as a different app to TCC, which may cause repeated Desktop / Documents / Downloads permission prompts.

For stable local testing, use a stable Apple Development signing identity. For long-term distribution, use Developer ID Application signing plus notarization.

The app also stores security-scoped bookmarks for user-selected working-copy roots so normal use can be closer to “choose once, reuse later.”

## Remaining work

- Production signing and notarization.
- More complete release packaging outside local debug builds.
- Larger-scale performance and stress testing.
- Native diff / merge UI beyond external-tool integration.
- Broader backend coverage for advanced SVN workflows.
- Finalized stable IPC boundary between Swift and Rust / service layers.
- Additional hardening review for XPC audit-token implementation and notarization compatibility.

## License

This project is licensed under the **Apache License 3.0** — see the [LICENSE](LICENSE) file for details.

## Support the project

If this project helps you, sponsorship is welcome.

<p align="center">
  <img src="Docs/Assets/wechat-pay.png" alt="WeChat Pay QR Code" width="360">
</p>
