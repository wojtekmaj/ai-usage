import Foundation
import Testing
@testable import AiUsageApp

@MainActor
struct ClaudeSignInTests {
    @Test
    func runsClaudeLoginAndWaitsForCompletion() async throws {
        let executable = try makeExecutable("test \"$#\" -eq 2 && test \"$1\" = auth && test \"$2\" = login")
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }

        try await ClaudeSignIn.signIn(executableURL: executable, timeout: .seconds(5))
    }

    @Test
    func reportsFailedSignIn() async throws {
        let executable = try makeExecutable("exit 1")
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }

        await #expect(throws: ClaudeSignInError.failed) {
            try await ClaudeSignIn.signIn(executableURL: executable, timeout: .seconds(5))
        }
    }

    @Test
    func timesOutWhenSignInDoesNotFinish() async throws {
        let executable = try makeExecutable("exec /bin/sleep 30")
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }

        await #expect(throws: ClaudeSignInError.timedOut) {
            try await ClaudeSignIn.signIn(executableURL: executable, timeout: .milliseconds(100))
        }
    }

    @Test
    func cancelsPendingSignIn() async throws {
        let executable = try makeExecutable("exec /bin/sleep 30")
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let signIn = Task {
            try await ClaudeSignIn.signIn(executableURL: executable)
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
        let executable = directory.appendingPathComponent("claude")
        try ("#!/bin/sh\n" + script + "\n").write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

        return executable
    }
}
