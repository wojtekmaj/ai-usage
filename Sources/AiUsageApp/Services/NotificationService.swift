import Foundation
import UserNotifications

struct NotificationCenterClient {
    let requestAuthorization: () -> Void
    let addRequest: (UNNotificationRequest) -> Void
    let setNotificationCategories: (Set<UNNotificationCategory>) -> Void

    init(
        requestAuthorization: @escaping () -> Void,
        addRequest: @escaping (UNNotificationRequest) -> Void,
        setNotificationCategories: @escaping (Set<UNNotificationCategory>) -> Void = { _ in }
    ) {
        self.requestAuthorization = requestAuthorization
        self.addRequest = addRequest
        self.setNotificationCategories = setNotificationCategories
    }

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
            },
            setNotificationCategories: { categories in
                UNUserNotificationCenter.current().setNotificationCategories(categories)
            }
        )
    }
}

@MainActor
final class NotificationService {
    static let codexResetCategoryIdentifier = "codex-reset"
    static let codexPreheatActionIdentifier = "preheat-codex"

    private let notificationCenter: NotificationCenterClient?
    private let logStore: LogStore
    private let usageStore: UsageStore
    private let scheduleEvaluationClient: ScheduleEvaluationClient
    private let sharedCore = SharedCoreClient()

    init(
        usageStore: UsageStore,
        logStore: LogStore,
        notificationCenter: NotificationCenterClient? = .live(),
        scheduleEvaluationClient: ScheduleEvaluationClient = .live
    ) {
        self.usageStore = usageStore
        self.logStore = logStore
        self.notificationCenter = notificationCenter
        self.scheduleEvaluationClient = scheduleEvaluationClient
        AppDelegate.codexPreheatHandler = { [weak self] in
            self?.preheatCodex()
        }
    }

    var notificationsAreAvailable: Bool {
        notificationCenter != nil
    }

    func requestAuthorizationIfNeeded() {
        notificationCenter?.requestAuthorization()
    }

    func showUpdateAvailable(release: AppRelease, localizer: Localizer) {
        let content = UNMutableNotificationContent()
        content.title = localizer.formatted(.updateNotificationTitleFormat, release.version)
        content.body = localizer.text(.updateNotificationBody)
        content.sound = .default
        content.userInfo = [AppDelegate.updateURLUserInfoKey: release.pageURL.absoluteString]
        notificationCenter?.addRequest(
            UNNotificationRequest(identifier: "update-\(release.version)", content: content, trigger: nil)
        )
    }

    func processRefresh(
        previousSnapshots: [ProviderID: ProviderSnapshot],
        newSnapshots: [ProviderID: ProviderSnapshot],
        preferences: DisplayPreferences,
        now: Date
    ) async {
        let localizer = Localizer(language: preferences.language)
        registerCodexResetCategory(localizer: localizer)
        var alertStates = usageStore.loadAlertStates()
        var resetMarkers = usageStore.loadResetMarkers()
        var evaluationKeys: [String] = []
        var evaluations: [ScheduleEvaluationRequest] = []

        for snapshot in newSnapshots.values {
            guard snapshot.fetchState == .ok else {
                continue
            }

            for metric in snapshot.metrics {
                if preferences.showAheadNotifications {
                    appendEvaluation(
                        metric: metric,
                        direction: .ahead,
                        alertStates: alertStates,
                        keys: &evaluationKeys,
                        evaluations: &evaluations
                    )
                }

                if preferences.showBehindNotifications {
                    appendEvaluation(
                        metric: metric,
                        direction: .behind,
                        alertStates: alertStates,
                        keys: &evaluationKeys,
                        evaluations: &evaluations
                    )
                }
            }
        }

        do {
            let results = try await scheduleEvaluationClient.evaluateSchedules(evaluations, now: now)
            for (index, result) in results.enumerated() {
                guard let result else {
                    continue
                }
                let evaluation = evaluations[index]
                let key = evaluationKeys[index]
                let previousState = alertStates[key]
                alertStates[key] = result.state
                logPaceEvaluationIfNeeded(
                    metric: evaluation.metric,
                    direction: evaluation.direction,
                    previousState: previousState,
                    result: result
                )
                if result.shouldNotify {
                    sendNotification(
                        identifier: "\(evaluation.direction.rawValue)-\(evaluation.metric.kind.rawValue)-\(now.timeIntervalSince1970)",
                        title: title(for: evaluation.metric.kind, direction: evaluation.direction, localizer: localizer),
                        body: body(actualRemaining: result.actualRemaining, expectedRemaining: result.expectedRemaining, localizer: localizer)
                    )
                }
            }
        } catch {
            logStore.append(
                level: .error,
                category: "notifications",
                message: "Shared-core schedule evaluation failed: \(error.localizedDescription)"
            )
        }

        if preferences.showCodexResetNotifications || preferences.showCodexScheduledResetNotifications {
            processResetNotifications(
                previousSnapshots: previousSnapshots,
                newSnapshots: newSnapshots,
                metricKinds: [UsageMetricKind.codexFiveHour, .codexWeekly],
                identifierPrefix: "codex-reset",
                earlyNotificationsEnabled: preferences.showCodexResetNotifications,
                scheduledNotificationsEnabled: preferences.showCodexScheduledResetNotifications,
                earlyTitle: localizer.text(.notificationTitleCodexReset),
                scheduledTitle: localizer.text(.notificationTitleCodexScheduledReset),
                categoryIdentifier: Self.codexResetCategoryIdentifier,
                resetMarkers: &resetMarkers,
                localizer: localizer,
                now: now
            )
        }

        if preferences.showClaudeResetNotifications || preferences.showClaudeScheduledResetNotifications {
            processResetNotifications(
                previousSnapshots: previousSnapshots,
                newSnapshots: newSnapshots,
                metricKinds: [.claudeFiveHour, .claudeWeekly],
                identifierPrefix: "claude-reset",
                earlyNotificationsEnabled: preferences.showClaudeResetNotifications,
                scheduledNotificationsEnabled: preferences.showClaudeScheduledResetNotifications,
                earlyTitle: localizer.text(.notificationTitleClaudeReset),
                scheduledTitle: localizer.text(.notificationTitleClaudeScheduledReset),
                categoryIdentifier: nil,
                resetMarkers: &resetMarkers,
                localizer: localizer,
                now: now
            )
        }

        usageStore.saveAlertStates(alertStates)
        usageStore.saveResetMarkers(resetMarkers)
    }

