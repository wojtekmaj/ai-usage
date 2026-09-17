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

    @Test
    func showsClaudeUsageOnlyAfterASuccessfulFetch() {
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        var snapshot = ProviderSnapshot(
            provider: .claude,
            authState: .authenticated,
            fetchState: .ok,
            fetchedAtUTC: fetchedAt,
            metrics: [UsageMetric(kind: .claudeWeekly, remainingFraction: 0.75, remainingValue: nil, totalValue: nil, unit: .percentage, resetAtUTC: nil, lastUpdatedAtUTC: fetchedAt, detailText: nil)],
            errorDescription: nil,
            sourceDescription: nil
        )

        #expect(snapshot.shouldShowUsageMetrics)

        snapshot.authState = .signedOut
        snapshot.fetchState = .failed
        #expect(snapshot.shouldShowUsageMetrics == false)

        snapshot.fetchState = .missingAuth
        #expect(snapshot.shouldShowUsageMetrics == false)

        snapshot.authState = .configured
        snapshot.fetchState = .failed
        #expect(snapshot.shouldShowUsageMetrics == false)

        snapshot.authState = .authenticated
        snapshot.fetchState = .ok
        #expect(snapshot.shouldShowUsageMetrics)
    }

    @Test
    func distinguishesClaudeNetworkErrorsFromSignInFailures() {
        let failed = ProviderSnapshot(
            provider: .claude,
            authState: .configured,
            fetchState: .failed,
            fetchedAtUTC: .now,
            metrics: [],
            errorDescription: "Offline",
            sourceDescription: nil
        )

        #expect(failed.requiresClaudeSignIn == false)
        #expect(failed.shouldShowUsageMetrics == false)
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
