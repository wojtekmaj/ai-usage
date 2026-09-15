using System.Text.Json;
using System.Text.Json.Nodes;
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
                var data = JsonNode.Parse(File.ReadAllText(AppPaths.UsageFile));

                /**
                 * Saved snapshots can contain retired metric kinds. Remove those entries before
                 * decoding so one unknown enum value does not discard all cached usage.
                 */
                if (data?["snapshots"] is JsonObject snapshots)
                {
                    foreach (var snapshot in snapshots)
                    {
                        if (snapshot.Value?["metrics"] is not JsonArray metrics)
                        {
                            continue;
                        }

                        for (var index = metrics.Count - 1; index >= 0; index--)
                        {
                            var kind = metrics[index]?["kind"]?.GetValue<string>();
                            if (!Enum.TryParse<UsageMetricKind>(kind, true, out var metricKind) || !Enum.IsDefined(metricKind))
                            {
                                metrics.RemoveAt(index);
                            }
                        }
                    }
                }

                return data.Deserialize(JsonDefaults.TypeInfo<PersistedUsage>()) ?? new PersistedUsage();
            }
        }
        catch (Exception error) when (error is JsonException or IOException or InvalidOperationException)
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
