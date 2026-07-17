#!/usr/bin/env bash
#
# Build, sign, notarize, and package Perch for direct (non-App-Store) distribution.
#
# Prerequisites (one-time — see RELEASING.md):
#   - A "Developer ID Application" certificate in your login keychain.
#   - A notarytool keychain profile: `xcrun notarytool store-credentials PerchNotary`.
#   - Sparkle keys generated and SUPublicEDKey + SUFeedURL set in project.yml.
#
# Usage:
#   DEV_ID="Developer ID Application: Your Name (TEAMID)" ./scripts/release.sh
#
set -euo pipefail

APP_NAME="Perch"
SCHEME="Perch"
CONFIG="Release"
BUILD_DIR="build/release"
NOTARY_PROFILE="${NOTARY_PROFILE:-PerchNotary}"
ALLOW_UNCONFIGURED_SPARKLE="${ALLOW_UNCONFIGURED_SPARKLE:-0}"

: "${DEV_ID:?Set DEV_ID to your 'Developer ID Application: … (TEAMID)' identity}"

cd "$(dirname "$0")/.."

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: required command not found: $1" >&2
    exit 1
  }
}

echo "==> Preflight"
require_cmd xcodegen
require_cmd xcodebuild
require_cmd codesign
require_cmd ditto
require_cmd lipo
require_cmd plutil
require_cmd xcrun
require_cmd python3

if ! security find-identity -v -p codesigning | grep -F "$DEV_ID" >/dev/null; then
  echo "error: signing identity not found in keychain: $DEV_ID" >&2
  echo "       Run: security find-identity -v -p codesigning" >&2
  exit 1
fi

FEED_URL="$(python3 - <<'PY'
import re, pathlib
text = pathlib.Path("project.yml").read_text()
m = re.search(r'SUFeedURL:\s*"([^"]*)"', text)
print(m.group(1) if m else "")
PY
)"
PUBLIC_KEY="$(python3 - <<'PY'
import re, pathlib
text = pathlib.Path("project.yml").read_text()
m = re.search(r'SUPublicEDKey:\s*"([^"]*)"', text)
print(m.group(1) if m else "")
PY
)"

if [[ -z "$PUBLIC_KEY" || "$FEED_URL" == *"example.com"* ]]; then
  if [[ "$ALLOW_UNCONFIGURED_SPARKLE" != "1" ]]; then
    echo "error: Sparkle is not production-configured in project.yml" >&2
    echo "       Set SUPublicEDKey and a real SUFeedURL (see RELEASING.md)." >&2
    echo "       To package anyway without auto-update: ALLOW_UNCONFIGURED_SPARKLE=1 $0" >&2
    exit 1
  fi
  echo "warning: shipping without a configured Sparkle feed/key"
fi

echo "==> Regenerating project"
xcodegen generate

echo "==> Building universal $CONFIG"
xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$SCHEME" -configuration "$CONFIG" \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$BUILD_DIR" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$DEV_ID" \
  ENABLE_HARDENED_RUNTIME=YES \
  build

APP="$BUILD_DIR/Build/Products/$CONFIG/$APP_NAME.app"
BIN="$APP/Contents/MacOS/$APP_NAME"
PLIST="$APP/Contents/Info.plist"

[[ -d "$APP" ]] || { echo "error: app bundle missing: $APP" >&2; exit 1; }
[[ -f "$BIN" ]] || { echo "error: binary missing: $BIN" >&2; exit 1; }

ARCHS="$(lipo -archs "$BIN" 2>/dev/null || true)"
if ! echo " $ARCHS " | grep -q " arm64 " || ! echo " $ARCHS " | grep -q " x86_64 "; then
  echo "error: expected universal binary (arm64 + x86_64), got: ${ARCHS:-unknown}" >&2
  exit 1
fi
echo "    Architectures: $ARCHS"

if [[ -n "$PUBLIC_KEY" && "$FEED_URL" != *"example.com"* ]]; then
  BUNDLE_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$PLIST" 2>/dev/null || true)"
  BUNDLE_FEED="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$PLIST" 2>/dev/null || true)"
  [[ "$BUNDLE_KEY" == "$PUBLIC_KEY" ]] || {
    echo "error: bundled SUPublicEDKey does not match project.yml" >&2
    exit 1
  }
  [[ "$BUNDLE_FEED" == "$FEED_URL" ]] || {
    echo "error: bundled SUFeedURL does not match project.yml" >&2
    exit 1
  }
fi

echo "==> Signing (hardened runtime, including embedded frameworks)"
# Sign nested frameworks first, then the app, with the hardened runtime enabled
# (required for notarization).
if [[ -d "$APP/Contents/Frameworks" ]]; then
  find "$APP/Contents/Frameworks" -name "*.framework" -maxdepth 1 -print0 2>/dev/null \
    | xargs -0 -I{} codesign --force --options runtime --timestamp --sign "$DEV_ID" {}
fi
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
xcrun stapler validate "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Gatekeeper assessment"
spctl --assess --type execute --verbose=4 "$APP"

echo "==> Done: $ZIP"
echo "    Architectures: $ARCHS"
echo "    Next: sign the zip for Sparkle and update appcast.xml (see RELEASING.md)."
if [[ -x "./bin/sign_update" ]]; then
  echo "      ./bin/sign_update $ZIP"
else
  echo "      # Install Sparkle's sign_update into ./bin, then:"
  echo "      ./bin/sign_update $ZIP"
fi
