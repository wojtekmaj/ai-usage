namespace AiUsage.Windows.Services;

internal static class AppPaths
{
    public static string DataDirectory { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "AI Usage");

    public static string SettingsFile => Path.Combine(DataDirectory, "settings.json");

    public static string UsageFile => Path.Combine(DataDirectory, "usage.json");

    public static string LogsFile => Path.Combine(DataDirectory, "logs.json");

    public static string UpdateStateFile => Path.Combine(DataDirectory, "updates.json");

    public static void EnsureDataDirectory() => Directory.CreateDirectory(DataDirectory);
}
