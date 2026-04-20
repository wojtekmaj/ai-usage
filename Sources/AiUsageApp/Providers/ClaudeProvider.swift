import Foundation

@MainActor
final class ClaudeProvider: UsageProvider {
    let id: ProviderID = .claude
    let sourceDescription = "Local Claude Code OAuth auth"

    private let logStore: LogStore
    private let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private let fallbackUserAgent = "claude-code/2.1.0"

    init(logStore: LogStore) {
        self.logStore = logStore
    }

    func currentAuthState() -> ProviderAuthState {
        ((try? loadCredentials()) != nil) ? .configured : .signedOut
    }

    func clearAuth() throws {
        // Claude auth is managed by Claude Code. The app intentionally avoids
        // mutating Keychain or ~/.claude/.credentials.json on the user's behalf.
    }

    func refresh(now: Date) async -> ProviderSnapshot {
        let baseMetrics = [
            UsageMetric(kind: .claudeFiveHour, remainingFraction: nil, remainingValue: nil, totalValue: nil, unit: .percentage, resetAtUTC: nil, lastUpdatedAtUTC: now, detailText: nil),
            UsageMetric(kind: .claudeWeekly, remainingFraction: nil, remainingValue: nil, totalValue: nil, unit: .percentage, resetAtUTC: nil, lastUpdatedAtUTC: now, detailText: nil),
        ]

        do {
            let credentials = try loadCredentials()
            guard credentials.hasUsageScope else {
                throw ClaudeOAuthCredentialsError.missingUsageScope
            }
            guard credentials.isExpired == false else {
                throw ClaudeOAuthCredentialsError.expired
            }

            let data = try await fetchUsageData(accessToken: credentials.accessToken)
            let metrics = try ClaudeUsageParser.parseMetrics(from: data, now: now)
            logStore.append(category: "claude", message: "Loaded Claude usage from local Claude Code auth.")

            return ProviderSnapshot(
                provider: id,
                authState: .authenticated,
                fetchState: .ok,
                fetchedAtUTC: now,
                metrics: metrics,
                errorDescription: nil,
                sourceDescription: sourceDescription
            )
        } catch let error as ClaudeOAuthCredentialsError {
            logStore.append(level: .warning, category: "claude", message: error.localizedDescription)
            return ProviderSnapshot(
                provider: id,
                authState: .signedOut,
                fetchState: .missingAuth,
                fetchedAtUTC: nil,
                metrics: baseMetrics,
                errorDescription: nil,
                sourceDescription: sourceDescription
            )
        } catch {
            logStore.append(level: .error, category: "claude", message: "Refresh failed: \(error.localizedDescription)")
            return ProviderSnapshot(
                provider: id,
                authState: .configured,
                fetchState: .failed,
                fetchedAtUTC: now,
                metrics: baseMetrics,
                errorDescription: error.localizedDescription,
                sourceDescription: sourceDescription
            )
        }
    }

    private func loadCredentials() throws -> ClaudeOAuthCredentials {
        try ClaudeOAuthCredentialsStore.load()
    }

    private func fetchUsageData(accessToken: String) async throws -> Data {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue(fallbackUserAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        logStore.append(category: "claude", message: "HTTP \(status) for \(usageURL.absoluteString) | preview=\(preview(of: data))")

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeProviderError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200 ..< 300:
            return data
        case 401:
            throw ClaudeProviderError.unauthorized
        default:
            throw ClaudeProviderError.httpFailure(httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    private func preview(of data: Data) -> String {
        let text = String(data: data, encoding: .utf8) ?? "<non-utf8>"
        return text.replacingOccurrences(of: "\n", with: " ")
    }
}

enum ClaudeProviderError: LocalizedError {
    case invalidResponse
    case unauthorized
    case httpFailure(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Claude usage API returned an unexpected response."
        case .unauthorized:
            return "Claude Code auth is no longer valid. Run `claude` again and refresh."
        case let .httpFailure(statusCode, body):
            if body.isEmpty {
                return "Claude usage API returned HTTP \(statusCode)."
            }

            return "Claude usage API returned HTTP \(statusCode): \(body)"
        }
    }
}
