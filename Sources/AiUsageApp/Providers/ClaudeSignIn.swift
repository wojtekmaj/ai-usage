import Darwin
import Foundation

enum ClaudeSignInError: Error, Equatable {
    case notInstalled
    case failed
    case timedOut
}

@MainActor
enum ClaudeSignIn {
    private static var activeProcess: Process?

    static func cancelActiveProcess() {
        if let process = activeProcess, process.isRunning {
            process.terminate()
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }

    @discardableResult
    static func renewSession(executableURL: URL? = nil, timeout: Duration = .seconds(30)) async throws -> Int32 {
        // Credential verification decides whether startup renewed the session
        try await execute(
            executableURL: executableURL,
            arguments: [
                "--print", "--tools", "", "--no-session-persistence",
                "--setting-sources", "", "--settings", "{\"disableAllHooks\":true}",
                "--strict-mcp-config", "--mcp-config", "{\"mcpServers\":{}}",
                "--disable-slash-commands",
            ],
            closeInput: true,
            timeout: timeout
        )
    }

    static func signIn(executableURL: URL? = nil, timeout: Duration = .seconds(600)) async throws {
        let status = try await execute(executableURL: executableURL, arguments: ["auth", "login"], closeInput: false, timeout: timeout)
        guard status == 0 else {
            throw ClaudeSignInError.failed
        }
    }

    private static func execute(executableURL: URL?, arguments: [String], closeInput: Bool, timeout: Duration) async throws -> Int32 {
        guard let executableURL = executableURL ?? findExecutable() else {
            throw ClaudeSignInError.notInstalled
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = executableURL.deletingLastPathComponent().path + ":/opt/homebrew/bin:/usr/local/bin:" + (environment["PATH"] ?? "/usr/bin:/bin")
        process.environment = environment
        let temporaryDirectory = closeInput
            ? FileManager.default.temporaryDirectory.appendingPathComponent("ai-usage-claude-" + UUID().uuidString)
            : nil
        if let temporaryDirectory {
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        }
        defer {
            if let temporaryDirectory {
                try? FileManager.default.removeItem(at: temporaryDirectory)
            }
        }
        process.currentDirectoryURL = temporaryDirectory ?? FileManager.default.homeDirectoryForCurrentUser
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        if closeInput {
            try input.fileHandleForWriting.close()
        }
        try Task.checkCancellation()
        try process.run()
        activeProcess = process
        defer {
            activeProcess = nil
            try? input.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
        }

        let deadline = ContinuousClock.now + timeout
        while process.isRunning {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else {
                throw ClaudeSignInError.timedOut
            }

            try await Task.sleep(for: .milliseconds(200))
        }

        try Task.checkCancellation()
        return process.terminationStatus
    }

    private static func findExecutable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)

        return paths.map { URL(fileURLWithPath: $0).appendingPathComponent("claude") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

@MainActor
struct ClaudeRecoveryClient {
    var renewSession: () async throws -> Int32
    var signIn: () async throws -> Void
    var refreshUsage: (String?, Date) async throws -> ProviderSnapshot

    static let live = ClaudeRecoveryClient(
        renewSession: { try await ClaudeSignIn.renewSession() },
        signIn: { try await ClaudeSignIn.signIn() },
        refreshUsage: { credentials, now in
            try await SharedCoreClient().refreshClaude(claudeCredentialsJSON: credentials, now: now)
        }
    )
}
