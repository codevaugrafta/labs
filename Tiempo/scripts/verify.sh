#!/usr/bin/env bash
# Tiempo verification loop — run from repo: ./scripts/verify.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
PASSES="${VERIFY_PASSES:-3}"
for i in $(seq 1 "$PASSES"); do
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Tiempo verify pass $i / $PASSES  —  swift test"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  swift test
done
echo ""
echo "✅ All $PASSES pass(es) completed successfully."
