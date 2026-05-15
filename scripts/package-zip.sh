#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/Reservoir.app"
ZIP_PATH="$ROOT_DIR/dist/Reservoir.zip"

cd "$ROOT_DIR"

./scripts/build-app.sh

xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"
COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent "$APP_DIR" "$ZIP_PATH"
rm -rf "$APP_DIR"

echo "Packaged $ZIP_PATH"
