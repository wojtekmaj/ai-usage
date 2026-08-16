using System.Diagnostics;
using System.Text.Json;
using AiUsage.Windows.Domain;

namespace AiUsage.Windows.Services;

internal sealed class CoreClient
{
    private const int ProtocolVersion = 1;

    public async Task<IReadOnlyList<ProviderSnapshot>> RefreshAsync(
        string? copilotToken,
        CancellationToken cancellationToken)
    {
        var snapshots = await SendAsync<RefreshRequest, List<ProviderSnapshot>>(
            new RefreshRequest(ProtocolVersion, "refresh", copilotToken, null, DateTimeOffset.UtcNow),
            cancellationToken);
        var providers = snapshots.Select(snapshot => snapshot.Provider).ToHashSet();
        if (snapshots.Count != Enum.GetValues<ProviderId>().Length
            || !providers.SetEquals(Enum.GetValues<ProviderId>()))
        {
            throw new InvalidDataException("A shared-core refresh must return exactly one snapshot for every provider.");
        }
        return snapshots;
    }

    public async Task<CopilotDeviceCode> RequestCopilotDeviceCodeAsync(CancellationToken cancellationToken)
    {
        return await SendAsync<DeviceCodeRequest, CopilotDeviceCode>(
            new DeviceCodeRequest(ProtocolVersion, "requestCopilotDeviceCode"),
            cancellationToken);
    }

    public async Task PreheatCodexAsync(CancellationToken cancellationToken)
    {
        await SendAsync<PreheatCodexRequest, bool>(
            new PreheatCodexRequest(ProtocolVersion, "preheatCodex"),
            cancellationToken);
    }

    public async Task<CopilotPollResult> PollCopilotTokenAsync(
        string deviceCode,
        ulong defaultInterval,
        CancellationToken cancellationToken)
    {
        return await SendAsync<PollTokenRequest, CopilotPollResult>(
            new PollTokenRequest(ProtocolVersion, "pollCopilotToken", deviceCode, defaultInterval),
            cancellationToken);
    }

    public async Task<IReadOnlyList<ScheduleEvaluationResult?>> EvaluateSchedulesAsync(
        IReadOnlyList<ScheduleEvaluationInput> evaluations,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        if (evaluations.Count == 0)
        {
            return [];
        }
        var results = await SendAsync<EvaluateSchedulesRequest, List<ScheduleEvaluationResult?>>(
            new EvaluateSchedulesRequest(ProtocolVersion, "evaluateSchedules", evaluations, now),
            cancellationToken);
        if (results.Count != evaluations.Count)
        {
            throw new InvalidDataException("The shared core returned an unexpected number of schedule evaluations.");
        }
        return results;
    }

    private static async Task<TResponse> SendAsync<TRequest, TResponse>(
        TRequest request,
        CancellationToken cancellationToken)
    {
        var executable = FindCoreExecutable();
        var startInfo = new ProcessStartInfo(executable)
        {
            CreateNoWindow = true,
            UseShellExecute = false,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        using var process = Process.Start(startInfo) ?? throw new InvalidOperationException("Unable to start the AI Usage shared core.");
        await process.StandardInput.WriteAsync(
            JsonSerializer.Serialize(request, JsonDefaults.TypeInfo<TRequest>()));
        process.StandardInput.Close();
        var outputTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
        var errorTask = process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken);
        var output = await outputTask;
        var standardError = await errorTask;
        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException($"The AI Usage shared core exited with code {process.ExitCode}: {standardError}");
        }

        var response = JsonSerializer.Deserialize<CoreResponse<TResponse>>(
                output,
                JsonDefaults.TypeInfo<CoreResponse<TResponse>>())
            ?? throw new InvalidOperationException("The AI Usage shared core returned no response.");
        if (response.ProtocolVersion != ProtocolVersion)
        {
            throw new InvalidDataException(
                $"The AI Usage shared core uses protocol version {response.ProtocolVersion}, but the app requires version {ProtocolVersion}.");
        }
        if (!response.Ok)
        {
            throw new InvalidOperationException(
                $"{response.Error?.Message ?? "The AI Usage shared core failed."} ({response.Error?.Code ?? "unknown"})");
        }
        if (response.Data is null)
        {
            throw new InvalidDataException("The AI Usage shared core returned a successful response without data.");
        }
        return response.Data;
    }

    private static string FindCoreExecutable()
    {
        const string fileName = "ai-usage-core.exe";
        var bundled = Path.Combine(AppContext.BaseDirectory, fileName);
        if (File.Exists(bundled))
        {
            return bundled;
        }

        for (var directory = new DirectoryInfo(AppContext.BaseDirectory); directory is not null; directory = directory.Parent)
        {
            var development = Path.Combine(directory.FullName, "target", "debug", fileName);
            if (File.Exists(development))
            {
                return development;
            }
        }
        throw new FileNotFoundException("The AI Usage shared core executable was not found.", fileName);
    }

}
