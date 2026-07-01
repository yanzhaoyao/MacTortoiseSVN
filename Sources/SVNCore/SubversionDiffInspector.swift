import Foundation

public struct SVNDiffPreview: Sendable, Hashable, Codable {
    public var targetPath: String
    public var rawText: String
    public var wasTruncated: Bool

    public var isEmpty: Bool {
        rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public init(targetPath: String, rawText: String, wasTruncated: Bool = false) {
        self.targetPath = targetPath
        self.rawText = rawText
        self.wasTruncated = wasTruncated
    }
}

public enum SubversionDiffInspectorError: Error, Sendable, LocalizedError, Equatable {
    case commandFailed(arguments: [String], exitCode: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case let .commandFailed(arguments, exitCode, stderr):
            let stderrSuffix = stderr.isEmpty ? "" : ", stderr: \(stderr)"
            return "svn command failed: svn \(arguments.joined(separator: " ")) (exit: \(exitCode))\(stderrSuffix)"
        }
    }
}

public actor SubversionDiffInspector {
    private let runner: any SubversionCommandRunning
    private var workingCopyCache: [String: SVNDiffPreview] = [:]
    private var revisionCache: [String: SVNDiffPreview] = [:]
    private let maxPreviewCharacters = 48_000
    private let maxCachedEntries = 32

    public init() {
        self.runner = ProcessSubversionRunner()
    }

    init(runner: any SubversionCommandRunning) {
        self.runner = runner
    }

    public func workingCopyDiff(
        at path: String,
        workingCopyRoot: String? = nil,
        context: SVNCommandContext
    ) async throws -> SVNDiffPreview {
        if let cacheKey = workingCopyCacheKey(for: path),
           let cached = workingCopyCache[cacheKey]
        {
            return cached
        }

        let request = SubversionCLIInvocationRequest(
            executablePath: "svn",
            arguments: ["diff", "--", path],
            workingDirectory: workingCopyRoot ?? fallbackWorkingDirectory(for: path)
        )
        let result = try await runner.run(request)

        guard result.exitCode == 0 else {
            throw SubversionDiffInspectorError.commandFailed(
                arguments: request.arguments,
                exitCode: result.exitCode,
                stderr: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        let preview = makePreview(targetPath: path, rawText: result.stdout)
        if let cacheKey = workingCopyCacheKey(for: path) {
            storeWorkingCopyPreview(preview, for: cacheKey)
        }
        return preview
    }

    public func revisionDiff(
        at rootPath: String,
        revision: Int64,
        context: SVNCommandContext
    ) async throws -> SVNDiffPreview {
        let cacheKey = "\(rootPath)\0\(revision)"
        if let cached = revisionCache[cacheKey] {
            return cached
        }

        let request = SubversionCLIInvocationRequest(
            executablePath: "svn",
            arguments: ["diff", "-c", String(revision), "--", rootPath],
            workingDirectory: rootPath
        )
        let result = try await runner.run(request)

        guard result.exitCode == 0 else {
            throw SubversionDiffInspectorError.commandFailed(
                arguments: request.arguments,
                exitCode: result.exitCode,
                stderr: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        let preview = makePreview(targetPath: "r\(revision)", rawText: result.stdout)
        storeRevisionPreview(preview, for: cacheKey)
        return preview
    }

    private func makePreview(targetPath: String, rawText: String) -> SVNDiffPreview {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxPreviewCharacters else {
            return SVNDiffPreview(targetPath: targetPath, rawText: rawText)
        }

        let truncated = String(trimmed.prefix(maxPreviewCharacters))
            + "\n\n… [diff truncated for preview performance]"
        return SVNDiffPreview(targetPath: targetPath, rawText: truncated, wasTruncated: true)
    }

    private func workingCopyCacheKey(for path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else {
            return nil
        }

        let mtime = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        let size = values.fileSize ?? 0
        return "\(path)\0\(mtime)\0\(size)"
    }

    private func storeWorkingCopyPreview(_ preview: SVNDiffPreview, for cacheKey: String) {
        workingCopyCache[cacheKey] = preview
        trimCache(&workingCopyCache)
    }

    private func storeRevisionPreview(_ preview: SVNDiffPreview, for cacheKey: String) {
        revisionCache[cacheKey] = preview
        trimCache(&revisionCache)
    }

    private func trimCache(_ cache: inout [String: SVNDiffPreview]) {
        guard cache.count > maxCachedEntries else {
            return
        }

        let overflow = cache.count - maxCachedEntries
        for key in cache.keys.prefix(overflow) {
            cache.removeValue(forKey: key)
        }
    }

    private func fallbackWorkingDirectory(for path: String) -> String {
        let parentDirectory = (path as NSString).deletingLastPathComponent
        return parentDirectory.isEmpty ? path : parentDirectory
    }
}
