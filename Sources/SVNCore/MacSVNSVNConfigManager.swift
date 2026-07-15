import Foundation

public enum MacSVNSVNConfigManager {
    public static let appGroupIdentifier = "group.com.morningstar.MacTortoiseSVN"

    public static func configDirectoryURL() -> URL {
        if let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) {
            return appGroupURL
                .appending(path: "MacTortoiseSVN", directoryHint: .isDirectory)
                .appending(path: ".subversion", directoryHint: .isDirectory)
        }

        return URL(fileURLWithPath: macSVNRealUserHomeDirectory())
            .appending(path: ".subversion", directoryHint: .isDirectory)
    }

    public static func prepareConfigDirectory() {
        let fileManager = FileManager.default
        let configURL = configDirectoryURL()
        let authDirectory = configURL.appending(path: "auth", directoryHint: .isDirectory)

        try? fileManager.createDirectory(at: authDirectory, withIntermediateDirectories: true)

        let configFileURL = configURL.appending(path: "config")
        if !fileManager.fileExists(atPath: configFileURL.path) {
            let contents = """
            [auth]
            password-stores =
            store-passwords = yes
            store-auth-creds = yes

            """
            try? contents.write(to: configFileURL, atomically: true, encoding: .utf8)
        }

        let userServersURL = URL(fileURLWithPath: macSVNRealUserHomeDirectory())
            .appending(path: ".subversion/servers")
        let appServersURL = configURL.appending(path: "servers")
        if !fileManager.fileExists(atPath: appServersURL.path),
           fileManager.fileExists(atPath: userServersURL.path)
        {
            try? fileManager.copyItem(at: userServersURL, to: appServersURL)
        }
    }

    public static func importedUsername(matchingRepositoryURL repositoryURL: String) -> String? {
        let candidates = [
            configDirectoryURL().appending(path: "auth"),
            URL(fileURLWithPath: macSVNRealUserHomeDirectory()).appending(path: ".subversion/auth"),
        ]

        for authDirectory in candidates {
            if let username = parseCachedUsername(
                in: authDirectory.appending(path: "svn.simple", directoryHint: .isDirectory),
                matchingRepositoryURL: repositoryURL
            ) {
                return username
            }
        }

        return nil
    }

    public static func hasStoredCredentials(matchingRepositoryURL repositoryURL: String) -> Bool {
        if storedCredentials(matchingRepositoryURL: repositoryURL) != nil {
            return true
        }

        prepareConfigDirectory()
        let authDirectory = configDirectoryURL().appending(path: "auth")
        return hasFileBasedCredentials(
            in: authDirectory.appending(path: "svn.simple", directoryHint: .isDirectory),
            matchingRepositoryURL: repositoryURL
        )
    }

    public static func storedCredentials(
        matchingRepositoryURL repositoryURL: String
    ) -> (username: String, password: String)? {
        guard let credential = loadStoredCredentialsMap()[credentialKey(for: repositoryURL)] else {
            return nil
        }
        return (credential.username, credential.password)
    }

    public static func saveStoredCredentials(
        username: String,
        password: String,
        repositoryURL: String
    ) {
        prepareConfigDirectory()
        var credentials = loadStoredCredentialsMap()
        credentials[credentialKey(for: repositoryURL)] = MacSVNSVNStoredCredential(
            username: username,
            password: password
        )
        persistStoredCredentials(credentials)
    }

    private static let storedCredentialsDefaultsKey = "MacSVNSVNStoredCredentials"

    private struct MacSVNSVNStoredCredential: Codable, Hashable {
        var username: String
        var password: String
    }

    private static func credentialKey(for repositoryURL: String) -> String {
        hostCandidate(from: repositoryURL) ?? repositoryURL
    }

    private static func loadStoredCredentialsMap() -> [String: MacSVNSVNStoredCredential] {
        if
            let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier),
            let data = sharedDefaults.data(forKey: storedCredentialsDefaultsKey),
            let credentials = try? JSONDecoder().decode([String: MacSVNSVNStoredCredential].self, from: data)
        {
            return credentials
        }

        return [:]
    }

    private static func persistStoredCredentials(_ credentials: [String: MacSVNSVNStoredCredential]) {
        guard
            let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier),
            let data = try? JSONEncoder().encode(credentials)
        else {
            return
        }
        sharedDefaults.set(data, forKey: storedCredentialsDefaultsKey)
    }

    private static func hasFileBasedCredentials(
        in authDirectory: URL,
        matchingRepositoryURL repositoryURL: String
    ) -> Bool {
        guard
            let host = URL(string: repositoryURL)?.host ?? hostCandidate(from: repositoryURL),
            let fileNames = try? FileManager.default.contentsOfDirectory(atPath: authDirectory.path)
        else {
            return false
        }

        for fileName in fileNames {
            let fileURL = authDirectory.appending(path: fileName)
            guard
                let content = try? String(contentsOf: fileURL, encoding: .utf8),
                content.contains(host)
            else {
                continue
            }

            if content.contains("passtype\nV 8\nkeychain") {
                continue
            }

            if parseField(named: "username", fromSimpleAuthCache: content) != nil,
               parseField(named: "password", fromSimpleAuthCache: content) != nil
            {
                return true
            }
        }

        return false
    }

    private static func hostCandidate(from repositoryURL: String) -> String? {
        if let host = URL(string: repositoryURL)?.host {
            return host
        }

        if repositoryURL.contains("://"), let host = repositoryURL.split(separator: "/").dropFirst(2).first {
            return String(host).split(separator: ":").first.map(String.init)
        }

        return nil
    }

    private static func parseCachedUsername(
        in authDirectory: URL,
        matchingRepositoryURL repositoryURL: String
    ) -> String? {
        guard
            let host = URL(string: repositoryURL)?.host,
            let fileNames = try? FileManager.default.contentsOfDirectory(atPath: authDirectory.path)
        else {
            return nil
        }

        for fileName in fileNames {
            let fileURL = authDirectory.appending(path: fileName)
            guard
                let content = try? String(contentsOf: fileURL, encoding: .utf8),
                content.contains(host)
            else {
                continue
            }

            if let username = parseField(named: "username", fromSimpleAuthCache: content) {
                return username
            }
        }

        return nil
    }

    private static func parseField(named fieldName: String, fromSimpleAuthCache content: String) -> String? {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var index = 0
        while index < lines.count {
            defer { index += 1 }
            guard lines[index] == fieldName, index + 2 < lines.count else {
                continue
            }
            let valueLine = lines[index + 2]
            return valueLine.isEmpty ? nil : valueLine
        }
        return nil
    }

    private static func parseUsername(fromSimpleAuthCache content: String) -> String? {
        parseField(named: "username", fromSimpleAuthCache: content)
    }
}

