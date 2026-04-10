# Test Strategy

## Overview

The automated suite currently lives in `Tests/AiUsageAppTests` and uses Swift Testing (`import Testing` with `@Test`).

The test target focuses on deterministic domain logic rather than UI automation. The highest-value coverage today is around parsers, scheduling logic, and formatting helpers, because those areas are both easy to regress and easy to exercise without network calls.

## How To Run Tests

From the package root:

```bash
swift test
```

Run tests before shipping parser, scheduling, persistence-format, or provider URL changes.

## What The Current Suite Covers

### Parsing

- `CodexHTMLParserTests`
  verifies direct Codex API payload parsing for 5-hour, weekly, and credits metrics.
- `CodexLocalAuthTests`
  verifies local Codex CLI auth parsing from `auth.json`.
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
  verifies that providers stay visible by default unless explicitly hidden, and that Claude-specific display preferences decode safely.

## What Is Intentionally Not Covered By Unit Tests

The current suite does not try to unit-test:

- AppKit and SwiftUI window wiring
- interactive GitHub device-flow approval in the browser
- live network requests to ChatGPT, Anthropic, or GitHub
- macOS notification delivery
- Keychain integration against the real system Keychain

Those areas are integration-heavy and depend on system frameworks or external services. They are better validated with manual verification and targeted refactors if we later want more isolated seams.

## Manual Verification Checklist

Use this checklist after changing providers, auth flows, or visible UI behavior:

1. Launch the app and confirm the status item renders.
2. Left click opens the usage panel and right click opens the action menu.
3. `Settings > Accounts` detects local Codex CLI auth after `codex login`.
4. `Settings > Accounts` detects local Claude Code auth after `claude` sign-in.
5. `Settings > Accounts` can start GitHub device flow and later clear the stored Copilot token.
6. `Settings > Display` changes language, refresh interval, visible providers, and the Claude and Codex menu bar metrics as expected.
7. Provider order is alphabetical in the menu bar, usage panel, and menu-bar icon settings list.
8. `Settings > Logs` can copy and clear logs.
9. Refresh succeeds or fails with a clear error message for each provider.
10. Reset times and percentages render sensibly in both English and Polish.

## When To Add Tests

Add or update tests when you change:

- provider parsing rules
- supported payload shapes
- schedule and alert thresholds
- user-facing date formatting behavior
- provider settings URLs
- domain logic that can be exercised without system UI

Prefer small, explicit fixtures over broad end-to-end tests. The current suite is intentionally readable and example-driven, which makes parser maintenance faster when upstream payloads evolve.
