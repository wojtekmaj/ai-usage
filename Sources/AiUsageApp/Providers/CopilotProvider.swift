import Foundation

struct CopilotSessionState: Codable, Hashable, Sendable {
    var cookies: [StoredCookie]
}

@MainActor
final class CopilotProvider: UsageProvider {
    let id: ProviderID = .copilot
    let sourceDescription = "GitHub Copilot billing session"

    private let keychain: KeychainStore
    private let logStore: LogStore
    private let tokenAccount = "copilot.personal-access-token"
    private let sessionAccount = "copilot.github-session"
    private let billingUsageURL = URL(string: "https://github.com/settings/billing/premium_requests_usage")!
    private let usageCardURL = URL(string: "https://github.com/settings/billing/copilot_usage_card")!

    init(keychain: KeychainStore, logStore: LogStore) {
        self.keychain = keychain
        self.logStore = logStore
    }

    func currentAuthState() -> ProviderAuthState {
        let token = (try? keychain.loadString(account: tokenAccount)) ?? nil
        let session = (try? loadSession()) ?? nil
        return (token?.isEmpty == false || session?.cookies.isEmpty == false) ? .configured : .signedOut
    }

    func saveToken(_ token: String) throws {
        try keychain.save(string: token.trimmingCharacters(in: .whitespacesAndNewlines), account: tokenAccount)
    }

    func saveSession(_ session: CopilotSessionState) throws {
        let data = try JSONEncoder().encode(session)
        try keychain.save(data: data, account: sessionAccount)
    }

    func clearAuth() throws {
        try? keychain.delete(account: tokenAccount)
        try? keychain.delete(account: sessionAccount)
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

        let storedToken = (try? keychain.loadString(account: tokenAccount)) ?? nil
        let storedSession = (try? loadSession()) ?? nil

        guard (storedToken?.isEmpty == false) || (storedSession?.cookies.isEmpty == false) else {
            logStore.append(level: .warning, category: "copilot", message: "Refresh skipped because no GitHub Copilot authentication is configured.")
            return ProviderSnapshot(provider: id, authState: .signedOut, fetchState: .missingAuth, fetchedAtUTC: nil, metrics: [baseMetric], errorDescription: nil, sourceDescription: sourceDescription)
        }

        do {
            if let session = storedSession, session.cookies.isEmpty == false {
                do {
                    let usagePayload = try await fetchUsagePayload(session: session)
                    let metric = try CopilotUsageParser.parseMetric(from: usagePayload, now: now)
                    logStore.append(category: "copilot", message: "Parsed GitHub Copilot usage metric from GitHub billing session JSON.")

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
                    logStore.append(level: .warning, category: "copilot", message: "GitHub billing session JSON fetch failed. \(error.localizedDescription)")
                }
            }

            if let token = storedToken, token.isEmpty == false {
                let login = try await fetchLogin(token: token)
                logStore.append(category: "copilot", message: "Resolved authenticated GitHub login: \(login)")
                let usagePayload = try await fetchUsagePayload(token: token, login: login, now: now)
                let metric = try CopilotUsageParser.parseMetric(from: usagePayload, now: now)
                logStore.append(category: "copilot", message: "Parsed GitHub Copilot usage metric from REST API.")

                return ProviderSnapshot(
                    provider: id,
                    authState: .authenticated,
                    fetchState: .ok,
                    fetchedAtUTC: now,
                    metrics: [metric],
                    errorDescription: nil,
                    sourceDescription: sourceDescription
                )
            }

            throw CopilotProviderError.webSessionRequired
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

    private func loadSession() throws -> CopilotSessionState? {
        guard let data = try keychain.loadData(account: sessionAccount) else {
            return nil
        }

        return try JSONDecoder().decode(CopilotSessionState.self, from: data)
    }

    private func fetchUsagePayload(session: CopilotSessionState) async throws -> Any {
        var request = URLRequest(url: usageCardURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("true", forHTTPHeaderField: "GitHub-Is-React")
        request.setValue(billingUsageURL.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue(cookieHeader(from: session.cookies), forHTTPHeaderField: "Cookie")

        let (data, response) = try await URLSession.shared.data(for: request)
        logHTTPResult(category: "copilot", url: usageCardURL, response: response, data: data)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CopilotProviderError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            if httpResponse.statusCode == 404 {
                throw CopilotProviderError.usageEndpointUnavailable
            }

            throw CopilotProviderError.httpFailure(httpResponse.statusCode, body)
        }

        guard let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased() else {
            throw CopilotProviderError.invalidResponse
        }

        if contentType.contains("json") == false {
            let body = String(data: data, encoding: .utf8) ?? ""
            if body.localizedCaseInsensitiveContains("sign in")
                || body.localizedCaseInsensitiveContains("session has expired")
                || body.localizedCaseInsensitiveContains("logged in") {
                throw CopilotProviderError.webSessionExpired
            }

            throw CopilotProviderError.invalidResponse
        }

        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw CopilotProviderError.invalidResponse
        }
    }

    private func fetchLogin(token: String) async throws -> String {
        let url = URL(string: "https://api.github.com/user")!
        var request = URLRequest(url: url)
        configure(&request, token: token)

        let (data, response) = try await URLSession.shared.data(for: request)
        logHTTPResult(category: "copilot", url: url, response: response, data: data)
        try validate(response: response, data: data)

        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let login = payload["login"] as? String,
              login.isEmpty == false else {
            throw CopilotProviderError.invalidLoginPayload
        }

        return login
    }

    private func fetchUsagePayload(token: String, login: String, now: Date) async throws -> Any {
        var lastError: Error?
        var sawOnly404 = true

        for url in userUsageURLs(login: login, now: now) {
            do {
                var request = URLRequest(url: url)
                configure(&request, token: token)
                let (data, response) = try await URLSession.shared.data(for: request)
                logHTTPResult(category: "copilot", url: url, response: response, data: data)
                try validate(response: response, data: data)
                return try JSONSerialization.jsonObject(with: data)
            } catch {
                lastError = error
                if case let CopilotProviderError.httpFailure(status, _) = error, status == 404 {
                    logStore.append(level: .warning, category: "copilot", message: "Endpoint returned 404: \(url.absoluteString)")
                } else {
                    sawOnly404 = false
                }
            }
        }

        if sawOnly404 {
            throw CopilotProviderError.userLevelUsageUnavailable
        }

        throw lastError ?? CopilotProviderError.usageEndpointUnavailable
    }

    private func configure(_ request: inout URLRequest, token: String) {
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
    }

    private func userUsageURLs(login: String, now: Date) -> [URL] {
        let billingPeriod = billingPeriodQueryItems(for: now)

        return uniqueURLs(
            [
                makeURL(path: "/users/\(login)/settings/billing/premium_request/usage", queryItems: billingPeriod + [.init(name: "product", value: "Copilot")]),
                makeURL(path: "/users/\(login)/settings/billing/premium_request/usage", queryItems: billingPeriod),
                makeURL(path: "/users/\(login)/settings/billing/usage/summary", queryItems: billingPeriod + [.init(name: "product", value: "Copilot")]),
                makeURL(path: "/users/\(login)/settings/billing/premium_request/usage", queryItems: [.init(name: "product", value: "Copilot")]),
                makeURL(path: "/users/\(login)/settings/billing/premium_request/usage"),
                makeURL(path: "/users/\(login)/settings/billing/usage/summary", queryItems: [.init(name: "product", value: "Copilot")]),
            ]
        )
    }

    private func billingPeriodQueryItems(for now: Date) -> [URLQueryItem] {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: now)

        guard let year = components.year, let month = components.month else {
            return []
        }

        return [
            .init(name: "year", value: String(year)),
            .init(name: "month", value: String(month)),
        ]
    }

    private func makeURL(path: String, queryItems: [URLQueryItem] = []) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url
    }

