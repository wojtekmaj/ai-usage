import Foundation

enum UsagePaceState: Hashable, Sendable {
    case ahead
    case onTrack
    case behind
}

struct UsagePaceAssessment: Hashable, Sendable {
    let state: UsagePaceState
    let expectedRemaining: Double
    let actualRemaining: Double
    let delta: Double
}

struct ScheduleEvaluator {
    struct Thresholds {
        let trigger: Double
        let rearmMargin: Double

        static let standard = Thresholds(trigger: 0.18, rearmMargin: 0.10)
    }

    struct Result {
        let direction: UsageAlertDirection
        let state: UsageAlertState
        let shouldNotify: Bool
        let delta: Double
        let expectedRemaining: Double
        let actualRemaining: Double
    }

    func evaluate(
        metric: UsageMetric,
        direction: UsageAlertDirection,
        previousState: UsageAlertState?,
        now: Date,
        thresholds: Thresholds = .standard
    ) -> Result? {
        guard let paceAssessment = paceAssessment(metric: metric, now: now, trigger: thresholds.trigger) else {
            return nil
        }

        let actualRemaining = paceAssessment.actualRemaining
        let expectedRemaining = paceAssessment.expectedRemaining
        let delta = paceAssessment.delta

        let severity: Double
        switch direction {
        case .ahead:
            severity = -delta
            guard metric.kind.supportsAheadNotifications else {
                return nil
            }
        case .behind:
            severity = delta
            guard metric.kind.supportsBehindNotifications else {
                return nil
            }
        }

        guard severity > 0 else {
            let state = UsageAlertState(
                direction: direction,
                metricKind: metric.kind,
                lastTriggeredAtUTC: previousState?.lastTriggeredAtUTC ?? now,
                lastExtremeDelta: 0,
                lastResetAtUTC: metric.resetAtUTC,
                isArmed: true
            )
            return Result(direction: direction, state: state, shouldNotify: false, delta: delta, expectedRemaining: expectedRemaining, actualRemaining: actualRemaining)
        }

        let shouldReset = previousState?.lastResetAtUTC != metric.resetAtUTC || previousState?.direction != direction || previousState?.metricKind != metric.kind
        let baselineState = previousState ?? UsageAlertState(
            direction: direction,
            metricKind: metric.kind,
            lastTriggeredAtUTC: now,
            lastExtremeDelta: 0,
            lastResetAtUTC: metric.resetAtUTC,
            isArmed: true
        )

        let state = shouldReset
            ? UsageAlertState(
                direction: direction,
                metricKind: metric.kind,
                lastTriggeredAtUTC: now,
                lastExtremeDelta: 0,
                lastResetAtUTC: metric.resetAtUTC,
                isArmed: true
            )
            : baselineState

        var updatedState = state
        let rearmThreshold = max(0, thresholds.trigger - thresholds.rearmMargin)

        if severity <= rearmThreshold {
            updatedState.isArmed = true
            updatedState.lastExtremeDelta = severity
            updatedState.lastResetAtUTC = metric.resetAtUTC
            return Result(direction: direction, state: updatedState, shouldNotify: false, delta: delta, expectedRemaining: expectedRemaining, actualRemaining: actualRemaining)
        }

        if severity >= thresholds.trigger && updatedState.isArmed {
            updatedState.isArmed = false
            updatedState.lastTriggeredAtUTC = now
            updatedState.lastExtremeDelta = severity
            updatedState.lastResetAtUTC = metric.resetAtUTC
            return Result(direction: direction, state: updatedState, shouldNotify: true, delta: delta, expectedRemaining: expectedRemaining, actualRemaining: actualRemaining)
        }

        updatedState.lastExtremeDelta = max(updatedState.lastExtremeDelta, severity)
        updatedState.lastResetAtUTC = metric.resetAtUTC
        return Result(direction: direction, state: updatedState, shouldNotify: false, delta: delta, expectedRemaining: expectedRemaining, actualRemaining: actualRemaining)
    }

    func paceAssessment(
        metric: UsageMetric,
        now: Date,
        trigger: Double = 0.09
    ) -> UsagePaceAssessment? {
        guard let actualRemaining = metric.remainingFraction,
              let period = metric.periodRange(containing: now) else {
            return nil
        }

        let elapsed = max(0, min(1, now.timeIntervalSince(period.start) / period.duration))
        let expectedRemaining = 1 - elapsed
        let delta = actualRemaining - expectedRemaining

        let state: UsagePaceState
        if delta <= -trigger {
            state = .ahead
        } else if delta >= trigger {
            state = .behind
        } else {
            state = .onTrack
        }

        return UsagePaceAssessment(
            state: state,
            expectedRemaining: expectedRemaining,
            actualRemaining: actualRemaining,
            delta: delta
        )
    }
}

private extension UsageMetric {
    func periodRange(containing now: Date) -> (start: Date, end: Date, duration: TimeInterval)? {
        guard let resetAtUTC else {
            return nil
        }

        switch kind {
        case .codexFiveHour, .claudeFiveHour:
            let start = resetAtUTC.addingTimeInterval(-(5 * 60 * 60))
            return (start, resetAtUTC, 5 * 60 * 60)
        case .codexWeekly, .claudeWeeklyQuota:
            let duration = 7 * 24 * 60 * 60.0
            let start = resetAtUTC.addingTimeInterval(-duration)
            return (start, resetAtUTC, duration)
        case .copilotMonthly:
            let calendar = Calendar(identifier: .gregorian)
            let start = calendar.date(byAdding: .month, value: -1, to: resetAtUTC) ?? now
            return (start, resetAtUTC, max(resetAtUTC.timeIntervalSince(start), 1))
        case .codexCredits, .claudeDailyCost, .claudeWeeklyCost, .claudeSonnet:
            return nil
        }
    }
}
