using AiUsage.Windows.Domain;

namespace AiUsage.Windows.Services;

internal sealed class NotificationService : IDisposable
{
    private readonly CoreClient coreClient;
    private readonly UsageStore usageStore;

    public NotificationService(CoreClient coreClient, UsageStore usageStore)
    {
        this.coreClient = coreClient;
        this.usageStore = usageStore;
    }

    public bool IsAvailable { get; private set; }

    public event Action<string, string>? NotificationRequested;

    public void Start() => IsAvailable = true;

    public async Task ProcessRefreshAsync(
        IReadOnlyDictionary<ProviderId, ProviderSnapshot> previousSnapshots,
        IReadOnlyDictionary<ProviderId, ProviderSnapshot> newSnapshots,
        DisplayPreferences preferences,
        Localizer localizer,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        if (!IsAvailable)
        {
            return;
        }

        foreach (var snapshot in newSnapshots.Values.Where(snapshot => snapshot.FetchState == ProviderFetchState.Ok))
        {
            foreach (var metric in snapshot.Metrics)
            {
                if (preferences.ShowAheadNotifications)
                {
                    await ProcessPaceAsync(metric, UsageAlertDirection.Ahead, localizer, now, cancellationToken);
                }
                if (preferences.ShowBehindNotifications)
                {
                    await ProcessPaceAsync(metric, UsageAlertDirection.Behind, localizer, now, cancellationToken);
                }
            }
        }

        if (preferences.ShowCodexResetNotifications)
        {
            ProcessEarlyResets(
                previousSnapshots,
                newSnapshots,
                [UsageMetricKind.CodexFiveHour, UsageMetricKind.CodexWeekly],
                localizer.Text("notificationTitleCodexReset"),
                localizer,
                now);
        }
        if (preferences.ShowClaudeResetNotifications)
        {
            ProcessEarlyResets(
                previousSnapshots,
                newSnapshots,
                [UsageMetricKind.ClaudeFiveHour, UsageMetricKind.ClaudeWeekly],
                localizer.Text("notificationTitleClaudeReset"),
                localizer,
                now);
        }
    }

    public void Dispose() => IsAvailable = false;

    private async Task ProcessPaceAsync(
        UsageMetric metric,
        UsageAlertDirection direction,
        Localizer localizer,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        var key = $"{metric.Kind}-{direction}";
        var previous = usageStore.AlertStates.GetValueOrDefault(key);
        var result = await coreClient.EvaluateScheduleAsync(metric, direction, previous, now, cancellationToken);
        if (result is null)
        {
            return;
        }
        usageStore.SaveAlertState(key, result.State);
        if (!result.ShouldNotify)
        {
            return;
        }

        var metricName = NotificationMetricName(metric.Kind, localizer);
        var titleKey = direction == UsageAlertDirection.Ahead
            ? "notificationTitleAheadFormat"
            : "notificationTitleBehindFormat";
        Show(
            localizer.Format(titleKey, metricName),
            localizer.Format(
                "notificationBodyScheduleFormat",
                Math.Round(result.ActualRemaining * 100),
                Math.Round(result.ExpectedRemaining * 100)));
    }

    private void ProcessEarlyResets(
        IReadOnlyDictionary<ProviderId, ProviderSnapshot> previousSnapshots,
        IReadOnlyDictionary<ProviderId, ProviderSnapshot> newSnapshots,
        IReadOnlyList<UsageMetricKind> metricKinds,
        string title,
        Localizer localizer,
        DateTimeOffset now)
    {
        foreach (var kind in metricKinds)
        {
            var provider = ProviderFor(kind);
            var previous = previousSnapshots.GetValueOrDefault(provider)?.Metric(kind);
            var current = newSnapshots.GetValueOrDefault(provider)?.Metric(kind);
            if (previous?.ResetAtUtc is null || current?.ResetAtUtc is null)
            {
                continue;
            }

            var marker = $"{kind}-{current.ResetAtUtc.Value:O}";
            var remainingJump = (current.RemainingFraction ?? 0) - (previous.RemainingFraction ?? 0);
            var resetMovedForward = current.ResetAtUtc.Value - previous.ResetAtUtc.Value > TimeSpan.FromMinutes(15);
            var happenedEarly = now < previous.ResetAtUtc.Value - TimeSpan.FromMinutes(5);
            if (!happenedEarly || !resetMovedForward || remainingJump <= 0.25 || usageStore.ResetMarkers.Contains(marker))
            {
                continue;
            }
            if (provider == ProviderId.Codex && WasCodexResetCreditConsumed(previousSnapshots, newSnapshots))
            {
                continue;
            }

            usageStore.AddResetMarker(marker);
            Show(title, localizer.Format("notificationBodyResetFormat", NotificationMetricName(kind, localizer)));
        }
    }

    private static bool WasCodexResetCreditConsumed(
        IReadOnlyDictionary<ProviderId, ProviderSnapshot> previousSnapshots,
        IReadOnlyDictionary<ProviderId, ProviderSnapshot> newSnapshots)
    {
        var previous = previousSnapshots.GetValueOrDefault(ProviderId.Codex)?.Metric(UsageMetricKind.CodexLimitResets)?.RemainingValue;
        var current = newSnapshots.GetValueOrDefault(ProviderId.Codex)?.Metric(UsageMetricKind.CodexLimitResets)?.RemainingValue;
        return previous is not null && current is not null && current < previous;
    }

    private static ProviderId ProviderFor(UsageMetricKind kind) => kind switch
    {
        UsageMetricKind.ClaudeFiveHour or UsageMetricKind.ClaudeWeekly => ProviderId.Claude,
        UsageMetricKind.CopilotMonthly => ProviderId.Copilot,
        _ => ProviderId.Codex,
    };

    private static string NotificationMetricName(UsageMetricKind kind, Localizer localizer)
    {
        var provider = localizer.ProviderName(ProviderFor(kind));
        return kind switch
        {
            UsageMetricKind.CodexFiveHour or UsageMetricKind.ClaudeFiveHour => localizer.Format("notificationMetricFiveHourFormat", provider),
            UsageMetricKind.CodexWeekly or UsageMetricKind.ClaudeWeekly => localizer.Format("notificationMetricWeeklyFormat", provider),
            UsageMetricKind.CopilotMonthly => localizer.Format("notificationMetricMonthlyFormat", provider),
            UsageMetricKind.CodexCredits => localizer.Format("notificationMetricCreditsFormat", provider),
            _ => localizer.MetricTitle(kind),
        };
    }

    private void Show(string title, string body) => NotificationRequested?.Invoke(title, body);
}
