import Foundation
import Testing
@testable import AiUsageApp

@MainActor
struct ClaudeRecoveryTests {
    @Test
    func verifiesBackgroundRenewalWithoutStartingBrowserSignIn() async {
        var signInCalls = 0
        var renewalCalls = 0
        var credentialsJSON = "{}"
        let credentials = ClaudeOAuthCredentialsStore { Data(credentialsJSON.utf8) }
        _ = try? credentials.rawJSONString()
        let client = ClaudeRecoveryClient(
            renewSession: {
                renewalCalls += 1
                credentialsJSON = "{\"claudeAiOauth\":{\"accessToken\":\"renewed-token\"}}"

                return 1
            },
            signIn: { signInCalls += 1 },
            refreshUsage: { json, _ in
                #expect(json == credentialsJSON)

                return Self.snapshot(authState: .authenticated)
            }
        )

        await withEnvironment(credentials: credentials, client: client) { environment in
            await environment.reconnectClaude()?.value

            #expect(renewalCalls == 1)
            #expect(signInCalls == 0)
            #expect(environment.snapshot(for: .claude)?.fetchState == .ok)
            #expect(environment.claudeSignInError == nil)
        }
    }

    @Test
    func leavesFailedRenewalForAnExplicitBrowserAction() async {
        var signInCalls = 0
        let client = ClaudeRecoveryClient(
            renewSession: { 1 },
            signIn: { signInCalls += 1 },
            refreshUsage: { _, _ in Self.snapshot(authState: signInCalls == 0 ? .signedOut : .authenticated) }
        )

        await withEnvironment(client: client) { environment in
            await environment.reconnectClaude()?.value

            #expect(signInCalls == 0)
            #expect(environment.claudeSignInError == .claudeRenewalFailed)

            await environment.signInToClaudeInBrowser()?.value

            #expect(signInCalls == 1)
            #expect(environment.snapshot(for: .claude)?.authState == .authenticated)
            #expect(environment.claudeSignInError == nil)
        }
    }

    @Test
    func verifiesCredentialsAfterExplicitKeychainAccess() async {
        var interactiveReads = 0
        let credentials = ClaudeOAuthCredentialsStore(
            rawDataLoader: { throw ClaudeOAuthCredentialsError.keychainError(errSecInteractionNotAllowed) },
            interactiveDataLoader: {
                interactiveReads += 1

                return Data("{\"claudeAiOauth\":{\"accessToken\":\"token\"}}".utf8)
            }
        )
        let client = ClaudeRecoveryClient(
            renewSession: { 1 },
            signIn: {},
            refreshUsage: { _, _ in Self.snapshot(authState: .authenticated) }
        )

        await withEnvironment(credentials: credentials, client: client) { environment in
            await environment.reconnectClaude()?.value

            #expect(environment.claudeSignInError == .claudeCredentialAccessRequired)
            #expect(interactiveReads == 0)

            await environment.allowClaudeCredentialAccess()?.value

            #expect(interactiveReads == 1)
            #expect(environment.snapshot(for: .claude)?.fetchState == .ok)
            #expect(environment.claudeSignInError == nil)
            #expect(environment.isReconnectingClaude == false)
        }
    }

    @Test
    func reportsVerificationFailureAfterKeychainAccess() async {
        let client = ClaudeRecoveryClient(
            renewSession: { 1 },
            signIn: {},
            refreshUsage: { _, _ in throw SharedCoreError.invalidResponse("Invalid response") }
        )

        await withEnvironment(client: client) { environment in
            await environment.allowClaudeCredentialAccess()?.value

            #expect(environment.claudeSignInError == .claudeSignInFailed)
            #expect(environment.isReconnectingClaude == false)
        }
    }

    @Test
    func separatesKeychainAccessFailureFromAuthentication() async {
        var signInCalls = 0
        var verificationCalls = 0
        let credentials = ClaudeOAuthCredentialsStore {
            throw ClaudeOAuthCredentialsError.keychainError(errSecInteractionNotAllowed)
        }
        let client = ClaudeRecoveryClient(
            renewSession: { 1 },
            signIn: { signInCalls += 1 },
            refreshUsage: { _, _ in
                verificationCalls += 1
                return Self.snapshot(authState: .signedOut)
            }
        )

        await withEnvironment(credentials: credentials, client: client) { environment in
            await environment.reconnectClaude()?.value

            #expect(signInCalls == 0)
            #expect(verificationCalls == 0)
            #expect(environment.claudeSignInError == .claudeCredentialAccessRequired)
        }
    }

    private func withEnvironment(
        credentials: ClaudeOAuthCredentialsStore = ClaudeOAuthCredentialsStore(rawDataLoader: { Data("{}".utf8) }),
        client: ClaudeRecoveryClient,
        body: (AppEnvironment) async -> Void
    ) async {
        let suiteName = "ClaudeRecoveryTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let environment = AppEnvironment(
            settings: SettingsStore(defaults: defaults),
            claudeCredentials: credentials,
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
