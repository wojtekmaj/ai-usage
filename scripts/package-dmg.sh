#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: ./scripts/package-dmg.sh --version <version> [--build-number <build>] [--skip-build]

Builds the app bundle (unsigned) and creates a DMG.

Outputs:
  - ./.build/AI-Usage-<version>.dmg

Environment (optional):
  BUILD_NUMBER     Default build number passed to build-app.sh
                 (defaults to GITHUB_RUN_NUMBER or 1)

Options:
  --build-number   CFBundleVersion (overrides BUILD_NUMBER/GITHUB_RUN_NUMBER)
  --skip-build     Assume ./.build/AI Usage.app already exists; do not rebuild
USAGE
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"

VERSION=""
SKIP_BUILD="0"
BUILD_NUMBER_FROM_ARGS=""

STAGING_DIR=""
DMG_TMP_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      if [[ $# -lt 2 || -z "${2:-}" || "${2:-}" == --* ]]; then
        echo "Missing value for --version" >&2
        usage >&2
        exit 2
      fi

      VERSION="$2"
      shift 2
      ;;
    --build-number)
      if [[ $# -lt 2 || -z "${2:-}" || "${2:-}" == --* ]]; then
        echo "Missing value for --build-number" >&2
        usage >&2
        exit 2
      fi

      BUILD_NUMBER_FROM_ARGS="$2"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD="1"
      shift 1
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

if [[ -z "$VERSION" ]]; then
  echo "--version is required" >&2
  usage >&2
  exit 2
fi

# Semver-ish: X.Y.Z with optional -prerelease and/or +build metadata.
# prerelease/build are dot-separated identifiers containing only [0-9A-Za-z-].
# Keep this compatible with scripts/build-app.sh and .github/workflows/release.yml.
SEMVER_LIKE_VERSION_REGEX='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'

# Reject any whitespace/control chars or other unexpected characters.
# This also prevents multiline bypasses of the semver-ish validation.
if [[ "$VERSION" =~ [^0-9A-Za-z.+-] ]]; then
  echo "Invalid --version: '$VERSION'" >&2
  echo "Expected semver-ish format like '1.2.3', optionally with '-rc.1' and/or '+build.5'." >&2
  exit 2
fi

if ! [[ "$VERSION" =~ $SEMVER_LIKE_VERSION_REGEX ]]; then
  echo "Invalid --version: '$VERSION'" >&2
  echo "Expected semver-ish format like '1.2.3', optionally with '-rc.1' and/or '+build.5'." >&2
  exit 2
fi

BUILD_NUMBER="${BUILD_NUMBER_FROM_ARGS:-${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-1}}}"

if [[ -z "$BUILD_NUMBER" ]]; then
  echo "BUILD_NUMBER resolved to empty string" >&2
  exit 1
fi

if ! [[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Invalid --build-number/BUILD_NUMBER: '$BUILD_NUMBER'" >&2
  echo "Expected digits only (e.g., '1' or '123')." >&2
  exit 2
fi

APP_NAME="AI Usage.app"
APP_PATH="$BUILD_DIR/$APP_NAME"

if [[ -L "$BUILD_DIR" ]]; then
  echo "Refusing to use symlink build directory: $BUILD_DIR" >&2
  exit 2
fi

if [[ -e "$BUILD_DIR" && ! -d "$BUILD_DIR" ]]; then
  echo "Build directory path exists but is not a directory: $BUILD_DIR" >&2
  exit 1
fi

if [[ ! -d "$BUILD_DIR" ]]; then
  mkdir -p "$BUILD_DIR"
fi

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

if [[ "$SKIP_BUILD" != "1" ]]; then
  BUILD_SCRIPT="$ROOT_DIR/scripts/build-app.sh"
  if [[ -x "$BUILD_SCRIPT" ]]; then
    "$BUILD_SCRIPT" --version "$VERSION" --build-number "$BUILD_NUMBER"
  else
    /bin/zsh "$BUILD_SCRIPT" --version "$VERSION" --build-number "$BUILD_NUMBER"
  fi
fi

if [[ "$SKIP_BUILD" == "1" && ! -d "$APP_PATH" ]]; then
  echo "--skip-build set, but app bundle was not found at: $APP_PATH" >&2
  echo "Build it first (or remove --skip-build)." >&2
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app bundle at: $APP_PATH" >&2
  exit 1
fi

if [[ -L "$APP_PATH" ]]; then
  echo "Refusing to package app bundle symlink: $APP_PATH" >&2
  exit 2
fi

APP_PATH_REALPATH="$(realpath_compat "$APP_PATH")"

APP_BUILD_COMMON_PATH="$(commonpath_compat "$APP_PATH_REALPATH" "$BUILD_DIR_REALPATH")"
if [[ "$APP_BUILD_COMMON_PATH" != "$BUILD_DIR_REALPATH" ]]; then
  echo "Refusing to package app outside build directory." >&2
  echo "APP_PATH resolved to: $APP_PATH_REALPATH" >&2
  echo "BUILD_DIR resolved to: $BUILD_DIR_REALPATH" >&2
  exit 2
fi

if [[ "$APP_PATH_REALPATH" == "$BUILD_DIR_REALPATH" ]]; then
  echo "Refusing to package build directory itself." >&2
  echo "APP_PATH resolved to: $APP_PATH_REALPATH" >&2
  exit 2
fi

APP_PATH_REAL_BASENAME="${APP_PATH_REALPATH##*/}"
APP_PATH_REAL_DIRNAME="${APP_PATH_REALPATH%/*}"

if [[ "$APP_PATH_REAL_BASENAME" != "$APP_NAME" ]]; then
  echo "Refusing to package unexpected app bundle name." >&2
  echo "Expected basename: $APP_NAME" >&2
  echo "Resolved APP_PATH basename: $APP_PATH_REAL_BASENAME" >&2
  exit 2
fi

if [[ "$APP_PATH_REAL_DIRNAME" != "$BUILD_DIR_REALPATH" ]]; then
  echo "Refusing to package app not directly inside build directory." >&2
  echo "Expected dirname: $BUILD_DIR_REALPATH" >&2
  echo "Resolved APP_PATH dirname: $APP_PATH_REAL_DIRNAME" >&2
  exit 2
fi

if [[ ! -d "$APP_PATH_REALPATH" ]]; then
  echo "Expected app bundle at resolved path: $APP_PATH_REALPATH" >&2
  exit 1
fi

echo "Preflight: verifying app bundle contains no symlinks or special files"
"$PYTHON_BIN" - "$APP_PATH_REALPATH" <<'PY'
import os
import stat
import sys

root = sys.argv[1]

def describe_special(mode: int) -> str:
    if stat.S_ISCHR(mode):
        return "character device"
    if stat.S_ISBLK(mode):
        return "block device"
    if stat.S_ISFIFO(mode):
        return "fifo"
    if stat.S_ISSOCK(mode):
        return "socket"
    return "unknown"

def fail(message: str) -> None:
    print(message, file=sys.stderr)
    sys.exit(2)

def walk_no_symlinks(start: str) -> None:
    stack = [start]
    while stack:
        current = stack.pop()
        try:
            with os.scandir(current) as it:
                for entry in it:
                    path = entry.path
                    try:
                        st = entry.stat(follow_symlinks=False)
                    except FileNotFoundError:
                        # Race: entry disappeared between scandir and stat.
                        fail(f"Refusing to package app bundle: entry disappeared during scan: {path}")
                    mode = st.st_mode

                    rel = os.path.relpath(path, start)

                    if stat.S_ISLNK(mode):
                        fail(
                            "Refusing to package app bundle containing symlink:\n"
                            f"- {rel}\n"
                            f"- full path: {path}"
                        )

                    if stat.S_ISDIR(mode):
                        stack.append(path)
                        continue

                    if stat.S_ISREG(mode):
                        continue

                    fail(
                        "Refusing to package app bundle containing non-regular file:\n"
                        f"- type: {describe_special(mode)}\n"
                        f"- {rel}\n"
                        f"- full path: {path}"
                    )
        except NotADirectoryError:
            fail(f"Refusing to package app bundle: expected directory during scan: {current}")


walk_no_symlinks(root)
PY

STAGING_DIR="$(mktemp -d)"

cleanup() {
  if [[ -n "${STAGING_DIR:-}" ]]; then
    rm -rf "$STAGING_DIR"
  fi

  if [[ -n "${DMG_TMP_PATH:-}" && -e "${DMG_TMP_PATH:-}" ]]; then
    rm -f "$DMG_TMP_PATH"
  fi
}

trap cleanup EXIT

STAGING_APP_DIR="$STAGING_DIR/stage"
mkdir -p "$STAGING_APP_DIR"
/usr/bin/ditto "$APP_PATH_REALPATH" "$STAGING_APP_DIR/$APP_NAME"

DMG_NAME="AI-Usage-${VERSION}.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"

# Refuse even if it's a broken symlink.
if [[ -L "$DMG_PATH" ]]; then
  echo "Refusing to overwrite symlink DMG path: $DMG_PATH" >&2
  exit 2
fi

DMG_TMP_PATH="$(mktemp "$BUILD_DIR/.AI-Usage-${VERSION}.XXXXXX.dmg")"

echo "Creating DMG: $DMG_PATH"
/usr/bin/hdiutil create \
  -volname "AI Usage" \
  -srcfolder "$STAGING_APP_DIR" \
  -ov \
  -format UDZO \
  "$DMG_TMP_PATH" >/dev/null

mv -f "$DMG_TMP_PATH" "$DMG_PATH"
DMG_TMP_PATH=""

echo "Packaged artifacts:"
echo "- $DMG_PATH"
