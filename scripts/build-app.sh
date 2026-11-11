#!/usr/bin/env bash
# Builds JARVIS.app and JARVIS.zip in ./build.
#
# Usage: ./scripts/build-app.sh [git ref, e.g. v0.1.0]
# Works with the free Command Line Tools (xcode-select --install) or Xcode.
set -euo pipefail

cd "$(dirname "$0")/.."

REF="${1:-}"
VERSION="0.1.0"
if [[ "$REF" =~ ^v([0-9]+\.[0-9]+\.[0-9]+) ]]; then
  VERSION="${BASH_REMATCH[1]}"
fi
BUILD_NUMBER="${GITHUB_RUN_NUMBER:-1}"

echo "==> Compiling (release, Apple silicon)"
swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

APP="build/JARVIS.app"
echo "==> Assembling $APP"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/JARVIS" "$APP/Contents/MacOS/JARVIS"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" \
  Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"

echo "==> Signing (ad-hoc: free, no Apple developer account)"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --verbose "$APP"

echo "==> Zipping"
(cd build && ditto -c -k --keepParent JARVIS.app JARVIS.zip)

echo "Built $APP and build/JARVIS.zip (version $VERSION, build $BUILD_NUMBER)"
