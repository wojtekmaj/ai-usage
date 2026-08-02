using System.Text.Json;
using AiUsage.Windows.Domain;

namespace AiUsage.Windows.Services;

internal sealed class SettingsStore
{
    public SettingsStore()
    {
        Preferences = Load();
    }

    public DisplayPreferences Preferences { get; private set; }

    public event EventHandler? Changed;

    public TimeSpan StalenessThreshold => TimeSpan.FromMinutes(Math.Max(Preferences.RefreshIntervalMinutes * 2, 15));

    public void Update(Action<DisplayPreferences> update)
    {
        update(Preferences);
        Normalize(Preferences);
        Save();
        Changed?.Invoke(this, EventArgs.Empty);
    }

    private static DisplayPreferences Load()
    {
        try
        {
            if (File.Exists(AppPaths.SettingsFile))
            {
                var preferences = JsonSerializer.Deserialize<DisplayPreferences>(
                    File.ReadAllText(AppPaths.SettingsFile),
                    JsonDefaults.TypeInfo<DisplayPreferences>());
                if (preferences is not null)
                {
                    Normalize(preferences);
                    return preferences;
                }
            }
        }
        catch (JsonException)
        {
        }
        catch (IOException)
        {
        }

        return new DisplayPreferences();
    }

    private void Save()
    {
        AppPaths.EnsureDataDirectory();
        File.WriteAllText(
            AppPaths.SettingsFile,
            JsonSerializer.Serialize(Preferences, JsonDefaults.TypeInfo<DisplayPreferences>()));
    }

    private static void Normalize(DisplayPreferences preferences)
    {
        preferences.RefreshIntervalMinutes = preferences.RefreshIntervalMinutes is 1 or 5 or 10 or 15
            ? preferences.RefreshIntervalMinutes
            : 5;
        if (preferences.VisibleProviders.Count == 0)
        {
            preferences.VisibleProviders.Add(ProviderId.Codex);
        }
        if (preferences.VisiblePanelProviders.Count == 0)
        {
            preferences.VisiblePanelProviders.Add(ProviderId.Codex);
        }
    }
}
