#!/usr/bin/env bash
set -euo pipefail

# Fast local iteration: rebuild, assemble, Developer ID sign, relaunch.
# Developer ID (not ad-hoc) keeps the Accessibility grant stable across rebuilds
# so the popup's CGEventTap keeps working. Compiles the icon every run (actool is
# quick) so dist/ can never serve a stale icon into the bundle.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib.sh"

DIST="$ROOT/dist"
APP_BUNDLE="$DIST/$APP_NAME.app"

cd "$ROOT"
echo "▸ Building…"
swift build -c release

echo "▸ Compiling icon…"
mkdir -p "$DIST"
build_app_icon "$DIST"

echo "▸ Assembling + signing (Developer ID)…"
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
