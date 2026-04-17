#!/bin/zsh

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: ./scripts/build-app.sh [--version <version>] [--build-number <build>]

Builds a standalone .app bundle into ./.build/AI Usage.app.

Options:
  --version        Sets CFBundleShortVersionString (default: env APP_VERSION or VERSION or 0.0.0)
  --build-number   Sets CFBundleVersion (default: env APP_BUILD or GITHUB_RUN_NUMBER or 1)
USAGE
}

APP_VERSION_FROM_ARGS=""
APP_BUILD_FROM_ARGS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      if [[ $# -lt 2 || -z "${2:-}" || "${2:-}" == --* ]]; then
        echo "Missing value for --version" >&2
        usage >&2
        exit 2
      fi

      APP_VERSION_FROM_ARGS="$2"
      shift 2
      ;;
    --build-number)
      if [[ $# -lt 2 || -z "${2:-}" || "${2:-}" == --* ]]; then
        echo "Missing value for --build-number" >&2
        usage >&2
        exit 2
      fi

      APP_BUILD_FROM_ARGS="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

APP_VERSION="${APP_VERSION_FROM_ARGS:-${APP_VERSION:-${VERSION:-0.0.0}}}"
APP_BUILD="${APP_BUILD_FROM_ARGS:-${APP_BUILD:-${GITHUB_RUN_NUMBER:-1}}}"

if [[ -z "$APP_VERSION" ]]; then
  echo "APP_VERSION resolved to empty string" >&2
  exit 1
fi

# Semver-ish: X.Y.Z with optional -prerelease and/or +build metadata.
# prerelease/build are dot-separated identifiers containing only [0-9A-Za-z-].
# (Apple requires a sane version string for CFBundleShortVersionString.)
SEMVER_LIKE_VERSION_REGEX='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'

# Reject any whitespace/control chars or other unexpected characters.
# This also prevents multiline bypasses of the semver-ish validation.
if [[ "$APP_VERSION" =~ [^0-9A-Za-z.+-] ]]; then
  echo "Invalid --version/APP_VERSION: '$APP_VERSION'" >&2
  echo "Expected semver-ish format like '1.2.3', optionally with '-rc.1' and/or '+build.5'." >&2
  exit 2
fi

if ! [[ "$APP_VERSION" =~ $SEMVER_LIKE_VERSION_REGEX ]]; then
  echo "Invalid --version/APP_VERSION: '$APP_VERSION'" >&2
  echo "Expected semver-ish format like '1.2.3', optionally with '-rc.1' and/or '+build.5'." >&2
  exit 2
fi

if [[ -z "$APP_BUILD" ]]; then
  echo "APP_BUILD resolved to empty string" >&2
  exit 1
fi

if ! [[ "$APP_BUILD" =~ ^[0-9]+$ ]]; then
  echo "Invalid --build-number/APP_BUILD: '$APP_BUILD'" >&2
  echo "Expected digits only (e.g., '1' or '123')." >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
APP_DIR="$BUILD_DIR/AI Usage.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_SOURCE="$ROOT_DIR/Sources/AiUsageApp/Resources/AppIcon.svg"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
ICON_BASE_PNG="$BUILD_DIR/AppIcon.svg.png"

# Hardening: prevent writing outside repo via symlinks/path tricks.
if [[ -L "$BUILD_DIR" ]]; then
  echo "Refusing to use symlink build directory: $BUILD_DIR" >&2
  exit 2
fi

if [[ -e "$BUILD_DIR" && ! -d "$BUILD_DIR" ]]; then
  echo "Build directory path exists but is not a directory: $BUILD_DIR" >&2
  exit 1
fi

mkdir -p "$BUILD_DIR"

if [[ ! -x /usr/bin/python3 ]]; then
  echo "Required python3 interpreter missing or not executable: /usr/bin/python3" >&2
  exit 1
fi

PYTHON_BIN="/usr/bin/python3"

realpath_compat() {
  "$PYTHON_BIN" -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"
}

commonpath_compat() {
  "$PYTHON_BIN" -c '
import os
import sys

try:
    print(os.path.commonpath([sys.argv[1], sys.argv[2]]))
except Exception as e:
    print(f"Failed to compute common path: {e}", file=sys.stderr)
    sys.exit(2)
' "$1" "$2"
}

ROOT_DIR_REALPATH="$(realpath_compat "$ROOT_DIR")"
BUILD_DIR_REALPATH="$(realpath_compat "$BUILD_DIR")"

ROOT_BUILD_COMMON_PATH="$(commonpath_compat "$BUILD_DIR_REALPATH" "$ROOT_DIR_REALPATH")"
if [[ "$ROOT_BUILD_COMMON_PATH" != "$ROOT_DIR_REALPATH" ]]; then
  echo "Refusing to use build directory outside repository root." >&2
  echo "ROOT_DIR resolved to: $ROOT_DIR_REALPATH" >&2
  echo "BUILD_DIR resolved to: $BUILD_DIR_REALPATH" >&2
  exit 2
fi

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

cp "$BUILD_DIR/release/AiUsageApp" "$MACOS_DIR/AiUsageApp"

rm -rf "$ICONSET_DIR" "$ICON_BASE_PNG"
qlmanage -t -s 1024 -o "$BUILD_DIR" "$ICON_SOURCE" >/dev/null
mkdir -p "$ICONSET_DIR"

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ICON_BASE_PNG" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
  double_size=$((size * 2))
  sips -z "$double_size" "$double_size" "$ICON_BASE_PNG" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>AI Usage</string>
  <key>CFBundleExecutable</key>
  <string>AiUsageApp</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>com.wojciechmaj.ai-usage</string>
  <key>CFBundleName</key>
  <string>AI Usage</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${APP_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${APP_BUILD}</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string></string>
</dict>
</plist>
PLIST

# Build output is only linker-signed. Sign the finished bundle ad hoc so the
# packaged app has a valid bundle signature after we add Info.plist/resources.
codesign --force --sign - "$MACOS_DIR/AiUsageApp"
codesign --force --sign - "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

echo "Created app bundle: $APP_DIR"
echo "Version: $APP_VERSION ($APP_BUILD)"
