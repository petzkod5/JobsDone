#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
mkdir -p "$HOME/Applications"
APP="$HOME/Applications/Job’s Done.app"
if pgrep -x JobsDone >/dev/null; then
  echo "Quit the running Job’s Done app from its menu before reinstalling."
  exit 1
fi
ditto "dist/Job’s Done.app" "$APP"
# Refresh this app's registration and modification date so macOS reloads its bundled icon.
touch "$APP"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -u "$PWD/dist/Job’s Done.app" >/dev/null 2>&1 || true
"$LSREGISTER" -f "$APP"
open "$APP"
echo "Installed and launched $APP"
