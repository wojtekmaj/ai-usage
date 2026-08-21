using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;
using AiUsage.Windows.Domain;

namespace AiUsage.Windows.Services;

internal sealed partial class Localizer
{
    private readonly IReadOnlyDictionary<string, string> english;
    private IReadOnlyDictionary<string, string> selected;

    public Localizer(AppLanguage language)
    {
        english = LoadCatalog("en-US.json");
        selected = LoadCatalog(FileName(language));
        Language = language;
    }

    public AppLanguage Language { get; private set; }

    public CultureInfo Culture => CultureInfo.GetCultureInfo(CultureName(Language));

    public event EventHandler? Changed;

    public string this[string key] => Text(key);

    public void SetLanguage(AppLanguage language)
    {
        if (Language == language)
        {
            return;
        }
        selected = LoadCatalog(FileName(language));
        Language = language;
        Changed?.Invoke(this, EventArgs.Empty);
    }

    public string Text(string key)
    {
        if (selected.TryGetValue(key, out var value) || english.TryGetValue(key, out value))
        {
            return value;
        }
        return key;
    }

    public string Format(string key, params object[] arguments)
    {
        var index = 0;
        return FormatPlaceholder().Replace(Text(key), match =>
        {
            if (match.Value == "%%")
            {
                return "%";
            }
            if (index >= arguments.Length)
            {
                return match.Value;
            }
            var argument = arguments[index++];
            return argument is IFormattable formattable
                ? formattable.ToString(null, Culture)
                : argument?.ToString() ?? string.Empty;
        });
    }

    public string ProviderName(ProviderId provider) => provider switch
    {
        ProviderId.Codex => Text("providerCodex"),
        ProviderId.Claude => Text("providerClaude"),
        ProviderId.Copilot => Text("providerCopilot"),
        _ => provider.ToString(),
    };

    public string MetricTitle(UsageMetricKind kind) => kind switch
    {
        UsageMetricKind.CodexFiveHour or UsageMetricKind.ClaudeFiveHour => Text("usageLimitFiveHour"),
        UsageMetricKind.CodexWeekly or UsageMetricKind.ClaudeWeekly => Text("usageLimitWeekly"),
        UsageMetricKind.CodexSparkFiveHour => Text("usageLimitFiveHourCodexSpark"),
        UsageMetricKind.CodexSparkWeekly => Text("usageLimitWeeklyCodexSpark"),
        UsageMetricKind.CodexCredits => Text("usageMetricCredits"),
        UsageMetricKind.CodexLimitResets => Text("usageMetricLimitResets"),
        UsageMetricKind.CopilotMonthly => Text("usageLimitMonthly"),
        _ => kind.ToString(),
    };

    public string LanguageDisplayName(AppLanguage language) => language switch
    {
        AppLanguage.EnglishUS => "English (US)",
        AppLanguage.Polish => "Polski",
        AppLanguage.Spanish => "Español",
        AppLanguage.German => "Deutsch",
        AppLanguage.French => "Français",
        AppLanguage.Japanese => "日本語",
        AppLanguage.PortugueseBrazil => "Português (Brasil)",
        _ => language.ToString(),
    };

    private static IReadOnlyDictionary<string, string> LoadCatalog(string fileName)
    {
        var path = Path.Combine(AppContext.BaseDirectory, "Localization", fileName);
        return File.Exists(path)
            ? JsonSerializer.Deserialize<Dictionary<string, string>>(
                File.ReadAllText(path),
                JsonDefaults.TypeInfo<Dictionary<string, string>>()) ?? new Dictionary<string, string>()
            : new Dictionary<string, string>();
    }

    private static string FileName(AppLanguage language) => $"{CultureName(language)}.json";

    private static string CultureName(AppLanguage language) => language switch
    {
        AppLanguage.EnglishUS => "en-US",
        AppLanguage.Polish => "pl-PL",
        AppLanguage.Spanish => "es-ES",
        AppLanguage.German => "de-DE",
        AppLanguage.French => "fr-FR",
        AppLanguage.Japanese => "ja-JP",
        AppLanguage.PortugueseBrazil => "pt-BR",
        _ => "en-US",
    };

    [GeneratedRegex("%@|%d|%%")]
    private static partial Regex FormatPlaceholder();
}
