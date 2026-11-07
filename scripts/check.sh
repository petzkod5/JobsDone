#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Match CI's downloaded tool versions; installation is separate from checking.
for TOOL in actionlint shellcheck; do
  command -v "$TOOL" >/dev/null || { echo "Missing required tool: $TOOL" >&2; exit 1; }
done
[[ "$(actionlint -version 2>&1 | head -n 1)" == '1.7.12' ]] || { echo 'Use actionlint 1.7.12' >&2; exit 1; }
[[ "$(shellcheck --version)" == *'version: 0.11.0'* ]] || { echo 'Use ShellCheck 0.11.0' >&2; exit 1; }

SHELL_FILES=()
WORKFLOW_FILES=()
while IFS= read -r -d '' FILE; do
  SHELL_FILES+=("$FILE")
done < <(git ls-files -z -- '*.sh' '*.bash')
while IFS= read -r -d '' FILE; do
  WORKFLOW_FILES+=("$FILE")
done < <(git ls-files -z -- '.github/workflows/*.yml' '.github/workflows/*.yaml')

# Errors and warnings catch unsafe shell use without imposing formatting policy.
if ((${#SHELL_FILES[@]})); then
  shellcheck --severity=warning "${SHELL_FILES[@]}"
fi
if ((${#WORKFLOW_FILES[@]})); then
  actionlint "${WORKFLOW_FILES[@]}"
  python3 scripts/check-runners.py "${WORKFLOW_FILES[@]}"
fi
