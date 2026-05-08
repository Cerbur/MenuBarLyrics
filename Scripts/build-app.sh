#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
APP_NAME="MenuBarLyrics"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

cd "$ROOT_DIR"

swift build -c release

BIN_DIR=$(swift build -c release --show-bin-path)
EXECUTABLE="$BIN_DIR/$APP_NAME"

if [ ! -x "$EXECUTABLE" ]; then
	echo "error: executable not found at $EXECUTABLE" >&2
	exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

cp "$ROOT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$EXECUTABLE" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

if command -v codesign >/dev/null 2>&1; then
	codesign --force --sign - "$APP_DIR" >/dev/null
fi

echo "Built $APP_DIR"
