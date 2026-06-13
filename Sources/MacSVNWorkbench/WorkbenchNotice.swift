import CoreTypes
import FinderSyncBridge
import Foundation

enum WorkbenchNotice: Equatable {
    case chooseWorkingCopyPrompt
    case noWorkingCopySelected
    case loadedEntries(entryCount: Int, badgeCount: Int)
    case refreshFailed
    case checkingOutWorkingCopy
    case checkedOutWorkingCopy(path: String, revision: Int64?)
    case checkoutFailed
    case importingPath
    case importedPath(revision: Int64?)
    case importFailed
    case exportingWorkingCopy
    case exportedWorkingCopy(path: String)
    case exportFailed
    case switchingWorkingCopy
    case switchedWorkingCopy(revision: Int64?)
    case switchFailed
    case relocatingWorkingCopy
    case relocatedWorkingCopy
    case relocateFailed
    case updatingWorkingCopy
    case updatedWorkingCopy(pathCount: Int, revision: Int64?, hasConflicts: Bool)
    case updateFailed
    case cleaningWorkingCopy
    case cleanedWorkingCopy
    case cleanupFailed
    case revertingPaths(pathCount: Int)
    case revertedPaths(Int)
    case revertFailed
    case resolvingPaths(pathCount: Int)
    case resolvedPaths(Int)
    case resolveFailed
    case processingFinderCommand(command: FinderMenuCommand, pathCount: Int)
    case finderCommandReady(command: FinderMenuCommand, selectedCount: Int)
    case finderCommitReady(selectedCount: Int)
    case finderDiffReady(selectedCount: Int)
    case watcherStarted
    case watcherStopped
    case watcherUpdateFailed
    case addedPaths(Int)
    case addFailed
    case copiedRepositoryLocation
    case openedRepositoryLocation
    case openedExternalDiff(String)
    case externalDiffLaunchFailed
    case shelvedPaths(pathCount: Int, name: String)
    case shelveFailed
    case unshelved(String)
    case unshelveFailed
    case committedPaths(pathCount: Int, revision: Int64)
    case commitFailed
    case deletedPath(String)
    case ignoredPath(String)
    case lockedPath(String)
    case unlockedPath(String)
    case renamedPath(String, String)
    case createdPatch(String)

