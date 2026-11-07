<p align="center">
  <img src="docs/banner.png" alt="Job’s Done — Work work. GitHub PR alerts for your Mac, with the Warcraft III Peon." width="800">
</p>

<p align="center">A tiny macOS menu bar app for your GitHub PRs.<br>Open one: <b>“Work work.”</b> Merge one: <b>“Job’s done!”</b></p>

## Install

You'll need **macOS 13+**, **Swift 6+** (Xcode or Command Line Tools), and [Homebrew](https://brew.sh).

```sh
brew install gh
gh auth login --hostname github.com
git clone https://github.com/petzkod5/JobsDone.git
cd JobsDone
./scripts/install.sh
```

The installer builds the app, copies it to `~/Applications`, and launches it. Quit any running copy before reinstalling. This is a local, ad-hoc signed build, not a notarized download.

## Set up

1. Click the **Peon** in your menu bar and allow macOS notifications.
2. Use the sound test options to check your audio and banners.
3. Leave it running. Click a notification to open the PR.

It uses your active `github.com` account in GitHub CLI—no token to paste. Public and private PRs **authored by you** are checked every minute while your Mac is awake. New PRs include drafts; existing PRs stay quiet when monitoring first starts. Missed events catch up after downtime, and merge alerts keep working for existing installs.

Mute, pause, and **Open at Login** live in the Peon menu. If banners are missing, check **System Settings → Notifications → Job’s Done** and Focus settings.

<sub>Warcraft artwork and audio belong to Blizzard Entertainment. Sources and credits: [THIRD_PARTY.md](THIRD_PARTY.md).</sub>
