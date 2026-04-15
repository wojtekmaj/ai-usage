import Foundation

enum CodexHTMLParser {
    static func parse(apiPayload: Any, now: Date) throws -> [UsageMetric] {
        guard let payload = apiPayload as? [String: Any] else {
            throw CodexParserError.unrecognizedAPIResponse
        }

        var metrics: [UsageMetric] = []

        if let rateLimit = payload["rate_limit"] as? [String: Any] {
            if let primaryWindow = rateLimit["primary_window"] as? [String: Any],
               let metric = apiMetric(from: primaryWindow, kind: .codexFiveHour, now: now) {
                metrics.append(metric)
            }

            if let secondaryWindow = rateLimit["secondary_window"] as? [String: Any],
               let metric = apiMetric(from: secondaryWindow, kind: .codexWeekly, now: now) {
                metrics.append(metric)
            }
        }

        if let additionalRateLimits = payload["additional_rate_limits"] as? [[String: Any]],
           let codexSpark = additionalRateLimits.first(where: isCodexSparkLimit(_:)),
           let rateLimit = codexSpark["rate_limit"] as? [String: Any] {
            if let primaryWindow = rateLimit["primary_window"] as? [String: Any],
               let metric = apiMetric(from: primaryWindow, kind: .codexSparkFiveHour, now: now) {
                metrics.append(metric)
            }

            if let secondaryWindow = rateLimit["secondary_window"] as? [String: Any],
               let metric = apiMetric(from: secondaryWindow, kind: .codexSparkWeekly, now: now) {
                metrics.append(metric)
            }
        }

        if let credits = payload["credits"] as? [String: Any],
           let balance = number(from: credits["balance"]) {
            metrics.append(
                UsageMetric(
                    kind: .codexCredits,
                    remainingFraction: nil,
                    remainingValue: balance,
                    totalValue: nil,
                    unit: .credits,
                    resetAtUTC: nil,
                    lastUpdatedAtUTC: now,
                    detailText: "\(Int(balance.rounded())) credits"
                )
            )
        }

        guard metrics.isEmpty == false else {
            throw CodexParserError.unrecognizedAPIResponse
        }

        return completedMetrics(from: metrics, now: now)
    }

    private static func completedMetrics(from parsed: [UsageMetric], now: Date) -> [UsageMetric] {
        var dictionary = Dictionary(uniqueKeysWithValues: parsed.map { ($0.kind, $0) })

        for kind in UsageMetricKind.allCases where kind.provider == .codex && dictionary[kind] == nil {
            dictionary[kind] = UsageMetric(
                kind: kind,
                remainingFraction: nil,
                remainingValue: nil,
                totalValue: nil,
                unit: kind == .codexCredits ? .credits : .percentage,
                resetAtUTC: nil,
                lastUpdatedAtUTC: now,
                detailText: nil
            )
        }

        return [.codexFiveHour, .codexWeekly, .codexSparkFiveHour, .codexSparkWeekly, .codexCredits].compactMap { dictionary[$0] }
    }

    private static func isCodexSparkLimit(_ item: [String: Any]) -> Bool {
        if let limitName = item["limit_name"] as? String, limitName == "GPT-5.3-Codex-Spark" {
            return true
        }

        if let meteredFeature = item["metered_feature"] as? String, meteredFeature == "codex_bengalfox" {
            return true
        }

        return false
    }

    private static func apiMetric(from window: [String: Any], kind: UsageMetricKind, now: Date) -> UsageMetric? {
        guard let usedPercent = number(from: window["used_percent"]) else {
            return nil
        }

        let remainingFraction = max(0, min(1, 1 - (usedPercent / 100)))
        let resetAtUTC = number(from: window["reset_at"]).map { Date(timeIntervalSince1970: $0) }

        return UsageMetric(
            kind: kind,
            remainingFraction: remainingFraction,
            remainingValue: remainingFraction * 100,
            totalValue: 100,
            unit: .percentage,
            resetAtUTC: resetAtUTC,
            lastUpdatedAtUTC: now,
            detailText: "\(Int((remainingFraction * 100).rounded()))% remaining"
        )
    }

    private static func number(from value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            return Double(string)
        }
        return nil
    }
}

enum CodexParserError: LocalizedError {
    case unrecognizedAPIResponse

    var errorDescription: String? {
        switch self {
        case .unrecognizedAPIResponse:
            return "The Codex usage API did not expose recognizable usage or credit metrics."
        }
    }
}
