import Foundation

@MainActor
final class CopilotProvider: UsageProvider {
    let id: ProviderID = .copilot
    let sourceDescription = "GitHub device-flow token"

    private let keychain: KeychainStore
    private let logStore: LogStore
    private let tokenAccount = "copilot.github-oauth-token"
    private let usageURL = URL(string: "https://api.github.com/copilot_internal/user")!

    init(keychain: KeychainStore, logStore: LogStore) {
        self.keychain = keychain
        self.logStore = logStore
    }

    func currentAuthState() -> ProviderAuthState {
        let token = (try? keychain.loadString(account: tokenAccount)) ?? nil
        return (token?.isEmpty == false) ? .configured : .signedOut
    }

    func saveToken(_ token: String) throws {
        try keychain.save(
            string: token.trimmingCharacters(in: .whitespacesAndNewlines),
            account: tokenAccount
        )
    }

    func clearAuth() throws {
        try keychain.delete(account: tokenAccount)
    }

    func refresh(now: Date) async -> ProviderSnapshot {
        let baseMetric = UsageMetric(
            kind: .copilotMonthly,
            remainingFraction: nil,
            remainingValue: nil,
            totalValue: nil,
            unit: .requests,
            resetAtUTC: CopilotUsageParser.nextReset(after: now),
            lastUpdatedAtUTC: now,
            detailText: nil
        )

        guard let token = (try? keychain.loadString(account: tokenAccount)),
              token.isEmpty == false else {
            logStore.append(level: .warning, category: "copilot", message: "Refresh skipped because no GitHub OAuth token is configured.")
            return ProviderSnapshot(
                provider: id,
                authState: .signedOut,
                fetchState: .missingAuth,
                fetchedAtUTC: nil,
                metrics: [baseMetric],
                errorDescription: nil,
                sourceDescription: sourceDescription
            )
        }

        do {
            let payload = try await fetchUsagePayload(token: token)
            let metric = try CopilotUsageParser.parseMetric(from: payload, now: now)
            logStore.append(category: "copilot", message: "Parsed GitHub Copilot usage from internal API.")

            return ProviderSnapshot(
                provider: id,
                authState: .authenticated,
                fetchState: .ok,
                fetchedAtUTC: now,
                metrics: [metric],
                errorDescription: nil,
                sourceDescription: sourceDescription
            )
        } catch {
            logStore.append(level: .error, category: "copilot", message: "Refresh failed: \(error.localizedDescription)")
            return ProviderSnapshot(
                provider: id,
                authState: .configured,
                fetchState: .failed,
                fetchedAtUTC: now,
                metrics: [baseMetric],
                errorDescription: error.localizedDescription,
                sourceDescription: sourceDescription
            )
        }
    }

    private func fetchUsagePayload(token: String) async throws -> Any {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("vscode/1.96.2", forHTTPHeaderField: "Editor-Version")
        request.setValue("copilot-chat/0.26.7", forHTTPHeaderField: "Editor-Plugin-Version")
        request.setValue("GitHubCopilotChat/0.26.7", forHTTPHeaderField: "User-Agent")
        request.setValue("2025-04-01", forHTTPHeaderField: "X-Github-Api-Version")

        let (data, response) = try await URLSession.shared.data(for: request)
        logHTTPResult(url: usageURL, response: response, data: data)
        try validate(response: response, data: data)

        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw CopilotProviderError.invalidResponse
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CopilotProviderError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200 ..< 300:
            return
        case 401, 403:
            throw CopilotProviderError.unauthorized
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CopilotProviderError.httpFailure(httpResponse.statusCode, body)
        }
    }

    private func logHTTPResult(url: URL, response: URLResponse, data: Data) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        logStore.append(category: "copilot", message: "HTTP \(status) for \(url.absoluteString) | preview=\(preview(of: data))")
    }

    private func preview(of data: Data) -> String {
        let text = String(data: data, encoding: .utf8) ?? "<non-utf8>"
        return text.replacingOccurrences(of: "\n", with: " ")
    }
}

enum CopilotProviderError: LocalizedError {
    case invalidResponse
    case unauthorized
    case unrecognizedUsagePayload
    case httpFailure(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "GitHub Copilot usage couldn't be loaded."
        case .unauthorized:
            return "GitHub Copilot sign-in expired. Sign in again and refresh."
        case .unrecognizedUsagePayload:
            return "GitHub Copilot usage response wasn't recognized."
        case let .httpFailure(status, body):
            if body.isEmpty {
                return "GitHub Copilot usage API returned HTTP \(status)."
            }
            return "GitHub Copilot usage API returned HTTP \(status): \(body)"
        }
    }
}
