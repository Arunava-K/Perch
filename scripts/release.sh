#!/usr/bin/env bash
#
# Build and package Perch for unsigned (free) distribution.
#
# The resulting .dmg is NOT signed or notarized. Users must bypass
# Gatekeeper once:
#   xattr -dr com.apple.quarantine /Applications/Perch.app
#
# Usage:
#   ./scripts/release.sh
#
set -euo pipefail

APP_NAME="Perch"
SCHEME="Perch"
CONFIG="Release"
BUILD_DIR="build/release"

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

echo "==> Regenerating project"
xcodegen generate

echo "==> Building universal $CONFIG (unsigned)"
xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$SCHEME" -configuration "$CONFIG" \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$BUILD_DIR" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

APP="$BUILD_DIR/Build/Products/$CONFIG/$APP_NAME.app"

[[ -d "$APP" ]] || { echo "error: app bundle missing: $APP" >&2; exit 1; }

echo "==> Packaging as DMG"
DMG="$APP_NAME.dmg"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$APP" -ov -format UDZO "$DMG"

echo "==> Done: $DMG"
echo ""
echo "    Upload $DMG to a GitHub Release (or share directly)."
echo ""
echo "    Users MUST bypass Gatekeeper on first launch:"
echo "      xattr -dr com.apple.quarantine /Applications/Perch.app"
echo "    Or use Homebrew with --no-quarantine."
echo ""
