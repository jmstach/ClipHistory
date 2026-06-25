#!/usr/bin/env bash
# Shared config + helpers for the ClipHistory build scripts.
# Sourced by build-dmg.sh (ad-hoc, public), dev.sh (fast local loop) and
# release.sh (notarised distributable). Keeping the identifiers here means the
# bundle ID / version / signing identity are defined exactly once.

APP_NAME="ClipHistory"
BUNDLE_ID="uk.stach.cliphistory"
VERSION="1.4.2"
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

# build_app_icon <dist_dir>
# Renders icon/AppIcon.icon (Icon Composer source) to a flat <dist>/AppIcon.icns
# at all sizes. actool also emits an Assets.car (the dynamic Liquid Glass form);
# we discard it — a flat icns keeps the bundle ~1.4 MB smaller and renders the
# same icon, just without the live specular highlight on macOS 26.
build_app_icon() {
    local dist="$1"
    mkdir -p "$dist"
    xcrun actool \
        --output-format human-readable-text --notices --warnings --errors \
        --target-device mac --minimum-deployment-target 14.0 --platform macosx \
        --app-icon AppIcon --standalone-icon-behavior all \
        --output-partial-info-plist "$dist/AppIcon-partial.plist" \
        --compile "$dist" "$ROOT/icon/AppIcon.icon" >/dev/null
    rm -f "$dist/Assets.car"

    # Cap the icns at 512px. The 1024px rendition is ~540 KB of PNG that the DMG
    # can't compress and that a menu-bar app never shows; dropping it roughly
    # quarters the icns with no visible difference at Finder sizes.
    local iconset="$dist/AppIcon.iconset"
    rm -rf "$iconset"
    iconutil -c iconset "$dist/AppIcon.icns" -o "$iconset"
    rm -f "$iconset/icon_512x512@2x.png"
    iconutil -c icns "$iconset" -o "$dist/AppIcon.icns"
    rm -rf "$iconset"
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
# Stages the app next to an /Applications symlink and builds a compressed DMG,
# branded with the app icon as the volume icon. The icon lives inside the image,
# so it survives signing + notarisation; Finder also adopts it for the .dmg file
# once the image has been mounted. Builds read-write first to flag the volume
# root as having a custom icon, then compresses to the final read-only image.
make_dmg() {
    local bundle="$1" dmg="$2"
    rm -f "$dmg"
    local staging
    staging="$(mktemp -d)"
    cp -R "$bundle" "$staging/"
    ln -s /Applications "$staging/Applications"

    local icns="$bundle/Contents/Resources/AppIcon.icns"
    [ -f "$icns" ] && cp "$icns" "$staging/.VolumeIcon.icns"

    local rw
    rw="$(mktemp -u).dmg"
    hdiutil create -volname "$APP_NAME" -srcfolder "$staging" -ov -format UDRW -o "$rw"
    if [ -f "$icns" ]; then
        local mnt
        mnt="$(mktemp -d)"
        hdiutil attach "$rw" -mountpoint "$mnt" -nobrowse -quiet
        SetFile -a C "$mnt"
        hdiutil detach "$mnt" -quiet
        rmdir "$mnt" 2>/dev/null || true
    fi
    hdiutil convert "$rw" -format UDZO -o "$dmg"
    rm -f "$rw"
    rm -rf "$staging"
}

# set_file_icon <icns> <file>
# Brands <file> with a custom Finder icon. This lives in the file's resource fork
# (com.apple.ResourceFork + FinderInfo), so it shows on the local artifact but is
# stripped by HTTP download — the make_dmg volume icon is what survives for users.
# Call AFTER signing/notarising/stapling: it touches only the resource fork, not
# the data fork, so the disk image's signature and staple stay valid.
set_file_icon() {
    local icns="$1" file="$2"
    [ -f "$icns" ] && [ -f "$file" ] || return 0
    swift - "$icns" "$file" <<'SWIFT'
import Cocoa
let img = NSImage(contentsOfFile: CommandLine.arguments[1])!
_ = NSWorkspace.shared.setIcon(img, forFile: CommandLine.arguments[2], options: [])
SWIFT
}
