import Foundation
import Testing
@testable import AiUsageApp

@MainActor
struct AppEnvironmentScreenshotModeTests {
    @Test
    func screenshotModeSeedsMockDataForEveryProvider() async throws {
        let defaultsSuite = "AppEnvironmentScreenshotModeTests"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        defaults.removePersistentDomain(forName: defaultsSuite)
        defer {
            defaults.removePersistentDomain(forName: defaultsSuite)
        }

        let now = Date(timeIntervalSince1970: 1_789_473_600)
        let environment = AppEnvironment(
            settings: SettingsStore(defaults: defaults),
            keychain: KeychainStore(service: defaultsSuite),
            usageStore: UsageStore(defaults: defaults),
            logStore: LogStore(defaults: defaults),
            env: ["AI_USAGE_SCREENSHOT_MODE": "1"],
            nowProvider: { now }
        )

        #expect(environment.lastRefreshAtUTC == now.addingTimeInterval(-8))
        #expect(environment.currentAuthState(for: .claude) == .authenticated)
        #expect(environment.currentAuthState(for: .codex) == .authenticated)
        #expect(environment.currentAuthState(for: .copilot) == .authenticated)

        let claudeSnapshot = try #require(environment.snapshot(for: .claude))
        #expect(claudeSnapshot.fetchState == .ok)
        #expect(claudeSnapshot.metric(.claudeFiveHour)?.remainingFraction == 0.23)
        #expect(claudeSnapshot.metric(.claudeWeekly)?.remainingFraction == 0.62)

        let codexSnapshot = try #require(environment.snapshot(for: .codex))
        #expect(codexSnapshot.fetchState == .ok)
        #expect(codexSnapshot.metric(.codexFiveHour)?.remainingFraction == 0.36)
        #expect(codexSnapshot.metric(.codexWeekly)?.remainingFraction == 0.76)
        #expect(codexSnapshot.metric(.codexCredits)?.remainingValue == 336)
        #expect(codexSnapshot.metric(.codexLimitResets)?.remainingValue == 2)
        #expect(codexSnapshot.metric(.codexSparkFiveHour)?.remainingFraction == 0.92)
        #expect(codexSnapshot.metric(.codexSparkWeekly)?.remainingFraction == 0.88)

        let copilotSnapshot = try #require(environment.snapshot(for: .copilot))
        #expect(copilotSnapshot.fetchState == .ok)
        #expect(copilotSnapshot.metric(.copilotMonthly)?.remainingFraction == 0.78)
        #expect(copilotSnapshot.metric(.copilotMonthly)?.remainingValue == 3_900)
        #expect(copilotSnapshot.metric(.copilotMonthly)?.unit == .credits)

        for snapshot in environment.snapshots.values {
            for resetDate in snapshot.metrics.compactMap(\.resetAtUTC) {
                #expect(resetDate > now)
            }
        }

        let snapshots = environment.snapshots
        await environment.refreshNow()
        #expect(environment.snapshots == snapshots)
    }
}
