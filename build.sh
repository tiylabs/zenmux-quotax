#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Quotax"
BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
EXECUTABLE="$MACOS/$APP_NAME"
ARCH="${ARCH:-$(uname -m)}"

rm -rf "$BUILD_DIR"
mkdir -p "$MACOS" "$RESOURCES"

SWIFT_FILES=("$ROOT"/Sources/*.swift)
/usr/bin/swiftc \
  -target "$ARCH-apple-macosx15.7" \
  -parse-as-library \
  -module-name zenmux_monitor \
  -O \
  -framework AppKit \
  -framework SwiftUI \
  -framework Foundation \
  "${SWIFT_FILES[@]}" \
  -o "$EXECUTABLE"

cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
printf 'APPL????' > "$CONTENTS/PkgInfo"

/usr/bin/plutil -lint "$CONTENTS/Info.plist"
/usr/bin/codesign --force --sign - "$APP_DIR" >/dev/null

printf 'Built %s\n' "$APP_DIR"
