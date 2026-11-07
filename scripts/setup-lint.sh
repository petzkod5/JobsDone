#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=0.65.1
SHA256=c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0
[[ "$(uname -s)" == Darwin ]] || { echo 'Swift lint setup requires macOS.' >&2; exit 1; }
DEST="$PWD/.local/tools/swiftlint"
if [[ -x "$DEST/swiftlint" ]] && [[ "$("$DEST/swiftlint" version)" == "$VERSION" ]]; then
  exit 0
fi
TEMP=$(mktemp -d)
trap 'rm -rf "$TEMP"' EXIT
curl --fail --location --silent --show-error "https://github.com/realm/SwiftLint/releases/download/$VERSION/portable_swiftlint.zip" -o "$TEMP/swiftlint.zip"
printf '%s  %s\n' "$SHA256" "$TEMP/swiftlint.zip" | shasum -a 256 --check --status
unzip -q "$TEMP/swiftlint.zip" -d "$TEMP/unpacked"
[[ "$("$TEMP/unpacked/swiftlint" version)" == "$VERSION" ]]
mkdir -p "$DEST"
cp "$TEMP/unpacked/swiftlint" "$TEMP/unpacked/LICENSE" "$DEST/"
