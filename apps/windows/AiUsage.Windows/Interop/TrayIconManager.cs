using System.ComponentModel;
using System.Runtime.InteropServices;
using AiUsage.Windows.Domain;
using Microsoft.Win32;

namespace AiUsage.Windows.Interop;

internal sealed class TrayIconManager : IDisposable
{
    private const uint CallbackMessage = 0x8001;
    private const int GwlWndProc = -4;
    private const uint NimAdd = 0;
    private const uint NimModify = 1;
    private const uint NimDelete = 2;
    private const uint NimSetVersion = 4;
    private const uint NifMessage = 1;
    private const uint NifIcon = 2;
    private const uint NifTip = 4;
    private const uint NifInfo = 0x10;
    private const uint NifShowTip = 0x80;
    private const uint NiifInfo = 1;
    private const uint NiifRespectQuietTime = 0x80;
    private const uint NotifyIconVersion4 = 4;
    private const uint ImageIcon = 1;
    private const uint LrLoadFromFile = 0x10;
    private const uint LrDefaultSize = 0x40;
    private const uint WmContextMenu = 0x007B;
    private const uint WmSettingChange = 0x001A;
    private const uint NinSelect = 0x0400;
    private const uint NinKeySelect = 0x0401;
    private const uint MfString = 0;
    private const uint MfSeparator = 0x800;
    private const uint TpmRightButton = 0x0002;
    private const uint TpmReturnCommand = 0x0100;
    private const uint CommandRefresh = 100;
    private const uint CommandSettings = 101;
    private const uint CommandQuit = 102;

    private readonly nint windowHandle;
    private readonly WndProcDelegate windowProcedure;
    private readonly nint previousWindowProcedure;
    private readonly uint taskbarCreatedMessage;
    private readonly Dictionary<ProviderId, TrayIconState> icons = [];
    private string refreshText = "Refresh";
    private string settingsText = "Settings";
    private string quitText = "Quit";
    private string iconThemeSuffix = CurrentIconThemeSuffix();
    private bool disposed;

    public TrayIconManager(nint windowHandle)
    {
        this.windowHandle = windowHandle;
        windowProcedure = WindowProcedure;
        previousWindowProcedure = SetWindowLongPtr(windowHandle, GwlWndProc, Marshal.GetFunctionPointerForDelegate(windowProcedure));
        if (previousWindowProcedure == 0)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        taskbarCreatedMessage = RegisterWindowMessage("TaskbarCreated");
    }

    public event EventHandler<ProviderId>? PrimaryInvoked;

    public event EventHandler? RefreshInvoked;

    public event EventHandler? SettingsInvoked;

    public event EventHandler? QuitInvoked;

    public void ShowNotification(string title, string body)
    {
        if (disposed || icons.Count == 0)
        {
            return;
        }
        var data = icons.Values.First().Data;
        data.uFlags = NifInfo;
        data.szInfoTitle = Truncate(title, 63);
        data.szInfo = Truncate(body, 255);
        data.dwInfoFlags = NiifInfo | NiifRespectQuietTime;
        ShellNotifyIcon(NimModify, ref data);
    }

