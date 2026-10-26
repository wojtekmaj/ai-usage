import Foundation
import Testing
@testable import AiUsageApp

@MainActor
struct ClaudeSignInTests {
    @Test
    func runsSharedCoreSignInAndWaitsForCredentials() async throws {
        let executable = try makeExecutable("""
        read request
        case "$request" in
            *'"command":"signInClaude"'*) ;;
            *) exit 1 ;;
        esac
        echo '{"protocolVersion":1,"ok":true,"data":"credentials"}'
        """)
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }

        let credentials = try await ClaudeSignIn.signIn(executableURL: executable, timeout: .seconds(5))

        #expect(credentials == "credentials")
    }

    @Test
    func reportsFailedSignIn() async throws {
        let executable = try makeExecutable("exit 1")
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }

        await #expect(throws: ClaudeSignInError.failed) {
            _ = try await ClaudeSignIn.signIn(executableURL: executable, timeout: .seconds(5))
        }
    }

    @Test
    func timesOutWhenSignInDoesNotFinish() async throws {
        let executable = try makeExecutable("exec /bin/sleep 30")
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }

        await #expect(throws: ClaudeSignInError.timedOut) {
            _ = try await ClaudeSignIn.signIn(executableURL: executable, timeout: .milliseconds(100))
        }
    }

    @Test
    func cancelsPendingSignIn() async throws {
        let executable = try makeExecutable("exec /bin/sleep 30")
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let signIn = Task {
            _ = try await ClaudeSignIn.signIn(executableURL: executable)
        }
        try await Task.sleep(for: .milliseconds(100))
        signIn.cancel()

        await #expect(throws: CancellationError.self) {
            try await signIn.value
        }
    }

    private func makeExecutable(_ script: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("ai-usage-core")
        try ("#!/bin/sh\n" + script + "\n").write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

        return executable
    }
}
