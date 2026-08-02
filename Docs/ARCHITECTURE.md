# Architecture

## Overview

AI Usage consists of independent native macOS and Windows 11 shells around a shared Rust data core and shared JSON localization catalogs. It tracks remaining usage for three providers:

- Codex
- Claude
- GitHub Copilot

The macOS app is SwiftUI/AppKit. The Windows app is WinUI 3 on the current stable Windows App SDK and .NET, with direct Win32 shell integration for notification-area icons. Each platform is packaged and distributed independently.

The portable Windows build references only the modular WinUI, Foundation, Interactive Experiences, and Runtime packages rather than the full Windows App SDK metapackage. It uses source-generated JSON metadata so the self-contained .NET application can be safely trimmed without removing persisted models or shared-core protocol types.

## Package Layout

```text
Sources/AiUsageApp/
  App/         App bootstrap, environment, status item, settings window
  Domain/      Shared models, localization, schedule evaluation, formatting
  Providers/   Provider protocol plus Claude, Codex, and Copilot integrations
  Services/    Keychain, persistence, notifications, logs
  UI/          SwiftUI views used in the popover and settings window
  Resources/   Provider icons and other bundled assets

apps/windows/AiUsage.Windows/
  Domain/      Windows domain models and preferences
  Interop/     Shell_NotifyIcon tray integration
  Services/    shared-core client, persistence, Credential Manager, notifications
  UI/          reusable WinUI usage-card construction

core/ai-usage-core/
  parsers/     provider payload and credential parsing
  providers/   provider HTTP/auth integrations
  schedule/    shared pace and alert evaluation
  protocol/    one-request JSON process protocol

shared/localization/
  Canonical catalogs for all seven supported languages

Tests/AiUsageAppTests/
  Parser, formatting, scheduling, and small domain-level tests
```

## Runtime Flow

1. The platform shell creates one application environment and one shared-core client.
2. `AppEnvironment.start()` creates the status item and settings window controllers.
3. The environment loads persisted snapshots and preferences, requests notification permission, and starts the refresh loop.
4. The refresh loop asks the bundled `ai-usage-core` helper for a fresh `ProviderSnapshot` per provider. The macOS app retains its native providers as a compatibility fallback while the shared helper is unavailable in a development checkout.
5. Updated snapshots are persisted, surfaced in the UI, and passed through the notification evaluator.

`AppEnvironment` is the hub for app state. It owns:

- current provider snapshots
- refresh state and refresh errors
- user preferences
- Keychain access
- notification processing
- diagnostic logging

The core is a short-lived helper rather than a background service. The UI sends one JSON request over standard input and receives one JSON response over standard output. This keeps crashes and credentials isolated, avoids a local port, and lets each platform retain its native secret store.

## UI Structure

### Menu bar item

`StatusItemController` renders a custom AppKit status item that shows one percentage per visible provider. The provider list comes from user preferences and is displayed alphabetically.

- Left click toggles the SwiftUI popover.
- Right click opens a context menu with `Refresh`, `Settings`, and `Quit`.

### Windows system tray

`TrayIconManager` uses `Shell_NotifyIcon` directly and creates one icon for every provider enabled in preferences. Left click toggles a transient, acrylic WinUI usage panel next to the notification area. Right click opens native `Refresh`, `Settings`, and `Quit` commands. The full settings window is separate from the quick panel.

### Popover

`UsagePanelView` on macOS and `UsageFlyoutWindow` on Windows are the read-only quick dashboards. They show cards for the providers enabled in display preferences:

- Claude 5-hour usage
- Claude 7-day usage
- Codex 5-hour usage
- Codex weekly usage
- Codex GPT-5.3-Codex-Spark 5-hour usage
- Codex GPT-5.3-Codex-Spark weekly usage
- Codex credits
- Codex available limit resets
- GitHub Copilot monthly quota

Each card renders:

- the current remaining value
- a remaining-usage progress bar
- a time-based comparison bar when that metric supports schedule evaluation
- the next reset time when it is known

### Settings window

The SwiftUI `SettingsView` and WinUI `MainWindow` are divided into five equivalent sections:

