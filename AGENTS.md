# JobsDone contributor guidance

JobsDone is a native Swift macOS menu bar app. Keep changes small and preserve authored-PR monitoring, account isolation, pause/mute behavior, and saved notification history.

Read [CONTRIBUTING.md](CONTRIBUTING.md) for local setup and the source map.
Write documentation in plain, specific language. Use actual commands and menu
labels, remove repetition, and keep claims tied to source or checks performed.
Avoid promotional filler, generic best-practice lists, and documents that repeat
each other. Keep the README focused on installing and using the app.
Keep writing changes within the requested scope. Do not add contribution
policies or expand the README as part of a wording cleanup.

## Commits and pull requests

Every commit must use Conventional Commits. This includes intermediate commits, reverts, and release automation commits. PR titles must follow the same format so squash merges remain compatible with release-please:

```text
feat: add a feature
fix(monitor): correct duplicate alerts
ci: update release automation
docs: clarify setup
feat!: describe a breaking change
```

Use a lowercase type from `feat`, `fix`, `perf`, `refactor`, `docs`, `style`, `test`, `build`, `ci`, `chore`, or `revert`. Add an optional scope, then an optional `!`, then `: ` and a short description. Separate any body from the subject with a blank line. Use `!` or a `BREAKING CHANGE:` footer for a breaking change.

- `fix`, `perf`, and `revert` produce patch releases; `feat` produces a minor release; breaking changes produce a major release. Other types normally do not trigger a release.
- Do not use `WIP`, `fixup!`, `squash!`, or default merge subjects. Every commit in a PR is checked, not just the title or latest commit.
- Use the pull request template. Describe the problem, resulting behavior, and checks actually performed. Include real-app evidence for visible changes and state any validation limits.
- Never rewrite a shared branch or change another contributor's work without coordination.

## Validation

Run `./scripts/typecheck.sh`, `./scripts/test.sh`, and `./scripts/build.sh` for app changes.
Keep Swift 6 language mode and warnings as errors enabled. Fix isolation and
Sendable contracts rather than suppressing concurrency diagnostics. For automation changes, validate the affected scripts and workflows and exercise their failure paths. Never claim a release or notification was tested when only a source review was performed.

Test the production path that owns the behavior. Do not reproduce that path in
the test and then assert its result. Replace external services at their
boundaries, and check the requests and observable results. For a bug fix,
confirm that its regression test fails without the fix. Keep reusable test
harnesses in version control and isolate their preferences and saved history.

## Releases

Release-please owns version bumps and changelogs. Merge its release PR to publish a version; do not hand-edit generated versions or create release tags to bypass it. Release packaging and Homebrew setup are documented in [docs/RELEASING.md](docs/RELEASING.md).

Keep credentials out of source, logs, commits, and PRs. Do not disable Gatekeeper or remove quarantine as part of installation or release automation. Keep Warcraft asset credits in `THIRD_PARTY.md`.
