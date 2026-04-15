import Foundation
import Testing
import UserNotifications
@testable import AiUsageApp

struct NotificationServiceTests {
    @Test
    func liveNotificationCenterClientRequiresAppBundleURL() {
        let buildDirectoryClient = NotificationCenterClient.live(
            bundleURL: URL(filePath: "/tmp/ai-usage/.build/arm64-apple-macosx/debug")
        )
        #expect(buildDirectoryClient == nil)

        let appBundleClient = NotificationCenterClient.live(
            bundleURL: URL(filePath: "/tmp/AI Usage.app")
        )
        #expect(appBundleClient != nil)
    }

    @Test
    @MainActor
    func requestAuthorizationUsesInjectedClient() {
        let defaultsSuiteName = "NotificationServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defer {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }

        var didRequestAuthorization = false
        let service = NotificationService(
            usageStore: UsageStore(defaults: defaults),
            notificationCenter: NotificationCenterClient(
                requestAuthorization: { didRequestAuthorization = true },
                addRequest: { _ in }
            )
        )

        service.requestAuthorizationIfNeeded()

        #expect(didRequestAuthorization)
    }

    @Test
    @MainActor
    func processRefreshSendsNotificationThroughInjectedClient() {
        let defaultsSuiteName = "NotificationServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defer {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }

        let now = Date(timeIntervalSince1970: 1_776_056_400) // 2026-04-15 12:00:00 UTC
        let resetAt = Date(timeIntervalSince1970: 1_777_420_800) // 2026-05-01 00:00:00 UTC
        var deliveredRequests: [UNNotificationRequest] = []

        let service = NotificationService(
            usageStore: UsageStore(defaults: defaults),
            notificationCenter: NotificationCenterClient(
                requestAuthorization: {},
                addRequest: { request in
                    deliveredRequests.append(request)
                }
            )
        )

        service.processRefresh(
            previousSnapshots: [
                .copilot: Self.makeSnapshot(remainingFraction: 0.8, now: now, resetAt: resetAt),
            ],
            newSnapshots: [
                .copilot: Self.makeSnapshot(remainingFraction: 0.3, now: now, resetAt: resetAt),
            ],
            preferences: .default,
            now: now
        )

        #expect(deliveredRequests.count == 1)
        #expect(deliveredRequests.first?.content.title == "Ahead of schedule: GitHub Copilot monthly quota")
        #expect(deliveredRequests.first?.content.body == "Remaining usage is 30% while the schedule suggests about 51% should remain.")
    }

    @Test
    @MainActor
    func processRefreshSendsClaudeEarlyResetNotification() {
        let defaultsSuiteName = "NotificationServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defer {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }

        let now = Date(timeIntervalSince1970: 1_776_055_200) // 2026-04-15 11:40:00 UTC
        let previousResetAt = Date(timeIntervalSince1970: 1_776_056_400) // 2026-04-15 12:00:00 UTC
        let currentResetAt = Date(timeIntervalSince1970: 1_776_072_600) // 2026-04-15 16:30:00 UTC
        var deliveredRequests: [UNNotificationRequest] = []
        let preferences = DisplayPreferences(
            visibleProviders: Set(ProviderID.allCases),
            visiblePanelProviders: Set(ProviderID.allCases),
            showAheadNotifications: false,
            showBehindNotifications: false,
            showCodexResetNotifications: false,
            showClaudeResetNotifications: true,
            refreshIntervalMinutes: 5,
            language: .englishUS,
            codexMenuBarMetric: .weekly,
            claudeMenuBarMetric: .weekly,
            usagePanelBackgroundStyle: .regularMaterial
        )

        let service = NotificationService(
            usageStore: UsageStore(defaults: defaults),
            notificationCenter: NotificationCenterClient(
                requestAuthorization: {},
                addRequest: { request in
                    deliveredRequests.append(request)
                }
            )
        )

        service.processRefresh(
            previousSnapshots: [
                .claude: Self.makeClaudeSnapshot(remainingFraction: 0.2, now: now, resetAt: previousResetAt),
            ],
            newSnapshots: [
                .claude: Self.makeClaudeSnapshot(remainingFraction: 0.8, now: now, resetAt: currentResetAt),
            ],
            preferences: preferences,
            now: now
        )

        #expect(deliveredRequests.count == 1)
        #expect(deliveredRequests.first?.content.title == "Claude Code reset detected early")
        #expect(deliveredRequests.first?.content.body == "Claude Code 5-hour window appears to have reset earlier than expected.")
        #expect(UsageStore(defaults: defaults).loadResetMarkers().count == 1)
    }

