import Foundation
import Testing
@testable import AiUsageApp

@MainActor
struct ClaudeRecoveryTests {
    @Test
    func reconnectsUsingUpdatedLocalCredentials() async {
        var signInCalls = 0
        var credentialsJSON = "{}"
        let credentials = ClaudeOAuthCredentialsStore { Data(credentialsJSON.utf8) }
        _ = try? credentials.rawJSONString()
        credentialsJSON = "{\"claudeAiOauth\":{\"accessToken\":\"updated-token\"}}"
        let client = ClaudeRecoveryClient(
            signIn: { signInCalls += 1 },
            refreshUsage: { json, _ in
                #expect(json == credentialsJSON)

                return Self.snapshot(authState: .authenticated)
            }
        )

        await withEnvironment(credentials: credentials, client: client) { environment in
            await environment.reconnectClaude()?.value

            #expect(signInCalls == 0)
            #expect(environment.snapshot(for: .claude)?.fetchState == .ok)
            #expect(environment.claudeSignInError == nil)
            #expect(environment.isReconnectingClaude == false)
        }
    }

    @Test
    func signsInWhenStoredCredentialsAreRejectedAndVerifiesNewCredentials() async {
        var signInCalls = 0
        var verificationCalls = 0
        var credentialsJSON = "{}"
        let credentials = ClaudeOAuthCredentialsStore { Data(credentialsJSON.utf8) }
        let client = ClaudeRecoveryClient(
            signIn: {
                signInCalls += 1
                credentialsJSON = "{\"claudeAiOauth\":{\"accessToken\":\"new-token\"}}"
            },
            refreshUsage: { json, _ in
                verificationCalls += 1
                #expect(json == credentialsJSON)

                return Self.snapshot(authState: signInCalls == 0 ? .signedOut : .authenticated)
            }
        )

        await withEnvironment(credentials: credentials, client: client) { environment in
            await environment.reconnectClaude()?.value

            #expect(signInCalls == 1)
            #expect(verificationCalls == 2)
            #expect(environment.snapshot(for: .claude)?.authState == .authenticated)
            #expect(environment.claudeSignInError == nil)
        }
    }

    @Test
    func permitsKeychainAccessOnReconnect() async {
        var interactiveReads = 0
        var signInCalls = 0
        let credentials = ClaudeOAuthCredentialsStore(
            rawDataLoader: { throw ClaudeOAuthCredentialsError.keychainError(errSecInteractionNotAllowed) },
            interactiveDataLoader: {
                interactiveReads += 1

                return Data("{\"claudeAiOauth\":{\"accessToken\":\"token\"}}".utf8)
            }
        )
        let client = ClaudeRecoveryClient(
            signIn: { signInCalls += 1 },
            refreshUsage: { _, _ in Self.snapshot(authState: .authenticated) }
        )

        await withEnvironment(credentials: credentials, client: client) { environment in
            await environment.reconnectClaude()?.value

            #expect(interactiveReads == 1)
            #expect(signInCalls == 0)
            #expect(environment.snapshot(for: .claude)?.fetchState == .ok)
            #expect(environment.claudeSignInError == nil)
        }
    }

    @Test
    func keepsNetworkFailureSeparateFromSignIn() async {
        var signInCalls = 0
        let client = ClaudeRecoveryClient(
            signIn: { signInCalls += 1 },
            refreshUsage: { _, _ in Self.snapshot(authState: .configured) }
        )

        await withEnvironment(client: client) { environment in
            await environment.reconnectClaude()?.value

            #expect(signInCalls == 0)
            #expect(environment.snapshot(for: .claude)?.fetchState == .failed)
            #expect(environment.claudeSignInError == nil)
            #expect(environment.isReconnectingClaude == false)
        }
    }

    @Test
    func reportsRejectedCredentialsAfterSignIn() async {
        var signInCalls = 0
        let client = ClaudeRecoveryClient(
            signIn: { signInCalls += 1 },
            refreshUsage: { _, _ in Self.snapshot(authState: .signedOut) }
        )

        await withEnvironment(client: client) { environment in
            await environment.reconnectClaude()?.value

            #expect(signInCalls == 1)
            #expect(environment.claudeSignInError == .claudeSignInFailed)
            #expect(environment.isReconnectingClaude == false)
        }
    }

    @Test
    func reportsVerificationFailure() async {
        let client = ClaudeRecoveryClient(
            signIn: {},
            refreshUsage: { _, _ in throw SharedCoreError.invalidResponse("Invalid response") }
        )

        await withEnvironment(client: client) { environment in
            await environment.reconnectClaude()?.value

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

    @Test
    func cancelsPendingBrowserSignInAndPreventsDuplicateReconnects() async {
        let (started, continuation) = AsyncStream<Void>.makeStream()
        let client = ClaudeRecoveryClient(
            signIn: {
                continuation.yield(())
                continuation.finish()
                try await Task.sleep(for: .seconds(30))
            },
            refreshUsage: { _, _ in Self.snapshot(authState: .signedOut) }
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

    @Test
    func replacesPreviouslySuccessfulUsageAfterAFailedRefresh() async {
        var snapshot = Self.snapshot(authState: .authenticated)
        snapshot.metrics = [UsageMetric(kind: .claudeWeekly, remainingFraction: 0.75, remainingValue: nil, totalValue: nil, unit: .percentage, resetAtUTC: nil, lastUpdatedAtUTC: .now, detailText: nil)]
        let client = ClaudeRecoveryClient(
            signIn: {},
            refreshUsage: { _, _ in snapshot }
        )

        await withEnvironment(client: client) { environment in
            await environment.reconnectClaude()?.value
            #expect(environment.snapshot(for: .claude)?.metric(.claudeWeekly)?.remainingFraction == 0.75)

            snapshot = Self.snapshot(authState: .configured)
            await environment.reconnectClaude()?.value

            #expect(environment.snapshot(for: .claude)?.shouldShowUsageMetrics == false)
            #expect(environment.snapshot(for: .claude)?.metrics.isEmpty == true)
            #expect(environment.usageStore.loadSnapshots()[.claude]?.metrics.isEmpty == true)
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