- `Accounts`
- `Display`
- `Notifications`
- `Logs`
- `About`

The settings window is hosted through AppKit so it behaves like a conventional macOS preferences window, while the contents remain SwiftUI.

## Provider Layer

The canonical parsing, HTTP, and schedule boundary lives in the Rust core. The macOS `UsageProvider` protocol remains as a native fallback and as the boundary for platform-specific credential management:

- `currentAuthState()`
- `refresh(now:)`
- `clearAuth()`

Each provider returns a `ProviderSnapshot` that includes:

- provider identity
- auth state
- fetch state
- fetched timestamp
- usage metrics
- error details
- source description

### Codex provider

`CodexProvider` uses the local Codex auth file created by the Codex desktop app or Codex CLI.

Refresh behavior:

1. Read `~/.codex/auth.json` or `$CODEX_HOME/auth.json`.
2. Refresh the OAuth token when the local auth state is stale.
3. Resolve the effective ChatGPT base URL from Codex config.
4. Fetch usage directly from the Codex API and parse the JSON response.

Codex currently exposes six metrics:

- 5-hour window
- weekly window
- GPT-5.3-Codex-Spark 5-hour window
- GPT-5.3-Codex-Spark weekly window
- credits balance
- available limit resets

### Claude provider

`ClaudeProvider` uses local Claude Code OAuth auth.

Refresh behavior:

1. Read Claude OAuth auth from Keychain or `~/.claude/.credentials.json`.
2. Validate that the token includes the scope required for usage requests.
3. Fetch usage from `https://api.anthropic.com/api/oauth/usage`.
4. Parse the returned payload into 5-hour and 7-day usage metrics.

Claude currently exposes two metrics:

- 5-hour window
- 7-day window

### GitHub Copilot provider

`CopilotProvider` uses GitHub OAuth device flow and stores the resulting GitHub token in Keychain.

Refresh behavior:

1. Start GitHub device flow from Settings when the user signs in.
2. Poll GitHub until the device-flow token is issued.
3. Fetch usage from `https://api.github.com/copilot_internal/user`.
4. Parse the returned payload into a single monthly quota metric.

## Persistence

### Secret storage

Secrets are stored in Keychain on macOS and Windows Credential Manager on Windows:

- Claude Code OAuth auth may be sourced from Keychain when available.
- GitHub Copilot OAuth token

### Non-secret state

macOS persists non-secret state in `UserDefaults`. Windows persists JSON under `%LocalAppData%\AI Usage`:

- `SettingsStore` stores `DisplayPreferences`
- `UsageStore` stores provider snapshots, alert state, and Codex reset markers
- `LogStore` stores up to 300 diagnostic entries

Menu bar and panel provider visibility are each persisted as opt-out lists, so providers remain visible by default when no explicit hide setting exists. Dates are encoded in ISO 8601 so stored state remains stable across launches.

## Notifications And Scheduling

`NotificationService` evaluates refreshed metrics and sends local notifications for:

- ahead-of-schedule usage
- behind-schedule usage
- early Codex resets

`ScheduleEvaluator` owns the pace logic. It uses per-metric support rules plus hysteresis and re-arming to reduce noisy repeat alerts.

Refresh cadence is preference-driven. `AppEnvironment` listens for preference changes and restarts the refresh loop whenever the interval changes.

## Localization

The canonical JSON catalogs under `shared/localization` support:

- English (`en_US`)
- Polish (`pl_PL`)
- Spanish (`es_ES`)
- German (`de_DE`)
- French (`fr_FR`)
- Japanese (`ja_JP`)
- Brazilian Portuguese (`pt_BR`)

Formatting helpers such as `ResetDateTextFormatter` use the selected locale for user-facing timestamps while persistence remains UTC-based.

## Extension Points

To add a new provider:

1. Add a new `ProviderID`.
2. Implement `UsageProvider`.
3. Define any new `UsageMetricKind` values.
4. Register the provider in `AppEnvironment.providers`.
5. Add localization strings, settings UI, icons, and panel cards as needed.

That separation keeps network and auth logic outside the UI and lets the app evolve provider-by-provider.
