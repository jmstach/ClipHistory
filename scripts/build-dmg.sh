#!/usr/bin/env bash
set -euo pipefail

# Public, from-source build: ad-hoc signed. Anyone can run this without the
# project's Developer ID. For a notarised release, use release.sh instead.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib.sh"

DIST="$ROOT/dist"
APP_BUNDLE="$DIST/$APP_NAME.app"
DMG="$DIST/$APP_NAME.dmg"

# ── 1. Release build ──────────────────────────────────────────────────────────
echo "▸ Building release binary…"
cd "$ROOT"
swift build -c release

# ── 2. Compile app icon (Icon Composer → Assets.car + loose icns) ─────────────
echo "▸ Compiling icon…"
build_app_icon "$DIST"

# ── 3. Assemble .app bundle ───────────────────────────────────────────────────
echo "▸ Assembling $APP_NAME.app…"
assemble_bundle ".build/release/$APP_NAME" "$APP_BUNDLE" "$DIST/AppIcon.icns"

# ── 4. Ad-hoc code sign ───────────────────────────────────────────────────────
echo "▸ Code signing (ad-hoc)…"
codesign --force --deep --sign - "$APP_BUNDLE"

# ── 5. DMG ────────────────────────────────────────────────────────────────────
echo "▸ Creating DMG…"
make_dmg "$APP_BUNDLE" "$DMG"
set_file_icon "$DIST/AppIcon.icns" "$DMG"

echo ""
echo "✓  $DMG"
echo "   Open the DMG and drag $APP_NAME.app → Applications to install."
echo "   (Ad-hoc signed: recipients clear quarantine with"
echo "    xattr -dr com.apple.quarantine /Applications/$APP_NAME.app)"
