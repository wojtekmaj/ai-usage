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
        let logStore = LogStore(defaults: defaults)
        let service = NotificationService(
            usageStore: UsageStore(defaults: defaults),
            logStore: logStore,
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
    func updateNotificationIncludesExactReleasePage() throws {
        let defaultsSuiteName = "NotificationServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defer {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }

        var deliveredRequests: [UNNotificationRequest] = []
        let service = NotificationService(
            usageStore: UsageStore(defaults: defaults),
            logStore: LogStore(defaults: defaults),
            notificationCenter: NotificationCenterClient(
                requestAuthorization: {},
                addRequest: { deliveredRequests.append($0) }
            )
        )
        let pageURL = try #require(URL(string: "https://github.com/wojtekmaj/ai-usage/releases/tag/v0.6.0"))

        service.showUpdateAvailable(
            release: AppRelease(version: "0.6.0", pageURL: pageURL),
            localizer: Localizer(language: .englishUS)
        )

        #expect(deliveredRequests.count == 1)
        #expect(deliveredRequests[0].identifier == "update-0.6.0")
        #expect(deliveredRequests[0].content.title == "AI Usage 0.6.0 is available")
        #expect(deliveredRequests[0].content.userInfo[AppDelegate.updateURLUserInfoKey] as? String == pageURL.absoluteString)
    }

    @Test
    @MainActor
    func processRefreshSendsNotificationThroughInjectedClient() async {
        let defaultsSuiteName = "NotificationServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defer {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }

        let now = Date(timeIntervalSince1970: 1_776_056_400) // 2026-04-15 12:00:00 UTC
        let resetAt = Date(timeIntervalSince1970: 1_777_420_800) // 2026-05-01 00:00:00 UTC
        var deliveredRequests: [UNNotificationRequest] = []
        let logStore = LogStore(defaults: defaults)

        let service = NotificationService(
            usageStore: UsageStore(defaults: defaults),
            logStore: logStore,
            notificationCenter: NotificationCenterClient(
                requestAuthorization: {},
                addRequest: { request in
                    deliveredRequests.append(request)
                }
            )
        )

        await service.processRefresh(
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
        #expect(logStore.entries.contains { entry in
            entry.category == "notifications"
                && entry.message.contains("pace-eval")
                && entry.message.contains("metric=copilotMonthly")
                && entry.message.contains("direction=ahead")
                && entry.message.contains("actual=30%")
                && entry.message.contains("expected=51%")
                && entry.message.contains("shouldNotify=true")
        })
    }

    @Test
    @MainActor
    func processRefreshSendsClaudeEarlyResetNotification() async {
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
            showCodexSparkUsage: false,
            codexCreditsVisibility: .always,
            codexLimitResetsVisibility: .always,
            refreshIntervalMinutes: 5,
            language: .englishUS,
            codexMenuBarMetric: .weekly,
            claudeMenuBarMetric: .weekly,
            usagePanelBackgroundStyle: .regularMaterial
        )

        let service = NotificationService(
            usageStore: UsageStore(defaults: defaults),
            logStore: LogStore(defaults: defaults),
            notificationCenter: NotificationCenterClient(
                requestAuthorization: {},
                addRequest: { request in
                    deliveredRequests.append(request)
                }
            )
        )

        await service.processRefresh(
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
        #expect(deliveredRequests.first?.content.categoryIdentifier.isEmpty == true)
        #expect(UsageStore(defaults: defaults).loadResetMarkers().count == 1)
    }

    @Test
    @MainActor
    func processRefreshUsesSelectedLanguageForNotificationCopy() async {
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
            showCodexSparkUsage: false,
            codexCreditsVisibility: .always,
            codexLimitResetsVisibility: .always,
            refreshIntervalMinutes: 5,
            language: .polish,
            codexMenuBarMetric: .weekly,
            claudeMenuBarMetric: .weekly,
            usagePanelBackgroundStyle: .regularMaterial
        )

        let service = NotificationService(
            usageStore: UsageStore(defaults: defaults),
            logStore: LogStore(defaults: defaults),
            notificationCenter: NotificationCenterClient(
                requestAuthorization: {},
                addRequest: { request in
                    deliveredRequests.append(request)
                }
            )
        )

        await service.processRefresh(
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

    @Test
    @MainActor
    func processRefreshSkipsCodexEarlyResetNotificationWhenLimitResetWasConsumed() async {
        let defaultsSuiteName = "NotificationServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defer {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }

        let now = Date(timeIntervalSince1970: 1_776_055_200) // 2026-04-15 11:40:00 UTC
        let previousResetAt = Date(timeIntervalSince1970: 1_776_056_400) // 2026-04-15 12:00:00 UTC
        let currentResetAt = Date(timeIntervalSince1970: 1_776_073_200) // 2026-04-15 16:40:00 UTC
        var deliveredRequests: [UNNotificationRequest] = []

        let service = NotificationService(
            usageStore: UsageStore(defaults: defaults),
            logStore: LogStore(defaults: defaults),
            notificationCenter: NotificationCenterClient(
                requestAuthorization: {},
                addRequest: { request in
                    deliveredRequests.append(request)
                }
            )
        )

        await service.processRefresh(
            previousSnapshots: [
                .codex: Self.makeCodexSnapshot(remainingFraction: 0.1, limitResets: 2, now: now, resetAt: previousResetAt),
            ],
            newSnapshots: [
                .codex: Self.makeCodexSnapshot(remainingFraction: 1, limitResets: 1, now: now, resetAt: currentResetAt),
            ],
            preferences: Self.resetOnlyPreferences,
            now: now
        )

        #expect(deliveredRequests.isEmpty)
        #expect(UsageStore(defaults: defaults).loadResetMarkers().isEmpty)
    }

    @Test
    @MainActor
    func processRefreshSendsCodexEarlyResetNotificationWhenLimitResetCountDoesNotDecrease() async {
        let defaultsSuiteName = "NotificationServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defer {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }

        let now = Date(timeIntervalSince1970: 1_776_055_200) // 2026-04-15 11:40:00 UTC
        let previousResetAt = Date(timeIntervalSince1970: 1_776_056_400) // 2026-04-15 12:00:00 UTC
        let currentResetAt = Date(timeIntervalSince1970: 1_776_073_200) // 2026-04-15 16:40:00 UTC
        var deliveredRequests: [UNNotificationRequest] = []

        let service = NotificationService(
            usageStore: UsageStore(defaults: defaults),
            logStore: LogStore(defaults: defaults),
            notificationCenter: NotificationCenterClient(
                requestAuthorization: {},
                addRequest: { request in
                    deliveredRequests.append(request)
                }
            )
        )

        await service.processRefresh(
            previousSnapshots: [
                .codex: Self.makeCodexSnapshot(remainingFraction: 0.1, limitResets: 1, now: now, resetAt: previousResetAt),
            ],
            newSnapshots: [
                .codex: Self.makeCodexSnapshot(remainingFraction: 1, limitResets: 1, now: now, resetAt: currentResetAt),
            ],
            preferences: Self.resetOnlyPreferences,
            now: now
        )

        #expect(deliveredRequests.count == 1)
        #expect(deliveredRequests.first?.content.title == "Codex reset detected early")
        #expect(deliveredRequests.first?.content.body == "Codex 5-hour window appears to have reset earlier than expected.")
        #expect(deliveredRequests.first?.content.categoryIdentifier == NotificationService.codexResetCategoryIdentifier)
    }

    @Test
    @MainActor
    func processRefreshSendsCodexScheduledResetNotification() async {
        let defaultsSuiteName = "NotificationServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defer {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }

        let now = Date(timeIntervalSince1970: 1_776_056_400) // 2026-04-15 12:00:00 UTC
        let currentResetAt = now.addingTimeInterval(5 * 60 * 60)
        var deliveredRequests: [UNNotificationRequest] = []
        var registeredCategories: Set<UNNotificationCategory> = []
        var preferences = Self.resetOnlyPreferences
        preferences.showCodexResetNotifications = false
        preferences.showClaudeResetNotifications = false
        preferences.showCodexScheduledResetNotifications = true

        let service = NotificationService(
            usageStore: UsageStore(defaults: defaults),
            logStore: LogStore(defaults: defaults),
            notificationCenter: NotificationCenterClient(
                requestAuthorization: {},
                addRequest: { request in
                    deliveredRequests.append(request)
                },
                setNotificationCategories: { categories in
                    registeredCategories = categories
                }
            )
        )

        await service.processRefresh(
            previousSnapshots: [
                .codex: Self.makeCodexSnapshot(remainingFraction: 0.1, limitResets: 1, now: now, resetAt: now),
            ],
            newSnapshots: [
                .codex: Self.makeCodexSnapshot(remainingFraction: 1, limitResets: 1, now: now, resetAt: currentResetAt),
            ],
            preferences: preferences,
            now: now
        )

        #expect(deliveredRequests.count == 1)
        #expect(deliveredRequests.first?.content.title == "Codex reset on schedule")
        #expect(deliveredRequests.first?.content.body == "Codex 5-hour window appears to have reset on schedule.")
        #expect(deliveredRequests.first?.content.categoryIdentifier == NotificationService.codexResetCategoryIdentifier)
        let preheatAction = registeredCategories.first?.actions.first
        #expect(preheatAction?.identifier == NotificationService.codexPreheatActionIdentifier)
        #expect(preheatAction?.title == "Preheat")
    }

    @Test
    @MainActor
    func scheduledResetNotificationsIgnoreEarlyResets() async {
        let defaultsSuiteName = "NotificationServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defer {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }

        let now = Date(timeIntervalSince1970: 1_776_055_200) // 2026-04-15 11:40:00 UTC
        let previousResetAt = now.addingTimeInterval(20 * 60)
        let currentResetAt = now.addingTimeInterval(5 * 60 * 60)
        var deliveredRequests: [UNNotificationRequest] = []
        var preferences = Self.resetOnlyPreferences
        preferences.showCodexResetNotifications = false
        preferences.showClaudeResetNotifications = false
        preferences.showCodexScheduledResetNotifications = true

        let service = NotificationService(
            usageStore: UsageStore(defaults: defaults),
            logStore: LogStore(defaults: defaults),
            notificationCenter: NotificationCenterClient(
                requestAuthorization: {},
                addRequest: { request in
                    deliveredRequests.append(request)
                }
            )
        )

        await service.processRefresh(
            previousSnapshots: [
                .codex: Self.makeCodexSnapshot(remainingFraction: 0.1, limitResets: 1, now: now, resetAt: previousResetAt),
            ],
            newSnapshots: [
                .codex: Self.makeCodexSnapshot(remainingFraction: 1, limitResets: 1, now: now, resetAt: currentResetAt),
            ],
            preferences: preferences,
            now: now
        )

        #expect(deliveredRequests.isEmpty)
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

    private static func makeCodexSnapshot(remainingFraction: Double, limitResets: Double, now: Date, resetAt: Date) -> ProviderSnapshot {
        ProviderSnapshot(
            provider: .codex,
            authState: .authenticated,
            fetchState: .ok,
            fetchedAtUTC: now,
            metrics: [
                UsageMetric(
                    kind: .codexFiveHour,
                    remainingFraction: remainingFraction,
                    remainingValue: remainingFraction * 100,
                    totalValue: 100,
                    unit: .percentage,
                    resetAtUTC: resetAt,
                    lastUpdatedAtUTC: now,
                    detailText: nil
                ),
                UsageMetric(
                    kind: .codexWeekly,
                    remainingFraction: 0.5,
                    remainingValue: 50,
                    totalValue: 100,
                    unit: .percentage,
                    resetAtUTC: resetAt.addingTimeInterval(7 * 24 * 60 * 60),
                    lastUpdatedAtUTC: now,
                    detailText: nil
                ),
                UsageMetric(
                    kind: .codexLimitResets,
                    remainingFraction: nil,
                    remainingValue: limitResets,
                    totalValue: nil,
                    unit: .credits,
                    resetAtUTC: nil,
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

    private static var resetOnlyPreferences: DisplayPreferences {
        DisplayPreferences(
            visibleProviders: Set(ProviderID.allCases),
            visiblePanelProviders: Set(ProviderID.allCases),
            showAheadNotifications: false,
            showBehindNotifications: false,
            showCodexResetNotifications: true,
            showClaudeResetNotifications: true,
            showCodexSparkUsage: false,
            codexCreditsVisibility: .always,
            codexLimitResetsVisibility: .always,
            refreshIntervalMinutes: 5,
            language: .englishUS,
            codexMenuBarMetric: .weekly,
            claudeMenuBarMetric: .weekly,
            usagePanelBackgroundStyle: .regularMaterial
        )
    }
}
