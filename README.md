<p align="center">
  <img src="docs/banner.png" alt="Job’s Done — Work work. GitHub PR alerts for your Mac, with the Warcraft III Peon." width="800">
</p>

A tiny Mac menu bar app that makes Warcraft noises at your GitHub PRs.

Open one: **“Work work.”** Merge one: **“Job’s done!”**
Someone else commits to it: **“Hmmm?”**

## Install

macOS 13+, Intel or Apple silicon. Requires [Homebrew](https://brew.sh).

```sh
brew install --cask petzkod5/tap/jobsdone
gh auth login --hostname github.com
```

Open **Job’s Done** from Applications, allow notifications, and leave it running.
It watches PRs you authored using your active GitHub CLI account.

[Help](SUPPORT.md) · [Settings and usage](docs/USAGE.md) · [Downloads](https://github.com/petzkod5/JobsDone/releases/latest) · [Contribute](CONTRIBUTING.md)

[MIT](LICENSE) for the code and docs. Warcraft art and audio belong to Blizzard
and are excluded; [credits here](THIRD_PARTY.md).
