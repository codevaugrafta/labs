#!/bin/bash
# Build script: creates Leo.app bundle from SPM executable
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="Leo"
BUNDLE_STEM="${LEO_BUNDLE_STEM_OVERRIDE:-${APP_NAME}}"
BUNDLE_NAME="${BUNDLE_STEM}.app"
BUNDLE_ID="${LEO_BUNDLE_ID_OVERRIDE:-com.franciscodilussor.leo}"
OUTPUT_DIR="build"
APP_BUNDLE="${OUTPUT_DIR}/${BUNDLE_NAME}"
TMP_BUNDLE="${OUTPUT_DIR}/.${BUNDLE_NAME}.tmp.$$"
BACKUP_BUNDLE="${OUTPUT_DIR}/.${BUNDLE_NAME}.bak.$$"
LOCK_DIR="${OUTPUT_DIR}/.build-app.lock"
INFO_PLIST_PATH="${TMP_BUNDLE}/Contents/Info.plist"

mkdir -p "${OUTPUT_DIR}"

acquire_lock() {
    local waited=0
    while ! mkdir "${LOCK_DIR}" 2>/dev/null; do
        if [ "${waited}" -eq 0 ]; then
            echo "Waiting for another Leo bundle build to finish..."
        fi
        waited=$((waited + 1))
        sleep 0.2
    done
}

cleanup() {
    rm -rf "${TMP_BUNDLE}" "${BACKUP_BUNDLE}" 2>/dev/null || true
    rmdir "${LOCK_DIR}" 2>/dev/null || true
}

acquire_lock
trap cleanup EXIT

echo "=== Building ${BUNDLE_STEM} (release) ==="

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
rm -rf "${TMP_BUNDLE}" "${BACKUP_BUNDLE}"
mkdir -p "${TMP_BUNDLE}/Contents/MacOS"
mkdir -p "${TMP_BUNDLE}/Contents/Resources"

# Step 3: Copy files
echo "[3/4] Copying files..."
cp "$EXECUTABLE" "${TMP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Sources/Resources/Info.plist" "${TMP_BUNDLE}/Contents/"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BUNDLE_ID}" "${INFO_PLIST_PATH}" >/dev/null
/usr/libexec/PlistBuddy -c "Set :CFBundleName ${BUNDLE_STEM}" "${INFO_PLIST_PATH}" >/dev/null
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName ${BUNDLE_STEM}" "${INFO_PLIST_PATH}" >/dev/null

# Copy dictionary and SPM bundle resources
if [ -d "${BUILD_DIR}/Leo_Leo.bundle" ]; then
    cp -r "${BUILD_DIR}/Leo_Leo.bundle" "${TMP_BUNDLE}/Contents/Resources/"
fi
# Copy dictionary directly as fallback
mkdir -p "${TMP_BUNDLE}/Contents/Resources/Dictionary"
if [ -f "Sources/Resources/Dictionary/cedict.txt" ]; then
    cp "Sources/Resources/Dictionary/cedict.txt" "${TMP_BUNDLE}/Contents/Resources/Dictionary/"
fi

# Copy web resources directly (foliate-js, reader.html, reader.js)
if [ -d "Sources/Resources/web" ]; then
    cp -r "Sources/Resources/web" "${TMP_BUNDLE}/Contents/Resources/"
fi

# Copy entitlements for signing
ENTITLEMENTS="Sources/Resources/Leo.entitlements"

# Step 4: Sign
echo "[4/4] Signing..."
codesign --force --sign - \
    --entitlements "$ENTITLEMENTS" \
    --deep \
    "${TMP_BUNDLE}"

if [ -e "${APP_BUNDLE}" ]; then
    mv "${APP_BUNDLE}" "${BACKUP_BUNDLE}"
fi
mv "${TMP_BUNDLE}" "${APP_BUNDLE}"
rm -rf "${BACKUP_BUNDLE}"

echo ""
echo "=== Build complete ==="
echo "App: ${APP_BUNDLE}"
echo ""
echo "To run: open ${APP_BUNDLE}"
echo "To install: cp -r ${APP_BUNDLE} /Applications/"
