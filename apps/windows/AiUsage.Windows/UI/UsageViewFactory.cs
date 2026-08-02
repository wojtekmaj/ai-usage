using AiUsage.Windows.Domain;
using AiUsage.Windows.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace AiUsage.Windows.UI;

internal sealed class UsageViewFactory(AppEnvironment environment)
{
    public UIElement CreateUsageCard(ProviderId provider)
    {
        var localizer = environment.Localizer;
        var snapshot = environment.Snapshots.GetValueOrDefault(provider);
        var section = new StackPanel { Spacing = 8 };
        section.Children.Add(CreateProviderHeader(
            provider,
            snapshot,
            includeExternalLink: true,
            providerIconSize: 24));

        var panel = new StackPanel { Spacing = 12 };

        if (snapshot is null || snapshot.FetchState == ProviderFetchState.MissingAuth)
        {
            panel.Children.Add(new TextBlock
            {
                Text = localizer.Text("authenticationRequired"),
                Foreground = SecondaryBrush,
            });
        }
        else if (snapshot.FetchState == ProviderFetchState.Failed)
        {
            panel.Children.Add(new InfoBar
            {
                IsOpen = true,
                Severity = InfoBarSeverity.Error,
                Title = localizer.Text("fetchFailed"),
                Message = snapshot.ErrorDescription,
            });
        }

        foreach (var metric in VisibleMetrics(snapshot))
        {
            panel.Children.Add(CreateMetricRow(metric));
        }
        section.Children.Add(Card(panel));
        return section;
    }

