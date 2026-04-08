#!/usr/bin/env zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
APP_DIR="$BUILD_DIR/AI Usage.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

cp "$BUILD_DIR/release/AiUsageApp" "$MACOS_DIR/AiUsageApp"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>AI Usage</string>
  <key>CFBundleExecutable</key>
  <string>AiUsageApp</string>
  <key>CFBundleIdentifier</key>
  <string>com.wojciechmaj.ai-usage</string>
  <key>CFBundleName</key>
  <string>AI Usage</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string></string>
</dict>
</plist>
PLIST

echo "Created app bundle: $APP_DIR"
