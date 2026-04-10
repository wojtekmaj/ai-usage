import Foundation
import Testing
@testable import AiUsageApp

struct CopilotUsageParserTests {
    @Test
    func parsesUsageReportPayloadFromGitHubBillingAPI() throws {
        let now = Date(timeIntervalSince1970: 1_744_128_000)
        let payload: [String: Any] = [
            "usageItems": [
                [
                    "product": "Copilot",
                    "sku": "Copilot Premium Request",
                    "netQuantity": 125,
                    "total_monthly_quota": 300,
                ]
            ]
        ]

        let metric = try CopilotUsageParser.parseMetric(from: payload, now: now)

        #expect(metric.remainingValue == 175)
        #expect(metric.totalValue == 300)
        #expect(metric.remainingFraction == 175.0 / 300.0)
    }

    @Test
    func parsesNestedQuotaPayload() throws {
        let now = Date(timeIntervalSince1970: 1_744_128_000) // 2025-04-15 UTC
        let payload: [String: Any] = [
            "account": [
                "quota": [
                    "total_monthly_quota": 1_000,
                    "remaining_quota": 275,
                ]
            ]
        ]

        let metric = try CopilotUsageParser.parseMetric(from: payload, now: now)

        #expect(metric.kind == .copilotMonthly)
        #expect(metric.remainingValue == 275)
        #expect(metric.totalValue == 1_000)
        #expect(metric.remainingFraction == 0.275)
        #expect(metric.resetAtUTC == Date(timeIntervalSince1970: 1_746_057_600))
    }

    @Test
    func parsesIncludedUsageFieldsFromMonthlyBillingPayload() throws {
        let now = Date(timeIntervalSince1970: 1_775_000_000)
        let payload: [String: Any] = [
            "billing": [
                "included_quantity": 300,
                "remaining_included_quantity": 180,
                "used_quantity": 120,
            ]
        ]

        let metric = try CopilotUsageParser.parseMetric(from: payload, now: now)

        #expect(metric.remainingValue == 180)
        #expect(metric.totalValue == 300)
        #expect(metric.remainingFraction == 0.6)
    }

    @Test
    func parsesGitHubBillingSessionCardPayload() throws {
        let now = Date(timeIntervalSince1970: 1_775_000_000)
        let payload: [String: Any] = [
            "netBilledAmount": 0,
            "netQuantity": 0,
            "discountQuantity": 51.4,
            "userPremiumRequestEntitlement": 300,
            "filteredUserPremiumRequestEntitlement": 0,
        ]

        let metric = try CopilotUsageParser.parseMetric(from: payload, now: now)

        #expect(metric.totalValue == 300)
        #expect(metric.remainingValue == 248.6)
        #expect(metric.remainingFraction == 248.6 / 300)
    }

    @Test
    func parsesCopilotInternalQuotaSnapshotsPayload() throws {
        let now = Date(timeIntervalSince1970: 1_775_000_000)
        let payload: [String: Any] = [
            "copilot_plan": "free",
            "quota_reset_date": "2025-02-01",
            "quota_snapshots": [
                "premium_interactions": [
                    "entitlement": 500,
                    "remaining": 450,
                    "percent_remaining": 90,
                    "quota_id": "premium_interactions",
                ],
                "chat": [
                    "entitlement": 300,
                    "remaining": 150,
                    "percent_remaining": 50,
                    "quota_id": "chat",
                ],
            ],
        ]

        let metric = try CopilotUsageParser.parseMetric(from: payload, now: now)

        #expect(metric.remainingValue == 450)
        #expect(metric.totalValue == 500)
        #expect(metric.remainingFraction == 0.9)
        #expect(metric.resetAtUTC == Date(timeIntervalSince1970: 1_738_368_000))
    }

    @Test
    func fallsBackToChatQuotaWhenPremiumInteractionsAreUnavailable() throws {
        let now = Date(timeIntervalSince1970: 1_775_000_000)
        let payload: [String: Any] = [
            "copilot_plan": "free",
            "quota_snapshots": [
                "chat": [
                    "entitlement": 200,
                    "remaining": 75,
                    "percent_remaining": 37.5,
                    "quota_id": "chat",
                ],
            ],
        ]

        let metric = try CopilotUsageParser.parseMetric(from: payload, now: now)

        #expect(metric.remainingValue == 75)
        #expect(metric.totalValue == 200)
        #expect(metric.remainingFraction == 0.375)
    }

    @Test
    func fallsBackToMonthlyQuotaPayloadWhenDirectSnapshotsAreMissing() throws {
        let now = Date(timeIntervalSince1970: 1_775_000_000)
        let payload: [String: Any] = [
            "copilot_plan": "free",
            "monthly_quotas": [
                "completions": 300,
            ],
            "limited_user_quotas": [
                "completions": 60,
            ],
        ]

        let metric = try CopilotUsageParser.parseMetric(from: payload, now: now)

        #expect(metric.remainingValue == 60)
        #expect(metric.totalValue == 300)
        #expect(metric.remainingFraction == 0.2)
    }
}
