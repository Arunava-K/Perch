#!/usr/bin/env bash
#
# Build, sign, notarize, and package Mybar for direct (non-App-Store) distribution.
#
# Prerequisites (one-time — see RELEASING.md):
#   - A "Developer ID Application" certificate in your login keychain.
#   - A notarytool keychain profile: `xcrun notarytool store-credentials MybarNotary`.
#   - Sparkle keys generated and SUPublicEDKey set in project.yml.
#
# Usage:
#   DEV_ID="Developer ID Application: Your Name (TEAMID)" ./scripts/release.sh
#
set -euo pipefail

APP_NAME="Mybar"
SCHEME="Mybar"
CONFIG="Release"
BUILD_DIR="build/release"
NOTARY_PROFILE="${NOTARY_PROFILE:-MybarNotary}"

: "${DEV_ID:?Set DEV_ID to your 'Developer ID Application: … (TEAMID)' identity}"

cd "$(dirname "$0")/.."

echo "==> Regenerating project"
xcodegen generate

echo "==> Building $CONFIG"
xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$SCHEME" -configuration "$CONFIG" \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$DEV_ID" \
  build

APP="$BUILD_DIR/Build/Products/$CONFIG/$APP_NAME.app"

echo "==> Signing (hardened runtime, including embedded frameworks)"
# Sign nested frameworks first, then the app, with the hardened runtime enabled
# (required for notarization).
find "$APP/Contents/Frameworks" -name "*.framework" -maxdepth 1 -print0 2>/dev/null \
  | xargs -0 -I{} codesign --force --options runtime --timestamp --sign "$DEV_ID" {}
codesign --force --options runtime --timestamp --deep --sign "$DEV_ID" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "==> Packaging"
ZIP="$APP_NAME.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Notarizing (this can take a few minutes)"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling + repackaging"
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Done: $ZIP"
echo "    Next: sign the zip for Sparkle and update appcast.xml (see RELEASING.md):"
echo "      ./bin/sign_update $ZIP"