    @Test
    @MainActor
    func processRefreshUsesSelectedLanguageForNotificationCopy() {
        let defaultsSuiteName = "NotificationServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defer {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }

        let now = Date(timeIntervalSince1970: 1_776_056_400) // 2026-04-15 12:00:00 UTC
        let resetAt = Date(timeIntervalSince1970: 1_777_420_800) // 2026-05-01 00:00:00 UTC
        var deliveredRequests: [UNNotificationRequest] = []
        let preferences = DisplayPreferences(
            visibleProviders: Set(ProviderID.allCases),
            visiblePanelProviders: Set(ProviderID.allCases),
            showAheadNotifications: true,
            showBehindNotifications: true,
            showCodexResetNotifications: true,
            showClaudeResetNotifications: true,
            refreshIntervalMinutes: 5,
            language: .polish,
            codexMenuBarMetric: .weekly,
            claudeMenuBarMetric: .weekly,
            usagePanelBackgroundStyle: .regularMaterial
        )

        let service = NotificationService(
            usageStore: UsageStore(defaults: defaults),
            notificationCenter: NotificationCenterClient(
                requestAuthorization: {},
                addRequest: { request in
                    deliveredRequests.append(request)
                }
            )
        )

        service.processRefresh(
            previousSnapshots: [
                .copilot: Self.makeSnapshot(remainingFraction: 0.8, now: now, resetAt: resetAt),
            ],
            newSnapshots: [
                .copilot: Self.makeSnapshot(remainingFraction: 0.3, now: now, resetAt: resetAt),
            ],
            preferences: preferences,
            now: now
        )

        #expect(deliveredRequests.count == 1)
        #expect(deliveredRequests.first?.content.title == "Zużycie powyżej tempa: Miesięczny limit GitHub Copilot")
        #expect(deliveredRequests.first?.content.body == "Pozostałe użycie to 30%, a harmonogram sugeruje około 51%.")
    }

    private static func makeSnapshot(remainingFraction: Double, now: Date, resetAt: Date) -> ProviderSnapshot {
        ProviderSnapshot(
            provider: .copilot,
            authState: .authenticated,
            fetchState: .ok,
            fetchedAtUTC: now,
            metrics: [
                UsageMetric(
                    kind: .copilotMonthly,
                    remainingFraction: remainingFraction,
                    remainingValue: remainingFraction * 1_000,
                    totalValue: 1_000,
                    unit: .requests,
                    resetAtUTC: resetAt,
                    lastUpdatedAtUTC: now,
                    detailText: nil
                ),
            ],
            errorDescription: nil,
            sourceDescription: nil
        )
    }

    private static func makeClaudeSnapshot(remainingFraction: Double, now: Date, resetAt: Date) -> ProviderSnapshot {
        ProviderSnapshot(
            provider: .claude,
            authState: .authenticated,
            fetchState: .ok,
            fetchedAtUTC: now,
            metrics: [
                UsageMetric(
                    kind: .claudeFiveHour,
                    remainingFraction: remainingFraction,
                    remainingValue: remainingFraction,
                    totalValue: 1,
                    unit: .percentage,
                    resetAtUTC: resetAt,
                    lastUpdatedAtUTC: now,
                    detailText: nil
                ),
                UsageMetric(
                    kind: .claudeWeekly,
                    remainingFraction: 0.5,
                    remainingValue: 0.5,
                    totalValue: 1,
                    unit: .percentage,
                    resetAtUTC: resetAt.addingTimeInterval(7 * 24 * 60 * 60),
                    lastUpdatedAtUTC: now,
                    detailText: nil
                ),
            ],
            errorDescription: nil,
            sourceDescription: nil
        )
    }
}
