#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
if [[ $# -ne 0 ]]; then
    echo "Usage: $0" >&2
    exit 2
fi

"$PROJECT_ROOT/scripts/build-app.sh" release
APP_PATH="$PROJECT_ROOT/build/Capture.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
ARCHITECTURES="$(lipo -archs "$APP_PATH/Contents/MacOS/Capture")"
ARCHITECTURES="${ARCHITECTURES// /-}"
DMG_NAME="Capture-$VERSION-$ARCHITECTURES.dmg"
WORK_DIR="$(mktemp -d "$PROJECT_ROOT/build/dmg.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
mkdir "$WORK_DIR/contents"
ditto "$APP_PATH" "$WORK_DIR/contents/Capture.app"
ln -s /Applications "$WORK_DIR/contents/Applications"
cp "$PROJECT_ROOT/LICENSE" "$WORK_DIR/contents/LICENSE.txt"
cat > "$WORK_DIR/contents/Install.txt" <<'INSTRUCTIONS'
Install Capture

1. Drag Capture.app to Applications.
2. Eject this disk image.
3. Open Capture from Applications. Look for the viewfinder icon in the menu bar.

Requires macOS 14 or later. Grant Screen Recording when capturing an area.
Document reading and agent input also require Accessibility permission.
Add your own OpenRouter key in Settings for AI features, or choose on-device OCR.

This image is locally built. It is not notarized by this packaging script.
macOS may block opening the app until a trusted, notarized release is provided.
INSTRUCTIONS

hdiutil create -volname Capture -fs HFS+ -srcfolder "$WORK_DIR/contents" \
    -format UDZO "$WORK_DIR/$DMG_NAME"
hdiutil verify "$WORK_DIR/$DMG_NAME"
mv -f "$WORK_DIR/$DMG_NAME" "$PROJECT_ROOT/build/$DMG_NAME"
(
    cd "$PROJECT_ROOT/build"
    shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256"
)
echo "Built $PROJECT_ROOT/build/$DMG_NAME"
echo "SHA-256: $PROJECT_ROOT/build/$DMG_NAME.sha256"
echo "Not notarized. Developer ID signing and notarization are required for public distribution."
