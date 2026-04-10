import AppKit
import SwiftUI

struct UsagePanelView: View {
    @ObservedObject var environment: AppEnvironment
    private let scheduleEvaluator = ScheduleEvaluator()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(referenceDate: context.date)
        }
    }

    private func content(referenceDate: Date) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            metricsSection(referenceDate: referenceDate)
            Divider()
            footer(referenceDate: referenceDate)
        }
        .padding(16)
        .frame(width: 420)
        .background(.regularMaterial)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(environment.localizer.text(.usagePanelTitle))
                .font(.headline)

            if shouldShowAuthenticationCallout {
                Text(environment.localizer.text(.authenticateInSettings))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func metricsSection(referenceDate: Date) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            providerSection(provider: .claude, metrics: [.claudeFiveHour, .claudeWeekly], referenceDate: referenceDate)
            providerSection(provider: .codex, metrics: [.codexFiveHour, .codexWeekly, .codexCredits], referenceDate: referenceDate)
            providerSection(provider: .copilot, metrics: [.copilotMonthly], referenceDate: referenceDate)
        }
    }

    private func footer(referenceDate: Date) -> some View {
        HStack {
            Button(environment.localizer.text(.openSettings)) {
                environment.showSettings()
            }

            Spacer()

            Text(lastUpdateText(referenceDate: referenceDate))
                .font(.caption.weight(environment.isStale(referenceDate: referenceDate) ? .semibold : .regular))
                .foregroundStyle(environment.isStale(referenceDate: referenceDate) ? .red : .primary)
                .lineLimit(1)
                .layoutPriority(1)

            Button(environment.localizer.text(.refreshNow)) {
                Task {
                    await environment.refreshNow()
                }
            }
            .disabled(environment.isRefreshing)
        }
    }

    private func providerSection(provider: ProviderID, metrics: [UsageMetricKind], referenceDate: Date) -> some View {
        let snapshot = environment.snapshot(for: provider)

        return VStack(alignment: .leading, spacing: 12) {
            ProviderHeaderView(
                provider: provider,
                title: provider.displayName(localizer: environment.localizer),
                subtitle: nil,
                externalLinkURL: provider.usageSettingsURL
            )

            providerIssue(provider: provider, snapshot: snapshot)

            if shouldShowMetrics(for: snapshot) {
                ForEach(metrics, id: \.self) { kind in
                    metricCard(kind: kind, referenceDate: referenceDate)
                }
            }
        }
    }

    private func metricCard(kind: UsageMetricKind, referenceDate: Date) -> some View {
        let snapshot = environment.snapshot(for: kind.provider)
        let metric = snapshot?.metric(kind)
        let paceAssessment = metric.flatMap { scheduleEvaluator.paceAssessment(metric: $0, now: referenceDate) }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title(for: kind))
                    .font(.subheadline.weight(.medium))

                Spacer()

                Text(valueText(for: kind, metric: metric))
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .monospacedDigit()
            }

            if kind != .codexCredits {
                VStack(alignment: .leading, spacing: 4) {
                    RemainingProgressBar(fraction: metric?.remainingFraction)

                    if let paceAssessment {
                        TimeRemainingProgressBar(
                            fraction: paceAssessment.expectedRemaining,
                            isEmphasized: paceAssessment.state != .onTrack
                        )
                    }
                }
            }

            if let resetText = resetText(for: metric, referenceDate: referenceDate) {
                Text(resetText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private func title(for kind: UsageMetricKind) -> String {
        switch kind {
        case .codexFiveHour:
            return environment.localizer.text(.codexFiveHour)
        case .codexWeekly:
            return environment.localizer.text(.codexWeekly)
        case .codexCredits:
            return environment.localizer.text(.codexCredits)
        case .claudeFiveHour:
            return environment.localizer.text(.claudeFiveHour)
        case .claudeWeekly:
            return environment.localizer.text(.claudeWeekly)
        case .copilotMonthly:
            return environment.localizer.text(.copilotMonthly)
        }
    }

    private func valueText(for kind: UsageMetricKind, metric: UsageMetric?) -> String {
        guard let metric else {
            return missingValueText(for: kind)
        }

        switch metric.unit {
        case .percentage, .requests:
            if let fraction = metric.remainingFraction {
                return "\(Int((fraction * 100).rounded()))%"
            }

            if let value = metric.remainingValue {
                return numberFormatter.string(from: NSNumber(value: value)) ?? environment.localizer.text(.unavailable)
            }

            return missingValueText(for: kind)
        case .credits:
            if let value = metric.remainingValue {
                return numberFormatter.string(from: NSNumber(value: value)) ?? environment.localizer.text(.unavailable)
            }

            return "-"
        }
    }

    private func resetText(for metric: UsageMetric?, referenceDate: Date) -> String? {
        guard let metric else {
            return environment.localizer.text(.authenticationRequired)
        }

        guard let resetAtUTC = metric.resetAtUTC else {
            return nil
        }

        return "\(environment.localizer.text(.resetAt)): \(resetDateFormatter.string(from: resetAtUTC, now: referenceDate))"
    }

    private func lastUpdateText(referenceDate: Date) -> String {
        guard let lastRefreshAtUTC = environment.lastRefreshAtUTC else {
            return "\(environment.localizer.text(.lastUpdate)): \(environment.localizer.text(.notConfigured))"
        }

        return "\(environment.localizer.text(.lastUpdate)): \(relativeFormatter.localizedString(for: lastRefreshAtUTC, relativeTo: referenceDate))"
    }

    private var shouldShowAuthenticationCallout: Bool {
        ProviderID.allCases
            .filter { environment.settings.preferences.visibleProviders.contains($0) }
            .allSatisfy { environment.currentAuthState(for: $0) == .signedOut }
    }

    @ViewBuilder
    private func providerIssue(provider: ProviderID, snapshot: ProviderSnapshot?) -> some View {
        if let snapshot {
            switch snapshot.fetchState {
            case .ok:
                EmptyView()
            case .missingAuth:
                Text("\(provider.displayName(localizer: environment.localizer)): \(environment.localizer.text(.authenticationRequired))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .failed:
                Text(snapshot.errorDescription ?? environment.localizer.text(.fetchFailed))
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private func missingValueText(for kind: UsageMetricKind) -> String {
        switch kind {
        case .codexCredits:
            return "-"
        case .codexFiveHour, .codexWeekly, .claudeFiveHour, .claudeWeekly, .copilotMonthly:
            return "-%"
        }
    }

    private func shouldShowMetrics(for snapshot: ProviderSnapshot?) -> Bool {
        snapshot?.fetchState != .missingAuth
    }

    private var resetDateFormatter: ResetDateTextFormatter {
        ResetDateTextFormatter(
            locale: environment.settings.preferences.language.locale,
            timeZone: .autoupdatingCurrent
        )
    }

    private var relativeFormatter: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = environment.settings.preferences.language.locale
        formatter.unitsStyle = .full
        return formatter
    }

    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = environment.settings.preferences.language.locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }
}
