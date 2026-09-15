using System.Globalization;

namespace AiUsage.Windows.Domain;

internal static class UsageAmountTextFormatter
{
    public static string Format(double? remaining, double? total, CultureInfo culture)
    {
        string FormatNumber(double? value) => value is double amount
            ? Math.Round(amount, MidpointRounding.AwayFromZero).ToString("N0", culture)
            : "—";

        return $"{FormatNumber(remaining)}/{FormatNumber(total)}";
    }
}
