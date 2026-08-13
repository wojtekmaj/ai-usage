using System.Net;
using System.Net.Http.Headers;
using System.Reflection;
using System.Text.Json;

namespace AiUsage.Windows.Services;

internal sealed record AppRelease(string Version, Uri PageUri);

internal enum UpdateCheckStatus
{
    Idle,
    Checking,
    UpToDate,
    Available,
    Failed,
}

internal sealed class UpdateChecker : IDisposable
{
    private static readonly Uri ReleasesEndpoint = new("https://api.github.com/repos/wojtekmaj/ai-usage/releases?per_page=20");
    private static readonly TimeSpan CheckInterval = TimeSpan.FromHours(24);
    private readonly NotificationService notifications;
    private readonly LogStore logs;
    private readonly HttpClient httpClient;
    private readonly SemaphoreSlim checkLock = new(1, 1);
    private UpdateCheckMetadata metadata;

    public UpdateChecker(NotificationService notifications, LogStore logs, HttpClient? httpClient = null)
    {
        this.notifications = notifications;
        this.logs = logs;
        this.httpClient = httpClient ?? new HttpClient();
        metadata = LoadMetadata();
        CurrentVersion = GetCurrentVersion();
        if (metadata.CachedVersion is not null
            && Uri.TryCreate(metadata.CachedPageUrl, UriKind.Absolute, out var cachedUri)
            && cachedUri.Scheme == Uri.UriSchemeHttps
            && string.Equals(cachedUri.Host, "github.com", StringComparison.OrdinalIgnoreCase)
            && SemanticVersion.TryParse(CurrentVersion, out var installed)
            && SemanticVersion.TryParse(metadata.CachedVersion, out var latest)
            && installed.CompareTo(latest) < 0)
        {
            AvailableRelease = new AppRelease(metadata.CachedVersion, cachedUri);
            Status = UpdateCheckStatus.Available;
        }
    }

    public string CurrentVersion { get; }

    public UpdateCheckStatus Status { get; private set; }

    public AppRelease? AvailableRelease { get; private set; }

    public event EventHandler? Changed;

    public Task CheckIfDueAsync(Localizer localizer, CancellationToken cancellationToken)
    {
        return metadata.LastCheckUtc is null || DateTimeOffset.UtcNow - metadata.LastCheckUtc >= CheckInterval
            ? CheckAsync(manual: false, localizer, cancellationToken)
            : Task.CompletedTask;
    }

    public async Task CheckManuallyAsync(Localizer localizer, CancellationToken cancellationToken = default)
    {
        await CheckAsync(manual: true, localizer, cancellationToken);
    }

    public void Dispose()
    {
        httpClient.Dispose();
    }

    private async Task CheckAsync(bool manual, Localizer localizer, CancellationToken cancellationToken)
    {
        if (!await checkLock.WaitAsync(0, cancellationToken))
        {
            return;
        }

        Status = UpdateCheckStatus.Checking;
        OnChanged();
        try
        {
            var release = await FetchLatestApplicableReleaseAsync(cancellationToken);
            if (!SemanticVersion.TryParse(CurrentVersion, out var installed)
                || !SemanticVersion.TryParse(release.Version, out var latest))
            {
                throw new InvalidDataException("The installed or release version is invalid.");
            }

            metadata = metadata with { LastCheckUtc = DateTimeOffset.UtcNow };
            if (installed.CompareTo(latest) < 0)
            {
                AvailableRelease = release;
                Status = UpdateCheckStatus.Available;
                if (!manual && !string.Equals(metadata.LastNotifiedVersion, release.Version, StringComparison.Ordinal))
                {
                    notifications.ShowUpdateAvailable(release, localizer);
                    metadata = metadata with { LastNotifiedVersion = release.Version };
                }
            }
            else
            {
                AvailableRelease = null;
                Status = UpdateCheckStatus.UpToDate;
            }
            SaveMetadata();
            logs.Append(Domain.AppLogLevel.Info, "updates", $"Update check completed. Installed={CurrentVersion}, latest={release.Version}.");
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            Status = UpdateCheckStatus.Idle;
        }
        catch (Exception error)
        {
            Status = UpdateCheckStatus.Failed;
            logs.Append(Domain.AppLogLevel.Warning, "updates", $"Update check failed: {error.Message}");
        }
        finally
        {
            checkLock.Release();
            OnChanged();
        }
    }

    private async Task<AppRelease> FetchLatestApplicableReleaseAsync(CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, ReleasesEndpoint);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
        request.Headers.UserAgent.ParseAdd($"AI-Usage/{CurrentVersion}");
        request.Headers.Add("X-GitHub-Api-Version", "2022-11-28");
        if (!string.IsNullOrWhiteSpace(metadata.ETag))
        {
            request.Headers.TryAddWithoutValidation("If-None-Match", metadata.ETag);
        }

