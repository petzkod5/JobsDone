#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD/.local/unit-a/dev"
APP="$ROOT/JobsDone Dev.app"
swift build --scratch-path "$ROOT/build" -c debug -Xswiftc -DJOBSDONE_DEV
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/build/debug/JobsDone" "$APP/Contents/MacOS/JobsDoneDev"
bash scripts/copy-sound-packs.sh "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier org.jobsdone.dev' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable JobsDoneDev' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName JobsDone Dev' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName JobsDone Dev' "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
printf 'Built isolated app (no live monitoring): %s\n' "$APP"
