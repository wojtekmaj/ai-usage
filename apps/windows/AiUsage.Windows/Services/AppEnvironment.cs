using System.Diagnostics;
using AiUsage.Windows.Domain;

namespace AiUsage.Windows.Services;

internal sealed class AppEnvironment : IDisposable
{
    private const string CopilotTokenAccount = "copilot.github-oauth-token";
    private readonly SemaphoreSlim refreshLock = new(1, 1);
    private readonly CancellationTokenSource lifetime = new();
    private Task? refreshLoop;
    private CancellationTokenSource? refreshLoopCancellation;
    private CancellationTokenSource? copilotSignIn;

    public AppEnvironment()
    {
        Settings = new SettingsStore();
        Logs = new LogStore();
        Usage = new UsageStore();
        Credentials = new CredentialStore();
        Core = new CoreClient();
        Localizer = new Localizer(Settings.Preferences.Language);
        Notifications = new NotificationService(Core, Usage);
        Snapshots = Usage.Snapshots.ToDictionary();
        Settings.Changed += SettingsChanged;
    }

    public SettingsStore Settings { get; }

    public LogStore Logs { get; }

    public UsageStore Usage { get; }

    public CredentialStore Credentials { get; }

    public CoreClient Core { get; }

    public Localizer Localizer { get; }

    public NotificationService Notifications { get; }

    public Dictionary<ProviderId, ProviderSnapshot> Snapshots { get; private set; }

    public bool IsRefreshing { get; private set; }

    public CopilotDeviceCode? PendingCopilotDeviceCode { get; private set; }

    public event EventHandler? Changed;

    public void Start()
    {
        Notifications.Start();
        RestartRefreshLoop();
        _ = RefreshAsync(lifetime.Token);
    }

    public async Task RefreshAsync(CancellationToken cancellationToken = default)
    {
        if (!await refreshLock.WaitAsync(0, cancellationToken))
        {
            return;
        }
        IsRefreshing = true;
        OnChanged();
        try
        {
            var previous = Snapshots.ToDictionary();
            var token = Credentials.Load(CopilotTokenAccount);
            var tasks = Enum.GetValues<ProviderId>().ToDictionary(
                provider => provider,
                provider => Core.RefreshAsync(
                    provider,
                    provider == ProviderId.Copilot ? token : null,
                    cancellationToken));
            await Task.WhenAll(tasks.Values);
            Snapshots = tasks.ToDictionary(item => item.Key, item => item.Value.Result);
            Usage.SaveSnapshots(Snapshots);

            foreach (var snapshot in Snapshots.Values)
            {
                var level = snapshot.FetchState switch
                {
                    ProviderFetchState.Ok => AppLogLevel.Info,
                    ProviderFetchState.MissingAuth => AppLogLevel.Warning,
                    _ => AppLogLevel.Error,
                };
                Logs.Append(level, snapshot.Provider.ToString().ToLowerInvariant(),
                    snapshot.FetchState == ProviderFetchState.Ok
                        ? "Usage refreshed."
                        : snapshot.ErrorDescription ?? "Authentication is not configured.");
            }
            await Notifications.ProcessRefreshAsync(
                previous,
                Snapshots,
                Settings.Preferences,
                Localizer,
                DateTimeOffset.UtcNow,
                cancellationToken);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
        }
        catch (Exception error)
        {
            Logs.Append(AppLogLevel.Error, "refresh", error.Message);
        }
        finally
        {
            IsRefreshing = false;
            refreshLock.Release();
            OnChanged();
        }
    }

    public async Task SignInToCopilotAsync()
    {
        copilotSignIn?.Cancel();
        copilotSignIn?.Dispose();
        copilotSignIn = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
        var cancellationToken = copilotSignIn.Token;
        try
        {
            var code = await Core.RequestCopilotDeviceCodeAsync(cancellationToken);
            PendingCopilotDeviceCode = code;
            OnChanged();
            OpenUrl(code.VerificationUri);
            var expiresAt = DateTimeOffset.UtcNow.AddSeconds(code.ExpiresIn);
            var delay = code.Interval;
            while (DateTimeOffset.UtcNow < expiresAt)
            {
                await Task.Delay(TimeSpan.FromSeconds(delay), cancellationToken);
                var result = await Core.PollCopilotTokenAsync(code.DeviceCode, code.Interval, cancellationToken);
                if (string.Equals(result.Status, "complete", StringComparison.OrdinalIgnoreCase) && result.AccessToken is not null)
                {
                    Credentials.Save(CopilotTokenAccount, result.AccessToken);
                    PendingCopilotDeviceCode = null;
                    OnChanged();
                    await RefreshAsync(cancellationToken);
                    return;
                }
                if (string.Equals(result.Status, "expired", StringComparison.OrdinalIgnoreCase))
                {
                    throw new InvalidOperationException("GitHub sign-in expired before it was completed.");
                }
                delay = result.RetryAfterSeconds ?? code.Interval;
            }
            throw new InvalidOperationException("GitHub sign-in expired before it was completed.");
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
        }
        catch (Exception error)
        {
            Logs.Append(AppLogLevel.Error, "copilot", error.Message);
            PendingCopilotDeviceCode = null;
            OnChanged();
        }
    }

    public async Task SignOutFromCopilotAsync()
    {
        copilotSignIn?.Cancel();
        PendingCopilotDeviceCode = null;
        Credentials.Delete(CopilotTokenAccount);
        await RefreshAsync(lifetime.Token);
    }

    public bool HasCopilotToken()
    {
        try
        {
            return !string.IsNullOrWhiteSpace(Credentials.Load(CopilotTokenAccount));
        }
        catch
        {
            return false;
        }
    }

    public void OpenProviderSettings(ProviderId provider) => OpenUrl(provider switch
    {
        ProviderId.Codex => "https://chatgpt.com/codex/cloud/settings/usage",
        ProviderId.Claude => "https://claude.ai/settings/usage",
        ProviderId.Copilot => "https://github.com/settings/copilot/features",
        _ => "https://github.com/wojtekmaj/ai-usage",
    });

    public void Dispose()
    {
        Settings.Changed -= SettingsChanged;
        lifetime.Cancel();
        refreshLoopCancellation?.Cancel();
        refreshLoopCancellation?.Dispose();
        copilotSignIn?.Cancel();
        copilotSignIn?.Dispose();
        Notifications.Dispose();
        refreshLock.Dispose();
        lifetime.Dispose();
    }

    private void SettingsChanged(object? sender, EventArgs args)
    {
        Localizer.SetLanguage(Settings.Preferences.Language);
        RestartRefreshLoop();
        OnChanged();
    }

    private void RestartRefreshLoop()
    {
        refreshLoopCancellation?.Cancel();
        refreshLoopCancellation?.Dispose();
        refreshLoopCancellation = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
        refreshLoop = RunRefreshLoopAsync(refreshLoopCancellation.Token);
    }

    private async Task RunRefreshLoopAsync(CancellationToken cancellationToken)
    {
        var interval = TimeSpan.FromMinutes(Settings.Preferences.RefreshIntervalMinutes);
        using var timer = new PeriodicTimer(interval);
        try
        {
            while (await timer.WaitForNextTickAsync(cancellationToken))
            {
                await RefreshAsync(cancellationToken);
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
        }
    }

    private static void OpenUrl(string url)
    {
        Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
    }

    private void OnChanged() => Changed?.Invoke(this, EventArgs.Empty);
}
