using System.Text.Json.Serialization;

namespace AiUsage.Windows.Domain;

internal sealed record AuthStateRequest(
    string Command,
    ProviderId Provider,
    bool CopilotTokenPresent);

internal sealed record RefreshRequest(
    string Command,
    ProviderId Provider,
    string? CopilotToken,
    DateTimeOffset Now);

internal sealed record DeviceCodeRequest(string Command);

internal sealed record PreheatCodexRequest(string Command);

internal sealed record PollTokenRequest(
    string Command,
    string DeviceCode,
    ulong DefaultInterval);

internal sealed record EvaluateScheduleRequest(
    string Command,
    UsageMetric Metric,
    UsageAlertDirection Direction,
    UsageAlertState? PreviousState,
    DateTimeOffset Now);

internal sealed record CoreResponse<T>(bool Ok, T? Data, CoreError? Error);

internal sealed record CoreError(string Code, string Message);

internal sealed record CopilotDeviceCode(
    string DeviceCode,
    string UserCode,
    string VerificationUri,
    ulong ExpiresIn,
    ulong Interval);

internal sealed record CopilotPollResult(string Status, ulong? RetryAfterSeconds, string? AccessToken);

internal sealed class PersistedUsage
{
    public Dictionary<ProviderId, ProviderSnapshot> Snapshots { get; set; } = [];

    public Dictionary<string, UsageAlertState> AlertStates { get; set; } = [];

    public HashSet<string> ResetMarkers { get; set; } = [];
}

[JsonSourceGenerationOptions(
    PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase,
    PropertyNameCaseInsensitive = true,
    WriteIndented = true,
    UseStringEnumConverter = true)]
[JsonSerializable(typeof(DisplayPreferences))]
[JsonSerializable(typeof(PersistedUsage))]
[JsonSerializable(typeof(List<AppLogEntry>))]
[JsonSerializable(typeof(Dictionary<string, string>))]
[JsonSerializable(typeof(AuthStateRequest))]
[JsonSerializable(typeof(RefreshRequest))]
[JsonSerializable(typeof(DeviceCodeRequest))]
[JsonSerializable(typeof(PreheatCodexRequest))]
[JsonSerializable(typeof(PollTokenRequest))]
[JsonSerializable(typeof(EvaluateScheduleRequest))]
[JsonSerializable(typeof(CoreResponse<ProviderAuthState>))]
[JsonSerializable(typeof(CoreResponse<ProviderSnapshot>))]
[JsonSerializable(typeof(CoreResponse<CopilotDeviceCode>))]
[JsonSerializable(typeof(CoreResponse<CopilotPollResult>))]
[JsonSerializable(typeof(CoreResponse<ScheduleEvaluationResult>))]
[JsonSerializable(typeof(CoreResponse<bool>))]
internal sealed partial class AppJsonContext : JsonSerializerContext
{
}
