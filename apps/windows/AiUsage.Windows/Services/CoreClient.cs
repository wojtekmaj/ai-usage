using System.Diagnostics;
using System.Text.Json;
using AiUsage.Windows.Domain;

namespace AiUsage.Windows.Services;

internal sealed class CoreClient
{
    public async Task<ProviderAuthState> GetAuthStateAsync(
        ProviderId provider,
        bool copilotTokenPresent,
        CancellationToken cancellationToken)
    {
        return await SendAsync<AuthStateRequest, ProviderAuthState>(
            new AuthStateRequest("authState", provider, copilotTokenPresent),
            cancellationToken);
    }

    public async Task<ProviderSnapshot> RefreshAsync(
        ProviderId provider,
        string? copilotToken,
        CancellationToken cancellationToken)
    {
        return await SendAsync<RefreshRequest, ProviderSnapshot>(
            new RefreshRequest("refresh", provider, copilotToken, DateTimeOffset.UtcNow),
            cancellationToken);
    }

    public async Task<CopilotDeviceCode> RequestCopilotDeviceCodeAsync(CancellationToken cancellationToken)
    {
        return await SendAsync<DeviceCodeRequest, CopilotDeviceCode>(
            new DeviceCodeRequest("requestCopilotDeviceCode"),
            cancellationToken);
    }

    public async Task<CopilotPollResult> PollCopilotTokenAsync(
        string deviceCode,
        ulong defaultInterval,
        CancellationToken cancellationToken)
    {
        return await SendAsync<PollTokenRequest, CopilotPollResult>(
            new PollTokenRequest("pollCopilotToken", deviceCode, defaultInterval),
            cancellationToken);
    }

    public async Task<ScheduleEvaluationResult?> EvaluateScheduleAsync(
        UsageMetric metric,
        UsageAlertDirection direction,
        UsageAlertState? previousState,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        return await SendAsync<EvaluateScheduleRequest, ScheduleEvaluationResult?>(
            new EvaluateScheduleRequest("evaluateSchedule", metric, direction, previousState, now),
            cancellationToken);
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
        if (!response.Ok)
        {
            throw new InvalidOperationException(response.Error?.Message ?? "The AI Usage shared core failed.");
        }
        return response.Data!;
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
