#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
swift scripts/render-app-icon.swift
ICONSET="$PWD/.build/AppIcon.iconset"
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
  sips -s format png -z "$SIZE" "$SIZE" Resources/AppIcon.png --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE * 2))
  sips -s format png -z "$DOUBLE" "$DOUBLE" Resources/AppIcon.png --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
APP="$PWD/dist/Job’s Done.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/PeonPortrait.icns"
cp .build/release/JobsDone "$APP/Contents/MacOS/JobsDone"
cp Resources/JobsDone.wav "$APP/Contents/Resources/JobsDone.wav"
cp Resources/Hmmm.wav "$APP/Contents/Resources/Hmmm.wav"
cp Resources/WorkWork.wav "$APP/Contents/Resources/WorkWork.wav"
sips -s format png Resources/Peon.gif --out "$APP/Contents/Resources/PeonPortrait.png" >/dev/null
cp Resources/MenuBarPeon.png "$APP/Contents/Resources/MenuBarPeon.png"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"
