#!/bin/bash
# Builds a styled drag-to-Applications disk image.
set -euo pipefail

cd "$(dirname "$0")"

APP="MacPower.app"
DMG="MacPower.dmg"
VOLUME_NAME="MacPower"
WORK_DIR="$(mktemp -d)"
STAGING="$WORK_DIR/staging"
RW_DMG="$WORK_DIR/MacPower-rw.dmg"
MOUNT_POINT=""

cleanup() {
    if [[ -n "$MOUNT_POINT" ]] && mount | rg -Fq "on $MOUNT_POINT "; then
        hdiutil detach "$MOUNT_POINT" -force >/dev/null 2>&1 || true
    fi
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

./build.sh

mkdir -p "$STAGING/.background"
ditto "$APP" "$STAGING/$APP"
cp "Resources/DMGBackground.png" "$STAGING/.background/background.png"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING" \
    -format UDRW \
    -ov \
    "$RW_DMG" >/dev/null

if [[ -d "/Volumes/$VOLUME_NAME" ]]; then
    hdiutil detach "/Volumes/$VOLUME_NAME" >/dev/null
fi

MOUNT_POINT="$(hdiutil attach \
    -readwrite \
    -noverify \
    -noautoopen \
    "$RW_DMG" | awk 'END {print $NF}')"

sleep 1

osascript <<EOF
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set pathbar visible of container window to false
        set bounds of container window to {140, 140, 800, 560}

        set viewOptions to icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 104
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:background.png"

        set position of item "$APP" of container window to {165, 205}
        set position of item "Applications" of container window to {495, 205}

        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
EOF

sync
hdiutil detach "$MOUNT_POINT" >/dev/null

hdiutil convert \
    "$RW_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    -o "$DMG" >/dev/null

echo "Built $DMG — open it and drag MacPower to Applications."
