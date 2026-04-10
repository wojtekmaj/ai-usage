import Foundation

enum ClaudeAPIClient {
    struct DailyResult {
        let totalCostUSD: Double
        let sonnetFraction: Double?
    }

    struct WeeklyResult {
        let totalCostUSD: Double
        let sonnetFraction: Double?
    }

    // MARK: - Public

    static func fetchDaily(adminKey: String, date: Date) async throws -> DailyResult {
        let dateStr = yyyyMMDD(date)
        let url = try buildURL(
            path: "/v1/organizations/usage_report/claude_code",
            queryItems: [
                URLQueryItem(name: "starting_at", value: dateStr),
                URLQueryItem(name: "limit", value: "1000"),
            ]
        )

        let data = try await fetch(url: url, adminKey: adminKey)
        let response = try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)
        return daily(from: response.data)
    }

    /// Fetch cost and Sonnet fraction for a rolling 7-day window ending today.
    /// Makes one API call per day (7 total) to the claude_code endpoint.
    static func fetchWeekly(adminKey: String, startDate: Date) async throws -> WeeklyResult {
        var allRecords: [ClaudeUsageRecord] = []

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!

        var cursor = startDate
        let today = Date()

        while cursor <= today {
            let dateStr = yyyyMMDD(cursor)
            let url = try buildURL(
                path: "/v1/organizations/usage_report/claude_code",
                queryItems: [
                    URLQueryItem(name: "starting_at", value: dateStr),
                    URLQueryItem(name: "limit", value: "1000"),
                ]
            )
            let data = try await fetch(url: url, adminKey: adminKey)
            let response = try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)
            allRecords.append(contentsOf: response.data)

            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return weeklyFromRecords(allRecords)
    }

    // MARK: - Networking

    private static func fetch(url: URL, adminKey: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(adminKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            if http.statusCode == 401 || http.statusCode == 403 {
                throw ClaudeAPIError.unauthorized
            }
            throw ClaudeAPIError.httpFailure(http.statusCode, body)
        }

        return data
    }

    private static func buildURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.anthropic.com"
        components.path = path
        components.queryItems = queryItems
        guard let url = components.url else {
            throw ClaudeAPIError.invalidResponse
        }
        return url
    }

    // MARK: - Aggregation

    private static func daily(from records: [ClaudeUsageRecord]) -> DailyResult {
        var total = 0.0
        var sonnetCost = 0.0

        for record in records {
            for breakdown in record.modelBreakdown {
                let cost = breakdown.estimatedCost.amountInUSD
                total += cost
                if breakdown.model.lowercased().contains("sonnet") {
                    sonnetCost += cost
                }
            }
        }

        let sonnetFraction: Double? = total > 0 ? sonnetCost / total : nil
        return DailyResult(totalCostUSD: total, sonnetFraction: sonnetFraction)
    }

    private static func weeklyFromRecords(_ records: [ClaudeUsageRecord]) -> WeeklyResult {
        var total = 0.0
        var sonnetCost = 0.0

        for record in records {
            for breakdown in record.modelBreakdown {
                let cost = breakdown.estimatedCost.amountInUSD
                total += cost
                if breakdown.model.lowercased().contains("sonnet") {
                    sonnetCost += cost
                }
            }
        }

        let sonnetFraction: Double? = total > 0 ? sonnetCost / total : nil
        return WeeklyResult(totalCostUSD: total, sonnetFraction: sonnetFraction)
    }

    // MARK: - Date formatting

    private static func yyyyMMDD(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}

// MARK: - Response models

private struct ClaudeUsageResponse: Decodable {
    let data: [ClaudeUsageRecord]
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
    }
}

private struct ClaudeUsageRecord: Decodable {
    let modelBreakdown: [ModelBreakdown]

    enum CodingKeys: String, CodingKey {
        case modelBreakdown = "model_breakdown"
    }

    struct ModelBreakdown: Decodable {
        let model: String
        let estimatedCost: CostAmount

        enum CodingKeys: String, CodingKey {
            case model
            case estimatedCost = "estimated_cost"
        }
    }

    struct CostAmount: Decodable {
        let amount: Double    // minor units (cents)
        let currency: String

        var amountInUSD: Double { amount / 100.0 }
    }
}


// MARK: - Errors

enum ClaudeAPIError: LocalizedError {
    case invalidResponse
    case unauthorized
    case httpFailure(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Claude Code API returned an unexpected response."
        case .unauthorized:
            return "Admin API key is invalid or lacks permission."
        case let .httpFailure(status, body):
            return body.isEmpty
                ? "Claude Code API request failed with status \(status)."
                : "Claude Code API request failed with status \(status): \(body)"
        }
    }
}
