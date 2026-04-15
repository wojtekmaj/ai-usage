#!/usr/bin/env zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
APP_NAME="AI Usage.app"
APP_PATH="$BUILD_DIR/$APP_NAME"
DMG_STAGE_DIR="$BUILD_DIR/dmg-stage"
DMG_VOLUME_NAME="AI Usage"
MOUNT_DIR="$BUILD_DIR/dmg-mount"

cd "$ROOT_DIR"
./scripts/build-app.sh

if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app bundle at $APP_PATH, but it was not found."
  exit 1
fi

version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")"
dmg_path="$BUILD_DIR/AI-Usage-${version}.dmg"
legacy_dmg_path="$BUILD_DIR/AI-Usage-${version}-unsigned.dmg"

rm -rf "$DMG_STAGE_DIR" "$dmg_path" "$legacy_dmg_path"
mkdir -p "$DMG_STAGE_DIR"

ditto --noqtn "$APP_PATH" "$DMG_STAGE_DIR/$APP_NAME"
xattr -cr "$DMG_STAGE_DIR/$APP_NAME"

hdiutil create \
  -volname "$DMG_VOLUME_NAME" \
  -srcfolder "$DMG_STAGE_DIR" \
  -ov \
  -format UDZO \
  "$dmg_path"

xattr -cr "$dmg_path"

if xattr -l "$dmg_path" >/dev/null 2>&1 && [[ -n "$(xattr -l "$dmg_path" 2>/dev/null)" ]]; then
  echo "DMG still has extended attributes after cleanup."
  exit 1
fi

rm -rf "$MOUNT_DIR"
mkdir -p "$MOUNT_DIR"
hdiutil attach "$dmg_path" -mountpoint "$MOUNT_DIR" -nobrowse >/dev/null
if ! codesign -dv "$MOUNT_DIR/$APP_NAME" >/dev/null 2>&1; then
  hdiutil detach "$MOUNT_DIR" >/dev/null
  echo "App inside DMG is not launchable signed (adhoc) binary."
  exit 1
fi
hdiutil detach "$MOUNT_DIR" >/dev/null
rm -rf "$MOUNT_DIR"

echo "Created DMG: $dmg_path"
