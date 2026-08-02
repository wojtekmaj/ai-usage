# Test Strategy

## Overview

The automated suites live in `core/ai-usage-core` and `Tests/AiUsageAppTests`. The shared core uses Rust's built-in test harness; the macOS shell uses Swift Testing (`import Testing` with `@Test`). Windows builds are compiled natively on ARM64 and x64 CI runners.

The test target focuses on deterministic domain logic rather than UI automation. The highest-value coverage today is around parsers, scheduling logic, and formatting helpers, because those areas are both easy to regress and easy to exercise without network calls.

## How To Run Tests

From the package root:

```bash
cargo test --workspace
swift test
```

On Windows ARM64:

```powershell
cargo +stable-aarch64-pc-windows-gnullvm test --workspace
& 'C:\Program Files\dotnet\dotnet.exe' build apps\windows\AiUsage.Windows\AiUsage.Windows.csproj -p:Platform=ARM64
```

On Windows x64, use the `stable-x86_64-pc-windows-gnullvm` toolchain and `-p:Platform=x64` instead.

Run tests before shipping parser, scheduling, persistence-format, or provider URL changes.

## What The Current Suite Covers

### Parsing

The Rust suite is the canonical parser coverage for Codex, Claude, and the supported Copilot payload shapes. The Swift parser tests remain useful compatibility coverage for the native macOS fallback.

- `CodexHTMLParserTests`
  verifies direct Codex API payload parsing for the standard and GPT-5.3-Codex-Spark windows, credits, and available limit resets.
- `CodexLocalAuthTests`
  verifies local Codex auth parsing from `auth.json`.
- `ClaudeLocalAuthTests`
  verifies local Claude Code auth parsing from OAuth credential payloads and config-directory resolution.
- `ClaudeUsageParserTests`
  verifies Claude OAuth usage parsing for 5-hour and 7-day windows.
- `CopilotUsageParserTests`
  verifies multiple GitHub Copilot API payload shapes, including direct quota snapshots and fallback monthly quota fields.

These tests are the main guardrail against upstream response-shape drift.

### Scheduling And Thresholds

- `ScheduleEvaluatorTests`
  verifies pace assessment states, ahead-alert re-arming behavior, and unsupported alert combinations.
- `RemainingUsageBarThresholdTests`
  verifies the warning and critical bands used by the remaining-usage progress UI.

### Formatting And Small Domain Rules

- `ResetDateTextFormatterTests`
  verifies same-day versus later-day reset rendering.
- `ProviderIDTests`
  verifies that provider settings links still point to the expected destinations.
- `DisplayPreferencesTests`
  verifies that menu bar and panel providers stay visible by default unless explicitly hidden, and that display preferences decode safely.

## What Is Intentionally Not Covered By Unit Tests

The current suites do not try to unit-test:

- AppKit, SwiftUI, WinUI, and Shell_NotifyIcon window wiring
- interactive GitHub device-flow approval in the browser
- live network requests to ChatGPT, Anthropic, or GitHub
- platform notification delivery
- Keychain or Windows Credential Manager integration against the real vault

Those areas are integration-heavy and depend on system frameworks or external services. They are better validated with manual verification and targeted refactors if we later want more isolated seams.

## Manual Verification Checklist

Use this checklist after changing providers, auth flows, or visible UI behavior:

1. Launch the app and confirm the macOS status item or Windows provider tray icons render.
2. Left click opens only the compact usage panel, right click opens the action menu, and Settings opens a separate full window.
3. `Settings > Accounts` detects local Codex auth after signing in to the Codex desktop app or, for Codex CLI, after `codex login`.
4. `Settings > Accounts` detects local Claude Code auth after `claude` sign-in.
5. `Settings > Accounts` can start GitHub device flow and later clear the stored Copilot token.
6. `Settings > Display` changes language, refresh interval, panel background, bar colors, menu bar/system-tray providers, panel providers, optional Codex metrics, and the Claude and Codex summary metrics as expected.
7. Provider order is alphabetical in the menu bar, usage panel, and both provider visibility settings lists.
8. `Settings > Logs` can copy and clear logs.
9. Refresh succeeds or fails with a clear error message for each provider.
10. Reset times and percentages render sensibly in each supported language.
11. On Windows, close the settings window and confirm that the tray process remains alive; launch the executable again and confirm that no duplicate icons or process appear.
12. On Windows, verify the portable folder on a machine without Visual Studio and pin the desired provider icons from tray overflow next to the battery.
13. For trimmed Windows builds, change a preference, restart the app, and verify that settings, snapshots, logs, localization catalogs, and shared-core responses still serialize and deserialize correctly.

## When To Add Tests

Add or update tests when you change:

- provider parsing rules
- supported payload shapes
- schedule and alert thresholds
- user-facing date formatting behavior
- provider settings URLs
- domain logic that can be exercised without system UI

Prefer small, explicit fixtures over broad end-to-end tests. The current suite is intentionally readable and example-driven, which makes parser maintenance faster when upstream payloads evolve.
