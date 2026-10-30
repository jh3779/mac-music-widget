#!/usr/bin/env bash
# Builds Mac Music Widget.app into ./build. Pass --install to copy it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

# Captured up front: the retina-icon loop below reassigns the positional parameters.
MODE=""
SPEC="project.yml"
BUILD_OPTIONS=("CODE_SIGNING_ALLOWED=YES")
for option in "$@"; do
  case "$option" in
    --install) MODE="--install" ;;
    --safari) SPEC="project-safari.yml" ;;
    *) echo "Usage: $0 [--safari] [--install]" >&2; exit 2 ;;
  esac
done
if [[ "$SPEC" == "project-safari.yml" ]]; then
  : "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to your Apple signing team for the Safari build.}"
  : "${APP_GROUP_IDENTIFIER:?Set APP_GROUP_IDENTIFIER to your provisioned App Group.}"
  : "${BUNDLE_ID_PREFIX:?Set BUNDLE_ID_PREFIX to your own unique reverse-DNS app identifier.}"
  BUILD_OPTIONS+=("DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM" "APP_GROUP_IDENTIFIER=$APP_GROUP_IDENTIFIER" "BUNDLE_ID_PREFIX=$BUNDLE_ID_PREFIX")
fi

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
xcodegen generate --spec "$SPEC" >/dev/null

echo "==> Building"
mkdir -p .build
if ! xcodebuild -project MacMusicWidget.xcodeproj -scheme MacMusicWidgetHost \
  -configuration Release -derivedDataPath .build "${BUILD_OPTIONS[@]}" build > .build/build.log 2>&1; then
  tail -80 .build/build.log >&2
  exit 1
fi

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
