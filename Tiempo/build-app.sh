#!/bin/bash
# Build Tiempo.app — run from the Tiempo/ directory
set -e

echo "Building Tiempo (release)..."
swift build -c release

echo "Packaging .app bundle..."
mkdir -p build/Tiempo.app/Contents/MacOS
mkdir -p build/Tiempo.app/Contents/Resources

cp packaging/Info.plist build/Tiempo.app/Contents/Info.plist

cp .build/release/Tiempo build/Tiempo.app/Contents/MacOS/Tiempo
chmod +x build/Tiempo.app/Contents/MacOS/Tiempo

# Generate icon if not present
if [ ! -f build/Tiempo.app/Contents/Resources/AppIcon.icns ]; then
    echo "Generating app icon..."
    swift scripts/create-icon.swift
    iconutil -c icns build/AppIcon.iconset -o build/Tiempo.app/Contents/Resources/AppIcon.icns
fi

echo ""
echo "✅ Tiempo.app built at: build/Tiempo.app"
echo ""
echo "To install: cp -R build/Tiempo.app /Applications/"
echo "To run:     open build/Tiempo.app"
