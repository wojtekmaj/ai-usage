import Foundation
import Testing
@testable import AiUsageApp

struct MenuBarSummaryEvaluatorTests {
    @Test
    func copilotCanShowRemainingValue() {
        var preferences = DisplayPreferences.default
        preferences.copilotMenuBarValue = .remainingValue

        let value = MenuBarSummaryEvaluator.value(
            for: .copilot,
            snapshot: copilotSnapshot,
            preferences: preferences
        )

        #expect(value == .count(275_000))
    }

    @Test
    func copilotShowsPercentageByDefault() {
        let value = MenuBarSummaryEvaluator.value(
            for: .copilot,
            snapshot: copilotSnapshot,
            preferences: .default
        )

        #expect(value == .percentage(0.55))
    }

    private var copilotSnapshot: ProviderSnapshot {
        ProviderSnapshot(
            provider: .copilot,
            authState: .authenticated,
            fetchState: .ok,
            fetchedAtUTC: .now,
            metrics: [
                UsageMetric(
                    kind: .copilotMonthly,
                    remainingFraction: 0.55,
                    remainingValue: 275_000,
                    totalValue: 500_000,
                    unit: .credits,
                    resetAtUTC: nil,
                    lastUpdatedAtUTC: .now,
                    detailText: nil
                ),
            ],
            errorDescription: nil,
            sourceDescription: nil
        )
    }
}
