#!/usr/bin/env bash
# Open packaged Adhan.app (not `swift run`). Use this to verify menu bar matches release bundle.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
./build-app.sh
open "$SCRIPT_DIR/build/Adhan.app"
echo "Launched: $SCRIPT_DIR/build/Adhan.app"
echo "Install: cp -R \"$SCRIPT_DIR/build/Adhan.app\" /Applications/"
