#!/usr/bin/env bash
# Build a fresh Love.app and copy it to /Applications so it appears in Launchpad & Spotlight.
# Does not add a Dock icon (Love is LSUIElement — use the menu bar heart after launch).
# Run from repo: ./Love/scripts/install-to-applications.sh
# Or from Love/: ./scripts/install-to-applications.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "→ Quitting Love (ignore errors if not running)…"
osascript -e 'tell application "Love" to if it is running then quit' 2>/dev/null || true
sleep 1

echo "→ Building release + .app bundle…"
./build-app.sh

echo "→ Installing to /Applications (may prompt for admin if permissions fail)…"
if cp -R build/Love.app /Applications/; then
  echo "→ Opening Love from /Applications…"
  open -a Love
  echo ""
  echo "Done. Love will not show in the Dock — check the menu bar (top right) for the heart icon."
  echo "Main window: menu bar → Show main window (⌘O). Quick capture: ⌃⌥L"
else
  echo "Copy failed. Try: sudo cp -R build/Love.app /Applications/"
  exit 1
fi
