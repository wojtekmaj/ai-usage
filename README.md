# AI Usage App

Native macOS menu bar app for tracking remaining Claude, Codex, and GitHub Copilot usage.

`AI Usage` is the user-facing app name. `AiUsageApp` is the Swift package, executable target, and Xcode scheme name.

<img src="screenshot-button.png" width="182" height="27" alt="Screenshot of the AI Usage App menu bar item showing Claude, Codex, and Copilot percentages" />

<img src="screenshot.png" width="492" height="885" alt="Screenshot of the AI Usage App popover showing Claude, Codex, and GitHub Copilot usage cards" />

## Features

- Native macOS status item with a left-click usage panel and right-click quick actions.
- Separate Claude, Codex, and GitHub Copilot providers behind a shared provider abstraction.
- Codex tracking for 5-hour usage, weekly usage, and credits.
- Claude tracking for 5-hour usage and 7-day usage.
- GitHub Copilot monthly quota tracking.
- Configurable refresh cadence, which providers appear in the menu bar, which providers appear in the usage panel, language, and which Claude and Codex percentages appear in the menu bar.
- Local notifications for ahead-of-schedule usage, behind-schedule usage, and early Codex resets.
- Keychain-backed credential storage plus persisted snapshots, preferences, and diagnostic logs.
- English and Polish UI support.
- Settings tabs for Accounts, Display, Notifications, Logs, and About.

## Requirements

- macOS 15 or newer

## Download And Install

Prebuilt DMG files are available on the GitHub [Releases](https://github.com/wojtekmaj/ai-usage/releases) page.

Typical install flow:

1. Download the latest DMG from GitHub Releases.
2. Open the DMG.
3. Drag `AI Usage.app` to `/Applications`.
4. Launch the app from Applications.

## Gatekeeper And First Launch

Current GitHub release builds are packaged as an unsigned, not notarized DMG. Because of that, macOS Gatekeeper may block the first launch of a downloaded copy even though the app bundle inside the DMG is ad hoc-signed.

If macOS says the app cannot be opened because the developer cannot be verified, use one of these options:

1. In Finder, open `/Applications`, Control-click `AI Usage.app`, choose `Open`, then confirm `Open` in the dialog.
2. Or remove the quarantine attribute in Terminal:

   ```bash
   xattr -dr com.apple.quarantine "/Applications/AI Usage.app"
   ```

After the first successful launch, later launches should work normally.

## Authentication

### Codex

1. Run `codex login` in Terminal.
2. Open or refresh `Settings > Accounts`.
3. The app will detect your local Codex CLI auth automatically.

### GitHub Copilot

1. Open `Settings > Accounts`.
2. Click `Sign in to GitHub`.
3. Your browser opens GitHub's device-flow page.
4. Enter the code shown by the app and finish the sign-in flow.

The app stores the resulting GitHub OAuth token in Keychain and uses it for Copilot usage requests.

### Claude

1. Run `claude` in Terminal and complete Claude Code sign-in.
2. Open or refresh `Settings > Accounts`.
3. The app will detect your local Claude Code auth automatically.

## Data Sources

- Codex uses the local Codex CLI auth stored in `~/.codex/auth.json` or `$CODEX_HOME/auth.json`, then fetches usage directly from the Codex usage API.
- Claude uses the local Claude Code OAuth auth from Keychain or `~/.claude/.credentials.json`, then fetches usage directly from Anthropic's OAuth usage API.
- GitHub Copilot uses GitHub OAuth device flow, stores the resulting GitHub token in Keychain, and fetches usage from GitHub's Copilot internal API.

## Notifications

- Ahead-of-schedule alerts fire when remaining usage is materially below the time-adjusted expected remaining amount.
- Behind-schedule alerts fire when remaining usage is materially above the expected remaining amount for supported windows.
- Codex early reset alerts fire when a Codex 5-hour or weekly reset appears to happen earlier than previously observed.

The alert evaluator uses hysteresis and re-arming so the app does not spam notifications when usage hovers near a threshold.

## Settings Overview

- `Accounts`: manage Claude, Codex, and GitHub Copilot authentication.
- `Display`: choose language, refresh interval, which providers appear in the menu bar, which providers appear in the usage panel, and the Claude and Codex menu bar percentages.
- `Notifications`: enable or disable pace and reset alerts.
- `Logs`: inspect, copy, and clear persisted diagnostic logs.
- `About`: show the current app version.

## Notes

- The menu bar shows one percentage per visible provider, ordered alphabetically.
- The usage panel shows cards only for the providers enabled in settings, ordered alphabetically.
- Codex credits are shown in the panel, but not in the menu bar summary.
- Providers are visible by default in both places unless they are explicitly hidden in settings.
- If a metric has no known reset timestamp, the panel omits the reset line instead of inventing one.
- Right-click the menu bar item for direct `Refresh`, `Settings`, and `Quit` actions.

## Docs

- See [CONTRIBUTING.md](CONTRIBUTING.md) for local development, testing, and packaging.
- See [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md) for the package layout and runtime design.
- See [Docs/TEST_STRATEGY.md](Docs/TEST_STRATEGY.md) for automated and manual verification guidance.
- See [Docs/RELEASING.md](Docs/RELEASING.md) for tag-driven release publishing.

## Legal

The OpenAI logo, Claude logo, and GitHub Copilot logo are used only to identify their respective services. All trademarks, service marks, and logos are the property of their respective owners. This project is independent and is not affiliated with, endorsed by, or sponsored by OpenAI, Anthropic, or GitHub.
