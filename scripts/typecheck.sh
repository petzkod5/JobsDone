#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# SwiftPM owns the app/test module graph and the manifest's strict settings.
# Listing discovers and compiles tests without executing them or launching the app.
./scripts/test.sh list >/dev/null

FLAGS=(-swift-version 6 -strict-concurrency=complete -warnings-as-errors
       -target "$(uname -m)-apple-macosx13.0")
# Check the conditional development path as well as the production SwiftPM target.
swiftc -typecheck "${FLAGS[@]}" -D JOBSDONE_DEV Sources/*.swift

SOURCES=()
for SOURCE in Sources/*.swift; do
  [[ "$SOURCE" == Sources/main.swift ]] || SOURCES+=("$SOURCE")
done
swiftc -typecheck "${FLAGS[@]}" "${SOURCES[@]}" Tests/Native/main.swift

# Each utility is an independent executable with its own top-level declarations.
for SOURCE in scripts/*.swift; do
  swiftc -typecheck "${FLAGS[@]}" "$SOURCE"
done
printf 'Strict Swift type checking passed.\n'
