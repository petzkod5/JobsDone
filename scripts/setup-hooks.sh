#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CURRENT=$(git config --get core.hooksPath || true)
if [[ -n "$CURRENT" && "$CURRENT" != .githooks ]]; then
  echo "Existing core.hooksPath ($CURRENT); integrate .githooks/pre-commit before replacing it." >&2
  exit 1
fi
./scripts/setup-lint.sh
git config --local core.hooksPath .githooks
echo 'Installed staged Swift lint pre-commit hook.'
