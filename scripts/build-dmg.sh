#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="ClipHistory"
DIST="$ROOT/dist"
APP_BUNDLE="$DIST/$APP_NAME.app"
DMG="$DIST/$APP_NAME.dmg"

# ── 1. Release build ──────────────────────────────────────────────────────────
echo "▸ Building release binary…"
cd "$ROOT"
swift build -c release

# ── 2. Generate app icon ──────────────────────────────────────────────────────
echo "▸ Generating icons…"
mkdir -p "$DIST"
swift scripts/generate-icons.swift "$DIST"

echo "▸ Compiling AppIcon.icns…"
iconutil -c icns "$DIST/AppIcon.iconset" -o "$DIST/AppIcon.icns"
rm -rf "$DIST/AppIcon.iconset"          # clean up intermediate files

# ── 3. Assemble .app bundle ───────────────────────────────────────────────────
echo "▸ Assembling $APP_NAME.app…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp ".build/release/$APP_NAME"   "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$DIST/AppIcon.icns"         "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ClipHistory</string>

    <key>CFBundleIdentifier</key>
    <string>com.weiyuankong.cliphistory</string>

    <key>CFBundleName</key>
    <string>ClipHistory</string>

    <key>CFBundleDisplayName</key>
    <string>ClipHistory</string>

    <key>CFBundleIconFile</key>
    <string>AppIcon</string>

    <key>CFBundleVersion</key>
    <string>1.0.0</string>

    <key>CFBundleShortVersionString</key>
    <string>1.0</string>

    <key>CFBundlePackageType</key>
    <string>APPL</string>

    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>

    <!-- Hide from Dock; lives only in the menu bar -->
    <key>LSUIElement</key>
    <true/>

    <key>NSPrincipalClass</key>
    <string>NSApplication</string>

    <key>NSHighResolutionCapable</key>
    <true/>

    <key>NSAccessibilityUsageDescription</key>
    <string>ClipHistory needs Accessibility access to detect your clipboard shortcut and paste items into other apps.</string>
</dict>
</plist>
PLIST

# ── 4. Ad-hoc code sign ───────────────────────────────────────────────────────
echo "▸ Code signing (ad-hoc)…"
codesign --force --deep --sign - "$APP_BUNDLE"

# ── 5. Create DMG with drag-to-Applications layout ────────────────────────────
echo "▸ Creating DMG…"
rm -f "$DMG"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -r "$APP_BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -volname   "$APP_NAME" \
    -srcfolder "$STAGING" \
    -ov \
    -format    UDZO \
    -o         "$DMG"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "✓  $DMG"
echo "   Open the DMG and drag $APP_NAME.app → Applications to install."
