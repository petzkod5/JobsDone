These screenshots show the real installed macOS app, captured during local validation of the Peon toast and Setup Help. The local preview displayed version 1.3.4; repository release versions remain managed by release-please. The app UI sources match the reviewed revision.

- `setup-help.png`: grouped Help with the Warcraft III portrait and selectable setup command.
- `peon-toast.png`: app-owned toast with the real portrait, Open Pull Request, and dismiss controls.

Native macOS banner pixels, physical speaker playback, and an actual VoiceOver speech session were not verified.

`hmmm-toast.png` shows the real installed app’s commit-notification test with the original Orc Peon sound packaged. This later capture displays the repository-managed preview version 1.2.0.

`comment-toast-view.png` and `comment-settings-view.png` are native NSView renders
from the isolated app harness on macOS 26.6.2, using fixture PR data. They show
the comment toast and settings toggle. Compositor capture was unavailable.
