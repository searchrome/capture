#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
CONFIGURATION="${1:-debug}"
case "$CONFIGURATION" in
    debug|release) ;;
    *) echo "Usage: $0 [debug|release]" >&2; exit 2 ;;
esac

swift build -c "$CONFIGURATION"
BIN_PATH="$(swift build -c "$CONFIGURATION" --show-bin-path)"
APP_PATH="$PROJECT_ROOT/build/Capture.app"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN_PATH/Capture" "$APP_PATH/Contents/MacOS/Capture"
cp "$PROJECT_ROOT/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
shopt -s dotglob nullglob
for RESOURCE in "$PROJECT_ROOT"/Resources/*; do
    [[ "$(basename "$RESOURCE")" == "Info.plist" ]] && continue
    cp -R "$RESOURCE" "$APP_PATH/Contents/Resources/"
done

SIGNING_IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/"Apple Development/ && !found { print $2; found=1 }' || true)"
fi
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
codesign --force --sign "$SIGNING_IDENTITY" "$APP_PATH"
codesign --verify --strict "$APP_PATH"
echo "Built $APP_PATH"
