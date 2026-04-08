import Foundation
import UserNotifications

struct NotificationCenterClient {
    let requestAuthorization: () -> Void
    let addRequest: (UNNotificationRequest) -> Void

    static func live(bundleURL: URL = Bundle.main.bundleURL) -> NotificationCenterClient? {
        guard bundleURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
            return nil
        }

        return NotificationCenterClient(
            requestAuthorization: {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
            },
            addRequest: { request in
                UNUserNotificationCenter.current().add(request)
            }
        )
    }
}

@MainActor
final class NotificationService {
    private let notificationCenter: NotificationCenterClient?
    private let evaluator = ScheduleEvaluator()
    private let usageStore: UsageStore

    init(
        usageStore: UsageStore,
        notificationCenter: NotificationCenterClient? = .live()
    ) {
        self.usageStore = usageStore
        self.notificationCenter = notificationCenter
    }

    var notificationsAreAvailable: Bool {
        notificationCenter != nil
    }

    func requestAuthorizationIfNeeded() {
        notificationCenter?.requestAuthorization()
    }

    func processRefresh(
        previousSnapshots: [ProviderID: ProviderSnapshot],
        newSnapshots: [ProviderID: ProviderSnapshot],
        preferences: DisplayPreferences,
        now: Date
    ) {
        var alertStates = usageStore.loadAlertStates()
        var resetMarkers = usageStore.loadCodexResetMarkers()

        for snapshot in newSnapshots.values {
            guard snapshot.fetchState == .ok else {
                continue
            }

            for metric in snapshot.metrics {
                if preferences.showAheadNotifications,
                   let result = evaluator.evaluate(metric: metric, direction: .ahead, previousState: alertStates[alertKey(metric.kind, .ahead)], now: now) {
                    alertStates[alertKey(metric.kind, .ahead)] = result.state
                    if result.shouldNotify {
                        sendNotification(
                            identifier: "ahead-\(metric.kind.rawValue)-\(now.timeIntervalSince1970)",
                            title: title(for: metric.kind, direction: .ahead),
                            body: body(for: metric.kind, direction: .ahead, actualRemaining: result.actualRemaining, expectedRemaining: result.expectedRemaining)
                        )
                    }
                }

                if preferences.showBehindNotifications,
                   let result = evaluator.evaluate(metric: metric, direction: .behind, previousState: alertStates[alertKey(metric.kind, .behind)], now: now) {
                    alertStates[alertKey(metric.kind, .behind)] = result.state
                    if result.shouldNotify {
                        sendNotification(
                            identifier: "behind-\(metric.kind.rawValue)-\(now.timeIntervalSince1970)",
                            title: title(for: metric.kind, direction: .behind),
                            body: body(for: metric.kind, direction: .behind, actualRemaining: result.actualRemaining, expectedRemaining: result.expectedRemaining)
                        )
                    }
                }
            }
        }

        if preferences.showCodexResetNotifications {
            for kind in [UsageMetricKind.codexFiveHour, .codexWeekly] {
                guard let previous = previousSnapshots[kind.provider]?.metric(kind),
                      let current = newSnapshots[kind.provider]?.metric(kind),
                      let previousReset = previous.resetAtUTC,
                      let currentReset = current.resetAtUTC else {
                    continue
                }

                let marker = "\(kind.rawValue)-\(currentReset.ISO8601Format())"
                let remainingJump = (current.remainingFraction ?? 0) - (previous.remainingFraction ?? 0)
                let resetMovedForward = currentReset.timeIntervalSince(previousReset) > 15 * 60
                let happenedEarly = now < previousReset.addingTimeInterval(-5 * 60)

                if happenedEarly && resetMovedForward && remainingJump > 0.25 && resetMarkers.contains(marker) == false {
                    resetMarkers.insert(marker)
                    sendNotification(
                        identifier: "codex-reset-\(marker)",
                        title: "Codex reset detected early",
                        body: "\(humanName(for: kind)) appears to have reset earlier than expected."
                    )
                }
            }
        }

        usageStore.saveAlertStates(alertStates)
        usageStore.saveCodexResetMarkers(resetMarkers)
    }

    private func sendNotification(identifier: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        notificationCenter?.addRequest(request)
    }

    private func alertKey(_ kind: UsageMetricKind, _ direction: UsageAlertDirection) -> String {
        "\(kind.rawValue)-\(direction.rawValue)"
    }

    private func title(for kind: UsageMetricKind, direction: UsageAlertDirection) -> String {
        let prefix = direction == .ahead ? "Ahead of schedule" : "Behind schedule"
        return "\(prefix): \(humanName(for: kind))"
    }

    private func body(for kind: UsageMetricKind, direction: UsageAlertDirection, actualRemaining: Double, expectedRemaining: Double) -> String {
        let actual = Int((actualRemaining * 100).rounded())
        let expected = Int((expectedRemaining * 100).rounded())

        switch direction {
        case .ahead:
            return "Remaining usage is \(actual)% while the schedule suggests about \(expected)% should remain."
        case .behind:
            return "Remaining usage is \(actual)% while the schedule suggests about \(expected)% should remain."
        }
    }

    private func humanName(for kind: UsageMetricKind) -> String {
        switch kind {
        case .codexFiveHour:
            return "Codex 5-hour window"
        case .codexWeekly:
            return "Codex weekly window"
        case .codexCredits:
            return "Codex credits"
        case .copilotMonthly:
            return "GitHub Copilot monthly quota"
        }
    }
}
