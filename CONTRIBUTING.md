# Contributing

This document covers local development, testing, packaging, and the other repo-internal details that do not belong in the user-facing README.

## macOS requirements

- macOS 15 or newer
- Xcode 16 or newer
- Swift 6 or newer
- Current stable Rust toolchain

## Windows requirements

- Windows 11
- .NET 10 SDK matching the host architecture
- Current stable Rust `*-pc-windows-gnullvm` toolchain
- LLVM-MinGW UCRT (provides the linker without installing Visual Studio)

The Windows setup deliberately does not require Visual Studio or Visual Studio Build Tools. One minimal setup is:

```powershell
winget install Microsoft.DotNet.SDK.10
winget install Rustlang.Rustup
winget install MartinStorsjo.LLVM-MinGW.UCRT
rustup toolchain install stable-aarch64-pc-windows-gnullvm
```

Use `stable-x86_64-pc-windows-gnullvm` on an x64 development machine.

## Getting Started on macOS

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

For app-bundle builds, the Rust core is built and bundled automatically by `scripts/build-app.sh`. For `swift run`, build it once with `cargo build` so the development executable can find it.

## Getting Started on Windows

```powershell
cargo +stable-aarch64-pc-windows-gnullvm test --workspace
& 'C:\Program Files\dotnet\dotnet.exe' build apps\windows\AiUsage.Windows\AiUsage.Windows.csproj -p:Platform=ARM64
```

The debug build opens the compact usage panel automatically. Release builds start tray-only.

## Local Packaging

### Standalone `.app` Bundle

```bash
./scripts/build-app.sh
open '.build/AI Usage.app'
```

The packaging script creates a lightweight menu bar app bundle with `LSUIElement=1`, so the app runs without a Dock icon.

### `.dmg` Bundle

```bash
./scripts/package-dmg.sh --version 0.5.2 --build-number 1
open .build/AI-Usage-0.5.2.dmg
```

The DMG build is not Developer ID-signed or notarized. It applies an ad hoc signature to the finished app bundle before packaging.

User-facing first-launch and Gatekeeper guidance lives in [README.md](README.md).

### Portable Windows ZIP

```powershell
.\scripts\package-windows.ps1 -Architecture ARM64 -Version 0.5.2
```

The output is written under `artifacts/`. The trimmed, self-contained folder and ZIP run on a clean Windows 11 machine without Visual Studio, a separately installed .NET runtime, or a separately installed Windows App SDK runtime. Use `-Architecture x64` for the optional x64 build.

## Contributor Checklist

Before opening a PR or cutting a release candidate:

1. Run `cargo test --workspace` and `cargo fmt --check`.
2. On macOS, run `swift test`; on Windows, build the WinUI project for the host architecture.
3. Launch the app and verify that a left click opens only the compact panel and Settings opens a separate full window.
4. Sanity-check the providers or settings areas affected by your change.
5. If you changed packaging behavior, verify the generated `.app`, `.dmg`, portable folder, or ZIP locally.

## Project Docs

- See [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md) for package structure and runtime flow.
- See [Docs/TEST_STRATEGY.md](Docs/TEST_STRATEGY.md) for automated coverage and manual verification guidance.
- See [Docs/RELEASING.md](Docs/RELEASING.md) for the tag-driven GitHub Actions release flow.
