#!/bin/bash
# Build script: creates Leo.app bundle from SPM executable
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="Leo"
BUNDLE_NAME="${APP_NAME}.app"
OUTPUT_DIR="build"
APP_BUNDLE="${OUTPUT_DIR}/${BUNDLE_NAME}"

echo "=== Building ${APP_NAME} (release) ==="

# Step 1: Build with SPM
echo "[1/4] Compiling..."
swift build -c release 2>&1

BUILD_DIR=".build/arm64-apple-macosx/release"
EXECUTABLE="${BUILD_DIR}/${APP_NAME}"

if [ ! -f "$EXECUTABLE" ]; then
    echo "ERROR: Executable not found at $EXECUTABLE"
    echo "Checking .build for executable..."
    find .build -name "$APP_NAME" -type f 2>/dev/null
    exit 1
fi

# Step 2: Create .app bundle structure
echo "[2/4] Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Step 3: Copy files
echo "[3/4] Copying files..."
cp "$EXECUTABLE" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Sources/Resources/Info.plist" "${APP_BUNDLE}/Contents/"

# Copy dictionary and SPM bundle resources
if [ -d "${BUILD_DIR}/Leo_Leo.bundle" ]; then
    cp -r "${BUILD_DIR}/Leo_Leo.bundle" "${APP_BUNDLE}/Contents/Resources/"
fi
# Copy dictionary directly as fallback
mkdir -p "${APP_BUNDLE}/Contents/Resources/Dictionary"
if [ -f "Sources/Resources/Dictionary/cedict.txt" ]; then
    cp "Sources/Resources/Dictionary/cedict.txt" "${APP_BUNDLE}/Contents/Resources/Dictionary/"
fi

# Copy web resources directly (foliate-js, reader.html, reader.js)
if [ -d "Sources/Resources/web" ]; then
    cp -r "Sources/Resources/web" "${APP_BUNDLE}/Contents/Resources/"
fi

# Copy entitlements for signing
ENTITLEMENTS="Sources/Resources/Leo.entitlements"

# Step 4: Sign
echo "[4/4] Signing..."
codesign --force --sign - \
    --entitlements "$ENTITLEMENTS" \
    --deep \
    "${APP_BUNDLE}"

echo ""
echo "=== Build complete ==="
echo "App: ${APP_BUNDLE}"
echo ""
echo "To run: open ${APP_BUNDLE}"
echo "To install: cp -r ${APP_BUNDLE} /Applications/"
