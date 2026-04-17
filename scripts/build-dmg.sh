#!/usr/bin/env zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
ASSETS_DIR="$ROOT_DIR/assets"
APP_NAME="AI Usage.app"
APP_PATH="$BUILD_DIR/$APP_NAME"
DMG_VOLUME_NAME="AI Usage"

cd "$ROOT_DIR"
./scripts/build-app.sh

if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app bundle at $APP_PATH, but it was not found."
  exit 1
fi

version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")"
dmg_path="$BUILD_DIR/AI-Usage-${version}.dmg"
dmg_writable_path="$BUILD_DIR/AI-Usage-${version}-rw.dmg"
legacy_dmg_path="$BUILD_DIR/AI-Usage-${version}-unsigned.dmg"
mount_dir="$BUILD_DIR/dmg-mount"

rm -rf "$BUILD_DIR/dmg-stage" "$dmg_path" "$dmg_writable_path" "$legacy_dmg_path"

# ── Staging directory ──────────────────────────────────────────────────────────
DMG_STAGE_DIR="$BUILD_DIR/dmg-stage"
mkdir -p "$DMG_STAGE_DIR"

ditto --noqtn "$APP_PATH" "$DMG_STAGE_DIR/$APP_NAME"
xattr -cr "$DMG_STAGE_DIR/$APP_NAME"

# Applications symlink — the drop target users drag the app to
ln -s /Applications "$DMG_STAGE_DIR/Applications"

# ── Background image ───────────────────────────────────────────────────────────
BG_SVG="$ASSETS_DIR/dmg-background.svg"
BG_DIR="$DMG_STAGE_DIR/.background"
mkdir -p "$BG_DIR"

if [[ ! -f "$BG_SVG" ]]; then
  echo "Warning: DMG background SVG not found at $BG_SVG — skipping background." >&2
else
  echo "Generating DMG background image..."

  # 1x (660 × 400) — qlmanage outputs <name>.png inside the destination dir
  qlmanage -t -s 660 -o "$BUILD_DIR" "$BG_SVG" >/dev/null 2>&1
  BG_1X_SRC="$BUILD_DIR/dmg-background.svg.png"

  # 2x (1320 × 800) for Retina
  qlmanage -t -s 1320 -o "$BUILD_DIR" "$BG_SVG" >/dev/null 2>&1
  BG_2X_SRC="$BUILD_DIR/dmg-background.svg.png"
  cp "$BG_2X_SRC" "$BUILD_DIR/dmg-background-2x.png"

  # Restore the 1x copy (qlmanage overwrites the same filename)
  qlmanage -t -s 660 -o "$BUILD_DIR" "$BG_SVG" >/dev/null 2>&1
  cp "$BG_1X_SRC" "$BUILD_DIR/dmg-background-1x.png"

  # Merge into a multi-resolution TIFF for crisp Retina display
  tiffutil -cathidpicheck \
    "$BUILD_DIR/dmg-background-1x.png" \
    "$BUILD_DIR/dmg-background-2x.png" \
    -out "$BG_DIR/background.tiff"

  echo "Background image ready."
fi

# ── Create writable DMG, configure layout, then compress ──────────────────────
echo "Creating writable DMG..."
hdiutil create \
  -volname "$DMG_VOLUME_NAME" \
  -srcfolder "$DMG_STAGE_DIR" \
  -ov \
  -format UDRW \
  "$dmg_writable_path" >/dev/null

rm -rf "$mount_dir"
mkdir -p "$mount_dir"

mount_dir="/Volumes/AI Usage"
/usr/bin/hdiutil attach "$dmg_writable_path" -noverify >/dev/null

# Hide the .background folder so it is invisible to users
chflags hidden "$mount_dir/.background" 2>/dev/null || true

# Configure Finder window layout via AppleScript.
# Non-fatal: if Finder / AppleScript is unavailable (e.g. headless CI) the
# DMG is still fully functional — just without the custom icon positions.
echo "Configuring DMG window layout..."
open -a Finder >/dev/null 2>&1 || true
sleep 1

APPLESCRIPT_SUCCESS=0
for attempt in 1 2 3; do
  if osascript <<'APPLESCRIPT' 2>/dev/null; then
tell application "Finder"
  tell disk "AI Usage"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {400, 100, 1060, 500}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set background picture of viewOptions to file ".background:background.tiff"
    set position of item "AI Usage.app" to {165, 190}
    set position of item "Applications" to {495, 190}
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT
    APPLESCRIPT_SUCCESS=1
    break
  fi
  echo "  AppleScript attempt $attempt failed, retrying..." >&2
  sleep 3
done

if [[ "$APPLESCRIPT_SUCCESS" -eq 0 ]]; then
  echo "Warning: AppleScript layout configuration failed — DMG will open without custom layout." >&2
fi

sync
sleep 2

/usr/bin/hdiutil detach "$mount_dir" >/dev/null

# ── Verify app is launchable inside the final DMG ─────────────────────────────
# Re-use the compressed DMG (after conversion below) for the codesign check
# so we only need one extra attach/detach cycle.

# ── Compress to final read-only DMG ───────────────────────────────────────────
echo "Compressing DMG..."
hdiutil convert "$dmg_writable_path" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$dmg_path" >/dev/null

rm -f "$dmg_writable_path"
xattr -cr "$dmg_path"

# ── Verify app is launchable (codesign check) ─────────────────────────────────
/usr/bin/hdiutil attach "$dmg_path" -noverify >/dev/null
if ! codesign --verify --deep --strict --verbose=2 "/Volumes/AI Usage/$APP_NAME" >/dev/null 2>&1; then
  /usr/bin/hdiutil detach "/Volumes/AI Usage" >/dev/null
  echo "App inside DMG failed strict ad-hoc signature verification."
  exit 1
fi
/usr/bin/hdiutil detach "/Volumes/AI Usage" >/dev/null

echo "Created DMG: $dmg_path"