    func text(using localizer: MacSVNLocalizer) -> String {
        switch self {
        case .chooseWorkingCopyPrompt:
            return localizer.chooseWorkingCopyPrompt
        case .noWorkingCopySelected:
            return localizer.noWorkingCopySelected
        case let .processingFinderCommand(command, pathCount):
            return localizer.finderCommandLoadingText(
                localizer.title(for: command),
                pathCount: pathCount
            )
        case let .finderCommandReady(command, selectedCount):
            return localizer.finderCommandReadyText(
                localizer.title(for: command),
                selectedCount: selectedCount
            )
        case let .finderCommitReady(selectedCount):
            return localizer.finderCommitReadyText(selectedCount: selectedCount)
        case let .finderDiffReady(selectedCount):
            return localizer.finderDiffReadyText(selectedCount: selectedCount)
        case let .loadedEntries(entryCount, badgeCount):
            return localizer.loadedEntriesText(
                entryCount: entryCount,
                badgeCount: badgeCount
            )
        case .refreshFailed:
            return localizer.refreshFailed
        case .checkingOutWorkingCopy:
            return localizer.checkingOutWorkingCopyText
        case let .checkedOutWorkingCopy(path, revision):
            return localizer.checkoutSucceededText(path: path, revision: revision)
        case .checkoutFailed:
            return localizer.checkoutFailed
        case .importingPath:
            return localizer.importingPathText
        case let .importedPath(revision):
            return localizer.importSucceededText(revision: revision)
        case .importFailed:
            return localizer.importFailed
        case .exportingWorkingCopy:
            return localizer.exportingWorkingCopyText
        case let .exportedWorkingCopy(path):
            return localizer.exportSucceededText(path: path)
        case .exportFailed:
            return localizer.exportFailed
        case .switchingWorkingCopy:
            return localizer.switchingWorkingCopyText
        case let .switchedWorkingCopy(revision):
            return localizer.switchSucceededText(revision: revision)
        case .switchFailed:
            return localizer.switchFailed
        case .relocatingWorkingCopy:
            return localizer.relocatingWorkingCopyText
        case .relocatedWorkingCopy:
            return localizer.relocateSucceededText
        case .relocateFailed:
            return localizer.relocateFailed
        case .updatingWorkingCopy:
            return localizer.updatingWorkingCopyText
        case let .updatedWorkingCopy(pathCount, revision, hasConflicts):
            return localizer.updateSucceededText(
                pathCount: pathCount,
                revision: revision,
                hasConflicts: hasConflicts
            )
        case .updateFailed:
            return localizer.updateFailed
        case .cleaningWorkingCopy:
            return localizer.cleaningWorkingCopyText
        case .cleanedWorkingCopy:
            return localizer.cleanupSucceededText
        case .cleanupFailed:
            return localizer.cleanupFailed
        case let .revertingPaths(pathCount):
            return localizer.revertingPathsText(pathCount: pathCount)
        case let .revertedPaths(pathCount):
            return localizer.revertSucceededText(pathCount: pathCount)
        case .revertFailed:
            return localizer.revertFailed
        case let .resolvingPaths(pathCount):
            return localizer.resolvingPathsText(pathCount: pathCount)
        case let .resolvedPaths(pathCount):
            return localizer.resolveSucceededText(pathCount: pathCount)
        case .resolveFailed:
            return localizer.resolveFailed
        case .watcherStarted:
            return localizer.watcherStarted
        case .watcherStopped:
            return localizer.watcherStopped
        case .watcherUpdateFailed:
            return localizer.watcherUpdateFailed
        case let .addedPaths(pathCount):
            return localizer.addSucceededText(pathCount: pathCount)
        case .addFailed:
            return localizer.addFailed
        case .copiedRepositoryLocation:
            return localizer.repositoryBrowserCopied
        case .openedRepositoryLocation:
            return localizer.repositoryBrowserOpened
        case let .openedExternalDiff(profileName):
            return localizer.openedExternalDiff(profileName)
        case .externalDiffLaunchFailed:
            return localizer.externalDiffLaunchFailed
        case let .shelvedPaths(pathCount, name):
            return localizer.shelveSucceededText(pathCount: pathCount, name: name)
        case .shelveFailed:
            return localizer.shelveFailed
        case let .unshelved(name):
            return localizer.unshelveSucceededText(name: name)
        case .unshelveFailed:
            return localizer.unshelveFailed
        case let .committedPaths(pathCount, revision):
            return localizer.commitSucceededText(
                pathCount: pathCount,
                revision: revision
            )
        case .commitFailed:
            return localizer.commitFailed
        case let .deletedPath(name):
            return localizer.deletedPathText(name)
        case let .ignoredPath(name):
            return localizer.ignoredPathText(name)
        case let .lockedPath(name):
            return localizer.lockedPathText(name)
        case let .unlockedPath(name):
            return localizer.unlockedPathText(name)
        case let .renamedPath(oldName, newName):
            return localizer.renamedPathText(oldName, newName: newName)
        case let .createdPatch(name):
            return localizer.createdPatchText(name)
        }
    }
}

enum WorkbenchError: Error {
    case invalidWorkingCopyRoot
    case workingCopyPathNotFound(String)
    case workingCopyPathIsNotDirectory(String)
    case notConfigured
    case operationFailed(String)

    func localizedText(using localizer: MacSVNLocalizer) -> String {
        switch self {
        case .invalidWorkingCopyRoot:
            return localizer.invalidWorkingCopyRoot
        case let .workingCopyPathNotFound(path):
            return localizer.workingCopyPathNotFoundText(path)
        case let .workingCopyPathIsNotDirectory(path):
            return localizer.workingCopyPathIsNotDirectoryText(path)
        case .notConfigured:
            return localizer.notConfigured
        case let .operationFailed(message):
            return message
        }
    }
}
