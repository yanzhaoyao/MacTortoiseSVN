import Foundation

public struct SVNUpdateResult: Sendable, Hashable, Codable {
    public var rootPath: String
    public var updatedPaths: [String]
    public var resultingRevision: Int64?
    public var hasConflicts: Bool
    public var rawOutput: String

    public init(
        rootPath: String,
        updatedPaths: [String],
        resultingRevision: Int64?,
        hasConflicts: Bool,
        rawOutput: String
    ) {
        self.rootPath = rootPath
        self.updatedPaths = updatedPaths
        self.resultingRevision = resultingRevision
        self.hasConflicts = hasConflicts
        self.rawOutput = rawOutput
    }
}

public struct SVNRevertResult: Sendable, Hashable, Codable {
    public var requestedPaths: [String]
    public var revertedPaths: [String]
    public var removeAdded: Bool
    public var rawOutput: String

    public init(
        requestedPaths: [String],
        revertedPaths: [String],
        removeAdded: Bool,
        rawOutput: String
    ) {
        self.requestedPaths = requestedPaths
        self.revertedPaths = revertedPaths
        self.removeAdded = removeAdded
        self.rawOutput = rawOutput
    }
}

public struct SVNCleanupResult: Sendable, Hashable, Codable {
    public var rootPath: String
    public var rawOutput: String

    public init(rootPath: String, rawOutput: String) {
        self.rootPath = rootPath
        self.rawOutput = rawOutput
    }
}

public struct SVNResolveResult: Sendable, Hashable, Codable {
    public var requestedPaths: [String]
    public var resolvedPaths: [String]
    public var acceptStrategy: String
    public var rawOutput: String

    public init(
        requestedPaths: [String],
        resolvedPaths: [String],
        acceptStrategy: String,
        rawOutput: String
    ) {
        self.requestedPaths = requestedPaths
        self.resolvedPaths = resolvedPaths
        self.acceptStrategy = acceptStrategy
        self.rawOutput = rawOutput
    }
}

public struct SVNCheckoutResult: Sendable, Hashable, Codable {
    public var repositoryURL: String
    public var destinationPath: String
    public var revision: Int64?
    public var rawOutput: String

    public init(repositoryURL: String, destinationPath: String, revision: Int64?, rawOutput: String) {
        self.repositoryURL = repositoryURL
        self.destinationPath = destinationPath
        self.revision = revision
        self.rawOutput = rawOutput
    }
}

public struct SVNImportResult: Sendable, Hashable, Codable {
    public var sourcePath: String
    public var repositoryURL: String
    public var revision: Int64?
    public var rawOutput: String

    public init(sourcePath: String, repositoryURL: String, revision: Int64?, rawOutput: String) {
        self.sourcePath = sourcePath
        self.repositoryURL = repositoryURL
        self.revision = revision
        self.rawOutput = rawOutput
    }
}

public struct SVNExportResult: Sendable, Hashable, Codable {
    public var source: String
    public var destinationPath: String
    public var rawOutput: String

    public init(source: String, destinationPath: String, rawOutput: String) {
        self.source = source
        self.destinationPath = destinationPath
        self.rawOutput = rawOutput
    }
}

public struct SVNSwitchResult: Sendable, Hashable, Codable {
    public var workingCopyPath: String
    public var repositoryURL: String
    public var revision: Int64?
    public var rawOutput: String

    public init(workingCopyPath: String, repositoryURL: String, revision: Int64?, rawOutput: String) {
        self.workingCopyPath = workingCopyPath
        self.repositoryURL = repositoryURL
        self.revision = revision
        self.rawOutput = rawOutput
    }
}

public struct SVNRelocateResult: Sendable, Hashable, Codable {
    public var workingCopyPath: String
    public var fromURL: String
    public var toURL: String
    public var rawOutput: String

    public init(workingCopyPath: String, fromURL: String, toURL: String, rawOutput: String) {
        self.workingCopyPath = workingCopyPath
        self.fromURL = fromURL
        self.toURL = toURL
        self.rawOutput = rawOutput
    }
}

