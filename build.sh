#!/usr/bin/env bash
# Builds Mac Music Widget.app into ./build. Pass --install to copy it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

# Captured up front: the retina-icon loop below reassigns the positional parameters.
MODE="${1:-}"

APP_NAME="Mac Music Widget"
SOURCE_SVG="Resources/AppIcon.svg"
SOURCE_ICON="Resources/AppIcon.png"
ICNS="Resources/AppIcon.icns"

# --- icon -------------------------------------------------------------------
# Rendered fresh on every build. The SVG is the source of truth: each icon size is
# rasterised from vector at its exact pixel size, which stays crisp at 1024 where
# upscaling the small PNG would not. Falls back to the PNG if rsvg-convert is absent.
if [ -f "$SOURCE_SVG" ] || [ -f "$SOURCE_ICON" ]; then
  echo "==> Generating app icon"
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for size in 16 32 64 128 256 512 1024; do
    OUT="$ICONSET/icon_${size}x${size}.png"
    if [ -f "$SOURCE_SVG" ] && command -v rsvg-convert >/dev/null 2>&1; then
      rsvg-convert -w $size -h $size "$SOURCE_SVG" -o "$OUT"
    else
      sips -z $size $size "$SOURCE_ICON" --out "$OUT" >/dev/null 2>&1
    fi
  done
  # Retina variants are the @2x of the next size down.
  for pair in "16:32" "32:64" "128:256" "256:512" "512:1024"; do
    base="${pair%%:*}"; retina="${pair##*:}"
    cp "$ICONSET/icon_${retina}x${retina}.png" "$ICONSET/icon_${base}x${base}@2x.png"
  done
  rm -f "$ICONSET/icon_64x64.png" "$ICONSET/icon_1024x1024.png"
  iconutil -c icns "$ICONSET" -o "$ICNS"
  rm -rf "$(dirname "$ICONSET")"
fi

# --- build ------------------------------------------------------------------
echo "==> Generating Xcode project"
xcodegen generate >/dev/null

echo "==> Building"
xcodebuild -project MacMusicWidget.xcodeproj -scheme MacMusicWidgetHost \
  -configuration Release -derivedDataPath .build build 2>&1 | grep -E "error:|\*\* BUILD" || true

BUILT=".build/Build/Products/Release/$APP_NAME.app"
[ -d "$BUILT" ] || { echo "Build produced no app at $BUILT"; exit 1; }

rm -rf build && mkdir -p build
cp -R "$BUILT" "build/$APP_NAME.app"
echo "==> Built: build/$APP_NAME.app"

if [[ "$MODE" == "--install" ]]; then
  echo "==> Installing to /Applications"
  pkill -f "/Applications/$APP_NAME.app" 2>/dev/null || true
  pkill -f "MacMusicWidgetExtension" 2>/dev/null || true
  sleep 1
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "build/$APP_NAME.app" "/Applications/$APP_NAME.app"
  open "/Applications/$APP_NAME.app"
  echo "==> Installed and launched"
fi
