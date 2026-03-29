#!/usr/bin/env bash
# Full UX gate: build Leo.app, then run XCUITest via Leo/XcodeUX (no SwiftPM workspace required).
# Run from anywhere: ./Leo/scripts/run-ux-tests.sh  (or cd Leo && ./scripts/run-ux-tests.sh)
# Host may need Accessibility enabled for the test runner if macOS prompts.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "=== Leo UX tests (XCUITest) ==="

UITEST_DATA_DIR="$(mktemp -d "${TMPDIR:-/tmp}/leo-ux.XXXXXX")"
export LEO_UI_TEST_DATA_DIR="$UITEST_DATA_DIR"

pkill -x Leo >/dev/null 2>&1 || true
sleep 1

LEO_BUNDLE_ID_OVERRIDE="com.franciscodilussor.leo.uitest" \
LEO_BUNDLE_STEM_OVERRIDE="LeoUITest" \
./build-app.sh

xcodebuild test \
  -project XcodeUX/LeoUX.xcodeproj \
  -scheme LeoUX \
  -destination 'platform=macOS'

echo "=== UX tests finished ==="
