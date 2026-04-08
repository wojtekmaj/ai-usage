import Foundation

enum CopilotUsageParser {
    static func parseMetric(from payload: Any, now: Date) throws -> UsageMetric {
        if let sessionMetric = parseMetricFromBillingSessionCard(payload: payload, now: now) {
            return sessionMetric
        }

        if let reportMetric = parseMetricFromUsageReport(payload: payload, now: now) {
            return reportMetric
        }

        let remaining = findNumber(in: payload, candidateKeys: ["remaining_quota", "remainingQuota", "remaining_requests", "remainingRequests", "quota_remaining", "remaining_included_usage", "remainingIncludedUsage", "remaining_included_quota", "remainingIncludedQuota", "remaining_included_quantity", "remainingIncludedQuantity"])
        let total = findNumber(in: payload, candidateKeys: ["total_monthly_quota", "monthly_quota", "included_usage", "includedUsage", "quota", "total_quota", "included_quota", "includedQuota", "included_quantity", "includedQuantity", "userPremiumRequestEntitlement", "filteredUserPremiumRequestEntitlement"])
        let used = findNumber(in: payload, candidateKeys: ["discountQuantity", "discount_quantity", "used_quota", "usedQuota", "consumed_usage", "consumedUsage", "usage", "used", "used_quantity", "usedQuantity", "included_usage_consumed", "includedUsageConsumed", "netQuantity", "grossQuantity", "quantity"])

        let resolvedRemaining = remaining ?? {
            guard let total, let used else { return nil }
            return max(total - used, 0)
        }()

        let resolvedTotal = total ?? {
            guard let remaining = resolvedRemaining, let used else { return nil }
            return remaining + used
        }()

        guard let resolvedRemaining else {
            throw CopilotProviderError.unrecognizedUsagePayload
        }

        let fraction = resolvedTotal.map { max(0, min(1, resolvedRemaining / max($0, 1))) }
        let detailText: String?
        if let resolvedTotal {
            detailText = "\(Int(resolvedRemaining.rounded())) of \(Int(resolvedTotal.rounded())) requests left"
        } else {
            detailText = "\(Int(resolvedRemaining.rounded())) requests left"
        }

        return UsageMetric(
            kind: .copilotMonthly,
            remainingFraction: fraction,
            remainingValue: resolvedRemaining,
            totalValue: resolvedTotal,
            unit: .requests,
            resetAtUTC: nextReset(after: now),
            lastUpdatedAtUTC: now,
            detailText: detailText
        )
    }

    private static func parseMetricFromBillingSessionCard(payload: Any, now: Date) -> UsageMetric? {
        guard let dictionary = payload as? [String: Any] else {
            return nil
        }

        let total = (findNumber(in: dictionary, candidateKeys: ["userPremiumRequestEntitlement", "filteredUserPremiumRequestEntitlement"]) ?? 0)
        let usedIncluded = findNumber(in: dictionary, candidateKeys: ["discountQuantity", "discount_quantity"]) ?? 0

        guard total > 0 else {
            return nil
        }

        let remaining = max(total - usedIncluded, 0)
        let fraction = max(0, min(1, remaining / total))

        return UsageMetric(
            kind: .copilotMonthly,
            remainingFraction: fraction,
            remainingValue: remaining,
            totalValue: total,
            unit: .requests,
            resetAtUTC: nextReset(after: now),
            lastUpdatedAtUTC: now,
            detailText: "\(Int(remaining.rounded())) of \(Int(total.rounded())) requests left"
        )
    }

