#!/usr/bin/env bash
# Starts production Next server, runs Playwright, then stops the server.
# Use when `playwright test` webServer subprocess misbehaves (some sandboxes / agents).
set -euo pipefail
cd "$(dirname "$0")/.."
HOST="${E2E_HOST:-127.0.0.1}"
# Default: ephemeral port so EADDRINUSE on 3000 cannot make tests hit the wrong server.
if [ -n "${E2E_PORT:-}" ]; then
  PORT="$E2E_PORT"
else
  PORT="$(
    node -e "
      const n = require('net');
      const s = n.createServer();
      s.listen(0, '127.0.0.1', () => {
        const p = s.address().port;
        s.close(() => { process.stdout.write(String(p)); process.exit(0); });
      });
    "
  )"
fi
BASE="http://${HOST}:${PORT}"

if [ "${SKIP_E2E_BUILD:-0}" != "1" ]; then
  npm run build
fi
npm run start -- -H "$HOST" -p "$PORT" &
SRV_PID=$!
cleanup() {
  kill "$SRV_PID" 2>/dev/null || true
}
trap cleanup EXIT

# If `next start` fails (e.g. EADDRINUSE), npm exits; do not trust curl alone — another app may be on this port.
sleep 2
if ! kill -0 "$SRV_PID" 2>/dev/null; then
  echo "Server process exited immediately. If you pinned E2E_PORT, pick a free port." >&2
  exit 1
fi

echo "Waiting for ${BASE} (this app’s HTML) …" >&2
ready=0
for i in $(seq 1 90); do
  if curl -sf "${BASE}/" | grep -q '<title>Pomodoro</title>'; then
    echo "Server ready (attempt ${i})." >&2
    ready=1
    break
  fi
  sleep 1
done
if [ "$ready" != "1" ]; then
  echo "Server did not serve this app after 90s at ${BASE}/ (expected <title>Pomodoro</title>)." >&2
  exit 1
fi

export CI=true
export PLAYWRIGHT_TEST_BASE_URL="$BASE"
echo "Running Playwright…" >&2
exec npx playwright test --reporter=line "$@"
