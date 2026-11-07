#!/bin/bash
set -euo pipefail
: "${HOMEBREW_TAP_DEPLOY_KEY:?}"
TAG=$1
TEMP_TAP=$(mktemp -d)
trap 'rm -rf "$TEMP_TAP"' EXIT
umask 077
printf '%s\n' "$HOMEBREW_TAP_DEPLOY_KEY" > "$TEMP_TAP/key"
chmod 600 "$TEMP_TAP/key"
# Trust keys supplied by GitHub's authenticated HTTPS endpoint, never ssh-keyscan.
curl --fail --silent --show-error --proto '=https' https://api.github.com/meta \
  | python3 -c 'import json,sys; print("\n".join("github.com " + k for k in json.load(sys.stdin)["ssh_keys"]))' > "$TEMP_TAP/known_hosts"
export GIT_SSH_COMMAND="ssh -i '$TEMP_TAP/key' -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile='$TEMP_TAP/known_hosts'"
git clone --depth 1 git@github.com:petzkod5/homebrew-tap.git "$TEMP_TAP/tap"
# Regenerate after each fresh fetch so a racing update can never be downgraded.
for ATTEMPT in 1 2 3; do
  echo "Updating Homebrew tap (attempt $ATTEMPT of 3)"
  git -C "$TEMP_TAP/tap" fetch origin main
  git -C "$TEMP_TAP/tap" reset --hard origin/main
  python3 scripts/release.py cask "$TAG" "$TEMP_TAP/tap/Casks/jobsdone.rb"
  ruby -c "$TEMP_TAP/tap/Casks/jobsdone.rb"
  git -C "$TEMP_TAP/tap" add -- Casks/jobsdone.rb
  if git -C "$TEMP_TAP/tap" diff --cached --quiet; then exit 0; fi
  git -C "$TEMP_TAP/tap" -c user.name=github-actions\[bot\] -c user.email=41898282+github-actions\[bot\]@users.noreply.github.com commit -m "chore: update jobsdone to $TAG"
  if git -C "$TEMP_TAP/tap" push origin HEAD:main; then exit 0; fi
done
exit 1
