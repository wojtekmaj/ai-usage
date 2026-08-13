using System.Text.Json.Serialization;
using System.Text.Json.Serialization.Metadata;

namespace AiUsage.Windows.Domain;

internal enum ProviderId
{
    [JsonStringEnumMemberName("codex")]
    Codex,
    [JsonStringEnumMemberName("claude")]
    Claude,
    [JsonStringEnumMemberName("copilot")]
    Copilot,
}

internal enum UsageMetricKind
{
    [JsonStringEnumMemberName("codexFiveHour")]
    CodexFiveHour,
    [JsonStringEnumMemberName("codexWeekly")]
    CodexWeekly,
    [JsonStringEnumMemberName("codexSparkFiveHour")]
    CodexSparkFiveHour,
    [JsonStringEnumMemberName("codexSparkWeekly")]
    CodexSparkWeekly,
    [JsonStringEnumMemberName("codexCredits")]
    CodexCredits,
    [JsonStringEnumMemberName("codexLimitResets")]
    CodexLimitResets,
    [JsonStringEnumMemberName("claudeFiveHour")]
    ClaudeFiveHour,
    [JsonStringEnumMemberName("claudeWeekly")]
    ClaudeWeekly,
    [JsonStringEnumMemberName("copilotMonthly")]
    CopilotMonthly,
}

internal enum MetricUnit
{
    [JsonStringEnumMemberName("percentage")]
    Percentage,
    [JsonStringEnumMemberName("requests")]
    Requests,
    [JsonStringEnumMemberName("credits")]
    Credits,
}

internal enum ProviderAuthState
{
    [JsonStringEnumMemberName("signedOut")]
    SignedOut,
    [JsonStringEnumMemberName("configured")]
    Configured,
    [JsonStringEnumMemberName("authenticated")]
    Authenticated,
}

internal enum ProviderFetchState
{
    [JsonStringEnumMemberName("ok")]
    Ok,
    [JsonStringEnumMemberName("missingAuth")]
    MissingAuth,
    [JsonStringEnumMemberName("failed")]
    Failed,
}

internal enum UsageAlertDirection
{
    [JsonStringEnumMemberName("ahead")]
    Ahead,
    [JsonStringEnumMemberName("behind")]
    Behind,
}

internal enum AppLanguage
{
    [JsonStringEnumMemberName("englishUS")]
    EnglishUS,
    [JsonStringEnumMemberName("polish")]
    Polish,
    [JsonStringEnumMemberName("spanish")]
    Spanish,
    [JsonStringEnumMemberName("german")]
    German,
    [JsonStringEnumMemberName("french")]
    French,
    [JsonStringEnumMemberName("japanese")]
    Japanese,
    [JsonStringEnumMemberName("portugueseBrazil")]
    PortugueseBrazil,
}

internal enum OptionalMetricVisibility
{
    [JsonStringEnumMemberName("always")]
    Always,
    [JsonStringEnumMemberName("onlyWhenAboveZero")]
    OnlyWhenAboveZero,
    [JsonStringEnumMemberName("never")]
    Never,
}

internal enum MenuBarMetric
{
    [JsonStringEnumMemberName("weekly")]
    Weekly,
    [JsonStringEnumMemberName("fiveHour")]
    FiveHour,
}

internal enum UsagePanelBackgroundStyle
{
    [JsonStringEnumMemberName("regularMaterial")]
    RegularMaterial,
    [JsonStringEnumMemberName("solidAdaptive")]
    SolidAdaptive,
}

internal enum UsageBarColorStyle
{
    [JsonStringEnumMemberName("defaultColors")]
    DefaultColors,
    [JsonStringEnumMemberName("systemAccent")]
    SystemAccent,
}

internal sealed record UsageMetric(
    UsageMetricKind Kind,
    double? RemainingFraction,
    double? RemainingValue,
    double? TotalValue,
    MetricUnit Unit,
    DateTimeOffset? ResetAtUtc,
    DateTimeOffset LastUpdatedAtUtc,
    string? DetailText);

internal sealed record ProviderSnapshot(
    ProviderId Provider,
    ProviderAuthState AuthState,
    ProviderFetchState FetchState,
    DateTimeOffset? FetchedAtUtc,
    IReadOnlyList<UsageMetric> Metrics,
    string? ErrorDescription,
    string? SourceDescription)
{
    public UsageMetric? Metric(UsageMetricKind kind) => Metrics.FirstOrDefault(metric => metric.Kind == kind);
}

internal sealed record UsageAlertState(
    UsageAlertDirection Direction,
    UsageMetricKind MetricKind,
    DateTimeOffset LastTriggeredAtUtc,
    double LastExtremeDelta,
    bool IsArmed);

internal sealed record ScheduleEvaluationResult(
    UsageAlertDirection Direction,
    UsageAlertState State,
    bool ShouldNotify,
    double Delta,
    double ExpectedRemaining,
    double ActualRemaining);

internal sealed class DisplayPreferences
{
    public HashSet<ProviderId> VisibleProviders { get; set; } = Enum.GetValues<ProviderId>().ToHashSet();

    public HashSet<ProviderId> VisiblePanelProviders { get; set; } = Enum.GetValues<ProviderId>().ToHashSet();

    public bool ShowAheadNotifications { get; set; } = true;

    public bool ShowBehindNotifications { get; set; } = true;

    public bool ShowCodexResetNotifications { get; set; } = true;

    public bool ShowClaudeResetNotifications { get; set; } = true;

    public bool ShowCodexScheduledResetNotifications { get; set; }

    public bool ShowClaudeScheduledResetNotifications { get; set; }

    public bool AutomaticallyCheckForUpdates { get; set; } = true;

    public bool ShowCodexSparkUsage { get; set; }

    public OptionalMetricVisibility CodexCreditsVisibility { get; set; } = OptionalMetricVisibility.Always;

    public OptionalMetricVisibility CodexLimitResetsVisibility { get; set; } = OptionalMetricVisibility.Always;

    public int RefreshIntervalMinutes { get; set; } = 5;

    public AppLanguage Language { get; set; } = AppLanguage.EnglishUS;

    public MenuBarMetric CodexMenuBarMetric { get; set; } = MenuBarMetric.Weekly;

    public MenuBarMetric ClaudeMenuBarMetric { get; set; } = MenuBarMetric.Weekly;

    public UsagePanelBackgroundStyle UsagePanelBackgroundStyle { get; set; } = UsagePanelBackgroundStyle.RegularMaterial;

    public UsageBarColorStyle UsageBarColorStyle { get; set; } = UsageBarColorStyle.DefaultColors;
}

internal enum AppLogLevel
{
    [JsonStringEnumMemberName("debug")]
    Debug,
    [JsonStringEnumMemberName("info")]
    Info,
    [JsonStringEnumMemberName("warning")]
    Warning,
    [JsonStringEnumMemberName("error")]
    Error,
}

internal sealed record AppLogEntry(
    Guid Id,
    DateTimeOffset TimestampUtc,
    AppLogLevel Level,
    string Category,
    string Message);

internal static class JsonDefaults
{
    public static JsonTypeInfo<T> TypeInfo<T>() =>
        (JsonTypeInfo<T>)(AppJsonContext.Default.GetTypeInfo(typeof(T))
            ?? throw new InvalidOperationException($"No generated JSON metadata exists for {typeof(T)}."));
}
