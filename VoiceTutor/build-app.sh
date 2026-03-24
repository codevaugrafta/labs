#!/bin/bash
# Build IMI.app — run from the VoiceTutor/ directory (executable binary: VoiceTutor)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_BUNDLE="build/IMI.app"

echo "Building IMI (release)..."
swift build -c release

echo "Packaging .app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp packaging/Info.plist "$APP_BUNDLE/Contents/Info.plist"

cp .build/release/VoiceTutor "$APP_BUNDLE/Contents/MacOS/VoiceTutor"
chmod +x "$APP_BUNDLE/Contents/MacOS/VoiceTutor"

# ElevenLabs / LiveKit links LiveKitWebRTC with @rpath; SPM places the framework under .build/release.
# Without this copy, the .app exits immediately (dyld: Library not loaded: LiveKitWebRTC.framework).
WEBRTC_FW="${SCRIPT_DIR}/.build/release/LiveKitWebRTC.framework"
if [ ! -d "$WEBRTC_FW" ]; then
    echo "error: LiveKitWebRTC.framework missing at $WEBRTC_FW — run: swift build -c release" >&2
    exit 1
fi
cp -R "$WEBRTC_FW" "$APP_BUNDLE/Contents/MacOS/"

if [ -f build/AppIcon.icns ]; then
    cp build/AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
else
    echo "Optional: add build/AppIcon.icns for a custom icon."
fi

echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "Code signing (ad-hoc)…"
codesign --force --deep --sign - "$APP_BUNDLE"

echo ""
echo "IMI.app built at: $APP_BUNDLE"

# Keep /Applications in sync so Spotlight/Launchpad and double‑click use the same build as build/.
# Skip in CI or with SKIP_IMI_APPLICATIONS_INSTALL=1 (e.g. read-only sandboxes).
if [ -n "${CI:-}" ] || [ "${SKIP_IMI_APPLICATIONS_INSTALL:-}" = "1" ]; then
  echo "Skipping /Applications install (CI or SKIP_IMI_APPLICATIONS_INSTALL=1)."
else
  echo "→ Quitting IMI if running…"
  osascript -e 'tell application "IMI" to if it is running then quit' 2>/dev/null || true
  sleep 1
  echo "→ Installing to /Applications…"
  cp -R "$APP_BUNDLE" /Applications/
  echo "→ Updated /Applications/IMI.app"
fi

echo ""
echo "To run: open build/IMI.app   or   open -a IMI"
echo "(IMI is LSUIElement — menu bar icon; IMI menu → Show Main Window ⌘O)"
