import AppKit
import FinderSyncBridge
import Foundation

@main
struct MacSVNQuickActions {
    static func main() {
        let arguments = CommandLine.arguments.dropFirst()
        let command = parseCommand(from: arguments.first)
        let paths = Array(arguments.dropFirst()).map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        }

        let rootsStore = MacSVNMonitoredRootsStore()
        let rootPath = paths.compactMap { rootsStore.rootPath(containing: $0) }.first
            ?? paths.first
            ?? rootsStore.loadRoots().first

        let workbenchCommand = MacSVNWorkbenchCommand(
            command: command,
            rootPath: rootPath,
            selectedPaths: paths
        )
        MacSVNWorkbenchCommandStore().saveCommand(workbenchCommand)

        NSWorkspace.shared.launchApplication(
            withBundleIdentifier: "com.morningstar.MacTortoiseSVN",
            options: [.async],
            additionalEventParamDescriptor: nil,
            launchIdentifier: nil
        )
    }

    private static func parseCommand(from rawValue: String?) -> FinderMenuCommand {
        guard let rawValue else {
            return .openInWorkbench
        }

        switch rawValue.lowercased() {
        case "update", "pull", "updateworkingcopy", "update-working-copy":
            return .updateWorkingCopy
        case "commit", "commitselected", "commit-selected":
            return .commitSelected
        case "diff", "diffselected", "diff-selected":
            return .diffSelected
        case "refresh", "refreshnow", "refresh-now":
            return .refreshNow
        default:
            return .openInWorkbench
        }
    }
}
