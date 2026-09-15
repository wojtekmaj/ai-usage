using AiUsage.Windows.Domain;
using AiUsage.Windows.Services;
using AiUsage.Windows.UI;
using Microsoft.UI;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Media;
using System.Runtime.InteropServices;
using Windows.ApplicationModel.DataTransfer;
using Windows.Graphics;

namespace AiUsage.Windows;

public sealed partial class MainWindow : Window
{
    private readonly AppEnvironment environment;
    private readonly UsageViewFactory usageViews;
    private string currentSection = "accounts";
    private bool updatingUi;
    private bool allowClose;
    private bool hasInitialPlacement;
    private bool ignoreNextEnvironmentChange;
    private bool renderQueued;
    private AppLanguage? renderedLanguage;

    internal MainWindow(AppEnvironment environment)
    {
        this.environment = environment;
        usageViews = new UsageViewFactory(environment);
        InitializeComponent();
        Title = "AI Usage";
        SystemBackdrop = new MicaBackdrop();
        ConfigureWindow();
        environment.Changed += Environment_Changed;
        environment.Logs.Changed += Environment_Changed;
        Navigation.SelectedItem = AccountsItem;
        Render();
    }

    internal nint WindowHandle => WinRT.Interop.WindowNative.GetWindowHandle(this);

    internal void ShowSettings()
    {
        Navigation.SelectedItem = AccountsItem;
        ShowAndActivate();
    }

    internal void Quit()
    {
        allowClose = true;
        environment.Changed -= Environment_Changed;
        environment.Logs.Changed -= Environment_Changed;
        Close();
    }

    private void ConfigureWindow()
    {
        var windowId = Win32Interop.GetWindowIdFromWindow(WindowHandle);
        var appWindow = AppWindow.GetFromWindowId(windowId);
        var scale = GetDpiForWindow(WindowHandle) / 96d;
        if (appWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.PreferredMinimumWidth = (int)Math.Round(720 * scale);
            presenter.PreferredMinimumHeight = (int)Math.Round(600 * scale);
        }
        var iconPath = Path.Combine(AppContext.BaseDirectory, "Assets", "AppIcon.ico");
        if (File.Exists(iconPath))
        {
            appWindow.SetIcon(iconPath);
        }
        appWindow.Closing += (_, args) =>
        {
            if (!allowClose)
            {
                args.Cancel = true;
                appWindow.Hide();
            }
        };
    }

    private void ShowAndActivate()
    {
        Activate();
        var appWindow = AppWindow;
        if (!hasInitialPlacement)
        {
            var scale = GetDpiForWindow(WindowHandle) / 96d;
            var displayArea = DisplayArea.GetFromWindowId(appWindow.Id, DisplayAreaFallback.Nearest);
            if (displayArea is not null)
            {
                var workArea = displayArea.WorkArea;
                var width = Math.Min((int)Math.Round(1067 * scale), workArea.Width - 32);
                var height = Math.Min((int)Math.Round(667 * scale), workArea.Height - 32);
                appWindow.Resize(new SizeInt32(width, height));
                appWindow.Move(new PointInt32(
                    workArea.X + Math.Max(0, (workArea.Width - width) / 2),
                    workArea.Y + Math.Max(0, (workArea.Height - height) / 2)));
            }
            hasInitialPlacement = true;
        }
        appWindow.Show();
        Render();
    }

    private void Environment_Changed(object? sender, EventArgs args)
    {
        if (ignoreNextEnvironmentChange)
        {
            ignoreNextEnvironmentChange = false;
            return;
        }
        QueueRender();
    }

