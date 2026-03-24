#!/usr/bin/env bash
# Build IMI.app; `build-app.sh` installs to /Applications by default. This script
# forces install (even if SKIP_IMI_APPLICATIONS_INSTALL is set in the environment) and opens the app.
# IMI is LSUIElement — no Dock icon; use the menu bar after launch.
# Run from repo: ./VoiceTutor/scripts/install-to-applications.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "→ Building release + .app bundle + /Applications…"
SKIP_IMI_APPLICATIONS_INSTALL= ./build-app.sh

echo "→ Opening IMI…"
open -a IMI
echo ""
echo "Done. IMI does not show in the Dock — check the menu bar for the speech-bubbles icon."
echo "Main window: IMI menu → Show Main Window (⌘O)."
