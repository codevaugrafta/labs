#!/usr/bin/env bash
# Build a fresh Tiempo.app and replace /Applications/Tiempo.app.
# Run from repo root: ./Tiempo/scripts/install-to-applications.sh
# Or from Tiempo/: ./scripts/install-to-applications.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "→ Quitting Tiempo (ignore errors if not running)…"
osascript -e 'tell application "Tiempo" to if it is running then quit' 2>/dev/null || true
sleep 1

echo "→ Building release + .app bundle…"
./build-app.sh

echo "→ Installing to /Applications (may prompt for admin)…"
if cp -R build/Tiempo.app /Applications/; then
  echo "→ Opening Tiempo from /Applications…"
  open -a Tiempo
  echo "Done. You should see only Standard + Standard Dark under Theme, and new feedback/motion after a timer tap."
else
  echo "Copy failed. Try: sudo cp -R build/Tiempo.app /Applications/"
  exit 1
fi
