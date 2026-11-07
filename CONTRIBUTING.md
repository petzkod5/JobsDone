# Contributing to Job’s Done

Bug reports, fixes, and clearer instructions are welcome. Small changes are
easiest to review. For a new feature or a large refactor, open an issue first
so we can agree on the behavior before you build it.

## Build locally

You need macOS, Swift 6 or later, and Xcode Command Line Tools. The app targets
macOS 13+. Install [GitHub CLI](https://cli.github.com/) through Homebrew if you
want to try PR monitoring.

Fork the repo, then clone your fork:

```sh
git clone https://github.com/YOUR-USERNAME/JobsDone.git
cd JobsDone
git switch -c fix/your-change
./scripts/test.sh
./scripts/build.sh
```

The built app is at `dist/Job’s Done.app`. Quit any installed copy before
opening it. Local builds share the installed app’s preferences and saved PR
history; use a separate macOS user account if you need clean test data.
`scripts/install.sh` copies to `~/Applications` and launches the app, so it is
not needed for building or testing.

## Find your way around

- `Sources/Monitor.swift`: GitHub queries, event detection, account state.
- `Sources/main.swift`: menu, notifications, app lifecycle.
- `Sources/PeonToast.swift`: custom notification toasts.
- `Sources/NotificationPreferences.swift` and `NotificationSettings.swift`: alert filters and settings.
- `Sources/UIState.swift`: shared UI state.
- `Tests/main.swift`: monitor and settings regression checks.
- `scripts/`: build, test, and release tooling.

Keep authored-PR monitoring, account separation, pause/mute behavior, and saved
history intact. Add a regression check when fixing event detection or state
persistence. Do not add credentials or private PR data to fixtures.

## Send a pull request

Use [Conventional Commits](https://www.conventionalcommits.org/) for **every
commit and the PR title**. For example:

```text
fix(monitor): avoid duplicate merge alerts
feat: add a notification option
docs: clarify GitHub sign-in
```

CI checks all commits in the PR. See [AGENTS.md](AGENTS.md) for allowed types
and release rules. Release-please owns versions and the changelog; leave those
generated files alone.

Use the PR template to explain the problem, the resulting behavior, and checks
you actually ran. For app changes, run `./scripts/test.sh` and
`./scripts/build.sh`. For release or CI changes, also run:

```sh
python3 -m unittest discover -s scripts/ci -p 'test_*.py'
```

Exercise affected failure paths. For visible changes, include screenshots from
the real app and the macOS version. Say when notification delivery, audio, or
accessibility behavior was not tested; a successful build does not prove them.
Docs-only changes need a link and command review rather than an app build.

Write docs for someone trying to use the app: give the command or next step,
use the actual menu labels, and cut repeated explanations. Keep build internals
in contributor docs and release details in [the release guide](docs/RELEASING.md).

Original code and documentation use the [MIT license](LICENSE). Warcraft assets
have separate rights and credits in [THIRD_PARTY.md](THIRD_PARTY.md).
