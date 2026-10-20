#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="build/Loop.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# A new file, not an overwrite: a review window still running the old binary keeps a valid code signature.
rm -f "$APP/Contents/MacOS/Loop"
cp "$BIN_DIR/Loop" "$APP/Contents/MacOS/Loop"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.chris.loop</string>
    <key>CFBundleName</key><string>Loop</string>
    <key>CFBundleDisplayName</key><string>Loop</string>
    <key>CFBundleExecutable</key><string>Loop</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
    <key>CFBundleLocalizations</key><array><string>zh_CN</string></array>
</dict>
</plist>
PLIST
SIGNING_IDENTITY="Developer ID Application: Hangzhou Xinyouduzhong Technology Co., Ltd. (W4SX57U6XB)"
if security find-identity -v -p codesigning | grep -Fq "\"$SIGNING_IDENTITY\""; then
    codesign --force --deep -s "$SIGNING_IDENTITY" "$APP"
else
    echo "Signing identity not found, falling back to ad-hoc signing" >&2
    codesign --force --deep -s - "$APP"
fi
echo "Built $APP"
