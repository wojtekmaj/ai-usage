import Foundation
import Testing
@testable import AiUsageApp

@MainActor
struct ClaudeRecoveryTests {
    @Test
    func signsInWithAnIndependentSessionAndVerifiesUsage() async {
        var savedCredentials: String?
        var localReads = 0
        let session = ClaudeSessionStore(load: { savedCredentials }, save: { savedCredentials = $0 })
        let credentials = ClaudeOAuthCredentialsStore {
            localReads += 1
            throw ClaudeOAuthCredentialsError.keychainError(errSecInteractionNotAllowed)
        }
        let client = ClaudeRecoveryClient(
            signIn: { _ in "new-session" },
            refreshSession: { json, _ in
                #expect(json == "new-session")

                return ClaudeSessionResult(credentialsJson: "renewed-session", snapshot: Self.snapshot(authState: .authenticated))
            }
        )

        await withEnvironment(credentials: credentials, session: session, client: client) { environment in
            await environment.reconnectClaude()?.value

            #expect(savedCredentials == "renewed-session")
            #expect(localReads == 0)
            #expect(environment.hasClaudeSession)
            #expect(environment.snapshot(for: .claude)?.fetchState == .ok)
            #expect(environment.claudeSignInError == nil)
            #expect(environment.isReconnectingClaude == false)
        }
    }

    @Test
    func keepsNetworkFailureSeparateFromSignIn() async {
        let client = ClaudeRecoveryClient(
            signIn: { _ in "session" },
            refreshSession: { credentials, _ in
                ClaudeSessionResult(credentialsJson: credentials, snapshot: Self.snapshot(authState: .configured))
            }
        )

        await withEnvironment(client: client) { environment in
            await environment.reconnectClaude()?.value

            #expect(environment.snapshot(for: .claude)?.fetchState == .failed)
            #expect(environment.claudeSignInError == nil)
            #expect(environment.isReconnectingClaude == false)
        }
    }

    @Test
    func reportsRejectedCredentialsAfterSignIn() async {
        let client = ClaudeRecoveryClient(
            signIn: { _ in "session" },
            refreshSession: { credentials, _ in
                ClaudeSessionResult(credentialsJson: credentials, snapshot: Self.snapshot(authState: .signedOut))
            }
        )

        await withEnvironment(client: client) { environment in
            await environment.reconnectClaude()?.value

            #expect(environment.claudeSignInError == .claudeSignInFailed)
            #expect(environment.isReconnectingClaude == false)
        }
    }

    @Test
    func reportsVerificationFailure() async {
        let client = ClaudeRecoveryClient(
            signIn: { _ in "session" },
            refreshSession: { _, _ in throw SharedCoreError.invalidResponse("Invalid response") }
        )

        await withEnvironment(client: client) { environment in
            await environment.reconnectClaude()?.value

            #expect(environment.claudeSignInError == .claudeSignInFailed)
            #expect(environment.isReconnectingClaude == false)
        }
    }

    @Test
    func cancelsPendingBrowserSignInAndPreventsDuplicateReconnects() async {
        let (started, continuation) = AsyncStream<Void>.makeStream()
        let client = ClaudeRecoveryClient(
            signIn: { _ in
                continuation.yield(())
                continuation.finish()
                try await Task.sleep(for: .seconds(30))

                return "session"
            }
        )

        await withEnvironment(client: client) { environment in
            let task = environment.reconnectClaude()
            for await _ in started {
                #expect(environment.claudeReconnectPhase == .signingIn)
                #expect(environment.reconnectClaude() == nil)
                environment.cancelClaudeSignIn()
            }
            await task?.value

            #expect(environment.claudeSignInError == nil)
            #expect(environment.isReconnectingClaude == false)
        }
    }

    private func withEnvironment(
        credentials: ClaudeOAuthCredentialsStore = ClaudeOAuthCredentialsStore(rawDataLoader: { Data("{}".utf8) }),
        session: ClaudeSessionStore = ClaudeSessionStore(load: { nil }, save: { _ in }),
        client: ClaudeRecoveryClient,
        body: (AppEnvironment) async -> Void
    ) async {
        let suiteName = "ClaudeRecoveryTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let environment = AppEnvironment(
            settings: SettingsStore(defaults: defaults),
            claudeCredentials: credentials,
            claudeSession: session,
            usageStore: UsageStore(defaults: defaults),
            logStore: LogStore(defaults: defaults),
            claudeRecoveryClient: client
        )

        await body(environment)
    }

    private static func snapshot(authState: ProviderAuthState) -> ProviderSnapshot {
        ProviderSnapshot(
            provider: .claude,
            authState: authState,
            fetchState: authState == .authenticated ? .ok : .failed,
            fetchedAtUTC: .now,
            metrics: [],
            errorDescription: nil,
            sourceDescription: nil
        )
    }
}
