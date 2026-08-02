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
2. Builds a macOS app bundle, applies a full ad hoc signature, and packages it in a DMG that is not Developer ID-signed or notarized by running:

   ```bash
   ./scripts/package-dmg.sh --version "$VERSION" --build-number "$GITHUB_RUN_NUMBER"
   ```

3. Builds unsigned, trimmed, self-contained portable Windows ZIP files on native ARM64 and x64 runners.
4. Creates one GitHub Release for the tag and uploads:

   - `.build/AI-Usage-<version>.dmg`
   - `artifacts/AI-Usage-<version>-windows-arm64.zip`
   - `artifacts/AI-Usage-<version>-windows-x64.zip`

Neither platform requires a paid developer account. The tradeoff is that macOS Gatekeeper and Windows SmartScreen can warn on first launch. First-launch guidance is maintained in `README.md` and the Windows ZIP's `README.txt`.