    private func uniqueURLs(_ urls: [URL?]) -> [URL] {
        var seen = Set<String>()

        return urls.compactMap { url in
            guard let url, seen.insert(url.absoluteString).inserted else {
                return nil
            }

            return url
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CopilotProviderError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CopilotProviderError.httpFailure(httpResponse.statusCode, body)
        }
    }

    private func logHTTPResult(category: String, url: URL, response: URLResponse, data: Data) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        logStore.append(category: category, message: "HTTP \(status) for \(url.absoluteString) | preview=\(preview(of: data))")
    }

    private func preview(of data: Data) -> String {
        let text = String(data: data.prefix(320), encoding: .utf8) ?? "<non-utf8>"
        return text.replacingOccurrences(of: "\n", with: " ")
    }

    private func cookieHeader(from cookies: [StoredCookie]) -> String {
        cookies
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
    }

}

enum CopilotProviderError: LocalizedError {
    case invalidResponse
    case invalidLoginPayload
    case usageEndpointUnavailable
    case unrecognizedUsagePayload
    case userLevelUsageUnavailable
    case webSessionRequired
    case webSessionExpired
    case httpFailure(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "GitHub Copilot usage couldn't be loaded."
        case .invalidLoginPayload:
            return "GitHub account details couldn't be loaded."
        case .usageEndpointUnavailable:
            return "GitHub Copilot usage is temporarily unavailable."
        case .unrecognizedUsagePayload:
            return "GitHub Copilot usage couldn't be read."
        case .userLevelUsageUnavailable:
            return "This GitHub token can't access your GitHub Copilot usage."
        case .webSessionRequired:
            return "Sign in to GitHub in Settings to load your GitHub Copilot usage."
        case .webSessionExpired:
            return "Your GitHub sign-in expired. Sign in again in Settings."
        case let .httpFailure(status, body):
            return body.isEmpty
                ? "GitHub request failed with status \(status)."
                : "GitHub request failed with status \(status): \(body)"
        }
    }
}
