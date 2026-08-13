import Foundation
import Testing
@testable import AiUsageApp

struct UsageMetricAvailabilityTests {
    @Test
    func codexUsageLimitWithoutValuesIsUnavailable() {
        let metric = UsageMetric(
            kind: .codexFiveHour,
            remainingFraction: nil,
            remainingValue: nil,
            totalValue: nil,
            unit: .percentage,
            resetAtUTC: nil,
            lastUpdatedAtUTC: .now,
            detailText: nil
        )

        #expect(metric.kind.isCodexUsageLimit)
        #expect(metric.isAvailable == false)
    }

    @Test
    func codexUsageLimitWithAValueIsAvailable() {
        let metric = UsageMetric(
            kind: .codexWeekly,
            remainingFraction: 0,
            remainingValue: 0,
            totalValue: 100,
            unit: .percentage,
            resetAtUTC: nil,
            lastUpdatedAtUTC: .now,
            detailText: nil
        )

        #expect(metric.isAvailable)
    }

    @Test
    func codexCreditsAreNotAUsageLimit() {
        #expect(UsageMetricKind.codexCredits.isCodexUsageLimit == false)
    }

    @Test
    func successfulFetchHidesAnUnavailableCodexUsageLimit() {
        let snapshot = snapshot(fetchState: .ok)

        #expect(snapshot.shouldHideUnavailableCodexUsageLimit(.codexFiveHour))
    }

    @Test
    func failedFetchDoesNotHideAnUnavailableCodexUsageLimit() {
        let snapshot = snapshot(fetchState: .failed)

        #expect(snapshot.shouldHideUnavailableCodexUsageLimit(.codexFiveHour) == false)
    }

    private func snapshot(fetchState: ProviderFetchState) -> ProviderSnapshot {
        ProviderSnapshot(
            provider: .codex,
            authState: .authenticated,
            fetchState: fetchState,
            fetchedAtUTC: .now,
            metrics: [
                UsageMetric(
                    kind: .codexFiveHour,
                    remainingFraction: nil,
                    remainingValue: nil,
                    totalValue: nil,
                    unit: .percentage,
                    resetAtUTC: nil,
                    lastUpdatedAtUTC: .now,
                    detailText: nil
                ),
            ],
            errorDescription: fetchState == .failed ? "Unable to fetch" : nil,
            sourceDescription: nil
        )
    }
}
