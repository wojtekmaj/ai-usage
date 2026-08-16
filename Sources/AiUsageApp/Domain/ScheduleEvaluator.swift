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

struct UsagePaceEvaluator {
    func assess(
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
        case .codexFiveHour, .codexSparkFiveHour, .claudeFiveHour:
            let duration = 5 * 60 * 60.0
            return (resetAtUTC.addingTimeInterval(-duration), resetAtUTC, duration)
        case .codexWeekly, .codexSparkWeekly, .claudeWeekly:
            let duration = 7 * 24 * 60 * 60.0
            return (resetAtUTC.addingTimeInterval(-duration), resetAtUTC, duration)
        case .copilotMonthly:
            let calendar = Calendar(identifier: .gregorian)
            let start = calendar.date(byAdding: .month, value: -1, to: resetAtUTC) ?? now
            return (start, resetAtUTC, max(resetAtUTC.timeIntervalSince(start), 1))
        case .codexCredits, .codexLimitResets:
            return nil
        }
    }
}
