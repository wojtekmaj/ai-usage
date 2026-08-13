using AiUsage.Windows.Domain;
using System.Diagnostics;
using Microsoft.Windows.AppLifecycle;
using Microsoft.Windows.AppNotifications;
using Microsoft.Windows.AppNotifications.Builder;

namespace AiUsage.Windows.Services;

internal sealed class NotificationService : IDisposable
{
    private readonly CoreClient coreClient;
    private readonly UsageStore usageStore;
    private readonly LogStore logStore;
    private readonly CancellationTokenSource lifetime = new();
    private AppNotificationManager? appNotificationManager;

    public NotificationService(CoreClient coreClient, UsageStore usageStore, LogStore logStore)
    {
        this.coreClient = coreClient;
        this.usageStore = usageStore;
        this.logStore = logStore;
    }

    public bool IsAvailable { get; private set; }

    public event Action<string, string>? NotificationRequested;

    public void Start()
    {
        try
        {
            var manager = AppNotificationManager.Default;
            manager.NotificationInvoked += NotificationInvoked;
            manager.Register();
            appNotificationManager = manager;
        }
        catch (Exception error)
        {
            appNotificationManager = null;
            logStore.Append(AppLogLevel.Warning, "notifications", $"Actionable notifications are unavailable: {error.Message}");
        }

        if (appNotificationManager is not null)
        {
            var activation = AppInstance.GetCurrent().GetActivatedEventArgs();
            if (activation.Kind == ExtendedActivationKind.AppNotification
                && activation.Data is AppNotificationActivatedEventArgs notificationArgs)
            {
                NotificationInvoked(appNotificationManager, notificationArgs);
            }
        }
        IsAvailable = true;
    }

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

        if (preferences.ShowCodexResetNotifications || preferences.ShowCodexScheduledResetNotifications)
        {
            ProcessResets(
                previousSnapshots,
                newSnapshots,
                [UsageMetricKind.CodexFiveHour, UsageMetricKind.CodexWeekly],
                preferences.ShowCodexResetNotifications,
                preferences.ShowCodexScheduledResetNotifications,
                localizer.Text("notificationTitleCodexReset"),
                localizer.Text("notificationTitleCodexScheduledReset"),
                localizer.Text("notificationActionPreheat"),
                localizer,
                now);
        }
        if (preferences.ShowClaudeResetNotifications || preferences.ShowClaudeScheduledResetNotifications)
        {
            ProcessResets(
                previousSnapshots,
                newSnapshots,
                [UsageMetricKind.ClaudeFiveHour, UsageMetricKind.ClaudeWeekly],
                preferences.ShowClaudeResetNotifications,
                preferences.ShowClaudeScheduledResetNotifications,
                localizer.Text("notificationTitleClaudeReset"),
                localizer.Text("notificationTitleClaudeScheduledReset"),
                null,
                localizer,
                now);
        }
    }

    public void ShowUpdateAvailable(AppRelease release, Localizer localizer)
    {
        Show(
            localizer.Format("updateNotificationTitleFormat", release.Version),
            localizer.Text("updateNotificationBody"),
            localizer.Text("viewRelease"),
            new Dictionary<string, string>
            {
                ["action"] = "openUpdate",
                ["url"] = release.PageUri.AbsoluteUri,
            });
    }

    public void Dispose()
    {
        IsAvailable = false;
        lifetime.Cancel();
        if (appNotificationManager is not null)
        {
            appNotificationManager.NotificationInvoked -= NotificationInvoked;
            appNotificationManager.Unregister();
            appNotificationManager = null;
        }
        lifetime.Dispose();
    }

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

    private void ProcessResets(
        IReadOnlyDictionary<ProviderId, ProviderSnapshot> previousSnapshots,
        IReadOnlyDictionary<ProviderId, ProviderSnapshot> newSnapshots,
        IReadOnlyList<UsageMetricKind> metricKinds,
        bool earlyNotificationsEnabled,
        bool scheduledNotificationsEnabled,
        string earlyTitle,
        string scheduledTitle,
        string? actionTitle,
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
            var happenedOnSchedule = now <= previous.ResetAtUtc.Value + TimeSpan.FromMinutes(15);
            if (!resetMovedForward || remainingJump <= 0.25 || usageStore.ResetMarkers.Contains(marker))
            {
                continue;
            }
            if (provider == ProviderId.Codex && WasCodexResetCreditConsumed(previousSnapshots, newSnapshots))
            {
                continue;
            }

            (string Title, string BodyKey)? notification = (happenedEarly, earlyNotificationsEnabled, scheduledNotificationsEnabled, happenedOnSchedule) switch
            {
                (true, true, _, _) => (earlyTitle, "notificationBodyResetFormat"),
                (false, _, true, true) => (scheduledTitle, "notificationBodyScheduledResetFormat"),
                _ => null,
            };
            if (notification is null)
            {
                continue;
            }

            usageStore.AddResetMarker(marker);
            Show(
                notification.Value.Title,
                localizer.Format(notification.Value.BodyKey, NotificationMetricName(kind, localizer)),
                actionTitle);
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

    private async void NotificationInvoked(AppNotificationManager sender, AppNotificationActivatedEventArgs args)
    {
        var arguments = ParseArguments(args.Argument);
        if (arguments.GetValueOrDefault("action") == "openUpdate"
            && Uri.TryCreate(arguments.GetValueOrDefault("url"), UriKind.Absolute, out var releaseUri)
            && releaseUri.Scheme == Uri.UriSchemeHttps
            && string.Equals(releaseUri.Host, "github.com", StringComparison.OrdinalIgnoreCase))
        {
            Process.Start(new ProcessStartInfo(releaseUri.AbsoluteUri) { UseShellExecute = true });
            return;
        }
        if (arguments.GetValueOrDefault("action") != "preheatCodex")
        {
            return;
        }

        logStore.Append(AppLogLevel.Info, "codex", "Codex preheat requested.");
        try
        {
            await coreClient.PreheatCodexAsync(lifetime.Token);
            logStore.Append(AppLogLevel.Info, "codex", "Codex preheat completed.");
        }
        catch (OperationCanceledException) when (lifetime.IsCancellationRequested)
        {
        }
        catch (Exception error)
        {
            logStore.Append(AppLogLevel.Error, "codex", $"Codex preheat failed: {error.Message}");
        }
    }

    private void Show(
        string title,
        string body,
        string? actionTitle = null,
        IReadOnlyDictionary<string, string>? arguments = null)
    {
        if (appNotificationManager is null)
        {
            NotificationRequested?.Invoke(title, body);
            return;
        }

        var builder = new AppNotificationBuilder()
            .AddText(title)
            .AddText(body);
        if (arguments is not null)
        {
            foreach (var argument in arguments)
            {
                builder.AddArgument(argument.Key, argument.Value);
            }
        }
        if (actionTitle is not null)
        {
            var button = new AppNotificationButton(actionTitle);
            if (arguments is null)
            {
                button.AddArgument("action", "preheatCodex");
            }
            else
            {
                foreach (var argument in arguments)
                {
                    button.AddArgument(argument.Key, argument.Value);
                }
            }
            builder.AddButton(button);
        }
        appNotificationManager.Show(builder.BuildNotification());
    }

    private static Dictionary<string, string> ParseArguments(string arguments)
    {
        var result = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var item in arguments.Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            var parts = item.Split('=', 2);
            if (parts.Length == 2)
            {
                result[Uri.UnescapeDataString(parts[0])] = Uri.UnescapeDataString(parts[1]);
            }
        }
        return result;
    }
}
