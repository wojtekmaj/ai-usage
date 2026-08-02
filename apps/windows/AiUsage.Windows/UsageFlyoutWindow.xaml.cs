using AiUsage.Windows.Domain;
using AiUsage.Windows.Services;
using AiUsage.Windows.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using System.Runtime.InteropServices;
using Windows.Graphics;

namespace AiUsage.Windows;

public sealed partial class UsageFlyoutWindow : Window
{
    private const int DwmUseImmersiveDarkModeAttribute = 20;
    private const int DwmWindowCornerPreferenceAttribute = 33;

    private readonly AppEnvironment environment;
    private readonly UsageViewFactory usageViews;
    private readonly DispatcherTimer relativeTimeTimer;
    private bool isVisible;
    private bool allowClose;

    internal UsageFlyoutWindow(AppEnvironment environment)
    {
        this.environment = environment;
        usageViews = new UsageViewFactory(environment);
        relativeTimeTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        relativeTimeTimer.Tick += (_, _) => RenderLastUpdate();
        InitializeComponent();
        Title = "AI Usage";
        ConfigureWindow();
        environment.Changed += Environment_Changed;
        environment.Localizer.Changed += Environment_Changed;
        Render();
    }

    internal event EventHandler? OpenSettingsRequested;

    internal void Toggle()
    {
        if (isVisible)
        {
            Hide();
        }
        else
        {
            ShowNearNotificationArea();
        }
    }

