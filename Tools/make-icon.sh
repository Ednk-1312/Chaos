#!/bin/bash
# Renders Tools/Icon.svg into a macOS .icns and copies it into the asset catalog.
# Requires: rsvg-convert (brew install librsvg) — falls back to qlmanage/sips roundtrip.
set -euo pipefail
cd "$(dirname "$0")/.."

ICONSET=build/AppIcon.iconset
mkdir -p "$ICONSET"

render() {
  if command -v rsvg-convert >/dev/null 2>&1; then
    rsvg-convert -w "$2" -h "$2" Tools/Icon.svg -o "$ICONSET/icon_${1}x${1}.png"
    cp "$ICONSET/icon_${1}x${1}.png" "$ICONSET/icon_${1}x${1}@2x.png" 2>/dev/null || true
  else
    echo "rsvg-convert not found; trying qlmanage..." >&2
    qlmanage -t -s 1024 -o /tmp Tools/Icon.svg >/dev/null 2>&1
    sips -z "$2" "$2" /tmp/Icon.svg.png --out "$ICONSET/icon_${1}x${1}.png" >/dev/null
  fi
}

for size in 16 32 128 256 512; do
  render "$size" "$size"
done

# Build @2x variants by upscaling pairs correctly
if command -v rsvg-convert >/dev/null 2>&1; then
  for size in 16 32 128 256 512; do
    rsvg-convert -w $((size*2)) -h $((size*2)) Tools/Icon.svg -o "$ICONSET/icon_${size}x${size}@2x.png"
  done
fi

rm -f Chaos/Assets.xcassets/AppIcon.appiconset/*.png
cp "$ICONSET"/icon_16x16.png Chaos/Assets.xcassets/AppIcon.appiconset/
cp "$ICONSET"/icon_16x16@2x.png Chaos/Assets.xcassets/AppIcon.appiconset/
cp "$ICONSET"/icon_32x32.png Chaos/Assets.xcassets/AppIcon.appiconset/
cp "$ICONSET"/icon_32x32@2x.png Chaos/Assets.xcassets/AppIcon.appiconset/
cp "$ICONSET"/icon_128x128.png Chaos/Assets.xcassets/AppIcon.appiconset/
cp "$ICONSET"/icon_128x128@2x.png Chaos/Assets.xcassets/AppIcon.appiconset/
cp "$ICONSET"/icon_256x256.png Chaos/Assets.xcassets/AppIcon.appiconset/
cp "$ICONSET"/icon_256x256@2x.png Chaos/Assets.xcassets/AppIcon.appiconset/
cp "$ICONSET"/icon_512x512.png Chaos/Assets.xcassets/AppIcon.appiconset/
cp "$ICONSET"/icon_512x512@2x.png Chaos/Assets.xcassets/AppIcon.appiconset/

iconutil -c icns "$ICONSET" -o build/Chaos.icns
echo "Icon written to build/Chaos.icns and Chaos/Assets.xcassets/AppIcon.appiconset/"
