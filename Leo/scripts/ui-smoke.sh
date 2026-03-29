#!/usr/bin/env bash
# Minimal UI smoke: build .app, launch Leo, verify process (and windows if Accessibility allows).
# Run from repo: ./Leo/scripts/ui-smoke.sh
# If window check fails: grant Accessibility to the calling app, or LEO_UI_SMOKE_SKIP_AX=1 for process-only.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "=== Leo UI smoke ==="
./build-app.sh

APP="$ROOT/build/Leo.app"
APP_BIN="$APP/Contents/MacOS/Leo"
SMOKE_DATA_DIR="$(mktemp -d "${TMPDIR:-/tmp}/leo-ui-smoke.XXXXXX")"

pkill -x Leo >/dev/null 2>&1 || true
sleep 1

LEO_UI_TEST_DATA_DIR="$SMOKE_DATA_DIR" "$APP_BIN" >/tmp/leo-ui-smoke.log 2>&1 &
LAUNCH_PID=$!

found=""
for _ in $(seq 1 60); do
  if pgrep -x Leo >/dev/null 2>&1; then
    found=1
    break
  fi
  sleep 0.25
done

if [[ -z "$found" ]]; then
  echo "FAIL: Leo process never appeared"
  exit 1
fi
echo "OK: process running"

if [[ "${LEO_UI_SMOKE_SKIP_AX:-}" == "1" ]]; then
  echo "SKIP: window check (LEO_UI_SMOKE_SKIP_AX=1)"
else
  osascript -e 'tell application "Leo" to activate' >/dev/null 2>&1 || true
  sleep 1
  w=$(osascript -e 'tell application "System Events" to tell process "Leo" to count windows' 2>/dev/null || echo "0")
  if [[ "${w:-0}" =~ ^[1-9] ]]; then
    echo "OK: windows=$w"
  else
    echo "WARN: window check got '$w' — enable Accessibility for this terminal/IDE, or use LEO_UI_SMOKE_SKIP_AX=1"
  fi
fi

osascript -e 'quit app "Leo"' 2>/dev/null || true
sleep 1
if pgrep -x Leo >/dev/null 2>&1; then
  echo "WARN: forcing killall Leo"
  killall Leo 2>/dev/null || true
fi
kill "$LAUNCH_PID" >/dev/null 2>&1 || true

echo "=== UI smoke finished ==="
