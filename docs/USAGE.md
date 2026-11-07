# Using Job’s Done

## PR and issue alerts

JobsDone checks PRs authored by your active `github.com` account while your Mac
is awake. It also watches issues opened by anyone in repositories owned by
that account; organization and collaborator repositories are excluded. In **Settings…**, choose **GitHub polling interval** from 30 seconds
to 15 minutes (default: 60 seconds). Changes apply immediately. GitHub CLI handles sign-in; there is no token to paste
into the app.

New PRs include drafts. Existing PRs stay quiet when monitoring first starts;
after that, missed events catch up when the app runs again. Recent PR links
remain in the menu after a notification disappears.

Other people’s commits on your PRs play “Hmmm?”. Attribution uses the linked
GitHub commit author, including bots. Your own commits and commits without a
linked author stay quiet. PRs changed and closed between checks are included.
Existing open PRs are silently baselined when upgrading to commit alerts.
Saved commit IDs prevent repeats across restart and force-push.

New issues play “Something need doing?” and appear under **Recent Issues**.
Existing issues stay silent on first launch or upgrade. Issues closed between
checks are included. Saved issue IDs prevent repeat alerts after restart.

## Choose a notification style

Open **Settings…** or use the Peon menu:

- **Peon Toast** (default): app-owned toast with an Open Pull Request or Open Issue button.
  It may appear during Focus and saves a quiet copy in Notification Center.
- **macOS Notification**: system banners and scheduled sounds that follow Focus.

Peon toasts respect notification permission, banner settings, and
**Show Previews: Never**. Notification Center may show a generic app icon;
the Peon portrait is also attached as a thumbnail.

In **Settings…**, choose **Notification duration** from 5 to 60 seconds
(default: 8 seconds). The duration applies to new Peon toasts, including tests.
macOS controls native notification duration. Hovering pauses the toast stack.
Up to three appear at once; an overflow count points to more updates in the
histories. Toasts do not expire while VoiceOver or Switch Control is active.

## Filters, pause, and mute

Open **Settings…** with **Command-comma**. Changes save immediately and apply
to all GitHub accounts on this Mac. Choose alerts for opened PRs, merged PRs,
commits by others, and issues opened in your repositories.

To ignore a repository, enter its exact **owner/repository** and press Return.
Names are case-insensitive. URLs and wildcards are not accepted. Use Remove
to restore alerts.

Filtered events stay in account-specific Recent history and will not notify
later. Paused events catch up when you resume. Manual notification tests bypass
pause, alert filters, and ignored repositories; mute and macOS permission still
apply. Pause and **Open at Login** are in the Peon menu.

## Keyboard access

In Help, **Command-C** copies selected text, **Command-A** selects all, and
**Command-W** closes the window. **Command-Shift-M** opens the Peon menu from
Help. Use arrow keys and Return to open links under **Recently Opened**,
**Recent Merges**, **Recent Commits by Others**, or **Recent Issues**.

For sign-in or notification problems, see [Help](../SUPPORT.md).
