using AiUsage.Windows.Interop;
using AiUsage.Windows.Services;
using Microsoft.UI.Xaml;

namespace AiUsage.Windows;

public partial class App : Application
{
    private AppEnvironment? environment;
    private MainWindow? mainWindow;
    private UsageFlyoutWindow? usageFlyout;
    private TrayIconManager? trayIcons;

    public App()
    {
        InitializeComponent();
        UnhandledException += (_, args) =>
        {
            environment?.Logs.Append(Domain.AppLogLevel.Error, "application", args.Exception.Message);
        };
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        environment = new AppEnvironment();
        mainWindow = new MainWindow(environment);
        usageFlyout = new UsageFlyoutWindow(environment);
        usageFlyout.OpenSettingsRequested += (_, _) => mainWindow.ShowSettings();
        trayIcons = new TrayIconManager(mainWindow.WindowHandle);
        trayIcons.PrimaryInvoked += (_, _) => usageFlyout.Toggle();
        trayIcons.RefreshInvoked += async (_, _) => await environment.RefreshAsync();
        trayIcons.SettingsInvoked += (_, _) => mainWindow.ShowSettings();
        trayIcons.QuitInvoked += (_, _) => Quit();
        environment.Notifications.NotificationRequested += (title, body) =>
            mainWindow.DispatcherQueue.TryEnqueue(() => trayIcons?.ShowNotification(title, body));
        environment.Changed += (_, _) => mainWindow.DispatcherQueue.TryEnqueue(UpdateTrayIcons);
        environment.Localizer.Changed += (_, _) => mainWindow.DispatcherQueue.TryEnqueue(UpdateTrayIcons);
        UpdateTrayIcons();
        environment.Start();
        Program.DeliverPendingActivation(this);
#if DEBUG
        usageFlyout.ShowNearNotificationArea();
#endif
    }

    internal void HandleRedirectedActivation()
    {
        mainWindow?.DispatcherQueue.TryEnqueue(() => usageFlyout?.ShowNearNotificationArea());
    }

    private void UpdateTrayIcons()
    {
        if (environment is null || trayIcons is null)
        {
            return;
        }
        trayIcons.Update(
            environment.Settings.Preferences.VisibleProviders,
            environment.Snapshots,
            environment.Settings.Preferences,
            environment.Localizer.ProviderName,
            environment.Localizer.Text);
    }

    private void Quit()
    {
        trayIcons?.Dispose();
        trayIcons = null;
        environment?.Dispose();
        environment = null;
        usageFlyout?.Quit();
        usageFlyout = null;
        mainWindow?.Quit();
        mainWindow = null;
    }
}
