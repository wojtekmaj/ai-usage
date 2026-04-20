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
    private let logStore: LogStore
    private let usageStore: UsageStore

    init(
        usageStore: UsageStore,
        logStore: LogStore,
        notificationCenter: NotificationCenterClient? = .live()
    ) {
        self.usageStore = usageStore
        self.logStore = logStore
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
                let previousAheadState = alertStates[alertKey(metric.kind, .ahead)]
                if preferences.showAheadNotifications,
                   let result = evaluator.evaluate(metric: metric, direction: .ahead, previousState: previousAheadState, now: now) {
                    alertStates[alertKey(metric.kind, .ahead)] = result.state
                    logPaceEvaluationIfNeeded(metric: metric, direction: .ahead, previousState: previousAheadState, result: result)
                    if result.shouldNotify {
                        sendNotification(
                            identifier: "ahead-\(metric.kind.rawValue)-\(now.timeIntervalSince1970)",
                            title: title(for: metric.kind, direction: .ahead, localizer: localizer),
                            body: body(actualRemaining: result.actualRemaining, expectedRemaining: result.expectedRemaining, localizer: localizer)
                        )
                    }
                }

                let previousBehindState = alertStates[alertKey(metric.kind, .behind)]
                if preferences.showBehindNotifications,
                   let result = evaluator.evaluate(metric: metric, direction: .behind, previousState: previousBehindState, now: now) {
                    alertStates[alertKey(metric.kind, .behind)] = result.state
                    logPaceEvaluationIfNeeded(metric: metric, direction: .behind, previousState: previousBehindState, result: result)
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

    private func logPaceEvaluationIfNeeded(
        metric: UsageMetric,
        direction: UsageAlertDirection,
        previousState: UsageAlertState?,
        result: ScheduleEvaluator.Result
    ) {
        let previousArmed = previousState?.isArmed
        let resetChanged = previousState?.lastResetAtUTC != metric.resetAtUTC
        let armedChanged = previousArmed != result.state.isArmed

        guard result.shouldNotify || armedChanged || resetChanged else {
            return
        }

        logStore.append(
            level: result.shouldNotify ? .info : .debug,
            category: "notifications",
            message: [
                "pace-eval",
                "metric=\(metric.kind.rawValue)",
                "direction=\(direction.rawValue)",
                "actual=\(percentText(result.actualRemaining))",
                "expected=\(percentText(result.expectedRemaining))",
                "delta=\(signedPercentText(result.delta))",
                "previousArmed=\(boolText(previousArmed))",
                "currentArmed=\(boolText(result.state.isArmed))",
                "shouldNotify=\(boolText(result.shouldNotify))",
                "previousResetAt=\(dateText(previousState?.lastResetAtUTC))",
                "currentResetAt=\(dateText(metric.resetAtUTC))",
            ].joined(separator: " ")
        )
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

    private func percentText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func signedPercentText(_ value: Double) -> String {
        let percent = Int((value * 100).rounded())
        return percent >= 0 ? "+\(percent)%" : "\(percent)%"
    }

    private func boolText(_ value: Bool?) -> String {
        guard let value else {
            return "nil"
        }

        return value ? "true" : "false"
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else {
            return "nil"
        }

        return date.ISO8601Format()
    }
}
