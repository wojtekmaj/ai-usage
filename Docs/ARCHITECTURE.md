# Architecture

## Overview

`AiUsageApp` is a Swift Package Manager macOS menu bar app. It tracks remaining usage for two providers:

- Codex
- GitHub Copilot

The package ships a single executable target, `AiUsageApp`, plus the `AiUsageAppTests` test target.

## Package Layout

```text
Sources/AiUsageApp/
  App/         App bootstrap, environment, status item, settings window
  Domain/      Shared models, localization, schedule evaluation, formatting
  Providers/   Provider protocol plus Codex and Copilot integrations
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

`StatusItemController` renders a custom AppKit status item that shows one percentage per visible provider. The provider list comes from user preferences.

- Left click toggles the SwiftUI popover.
- Right click opens a context menu with `Refresh`, `Settings`, and `Quit`.

### Popover

`UsagePanelView` is the main read-only dashboard. It shows:

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

`CodexProvider` uses a locally captured ChatGPT web session stored in Keychain.

Refresh behavior:

1. Rehydrate cookies plus saved local and session storage values.
2. Resolve request context from the ChatGPT session.
3. Try the usage API response first.
4. If that fails, render the usage page in WebKit and parse the HTML/text fallback.

Codex currently exposes three metrics:

- 5-hour window
- weekly window
- credits balance

### GitHub Copilot provider

`CopilotProvider` supports two auth methods:

- GitHub session cookies captured through the in-app sign-in flow
- a fine-grained personal access token stored in Keychain

Refresh behavior:

1. If a saved GitHub session exists, request the billing usage card JSON from the GitHub web UI.
2. If that path fails and a token exists, resolve the authenticated login and try the GitHub billing REST endpoints.
3. Parse the returned payload into a single monthly quota metric.

## Persistence

### Keychain

Secrets are stored in Keychain:

- Codex session payload
- GitHub session payload
- GitHub Copilot personal access token

### UserDefaults

Non-secret state is persisted in `UserDefaults`:

- `SettingsStore` stores `DisplayPreferences`
- `UsageStore` stores provider snapshots, alert state, and Codex reset markers
- `LogStore` stores up to 300 diagnostic entries

Dates are encoded in ISO 8601 so stored state remains stable across launches.

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
