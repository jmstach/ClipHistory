#!/usr/bin/env bash
# Shared config + helpers for the ClipHistory build scripts.
# Sourced by build-dmg.sh (ad-hoc, public), dev.sh (fast local loop) and
# release.sh (notarised distributable). Keeping the identifiers here means the
# bundle ID / version / signing identity are defined exactly once.

APP_NAME="ClipHistory"
BUNDLE_ID="uk.stach.cliphistory"
VERSION="1.4.0"
DEV_ID="Developer ID Application: Justin Stach (D25B8VCSB7)"
NOTARY_PROFILE="ClipHistoryNotary"   # created via `xcrun notarytool store-credentials`

# Cloudflare R2 release hosting (see UpdateChecker.swift — it reads appcast.json here).
DOWNLOAD_BASE="https://downloads.cliphistory.stach.uk"   # custom domain on the bucket
R2_BUCKET="cliphistory-downloads"                        # stable keys: ClipHistory.dmg + appcast.json
NOTES_URL="https://github.com/jmstach/ClipHistory/releases"

# write_info_plist <app_bundle>
write_info_plist() {
    local bundle="$1"
    cat > "$bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>

    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>

    <key>CFBundleName</key>
    <string>${APP_NAME}</string>

    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>

    <key>CFBundleIconFile</key>
    <string>AppIcon</string>

    <key>CFBundleVersion</key>
    <string>${VERSION}</string>

    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>

    <key>CFBundlePackageType</key>
    <string>APPL</string>

    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>

    <!-- Hide from Dock; lives only in the menu bar / hotkey popup -->
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
}

# assemble_bundle <binary_src> <app_bundle> [icns_src]
# Builds the .app layout from a freshly-built binary. Caller signs afterwards.
assemble_bundle() {
    local bin="$1" bundle="$2" icns="${3:-}"
    rm -rf "$bundle"
    mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
    cp "$bin" "$bundle/Contents/MacOS/$APP_NAME"
    if [ -n "$icns" ] && [ -f "$icns" ]; then
        cp "$icns" "$bundle/Contents/Resources/AppIcon.icns"
    fi
    printf 'APPL????' > "$bundle/Contents/PkgInfo"
    write_info_plist "$bundle"
}

# make_dmg <app_bundle> <dmg_path>
# Stages the app next to an /Applications symlink and builds a compressed DMG.
make_dmg() {
    local bundle="$1" dmg="$2"
    rm -f "$dmg"
    local staging
    staging="$(mktemp -d)"
    cp -R "$bundle" "$staging/"
    ln -s /Applications "$staging/Applications"
    hdiutil create -volname "$APP_NAME" -srcfolder "$staging" -ov -format UDZO -o "$dmg"
    rm -rf "$staging"
}