public func macSVNWorkingCopyRepositoryURL(workingCopyPath: String) async throws -> String {
    let runner = ProcessSubversionRunner()
    let result = try await runner.run(
        SubversionCLIInvocationRequest(
            executablePath: "svn",
            arguments: ["info", "--show-item", "url", workingCopyPath],
            workingDirectory: workingCopyPath
        )
    )

    guard result.exitCode == 0 else {
        throw SubversionRepositoryInspectorError.commandFailed(
            arguments: ["info", "--show-item", "url", workingCopyPath],
            exitCode: result.exitCode,
            stderr: result.stderr
        )
    }

    let url = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !url.isEmpty else {
        throw SubversionRepositoryInspectorError.invalidResponse("Missing repository URL.")
    }
    return url
}

public func macSVNIsAuthenticationError(_ error: Error) -> Bool {
    let message: String
    if let localized = error as? LocalizedError, let description = localized.errorDescription {
        message = description
    } else {
        message = String(describing: error)
    }

    return message.contains("E215004")
        || message.contains("E170001")
        || message.contains("Authentication failed")
        || message.contains("Unable to authorize")
        || message.contains("No more credentials")
}

public func macSVNAuthenticationArguments(
    forWorkingCopyPath path: String,
    repositoryURL: String? = nil
) async -> [String] {
    let resolvedURL: String?
    if let repositoryURL {
        resolvedURL = repositoryURL
    } else {
        resolvedURL = try? await macSVNWorkingCopyRepositoryURL(workingCopyPath: path)
    }

    guard
        let resolvedURL,
        let credentials = MacSVNSVNConfigManager.storedCredentials(matchingRepositoryURL: resolvedURL)
    else {
        return []
    }

    return [
        "--username",
        credentials.username,
        "--password",
        credentials.password,
        "--non-interactive",
    ]
}

public func macSVNStoreCredentials(
    username: String,
    password: String,
    workingCopyPath: String
) async throws {
    MacSVNSVNConfigManager.prepareConfigDirectory()

    let repositoryURL = try await macSVNWorkingCopyRepositoryURL(workingCopyPath: workingCopyPath)
    let runner = ProcessSubversionRunner()
    let result = try await runner.run(
        SubversionCLIInvocationRequest(
            executablePath: "svn",
            arguments: [
                "info",
                "--username",
                username,
                "--password",
                password,
                "--non-interactive",
                repositoryURL,
            ],
            workingDirectory: workingCopyPath
        )
    )

    guard result.exitCode == 0 else {
        throw SubversionRepositoryInspectorError.commandFailed(
            arguments: ["info", repositoryURL],
            exitCode: result.exitCode,
            stderr: result.stderr
        )
    }

    MacSVNSVNConfigManager.saveStoredCredentials(
        username: username,
        password: password,
        repositoryURL: repositoryURL
    )
}
