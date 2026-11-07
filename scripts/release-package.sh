#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(cat version.txt)
[[ "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || exit 1
export MACOSX_DEPLOYMENT_TARGET=13.0
bash scripts/build.sh
APP="$PWD/dist/Job’s Done.app"
for ARCH in arm64 x86_64; do
  swift build -c release --arch "$ARCH" --scratch-path ".build/release-$ARCH"
done
lipo -create .build/release-arm64/arm64-apple-macosx/release/JobsDone \
  .build/release-x86_64/x86_64-apple-macosx/release/JobsDone -output "$APP/Contents/MacOS/JobsDone"
for KEY in CFBundleShortVersionString CFBundleVersion; do
  /usr/libexec/PlistBuddy -c "Set :$KEY $VERSION" "$APP/Contents/Info.plist"
done
TEMP_SIGN=$(mktemp -d)
KEYCHAIN=""
cleanup() {
  if [[ -n "$KEYCHAIN" ]]; then security delete-keychain "$KEYCHAIN"; fi
  rm -rf "$TEMP_SIGN"
}
trap cleanup EXIT
if [[ "${MACOS_SIGNING_ENABLED:-false}" == true ]]; then
  : "${MACOS_CERTIFICATE_BASE64:?}" "${MACOS_CERTIFICATE_PASSWORD:?}" "${MACOS_SIGNING_IDENTITY:?}"
  : "${MACOS_NOTARY_KEY_BASE64:?}" "${MACOS_NOTARY_KEY_ID:?}" "${MACOS_NOTARY_ISSUER_ID:?}"
  KEYCHAIN="$TEMP_SIGN/release.keychain-db"
  PASSWORD=$(openssl rand -hex 24)
  printf '%s' "$MACOS_CERTIFICATE_BASE64" | base64 --decode > "$TEMP_SIGN/certificate.p12"
  security create-keychain -p "$PASSWORD" "$KEYCHAIN"
  security set-keychain-settings -lut 21600 "$KEYCHAIN"
  security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
  security import "$TEMP_SIGN/certificate.p12" -k "$KEYCHAIN" -P "$MACOS_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASSWORD" "$KEYCHAIN" >/dev/null
  codesign --force --options runtime --timestamp --keychain "$KEYCHAIN" --sign "$MACOS_SIGNING_IDENTITY" "$APP"
  printf '%s' "$MACOS_NOTARY_KEY_BASE64" | base64 --decode > "$TEMP_SIGN/notary.p8"
  ditto -c -k --keepParent "$APP" "$TEMP_SIGN/notarize.zip"
  xcrun notarytool submit "$TEMP_SIGN/notarize.zip" --key "$TEMP_SIGN/notary.p8" \
    --key-id "$MACOS_NOTARY_KEY_ID" --issuer "$MACOS_NOTARY_ISSUER_ID" --wait
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
else
  codesign --force --sign - "$APP"
fi
mkdir -p dist/release
ZIP="$PWD/dist/release/JobsDone-$VERSION-universal.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
bash scripts/release-validate.sh "$ZIP" "$VERSION"
shasum -a 256 "$ZIP"
