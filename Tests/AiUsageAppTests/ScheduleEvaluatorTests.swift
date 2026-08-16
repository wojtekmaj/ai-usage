import Foundation
import Testing
@testable import AiUsageApp

struct UsagePaceEvaluatorTests {
    @Test
    func usesTheDisplayThresholdForMonthlyWindows() {
        let evaluator = UsagePaceEvaluator()
        let now = Date(timeIntervalSince1970: 1_776_056_400)
        let resetAt = Date(timeIntervalSince1970: 1_777_420_800)

        #expect(evaluator.assess(metric: metric(.copilotMonthly, remaining: 0.39, now: now, resetAt: resetAt), now: now)?.state == .ahead)
        #expect(evaluator.assess(metric: metric(.copilotMonthly, remaining: 0.47, now: now, resetAt: resetAt), now: now)?.state == .onTrack)
        #expect(evaluator.assess(metric: metric(.copilotMonthly, remaining: 0.62, now: now, resetAt: resetAt), now: now)?.state == .behind)
    }

    @Test
    func startsFiveHourWindowsAtFullExpectedUsage() {
        let evaluator = UsagePaceEvaluator()
        let now = Date(timeIntervalSince1970: 1_744_128_000)
        let result = evaluator.assess(
            metric: metric(
                .codexFiveHour,
                remaining: 0.99,
                now: now,
                resetAt: now.addingTimeInterval(5 * 60 * 60)
            ),
            now: now
        )

        #expect(result?.expectedRemaining == 1)
        #expect(result?.state == .onTrack)
    }

    private func metric(
        _ kind: UsageMetricKind,
        remaining: Double,
        now: Date,
        resetAt: Date
    ) -> UsageMetric {
        UsageMetric(
            kind: kind,
            remainingFraction: remaining,
            remainingValue: remaining * 100,
            totalValue: 100,
            unit: .percentage,
            resetAtUTC: resetAt,
            lastUpdatedAtUTC: now,
            detailText: nil
        )
    }
}
