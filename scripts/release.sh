#!/usr/bin/env bash
# Builds, Developer ID-signs, notarizes, and staples a distributable DMG.
#
# One-time setup (your Apple credentials, run it yourself):
#   xcrun notarytool store-credentials desktoppet \
#     --apple-id "<your-apple-id-email>" \
#     --team-id 9D7HY2JCGN \
#     --password "<app-specific-password>"
# Create the app-specific password at https://appleid.apple.com → Sign-In & Security.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/build/DesktopPet.app"
IDENTITY="Developer ID Application: Dat Nguyen (9D7HY2JCGN)"
PROFILE="${NOTARY_PROFILE:-desktoppet}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' scripts/AppInfo.plist)"

echo "==> Building DesktopPet.app"
./scripts/build-app.sh release

echo "==> Signing with Developer ID (hardened runtime)"
# Sign any nested bundles first, then the main executable, then the app.
while IFS= read -r -d '' nested; do
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$nested"
done < <(find "$APP/Contents/Resources" -name "*.bundle" -print0 2>/dev/null)

# Sparkle.framework ships nested XPC services and helper apps that each must be
# signed inside-out (deepest first) with the hardened runtime before the app.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPARKLE" ]; then
    SV="$SPARKLE/Versions/B"
    for nested in \
        "$SV/XPCServices/Downloader.xpc" \
        "$SV/XPCServices/Installer.xpc" \
        "$SV/Autoupdate" \
        "$SV/Updater.app"; do
        codesign --force --options runtime --timestamp --sign "$IDENTITY" "$nested"
    done
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$SPARKLE"
fi

codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP/Contents/MacOS/desktoppet"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

DMG="$ROOT/build/DesktopPet-$VERSION.dmg"
STAGE="$ROOT/build/dmg"

make_dmg() {
    rm -f "$DMG"; rm -rf "$STAGE"; mkdir -p "$STAGE"
    # ditto preserves the stapled notarization ticket inside the app bundle.
    ditto "$APP" "$STAGE/DesktopPet.app"
    # create-dmg lays out a branded install window: custom background, the app on
    # the left, an arrow, and the Applications drop target on the right.
    create-dmg \
        --volname "DesktopPet" \
        --background "$ROOT/scripts/dmg-background.tiff" \
        --window-pos 200 120 \
        --window-size 660 420 \
        --icon-size 120 \
        --icon "DesktopPet.app" 180 206 \
        --app-drop-link 480 206 \
        --hide-extension "DesktopPet.app" \
        --no-internet-enable \
        "$DMG" "$STAGE" >/dev/null
}

if [ -n "${SKIP_NOTARIZE:-}" ]; then
    echo "==> Skipping notarization (SKIP_NOTARIZE set); signed-only build"
    echo "==> Building DMG"
    make_dmg
else
    # Notarize the APP first and staple it, so the ticket is embedded in the
    # bundle that actually ships. Building the DMG before stapling (the old bug)
    # left every distributed copy un-stapled, so Gatekeeper had to verify online
    # and blocked the app whenever that check lagged.
    echo "==> Notarizing the app (this can take a few minutes)"
    ZIP="$ROOT/build/DesktopPet-$VERSION-app.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
    xcrun stapler staple "$APP"
    rm -f "$ZIP"

    echo "==> Building DMG from the stapled app"
    make_dmg

    echo "==> Notarizing the DMG"
    xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
    xcrun stapler staple "$DMG"
fi

echo "==> Signing update for Sparkle appcast"
SIGN_UPDATE="$(find "$ROOT/.build/artifacts" -name sign_update -path '*Sparkle*' 2>/dev/null | head -1)"
ED_ATTRS="$("$SIGN_UPDATE" "$DMG")"   # emits: sparkle:edSignature="..." length="..."

echo "==> Done"
echo "DMG:    $DMG"
echo "SHA256: $(shasum -a 256 "$DMG" | awk '{print $1}')"
echo ""
echo "Appcast <item> (paste into docs/appcast.xml, then commit + push for Pages):"
cat <<EOF
        <item>
            <title>$VERSION</title>
            <sparkle:version>$VERSION</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
            <enclosure url="https://github.com/Imzl-zl/desktop-pet/releases/download/v$VERSION/DesktopPet-$VERSION.dmg"
                       $ED_ATTRS type="application/octet-stream" />
        </item>
EOF
