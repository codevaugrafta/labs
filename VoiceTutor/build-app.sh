#!/bin/bash
# Build VoiceTutor.app — run from the VoiceTutor/ directory
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_BUNDLE="build/VoiceTutor.app"

echo "Building VoiceTutor (release)..."
swift build -c release

echo "Packaging .app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp packaging/Info.plist "$APP_BUNDLE/Contents/Info.plist"

cp .build/release/VoiceTutor "$APP_BUNDLE/Contents/MacOS/VoiceTutor"
chmod +x "$APP_BUNDLE/Contents/MacOS/VoiceTutor"

if [ -f build/AppIcon.icns ]; then
    cp build/AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
else
    echo "Optional: add build/AppIcon.icns for a custom icon."
fi

echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "Code signing (ad-hoc)..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo ""
echo "VoiceTutor.app built at: $APP_BUNDLE"
echo ""
echo "To install: cp -R build/VoiceTutor.app /Applications/"
echo "To run:     open build/VoiceTutor.app"