    internal void ShowNearNotificationArea()
    {
        Activate();
        var windowHandle = WinRT.Interop.WindowNative.GetWindowHandle(this);
        var scale = GetDpiForWindow(windowHandle) / 96d;
        var displayArea = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Nearest);
        if (displayArea is not null)
        {
            var workArea = displayArea.WorkArea;
            var width = Math.Min((int)Math.Round(440 * scale), workArea.Width - 24);
            var height = Math.Min((int)Math.Round(560 * scale), workArea.Height - 24);
            AppWindow.Resize(new SizeInt32(width, height));
            AppWindow.Move(new PointInt32(workArea.X + workArea.Width - width - 12, workArea.Y + workArea.Height - height - 12));
        }
        AppWindow.Show();
        isVisible = true;
        relativeTimeTimer.Start();
        Render();
    }

    internal void Hide()
    {
        AppWindow.Hide();
        isVisible = false;
        relativeTimeTimer.Stop();
    }

    internal void Quit()
    {
        allowClose = true;
        environment.Changed -= Environment_Changed;
        environment.Localizer.Changed -= Environment_Changed;
        relativeTimeTimer.Stop();
        Close();
    }

    private void ConfigureWindow()
    {
        SystemBackdrop = new DesktopAcrylicBackdrop();
        AppWindow.IsShownInSwitchers = false;
        if (AppWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.IsResizable = false;
            presenter.IsMaximizable = false;
            presenter.IsMinimizable = false;
            presenter.IsAlwaysOnTop = true;
            presenter.SetBorderAndTitleBar(true, false);
        }
        var cornerPreference = 2;
        DwmSetWindowAttribute(
            WinRT.Interop.WindowNative.GetWindowHandle(this),
            DwmWindowCornerPreferenceAttribute,
            ref cornerPreference,
            Marshal.SizeOf<int>());
        Root.ActualThemeChanged += Root_ActualThemeChanged;
        UpdateWindowFrameTheme();
        AppWindow.Closing += (_, args) =>
        {
            if (!allowClose)
            {
                args.Cancel = true;
                Hide();
            }
        };
        Activated += (_, args) =>
        {
            if (isVisible && args.WindowActivationState == WindowActivationState.Deactivated)
            {
                Hide();
            }
        };
    }

    private void UpdateWindowFrameTheme()
    {
        var useDarkMode = Root.ActualTheme == ElementTheme.Dark ? 1 : 0;
        DwmSetWindowAttribute(
            WinRT.Interop.WindowNative.GetWindowHandle(this),
            DwmUseImmersiveDarkModeAttribute,
            ref useDarkMode,
            Marshal.SizeOf<int>());
    }

    private void Root_ActualThemeChanged(FrameworkElement sender, object args)
    {
        UpdateWindowFrameTheme();
        Render();
    }

    private void Environment_Changed(object? sender, EventArgs args)
    {
        DispatcherQueue.TryEnqueue(Render);
    }

    private void Render()
    {
        if (Content is null)
        {
            return;
        }
        var localizer = environment.Localizer;
        var preferences = environment.Settings.Preferences;
        Root.Background = preferences.UsagePanelBackgroundStyle == UsagePanelBackgroundStyle.SolidAdaptive
            ? (Brush)Application.Current.Resources["SolidBackgroundFillColorBaseBrush"]
            : new SolidColorBrush(Microsoft.UI.Colors.Transparent);
        PanelTitle.Text = localizer.Text("usagePanelTitle");
        AuthenticationCallout.Text = preferences.VisiblePanelProviders.All(provider =>
            environment.Snapshots.GetValueOrDefault(provider)?.AuthState == ProviderAuthState.SignedOut)
            ? localizer.Text("authenticateInSettings")
            : string.Empty;
        AuthenticationCallout.Visibility = string.IsNullOrEmpty(AuthenticationCallout.Text) ? Visibility.Collapsed : Visibility.Visible;

        ProviderCards.Children.Clear();
        foreach (var provider in preferences.VisiblePanelProviders.OrderBy(localizer.ProviderName, StringComparer.CurrentCulture))
        {
            ProviderCards.Children.Add(usageViews.CreateUsageCard(provider));
        }

        SettingsButton.Content = localizer.Text("openSettings");
        RefreshButtonText.Text = localizer.Text("refreshNow");
        var isRefreshing = environment.IsRefreshing;
        RefreshButton.IsEnabled = !isRefreshing;
        RefreshIcon.Visibility = isRefreshing ? Visibility.Collapsed : Visibility.Visible;
        RefreshProgress.Visibility = isRefreshing ? Visibility.Visible : Visibility.Collapsed;
        RefreshProgress.IsActive = isRefreshing;
        RenderLastUpdate();
    }

    private void RenderLastUpdate()
    {
        var localizer = environment.Localizer;
        var latest = environment.Snapshots.Values.Select(snapshot => snapshot.FetchedAtUtc).Where(value => value is not null).Max();
        if (latest is null)
        {
            LastUpdateText.Text = $"{localizer.Text("lastUpdate")}: {localizer.Text("notConfigured")}";
            LastUpdateText.Foreground = (Brush)Application.Current.Resources["TextFillColorPrimaryBrush"];
            return;
        }
        var elapsed = DateTimeOffset.UtcNow - latest.Value;
        var isStale = elapsed >= environment.Settings.StalenessThreshold;
        var relative = elapsed.TotalMinutes switch
        {
            < 1 => localizer.Text("timeJustNow"),
            < 60 => localizer.Format("timeMinutesAgoFormat", Math.Max(1, (int)elapsed.TotalMinutes)),
            _ => localizer.Format("timeHoursAgoFormat", Math.Max(1, (int)elapsed.TotalHours)),
        };
        LastUpdateText.Text = $"{localizer.Text("lastUpdate")}: {relative}";
        LastUpdateText.Foreground = (Brush)Application.Current.Resources[
            isStale ? "SystemFillColorCriticalBrush" : "TextFillColorPrimaryBrush"];
        LastUpdateText.FontWeight = isStale
            ? Microsoft.UI.Text.FontWeights.SemiBold
            : Microsoft.UI.Text.FontWeights.Normal;
    }

    private void SettingsButton_Click(object sender, RoutedEventArgs args)
    {
        Hide();
        OpenSettingsRequested?.Invoke(this, EventArgs.Empty);
    }

    private async void RefreshButton_Click(object sender, RoutedEventArgs args)
    {
        await environment.RefreshAsync();
    }

    [DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(nint windowHandle);

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(nint windowHandle, int attribute, ref int value, int valueSize);
}
