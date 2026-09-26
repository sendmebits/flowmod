#!/bin/bash
# Package a signed FlowMod.app for release.
#
#   scripts/create-dmg.sh /path/to/flowmod.app [output-directory]
#
# Writes two files:
#   FlowMod.dmg   First-time download. Drag the app onto Applications.
#   flowmod.zip   In-app update. UpdateManager looks for this asset by name.
#
# The app you pass in must already be signed with Developer ID Application.
# This script does not re-sign it. Set these to sign, notarize, and staple
# the disk image, and to notarize the update zip:
#
#   export FLOWMOD_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   export FLOWMOD_NOTARY_PROFILE="flowmod-notary"
#
# Create the notary profile once with:
#   xcrun notarytool store-credentials "$FLOWMOD_NOTARY_PROFILE"

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Usage: scripts/create-dmg.sh /path/to/flowmod.app [output-directory]" >&2
    exit 1
fi

APP_PATH=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
OUT_DIR=${2:-build}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
VOLUME_NAME="FlowMod"
WINDOW_WIDTH=660
WINDOW_HEIGHT=400
WINDOW_X=200
WINDOW_Y=120

if [[ ! -d "$APP_PATH" || "${APP_PATH##*.}" != "app" ]]; then
    echo "Not an application bundle: $APP_PATH" >&2
    exit 1
fi

mkdir -p "$OUT_DIR"
OUT_DIR=$(cd "$OUT_DIR" && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/flowmod-dmg.XXXXXX")
RW_DMG="$WORK/flowmod-rw.dmg"
STAGING="$WORK/stage"
BACKGROUND="$WORK/background.png"

DEVICE=""
cleanup() {
    if [[ -n "$DEVICE" ]]; then
        diskutil eject "$DEVICE" >/dev/null 2>&1 || true
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT

mkdir -p "$STAGING"
# Finder shows the file name. Ship FlowMod.app even when the build product is flowmod.app.
# ditto keeps the existing Developer ID signature and staple.
ditto "$APP_PATH" "$STAGING/FlowMod.app"

if [[ -n "${FLOWMOD_NOTARY_PROFILE:-}" ]]; then
    if ! codesign -dv --verbose=4 "$STAGING/FlowMod.app" 2>&1 | grep -q "Authority=Developer ID Application"; then
        echo "Refusing to notarize: FlowMod.app is not signed with Developer ID Application." >&2
        exit 1
    fi
fi

echo "Writing $OUT_DIR/flowmod.zip"
rm -f "$OUT_DIR/flowmod.zip"
# --norsrc keeps the code signature and omits AppleDouble sidecars. Unzipping
# those sidecars into the bundle makes the signature fail validation.
ditto -c -k --keepParent --norsrc "$STAGING/FlowMod.app" "$OUT_DIR/flowmod.zip"

swift "$ROOT/scripts/render-dmg-background.swift" "$BACKGROUND" "$WINDOW_WIDTH" "$WINDOW_HEIGHT"

APP_KB=$(du -sk "$STAGING/FlowMod.app" | awk '{print $1}')
DMG_KB=$((APP_KB + 30000))
diskutil image create blank --size "${DMG_KB}k" --volumeName "$VOLUME_NAME" --fs APFS --format RAW "$RW_DMG" >/dev/null
ATTACH_INFO=$(diskutil image attach "$RW_DMG")
DEVICE=$(printf '%s\n' "$ATTACH_INFO" | awk '/\/Volumes\// {print $1; exit}')
MOUNT=$(printf '%s\n' "$ATTACH_INFO" | awk '/\/Volumes\// {print $3; exit}')
if [[ -z "$DEVICE" || -z "$MOUNT" || ! -d "$MOUNT" ]]; then
    echo "Could not mount the disk image." >&2
    exit 1
fi
mkdir -p "$MOUNT/.background"
cp "$BACKGROUND" "$MOUNT/.background/background.png"
chflags hidden "$MOUNT/.background"
ditto "$STAGING/FlowMod.app" "$MOUNT/FlowMod.app"
ln -s /Applications "$MOUNT/Applications"

osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set theWindow to container window
        set current view of theWindow to icon view
        set toolbar visible of theWindow to false
        set statusbar visible of theWindow to false
        set bounds of theWindow to {$WINDOW_X, $WINDOW_Y, $((WINDOW_X + WINDOW_WIDTH)), $((WINDOW_Y + WINDOW_HEIGHT))}
        set theViewOptions to the icon view options of theWindow
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 128
        set background picture of theViewOptions to file ".background:background.png"
        set position of item "FlowMod.app" of theWindow to {165, 175}
        set position of item "Applications" of theWindow to {495, 175}
        update without registering applications
        delay 1
        set bounds of theWindow to {$WINDOW_X, $WINDOW_Y, $((WINDOW_X + WINDOW_WIDTH)), $((WINDOW_Y + WINDOW_HEIGHT))}
        close theWindow
    end tell
end tell
APPLESCRIPT

# Finder writes .DS_Store after the window closes. Wait so the icon layout is saved.
sleep 3
sync
# Don't follow the Applications symlink into the real Applications folder.
chmod -R go-w "$MOUNT/FlowMod.app" "$MOUNT/.background" || true
diskutil eject "$MOUNT" >/dev/null
DEVICE=""

echo "Writing $OUT_DIR/FlowMod.dmg"
rm -f "$OUT_DIR/FlowMod.dmg"
if ! convert_output=$(diskutil image create from --format UDZO "$RW_DMG" "$OUT_DIR/FlowMod.dmg" 2>&1); then
    printf '%s\n' "$convert_output" >&2
    exit 1
fi

if [[ -n "${FLOWMOD_SIGN_IDENTITY:-}" ]]; then
    echo "Signing FlowMod.dmg"
    codesign --sign "$FLOWMOD_SIGN_IDENTITY" --timestamp "$OUT_DIR/FlowMod.dmg"
fi

if [[ -n "${FLOWMOD_NOTARY_PROFILE:-}" ]]; then
    if [[ -z "${FLOWMOD_SIGN_IDENTITY:-}" ]]; then
        echo "Set FLOWMOD_SIGN_IDENTITY before notarizing. An unsigned disk image cannot be stapled." >&2
        exit 1
    fi
    echo "Notarizing flowmod.zip"
    xcrun notarytool submit "$OUT_DIR/flowmod.zip" --keychain-profile "$FLOWMOD_NOTARY_PROFILE" --wait
    echo "Notarizing and stapling FlowMod.dmg"
    xcrun notarytool submit "$OUT_DIR/FlowMod.dmg" --keychain-profile "$FLOWMOD_NOTARY_PROFILE" --wait
    xcrun stapler staple "$OUT_DIR/FlowMod.dmg"
    xcrun stapler validate "$OUT_DIR/FlowMod.dmg"
else
    echo "FlowMod.dmg is not notarized."
    echo "Set FLOWMOD_SIGN_IDENTITY and FLOWMOD_NOTARY_PROFILE, then run this script again to sign, notarize, and staple it."
fi

echo "Release files:"
echo "  $OUT_DIR/FlowMod.dmg"
echo "  $OUT_DIR/flowmod.zip"
