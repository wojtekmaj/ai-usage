using System.Text.Json;
using AiUsage.Windows.Domain;

namespace AiUsage.Windows.Services;

internal sealed class LogStore
{
    private const int MaximumEntries = 300;
    private readonly List<AppLogEntry> entries;

    public LogStore()
    {
        entries = Load();
    }

    public IReadOnlyList<AppLogEntry> Entries => entries;

    public event EventHandler? Changed;

    public void Append(AppLogLevel level, string category, string message)
    {
        entries.Add(new AppLogEntry(Guid.NewGuid(), DateTimeOffset.UtcNow, level, category, message));
        if (entries.Count > MaximumEntries)
        {
            entries.RemoveRange(0, entries.Count - MaximumEntries);
        }
        Save();
        Changed?.Invoke(this, EventArgs.Empty);
    }

    public void Append(string category, string message) => Append(AppLogLevel.Info, category, message);

    public void Clear()
    {
        entries.Clear();
        Save();
        Changed?.Invoke(this, EventArgs.Empty);
    }

    public string ExportText => string.Join(
        Environment.NewLine,
        entries.Select(entry =>
            $"[{entry.TimestampUtc:O}] [{entry.Level.ToString().ToUpperInvariant()}] [{entry.Category}] {entry.Message}"));

    private static List<AppLogEntry> Load()
    {
        try
        {
            return File.Exists(AppPaths.LogsFile)
                ? JsonSerializer.Deserialize<List<AppLogEntry>>(
                    File.ReadAllText(AppPaths.LogsFile),
                    JsonDefaults.TypeInfo<List<AppLogEntry>>()) ?? []
                : [];
        }
        catch (Exception error) when (error is JsonException or IOException)
        {
            return [];
        }
    }

    private void Save()
    {
        AppPaths.EnsureDataDirectory();
        File.WriteAllText(
            AppPaths.LogsFile,
            JsonSerializer.Serialize(entries, JsonDefaults.TypeInfo<List<AppLogEntry>>()));
    }
}
