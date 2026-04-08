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
    func parsesBillingOverviewCountsFromHtml() throws {
        let now = Date(timeIntervalSince1970: 1_775_000_000)
        let text = "Metered usage Copilot premium requests 120 of 300 premium requests used this month"
        let html = "<section><h2>Metered usage</h2><div>Copilot premium requests 120 of 300 premium requests used this month</div></section>"

        let metric = try CopilotHTMLParser.parseMetric(text: text, html: html, now: now)

        #expect(metric.remainingValue == 180)
        #expect(metric.totalValue == 300)
        #expect(metric.remainingFraction == 0.6)
    }

    @Test
    func parsesBillingOverviewPercentFromHtml() throws {
        let now = Date(timeIntervalSince1970: 1_775_000_000)
        let text = "Copilot premium requests 40% of your allowance used"
        let html = "<div>Copilot premium requests 40% of your allowance used</div>"

        let metric = try CopilotHTMLParser.parseMetric(text: text, html: html, now: now)

        #expect(metric.remainingFraction == 0.6)
        #expect(metric.totalValue == 100)
        #expect(metric.remainingValue == 60)
    }
}
