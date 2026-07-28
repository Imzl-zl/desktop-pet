#!/usr/bin/env bash
# Builds DesktopPet.app and a DMG. Signs with a Developer ID and notarizes when
# the corresponding env vars (from CI secrets) are present; otherwise produces
# an ad-hoc-signed DMG. Used by .github/workflows/release.yml.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/DesktopPet.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' scripts/AppInfo.plist)"

./scripts/build-app.sh release

if [ -n "${SIGN_IDENTITY:-}" ]; then
    echo "==> Signing with Developer ID"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP/Contents/MacOS/desktoppet"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
    codesign --verify --strict "$APP"
fi

DMG="build/DesktopPet-$VERSION.dmg"
STAGE="build/dmg"
rm -f "$DMG"; rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/DesktopPet.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "DesktopPet" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

if [ -n "${AC_API_KEY_P8:-}" ] && [ -n "${AC_KEY_ID:-}" ] && [ -n "${AC_ISSUER_ID:-}" ]; then
    echo "==> Notarizing"
    echo "$AC_API_KEY_P8" | base64 --decode > /tmp/ac_key.p8
    xcrun notarytool submit "$DMG" --key /tmp/ac_key.p8 --key-id "$AC_KEY_ID" --issuer "$AC_ISSUER_ID" --wait
    xcrun stapler staple "$DMG"
    rm -f /tmp/ac_key.p8
fi

echo "==> Built $DMG"
shasum -a 256 "$DMG"