    private func sendNotification(
        identifier: String,
        title: String,
        body: String,
        categoryIdentifier: String? = nil
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let categoryIdentifier {
            content.categoryIdentifier = categoryIdentifier
        }

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        notificationCenter?.addRequest(request)
    }

    private func registerCodexResetCategory(localizer: Localizer) {
        let action = UNNotificationAction(
            identifier: Self.codexPreheatActionIdentifier,
            title: localizer.text(.notificationActionPreheat)
        )
        let category = UNNotificationCategory(
            identifier: Self.codexResetCategoryIdentifier,
            actions: [action],
            intentIdentifiers: []
        )
        notificationCenter?.setNotificationCategories([category])
    }

    private func preheatCodex() {
        logStore.append(category: "codex", message: "Codex preheat requested.")
        Task { [weak self] in
            guard let self else {
                return
            }
            do {
                try await sharedCore.preheatCodex()
                logStore.append(category: "codex", message: "Codex preheat completed.")
            } catch {
                logStore.append(level: .error, category: "codex", message: "Codex preheat failed: \(error.localizedDescription)")
            }
        }
    }

    private func logPaceEvaluationIfNeeded(
        metric: UsageMetric,
        direction: UsageAlertDirection,
        previousState: UsageAlertState?,
        result: ScheduleEvaluationResult
    ) {
        let previousArmed = previousState?.isArmed
        let armedChanged = previousArmed != result.state.isArmed

        guard result.shouldNotify || armedChanged else {
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
            ].joined(separator: " ")
        )
    }

    private func appendEvaluation(
        metric: UsageMetric,
        direction: UsageAlertDirection,
        alertStates: [String: UsageAlertState],
        keys: inout [String],
        evaluations: inout [ScheduleEvaluationRequest]
    ) {
        let key = alertKey(metric.kind, direction)
        keys.append(key)
        evaluations.append(
            ScheduleEvaluationRequest(
                metric: metric,
                direction: direction,
                previousState: alertStates[key]
            )
        )
    }

    private func processResetNotifications(
        previousSnapshots: [ProviderID: ProviderSnapshot],
        newSnapshots: [ProviderID: ProviderSnapshot],
        metricKinds: [UsageMetricKind],
        identifierPrefix: String,
        earlyNotificationsEnabled: Bool,
        scheduledNotificationsEnabled: Bool,
        earlyTitle: String,
        scheduledTitle: String,
        categoryIdentifier: String?,
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
            let happenedOnSchedule = now <= previousReset.addingTimeInterval(15 * 60)

            guard resetMovedForward,
               remainingJump > 0.25,
               resetMarkers.contains(marker) == false,
               wasCodexLimitResetConsumed(for: kind, previousSnapshots: previousSnapshots, newSnapshots: newSnapshots) == false else {
                continue
            }

            let timing: String
            let title: String
            let bodyKey: L10nKey
            if happenedEarly, earlyNotificationsEnabled {
                timing = "early"
                title = earlyTitle
                bodyKey = .notificationBodyResetFormat
            } else if happenedEarly == false, happenedOnSchedule, scheduledNotificationsEnabled {
                timing = "scheduled"
                title = scheduledTitle
                bodyKey = .notificationBodyScheduledResetFormat
            } else {
                continue
            }

            resetMarkers.insert(marker)
            sendNotification(
                identifier: "\(identifierPrefix)-\(timing)-\(marker)",
                title: title,
                body: localizer.formatted(bodyKey, humanName(for: kind, localizer: localizer)),
                categoryIdentifier: categoryIdentifier
            )
        }
    }

    private func wasCodexLimitResetConsumed(
        for kind: UsageMetricKind,
        previousSnapshots: [ProviderID: ProviderSnapshot],
        newSnapshots: [ProviderID: ProviderSnapshot]
    ) -> Bool {
        guard kind.provider == .codex else {
            return false
        }

        guard let previous = previousSnapshots[.codex]?.metric(.codexLimitResets)?.remainingValue,
              let current = newSnapshots[.codex]?.metric(.codexLimitResets)?.remainingValue else {
            return false
        }

        return current < previous
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
}
