import Foundation

struct ClaudeOAuthUsageResponse: Decodable {
    let fiveHour: ClaudeUsageWindow?
    let sevenDay: ClaudeUsageWindow?
    let sevenDayOAuthApps: ClaudeUsageWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOAuthApps = "seven_day_oauth_apps"
    }
}

struct ClaudeUsageWindow: Decodable {
    let utilization: Double?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

enum ClaudeUsageParser {
    static func parseMetrics(from data: Data, now: Date) throws -> [UsageMetric] {
        let response = try JSONDecoder().decode(ClaudeOAuthUsageResponse.self, from: data)
        return parseMetrics(from: response, now: now)
    }

    static func parseMetrics(from response: ClaudeOAuthUsageResponse, now: Date) -> [UsageMetric] {
        let weeklyWindow = response.sevenDay ?? response.sevenDayOAuthApps

        return [
            metric(kind: .claudeFiveHour, window: response.fiveHour, now: now),
            metric(kind: .claudeWeekly, window: weeklyWindow, now: now),
        ]
    }

    static func parseResetDate(_ string: String?) -> Date? {
        guard let string, string.isEmpty == false else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private static func metric(kind: UsageMetricKind, window: ClaudeUsageWindow?, now: Date) -> UsageMetric {
        let utilization = window?.utilization.map { max(0, min(1, $0)) }
        let remainingFraction = utilization.map { max(0, min(1, 1 - $0)) }

        return UsageMetric(
            kind: kind,
            remainingFraction: remainingFraction,
            remainingValue: remainingFraction,
            totalValue: utilization.map { _ in 1 },
            unit: .percentage,
            resetAtUTC: parseResetDate(window?.resetsAt),
            lastUpdatedAtUTC: now,
            detailText: remainingFraction.map { "\(Int(($0 * 100).rounded()))% remaining" }
        )
    }
}
