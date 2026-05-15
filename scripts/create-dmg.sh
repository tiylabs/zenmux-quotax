#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
  printf 'Usage: %s <output-dmg> <app-path> <background-png>\n' "$0" >&2
  exit 64
fi

OUTPUT_DMG="$1"
APP_PATH="$2"
BACKGROUND_PATH="$3"
APP_NAME="Quotax.app"
VOLUME_NAME="Quotax"
WINDOW_X=100
WINDOW_Y=100
WINDOW_WIDTH=640
WINDOW_HEIGHT=420
ICON_SIZE=96
TEXT_SIZE=14
APP_ICON_X=176
APP_ICON_Y=230
APPLICATIONS_ICON_X=459
APPLICATIONS_ICON_Y=230
BACKGROUND_ICON_X=96
BACKGROUND_ICON_Y=92

if [ ! -d "$APP_PATH" ]; then
  printf 'Missing app bundle: %s\n' "$APP_PATH" >&2
  exit 66
fi

if [ ! -f "$BACKGROUND_PATH" ]; then
  printf 'Missing DMG background: %s\n' "$BACKGROUND_PATH" >&2
  exit 66
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/quotax-dmg.XXXXXX")"
STAGING_DIR="$TMP_DIR/staging"
RW_DMG="$TMP_DIR/Quotax-rw.dmg"
BACKGROUND_NAME="DmgBackground.tiff"
BACKGROUND_1X_PNG="$TMP_DIR/DmgBackground@1x.png"
BACKGROUND_1X_TIFF="$TMP_DIR/DmgBackground@1x.tiff"
BACKGROUND_2X_TIFF="$TMP_DIR/DmgBackground@2x.tiff"
DEV_NAME=""
MOUNT_DIR=""

cleanup() {
  if [ -n "$DEV_NAME" ]; then
    hdiutil detach "$DEV_NAME" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$STAGING_DIR/.background" "$(dirname "$OUTPUT_DMG")"
ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME"
ln -s /Applications "$STAGING_DIR/Applications"
/usr/bin/sips -z "$WINDOW_HEIGHT" "$WINDOW_WIDTH" "$BACKGROUND_PATH" --out "$BACKGROUND_1X_PNG" >/dev/null
/usr/bin/sips -s format tiff "$BACKGROUND_1X_PNG" --out "$BACKGROUND_1X_TIFF" >/dev/null
/usr/bin/sips -s format tiff "$BACKGROUND_PATH" --out "$BACKGROUND_2X_TIFF" >/dev/null
/usr/bin/tiffutil -cathidpicheck "$BACKGROUND_1X_TIFF" "$BACKGROUND_2X_TIFF" -out "$STAGING_DIR/.background/$BACKGROUND_NAME" >/dev/null
chflags hidden "$STAGING_DIR/.background" || true

rm -f "$OUTPUT_DMG" "$RW_DMG"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDRW \
  -fs HFS+ \
  "$RW_DMG" >/dev/null

DEV_NAME="$(hdiutil attach \
  -readwrite \
  -noverify \
  -noautoopen \
  -nobrowse \
  "$RW_DMG" | awk '/^\/dev\// { print $1; exit }')"

if [ -z "$DEV_NAME" ]; then
  printf 'Failed to mount temporary DMG.\n' >&2
  exit 1
fi

MOUNT_DIR="$(df | awk -v dev="$DEV_NAME" '$1 == dev || index($1, dev) == 1 { print $9; exit }')"
if [ -z "$MOUNT_DIR" ]; then
  MOUNT_DIR="$(mount | awk -v dev="$DEV_NAME" '$1 == dev || index($1, dev) == 1 { sub(/^on /, "", $3); print $3; exit }')"
fi
if [ -z "$MOUNT_DIR" ] || [ ! -d "$MOUNT_DIR" ]; then
  printf 'Failed to resolve mount directory for %s.\n' "$DEV_NAME" >&2
  exit 1
fi

VOLUME_NAME="$(basename "$MOUNT_DIR")"

# Keep the background directory hidden for normal Finder users. If a developer has
# Finder hidden files enabled, it is still positioned inside the window so it will
# not expand the scrollable canvas.
chflags hidden "$MOUNT_DIR/.background" || true

osascript <<APPLESCRIPT
set volumeName to "$VOLUME_NAME"
set backgroundName to "$BACKGROUND_NAME"
set windowX to $WINDOW_X
set windowY to $WINDOW_Y
set windowWidth to $WINDOW_WIDTH
set windowHeight to $WINDOW_HEIGHT
set appIconX to $APP_ICON_X
set appIconY to $APP_ICON_Y
set applicationsIconX to $APPLICATIONS_ICON_X
set applicationsIconY to $APPLICATIONS_ICON_Y
set backgroundIconX to $BACKGROUND_ICON_X
set backgroundIconY to $BACKGROUND_ICON_Y
set mountPath to "$MOUNT_DIR"

set windowRight to windowX + windowWidth
set windowBottom to windowY + windowHeight

tell application "Finder"
    tell disk volumeName
        open
        tell container window
            set current view to icon view
            set toolbar visible to false
            set statusbar visible to false
            set bounds to {windowX, windowY, windowRight, windowBottom}
        end tell

        set iconOptions to icon view options of container window
        tell iconOptions
            set arrangement to not arranged
            set icon size to $ICON_SIZE
            set text size to $TEXT_SIZE
            set background picture to (POSIX file (mountPath & "/.background/" & backgroundName))
        end tell

        set position of item "$APP_NAME" to {appIconX, appIconY}
        set position of item "Applications" to {applicationsIconX, applicationsIconY}
        set position of item ".background" to {backgroundIconX, backgroundIconY}
        set extension hidden of item "$APP_NAME" to true

        update without registering applications
        delay 1
        close
        open
        delay 1
        tell container window
            set current view to icon view
            set toolbar visible to false
            set statusbar visible to false
            set bounds to {windowX, windowY, windowRight, windowBottom}
        end tell
        close
    end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$DEV_NAME" >/dev/null
DEV_NAME=""

hdiutil convert "$RW_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  -o "$OUTPUT_DMG" >/dev/null

printf 'Created %s\n' "$OUTPUT_DMG"
