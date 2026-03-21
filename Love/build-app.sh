#!/bin/bash
# Build Love.app — run from the Love/ directory
set -e

echo "Building Love (release)..."
swift build -c release

echo "Packaging .app bundle..."
mkdir -p build/Love.app/Contents/MacOS
mkdir -p build/Love.app/Contents/Resources

cp packaging/Info.plist build/Love.app/Contents/Info.plist

cp .build/release/Love build/Love.app/Contents/MacOS/Love
chmod +x build/Love.app/Contents/MacOS/Love

if [ -f build/AppIcon.icns ]; then
    echo "Using build/AppIcon.icns (e.g. from scripts/generate_app_icon_gemini.py)..."
    cp build/AppIcon.icns build/Love.app/Contents/Resources/AppIcon.icns
elif [ ! -f build/Love.app/Contents/Resources/AppIcon.icns ]; then
    echo "Generating app icon (offline)..."
    swift scripts/create-icon.swift
    iconutil -c icns build/AppIcon.iconset -o build/Love.app/Contents/Resources/AppIcon.icns
fi

echo ""
echo "Love.app built at: build/Love.app"
echo ""
echo "To install: cp -R build/Love.app /Applications/"
echo "To run:     open build/Love.app"
