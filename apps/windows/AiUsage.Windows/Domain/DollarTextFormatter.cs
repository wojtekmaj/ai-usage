using System.Globalization;

namespace AiUsage.Windows.Domain;

internal static class DollarTextFormatter
{
    public static string Format(double? amount, CultureInfo culture) =>
        amount is double value && double.IsFinite(value)
            ? "$" + Math.Round(value, 2, MidpointRounding.AwayFromZero).ToString("N2", culture)
            : "—";

    public static string Format(double? remaining, double? total, CultureInfo culture) =>
        $"{Format(remaining, culture)}/{Format(total, culture)}";
}