    private void Navigation_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.SelectedItemContainer?.Tag is string section)
        {
            currentSection = section;
            Render();
        }
    }

    private void LanguageCombo_SelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        if (!updatingUi && LanguageCombo.SelectedItem is ComboBoxItem { Tag: AppLanguage language })
        {
            UpdateSetting(preferences => preferences.Language = language, renderAfterUpdate: true);
        }
    }

    private void RefreshIntervalCombo_SelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        if (!updatingUi && RefreshIntervalCombo.SelectedItem is ComboBoxItem item && int.TryParse(item.Tag?.ToString(), out var minutes))
        {
            UpdateSetting(preferences => preferences.RefreshIntervalMinutes = minutes);
        }
    }

    private void PanelBackgroundCombo_SelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        if (!updatingUi && PanelBackgroundCombo.SelectedItem is ComboBoxItem { Tag: UsagePanelBackgroundStyle style })
        {
            UpdateSetting(preferences => preferences.UsagePanelBackgroundStyle = style);
        }
    }

    private void UsageBarColorCombo_SelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        if (!updatingUi && UsageBarColorCombo.SelectedItem is ComboBoxItem { Tag: UsageBarColorStyle style })
        {
            UpdateSetting(preferences => preferences.UsageBarColorStyle = style);
        }
    }

    private void NotificationToggle_Toggled(object sender, RoutedEventArgs args)
    {
        if (updatingUi)
        {
            return;
        }
        UpdateSetting(preferences =>
        {
            preferences.ShowAheadNotifications = AheadToggle.IsOn;
            preferences.ShowBehindNotifications = BehindToggle.IsOn;
            preferences.ShowCodexResetNotifications = CodexResetToggle.IsOn;
            preferences.ShowClaudeResetNotifications = ClaudeResetToggle.IsOn;
            preferences.ShowCodexScheduledResetNotifications = CodexScheduledResetToggle.IsOn;
            preferences.ShowClaudeScheduledResetNotifications = ClaudeScheduledResetToggle.IsOn;
        });
    }

    private void CopyLogsButton_Click(object sender, RoutedEventArgs args)
    {
        var package = new DataPackage();
        package.SetText(environment.Logs.ExportText);
        Clipboard.SetContent(package);
    }

    private void ClearLogsButton_Click(object sender, RoutedEventArgs args)
    {
        environment.Logs.Clear();
    }

    private async void CheckForUpdatesButton_Click(object sender, RoutedEventArgs args)
    {
        await environment.Updates.CheckManuallyAsync(environment.Localizer);
    }

    private void ViewReleaseButton_Click(object sender, RoutedEventArgs args)
    {
        if (environment.Updates.AvailableRelease is { } release)
        {
            environment.OpenUrl(release.PageUri.AbsoluteUri);
        }
    }

    private void AutomaticUpdateChecksToggle_Toggled(object sender, RoutedEventArgs args)
    {
        if (!updatingUi)
        {
            UpdateSetting(preferences => preferences.AutomaticallyCheckForUpdates = AutomaticUpdateChecksToggle.IsOn);
            if (AutomaticUpdateChecksToggle.IsOn)
            {
                _ = environment.Updates.CheckIfDueAsync(environment.Localizer, CancellationToken.None);
            }
        }
    }

    private void Render()
    {
        if (Content is null)
        {
            return;
        }
        updatingUi = true;
        try
        {
            RenderNavigation();
            RenderHeader();
            RenderAccounts();
            RenderDisplay();
            RenderNotifications();
            RenderLogs();
            RenderAbout();
        }
        finally
        {
            updatingUi = false;
        }
    }

    private void RenderNavigation()
    {
        var l = environment.Localizer;
        AccountsItem.Content = l.Text("settingsTabAccounts");
        DisplayItem.Content = l.Text("settingsTabDisplay");
        NotificationsItem.Content = l.Text("settingsTabNotifications");
        LogsItem.Content = l.Text("settingsTabLogs");
        AboutItem.Content = l.Text("settingsTabAbout");

        AccountsSection.Visibility = Visibility.Collapsed;
        DisplaySection.Visibility = Visibility.Collapsed;
        NotificationsSection.Visibility = Visibility.Collapsed;
        LogsSection.Visibility = Visibility.Collapsed;
        AboutSection.Visibility = Visibility.Collapsed;
        switch (currentSection)
        {
            case "accounts": AccountsSection.Visibility = Visibility.Visible; break;
            case "display": DisplaySection.Visibility = Visibility.Visible; break;
            case "notifications": NotificationsSection.Visibility = Visibility.Visible; break;
            case "logs": LogsSection.Visibility = Visibility.Visible; break;
            case "about": AboutSection.Visibility = Visibility.Visible; break;
            default: AccountsSection.Visibility = Visibility.Visible; break;
        }
    }

    private void RenderHeader()
    {
        var l = environment.Localizer;
        PageTitle.Text = currentSection switch
        {
            "accounts" => l.Text("settingsTabAccounts"),
            "display" => l.Text("settingsTabDisplay"),
            "notifications" => l.Text("settingsTabNotifications"),
            "logs" => l.Text("settingsTabLogs"),
            "about" => l.Text("settingsTabAbout"),
            _ => l.Text("settingsTabAccounts"),
        };
    }

    private void RenderAccounts()
    {
        AccountCards.Children.Clear();
        foreach (var provider in Enum.GetValues<ProviderId>().OrderBy(environment.Localizer.ProviderName, StringComparer.CurrentCulture))
        {
            AccountCards.Children.Add(CreateAccountCard(provider));
        }
    }

    private UIElement CreateAccountCard(ProviderId provider)
    {
        var l = environment.Localizer;
        var snapshot = environment.Snapshots.GetValueOrDefault(provider);
        var stack = new StackPanel { Spacing = 8 };
        stack.Children.Add(usageViews.CreateProviderHeader(provider, snapshot, includeExternalLink: false));
        if (provider == ProviderId.Claude && (snapshot?.RequiresClaudeSignIn != false || environment.IsReconnectingClaude || environment.ClaudeSignInError is not null))
        {
            stack.Children.Add(usageViews.CreateClaudeConnection());

            return Card(stack);
        }

        stack.Children.Add(new TextBlock
        {
            Text = provider switch
            {
                ProviderId.Codex => l.Text(snapshot?.AuthState == ProviderAuthState.SignedOut ? "codexSessionHelp" : "codexCliConnected"),
                ProviderId.Claude => l.Text("claudeCliConnected"),
                _ => l.Text(environment.HasCopilotToken() ? "copilotConnectedHelp" : "copilotPlanHelp"),
            },
            TextWrapping = TextWrapping.Wrap,
            Style = (Style)Application.Current.Resources["CaptionTextBlockStyle"],
            Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
        });
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        if (provider == ProviderId.Copilot)
        {
            var connected = environment.HasCopilotToken();
            var button = new Button { Content = l.Text(connected ? "signOut" : "signInToGitHubCopilot") };
            button.Click += async (_, _) =>
            {
                if (connected) await environment.SignOutFromCopilotAsync();
                else await environment.SignInToCopilotAsync();
            };
            buttons.Children.Add(button);
            if (environment.PendingCopilotDeviceCode is { } code)
            {
                stack.Children.Add(new InfoBar
                {
                    IsOpen = true,
                    Severity = InfoBarSeverity.Informational,
                    Title = l.Format("copilotDeviceFlowWaiting", code.UserCode),
                    Message = code.VerificationUri,
                });
            }
        }
        else
        {
            var reload = new Button { Content = l.Text("reload") };
            reload.Click += async (_, _) => await environment.RefreshAsync();
            buttons.Children.Add(reload);
        }
        var usage = new Button { Content = l.Text("openSettings") };
        usage.Click += (_, _) => environment.OpenProviderSettings(provider);
        buttons.Children.Add(usage);
        stack.Children.Add(buttons);
        return Card(stack);
    }

    private void RenderDisplay()
    {
        var l = environment.Localizer;
        var preferences = environment.Settings.Preferences;
        var languageChanged = renderedLanguage != preferences.Language;
        GeneralHeading.Text = l.Text("generalSection");
        LanguageLabel.Text = l.Text("language");
        RefreshIntervalLabel.Text = l.Text("refreshInterval");
        PanelBackgroundLabel.Text = l.Text("usagePanelBackground");
        UsageBarColorLabel.Text = l.Text("usageBarColors");
        TrayHeading.Text = l.Text("windowsSystemTraySection");
        PanelHeading.Text = l.Text("mainPanelSection");

        if (LanguageCombo.Items.Count == 0)
        {
            foreach (var language in Enum.GetValues<AppLanguage>())
            {
                LanguageCombo.Items.Add(new ComboBoxItem { Tag = language });
            }
        }
        foreach (var item in LanguageCombo.Items.Cast<ComboBoxItem>())
        {
            item.Content = l.LanguageDisplayName((AppLanguage)item.Tag);
        }
        LanguageCombo.SelectedItem = LanguageCombo.Items.Cast<ComboBoxItem>().First(item => Equals(item.Tag, preferences.Language));
        RefreshIntervalCombo.SelectedItem = RefreshIntervalCombo.Items.Cast<ComboBoxItem>()
            .First(item => item.Tag?.ToString() == preferences.RefreshIntervalMinutes.ToString());
        if (PanelBackgroundCombo.Items.Count == 0)
        {
            PanelBackgroundCombo.Items.Add(new ComboBoxItem { Tag = UsagePanelBackgroundStyle.RegularMaterial });
            PanelBackgroundCombo.Items.Add(new ComboBoxItem { Tag = UsagePanelBackgroundStyle.SolidAdaptive });
        }
        foreach (var item in PanelBackgroundCombo.Items.Cast<ComboBoxItem>())
        {
            item.Content = (UsagePanelBackgroundStyle)item.Tag == UsagePanelBackgroundStyle.RegularMaterial
                ? l.Text("usagePanelBackgroundRegularMaterial")
                : l.Text("usagePanelBackgroundSolidAdaptive");
        }
        if (languageChanged)
        {
            PanelBackgroundCombo.SelectedItem = null;
        }
        PanelBackgroundCombo.SelectedItem = PanelBackgroundCombo.Items.Cast<ComboBoxItem>()
            .First(item => Equals(item.Tag, preferences.UsagePanelBackgroundStyle));
        if (UsageBarColorCombo.Items.Count == 0)
        {
            UsageBarColorCombo.Items.Add(new ComboBoxItem { Tag = UsageBarColorStyle.DefaultColors });
            UsageBarColorCombo.Items.Add(new ComboBoxItem { Tag = UsageBarColorStyle.SystemAccent });
        }
        foreach (var item in UsageBarColorCombo.Items.Cast<ComboBoxItem>())
        {
            item.Content = (UsageBarColorStyle)item.Tag == UsageBarColorStyle.DefaultColors
                ? l.Text("usageBarColorsDefault")
                : l.Text("usageBarColorsSystemAccent");
        }
        if (languageChanged)
        {
            UsageBarColorCombo.SelectedItem = null;
        }
        UsageBarColorCombo.SelectedItem = UsageBarColorCombo.Items.Cast<ComboBoxItem>()
            .First(item => Equals(item.Tag, preferences.UsageBarColorStyle));
        renderedLanguage = preferences.Language;

        TrayProviderSettings.Children.Clear();
        PanelProviderSettings.Children.Clear();
        foreach (var provider in Enum.GetValues<ProviderId>().OrderBy(l.ProviderName, StringComparer.CurrentCulture))
        {
            TrayProviderSettings.Children.Add(CreateProviderVisibilityCard(provider, true));
            PanelProviderSettings.Children.Add(CreateProviderVisibilityCard(provider, false));
        }
    }

    private UIElement CreateProviderVisibilityCard(ProviderId provider, bool tray)
    {
        var l = environment.Localizer;
        var preferences = environment.Settings.Preferences;
        var visibleSet = tray ? preferences.VisibleProviders : preferences.VisiblePanelProviders;
        var stack = new StackPanel();
        var enabled = new ToggleSwitch
        {
            IsOn = visibleSet.Contains(provider),
            OffContent = "",
            OnContent = "",
            MinWidth = 0,
        };
        enabled.Toggled += (_, _) =>
        {
            if (updatingUi) return;

            UpdateSetting(updated =>
            {
                var set = tray ? updated.VisibleProviders : updated.VisiblePanelProviders;

                if (enabled.IsOn) set.Add(provider);
                else if (set.Count > 1) set.Remove(provider);
            }, renderAfterUpdate: true);
        };
        stack.Children.Add(CreateSettingsRow(l.ProviderName(provider), enabled, provider));

        if (tray && provider is ProviderId.Codex or ProviderId.Claude)
        {
            var combo = new ComboBox { IsEnabled = visibleSet.Contains(provider) };
            combo.Items.Add(new ComboBoxItem { Content = l.Text("menuBarMetricWeekly"), Tag = MenuBarMetric.Weekly });
            combo.Items.Add(new ComboBoxItem { Content = l.Text("menuBarMetricFiveHour"), Tag = MenuBarMetric.FiveHour });
            var selected = provider == ProviderId.Codex ? preferences.CodexMenuBarMetric : preferences.ClaudeMenuBarMetric;
            combo.SelectedItem = combo.Items.Cast<ComboBoxItem>().First(item => Equals(item.Tag, selected));
            combo.SelectionChanged += (_, _) =>
            {
                if (updatingUi || combo.SelectedItem is not ComboBoxItem { Tag: MenuBarMetric metric }) return;
                UpdateSetting(updated =>
                {
                    if (provider == ProviderId.Codex) updated.CodexMenuBarMetric = metric;
                    else updated.ClaudeMenuBarMetric = metric;
                });
            };
            stack.Children.Add(CreateSettingsRow(l.Text("percentageShown"), combo));
        }

        if (provider == ProviderId.Copilot)
        {
            var unit = environment.Snapshots.GetValueOrDefault(provider)?.Metric(UsageMetricKind.CopilotMonthly)?.Unit
                ?? MetricUnit.Credits;
            var combo = new ComboBox
            {
                IsEnabled = visibleSet.Contains(provider),
            };

            combo.Items.Add(new ComboBoxItem
            {
                Content = l.Text("menuBarValuePercentage"),
                Tag = CopilotDisplayValue.Percentage,
            });
            combo.Items.Add(new ComboBoxItem
            {
                Content = l.Text(unit == MetricUnit.Requests
                    ? "menuBarValueRemainingPremiumRequests"
                    : "menuBarValueRemainingAICredits"),
                Tag = CopilotDisplayValue.RemainingValue,
            });
            combo.Items.Add(new ComboBoxItem
            {
                Content = l.Text("menuBarValueRemainingDollars"),
                Tag = CopilotDisplayValue.RemainingDollars,
            });
            var selected = tray ? preferences.CopilotMenuBarValue : preferences.CopilotPanelValue;
            combo.SelectedItem = combo.Items.Cast<ComboBoxItem>()
                .First(item => Equals(item.Tag, selected));
            combo.SelectionChanged += (_, _) =>
            {
                if (updatingUi || combo.SelectedItem is not ComboBoxItem { Tag: CopilotDisplayValue value }) return;

                UpdateSetting(updated =>
                {
                    if (tray) updated.CopilotMenuBarValue = value;
                    else updated.CopilotPanelValue = value;
                });
            };
            stack.Children.Add(CreateSettingsRow(l.Text("valueShown"), combo));
        }

        if (!tray && provider == ProviderId.Codex)
        {
            stack.Children.Add(CreateOptionalVisibilityRow(
                l.Text("showCodexCredits"),
                preferences.CodexCreditsVisibility,
                value => UpdateSetting(updated => updated.CodexCreditsVisibility = value),
                visibleSet.Contains(provider)));
            stack.Children.Add(CreateOptionalVisibilityRow(
                l.Text("showCodexLimitResets"),
                preferences.CodexLimitResetsVisibility,
                value => UpdateSetting(updated => updated.CodexLimitResetsVisibility = value),
                visibleSet.Contains(provider)));
            var unavailableLimits = new ToggleSwitch
            {
                IsEnabled = visibleSet.Contains(provider),
                OffContent = "",
                OnContent = "",
                MinWidth = 0,
                IsOn = preferences.HideUnavailableCodexUsageLimits,
            };
            unavailableLimits.Toggled += (_, _) =>
            {
                if (!updatingUi) UpdateSetting(updated => updated.HideUnavailableCodexUsageLimits = unavailableLimits.IsOn);
            };
            stack.Children.Add(CreateSettingsRow(l.Text("hideUnavailableCodexUsageLimits"), unavailableLimits));

            var spark = new ToggleSwitch
            {
                IsOn = preferences.ShowCodexSparkUsage,
                IsEnabled = visibleSet.Contains(provider),
                OffContent = "",
                OnContent = "",
                MinWidth = 0,
            };
            spark.Toggled += (_, _) =>
            {
                if (!updatingUi) UpdateSetting(updated => updated.ShowCodexSparkUsage = spark.IsOn);
            };
            stack.Children.Add(CreateSettingsRow(l.Text("showCodexSparkUsage"), spark));
        }

        for (var index = stack.Children.Count - 1; index > 0; index--)
        {
            stack.Children.Insert(index, new Border
            {
                Style = (Style)Application.Current.Resources["SettingsRowDividerStyle"],
            });
        }

        return new Border
        {
            Style = (Style)Application.Current.Resources["SettingsGroupCardStyle"],
            Child = stack,
        };
    }

    private Grid CreateOptionalVisibilityRow(string title, OptionalMetricVisibility selected, Action<OptionalMetricVisibility> update, bool isEnabled)
    {
        var l = environment.Localizer;
        var combo = new ComboBox { IsEnabled = isEnabled };

        foreach (var value in Enum.GetValues<OptionalMetricVisibility>())
        {
            combo.Items.Add(new ComboBoxItem
            {
                Content = l.Text(value switch
                {
                    OptionalMetricVisibility.Always => "optionalMetricAlways",
                    OptionalMetricVisibility.OnlyWhenAboveZero => "optionalMetricOnlyWhenAboveZero",
                    _ => "optionalMetricNever",
                }),
                Tag = value,
            });
        }
        combo.SelectedItem = combo.Items.Cast<ComboBoxItem>().First(item => Equals(item.Tag, selected));
        combo.SelectionChanged += (_, _) =>
        {
            if (!updatingUi && combo.SelectedItem is ComboBoxItem { Tag: OptionalMetricVisibility value }) update(value);
        };

        return CreateSettingsRow(title, combo);
    }

    private static Grid CreateSettingsRow(string title, FrameworkElement control, ProviderId? provider = null)
    {
        var row = new Grid { Style = (Style)Application.Current.Resources["SettingsRowStyle"] };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var label = new TextBlock
        {
            Text = title,
            VerticalAlignment = VerticalAlignment.Center,
            TextWrapping = TextWrapping.Wrap,
        };

        if (provider is ProviderId providerId)
        {
            var header = new Grid { ColumnSpacing = 12, VerticalAlignment = VerticalAlignment.Center };
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            header.Children.Add(UsageViewFactory.CreateProviderIcon(providerId, 28));
            Grid.SetColumn(label, 1);
            header.Children.Add(label);
            row.Children.Add(header);
            row.MinHeight = 64;
        }
        else
        {
            row.Children.Add(label);
        }

        if (control is ToggleSwitch toggle)
        {
            toggle.Style = (Style)Application.Current.Resources["SettingsRowToggleStyle"];
        }

        control.HorizontalAlignment = HorizontalAlignment.Right;
        control.VerticalAlignment = VerticalAlignment.Center;
        AutomationProperties.SetName(control, title);
        Grid.SetColumn(control, 1);
        row.Children.Add(control);

        return row;
    }

    private void RenderNotifications()
    {
        var l = environment.Localizer;
        var preferences = environment.Settings.Preferences;
        UsageNotificationsHeading.Text = l.Text("usageNotificationsSection");
        ResetNotificationsHeading.Text = l.Text("earlyResetNotificationsSection");
        ScheduledResetNotificationsHeading.Text = l.Text("scheduledResetNotificationsSection");
        SetToggle(AheadToggle, AheadTitle, AheadDescription, "notificationsAhead", "notificationsAheadDescription", preferences.ShowAheadNotifications);
        SetToggle(BehindToggle, BehindTitle, BehindDescription, "notificationsBehind", "notificationsBehindDescription", preferences.ShowBehindNotifications);
        SetToggle(CodexResetToggle, CodexResetTitle, CodexResetDescription, "notificationsCodexReset", "notificationsCodexResetDescription", preferences.ShowCodexResetNotifications);
        SetToggle(ClaudeResetToggle, ClaudeResetTitle, ClaudeResetDescription, "notificationsClaudeReset", "notificationsClaudeResetDescription", preferences.ShowClaudeResetNotifications);
        SetToggle(CodexScheduledResetToggle, CodexScheduledResetTitle, CodexScheduledResetDescription, "notificationsCodexScheduledReset", "notificationsCodexScheduledResetDescription", preferences.ShowCodexScheduledResetNotifications);
        SetToggle(ClaudeScheduledResetToggle, ClaudeScheduledResetTitle, ClaudeScheduledResetDescription, "notificationsClaudeScheduledReset", "notificationsClaudeScheduledResetDescription", preferences.ShowClaudeScheduledResetNotifications);
    }

    private void SetToggle(ToggleSwitch toggle, TextBlock title, TextBlock description, string titleKey, string descriptionKey, bool value)
    {
        title.Text = environment.Localizer.Text(titleKey);
        description.Text = environment.Localizer.Text(descriptionKey);
        toggle.IsOn = value;
    }

    private void RenderLogs()
    {
        var l = environment.Localizer;
        LogsList.ItemsSource = environment.Logs.Entries
            .Reverse()
            .Select(entry => new LogDisplayEntry(
                $"{entry.TimestampUtc.ToLocalTime().ToString("g", l.Culture)} • {entry.Level.ToString().ToUpperInvariant()} • {entry.Category}{Environment.NewLine}{entry.Message}"))
            .ToArray();
        CopyLogsButton.Content = l.Text("copyLogs");
        ClearLogsButton.Content = l.Text("clearLogs");
    }

    private void RenderAbout()
    {
        var l = environment.Localizer;
        AppNameText.Text = l.Text("menuBarAppName");
        VersionText.Text = $"{l.Text("appVersion")} {environment.Updates.CurrentVersion}";
        CheckForUpdatesButton.Content = l.Text("checkForUpdates");
        CheckForUpdatesButton.IsEnabled = environment.Updates.Status != UpdateCheckStatus.Checking;
        ViewReleaseButton.Content = l.Text("viewRelease");
        ViewReleaseButton.Visibility = environment.Updates.Status == UpdateCheckStatus.Available
            ? Visibility.Visible
            : Visibility.Collapsed;
        UpdateStatusText.Text = environment.Updates.Status switch
        {
            UpdateCheckStatus.Checking => l.Text("checkingForUpdates"),
            UpdateCheckStatus.UpToDate => l.Text("updateUpToDate"),
            UpdateCheckStatus.Available when environment.Updates.AvailableRelease is { } release => l.Format("updateAvailableFormat", release.Version),
            UpdateCheckStatus.Failed => l.Text("updateCheckFailed"),
            _ => string.Empty,
        };
        UpdateStatusText.Visibility = string.IsNullOrEmpty(UpdateStatusText.Text) ? Visibility.Collapsed : Visibility.Visible;
        AutomaticUpdateChecksToggle.Header = l.Text("automaticallyCheckForUpdates");
        AutomaticUpdateChecksToggle.IsOn = environment.Settings.Preferences.AutomaticallyCheckForUpdates;
        AutomaticUpdateChecksDescription.Text = l.Text("automaticallyCheckForUpdatesDescription");
        ProjectHeading.Text = l.Text("projectSection");
        RepositoryButton.Content = l.Text("projectRepository");
        SponsorButton.Content = l.Text("sponsor");
        ReportIssueButton.Content = l.Text("reportIssue");
        LegalHeading.Text = l.Text("legalSection");
        LegalText.Text = l.Text("logoDisclaimer");
    }

    private static Border Card(UIElement content) => new()
    {
        Style = (Style)Application.Current.Resources["SettingsCardStyle"],
        Child = content,
    };

    private void UpdateSetting(Action<DisplayPreferences> update, bool renderAfterUpdate = false)
    {
        ignoreNextEnvironmentChange = true;
        try
        {
            environment.Settings.Update(update);
        }
        finally
        {
            ignoreNextEnvironmentChange = false;
        }
        if (renderAfterUpdate)
        {
            QueueRender();
        }
    }

    private void QueueRender()
    {
        if (renderQueued)
        {
            return;
        }
        renderQueued = true;
        if (!DispatcherQueue.TryEnqueue(DispatcherQueuePriority.Low, () =>
        {
            renderQueued = false;
            Render();
        }))
        {
            renderQueued = false;
        }
    }

    [DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(nint windowHandle);

}
