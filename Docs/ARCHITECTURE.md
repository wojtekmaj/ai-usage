# Architecture

## Overview

`AiUsageApp` is a Swift Package Manager macOS menu bar app. It tracks remaining usage for three providers:

- Codex
- Claude
- GitHub Copilot

The package ships a single executable target, `AiUsageApp`, plus the `AiUsageAppTests` test target.

## Package Layout

```text
Sources/AiUsageApp/
  App/         App bootstrap, environment, status item, settings window
  Domain/      Shared models, localization, schedule evaluation, formatting
  Providers/   Provider protocol plus Claude, Codex, and Copilot integrations
  Services/    Keychain, persistence, notifications, logs
  UI/          SwiftUI views used in the popover and settings window
  Resources/   Provider icons and other bundled assets

Tests/AiUsageAppTests/
  Parser, formatting, scheduling, and small domain-level tests
```

## Runtime Flow

1. `AiUsageApp` creates a single `AppEnvironment`.
2. `AppEnvironment.start()` creates the status item and settings window controllers.
3. The environment loads persisted snapshots and preferences, requests notification permission, and starts the refresh loop.
4. The refresh loop asks each `UsageProvider` for a fresh `ProviderSnapshot`.
5. Updated snapshots are persisted, surfaced in the UI, and passed through the notification evaluator.

`AppEnvironment` is the hub for app state. It owns:

- current provider snapshots
- refresh state and refresh errors
- user preferences
- Keychain access
- notification processing
- diagnostic logging

## UI Structure

### Menu bar item

`StatusItemController` renders a custom AppKit status item that shows one percentage per visible provider. The provider list comes from user preferences and is displayed alphabetically.

- Left click toggles the SwiftUI popover.
- Right click opens a context menu with `Refresh`, `Settings`, and `Quit`.

### Popover

`UsagePanelView` is the main read-only dashboard. It shows cards for the providers enabled in display preferences:

- Claude 5-hour usage
- Claude 7-day usage
- Codex 5-hour usage
- Codex weekly usage
- Codex credits
- GitHub Copilot monthly quota

Each card renders:

- the current remaining value
- a remaining-usage progress bar
- a time-based comparison bar when that metric supports schedule evaluation
- the next reset time when it is known

### Settings window

`SettingsView` is divided into five tabs:

- `Accounts`
- `Display`
- `Notifications`
- `Logs`
- `About`

The settings window is hosted through AppKit so it behaves like a conventional macOS preferences window, while the contents remain SwiftUI.

## Provider Layer

The provider boundary is the `UsageProvider` protocol:

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

`CodexProvider` uses the local Codex CLI auth file.

Refresh behavior:

1. Read `~/.codex/auth.json` or `$CODEX_HOME/auth.json`.
2. Refresh the OAuth token when the local auth state is stale.
3. Resolve the effective ChatGPT base URL from Codex config.
4. Fetch usage directly from the Codex API and parse the JSON response.

Codex currently exposes three metrics:

- 5-hour window
- weekly window
- credits balance

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

### Keychain

Secrets are stored in Keychain:

- Claude Code OAuth auth may be sourced from Keychain when available.
- GitHub Copilot OAuth token

### UserDefaults

Non-secret state is persisted in `UserDefaults`:

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

`Localizer` currently supports:

- English (`en_US`)
- Polish (`pl_PL`)

Formatting helpers such as `ResetDateTextFormatter` use the selected locale for user-facing timestamps while persistence remains UTC-based.

## Extension Points

To add a new provider:

1. Add a new `ProviderID`.
2. Implement `UsageProvider`.
3. Define any new `UsageMetricKind` values.
4. Register the provider in `AppEnvironment.providers`.
5. Add localization strings, settings UI, icons, and panel cards as needed.

That separation keeps network and auth logic outside the UI and lets the app evolve provider-by-provider.
