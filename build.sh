#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

APP_NAME="Clair de Lune"
APP_BUNDLE="${APP_NAME}.app"
DMG_NAME="${APP_NAME}.dmg"
STAGE_DIR="dist/dmg_staging"

clean_xattrs() {
  xattr -cr "$1" 2>/dev/null || true
  find "$1" -exec xattr -c {} \; 2>/dev/null || true
}

rm -rf "$APP_BUNDLE" "$STAGE_DIR" "$DMG_NAME"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$STAGE_DIR"

swiftc \
  Sources/*.swift \
  -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
  -framework Cocoa -framework CoreLocation

cp Info.plist "$APP_BUNDLE/Contents/Info.plist"
cp Assets/moon.icns "$APP_BUNDLE/Contents/Resources/moon.icns"

clean_xattrs "$APP_BUNDLE"
codesign --force --deep --sign - "$APP_BUNDLE" > /dev/null
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

ditto --noextattr --noqtn "$APP_BUNDLE" "$STAGE_DIR/$APP_BUNDLE"
ln -s /Applications "$STAGE_DIR/Applications"
cp Assets/moon.icns "$STAGE_DIR/.VolumeIcon.icns"
if [ -x /Library/Developer/CommandLineTools/usr/bin/SetFile ]; then
  /Library/Developer/CommandLineTools/usr/bin/SetFile -a C "$STAGE_DIR"
fi

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_NAME" \
  > /dev/null

xattr -cr "$DMG_NAME" 2>/dev/null || true
