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
  verifies both API-style payload parsing and HTML/text fallback parsing for Codex 5-hour, weekly, and credits metrics.
- `CopilotUsageParserTests`
  verifies multiple GitHub payload shapes plus HTML fallback parsing for Copilot quota data.

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

## What Is Intentionally Not Covered By Unit Tests

The current suite does not try to unit-test:

- AppKit and SwiftUI window wiring
- embedded web-view sign-in flows
- live network requests to ChatGPT or GitHub
- macOS notification delivery
- Keychain integration against the real system Keychain

Those areas are integration-heavy and depend on system frameworks or external services. They are better validated with manual verification and targeted refactors if we later want more isolated seams.

## Manual Verification Checklist

Use this checklist after changing providers, auth flows, or visible UI behavior:

1. Launch the app and confirm the status item renders.
2. Left click opens the usage panel and right click opens the action menu.
3. `Settings > Accounts` can still save and clear Codex auth.
4. `Settings > Accounts` can still save and clear GitHub token or GitHub session auth.
5. `Settings > Display` changes language, refresh interval, visible providers, and the Codex menu bar metric as expected.
6. `Settings > Logs` can copy and clear logs.
7. Refresh succeeds or fails with a clear error message for each provider.
8. Reset times and percentages render sensibly in both English and Polish.

## When To Add Tests

Add or update tests when you change:

- provider parsing rules
- supported payload shapes
- schedule and alert thresholds
- user-facing date formatting behavior
- provider settings URLs
- domain logic that can be exercised without system UI

Prefer small, explicit fixtures over broad end-to-end tests. The current suite is intentionally readable and example-driven, which makes parser maintenance faster when upstream payloads evolve.
