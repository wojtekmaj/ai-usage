import Foundation
import Security

@MainActor
final class ClaudeProvider: UsageProvider {
    let id: ProviderID = .claude
    let sourceDescription = "Claude Code"

    private let keychain: KeychainStore
    private let logStore: LogStore
    private let adminKeyAccount = "claude.admin-api-key"
    private let oauthTokenCacheAccount = "claude.oauth-token-cache"
    private let oauthUsageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private struct CachedOAuthToken: Codable {
        let accessToken: String
        let expiresAt: Double // milliseconds since epoch, matching Claude Code's format
    }

    init(keychain: KeychainStore, logStore: LogStore) {
        self.keychain = keychain
        self.logStore = logStore
    }

    var oauthEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "claudeOAuthEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "claudeOAuthEnabled") }
    }

    var hasAdminKey: Bool {
        (try? keychain.loadString(account: adminKeyAccount))?.isEmpty == false
    }

    /// Attempts to read the OAuth token from the Keychain (may trigger macOS permission dialog on first call).
    /// Returns `true` if a valid token was found and sets `oauthEnabled = true`.
    func enableOAuth() -> Bool {
        guard readOAuthToken() != nil else { return false }
        oauthEnabled = true
        return true
    }

    func disableOAuth() {
        oauthEnabled = false
        try? keychain.delete(account: oauthTokenCacheAccount)
    }

    func currentAuthState() -> ProviderAuthState {
        (hasAdminKey || oauthEnabled) ? .configured : .signedOut
    }

    func saveAdminKey(_ key: String) throws {
        try keychain.save(string: key.trimmingCharacters(in: .whitespacesAndNewlines), account: adminKeyAccount)
    }

    func removeAdminKey() throws {
        try keychain.delete(account: adminKeyAccount)
    }

    func clearAuth() throws {
        try? keychain.delete(account: adminKeyAccount)
        try? keychain.delete(account: oauthTokenCacheAccount)
        oauthEnabled = false
        // Claude Code's own "Claude Code-credentials" item is not deleted — it belongs to Claude Code.
    }

    // MARK: - Refresh

    func refresh(now: Date) async -> ProviderSnapshot {
        let storedKey = hasAdminKey ? (try? keychain.loadString(account: adminKeyAccount)).flatMap { $0.isEmpty ? nil : $0 } : nil

        var oauthToken: String? = nil
        if oauthEnabled {
            oauthToken = readOAuthToken()
            if oauthToken == nil {
                // Credentials gone or token expired — revert to disconnected so Settings
                // shows the "Allow access" button again. No macOS dialog is shown here.
                disableOAuth()
                logStore.append(level: .warning, category: "claude", message: "OAuth token unavailable during refresh. Disconnected — user must re-allow access.")
                if storedKey == nil {
                    return ProviderSnapshot(
                        provider: id,
                        authState: .signedOut,
                        fetchState: .failed,
                        fetchedAtUTC: now,
                        metrics: placeholderMetrics(now: now),
                        errorDescription: ClaudeProviderError.tokenExpired.errorDescription,
                        sourceDescription: sourceDescription
                    )
                }
            }
        }

        guard storedKey != nil || oauthToken != nil else {
            logStore.append(level: .warning, category: "claude", message: "Refresh skipped: no credentials configured.")
            return missingAuthSnapshot(now: now)
        }

        // Try Admin API first
        if let key = storedKey {
            do {
                let snapshot = try await refreshViaAPI(key: key, now: now)
                logStore.append(category: "claude", message: "Refreshed Claude Code via Admin API.")
                return snapshot
            } catch {
                logStore.append(level: .warning, category: "claude", message: "Admin API refresh failed: \(error.localizedDescription). Falling back to OAuth.")
            }
        }

        // Fall back to OAuth token
        if let token = oauthToken {
            do {
                let snapshot = try await refreshViaOAuth(token: token, now: now)
                logStore.append(category: "claude", message: "Refreshed Claude Code via OAuth API.")
                return snapshot
            } catch {
                logStore.append(level: .error, category: "claude", message: "OAuth refresh failed: \(error.localizedDescription)")
                return ProviderSnapshot(
                    provider: id,
                    authState: .configured,
                    fetchState: .failed,
                    fetchedAtUTC: now,
                    metrics: placeholderMetrics(now: now),
                    errorDescription: error.localizedDescription,
                    sourceDescription: sourceDescription
                )
            }
        }

        return ProviderSnapshot(
            provider: id,
            authState: .configured,
            fetchState: .failed,
            fetchedAtUTC: now,
            metrics: placeholderMetrics(now: now),
            errorDescription: "All authentication methods failed.",
            sourceDescription: sourceDescription
        )
    }

    // MARK: - Admin API path

    private func refreshViaAPI(key: String, now: Date) async throws -> ProviderSnapshot {
        let sevenDaysAgo = now.addingTimeInterval(-6 * 24 * 3600)

        async let dailyResult = ClaudeAPIClient.fetchDaily(adminKey: key, date: now)
        async let weeklyResult = ClaudeAPIClient.fetchWeekly(adminKey: key, startDate: sevenDaysAgo)

        let (daily, weekly) = try await (dailyResult, weeklyResult)

        let sonnetFraction = weekly.sonnetFraction ?? daily.sonnetFraction
        let midnightTomorrow = nextMidnightUTC(after: now)
        let weeklyEnd = nextMidnightUTC(after: sevenDaysAgo.addingTimeInterval(7 * 24 * 3600))

        let metrics: [UsageMetric] = [
            UsageMetric(
                kind: .claudeDailyCost,
                remainingFraction: nil,
                remainingValue: daily.totalCostUSD,
                totalValue: nil,
                unit: .cost,
                resetAtUTC: midnightTomorrow,
                lastUpdatedAtUTC: now,
                detailText: nil
            ),
            UsageMetric(
                kind: .claudeWeeklyCost,
                remainingFraction: nil,
                remainingValue: weekly.totalCostUSD,
                totalValue: nil,
                unit: .cost,
                resetAtUTC: weeklyEnd,
                lastUpdatedAtUTC: now,
                detailText: nil
            ),
            UsageMetric(
                kind: .claudeSonnet,
                remainingFraction: sonnetFraction,
                remainingValue: sonnetFraction.map { $0 * 100 },
                totalValue: 100,
                unit: .percentage,
                resetAtUTC: weeklyEnd,
                lastUpdatedAtUTC: now,
                detailText: nil
            ),
        ]

        return ProviderSnapshot(
            provider: id,
            authState: .authenticated,
            fetchState: .ok,
            fetchedAtUTC: now,
            metrics: metrics,
            errorDescription: nil,
            sourceDescription: "Claude Code (Admin API)"
        )
    }

    // MARK: - OAuth path

    private func refreshViaOAuth(token: String, now: Date) async throws -> ProviderSnapshot {
        let response = try await fetchOAuthUsage(token: token)

        let fiveHourFraction = response.fiveHour.map { 1.0 - $0.utilization / 100.0 }
        let weeklyFraction = response.sevenDay.map { 1.0 - $0.utilization / 100.0 }

        // Sonnet: prefer API field (Max plan), fall back to JSONL
        let sonnetFraction: Double?
        if let sonnetUtilization = response.sevenDaySonnet?.utilization {
            sonnetFraction = 1.0 - sonnetUtilization / 100.0
        } else {
            sonnetFraction = ClaudeJSONLParser.sonnetFraction(referenceDate: now)
        }

        let metrics: [UsageMetric] = [
            UsageMetric(
                kind: .claudeFiveHour,
                remainingFraction: fiveHourFraction,
                remainingValue: fiveHourFraction.map { $0 * 100 },
                totalValue: 100,
                unit: .percentage,
                resetAtUTC: response.fiveHour?.resetsAt,
                lastUpdatedAtUTC: now,
                detailText: nil
            ),
            UsageMetric(
                kind: .claudeWeeklyQuota,
                remainingFraction: weeklyFraction,
                remainingValue: weeklyFraction.map { $0 * 100 },
                totalValue: 100,
                unit: .percentage,
                resetAtUTC: response.sevenDay?.resetsAt,
                lastUpdatedAtUTC: now,
                detailText: nil
            ),
            UsageMetric(
                kind: .claudeSonnet,
                remainingFraction: sonnetFraction,
                remainingValue: sonnetFraction.map { $0 * 100 },
                totalValue: 100,
                unit: .percentage,
                resetAtUTC: response.sevenDay?.resetsAt,
                lastUpdatedAtUTC: now,
                detailText: nil
            ),
        ]

        return ProviderSnapshot(
            provider: id,
            authState: .authenticated,
            fetchState: .ok,
            fetchedAtUTC: now,
            metrics: metrics,
            errorDescription: nil,
            sourceDescription: "Claude Code (OAuth)"
        )
    }

    private func fetchOAuthUsage(token: String) async throws -> OAuthUsageResponse {
        var request = URLRequest(url: oauthUsageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.0.37", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        logStore.append(category: "claude", message: "OAuth usage HTTP \(statusCode) | preview=\(preview(of: data))")

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ClaudeProviderError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let withMillis = ISO8601DateFormatter()
            withMillis.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withMillis.date(from: string) { return date }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let date = plain.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized date: \(string)")
        }

        return try decoder.decode(OAuthUsageResponse.self, from: data)
    }

    // MARK: - Keychain OAuth token read

    /// Returns a valid OAuth access token, using our own Keychain cache to avoid repeated
    /// ACL prompts for Claude Code's Keychain item. Falls back to reading Claude Code's
    /// Keychain directly (which may show a macOS permission dialog on first access).
    private func readOAuthToken() -> String? {
        let now = Date()
        let expiryThreshold = now.addingTimeInterval(5 * 60)

        // Check our cached copy first — no ACL prompt needed since we own this item.
        if let cached = loadCachedOAuthToken() {
            let expiryDate = Date(timeIntervalSince1970: cached.expiresAt / 1000.0)
            if expiryDate > expiryThreshold {
                return cached.accessToken
            }
            // Cache expired — fall through to re-read from Claude Code's Keychain.
        }

        return readAndCacheOAuthToken(expiryThreshold: expiryThreshold)
    }

    /// Reads the token from Claude Code's Keychain item and caches it in our own service.
    /// This is the only call that may trigger a macOS Keychain permission dialog.
    private func readAndCacheOAuthToken(expiryThreshold: Date) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let accessToken = oauth["accessToken"] as? String,
              accessToken.isEmpty == false else {
            return nil
        }

        let expiresAt = oauth["expiresAt"] as? Double ?? 0
        let expiryDate = Date(timeIntervalSince1970: expiresAt / 1000.0)
        if expiryDate < expiryThreshold {
            logStore.append(level: .warning, category: "claude", message: "OAuth token expired at \(expiryDate). Run `claude` to re-authenticate.")
            return nil
        }

        // Cache the token in our own Keychain service so future reads don't prompt.
        let cached = CachedOAuthToken(accessToken: accessToken, expiresAt: expiresAt)
        if let cacheData = try? JSONEncoder().encode(cached) {
            try? keychain.save(data: cacheData, account: oauthTokenCacheAccount)
        }

        return accessToken
    }

    private func loadCachedOAuthToken() -> CachedOAuthToken? {
        guard let data = try? keychain.loadData(account: oauthTokenCacheAccount) else { return nil }
        return try? JSONDecoder().decode(CachedOAuthToken.self, from: data)
    }

    // MARK: - Helpers

    private func missingAuthSnapshot(now: Date) -> ProviderSnapshot {
        ProviderSnapshot(
            provider: id,
            authState: .signedOut,
            fetchState: .missingAuth,
            fetchedAtUTC: nil,
            metrics: placeholderMetrics(now: now),
            errorDescription: nil,
            sourceDescription: sourceDescription
        )
    }

    private func placeholderMetrics(now: Date) -> [UsageMetric] {
        [
            UsageMetric(kind: .claudeFiveHour, remainingFraction: nil, remainingValue: nil, totalValue: nil, unit: .percentage, resetAtUTC: nil, lastUpdatedAtUTC: now, detailText: nil),
            UsageMetric(kind: .claudeWeeklyQuota, remainingFraction: nil, remainingValue: nil, totalValue: nil, unit: .percentage, resetAtUTC: nil, lastUpdatedAtUTC: now, detailText: nil),
            UsageMetric(kind: .claudeDailyCost, remainingFraction: nil, remainingValue: nil, totalValue: nil, unit: .cost, resetAtUTC: nil, lastUpdatedAtUTC: now, detailText: nil),
            UsageMetric(kind: .claudeWeeklyCost, remainingFraction: nil, remainingValue: nil, totalValue: nil, unit: .cost, resetAtUTC: nil, lastUpdatedAtUTC: now, detailText: nil),
            UsageMetric(kind: .claudeSonnet, remainingFraction: nil, remainingValue: nil, totalValue: nil, unit: .percentage, resetAtUTC: nil, lastUpdatedAtUTC: now, detailText: nil),
        ]
    }

    private func nextMidnightUTC(after date: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal.nextDate(after: date, matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime) ?? date.addingTimeInterval(86400)
    }

    private func preview(of data: Data) -> String {
        let text = String(data: data.prefix(320), encoding: .utf8) ?? "<non-utf8>"
        return text.replacingOccurrences(of: "\n", with: " ")
    }
}

// MARK: - OAuth response models

private struct OAuthUsageResponse: Decodable {
    let fiveHour: UsageBucket?
    let sevenDay: UsageBucket?
    let sevenDaySonnet: UsageBucket?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
    }

    struct UsageBucket: Decodable {
        let utilization: Double
        let resetsAt: Date?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }
}

enum ClaudeProviderError: LocalizedError {
    case invalidResponse
    case tokenExpired

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Claude Code usage couldn't be loaded."
        case .tokenExpired:
            return "Claude Code session expired. Open Settings and click \"Allow access\" to reconnect, or run `claude` in Terminal."
        }
    }
}