    private static func parseMetricFromUsageReport(payload: Any, now: Date) -> UsageMetric? {
        guard let dictionary = payload as? [String: Any] else {
            return nil
        }

        if let usageItems = dictionary["usageItems"] as? [[String: Any]], usageItems.isEmpty {
            return UsageMetric(
                kind: .copilotMonthly,
                remainingFraction: nil,
                remainingValue: nil,
                totalValue: nil,
                unit: .requests,
                resetAtUTC: nextReset(after: now),
                lastUpdatedAtUTC: now,
                detailText: "0 requests used this month"
            )
        }

        let usageItems = gatherUsageItems(in: dictionary)
        guard usageItems.isEmpty == false else {
            return nil
        }

        let copilotItems = usageItems.filter { item in
            let product = normalizedString(item["product"]).lowercased()
            let sku = normalizedString(item["sku"]).lowercased()
            return product.contains("copilot") || sku.contains("premium request") || sku.contains("copilot")
        }

        guard copilotItems.isEmpty == false else {
            return nil
        }

        let totalQuota = findNumber(in: dictionary, candidateKeys: ["total_monthly_quota", "monthly_quota", "included_usage", "includedUsage", "quota", "total_quota", "included_quota", "includedQuota", "included_quantity", "includedQuantity"])
            ?? copilotItems.compactMap { findNumber(in: $0, candidateKeys: ["total_monthly_quota", "monthly_quota", "included_usage", "includedUsage", "quota", "total_quota", "included_quota", "includedQuota", "included_quantity", "includedQuantity"]) }.max()

        let usedValue = copilotItems.reduce(0.0) { partialResult, item in
            partialResult + (findNumber(in: item, candidateKeys: ["netQuantity", "grossQuantity", "quantity", "used_quota", "usedQuota", "used_quantity", "usedQuantity", "consumed_usage", "consumedUsage"]) ?? 0)
        }

        let remainingValue = totalQuota.map { max($0 - usedValue, 0) }
        let fraction = (totalQuota != nil && remainingValue != nil) ? max(0, min(1, (remainingValue ?? 0) / max(totalQuota ?? 1, 1))) : nil

        let detailText: String
        if let totalQuota, let remainingValue {
            detailText = "\(Int(remainingValue.rounded())) of \(Int(totalQuota.rounded())) requests left"
        } else {
            detailText = "\(Int(usedValue.rounded())) requests used this month"
        }

        return UsageMetric(
            kind: .copilotMonthly,
            remainingFraction: fraction,
            remainingValue: remainingValue,
            totalValue: totalQuota,
            unit: .requests,
            resetAtUTC: nextReset(after: now),
            lastUpdatedAtUTC: now,
            detailText: detailText
        )
    }

    static func nextReset(after now: Date) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        let currentMonth = calendar.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: now)
        var nextComponents = DateComponents()
        nextComponents.timeZone = TimeZone(secondsFromGMT: 0)
        nextComponents.year = currentMonth.month == 12 ? (currentMonth.year ?? 0) + 1 : currentMonth.year
        nextComponents.month = currentMonth.month == 12 ? 1 : (currentMonth.month ?? 1) + 1
        nextComponents.day = 1
        nextComponents.hour = 0
        nextComponents.minute = 0
        nextComponents.second = 0
        return calendar.date(from: nextComponents) ?? now
    }

    private static func gatherUsageItems(in payload: [String: Any]) -> [[String: Any]] {
        var results: [[String: Any]] = []

        if let items = payload["usageItems"] as? [[String: Any]] {
            results.append(contentsOf: items)
        }

        for value in payload.values {
            if let dictionary = value as? [String: Any] {
                results.append(contentsOf: gatherUsageItems(in: dictionary))
            } else if let array = value as? [Any] {
                for item in array {
                    if let dictionary = item as? [String: Any] {
                        results.append(contentsOf: gatherUsageItems(in: dictionary))
                    }
                }
            }
        }

        return results
    }

    private static func normalizedString(_ value: Any?) -> String {
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return ""
    }

    private static func findNumber(in payload: Any, candidateKeys: [String]) -> Double? {
        if let dictionary = payload as? [String: Any] {
            for key in candidateKeys {
                if let rawValue = dictionary[key] {
                    if let number = rawValue as? NSNumber {
                        return number.doubleValue
                    }
                    if let string = rawValue as? String, let value = Double(string) {
                        return value
                    }
                }
            }

            for value in dictionary.values {
                if let nested = findNumber(in: value, candidateKeys: candidateKeys) {
                    return nested
                }
            }
        }

        if let array = payload as? [Any] {
            for value in array {
                if let nested = findNumber(in: value, candidateKeys: candidateKeys) {
                    return nested
                }
            }
        }

        return nil
    }
}
