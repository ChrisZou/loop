#!/bin/bash
# Build Loop.app, zip it for GitHub Releases. Optional notarization when
# LOOP_NOTARY_PROFILE is set (xcrun notarytool store-credentials profile).
set -euo pipefail
cd "$(dirname "$0")/.."
./build-app.sh
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/Loop.app/Contents/Info.plist 2>/dev/null || echo 1.0.0)"
STAGE="build/release"
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto build/Loop.app "$STAGE/Loop.app"
mkdir -p "$STAGE/Loop.app/Contents/Resources"
cp bin/loop "$STAGE/Loop.app/Contents/Resources/loop"
chmod +x "$STAGE/Loop.app/Contents/Resources/loop"
# Also keep a top-level copy for non-cask unzip users.
cp bin/loop "$STAGE/loop"
chmod +x "$STAGE/loop"
(
  cd "$STAGE"
  ditto -c -k --keepParent Loop.app "Loop-${VERSION}-macos.zip"
)
ZIP="$STAGE/Loop-${VERSION}-macos.zip"
shasum -a 256 "$ZIP" | tee "$ZIP.sha256"
echo "Packed $ZIP"

if [[ -n "${LOOP_NOTARY_PROFILE:-}" ]]; then
  echo "Submitting to Apple notary service (profile=$LOOP_NOTARY_PROFILE)…"
  xcrun notarytool submit "$ZIP" --keychain-profile "$LOOP_NOTARY_PROFILE" --wait
  xcrun stapler staple "$STAGE/Loop.app"
  (
    cd "$STAGE"
    rm -f "Loop-${VERSION}-macos.zip" "Loop-${VERSION}-macos.zip.sha256"
    ditto -c -k --keepParent Loop.app "Loop-${VERSION}-macos.zip"
  )
  shasum -a 256 "$ZIP" | tee "$ZIP.sha256"
  echo "Notarized and re-packed $ZIP"
else
  echo "Skip notarization (set LOOP_NOTARY_PROFILE to enable)." >&2
fi
