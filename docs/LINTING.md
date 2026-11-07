# Swift lint policy

Use the commands in [CONTRIBUTING.md](../CONTRIBUTING.md) to install and run
lint. `.swiftlint.yml` is the explicit rule list; `scripts/lint.py` owns file
selection and failure handling. There is no baseline or per-directory policy.

## Why SwiftLint

[SwiftLint](https://github.com/realm/SwiftLint/blob/0.65.1/README.md) supports
Swift syntax rules, strict warning handling, caching, and command-line use.
JobsDone pins its portable macOS binary and download checksum instead of
building a linter dependency with each app build. Lint never downloads tools
or fixes files. The setup command performs the download separately.

All selected rules run without SourceKit. The runner passes
`--disable-sourcekit` and `--strict`. This avoids compiler invocation and
build-log analysis in the commit path. Swift compilation and the app tests
remain separate checks; lint does not prove concurrency or delivery behavior.

## Rules and boundaries

The rules reject forced casts and forced tries, duplicate conditions and
imports, identical operands, unused bindings, incorrect delegate ownership,
and notification observer removal mistakes. They require unavailable
initializers to declare that intent. Collection rules avoid filter allocations
when a direct membership or emptiness check expresses the operation.

Spacing, braces, import order, and redundant syntax rules reduce review noise.
Cyclomatic complexity is limited to 15 per function, including switch cases.
The polling pipeline is split at its existing delivery phases to meet that
limit while retaining pause/cancellation guards and persistence checkpoints.

This is an explicit selection, not every available opt-in rule. Forced
unwrapping and implicitly unwrapped optionals remain allowed: existing AppKit
lifecycle state and test fixtures use them. This policy does not replace an
unwrap with a silent fallback merely to satisfy lint. File and type length
limits are omitted because moving declarations alone does not simplify control
flow. Review new rules against real violations before enabling them.

The runner rejects the reserved `swiftlint:` marker (including whitespace
before the colon) anywhere in Swift source, nested `.swiftlint.yml` or
`.swiftlint.yaml` files, and Swift source symlinks. This prevents local source
suppressions and nested overrides. Policy changes are still possible through
a reviewed root configuration change. No repository script can prevent a
contributor who can change the workflow or bypass repository protections from
weakening enforcement.

## Reference implementations

The transferable pattern is a checked-in command and shared policy, with fast
local feedback plus CI enforcement. These repositories use different languages;
their rule sets are not copied into Swift:

- [Node's Makefile](https://github.com/nodejs/node/blob/main/Makefile) exposes
  lint targets alongside build and test targets.
- [Next.js's lint guide](https://github.com/vercel/next.js/blob/canary/contributing/repository/linting.md)
  documents repository lint and formatting commands.
- [Electron's lint runner](https://github.com/electron/electron/blob/main/script/lint.js)
  selects files and propagates child tool failures.
- [TypeScript's CI](https://github.com/microsoft/TypeScript/blob/main/.github/workflows/ci.yml)
  invokes its repository lint command in CI.
- [VS Code's hygiene runner](https://github.com/microsoft/vscode/blob/main/build/hygiene.ts)
  centralizes repository hygiene and supports staged-file checks.

JobsDone uses a full staged snapshot rather than changed-line checks because
configuration edits and cross-file rules can affect files outside a diff.
The repository is small enough to check every Swift file without a build.
