#!/bin/bash
# Builds "TM Unstuck.app" into ./build. Pass --install to copy it to ~/Applications.
# Set VERSION (e.g. VERSION=1.2.0) to stamp the bundle version.
set -euo pipefail
cd "$(dirname "$0")"
VERSION="${VERSION:-1.0.0}"

swift build -c release

APP="build/TM Unstuck.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/TMUnstuck "$APP/Contents/MacOS/TMUnstuck"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>TM Unstuck</string>
    <key>CFBundleDisplayName</key><string>TM Unstuck</string>
    <key>CFBundleIdentifier</key><string>nl.bitform.tmunstuck</string>
    <key>CFBundleExecutable</key><string>TMUnstuck</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/TM Unstuck.app"
    cp -R "$APP" "$HOME/Applications/"
    echo "Installed to ~/Applications/TM Unstuck.app"
fi
