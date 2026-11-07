#!/bin/bash
set -euo pipefail
# Keep folder resources for NSSound and unique root aliases for UNNotificationSound.
DESTINATION="$1"
mkdir -p "$DESTINATION/SoundPacks"
cp -R Resources/SoundPacks/. "$DESTINATION/SoundPacks/"
for PACK in Resources/SoundPacks/*; do
  for EVENT in opened merged committed issueOpened; do
    cp "$PACK/$EVENT.wav" "$DESTINATION/$(basename "$PACK")-$EVENT.wav"
  done
done
