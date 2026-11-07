# Contributing to Job’s Done

Bug reports, fixes, and clearer instructions are welcome. Small changes are
easiest to review. For a new feature or a large refactor, open an issue first
so we can agree on the behavior before you build it.

## Build locally

You need macOS, Swift 6 or later, and Xcode Command Line Tools. The app targets
macOS 13+; use macOS 14+ for the Swift Testing runtime. Install
[GitHub CLI](https://cli.github.com/) through Homebrew if you
want to try PR monitoring.

Fork the repo, then clone your fork:

```sh
git clone https://github.com/YOUR-USERNAME/JobsDone.git
cd JobsDone
git switch -c fix/your-change
./scripts/test.sh
./scripts/build.sh
```

Use the isolated development app to try the settings without changing your
installed app's preferences or history:

```sh
./scripts/build-dev.sh
open ".local/unit-a/dev/JobsDone Dev.app"
```

This app has a separate identity and does not monitor GitHub, request
notification permission, or register a login item. Use `./scripts/test-native.sh`
in a logged-in macOS graphical session to check native control actions.

The production build is at `dist/Job’s Done.app`. It shares the installed
app's preferences and history. `scripts/install.sh` copies it to
`~/Applications` and launches it; installation is not needed for tests.

## Lint Swift and install the commit hook

```sh
./scripts/setup-hooks.sh
python3 scripts/lint.py
```

Setup downloads SwiftLint 0.65.1 into `.local/tools`, verifies its SHA-256,
and sets this clone's `core.hooksPath` to `.githooks`. It refuses to overwrite
another hook path. Run setup in each clone; no global installation is needed.
Use `./scripts/setup-lint.sh` to install the tool without configuring hooks.

The pre-commit hook checks the complete index in a temporary directory. It
checks staged contents even when a file also has unstaged edits, and changes
neither the index nor the working tree. The full command includes tracked and
untracked Git-visible Swift files, including tests, scripts, and Package.swift.
Stage deleted files before checking. Dependencies and build outputs are ignored.

Every warning fails. Fix findings rather than adding inline suppressions,
baselines, or nested configuration. Change the root `.swiftlint.yml` through
review when the policy needs to change. See [the lint policy](docs/LINTING.md)
for rule choices and research references.

The `Lint` workflow runs on every PR and push. Its `Swift lint` and
`Automation lint` checks are required alongside `macos` and `Conventional
commits`. Swift lint installs the same pinned version and checks all Swift
files; automation lint checks shell scripts and workflows. Local hooks can be
skipped by Git; CI is the merge gate. Changes to the policy, runner, hooks,
and workflows still need review.

## Find your way around

- `Sources/Monitor.swift`: GitHub queries, event detection, account state.
- `Sources/main.swift` and `AppConfiguration.swift`: launch and test isolation.
- `Sources/AppDelegate.swift`: menu, notifications, app lifecycle.
- `Sources/PollingSession.swift`: polling, delivery sequencing, saved history.
- `Sources/PeonToast.swift`: custom notification toasts.
- `Sources/NotificationPreferences.swift` and `NotificationSettings.swift`: alert filters and settings.
- `Sources/UIState.swift`: shared UI state.
- `Tests/`: discovered Swift regression tests; `Tests/Native/` tests AppKit actions.
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
./scripts/check.sh
```

The automation check requires actionlint 1.7.12 and ShellCheck 0.11.0. CI
downloads these versions. It checks tracked shell scripts and workflows;
stage new files before running it locally.

Exercise affected failure paths. For visible changes, include screenshots from
the real app and the macOS version. Say when notification delivery, audio, or
accessibility behavior was not tested; a successful build does not prove them.
Docs-only changes need a link and command review rather than an app build.

Write docs for someone trying to use the app: give the command or next step,
use the actual menu labels, and cut repeated explanations. Keep build internals
in contributor docs and release details in [the release guide](docs/RELEASING.md).

Original code and documentation use the [MIT license](LICENSE). Warcraft assets
have separate rights and credits in [THIRD_PARTY.md](THIRD_PARTY.md).
