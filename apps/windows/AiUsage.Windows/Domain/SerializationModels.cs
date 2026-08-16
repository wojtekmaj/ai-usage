using System.Text.Json.Serialization;
using AiUsage.Windows.Services;

namespace AiUsage.Windows.Domain;

internal sealed record RefreshRequest(
    int ProtocolVersion,
    string Command,
    string? CopilotToken,
    string? ClaudeCredentialsJson,
    DateTimeOffset Now);

internal sealed record DeviceCodeRequest(int ProtocolVersion, string Command);

internal sealed record PreheatCodexRequest(int ProtocolVersion, string Command);

internal sealed record PollTokenRequest(
    int ProtocolVersion,
    string Command,
    string DeviceCode,
    ulong DefaultInterval);

internal sealed record ScheduleEvaluationInput(
    UsageMetric Metric,
    UsageAlertDirection Direction,
    UsageAlertState? PreviousState);

internal sealed record EvaluateSchedulesRequest(
    int ProtocolVersion,
    string Command,
    IReadOnlyList<ScheduleEvaluationInput> Evaluations,
    DateTimeOffset Now);

internal sealed record CoreResponse<T>(int ProtocolVersion, bool Ok, T? Data, CoreError? Error);

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
[JsonSerializable(typeof(UpdateCheckMetadata))]
[JsonSerializable(typeof(RefreshRequest))]
[JsonSerializable(typeof(DeviceCodeRequest))]
[JsonSerializable(typeof(PreheatCodexRequest))]
[JsonSerializable(typeof(PollTokenRequest))]
[JsonSerializable(typeof(EvaluateSchedulesRequest))]
[JsonSerializable(typeof(CoreResponse<List<ProviderSnapshot>>))]
[JsonSerializable(typeof(CoreResponse<CopilotDeviceCode>))]
[JsonSerializable(typeof(CoreResponse<CopilotPollResult>))]
[JsonSerializable(typeof(CoreResponse<List<ScheduleEvaluationResult>>))]
[JsonSerializable(typeof(CoreResponse<bool>))]
internal sealed partial class AppJsonContext : JsonSerializerContext
{
}
