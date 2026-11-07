# Help with Job’s Done

## No PR alerts

1. Run `gh auth status --hostname github.com` in Terminal. If needed, run
   `gh auth login --hostname github.com`.
2. Check that the PR is authored by the active GitHub CLI account. JobsDone
   currently monitors `github.com`, not GitHub Enterprise Server.
3. Check **Pause**, mute, alert switches, and ignored repositories in the app.
4. Allow a minute while your Mac is awake. Existing PRs are silently baselined
   on first setup; opening the app does not announce every old PR.

To change accounts, run `gh auth switch --hostname github.com`, then allow the
next check to pick it up. History is saved separately for each account.

## No banner or sound

Use the notification tests in the Peon menu. Tests bypass pause and event
filters, but still respect mute and macOS notification permission.

Check **System Settings → Notifications → Job’s Done**, your output volume, and
Focus. **Peon Toast** can appear during Focus; **macOS Notification** follows
system scheduling. Choose the style in **Settings…**.

## Install or update trouble

Quit the app before updating, then follow [the install instructions](README.md#install).
If macOS rejects an official release, include the exact message in a bug report.
Do not disable Gatekeeper or remove quarantine. Locally built apps are ad-hoc
signed and differ from published releases.

## Ask for help or report a bug

Search [existing issues](https://github.com/petzkod5/JobsDone/issues), then open
an issue with the app version, macOS version, installation method, and what
happened. Questions can use a blank issue. Screenshots help; crop private PR
titles, repository names, and account details first.

Never post tokens, `gh auth token` output, or your saved account history files.
History lives in `~/Library/Application Support/JobsDone/`; deleting it changes
which events the app considers already delivered. Avoid resetting it as a
first troubleshooting step.

For a security vulnerability, use [private reporting](SECURITY.md).
