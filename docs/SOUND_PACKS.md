# Register a sound pack

Add a folder at `Resources/SoundPacks/<id>/` with WAV files named for their
sounds, such as `Hmmm.wav` or `SomethingNeedDoing.wav`. Filenames may contain
ASCII letters, digits, underscores, and hyphens, followed by `.wav`.
Use a unique pack ID with lowercase ASCII letters, digits, and hyphens. Keep the ID stable so saved selections continue to work.

Add a `SoundPack` to `SoundPackRegistry.bundled` in `Sources/SoundPack.swift`.
Set its directory to the matching folder in the app bundle, list its filenames
in `sounds`, and map every `NotificationEvent` to a filename in `eventSounds`.
Events can share a file, and packs can include sounds that no event selects.
Peon's defaults are:

| Event | Sound file |
| --- | --- |
| PR opened | `WorkWork.wav` |
| PR merged | `JobsDone.wav` |
| Other-author commit | `Hmmm.wav` |
| Issue opened | `SomethingNeedDoing.wav` |

The mapping supplies defaults in code; per-event sound selection in Settings
is future work. The Settings
**Sound pack** menu lists each registered pack by name. Peon is the default.
An unknown or invalid saved ID resolves to the default pack.

Run `./scripts/test.sh` and `./scripts/build.sh`. The shared packaging script
copies pack folders for `NSSound` and creates `<id>-<sound>.wav` aliases for every WAV file at the
bundle resource root for native notifications. Use PCM or IMA4 WAV files shorter
than 30 seconds. Confirm playback with both notification styles before shipping
a new pack. Missing toast audio reports the existing sound warning. Packaging fails for an
empty pack folder; confirm every registered filename exists before shipping.

Changing the selection in Settings stops the active clip and dismisses current
toasts. New playback and notification requests use the selected pack. Requests
already sent to macOS keep their original sound.
Mute, pause, event filters, and account history keep their existing behavior.
No pack download or folder import is provided.

Apple documents [bundle resource lookup](https://developer.apple.com/documentation/foundation/bundle)
and [custom notification sound formats, locations, and duration limits](https://developer.apple.com/documentation/usernotifications/unnotificationsound).
These API contracts support the resource and delivery design; they do not prove
that an output device or macOS notification permission permits audible playback.
