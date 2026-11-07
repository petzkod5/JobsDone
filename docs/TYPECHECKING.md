# Swift type checking

Run `./scripts/typecheck.sh` on macOS with Swift 6 or later and Xcode Command
Line Tools. It checks types without running tests, launching the app, or
executing the asset utilities. Run `./scripts/test.sh` separately for behavior.

## Enforcement

`Package.swift` selects Swift 6 language mode for the app and regression tests
and treats every Swift compiler warning as an error in debug and release
builds. Swift 6 enables complete concurrency checking: actor isolation,
Sendable captures, and shared mutable state are checked by the compiler.
Ordinary `swift build` and `swift test` inherit these settings.

The command compiles and lists the SwiftPM tests using the existing test
runner's framework search paths. This also checks the package manifest and
app module. It then uses `swiftc -typecheck` with Swift 6, complete concurrency
checking, warnings as errors, and the macOS 13 deployment target for:

- The app's `JOBSDONE_DEV` conditional path.
- App sources linked with `Tests/Native/main.swift`, excluding the app's main.
- Each independent `scripts/*.swift` utility.

The `Typecheck` workflow runs this command in its `Typecheck` job on pushes,
pull requests, and manual dispatch. Configure `Typecheck` as a required check
in repository branch protection. `./scripts/setup-hooks.sh` also installs the
pre-push hook. It checks each distinct outgoing commit tip from Git's ref input
in a temporary snapshot, so unstaged edits or a different checked-out branch
cannot hide an error. It skips deletions and fails closed when checking fails.
The lint workflow's macOS automation tests exercise this command in temporary
copies and verify that type errors, warnings, unsafe shared state, and errors
in the test, development, native, and utility entry points fail the gate.

Fix ownership and isolation at the boundary that produces the diagnostic.
For example, notification settings are copied into a `Sendable` snapshot
before crossing to the main actor; polling callbacks are main-actor isolated,
while GitHub process work remains in detached tasks. Do not silence findings
with `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, or weaker
compiler flags. Changes to compiler policy require review, just as lint policy
changes do. CI configuration and branch protections remain the enforcement
boundary; a contributor able to change them can weaken the checks.

The compiler does not prove notification delivery, account separation, or
pause/mute behavior. Regression tests and real-app checks still cover those
behaviors. This policy promotes Swift compiler warnings, not linker warnings.
Use `swift --version` and `xcode-select -p` when comparing SDK diagnostics.

## Tool choice and repository references

The [Swift compiler](https://www.swift.org/documentation/swift-compiler/)
provides authoritative semantic checking. Apple's
[Swift 6 migration guide](https://developer.apple.com/documentation/swift/adoptingswift6)
explains why Swift 6 language mode enables complete concurrency checks even
when merely using a Swift 6 toolchain would retain Swift 5 mode.
[SwiftLint](https://github.com/realm/SwiftLint#analyze) provides syntax and
convention checks; its optional analyzer consumes compiler logs. SourceKit
provides editor integration. Neither replaces the compiler gate. The existing
SwiftLint policy remains in [LINTING.md](LINTING.md).

The transferable practices from these projects are explicit commands, shared
compiler settings, and distinct lint, compilation, and behavior checks:

- [Next.js](https://github.com/vercel/next.js/blob/canary/package.json) exposes
  `test-types`, `typescript`, and repository-wide type checking in lint.
- [Electron](https://github.com/electron/electron/blob/main/package.json)
  exposes a dedicated `typecheck` command separately from bundling and lint.
- [VS Code](https://github.com/microsoft/vscode/blob/main/src/tsconfig.base.json)
  centralizes strict compiler options, unused-local and return checking.
- [TypeScript](https://github.com/microsoft/TypeScript/blob/main/package.json)
  exposes repository build, test, lint, and formatting commands separately.
- [Node.js](https://github.com/nodejs/node/blob/main/Makefile) maintains explicit
  build, test, and lint targets for its mixed-language repository.

These projects supply workflow examples; their language-specific options do
not translate directly into Swift flags.
