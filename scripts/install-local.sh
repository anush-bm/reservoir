#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ZIP_PATH="$ROOT_DIR/dist/Reservoir.zip"
INSTALL_DIR="$HOME/Applications"
APP_PATH="$INSTALL_DIR/Reservoir.app"
LEGACY_APP_PATH="/Applications/Reservoir.app"
DIST_APP_PATH="$ROOT_DIR/dist/Reservoir.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

cd "$ROOT_DIR"

if [ ! -f "$ZIP_PATH" ]; then
  ./scripts/package-zip.sh
fi

pkill -x Reservoir 2>/dev/null || true
sleep 0.5

mkdir -p "$INSTALL_DIR"
rm -rf "$APP_PATH"
rm -rf "$LEGACY_APP_PATH" 2>/dev/null || true
ditto -x -k "$ZIP_PATH" "$INSTALL_DIR"
xattr -cr "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

if [ -x "$LSREGISTER" ]; then
  "$LSREGISTER" -f "$APP_PATH" 2>/dev/null || true
fi

if ! open "$APP_PATH"; then
  echo "LaunchServices could not open Reservoir; starting the signed executable directly."
  "$APP_PATH/Contents/MacOS/Reservoir" >/dev/null 2>&1 &
fi

echo "Installed and opened $APP_PATH"
echo "Reservoir is a menu-bar app. Look for its compact percent badge in the macOS menu bar, not the Dock."
