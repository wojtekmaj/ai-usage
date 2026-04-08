import Foundation

enum CopilotHTMLParser {
    static func parseMetric(text: String, html: String, now: Date) throws -> UsageMetric {
        if let metric = parseCountMetric(in: text, now: now) ?? parseCountMetric(in: html, now: now) {
            return metric
        }

        if let metric = parsePercentageMetric(in: text, now: now) ?? parsePercentageMetric(in: html, now: now) {
            return metric
        }

        throw CopilotProviderError.unrecognizedUsagePayload
    }

    private static func parseCountMetric(in source: String, now: Date) -> UsageMetric? {
        let normalized = normalize(source)

        if let remainingAndTotal = firstGroups(
            pattern: #"(?i)(\d[\d,]*)\s*(?:/|of)\s*(\d[\d,]*)\s+(?:premium requests?|requests?)\s+(?:left|remaining)"#,
            in: normalized
        ) {
            let remaining = parseNumber(remainingAndTotal[0])
            let total = parseNumber(remainingAndTotal[1])
            return buildMetric(remaining: remaining, total: total, now: now)
        }

        if let usedAndTotal = firstGroups(
            pattern: #"(?i)(\d[\d,]*)\s*(?:/|of)\s*(\d[\d,]*)\s+(?:premium requests?|requests?)\s+(?:used|consumed)"#,
            in: normalized
        ) {
            let used = parseNumber(usedAndTotal[0])
            let total = parseNumber(usedAndTotal[1])
            return buildMetric(remaining: max(total - used, 0), total: total, now: now)
        }

        if let usedAndTotal = firstGroups(
            pattern: #"(?i)premium requests?.{0,80}?(\d[\d,]*)\s*(?:/|of)\s*(\d[\d,]*)"#,
            in: normalized
        ) {
            let used = parseNumber(usedAndTotal[0])
            let total = parseNumber(usedAndTotal[1])
            return buildMetric(remaining: max(total - used, 0), total: total, now: now)
        }

        return nil
    }

    private static func parsePercentageMetric(in source: String, now: Date) -> UsageMetric? {
        let normalized = normalize(source)

        if let remainingString = firstGroup(
            pattern: #"(?i)(\d+(?:\.\d+)?)\s*%\s+remaining.{0,80}?premium requests?"#,
            in: normalized
        ) ?? firstGroup(
            pattern: #"(?i)premium requests?.{0,80}?(\d+(?:\.\d+)?)\s*%\s+remaining"#,
            in: normalized
        ) {
            let remainingFraction = min(max(parseNumber(remainingString) / 100, 0), 1)
            return buildMetric(remainingFraction: remainingFraction, now: now)
        }

        if let usedString = firstGroup(
            pattern: #"(?i)(\d+(?:\.\d+)?)\s*%\s+(?:used|consumed|of (?:your )?allowance).{0,80}?premium requests?"#,
            in: normalized
        ) ?? firstGroup(
            pattern: #"(?i)premium requests?.{0,80}?(\d+(?:\.\d+)?)\s*%\s+(?:used|consumed|of (?:your )?allowance)"#,
            in: normalized
        ) ?? firstGroup(
            pattern: #"(?i)premium requests?.{0,160}?aria-valuenow=["'](\d+(?:\.\d+)?)["']"#,
            in: normalized
        ) {
            let usedFraction = min(max(parseNumber(usedString) / 100, 0), 1)
            return buildMetric(remainingFraction: max(1 - usedFraction, 0), now: now)
        }

        return nil
    }

    private static func buildMetric(remaining: Double, total: Double, now: Date) -> UsageMetric {
        let remainingFraction = total > 0 ? min(max(remaining / total, 0), 1) : nil
        return UsageMetric(
            kind: .copilotMonthly,
            remainingFraction: remainingFraction,
            remainingValue: remaining,
            totalValue: total,
            unit: .requests,
            resetAtUTC: CopilotUsageParser.nextReset(after: now),
            lastUpdatedAtUTC: now,
            detailText: total > 0 ? "\(Int(remaining.rounded())) of \(Int(total.rounded())) requests left" : nil
        )
    }

    private static func buildMetric(remainingFraction: Double, now: Date) -> UsageMetric {
        UsageMetric(
            kind: .copilotMonthly,
            remainingFraction: remainingFraction,
            remainingValue: remainingFraction * 100,
            totalValue: 100,
            unit: .percentage,
            resetAtUTC: CopilotUsageParser.nextReset(after: now),
            lastUpdatedAtUTC: now,
            detailText: "\(Int((remainingFraction * 100).rounded()))% remaining"
        )
    }

    private static func normalize(_ source: String) -> String {
        source.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func parseNumber(_ value: String) -> Double {
        Double(value.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    private static func firstGroup(pattern: String, in source: String) -> String? {
        firstGroups(pattern: pattern, in: source)?.first
    }

    private static func firstGroups(pattern: String, in source: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        guard let match = regex.firstMatch(in: source, range: range),
              match.numberOfRanges > 1 else {
            return nil
        }

        return (1..<match.numberOfRanges).compactMap { index in
            guard let groupRange = Range(match.range(at: index), in: source) else {
                return nil
            }

            return String(source[groupRange])
        }
    }
}
