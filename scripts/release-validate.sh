#!/bin/bash
set -euo pipefail
TOOLS_DIR=$(cd "$(dirname "$0")" && pwd)
ZIP=$1
VERSION=$2
[[ "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || exit 1
TEMP_VALIDATE=$(mktemp -d)
trap 'rm -rf "$TEMP_VALIDATE"' EXIT
# Reject paths escaping extraction before invoking ditto.
python3 - "$ZIP" <<'PY'
import sys, zipfile
from pathlib import PurePosixPath
with zipfile.ZipFile(sys.argv[1]) as z:
    for name in z.namelist():
        p = PurePosixPath(name)
        if p.is_absolute() or '..' in p.parts:
            raise SystemExit('Unsafe archive path')
PY
ditto -x -k "$ZIP" "$TEMP_VALIDATE"
APP="$TEMP_VALIDATE/Job’s Done.app"
for KEY in CFBundleShortVersionString CFBundleVersion; do
  [[ "$(/usr/libexec/PlistBuddy -c "Print :$KEY" "$APP/Contents/Info.plist")" == "$VERSION" ]] || { echo "Bundle version mismatch: $KEY" >&2; exit 1; }
done
[[ "$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$APP/Contents/Info.plist")" == 13.0 ]] || { echo "Invalid bundle macOS minimum" >&2; exit 1; }
BIN="$APP/Contents/MacOS/JobsDone"
[[ "$(lipo -archs "$BIN" | tr ' ' '\n' | sort | xargs)" == 'arm64 x86_64' ]] || { echo 'Expected universal arm64 + x86_64 executable' >&2; exit 1; }
for ARCH in arm64 x86_64; do
  MIN=$(xcrun vtool -arch "$ARCH" -show-build "$BIN" | awk '$1 == "minos" {print $2}')
  [[ "$MIN" == 13.0 ]] || { echo "Invalid macOS minimum: $MIN" >&2; exit 1; }
done
codesign --verify --deep --strict "$APP"
if [[ "${MACOS_SIGNING_ENABLED:-false}" == true ]]; then
  codesign -d -vv "$APP" 2>&1 | grep 'Authority=Developer ID Application:' >/dev/null
  python3 "$TOOLS_DIR/release-ticket.py" validate "$APP"
fi