        using var response = await httpClient.SendAsync(request, cancellationToken);
        if (response.StatusCode == HttpStatusCode.NotModified
            && metadata.CachedVersion is not null
            && Uri.TryCreate(metadata.CachedPageUrl, UriKind.Absolute, out var cachedUri)
            && cachedUri.Scheme == Uri.UriSchemeHttps
            && string.Equals(cachedUri.Host, "github.com", StringComparison.OrdinalIgnoreCase))
        {
            return new AppRelease(metadata.CachedVersion, cachedUri);
        }
        response.EnsureSuccessStatusCode();

        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var document = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);
        if (!SemanticVersion.TryParse(CurrentVersion, out var installed))
        {
            throw new InvalidDataException("The installed version is invalid.");
        }
        var acceptsPrereleases = installed.Prerelease.Count > 0;
        AppRelease? latestRelease = null;
        SemanticVersion? latestVersion = null;
        foreach (var item in document.RootElement.EnumerateArray())
        {
            if (item.GetProperty("draft").GetBoolean()
                || (!acceptsPrereleases && item.GetProperty("prerelease").GetBoolean()))
            {
                continue;
            }
            var tag = item.GetProperty("tag_name").GetString();
            var pageUrl = item.GetProperty("html_url").GetString();
            if (!SemanticVersion.TryParse(tag, out var version)
                || !Uri.TryCreate(pageUrl, UriKind.Absolute, out var pageUri)
                || pageUri.Scheme != Uri.UriSchemeHttps
                || !string.Equals(pageUri.Host, "github.com", StringComparison.OrdinalIgnoreCase)
                || latestVersion is not null && version.CompareTo(latestVersion) <= 0)
            {
                continue;
            }
            latestVersion = version;
            latestRelease = new AppRelease(tag!.TrimStart('v'), pageUri);
        }
        if (latestRelease is null)
        {
            throw new InvalidDataException("No applicable GitHub Release was found.");
        }

        metadata = metadata with
        {
            ETag = response.Headers.ETag?.ToString(),
            CachedVersion = latestRelease.Version,
            CachedPageUrl = latestRelease.PageUri.AbsoluteUri,
        };
        return latestRelease;
    }

    private static string GetCurrentVersion()
    {
        var assembly = Assembly.GetExecutingAssembly();
        var informational = assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion;
        if (!string.IsNullOrWhiteSpace(informational))
        {
            return informational.Split('+', 2)[0];
        }
        return assembly.GetName().Version?.ToString(3) ?? "0.0.0";
    }

    private static UpdateCheckMetadata LoadMetadata()
    {
        try
        {
            if (File.Exists(AppPaths.UpdateStateFile))
            {
                return JsonSerializer.Deserialize(
                    File.ReadAllText(AppPaths.UpdateStateFile),
                    Domain.JsonDefaults.TypeInfo<UpdateCheckMetadata>()) ?? new UpdateCheckMetadata();
            }
        }
        catch (JsonException)
        {
        }
        catch (IOException)
        {
        }
        return new UpdateCheckMetadata();
    }

    private void SaveMetadata()
    {
        AppPaths.EnsureDataDirectory();
        File.WriteAllText(
            AppPaths.UpdateStateFile,
            JsonSerializer.Serialize(metadata, Domain.JsonDefaults.TypeInfo<UpdateCheckMetadata>()));
    }

    private void OnChanged() => Changed?.Invoke(this, EventArgs.Empty);
}

internal sealed record UpdateCheckMetadata(
    DateTimeOffset? LastCheckUtc = null,
    string? ETag = null,
    string? CachedVersion = null,
    string? CachedPageUrl = null,
    string? LastNotifiedVersion = null);

internal sealed class SemanticVersion : IComparable<SemanticVersion>
{
    private SemanticVersion(int major, int minor, int patch, IReadOnlyList<string> prerelease)
    {
        Major = major;
        Minor = minor;
        Patch = patch;
        Prerelease = prerelease;
    }

    public int Major { get; }
    public int Minor { get; }
    public int Patch { get; }
    public IReadOnlyList<string> Prerelease { get; }

    public static bool TryParse(string? input, out SemanticVersion version)
    {
        version = null!;
        if (string.IsNullOrWhiteSpace(input)) return false;
        var value = input[0] == 'v' ? input[1..] : input;
        value = value.Split('+', 2)[0];
        var versionAndPrerelease = value.Split('-', 2);
        var core = versionAndPrerelease[0].Split('.');
        if (core.Length != 3
            || !TryParseNumber(core[0], out var major)
            || !TryParseNumber(core[1], out var minor)
            || !TryParseNumber(core[2], out var patch))
        {
            return false;
        }
        var prerelease = versionAndPrerelease.Length == 2 ? versionAndPrerelease[1].Split('.') : [];
        if (prerelease.Any(identifier => identifier.Length == 0
            || identifier.Any(character => !char.IsAsciiLetterOrDigit(character) && character != '-')
            || identifier.All(char.IsDigit) && identifier.Length > 1 && identifier[0] == '0'))
        {
            return false;
        }
        version = new SemanticVersion(major, minor, patch, prerelease);
        return true;
    }

    public int CompareTo(SemanticVersion? other)
    {
        if (other is null) return 1;
        var coreComparison = Major.CompareTo(other.Major);
        if (coreComparison == 0) coreComparison = Minor.CompareTo(other.Minor);
        if (coreComparison == 0) coreComparison = Patch.CompareTo(other.Patch);
        if (coreComparison != 0) return coreComparison;
        if (Prerelease.Count == 0 || other.Prerelease.Count == 0)
        {
            return Prerelease.Count == other.Prerelease.Count ? 0 : Prerelease.Count == 0 ? 1 : -1;
        }
        for (var index = 0; index < Math.Min(Prerelease.Count, other.Prerelease.Count); index++)
        {
            var left = Prerelease[index];
            var right = other.Prerelease[index];
            if (left == right) continue;
            var leftIsNumber = int.TryParse(left, out var leftNumber);
            var rightIsNumber = int.TryParse(right, out var rightNumber);
            if (leftIsNumber && rightIsNumber) return leftNumber.CompareTo(rightNumber);
            if (leftIsNumber) return -1;
            if (rightIsNumber) return 1;
            return string.CompareOrdinal(left, right);
        }
        return Prerelease.Count.CompareTo(other.Prerelease.Count);
    }

    private static bool TryParseNumber(string value, out int number)
    {
        number = 0;
        return value.Length > 0
            && (value.Length == 1 || value[0] != '0')
            && int.TryParse(value, out number);
    }
}
