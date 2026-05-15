#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SVG="$ROOT_DIR/assets/ReservoirIcon.svg"
ICONSET="$ROOT_DIR/assets/Reservoir.iconset"
ICNS="$ROOT_DIR/assets/Reservoir.icns"
SOURCE_PNG="$ROOT_DIR/assets/ReservoirIcon-1024.png"

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

rsvg-convert -w 1024 -h 1024 "$SVG" -o "$SOURCE_PNG"

sips -z 16 16 "$SOURCE_PNG" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$SOURCE_PNG" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$SOURCE_PNG" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$SOURCE_PNG" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$SOURCE_PNG" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$SOURCE_PNG" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$SOURCE_PNG" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$SOURCE_PNG" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$SOURCE_PNG" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$SOURCE_PNG" --out "$ICONSET/icon_512x512@2x.png" >/dev/null

xattr -cr "$ICONSET"

node - "$ICONSET" "$ICNS" <<'NODE'
const fs = require("fs");
const path = require("path");

const iconset = process.argv[2];
const out = process.argv[3];
const entries = [
  ["icp4", "icon_16x16.png"],
  ["icp5", "icon_32x32.png"],
  ["icp6", "icon_32x32@2x.png"],
  ["ic07", "icon_128x128.png"],
  ["ic08", "icon_256x256.png"],
  ["ic09", "icon_512x512.png"],
  ["ic10", "icon_512x512@2x.png"],
].map(([type, file]) => {
  const data = fs.readFileSync(path.join(iconset, file));
  const header = Buffer.alloc(8);
  header.write(type, 0, 4, "ascii");
  header.writeUInt32BE(data.length + 8, 4);
  return Buffer.concat([header, data]);
});

const totalLength = 8 + entries.reduce((sum, entry) => sum + entry.length, 0);
const header = Buffer.alloc(8);
header.write("icns", 0, 4, "ascii");
header.writeUInt32BE(totalLength, 4);
fs.writeFileSync(out, Buffer.concat([header, ...entries], totalLength));
NODE

echo "Built $ICNS"
