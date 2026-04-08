import Foundation
import Testing
@testable import AiUsageApp

struct ScheduleEvaluatorTests {
    @Test
    func paceAssessmentUsesSmallerTriggerForUIComparison() {
        let evaluator = ScheduleEvaluator()
        let now = Date(timeIntervalSince1970: 1_776_056_400) // 2026-04-15 12:00:00 UTC
        let resetAt = Date(timeIntervalSince1970: 1_777_420_800) // 2026-05-01 00:00:00 UTC

        let aheadMetric = UsageMetric(
            kind: .copilotMonthly,
            remainingFraction: 0.39,
            remainingValue: 390,
            totalValue: 1_000,
            unit: .requests,
            resetAtUTC: resetAt,
            lastUpdatedAtUTC: now,
            detailText: nil
        )

        let ahead = evaluator.paceAssessment(metric: aheadMetric, now: now)
        #expect(ahead?.state == .ahead)

        let onTrackMetric = UsageMetric(
            kind: .copilotMonthly,
            remainingFraction: 0.47,
            remainingValue: 470,
            totalValue: 1_000,
            unit: .requests,
            resetAtUTC: resetAt,
            lastUpdatedAtUTC: now,
            detailText: nil
        )

        let onTrack = evaluator.paceAssessment(metric: onTrackMetric, now: now)
        #expect(onTrack?.state == .onTrack)

        let behindMetric = UsageMetric(
            kind: .copilotMonthly,
            remainingFraction: 0.62,
            remainingValue: 620,
            totalValue: 1_000,
            unit: .requests,
            resetAtUTC: resetAt,
            lastUpdatedAtUTC: now,
            detailText: nil
        )

        let behind = evaluator.paceAssessment(metric: behindMetric, now: now)
        #expect(behind?.state == .behind)
    }

    @Test
    func paceAssessmentWorksForFiveHourWindows() {
        let evaluator = ScheduleEvaluator()
        let now = Date(timeIntervalSince1970: 1_744_128_000)
        let metric = UsageMetric(
            kind: .codexFiveHour,
            remainingFraction: 0.99,
            remainingValue: 99,
            totalValue: 100,
            unit: .percentage,
            resetAtUTC: now.addingTimeInterval(5 * 60 * 60),
            lastUpdatedAtUTC: now,
            detailText: nil
        )

        let result = evaluator.paceAssessment(metric: metric, now: now)
        #expect(result?.expectedRemaining == 1)
        #expect(result?.state == .onTrack)
    }

    @Test
    func aheadAlertRequiresRearmBeforeRepeating() {
        let evaluator = ScheduleEvaluator()
        let now = Date(timeIntervalSince1970: 1_776_056_400) // 2026-04-15 12:00:00 UTC
        let resetAt = Date(timeIntervalSince1970: 1_777_420_800) // 2026-05-01 00:00:00 UTC

        let firstMetric = UsageMetric(
            kind: .copilotMonthly,
            remainingFraction: 0.30,
            remainingValue: 300,
            totalValue: 1_000,
            unit: .requests,
            resetAtUTC: resetAt,
            lastUpdatedAtUTC: now,
            detailText: nil
        )

        let first = evaluator.evaluate(metric: firstMetric, direction: .ahead, previousState: nil, now: now)
        #expect(first?.shouldNotify == true)
        #expect(first?.state.isArmed == false)

        let stillAheadMetric = UsageMetric(
            kind: .copilotMonthly,
            remainingFraction: 0.34,
            remainingValue: 340,
            totalValue: 1_000,
            unit: .requests,
            resetAtUTC: resetAt,
            lastUpdatedAtUTC: now,
            detailText: nil
        )

        let second = evaluator.evaluate(metric: stillAheadMetric, direction: .ahead, previousState: first?.state, now: now)
        #expect(second?.shouldNotify == false)
        #expect(second?.state.isArmed == false)

        let recoveredMetric = UsageMetric(
            kind: .copilotMonthly,
            remainingFraction: 0.80,
            remainingValue: 800,
            totalValue: 1_000,
            unit: .requests,
            resetAtUTC: resetAt,
            lastUpdatedAtUTC: now,
            detailText: nil
        )

        let rearmed = evaluator.evaluate(metric: recoveredMetric, direction: .ahead, previousState: second?.state, now: now)
        #expect(rearmed?.shouldNotify == false)
        #expect(rearmed?.state.isArmed == true)

        let aheadAgainMetric = UsageMetric(
            kind: .copilotMonthly,
            remainingFraction: 0.25,
            remainingValue: 250,
            totalValue: 1_000,
            unit: .requests,
            resetAtUTC: resetAt,
            lastUpdatedAtUTC: now,
            detailText: nil
        )

        let third = evaluator.evaluate(metric: aheadAgainMetric, direction: .ahead, previousState: rearmed?.state, now: now)
        #expect(third?.shouldNotify == true)
    }

    @Test
    func behindAlertsIgnoreUnsupportedWindows() {
        let evaluator = ScheduleEvaluator()
        let now = Date(timeIntervalSince1970: 1_744_128_000)
        let metric = UsageMetric(
            kind: .codexFiveHour,
            remainingFraction: 0.95,
            remainingValue: 95,
            totalValue: 100,
            unit: .percentage,
            resetAtUTC: now.addingTimeInterval(5 * 60 * 60),
            lastUpdatedAtUTC: now,
            detailText: nil
        )

        let result = evaluator.evaluate(metric: metric, direction: .behind, previousState: nil, now: now)
        #expect(result == nil)
    }
}
