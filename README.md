<p align="center">
  <img src="docs/banner.png" alt="Job’s Done — Work work. GitHub PR alerts for your Mac, with the Warcraft III Peon." width="800">
</p>

<p align="center">A tiny macOS menu bar app for your GitHub PRs.<br>Open one: <b>“Work work.”</b> Merge one: <b>“Job’s done!”</b></p>

## Install

Requires **macOS 13+** and [Homebrew](https://brew.sh).

```sh
brew install --cask petzkod5/tap/jobsdone
gh auth login --hostname github.com
```

Homebrew installs the signed, notarized app and GitHub CLI. Open **Job’s Done** from Applications.

## Set up

1. Click the **Peon** in your menu bar and allow macOS notifications.
2. Use the sound test options to check your audio and banners.
3. Leave it running. Click a notification to open the PR.

It uses your active `github.com` account in GitHub CLI—no token to paste. Public and private PRs **authored by you** are checked every minute while your Mac is awake. Other people’s commits on your authored PRs play “Hmmm?” and link back to the PR. Attribution uses the GitHub commit author (including bots); your own commits and commits without a linked GitHub author stay quiet. Existing open PRs are silently baselined on upgrade. Commit IDs are saved per account to prevent repeats across restart and force-push; PRs changed and closed between checks are included. Use **Test Hmmm? + Notification** and **Recent Commits by Others** in the menu.

New PRs include drafts; existing PRs stay quiet when monitoring first starts. Missed events catch up after downtime, and merge alerts keep working for existing installs.

**Notification Style** defaults to **Peon Toast**, with the real Warcraft III portrait, an Open Pull Request button, and a dismiss button. Peon toasts may appear during Focus. Choose **macOS Notification** for system banners and system-scheduled Warcraft sounds that follow Focus.

Toasts stay for 8 seconds (20 seconds for tests); hovering over any toast pauses the stack. Up to three appear at a time; an overflow count points to additional PR updates in the histories. They do not expire while VoiceOver or Switch Control is active. Help supports Command-C / Command-A for selected text and Command-W to close. For keyboard access to PRs, Command-Shift-M opens the Peon menu from Help; arrow keys and Return open the Recently Opened / Recent Merges / Recent Commits by Others links.

Peon mode saves a quiet copy in Notification Center without a second banner. macOS may show a generic app icon there; the real portrait is also attached as a thumbnail. Peon toasts respect notification permission, banner settings, and Show Previews: Never. PR links remain in the menu after a toast disappears.

Open **Settings…** from the Peon menu or press **Command-comma**. Changes save immediately and apply to all GitHub accounts on this Mac. Choose alerts for opened PRs, merged PRs, and commits by others. Add an exact **owner/repository** to ignore all three event types for that repository; press Return to add, or Remove to restore alerts. Names are case-insensitive; URLs and wildcards are not accepted.

Filtered events stay in account-specific Recent history and won’t notify later. Paused events catch up when you resume. Manual notification tests bypass event filters, ignored repositories and pause; mute and macOS permission still apply.

Sound and notification style are available in Settings and the Peon menu. Pause and **Open at Login** live in the Peon menu. **macOS Notification Settings…** opens the separate system controls. If banners are missing, check **System Settings → Notifications → Job’s Done** and Focus settings.

<sub>Warcraft artwork and audio belong to Blizzard Entertainment. Sources and credits: [THIRD_PARTY.md](THIRD_PARTY.md).</sub>
