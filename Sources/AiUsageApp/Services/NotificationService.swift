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
        let localizer = Localizer(language: preferences.language)
        var alertStates = usageStore.loadAlertStates()
        var resetMarkers = usageStore.loadResetMarkers()

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
                            title: title(for: metric.kind, direction: .ahead, localizer: localizer),
                            body: body(actualRemaining: result.actualRemaining, expectedRemaining: result.expectedRemaining, localizer: localizer)
                        )
                    }
                }

                if preferences.showBehindNotifications,
                   let result = evaluator.evaluate(metric: metric, direction: .behind, previousState: alertStates[alertKey(metric.kind, .behind)], now: now) {
                    alertStates[alertKey(metric.kind, .behind)] = result.state
                    if result.shouldNotify {
                        sendNotification(
                            identifier: "behind-\(metric.kind.rawValue)-\(now.timeIntervalSince1970)",
                            title: title(for: metric.kind, direction: .behind, localizer: localizer),
                            body: body(actualRemaining: result.actualRemaining, expectedRemaining: result.expectedRemaining, localizer: localizer)
                        )
                    }
                }
            }
        }

        if preferences.showCodexResetNotifications {
            processEarlyResetNotifications(
                previousSnapshots: previousSnapshots,
                newSnapshots: newSnapshots,
                metricKinds: [UsageMetricKind.codexFiveHour, .codexWeekly],
                identifierPrefix: "codex-reset",
                title: localizer.text(.notificationTitleCodexReset),
                resetMarkers: &resetMarkers,
                localizer: localizer,
                now: now
            )
        }

        if preferences.showClaudeResetNotifications {
            processEarlyResetNotifications(
                previousSnapshots: previousSnapshots,
                newSnapshots: newSnapshots,
                metricKinds: [.claudeFiveHour, .claudeWeekly],
                identifierPrefix: "claude-reset",
                title: localizer.text(.notificationTitleClaudeReset),
                resetMarkers: &resetMarkers,
                localizer: localizer,
                now: now
            )
        }

        usageStore.saveAlertStates(alertStates)
        usageStore.saveResetMarkers(resetMarkers)
    }

    private func sendNotification(identifier: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        notificationCenter?.addRequest(request)
    }

    private func processEarlyResetNotifications(
        previousSnapshots: [ProviderID: ProviderSnapshot],
        newSnapshots: [ProviderID: ProviderSnapshot],
        metricKinds: [UsageMetricKind],
        identifierPrefix: String,
        title: String,
        resetMarkers: inout Set<String>,
        localizer: Localizer,
        now: Date
    ) {
        for kind in metricKinds {
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
                    identifier: "\(identifierPrefix)-\(marker)",
                    title: title,
                    body: localizer.formatted(.notificationBodyResetFormat, humanName(for: kind, localizer: localizer))
                )
            }
        }
    }

    private func alertKey(_ kind: UsageMetricKind, _ direction: UsageAlertDirection) -> String {
        "\(kind.rawValue)-\(direction.rawValue)"
    }

    private func title(for kind: UsageMetricKind, direction: UsageAlertDirection, localizer: Localizer) -> String {
        let key: L10nKey = direction == .ahead ? .notificationTitleAheadFormat : .notificationTitleBehindFormat
        return localizer.formatted(key, humanName(for: kind, localizer: localizer))
    }

    private func body(actualRemaining: Double, expectedRemaining: Double, localizer: Localizer) -> String {
        let actual = Int((actualRemaining * 100).rounded())
        let expected = Int((expectedRemaining * 100).rounded())
        return localizer.formatted(.notificationBodyScheduleFormat, actual, expected)
    }

    private func humanName(for kind: UsageMetricKind, localizer: Localizer) -> String {
        localizer.notificationMetricName(for: kind)
    }
}