public actor SubversionWorkspaceOperator {
    private let runner: any SubversionCommandRunning

    public init() {
        self.runner = ProcessSubversionRunner()
    }

    init(runner: any SubversionCommandRunning) {
        self.runner = runner
    }

    public func update(
        rootPath: String,
        depth: SVNDepth = .infinity,
        accept: String = "postpone",
        context: SVNCommandContext
    ) async throws -> SVNUpdateResult {
        let arguments = await authenticatedArguments(
            [
                "update",
                "--depth",
                depth.rawValue,
                "--accept",
                accept,
                "--",
                rootPath,
            ],
            workingCopyPath: rootPath
        )
        let request = SubversionCLIInvocationRequest(
            executablePath: "svn",
            arguments: arguments,
            workingDirectory: rootPath
        )
        let result = try await run(request)
        return parseUpdateResult(result.stdout, rootPath: rootPath)
    }

    public func revert(
        paths: [String],
        recursive: Bool = true,
        removeAdded: Bool = false,
        context: SVNCommandContext
    ) async throws -> SVNRevertResult {
        let normalizedPaths = Array(Set(paths)).sorted()
        guard let firstPath = normalizedPaths.first else {
            return SVNRevertResult(
                requestedPaths: [],
                revertedPaths: [],
                removeAdded: removeAdded,
                rawOutput: ""
            )
        }

        var arguments = ["revert", "--depth", recursive ? "infinity" : "empty"]
        if removeAdded {
            arguments.append("--remove-added")
        }
        arguments += ["--"] + normalizedPaths

        let request = SubversionCLIInvocationRequest(
            executablePath: "svn",
            arguments: arguments,
            workingDirectory: (firstPath as NSString).deletingLastPathComponent
        )
        let result = try await run(request)
        return parseRevertResult(
            result.stdout,
            requestedPaths: normalizedPaths,
            removeAdded: removeAdded
        )
    }

    public func cleanup(
        rootPath: String,
        context: SVNCommandContext
    ) async throws -> SVNCleanupResult {
        let request = SubversionCLIInvocationRequest(
            executablePath: "svn",
            arguments: ["cleanup", "--", rootPath],
            workingDirectory: rootPath
        )
        let result = try await run(request)
        return SVNCleanupResult(rootPath: rootPath, rawOutput: result.stdout)
    }

    public func resolve(
        paths: [String],
        accept: String = "working",
        recursive: Bool = true,
        context: SVNCommandContext
    ) async throws -> SVNResolveResult {
        let normalizedPaths = Array(Set(paths)).sorted()
        guard let firstPath = normalizedPaths.first else {
            return SVNResolveResult(
                requestedPaths: [],
                resolvedPaths: [],
                acceptStrategy: accept,
                rawOutput: ""
            )
        }

        var arguments = ["resolve", "--accept", accept]
        arguments += ["--depth", recursive ? "infinity" : "empty"]
        arguments += ["--"] + normalizedPaths

        let request = SubversionCLIInvocationRequest(
            executablePath: "svn",
            arguments: arguments,
            workingDirectory: (firstPath as NSString).deletingLastPathComponent
        )
        let result = try await run(request)
        return parseResolveResult(
            result.stdout,
            requestedPaths: normalizedPaths,
            accept: accept
        )
    }

    public func checkout(
        repositoryURL: String,
        destinationPath: String,
        depth: SVNDepth = .infinity,
        context: SVNCommandContext
    ) async throws -> SVNCheckoutResult {
        let arguments = await authenticatedArguments(
            [
                "checkout",
                "--depth",
                depth.rawValue,
                "--",
                repositoryURL,
                destinationPath,
            ],
            repositoryURL: repositoryURL
        )
        let request = SubversionCLIInvocationRequest(
            executablePath: "svn",
            arguments: arguments,
            workingDirectory: (destinationPath as NSString).deletingLastPathComponent
        )
        let result = try await run(request)
        return SVNCheckoutResult(
            repositoryURL: repositoryURL,
            destinationPath: destinationPath,
            revision: parseResultingRevision(fromText: result.stdout),
            rawOutput: result.stdout
        )
    }

    public func importPath(
        sourcePath: String,
        repositoryURL: String,
        message: String,
        context: SVNCommandContext
    ) async throws -> SVNImportResult {
        let arguments = await authenticatedArguments(
            [
                "import",
                "-m",
                message,
                "--",
                sourcePath,
                repositoryURL,
            ],
            repositoryURL: repositoryURL
        )
        let request = SubversionCLIInvocationRequest(
            executablePath: "svn",
            arguments: arguments,
            workingDirectory: (sourcePath as NSString).deletingLastPathComponent
        )
        let result = try await run(request)
        return SVNImportResult(
            sourcePath: sourcePath,
            repositoryURL: repositoryURL,
            revision: parseCommittedRevision(fromText: result.stdout),
            rawOutput: result.stdout
        )
    }

    public func export(
        source: String,
        destinationPath: String,
        force: Bool = true,
        context: SVNCommandContext
    ) async throws -> SVNExportResult {
        var arguments = ["export"]
        if force {
            arguments.append("--force")
        }
        arguments += ["--", source, destinationPath]

        let request = SubversionCLIInvocationRequest(
            executablePath: "svn",
            arguments: arguments,
            workingDirectory: (destinationPath as NSString).deletingLastPathComponent
        )
        let result = try await run(request)
        return SVNExportResult(
            source: source,
            destinationPath: destinationPath,
            rawOutput: result.stdout
        )
    }

    public func switchWorkingCopy(
        workingCopyPath: String,
        repositoryURL: String,
        depth: SVNDepth = .infinity,
        context: SVNCommandContext
    ) async throws -> SVNSwitchResult {
        let arguments = await authenticatedArguments(
            [
                "switch",
                "--depth",
                depth.rawValue,
                "--",
                repositoryURL,
                workingCopyPath,
            ],
            workingCopyPath: workingCopyPath,
            repositoryURL: repositoryURL
        )
        let request = SubversionCLIInvocationRequest(
            executablePath: "svn",
            arguments: arguments,
            workingDirectory: workingCopyPath
        )
        let result = try await run(request)
        return SVNSwitchResult(
            workingCopyPath: workingCopyPath,
            repositoryURL: repositoryURL,
            revision: parseResultingRevision(fromText: result.stdout),
            rawOutput: result.stdout
        )
    }

    public func relocate(
        workingCopyPath: String,
        fromURL: String,
        toURL: String,
        context: SVNCommandContext
    ) async throws -> SVNRelocateResult {
        let request = SubversionCLIInvocationRequest(
            executablePath: "svn",
            arguments: [
                "relocate",
                "--",
                fromURL,
                toURL,
                workingCopyPath,
            ],
            workingDirectory: workingCopyPath
        )
        let result = try await run(request)
        return SVNRelocateResult(
            workingCopyPath: workingCopyPath,
            fromURL: fromURL,
            toURL: toURL,
            rawOutput: result.stdout
        )
    }

    private func run(_ request: SubversionCLIInvocationRequest) async throws -> SubversionCLIInvocationResult {
        let result = try await runner.run(request)
        guard result.exitCode == 0 else {
            throw SubversionRepositoryInspectorError.commandFailed(
                arguments: request.arguments,
                exitCode: result.exitCode,
                stderr: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return result
    }

    private func authenticatedArguments(
        _ arguments: [String],
        workingCopyPath: String? = nil,
        repositoryURL: String? = nil
    ) async -> [String] {
        guard let command = arguments.first else {
            return arguments
        }

        let authArgs: [String]
        if let repositoryURL,
           let credentials = MacSVNSVNConfigManager.storedCredentials(matchingRepositoryURL: repositoryURL)
        {
            authArgs = [
                "--username",
                credentials.username,
                "--password",
                credentials.password,
                "--non-interactive",
            ]
        } else if let workingCopyPath {
            authArgs = await macSVNAuthenticationArguments(forWorkingCopyPath: workingCopyPath)
        } else {
            return arguments
        }

        guard !authArgs.isEmpty else {
            return arguments
        }

        return [command] + authArgs + Array(arguments.dropFirst())
    }

    private func parseUpdateResult(_ stdout: String, rootPath: String) -> SVNUpdateResult {
        let lines = stdout.split(separator: "\n").map(String.init)
        var updatedPaths: [String] = []
        var hasConflicts = false
        var resultingRevision: Int64?

        for line in lines {
            if let parsedPath = parseUpdatedPath(from: line) {
                updatedPaths.append(parsedPath.path)
                hasConflicts = hasConflicts || parsedPath.hasConflict
                continue
            }

            if let parsedRevision = parseResultingRevision(from: line) {
                resultingRevision = parsedRevision
            }
        }

        return SVNUpdateResult(
            rootPath: rootPath,
            updatedPaths: updatedPaths,
            resultingRevision: resultingRevision,
            hasConflicts: hasConflicts,
            rawOutput: stdout
        )
    }

    private func parseRevertResult(
        _ stdout: String,
        requestedPaths: [String],
        removeAdded: Bool
    ) -> SVNRevertResult {
        let revertedPaths = stdout
            .split(separator: "\n")
            .compactMap { parseRevertedPath(from: String($0)) }

        return SVNRevertResult(
            requestedPaths: requestedPaths,
            revertedPaths: revertedPaths.isEmpty ? requestedPaths : revertedPaths,
            removeAdded: removeAdded,
            rawOutput: stdout
        )
    }

    private func parseUpdatedPath(from line: String) -> (path: String, hasConflict: Bool)? {
        guard line.count > 5 else {
            return nil
        }

        let prefix = String(line.prefix(4))
        let statusCharacters = Set(prefix.filter { !$0.isWhitespace })
        let supported = Set("ADUCGER")

        guard !statusCharacters.isEmpty, statusCharacters.isSubset(of: supported) else {
            return nil
        }

        let path = String(line.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            return nil
        }

        return (path, prefix.contains("C"))
    }

    private func parseResultingRevision(from line: String) -> Int64? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = [
            "Updated to revision ",
            "At revision ",
            "Checked out revision ",
            "Exported revision ",
        ]

        guard let prefix = prefixes.first(where: { trimmed.hasPrefix($0) }) else {
            return nil
        }

        let revisionPortion = trimmed
            .dropFirst(prefix.count)
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))

        return Int64(revisionPortion)
    }

    private func parseResultingRevision(fromText text: String) -> Int64? {
        for line in text.split(separator: "\n").map(String.init).reversed() {
            if let revision = parseResultingRevision(from: line) {
                return revision
            }
        }

        return nil
    }

    private func parseCommittedRevision(fromText text: String) -> Int64? {
        let marker = "Committed revision "
        guard let markerRange = text.range(of: marker, options: .backwards) else {
            return nil
        }

        let revisionPortion = text[markerRange.upperBound...]
            .trimmingCharacters(in: CharacterSet(charactersIn: ". \n\r\t"))
        return Int64(revisionPortion)
    }

    private func parseRevertedPath(from line: String) -> String? {
        let prefix = "Reverted '"
        guard line.hasPrefix(prefix), line.hasSuffix("'") else {
            return nil
        }

        return String(line.dropFirst(prefix.count).dropLast())
    }

    private func parseResolveResult(
        _ stdout: String,
        requestedPaths: [String],
        accept: String
    ) -> SVNResolveResult {
        let resolvedPaths = stdout
            .split(separator: "\n")
            .compactMap { parseResolvedPath(from: String($0)) }

        return SVNResolveResult(
            requestedPaths: requestedPaths,
            resolvedPaths: resolvedPaths.isEmpty ? requestedPaths : resolvedPaths,
            acceptStrategy: accept,
            rawOutput: stdout
        )
    }

    private func parseResolvedPath(from line: String) -> String? {
        guard
            let firstQuote = line.firstIndex(of: "'"),
            let lastQuote = line.lastIndex(of: "'"),
            firstQuote < lastQuote,
            line.contains("marked as resolved")
        else {
            return nil
        }

        return String(line[line.index(after: firstQuote)..<lastQuote])
    }

    public func rollback(
        paths: [String],
        revision: Int64,
        recursive: Bool = true,
        context: SVNCommandContext
    ) async throws -> SVNRevertResult {
        let normalizedPaths = Array(Set(paths)).sorted()
        guard let firstPath = normalizedPaths.first else {
            return SVNRevertResult(
                requestedPaths: [],
                revertedPaths: [],
                removeAdded: false,
                rawOutput: ""
            )
        }

        var arguments = ["revert", "-r", String(revision), "--depth", recursive ? "infinity" : "empty"]
        arguments += ["--"] + normalizedPaths

        let request = SubversionCLIInvocationRequest(
            executablePath: "svn",
            arguments: arguments,
            workingDirectory: (firstPath as NSString).deletingLastPathComponent
        )
        let result = try await run(request)
        return parseRevertResult(
            result.stdout,
            requestedPaths: normalizedPaths,
            removeAdded: false
        )
    }
}
