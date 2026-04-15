# Releasing

Releases are built and published by GitHub Actions from a pushed git tag.

## Tag format

Create a tag in the form:

```
v<version>
```

Where `<version>` must match the same semver-like format enforced by the packaging scripts (`SEMVER_LIKE_VERSION_REGEX`):

- `X.Y.Z`
- optional `-prerelease` (dot-separated identifiers)
- optional `+build` metadata (dot-separated identifiers)

Examples:

- `v1.2.3`
- `v1.2.3-rc.1`
- `v1.2.3+build.5`

## How a release is triggered

Pushing a tag matching `v*` triggers `.github/workflows/release.yml`.

The workflow:

1. Validates the tag name (before checkout/build).
2. Builds an **unsigned** app bundle and packages an **unsigned** DMG by running:

   ```bash
   ./scripts/package-dmg.sh --version "$VERSION" --build-number "$GITHUB_RUN_NUMBER"
   ```

3. Creates a GitHub Release for the tag and uploads:

   - `.build/AI-Usage-<version>.dmg`

## Gatekeeper (unsigned DMG)

This project ships an **unsigned** DMG (no code signing, no notarization). macOS Gatekeeper may block the app on first launch.

Typical install flow:

1. Download the DMG from GitHub Releases.
2. Open the DMG and drag `AI Usage.app` to `/Applications`.
3. If macOS blocks the app, you can remove the quarantine attribute:

   ```bash
   xattr -dr com.apple.quarantine "/Applications/AI Usage.app"
   ```

Alternatively, macOS may allow opening via Finder `Right click -> Open`, or by approving the app in System Settings > Privacy & Security.
