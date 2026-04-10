import Foundation

enum CopilotUsageParser {
    static func parseMetric(from payload: Any, now: Date) throws -> UsageMetric {
        if let internalMetric = parseMetricFromCopilotInternalPayload(payload: payload, now: now) {
            return internalMetric
        }

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

    private static func parseMetricFromCopilotInternalPayload(payload: Any, now: Date) -> UsageMetric? {
        guard let dictionary = payload as? [String: Any] else {
            return nil
        }

        let quotaSnapshots = (dictionary["quota_snapshots"] as? [String: Any]) ?? (dictionary["quotaSnapshots"] as? [String: Any]) ?? [:]
        let premium = quotaSnapshot(from: quotaSnapshots["premium_interactions"], quotaIDFallback: "premium_interactions")
        let chat = quotaSnapshot(from: quotaSnapshots["chat"], quotaIDFallback: "chat")
        let unknown = quotaSnapshots.values.compactMap { quotaSnapshot(from: $0, quotaIDFallback: nil) }
            .first(where: \.isUsable)

        let resolvedPremium = premium?.isUsable == true ? premium : nil
        let resolvedChat = chat?.isUsable == true ? chat : nil

        let monthlyQuotas = (dictionary["monthly_quotas"] as? [String: Any]) ?? (dictionary["monthlyQuotas"] as? [String: Any]) ?? [:]
        let limitedQuotas = (dictionary["limited_user_quotas"] as? [String: Any]) ?? (dictionary["limitedUserQuotas"] as? [String: Any]) ?? [:]

        let fallbackPremium = quotaSnapshotFromMonthly(
            entitlement: monthlyQuotas["completions"] ?? monthlyQuotas["premium_interactions"],
            remaining: limitedQuotas["completions"] ?? limitedQuotas["premium_interactions"],
            quotaID: "completions"
        )
        let fallbackChat = quotaSnapshotFromMonthly(
            entitlement: monthlyQuotas["chat"],
            remaining: limitedQuotas["chat"],
            quotaID: "chat"
        )

        let selected = resolvedPremium
            ?? fallbackPremium
            ?? resolvedChat
            ?? fallbackChat
            ?? unknown

        guard let selected, let remaining = selected.remaining else {
            return nil
        }

        let total = selected.entitlement
        let fraction = selected.percentRemaining.map { max(0, min(1, $0 / 100)) }
        let resetAt = parseResetDate(from: dictionary["quota_reset_date"] ?? dictionary["quotaResetDate"]) ?? nextReset(after: now)

        let detailText: String
        if let total {
            detailText = "\(Int(remaining.rounded())) of \(Int(total.rounded())) requests left"
        } else {
            detailText = "\(Int(remaining.rounded())) requests left"
        }

        return UsageMetric(
            kind: .copilotMonthly,
            remainingFraction: fraction,
            remainingValue: remaining,
            totalValue: total,
            unit: .requests,
            resetAtUTC: resetAt,
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

    private static func quotaSnapshot(from payload: Any?, quotaIDFallback: String?) -> CopilotQuotaSnapshot? {
        guard let dictionary = payload as? [String: Any] else {
            return nil
        }

        let entitlement = number(from: dictionary["entitlement"])
        let remaining = number(from: dictionary["remaining"])
        let quotaID = normalizedString(dictionary["quota_id"]).isEmpty ? quotaIDFallback : normalizedString(dictionary["quota_id"])
        let percentRemaining = number(from: dictionary["percent_remaining"])
            ?? {
                guard let entitlement, let remaining, entitlement > 0 else {
                    return nil
                }
                return (remaining / entitlement) * 100
            }()

        return CopilotQuotaSnapshot(
            quotaID: quotaID,
            entitlement: entitlement,
            remaining: remaining,
            percentRemaining: percentRemaining
        )
    }

    private static func quotaSnapshotFromMonthly(entitlement: Any?, remaining: Any?, quotaID: String) -> CopilotQuotaSnapshot? {
        guard let entitlementValue = number(from: entitlement),
              let remainingValue = number(from: remaining),
              entitlementValue > 0 else {
            return nil
        }

        return CopilotQuotaSnapshot(
            quotaID: quotaID,
            entitlement: entitlementValue,
            remaining: remainingValue,
            percentRemaining: (remainingValue / entitlementValue) * 100
        )
    }

    private static func parseResetDate(from payload: Any?) -> Date? {
        guard let string = payload as? String, string.isEmpty == false else {
            return nil
        }

        let dateTimeFormatter = ISO8601DateFormatter()
        dateTimeFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = dateTimeFormatter.date(from: string) {
            return date
        }

        dateTimeFormatter.formatOptions = [.withInternetDateTime]
        if let date = dateTimeFormatter.date(from: string) {
            return date
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
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

    private static func number(from value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }

        if let string = value as? String {
            return Double(string)
        }

        return nil
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

private struct CopilotQuotaSnapshot {
    let quotaID: String?
    let entitlement: Double?
    let remaining: Double?
    let percentRemaining: Double?

    var isUsable: Bool {
        remaining != nil && percentRemaining != nil
    }
}
