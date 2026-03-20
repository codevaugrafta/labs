#!/bin/bash
# Build script: creates Adhan.app bundle from SPM executable
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="Adhan"
BUNDLE_NAME="${APP_NAME}.app"
OUTPUT_DIR="build"
APP_BUNDLE="${OUTPUT_DIR}/${BUNDLE_NAME}"

echo "=== Building ${APP_NAME} (release) ==="

# Step 1: Build with SPM
echo "[1/4] Compiling..."
swift build -c release 2>&1

BUILD_DIR=".build/arm64-apple-macosx/release"
EXECUTABLE="${BUILD_DIR}/AdhanApp"

if [ ! -f "$EXECUTABLE" ]; then
    echo "ERROR: Executable not found at $EXECUTABLE"
    exit 1
fi

# Step 2: Create .app bundle structure
echo "[2/4] Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources/Audio"

# Step 3: Copy files
echo "[3/4] Copying files..."
cp "$EXECUTABLE" "${APP_BUNDLE}/Contents/MacOS/AdhanApp"
cp "Sources/Resources/Info.plist" "${APP_BUNDLE}/Contents/"

# Copy app icon
if [ -f "Sources/Resources/AppIcon.icns" ]; then
    cp "Sources/Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/"
    echo "  Copied app icon"
fi

# Copy audio files if they exist
if ls Sources/Resources/Audio/*.m4a &>/dev/null 2>&1; then
    cp Sources/Resources/Audio/*.m4a "${APP_BUNDLE}/Contents/Resources/Audio/"
    echo "  Copied audio files"
fi
if ls Sources/Resources/Audio/*.caf &>/dev/null 2>&1; then
    cp Sources/Resources/Audio/*.caf "${APP_BUNDLE}/Contents/Resources/Audio/"
fi
if [ -f "Sources/Resources/Audio/ATTRIBUTION.md" ]; then
    cp Sources/Resources/Audio/ATTRIBUTION.md "${APP_BUNDLE}/Contents/Resources/Audio/"
    echo "  Copied audio attribution"
fi

# Create PkgInfo
echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

# Step 4: Ad-hoc sign (required for notifications + launch-at-login)
echo "[4/4] Code signing (ad-hoc)..."
codesign --force --deep --sign - \
    --entitlements "Sources/Resources/Adhan.entitlements" \
    "$APP_BUNDLE" 2>&1

echo ""
echo "=== Build complete ==="
echo "App bundle: $(pwd)/${APP_BUNDLE}"
echo ""
echo "To run:  open ${APP_BUNDLE}"
echo "To install: cp -r ${APP_BUNDLE} /Applications/"
echo ""

# Verify
if [ -f "${APP_BUNDLE}/Contents/MacOS/AdhanApp" ]; then
    echo "Bundle size: $(du -sh "$APP_BUNDLE" | cut -f1)"
    echo "Signed: $(codesign -v "$APP_BUNDLE" 2>&1 && echo "YES" || echo "NO")"
fi
