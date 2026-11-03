#!/bin/bash
# Builds MacPower.app. Requires only the Xcode Command Line Tools.
set -euo pipefail

cd "$(dirname "$0")"

APP="MacPower.app"

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/MacPower" "$APP/Contents/MacOS/MacPower"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature; enough for a locally built menu bar app.
codesign --force --sign - "$APP"

echo "Built $APP — run it with: open $APP"
