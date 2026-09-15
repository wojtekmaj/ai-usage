import Foundation
import Testing
@testable import AiUsageApp

struct ModelsTests {
    @Test
    func convertsCopilotCreditsToDollars() {
        var metric = copilotMetric

        #expect(metric.remainingDollars == 23.4)
        #expect(metric.totalDollars == 30)

        metric.remainingValue = 0

        #expect(metric.remainingDollars == 0)
    }

    @Test
    func dollarAmountsRequireAICredits() {
        var metric = copilotMetric
        metric.unit = .requests

        #expect(metric.remainingDollars == nil)
        #expect(metric.totalDollars == nil)
    }

    @Test
    func preservesIndependentlyMissingDollarAmounts() {
        var metric = copilotMetric
        metric.remainingValue = nil

        #expect(metric.remainingDollars == nil)
        #expect(metric.totalDollars == 30)

        metric.remainingValue = 2_340
        metric.totalValue = nil

        #expect(metric.remainingDollars == 23.4)
        #expect(metric.totalDollars == nil)
    }

    @Test(arguments: [-1, Double.infinity, Double.nan])
    func invalidCreditAmountsAreUnavailable(credits: Double) {
        var metric = copilotMetric
        metric.remainingValue = credits
        metric.totalValue = credits

        #expect(metric.remainingDollars == nil)
        #expect(metric.totalDollars == nil)
    }

    private var copilotMetric: UsageMetric {
        UsageMetric(
            kind: .copilotMonthly,
            remainingFraction: 0.78,
            remainingValue: 2_340,
            totalValue: 3_000,
            unit: .credits,
            resetAtUTC: nil,
            lastUpdatedAtUTC: .now,
            detailText: nil
        )
    }
}
