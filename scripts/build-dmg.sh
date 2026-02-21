#!/bin/bash
set -euo pipefail

VERSION="${1:-1.0.0}"
APP_NAME="Hola-AI"
BUNDLE_NAME="${APP_NAME}.app"
BUILD_DIR="/tmp/HolaAI-release"
APP_DIR="${BUILD_DIR}/${BUNDLE_NAME}"
DMG_DIR="${BUILD_DIR}/dmg"
DMG_OUTPUT="${BUILD_DIR}/${APP_NAME}-macOS-${VERSION}.dmg"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> Building ${APP_NAME} v${VERSION}..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

echo "==> Compiling release build..."
xcodebuild -scheme HolaAI \
    -destination 'platform=macOS' \
    -configuration Release \
    -derivedDataPath "${BUILD_DIR}/xcode" \
    build 2>&1 | tail -5

BINARY="${BUILD_DIR}/xcode/Build/Products/Release/HolaAI"

if [ ! -f "${BINARY}" ]; then
    echo "Trying Debug..."
    xcodebuild -scheme HolaAI \
        -destination 'platform=macOS' \
        -derivedDataPath "${BUILD_DIR}/xcode" \
        build 2>&1 | tail -5
    BINARY="${BUILD_DIR}/xcode/Build/Products/Debug/HolaAI"
fi

[ ! -f "${BINARY}" ] && echo "ERROR: Binary not found" && exit 1

echo "==> Creating app bundle..."
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BINARY}" "${APP_DIR}/Contents/MacOS/HolaAI"
cp "${PROJECT_DIR}/Info.plist" "${APP_DIR}/Contents/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" "${APP_DIR}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${APP_DIR}/Contents/Info.plist"

[ -f "${PROJECT_DIR}/Sources/HolaAI/Resources/AppIcon.icns" ] && \
    cp "${PROJECT_DIR}/Sources/HolaAI/Resources/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"

RESOURCE_BUNDLE=$(find "${BUILD_DIR}/xcode/Build/Products" -name "HolaAI_HolaAI.bundle" -type d 2>/dev/null | head -1)
[ -n "${RESOURCE_BUNDLE}" ] && [ -d "${RESOURCE_BUNDLE}" ] && \
    cp -R "${RESOURCE_BUNDLE}" "${APP_DIR}/Contents/Resources/"

echo "==> Creating DMG..."
mkdir -p "${DMG_DIR}"
cp -R "${APP_DIR}" "${DMG_DIR}/"
ln -s /Applications "${DMG_DIR}/Applications"

hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${DMG_DIR}" \
    -ov -format UDZO \
    "${DMG_OUTPUT}"

echo ""
echo "==> Done!"
echo "    App: ${APP_DIR}"
echo "    DMG: ${DMG_OUTPUT}"
