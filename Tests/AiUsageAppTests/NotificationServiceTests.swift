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
}
