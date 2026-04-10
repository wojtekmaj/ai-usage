import Foundation

@MainActor
final class CodexProvider: UsageProvider {
    let id: ProviderID = .codex
    let sourceDescription = "Local Codex CLI auth"

    private let logStore: LogStore

    init(keychain: KeychainStore, logStore: LogStore) {
        self.logStore = logStore
    }

    func currentAuthState() -> ProviderAuthState {
        ((try? loadCredentials()) != nil) ? .configured : .signedOut
    }

    func clearAuth() throws {
        // Codex auth is managed by the local Codex CLI. The app intentionally
        // avoids deleting ~/.codex/auth.json so it cannot sign the user out
        // of the CLI unexpectedly.
    }

    func refresh(now: Date) async -> ProviderSnapshot {
        let baseMetrics = [
            UsageMetric(kind: .codexFiveHour, remainingFraction: nil, remainingValue: nil, totalValue: nil, unit: .percentage, resetAtUTC: nil, lastUpdatedAtUTC: now, detailText: nil),
            UsageMetric(kind: .codexWeekly, remainingFraction: nil, remainingValue: nil, totalValue: nil, unit: .percentage, resetAtUTC: nil, lastUpdatedAtUTC: now, detailText: nil),
            UsageMetric(kind: .codexCredits, remainingFraction: nil, remainingValue: nil, totalValue: nil, unit: .credits, resetAtUTC: nil, lastUpdatedAtUTC: now, detailText: nil),
        ]

        do {
            var credentials = try loadCredentials()
            if credentials.needsRefresh {
                credentials = try await CodexTokenRefresher.refresh(credentials)
                try CodexOAuthCredentialsStore.save(credentials)
                logStore.append(category: "codex", message: "Refreshed local Codex CLI auth token.")
            }

            let payload = try await fetchUsagePayload(credentials: credentials)
            let metrics = try CodexHTMLParser.parse(apiPayload: payload, now: now)
            logStore.append(category: "codex", message: "Loaded Codex usage from local CLI auth.")

            return ProviderSnapshot(
                provider: id,
                authState: .authenticated,
                fetchState: .ok,
                fetchedAtUTC: now,
                metrics: metrics,
                errorDescription: nil,
                sourceDescription: sourceDescription
            )
        } catch let error as CodexOAuthCredentialsError {
            logStore.append(level: .warning, category: "codex", message: error.localizedDescription)
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
            logStore.append(level: .error, category: "codex", message: "Refresh failed: \(error.localizedDescription)")
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

    private func loadCredentials() throws -> CodexOAuthCredentials {
        try CodexOAuthCredentialsStore.load()
    }

    private func fetchUsagePayload(credentials: CodexOAuthCredentials) async throws -> Any {
        let baseURL = CodexOAuthCredentialsStore.chatGPTBaseURL()
        let usageURL = resolvedUsageURL(from: baseURL)

        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AI Usage", forHTTPHeaderField: "User-Agent")

        if let accountId = credentials.accountId, accountId.isEmpty == false {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        logStore.append(category: "codex", message: "HTTP \(status) for \(usageURL.absoluteString) | preview=\(preview(of: data))")

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CodexProviderError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200 ..< 300:
            do {
                return try JSONSerialization.jsonObject(with: data)
            } catch {
                throw CodexProviderError.invalidResponse
            }
        case 401, 403:
            throw CodexProviderError.unauthorized
        default:
            throw CodexProviderError.httpFailure(httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    private func resolvedUsageURL(from baseURL: URL) -> URL {
        let absolute = baseURL.absoluteString
        if absolute.contains("/backend-api/") {
            return baseURL.appendingPathComponent("wham/usage")
        }

        return baseURL.appendingPathComponent("api/codex/usage")
    }

    private func preview(of data: Data) -> String {
        let text = String(data: data.prefix(320), encoding: .utf8) ?? "<non-utf8>"
        return text.replacingOccurrences(of: "\n", with: " ")
    }
}

enum CodexProviderError: LocalizedError {
    case invalidResponse
    case unauthorized
    case httpFailure(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Codex usage API returned an unexpected response."
        case .unauthorized:
            return "Codex CLI auth is no longer valid. Run `codex login` and refresh."
        case let .httpFailure(statusCode, body):
            if body.isEmpty {
                return "Codex usage API returned HTTP \(statusCode)."
            }
            return "Codex usage API returned HTTP \(statusCode): \(body)"
        }
    }
}
