import Darwin
import Foundation

enum ClaudeSignInError: Error, Equatable {
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

    static func signIn(callbackMessage: String? = nil, executableURL: URL? = nil, timeout: Duration = .seconds(330)) async throws -> String {
        try await execute(callbackMessage: callbackMessage, executableURL: executableURL, timeout: timeout)
    }

    private static func execute(callbackMessage: String?, executableURL: URL?, timeout: Duration) async throws -> String {
        let process = Process()
        process.executableURL = try executableURL ?? SharedCoreClient.executableURL()
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

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

        let request = SignInRequest(protocolVersion: SharedCoreClient.protocolVersion, command: "signInClaude", callbackMessage: callbackMessage)
        input.fileHandleForWriting.write(try JSONEncoder().encode(request))
        try input.fileHandleForWriting.close()

        let deadline = ContinuousClock.now + timeout
        while process.isRunning {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else {
                throw ClaudeSignInError.timedOut
            }

            try await Task.sleep(for: .milliseconds(200))
        }

        try Task.checkCancellation()
        guard process.terminationStatus == 0 else {
            throw ClaudeSignInError.failed
        }

        return try SharedCoreClient.decodeResponse(output.fileHandleForReading.readDataToEndOfFile(), as: String.self)
    }

    private struct SignInRequest: Encodable {
        let protocolVersion: Int
        let command: String
        let callbackMessage: String?
    }
}

@MainActor
struct ClaudeRecoveryClient {
    var signIn: (String) async throws -> String
    var refreshSession: (String, Date) async throws -> ClaudeSessionResult = { credentials, now in
        try await SharedCoreClient().refreshClaudeSession(credentialsJSON: credentials, now: now)
    }

    static let live = ClaudeRecoveryClient(
        signIn: { try await ClaudeSignIn.signIn(callbackMessage: $0) }
    )
}
