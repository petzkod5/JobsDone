#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Command Line Tools ship Swift Testing outside the default framework search path.
FRAMEWORKS="$(xcode-select -p)/Library/Developer/Frameworks"
if [[ -d "$FRAMEWORKS/Testing.framework" ]]; then
  swift test --disable-xctest -Xswiftc -F -Xswiftc "$FRAMEWORKS" -Xlinker -F -Xlinker "$FRAMEWORKS" -Xlinker -rpath -Xlinker "$FRAMEWORKS" -Xlinker -rpath -Xlinker "$(xcode-select -p)/Library/Developer/usr/lib" "$@"
else
  swift test --disable-xctest "$@"
fi
