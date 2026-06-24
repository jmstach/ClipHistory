#!/usr/bin/env bash
set -euo pipefail

# Notarised release: Developer ID + hardened runtime, notarise + staple both the
# app and the DMG so it opens on any Mac with no Gatekeeper warning, fully offline.
#
# One-time prerequisite — store notarisation credentials in the keychain:
#   xcrun notarytool store-credentials "ClipHistoryNotary" \
#     --apple-id "<your-apple-id>" --team-id "D25B8VCSB7" \
#     --password "<app-specific-password>"
# (Generate the app-specific password at https://appleid.apple.com → Sign-In & Security.)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib.sh"

DIST="$ROOT/dist"
APP_BUNDLE="$DIST/$APP_NAME.app"
DMG="$DIST/$APP_NAME.dmg"

# Fail early with a clear message if the notary profile isn't set up yet.
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "✗  notarytool profile '$NOTARY_PROFILE' not found." >&2
    echo "   Set it up once (see the comment at the top of this script), then re-run." >&2
    exit 1
fi

cd "$ROOT"

# ── 1. Clean release build ────────────────────────────────────────────────────
echo "▸ Building release binary…"
swift build -c release

# ── 2. Icon ───────────────────────────────────────────────────────────────────
echo "▸ Generating icons…"
mkdir -p "$DIST"
swift scripts/generate-icons.swift "$DIST"
iconutil -c icns "$DIST/AppIcon.iconset" -o "$DIST/AppIcon.icns"
rm -rf "$DIST/AppIcon.iconset"

# ── 3. Assemble + sign with hardened runtime ──────────────────────────────────
echo "▸ Assembling + signing (Developer ID, hardened runtime)…"
assemble_bundle ".build/release/$APP_NAME" "$APP_BUNDLE" "$DIST/AppIcon.icns"
codesign --force --timestamp --options runtime --sign "$DEV_ID" "$APP_BUNDLE"
codesign --verify --strict --verbose=2 "$APP_BUNDLE"

# ── 4. Notarise the app, then staple its ticket ───────────────────────────────
echo "▸ Notarising app (this can take a few minutes)…"
APP_ZIP="$DIST/$APP_NAME-app.zip"
rm -f "$APP_ZIP"
ditto -c -k --keepParent "$APP_BUNDLE" "$APP_ZIP"
xcrun notarytool submit "$APP_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_BUNDLE"
rm -f "$APP_ZIP"

# ── 5. Build the DMG from the stapled app, sign + notarise + staple it too ─────
echo "▸ Creating, signing + notarising DMG…"
make_dmg "$APP_BUNDLE" "$DMG"
# Sign the disk image as well, so Gatekeeper assessment of the DMG is unambiguous.
codesign --force --timestamp --sign "$DEV_ID" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

# ── 6. Verify Gatekeeper acceptance ───────────────────────────────────────────
echo "▸ Verifying…"
spctl -a -t exec -vvv "$APP_BUNDLE" 2>&1 | sed 's/^/   /'
spctl -a -t open --context context:primary-signature -vvv "$DMG" 2>&1 | sed 's/^/   /'
xcrun stapler validate "$DMG"

# ── 7. Publish to Cloudflare R2 (DMG + appcast.json on stable keys) ────────────
echo "▸ Writing appcast.json + uploading to R2…"
APPCAST="$DIST/appcast.json"
cat > "$APPCAST" <<EOF
{
  "version": "$VERSION",
  "url": "$DOWNLOAD_BASE/$APP_NAME.dmg",
  "notesURL": "$NOTES_URL"
}
EOF

if command -v wrangler >/dev/null 2>&1; then
    wrangler r2 object put "$R2_BUCKET/$APP_NAME.dmg" --file "$DMG" --remote
    wrangler r2 object put "$R2_BUCKET/appcast.json" --file "$APPCAST" \
        --content-type application/json --remote
    echo "✓  Uploaded $APP_NAME.dmg + appcast.json to R2 ($R2_BUCKET)."
else
    echo "⚠  wrangler not found — DMG + appcast built locally but NOT uploaded. Run:" >&2
    echo "   wrangler r2 object put $R2_BUCKET/$APP_NAME.dmg --file $DMG --remote" >&2
    echo "   wrangler r2 object put $R2_BUCKET/appcast.json --file $APPCAST --content-type application/json --remote" >&2
fi

echo ""
echo "✓  $DMG — notarised & stapled, opens with no Gatekeeper warning."
echo "   Published to $DOWNLOAD_BASE/  (update check reads appcast.json there)."
echo "   Recipients still grant Accessibility once for the popup keyboard to work."