    public void Update(
        IEnumerable<ProviderId> visibleProviders,
        IReadOnlyDictionary<ProviderId, ProviderSnapshot> snapshots,
        DisplayPreferences preferences,
        Func<ProviderId, string> providerName,
        Func<string, string> text)
    {
        var visible = visibleProviders.ToHashSet();
        foreach (var provider in icons.Keys.Where(provider => !visible.Contains(provider)).ToArray())
        {
            Remove(provider);
        }

        foreach (var provider in visible.OrderBy(providerName, StringComparer.CurrentCulture))
        {
            var snapshot = snapshots.GetValueOrDefault(provider);
            var fraction = SummaryFraction(provider, snapshot, preferences);
            var status = snapshot?.FetchState switch
            {
                ProviderFetchState.Ok when fraction is not null => $"{Math.Round(fraction.Value * 100)}%",
                ProviderFetchState.MissingAuth => text("notConfigured"),
                ProviderFetchState.Failed => text("unavailable"),
                _ => text("unavailable"),
            };
            AddOrUpdate(provider, $"{providerName(provider)} — {status}");
        }
        refreshText = text("menuActionRefresh");
        settingsText = text("menuActionSettings");
        quitText = text("quitApp");
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }
        disposed = true;
        foreach (var provider in icons.Keys.ToArray())
        {
            Remove(provider);
        }
        SetWindowLongPtr(windowHandle, GwlWndProc, previousWindowProcedure);
    }

    private void AddOrUpdate(ProviderId provider, string tooltip)
    {
        if (icons.TryGetValue(provider, out var existing))
        {
            existing.Data.szTip = tooltip;
            if (!ShellNotifyIcon(NimModify, ref existing.Data))
            {
                Add(existing);
            }
            icons[provider] = existing;
            return;
        }

        var icon = LoadProviderIcon(provider);
        if (icon == 0)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), $"Unable to load the {provider} tray icon.");
        }
        var state = new TrayIconState(provider, icon, CreateData(provider, icon, tooltip));
        Add(state);
        icons.Add(provider, state);
    }

    private void Add(TrayIconState state)
    {
        if (!ShellNotifyIcon(NimAdd, ref state.Data))
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), $"Unable to add the {state.Provider} tray icon.");
        }
        var version = state.Data;
        version.uTimeoutOrVersion = NotifyIconVersion4;
        ShellNotifyIcon(NimSetVersion, ref version);
    }

    private void Remove(ProviderId provider)
    {
        if (!icons.Remove(provider, out var state))
        {
            return;
        }
        ShellNotifyIcon(NimDelete, ref state.Data);
        DestroyIcon(state.Icon);
    }

    private nint WindowProcedure(nint hwnd, uint message, nuint wParam, nint lParam)
    {
        if (message == taskbarCreatedMessage)
        {
            foreach (var state in icons.Values)
            {
                Add(state);
            }
            return 0;
        }

        if (message == WmSettingChange)
        {
            RefreshIconsForTheme();
        }

        if (message == CallbackMessage)
        {
            var eventMessage = (uint)((long)lParam & 0xFFFF);
            var iconId = (uint)(((long)lParam >> 16) & 0xFFFF);
            var provider = ProviderFromId(iconId);
            if (eventMessage is NinSelect or NinKeySelect)
            {
                PrimaryInvoked?.Invoke(this, provider);
                return 0;
            }
            if (eventMessage == WmContextMenu)
            {
                ShowContextMenu();
                return 0;
            }
        }
        return CallWindowProc(previousWindowProcedure, hwnd, message, wParam, lParam);
    }

    private nint LoadProviderIcon(ProviderId provider)
    {
        var iconPath = Path.Combine(
            AppContext.BaseDirectory,
            "Assets",
            "Providers",
            $"{provider.ToString().ToLowerInvariant()}-tray{iconThemeSuffix}.ico");
        return LoadImage(0, iconPath, ImageIcon, 0, 0, LrLoadFromFile | LrDefaultSize);
    }

    private void RefreshIconsForTheme()
    {
        var nextSuffix = CurrentIconThemeSuffix();
        if (nextSuffix == iconThemeSuffix)
        {
            return;
        }
        iconThemeSuffix = nextSuffix;

        foreach (var state in icons.Values)
        {
            var nextIcon = LoadProviderIcon(state.Provider);
            if (nextIcon == 0)
            {
                continue;
            }
            var previousIcon = state.Icon;
            state.Data.hIcon = nextIcon;
            if (ShellNotifyIcon(NimModify, ref state.Data))
            {
                state.Icon = nextIcon;
                DestroyIcon(previousIcon);
            }
            else
            {
                state.Data.hIcon = previousIcon;
                DestroyIcon(nextIcon);
            }
        }
    }

    private static string CurrentIconThemeSuffix()
    {
        try
        {
            var value = Registry.GetValue(
                @"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize",
                "SystemUsesLightTheme",
                1);
            return Convert.ToInt32(value) == 0 ? "-dark" : string.Empty;
        }
        catch
        {
            return string.Empty;
        }
    }

    private void ShowContextMenu()
    {
        var menu = CreatePopupMenu();
        if (menu == 0)
        {
            return;
        }
        try
        {
            AppendMenu(menu, MfString, CommandRefresh, refreshText);
            AppendMenu(menu, MfString, CommandSettings, settingsText);
            AppendMenu(menu, MfSeparator, 0, null);
            AppendMenu(menu, MfString, CommandQuit, quitText);
            GetCursorPos(out var cursor);
            SetForegroundWindow(windowHandle);
            var command = TrackPopupMenuEx(menu, TpmRightButton | TpmReturnCommand, cursor.X, cursor.Y, windowHandle, 0);
            switch (command)
            {
                case CommandRefresh:
                    RefreshInvoked?.Invoke(this, EventArgs.Empty);
                    break;
                case CommandSettings:
                    SettingsInvoked?.Invoke(this, EventArgs.Empty);
                    break;
                case CommandQuit:
                    QuitInvoked?.Invoke(this, EventArgs.Empty);
                    break;
            }
        }
        finally
        {
            DestroyMenu(menu);
        }
    }

    private NotifyIconData CreateData(ProviderId provider, nint icon, string tooltip) => new()
    {
        cbSize = (uint)Marshal.SizeOf<NotifyIconData>(),
        hWnd = windowHandle,
        uID = Id(provider),
        uFlags = NifMessage | NifIcon | NifTip | NifShowTip,
        uCallbackMessage = CallbackMessage,
        hIcon = icon,
        szTip = tooltip,
        szInfo = string.Empty,
        szInfoTitle = string.Empty,
    };

    private static uint Id(ProviderId provider) => provider switch
    {
        ProviderId.Claude => 1,
        ProviderId.Codex => 2,
        ProviderId.Copilot => 3,
        _ => 4,
    };

    private static ProviderId ProviderFromId(uint id) => id switch
    {
        1 => ProviderId.Claude,
        2 => ProviderId.Codex,
        3 => ProviderId.Copilot,
        _ => ProviderId.Codex,
    };

    private static double? SummaryFraction(ProviderId provider, ProviderSnapshot? snapshot, DisplayPreferences preferences)
    {
        if (snapshot is null)
        {
            return null;
        }
        var kind = provider switch
        {
            ProviderId.Claude when preferences.ClaudeMenuBarMetric == MenuBarMetric.FiveHour => UsageMetricKind.ClaudeFiveHour,
            ProviderId.Claude => UsageMetricKind.ClaudeWeekly,
            ProviderId.Codex when preferences.CodexMenuBarMetric == MenuBarMetric.FiveHour => UsageMetricKind.CodexFiveHour,
            ProviderId.Codex => UsageMetricKind.CodexWeekly,
            ProviderId.Copilot => UsageMetricKind.CopilotMonthly,
            _ => UsageMetricKind.CodexWeekly,
        };
        return snapshot.Metric(kind)?.RemainingFraction;
    }

    private static string Truncate(string text, int maxLength)
    {
        var clean = text.Replace('\0', ' ');
        return clean.Length <= maxLength ? clean : clean[..maxLength];
    }

    private sealed class TrayIconState(ProviderId provider, nint icon, NotifyIconData data)
    {
        public ProviderId Provider { get; } = provider;

        public nint Icon { get; set; } = icon;

        public NotifyIconData Data = data;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NotifyIconData
    {
        public uint cbSize;
        public nint hWnd;
        public uint uID;
        public uint uFlags;
        public uint uCallbackMessage;
        public nint hIcon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string szTip;
        public uint dwState;
        public uint dwStateMask;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string szInfo;
        public uint uTimeoutOrVersion;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string szInfoTitle;
        public uint dwInfoFlags;
        public Guid guidItem;
        public nint hBalloonIcon;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Point
    {
        public int X;
        public int Y;
    }

    private delegate nint WndProcDelegate(nint hwnd, uint message, nuint wParam, nint lParam);

    [DllImport("shell32.dll", EntryPoint = "Shell_NotifyIconW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ShellNotifyIcon(uint message, ref NotifyIconData data);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW", SetLastError = true)]
    private static extern nint SetWindowLongPtr(nint hwnd, int index, nint newLong);

    [DllImport("user32.dll", EntryPoint = "CallWindowProcW")]
    private static extern nint CallWindowProc(nint previous, nint hwnd, uint message, nuint wParam, nint lParam);

    [DllImport("user32.dll", EntryPoint = "RegisterWindowMessageW", CharSet = CharSet.Unicode)]
    private static extern uint RegisterWindowMessage(string message);

    [DllImport("user32.dll", EntryPoint = "LoadImageW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern nint LoadImage(nint instance, string name, uint type, int width, int height, uint load);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyIcon(nint icon);

    [DllImport("user32.dll")]
    private static extern nint CreatePopupMenu();

    [DllImport("user32.dll", EntryPoint = "AppendMenuW", CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AppendMenu(nint menu, uint flags, nuint item, string? text);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyMenu(nint menu);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetCursorPos(out Point point);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetForegroundWindow(nint hwnd);

    [DllImport("user32.dll", EntryPoint = "TrackPopupMenuEx")]
    private static extern uint TrackPopupMenuEx(nint menu, uint flags, int x, int y, nint hwnd, nint parameters);
}
