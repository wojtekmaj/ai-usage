# AI Usage App

Native macOS menu bar app for tracking remaining Codex and GitHub Copilot usage.

`AI Usage` is the user-facing app name. `AiUsageApp` is the Swift package, executable target, and Xcode scheme name.

<img src="screenshot-button.png" width="122" height="27" alt="Screenshot of the AI Usage App menu bar item showing Codex and Copilot percentages" />

<img src="screenshot.png" width="492" height="637" alt="Screenshot of the AI Usage App popover showing Codex 5-hour usage, Codex weekly usage, Codex credits, and GitHub Copilot monthly quota" />

## Features

- Native macOS status item with a left-click usage panel and right-click quick actions.
- Separate Codex and GitHub Copilot providers behind a shared provider abstraction.
- Codex tracking for 5-hour usage, weekly usage, and credits.
- GitHub Copilot monthly quota tracking.
- Configurable refresh cadence, visible providers, language, and which Codex percentage appears in the menu bar.
- Local notifications for ahead-of-schedule usage, behind-schedule usage, and early Codex resets.
- Keychain-backed credential storage plus persisted snapshots, preferences, and diagnostic logs.
- English and Polish UI support.
- Settings tabs for Accounts, Display, Notifications, Logs, and About.

## Data Sources

- Codex uses a locally captured ChatGPT web session. The app prefers the ChatGPT usage API response and falls back to parsing a rendered WebKit page when needed.
- GitHub Copilot supports two auth paths:
  - a GitHub web session captured through the in-app sign-in flow
  - a fine-grained personal access token for GitHub billing REST API requests

When both GitHub auth methods are present, the app tries the captured web session first and then falls back to the token flow.

## Requirements

- macOS 15 or newer
- Xcode 16 or newer
- Swift 6 or newer

## Build, Test, And Run

### Xcode

1. Open the package root in Xcode.
2. Select the `AiUsageApp` scheme.
3. Run the app.

### SwiftPM

```bash
swift build
swift test
swift run AiUsageApp
```

### Standalone `.app` Bundle

```bash
./scripts/build-app.sh
open '.build/AI Usage.app'
```

The packaging script creates a lightweight menu bar app bundle with `LSUIElement=1`, so the app runs without a Dock icon.

### `.dmg` Bundle

```bash
./scripts/build-dmg.sh
open .build/AI-Usage-*.dmg
```

The DMG build intentionally uses the app's ad-hoc signature (no Developer ID signing/notarization) and clears quarantine attributes from staged files to keep local and CI-generated archives consistent.

## Authentication

### Codex

1. Open `Settings > Accounts`.
2. Click `Sign in to Codex`.
3. Sign in through the embedded ChatGPT web view.
4. Click `Save session`.

The saved Codex session includes cookies plus the local and session storage values needed for follow-up usage requests.

### GitHub Copilot

You can authenticate in either of these ways:

1. `Settings > Accounts > GitHub Copilot token`
   Paste a fine-grained personal access token with the billing or usage access needed by the GitHub billing endpoints, then save.
2. `Settings > Accounts > Sign in to GitHub`
   Sign in through the embedded GitHub web view and save the captured session cookies.

If every known user-level REST endpoint returns `404`, your Copilot usage is probably billed through an organization or enterprise instead of your personal account. In that case, the web-session path may still work if GitHub exposes your usage in the billing UI.

## Notifications

- Ahead-of-schedule alerts fire when remaining usage is materially below the time-adjusted expected remaining amount.
- Behind-schedule alerts fire when remaining usage is materially above the expected remaining amount for supported windows.
- Codex early reset alerts fire when a Codex 5-hour or weekly reset appears to happen earlier than previously observed.

The alert evaluator uses hysteresis and re-arming so the app does not spam notifications when usage hovers near a threshold.

## Settings Overview

- `Accounts`: manage Codex and GitHub Copilot authentication.
- `Display`: choose language, refresh interval, visible providers, and the Codex menu bar metric.
- `Notifications`: enable or disable pace and reset alerts.
- `Logs`: inspect, copy, and clear persisted diagnostic logs.
- `About`: show the current app version.

## Notes

- The menu bar shows one percentage per visible provider.
- Codex credits are shown in the panel, but not in the menu bar summary.
- If a metric has no known reset timestamp, the panel omits the reset line instead of inventing one.
- Right-click the menu bar item for direct `Refresh`, `Settings`, and `Quit` actions.

## Legal

The OpenAI logo and GitHub Copilot logo are used only to identify their respective services. All trademarks, service marks, and logos are the property of their respective owners. This project is independent and is not affiliated with, endorsed by, or sponsored by OpenAI or GitHub.

## Docs

- See `Docs/ARCHITECTURE.md` for the current package layout and runtime design.
- See `Docs/TEST_STRATEGY.md` for the current automated and manual testing strategy.
