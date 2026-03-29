#!/bin/zsh
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
EXPECTED_BRANCH="leo/v1.0-digital-vellum"
FALLBACK_BRANCH="leo/v0.2-consolidation"
CURRENT_BRANCH="$(git -C "$ROOT" branch --show-current)"
LEO_STATUS="$(git -C "$ROOT" status --short Leo)"

if [[ "$CURRENT_BRANCH" != "$EXPECTED_BRANCH" ]]; then
  echo "Leo branch gate failed: current branch is '$CURRENT_BRANCH', expected '$EXPECTED_BRANCH'."
  exit 1
fi

if [[ -n "$LEO_STATUS" ]]; then
  echo "Leo branch gate failed: 'git status --short Leo' is not clean."
  echo "$LEO_STATUS"
  exit 1
fi

echo "Leo branch gate passed."
echo "branch: $CURRENT_BRANCH"
echo "leo status: clean"
echo "authoritative delta:"
git -C "$ROOT" log --oneline "${FALLBACK_BRANCH}..${EXPECTED_BRANCH}" -- Leo
