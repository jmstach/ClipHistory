#!/usr/bin/env bash
set -euo pipefail

# Fast local iteration: rebuild, assemble, Developer ID sign, relaunch.
# Developer ID (not ad-hoc) keeps the Accessibility grant stable across rebuilds
# so the popup's CGEventTap keeps working. Reuses the last generated icon if
# present; run build-dmg.sh or release.sh once if you want a fresh icon.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib.sh"

DIST="$ROOT/dist"
APP_BUNDLE="$DIST/$APP_NAME.app"

cd "$ROOT"
echo "▸ Building…"
swift build -c release

echo "▸ Assembling + signing (Developer ID)…"
mkdir -p "$DIST"
assemble_bundle ".build/release/$APP_NAME" "$APP_BUNDLE" "$DIST/AppIcon.icns"
codesign --force --sign "$DEV_ID" "$APP_BUNDLE"
codesign --verify "$APP_BUNDLE"

echo "▸ Relaunching…"
osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
sleep 1
pkill -f "$APP_BUNDLE/Contents/MacOS/$APP_NAME" 2>/dev/null || true
sleep 1
open "$APP_BUNDLE"
sleep 1
echo "✓  Running: $(pgrep -f "$APP_BUNDLE/Contents/MacOS/$APP_NAME" | head -1)"
