# Contributing

This document covers local development, testing, packaging, and the other repo-internal details that do not belong in the user-facing README.

## Requirements

- macOS 15 or newer
- Xcode 16 or newer
- Swift 6 or newer

## Getting Started

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

## Local Packaging

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

The DMG build intentionally stays unsigned and ad hoc-signs the finished app bundle before packaging.

User-facing first-launch and Gatekeeper guidance lives in [README.md](README.md).

## Contributor Checklist

Before opening a PR or cutting a release candidate:

1. Run `swift test`.
2. Launch the app and verify the status item opens correctly.
3. Sanity-check the providers or settings areas affected by your change.
4. If you changed packaging behavior, verify the generated `.app` or `.dmg` locally.

## Project Docs

- See [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md) for package structure and runtime flow.
- See [Docs/TEST_STRATEGY.md](Docs/TEST_STRATEGY.md) for automated coverage and manual verification guidance.
- See [Docs/RELEASING.md](Docs/RELEASING.md) for the tag-driven GitHub Actions release flow.