    public UIElement CreateProviderHeader(
        ProviderId provider,
        ProviderSnapshot? snapshot,
        bool includeExternalLink,
        double providerIconSize = 28)
    {
        var grid = new Grid { ColumnSpacing = 10 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        grid.Children.Add(CreateProviderIcon(provider, providerIconSize));

        var title = new TextBlock
        {
            Text = environment.Localizer.ProviderName(provider),
            VerticalAlignment = VerticalAlignment.Center,
            Style = (Style)Application.Current.Resources["BodyStrongTextBlockStyle"],
        };
        Grid.SetColumn(title, 1);
        grid.Children.Add(title);

        if (snapshot?.FetchState != ProviderFetchState.Ok)
        {
            var status = new TextBlock
            {
                Text = environment.Localizer.Text("providerStatusNeedsAttention"),
                Foreground = SecondaryBrush,
                VerticalAlignment = VerticalAlignment.Center,
            };
            Grid.SetColumn(status, 2);
            grid.Children.Add(status);
        }

        if (includeExternalLink)
        {
            var link = new Button
            {
                Content = new FontIcon { Glyph = "\uE8A7", FontSize = 13 },
                Padding = new Thickness(7),
            };
            ToolTipService.SetToolTip(link, environment.Localizer.Text("openSettings"));
            link.Click += (_, _) => environment.OpenProviderSettings(provider);
            Grid.SetColumn(link, 3);
            grid.Children.Add(link);
        }
        return grid;
    }

    private UIElement CreateMetricRow(UsageMetric metric)
    {
        var localizer = environment.Localizer;
        var stack = new StackPanel { Spacing = 5 };
        var header = new Grid();
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        header.Children.Add(new TextBlock
        {
            Text = localizer.MetricTitle(metric.Kind),
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
        });
        var amount = new TextBlock { Text = MetricAmount(metric), Foreground = SecondaryBrush };
        Grid.SetColumn(amount, 1);
        header.Children.Add(amount);
        stack.Children.Add(header);

        if (metric.RemainingFraction is double remaining)
        {
            var remainingBar = CreateBar(remaining, isTimeRemaining: false);
            remainingBar.Margin = new Thickness(0, 3, 0, 0);
            stack.Children.Add(remainingBar);
            if (ExpectedRemaining(metric, DateTimeOffset.UtcNow) is double expected)
            {
                var expectedBar = CreateBar(expected, isTimeRemaining: true);
                ToolTipService.SetToolTip(expectedBar, $"Expected remaining: {Math.Round(expected * 100)}%");
                stack.Children.Add(expectedBar);
            }
        }
        if (metric.ResetAtUtc is DateTimeOffset reset)
        {
            stack.Children.Add(new TextBlock
            {
                Text = $"{localizer.Text("resetAt")}: {FormatReset(reset)}",
                Style = (Style)Application.Current.Resources["CaptionTextBlockStyle"],
                Foreground = SecondaryBrush,
            });
        }
        return stack;
    }

    private IEnumerable<UsageMetric> VisibleMetrics(ProviderSnapshot? snapshot)
    {
        if (snapshot is null)
        {
            return [];
        }
        var preferences = environment.Settings.Preferences;
        return snapshot.Metrics.Where(metric => metric.Kind switch
        {
            UsageMetricKind.CodexSparkFiveHour or UsageMetricKind.CodexSparkWeekly => preferences.ShowCodexSparkUsage,
            UsageMetricKind.CodexCredits => IsOptionalVisible(preferences.CodexCreditsVisibility, metric),
            UsageMetricKind.CodexLimitResets => IsOptionalVisible(preferences.CodexLimitResetsVisibility, metric),
            _ => true,
        });
    }

    private static bool IsOptionalVisible(OptionalMetricVisibility visibility, UsageMetric metric) => visibility switch
    {
        OptionalMetricVisibility.Always => true,
        OptionalMetricVisibility.OnlyWhenAboveZero => metric.RemainingValue > 0,
        _ => false,
    };

    private static Border Card(UIElement content) => new()
    {
        Style = (Style)Application.Current.Resources["SettingsCardStyle"],
        Child = content,
    };

    private string MetricAmount(UsageMetric metric)
    {
        if (metric.RemainingFraction is double fraction && metric.Unit is MetricUnit.Percentage or MetricUnit.Requests)
        {
            return $"{Math.Round(fraction * 100)}%";
        }
        if (metric.RemainingValue is double remaining && metric.TotalValue is double total)
        {
            return $"{Math.Round(remaining)} / {Math.Round(total)}";
        }
        if (metric.RemainingValue is double value)
        {
            return Math.Round(value).ToString(environment.Localizer.Culture);
        }
        return environment.Localizer.Text("unavailable");
    }

    private Grid CreateBar(double fraction, bool isTimeRemaining)
    {
        var clamped = Math.Clamp(fraction, 0, 1);
        var height = isTimeRemaining ? 4 : 10;
        var bar = new Grid { Height = height };
        bar.ColumnDefinitions.Add(new ColumnDefinition
        {
            Width = new GridLength(clamped, GridUnitType.Star),
        });
        bar.ColumnDefinitions.Add(new ColumnDefinition
        {
            Width = new GridLength(1 - clamped, GridUnitType.Star),
        });
        var radius = new CornerRadius(height / 2d);
        var track = new Border
        {
            Background = new SolidColorBrush(Microsoft.UI.ColorHelper.FromArgb(36, 127, 127, 127)),
            CornerRadius = radius,
        };
        Grid.SetColumnSpan(track, 2);
        bar.Children.Add(track);
        bar.Children.Add(new Border
        {
            Background = BarFill(fraction, isTimeRemaining),
            CornerRadius = radius,
        });
        return bar;
    }

    private Brush BarFill(double fraction, bool isTimeRemaining)
    {
        if (environment.Settings.Preferences.UsageBarColorStyle == UsageBarColorStyle.SystemAccent)
        {
            return (Brush)Application.Current.Resources["AccentFillColorDefaultBrush"];
        }
        var color = isTimeRemaining
            ? Microsoft.UI.ColorHelper.FromArgb(255, 0, 122, 255)
            : fraction switch
            {
                < 0.1 => Microsoft.UI.ColorHelper.FromArgb(255, 255, 59, 48),
                < 0.3 => Microsoft.UI.ColorHelper.FromArgb(255, 255, 204, 0),
                _ => Microsoft.UI.ColorHelper.FromArgb(255, 52, 199, 89),
            };
        return new LinearGradientBrush
        {
            StartPoint = new global::Windows.Foundation.Point(0, 0.5),
            EndPoint = new global::Windows.Foundation.Point(1, 0.5),
            GradientStops =
            {
                new GradientStop
                {
                    Color = Microsoft.UI.ColorHelper.FromArgb(242, color.R, color.G, color.B),
                    Offset = 0,
                },
                new GradientStop { Color = color, Offset = 1 },
            },
        };
    }

    private string FormatReset(DateTimeOffset reset)
    {
        var local = reset.ToLocalTime();
        return local.Date == DateTimeOffset.Now.Date
            ? local.ToString("t", environment.Localizer.Culture)
            : local.ToString("g", environment.Localizer.Culture);
    }

    private static FrameworkElement CreateProviderIcon(ProviderId provider, double size)
    {
        var templateKey = provider == ProviderId.Codex ? "CodexBitmapIconTemplate" : $"{provider}IconTemplate";
        var template = (DataTemplate)Application.Current.Resources[templateKey];
        var icon = (FrameworkElement)template.LoadContent();
        icon.Width = size;
        icon.Height = size;
        return icon;
    }

    private static double? ExpectedRemaining(UsageMetric metric, DateTimeOffset now)
    {
        if (metric.ResetAtUtc is not DateTimeOffset reset)
        {
            return null;
        }
        var duration = metric.Kind switch
        {
            UsageMetricKind.CodexFiveHour or UsageMetricKind.CodexSparkFiveHour or UsageMetricKind.ClaudeFiveHour => TimeSpan.FromHours(5),
            UsageMetricKind.CodexWeekly or UsageMetricKind.CodexSparkWeekly or UsageMetricKind.ClaudeWeekly => TimeSpan.FromDays(7),
            UsageMetricKind.CopilotMonthly => reset - reset.AddMonths(-1),
            _ => TimeSpan.Zero,
        };
        if (duration <= TimeSpan.Zero)
        {
            return null;
        }
        var elapsed = Math.Clamp((now - (reset - duration)).TotalSeconds / duration.TotalSeconds, 0, 1);
        return 1 - elapsed;
    }

    private static Brush SecondaryBrush => (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"];
}
