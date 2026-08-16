using System.Text.Json;
using AiUsage.Windows.Domain;

namespace AiUsage.Windows.Services;

internal sealed class UsageStore
{
    private PersistedUsage state;

    public UsageStore()
    {
        state = Load();
    }

    public IReadOnlyDictionary<ProviderId, ProviderSnapshot> Snapshots => state.Snapshots;

    public IReadOnlyDictionary<string, UsageAlertState> AlertStates => state.AlertStates;

    public IReadOnlySet<string> ResetMarkers => state.ResetMarkers;

    public void SaveSnapshots(IReadOnlyDictionary<ProviderId, ProviderSnapshot> snapshots)
    {
        state.Snapshots = snapshots.ToDictionary();
        Save();
    }

    public void SaveAlertStates(IReadOnlyDictionary<string, UsageAlertState> alertStates)
    {
        state.AlertStates = alertStates.ToDictionary();
        Save();
    }

    public void AddResetMarker(string marker)
    {
        state.ResetMarkers.Add(marker);
        Save();
    }

    private static PersistedUsage Load()
    {
        try
        {
            if (File.Exists(AppPaths.UsageFile))
            {
                return JsonSerializer.Deserialize<PersistedUsage>(
                    File.ReadAllText(AppPaths.UsageFile),
                    JsonDefaults.TypeInfo<PersistedUsage>()) ?? new PersistedUsage();
            }
        }
        catch (Exception error) when (error is JsonException or IOException)
        {
        }
        return new PersistedUsage();
    }

    private void Save()
    {
        AppPaths.EnsureDataDirectory();
        File.WriteAllText(
            AppPaths.UsageFile,
            JsonSerializer.Serialize(state, JsonDefaults.TypeInfo<PersistedUsage>()));
    }
}
