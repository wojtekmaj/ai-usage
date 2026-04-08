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

    static func parse(text: String, html: String, now: Date) throws -> [UsageMetric] {
        let fiveHour = parseWindowMetric(
            kind: .codexFiveHour,
            text: text,
            html: html,
            labelPatterns: ["5-hour", "5 hour", "5hr", "5-godzin", "5 godzin"],
            now: now
        )

        let weekly = parseWindowMetric(
            kind: .codexWeekly,
            text: text,
            html: html,
            labelPatterns: ["weekly", "7-day", "7 day", "tygodniowy"],
            now: now
        )

        let credits = parseCreditsMetric(text: text, html: html, now: now)

        let metrics = [fiveHour, weekly, credits].compactMap { $0 }
        guard metrics.isEmpty == false else {
            throw CodexParserError.noUsageMetricsFound
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

        return [.codexFiveHour, .codexWeekly, .codexCredits].compactMap { dictionary[$0] }
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

    private static func parseWindowMetric(kind: UsageMetricKind, text: String, html: String, labelPatterns: [String], now: Date) -> UsageMetric? {
        let fraction = firstPercentage(in: text, labelPatterns: labelPatterns) ?? firstPercentage(in: html, labelPatterns: labelPatterns)
        let resetAtUTC = firstTimestamp(in: html, labelPatterns: labelPatterns) ?? firstResetTextDate(in: text, labelPatterns: labelPatterns)

        guard let fraction else {
            return nil
        }

        return UsageMetric(
            kind: kind,
            remainingFraction: fraction,
            remainingValue: fraction * 100,
            totalValue: 100,
            unit: .percentage,
            resetAtUTC: resetAtUTC,
            lastUpdatedAtUTC: now,
            detailText: "\(Int((fraction * 100).rounded()))% remaining"
        )
    }

    private static func parseCreditsMetric(text: String, html: String, now: Date) -> UsageMetric? {
        let balance = firstNumber(near: ["credit balance", "credits balance", "remaining credits", "credits remaining", "pozostałe kredyty"], in: text)
            ?? firstNumber(near: ["credit_balance", "credits_balance", "remainingCredits", "creditsRemaining"], in: html)

        guard let balance else {
            return nil
        }

        let resetAtUTC = firstTimestamp(in: html, labelPatterns: ["credit expiry", "credits expire", "expiry", "expires"])

        return UsageMetric(
            kind: .codexCredits,
            remainingFraction: nil,
            remainingValue: balance,
            totalValue: nil,
            unit: .credits,
            resetAtUTC: resetAtUTC,
            lastUpdatedAtUTC: now,
            detailText: "\(Int(balance.rounded())) credits"
        )
    }

    private static func firstPercentage(in source: String, labelPatterns: [String]) -> Double? {
        for label in labelPatterns {
            let escaped = NSRegularExpression.escapedPattern(for: label)
            let patterns = [
                "(?i)\(escaped).{0,120}?([0-9]{1,3})\\s*%",
                "(?i)([0-9]{1,3})\\s*%.{0,80}?\(escaped)",
            ]

            for pattern in patterns {
                if let percentage = firstMatch(pattern: pattern, in: source) {
                    return max(0, min(1, percentage / 100))
                }
            }
        }

        return nil
    }

    private static func firstNumber(near labelPatterns: [String], in source: String) -> Double? {
        for label in labelPatterns {
            let escaped = NSRegularExpression.escapedPattern(for: label)
            let patterns = [
                "(?i)\(escaped).{0,40}?([0-9]+(?:[.,][0-9]+)?)",
                "(?i)([0-9]+(?:[.,][0-9]+)?).{0,20}?\(escaped)",
            ]

            for pattern in patterns {
                if let number = firstMatch(pattern: pattern, in: source) {
                    return number
                }
            }
        }

        return nil
    }

    private static func firstTimestamp(in source: String, labelPatterns: [String]) -> Date? {
        for label in labelPatterns {
            let escaped = NSRegularExpression.escapedPattern(for: label)
            let patterns = [
                "(?i)\(escaped).{0,160}?([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.+-Z]+)",
                "(?i)\(escaped).{0,160}?([0-9]{10,13})",
                "(?i)(?:reset|resets|expires|expiry).{0,80}?([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.+-Z]+)",
            ]

            for pattern in patterns {
                if let string = firstStringMatch(pattern: pattern, in: source),
                   let date = parseTimestamp(string) {
                    return date
                }
            }
        }

        return nil
    }

    private static func firstResetTextDate(in source: String, labelPatterns: [String]) -> Date? {
        for label in labelPatterns {
            let escaped = NSRegularExpression.escapedPattern(for: label)
            let pattern = "(?i)\(escaped).{0,160}?(?:reset|resets|expires|expiry).{0,40}?([A-Z][a-z]{2,8}\\s+[0-9]{1,2},\\s+[0-9]{4},?\\s+[0-9]{1,2}:[0-9]{2}(?:\\s?[AP]M)?)"
            if let string = firstStringMatch(pattern: pattern, in: source) {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = .autoupdatingCurrent
                formatter.dateFormat = "MMMM d, yyyy, h:mm a"
                if let date = formatter.date(from: string) {
                    return date
                }

                formatter.dateFormat = "MMM d, yyyy, h:mm a"
                if let date = formatter.date(from: string) {
                    return date
                }
            }
        }

        return nil
    }

    private static func parseTimestamp(_ string: String) -> Date? {
        if let value = Double(string) {
            let seconds = string.count > 10 ? value / 1000 : value
            return Date(timeIntervalSince1970: seconds)
        }

        let formatterWithFractionalSeconds = ISO8601DateFormatter()
        formatterWithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatterWithFractionalSeconds.date(from: string) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private static func firstMatch(pattern: String, in source: String) -> Double? {
        guard let string = firstStringMatch(pattern: pattern, in: source) else {
            return nil
        }

        return Double(string.replacingOccurrences(of: ",", with: "."))
    }

    private static func firstStringMatch(pattern: String, in source: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        guard let match = regex.firstMatch(in: source, range: range),
              match.numberOfRanges > 1,
              let groupRange = Range(match.range(at: 1), in: source) else {
            return nil
        }

        return String(source[groupRange])
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
    case noUsageMetricsFound
    case unrecognizedAPIResponse

    var errorDescription: String? {
        switch self {
        case .noUsageMetricsFound:
            return "The Codex usage page did not expose recognizable 5-hour, weekly, or credit metrics."
        case .unrecognizedAPIResponse:
            return "The Codex API response did not expose recognizable 5-hour, weekly, or credit metrics."
        }
    }
}