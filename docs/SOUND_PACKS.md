# Register a sound pack

Add a folder at `Resources/SoundPacks/<id>/` with `opened.wav`, `merged.wav`,
`committed.wav`, and `issueOpened.wav`. Use a unique ID with lowercase ASCII letters, digits, and
hyphens. Keep the ID stable so saved selections continue to work.

Add a `SoundPack` to `SoundPackRegistry.bundled` in `Sources/SoundPack.swift`.
Set its directory to the matching folder in the app bundle. The Settings
**Sound pack** menu lists each registered pack by name. Peon is the default.
An unknown or invalid saved ID resolves to the default pack.

Run `./scripts/test.sh` and `./scripts/build.sh`. The shared packaging script
copies pack folders for `NSSound` and creates `<id>-<event>.wav` aliases at the
bundle resource root for native notifications. Use PCM or IMA4 WAV files shorter
than 30 seconds. Confirm playback with both notification styles before shipping
a new pack. Missing toast audio reports the existing sound warning.

Changing the selection in Settings stops the active clip and dismisses current
toasts. New playback and notification requests use the selected pack. Requests
already sent to macOS keep their original sound.
Mute, pause, event filters, and account history keep their existing behavior.
No pack download or folder import is provided.

Apple documents [bundle resource lookup](https://developer.apple.com/documentation/foundation/bundle)
and [custom notification sound formats, locations, and duration limits](https://developer.apple.com/documentation/usernotifications/unnotificationsound).
These API contracts support the resource and delivery design; they do not prove
that an output device or macOS notification permission permits audible playback.
