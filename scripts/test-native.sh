#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Requires a logged-in macOS graphical session. Never launches the installed app.
EVIDENCE="$PWD/.local/unit-a/native"
APP="$EVIDENCE/JobsDone Native Tests.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
sips -s format png Resources/Peon.gif --out "$APP/Contents/Resources/PeonPortrait.png" >/dev/null
/usr/libexec/PlistBuddy -c 'Clear dict' "$APP/Contents/Info.plist" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string org.jobsdone.native-tests' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string NativeTests' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleName string JobsDone Native Tests' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :LSUIElement bool true' "$APP/Contents/Info.plist"
sources=()
for source in Sources/*.swift; do
  [[ "$source" == Sources/main.swift ]] || sources+=("$source")
done
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -target "$(uname -m)-apple-macosx13.0" "${sources[@]}" Tests/Native/main.swift -o "$APP/Contents/MacOS/NativeTests"
"$APP/Contents/MacOS/NativeTests" "$EVIDENCE"
