@testable import SVNCore
import XCTest

final class SubversionWorkspaceOperatorTests: XCTestCase {
    func testUpdateParsesChangedPathsRevisionAndConflictFlag() async throws {
        let output = """
        Updating '/repo':
        U    /repo/README.md
        C    /repo/Docs/Guide.md
        Updated to revision 42.
        """
        let runner = RecordingSubversionRunner(
            results: [
                SubversionCLIInvocationResult(stdout: output, stderr: "", exitCode: 0),
            ]
        )
        let workspaceOperator = SubversionWorkspaceOperator(runner: runner)

        let result = try await workspaceOperator.update(
            rootPath: "/repo",
            context: .foreground
        )
        let requests = await runner.requests()

        XCTAssertEqual(result.rootPath, "/repo")
        XCTAssertEqual(result.updatedPaths, ["/repo/README.md", "/repo/Docs/Guide.md"])
        XCTAssertEqual(result.resultingRevision, 42)
        XCTAssertTrue(result.hasConflicts)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(
            requests[0].arguments,
            ["update", "--depth", "infinity", "--accept", "postpone", "--", "/repo"]
        )
    }

    func testRevertParsesRevertedPaths() async throws {
        let output = """
        Reverted '/repo/README.md'
        Reverted '/repo/Docs/Guide.md'
        """
        let runner = RecordingSubversionRunner(
            results: [
                SubversionCLIInvocationResult(stdout: output, stderr: "", exitCode: 0),
            ]
        )
        let workspaceOperator = SubversionWorkspaceOperator(runner: runner)

        let result = try await workspaceOperator.revert(
            paths: ["/repo/Docs/Guide.md", "/repo/README.md"],
            context: .foreground
        )
        let requests = await runner.requests()

        XCTAssertEqual(result.requestedPaths, ["/repo/Docs/Guide.md", "/repo/README.md"])
        XCTAssertEqual(result.revertedPaths, ["/repo/README.md", "/repo/Docs/Guide.md"])
        XCTAssertFalse(result.removeAdded)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(
            requests[0].arguments,
            ["revert", "--depth", "infinity", "--", "/repo/Docs/Guide.md", "/repo/README.md"]
        )
    }

    func testCleanupUsesCleanupCommand() async throws {
        let runner = RecordingSubversionRunner(
            results: [
                SubversionCLIInvocationResult(stdout: "", stderr: "", exitCode: 0),
            ]
        )
        let workspaceOperator = SubversionWorkspaceOperator(runner: runner)

        let result = try await workspaceOperator.cleanup(
            rootPath: "/repo",
            context: .foreground
        )
        let requests = await runner.requests()

        XCTAssertEqual(result.rootPath, "/repo")
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].arguments, ["cleanup", "--", "/repo"])
    }

    func testResolveParsesResolvedPathsAndAcceptStrategy() async throws {
        let output = """
        Merge conflicts in '/repo/README.md' marked as resolved.
        Tree conflicts in '/repo/Docs' marked as resolved.
        """
        let runner = RecordingSubversionRunner(
            results: [
                SubversionCLIInvocationResult(stdout: output, stderr: "", exitCode: 0),
            ]
        )
        let workspaceOperator = SubversionWorkspaceOperator(runner: runner)

        let result = try await workspaceOperator.resolve(
            paths: ["/repo/Docs", "/repo/README.md"],
            context: .foreground
        )
        let requests = await runner.requests()

        XCTAssertEqual(result.requestedPaths, ["/repo/Docs", "/repo/README.md"])
        XCTAssertEqual(result.resolvedPaths, ["/repo/README.md", "/repo/Docs"])
        XCTAssertEqual(result.acceptStrategy, "working")
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(
            requests[0].arguments,
            ["resolve", "--accept", "working", "--depth", "infinity", "--", "/repo/Docs", "/repo/README.md"]
        )
    }

    func testCheckoutUsesCheckoutCommandAndParsesRevision() async throws {
        let runner = RecordingSubversionRunner(
            results: [
                SubversionCLIInvocationResult(
                    stdout: "Checked out revision 12.\n",
                    stderr: "",
                    exitCode: 0
                ),
            ]
        )
        let workspaceOperator = SubversionWorkspaceOperator(runner: runner)

        let result = try await workspaceOperator.checkout(
            repositoryURL: "https://svn.example.com/project/trunk",
            destinationPath: "/work/project",
            context: .foreground
        )
        let requests = await runner.requests()

        XCTAssertEqual(result.revision, 12)
        XCTAssertEqual(
            requests[0].arguments,
            ["checkout", "--depth", "infinity", "--", "https://svn.example.com/project/trunk", "/work/project"]
        )
    }

    func testImportUsesImportCommandAndParsesCommittedRevision() async throws {
        let runner = RecordingSubversionRunner(
            results: [
                SubversionCLIInvocationResult(
                    stdout: "Adding         /work/import/README.md\nCommitted revision 13.\n",
                    stderr: "",
                    exitCode: 0
                ),
            ]
        )
        let workspaceOperator = SubversionWorkspaceOperator(runner: runner)

        let result = try await workspaceOperator.importPath(
            sourcePath: "/work/import",
            repositoryURL: "https://svn.example.com/project/trunk",
            message: "Initial import",
            context: .foreground
        )
        let requests = await runner.requests()

        XCTAssertEqual(result.revision, 13)
        XCTAssertEqual(
            requests[0].arguments,
            ["import", "-m", "Initial import", "--", "/work/import", "https://svn.example.com/project/trunk"]
        )
    }

    func testExportUsesExportCommand() async throws {
        let runner = RecordingSubversionRunner(
            results: [
                SubversionCLIInvocationResult(stdout: "", stderr: "", exitCode: 0),
            ]
        )
        let workspaceOperator = SubversionWorkspaceOperator(runner: runner)

        _ = try await workspaceOperator.export(
            source: "/work/project",
            destinationPath: "/tmp/project-export",
            context: .foreground
        )
        let requests = await runner.requests()

        XCTAssertEqual(
            requests[0].arguments,
            ["export", "--force", "--", "/work/project", "/tmp/project-export"]
        )
    }

    func testSwitchAndRelocateUseExpectedCommands() async throws {
        let runner = RecordingSubversionRunner(
            results: [
                SubversionCLIInvocationResult(stdout: "At revision 21.\n", stderr: "", exitCode: 0),
                SubversionCLIInvocationResult(stdout: "", stderr: "", exitCode: 0),
            ]
        )
        let workspaceOperator = SubversionWorkspaceOperator(runner: runner)

        let switchResult = try await workspaceOperator.switchWorkingCopy(
            workingCopyPath: "/work/project",
            repositoryURL: "https://svn.example.com/project/branches/release",
            context: .foreground
        )
        _ = try await workspaceOperator.relocate(
            workingCopyPath: "/work/project",
            fromURL: "https://old.example.com/svn",
            toURL: "https://new.example.com/svn",
            context: .foreground
        )
        let requests = await runner.requests()

        XCTAssertEqual(switchResult.revision, 21)
        XCTAssertEqual(
            requests[0].arguments,
            ["switch", "--depth", "infinity", "--", "https://svn.example.com/project/branches/release", "/work/project"]
        )
        XCTAssertEqual(
            requests[1].arguments,
            ["relocate", "--", "https://old.example.com/svn", "https://new.example.com/svn", "/work/project"]
        )
    }
}
