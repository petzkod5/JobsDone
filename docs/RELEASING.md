# Releasing Job’s Done

The committed baseline is 1.2.0. Release Please's manifest uses the `simple`
strategy to update `version.txt`, its manifest, and `CHANGELOG.md` in a release
PR. `bootstrap-sha` excludes history through `be68e01` from the first changelog.
Merge conventional commits to main, review the generated PR, then merge it.
No direct version or tag edits are needed.

## Repository setup (maintainer)

Enable **Settings → Actions → General → Allow GitHub Actions to create and
approve pull requests** and permit the workflow's declared token permissions.
Create `petzkod5/homebrew-tap` with an initial commit on `main`. Add a write SSH
deploy key there and store its private key as this repository's
`HOMEBREW_TAP_DEPLOY_KEY` secret. These are configured for this repository.

The Release workflow runs on main pushes and manual dispatch. It uses
`GITHUB_TOKEN` for Release Please. Since events from this token do not trigger
ordinary PR/tag/release workflows, packaging runs as dependent jobs in the same
workflow. Release PR creation/updates explicitly dispatch `build.yml` at the PR
head branch and `conventional-commits.yml` on that same branch with the `pr`
number, so both checks report against the current PR head. Both workflows must
support dispatch on main before this pipeline is enabled. No PR output means no
CI dispatch. Protect `main` by requiring a PR and the `Conventional commits` and
`macos` status checks, including for administrators. These requirements are
configured for this repository; maintainers review and merge passing PRs.

## Artifacts and recovery

A release starts as a draft with an immediately created tag. The tag must resolve
to an ancestor of main, and its `version.txt` and manifest must match `vX.Y.Z`.
The app checkout must be exactly that commit. Release tooling comes from the
reviewed workflow commit on main, in a separate checkout. This allows a tooling
fix to recover an older draft without moving its tag or changing app source.
The package and tap jobs use the same pinned macOS runner label as the
`Build and test`, `Typecheck`, and `Lint` workflows, so releases build on the
image generation that checked the merged source. Image updates can still change
its default Xcode; the package job runs the tests again before uploading.
`./scripts/check.sh` fails when a macOS job uses a `-latest` label or a
different label; change every workflow together.
Packaging builds both arm64
and x86_64 for macOS 13, replaces the native bundled binary, sets both built bundle
version fields to the semver, and signs the result without editing source plist.

`JobsDone-X.Y.Z-universal.zip` and its `.sha256` sidecar are uploaded. The workflow
**downloads the uploaded archive**, verifies both architectures, deployment
minimum, bundle versions and code signature, and checks its bytes against the
build before publishing. The release is published without changing GitHub's
latest-release selection. Only then does the final job use the tap deploy key.
It downloads and validates the published ZIP and sidecar again before generating
`Casks/jobsdone.rb`; the checksum always describes the distributed archive.

For a failed packaging/upload/tap job, dispatch **Release** from **main** with
`retry_tag` set to the existing tag, such as `v1.2.1`. Empty input runs Release
Please normally. A retry requires an existing GitHub release and immutable tag;
it never builds an arbitrary input branch or creates a missing release/tag.
Existing ZIP bytes are reused and validated; an existing inconsistent sidecar
fails, and assets are never overwritten. If an interrupted upload left invalid
bytes, investigate manually rather than replacing a public version silently.
Changing signing mode also requires a new release version.

One concurrency group serializes release runs without cancellation. GitHub can
replace an older pending run with a newer pending run; use manual retry for a
missed draft. Tap updates refuse version downgrades and same-version checksum
changes. Non-fast-forward pushes fetch and regenerate up to three times. Only
`Casks/jobsdone.rb` is staged. The tap key is a temporary chmod-600 file, removed
on exit; host keys come from GitHub's HTTPS meta API. SSH is used only by git.
Other writers must honor the same version rule; repository admins can still
move/delete tags, so protect `v*` tags against modification/deletion.

## Signing

Published releases use Developer ID signing and notarization. The repository
variable `MACOS_SIGNING_ENABLED` is set to `true`; the v1.4.0 release ZIP was
verified with `codesign --verify --deep --strict` and `xcrun stapler validate`.
Local builds from `scripts/build.sh` remain ad-hoc signed.

If signing is disabled, release packaging uses ad-hoc signing without Apple
notarization. Homebrew installation does not confer Apple trust. The pipeline
does not remove quarantine or bypass Gatekeeper.

Developer ID signing requires `MACOS_SIGNING_ENABLED=true` and these secrets:

- `MACOS_CERTIFICATE_BASE64`: base64 PKCS#12 Developer ID Application certificate
  with its private key.
- `MACOS_CERTIFICATE_PASSWORD`: PKCS#12 password.
- `MACOS_SIGNING_IDENTITY`: full Developer ID Application signing identity.
- `MACOS_NOTARY_KEY_BASE64`: base64 App Store Connect API `.p8` key.
- `MACOS_NOTARY_KEY_ID` and `MACOS_NOTARY_ISSUER_ID`: its key and issuer IDs.

Enabled signing fails if any credential is missing. A temporary keychain signs
with hardened runtime and timestamp. It imports Apple’s Developer ID G2
intermediate, registers the temporary keychain for signing, and restores the
original search list on success or failure. Then notarytool submits and waits, and the
ticket is stapled before the final ZIP. Archive validation requires Developer ID
and a valid stapled ticket in this mode. Apple's certificate/API permissions and
service availability must be validated with a real signed release; no credentials
are provisioned here.

Ticket stapling and validation retry exit codes 65/68 and command timeouts up to
three attempts, with 30s and 60s pauses. Each attempt has a 120s timeout. These
CloudKit operations can fail after notarization is accepted; retrying them does
not rebuild or resubmit the app. Other errors stop immediately, and exhausted
retries still fail the release.

References: [Release Please action](https://github.com/googleapis/release-please-action#readme)
and [manifest configuration](https://github.com/googleapis/release-please/blob/main/docs/manifest-releaser.md).
