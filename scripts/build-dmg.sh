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
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

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

# PkgInfo
echo -n "APPL????" > "${APP_DIR}/Contents/PkgInfo"

[ -f "${PROJECT_DIR}/Sources/HolaAI/Resources/AppIcon.icns" ] && \
    cp "${PROJECT_DIR}/Sources/HolaAI/Resources/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"

RESOURCE_BUNDLE=$(find "${BUILD_DIR}/xcode/Build/Products" -name "HolaAI_HolaAI.bundle" -type d 2>/dev/null | head -1)
[ -n "${RESOURCE_BUNDLE}" ] && [ -d "${RESOURCE_BUNDLE}" ] && \
    cp -R "${RESOURCE_BUNDLE}" "${APP_DIR}/Contents/Resources/"

echo "==> Creating entitlements..."
cat > "${BUILD_DIR}/entitlements.plist" << 'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
ENTITLEMENTS

echo "==> Signing app bundle (identity: ${SIGN_IDENTITY})..."
codesign --force --deep --sign "${SIGN_IDENTITY}" \
    --entitlements "${BUILD_DIR}/entitlements.plist" \
    --options runtime \
    "${APP_DIR}"

# Remove quarantine attribute
xattr -cr "${APP_DIR}"

echo "==> Creating DMG..."
mkdir -p "${DMG_DIR}"
cp -R "${APP_DIR}" "${DMG_DIR}/"
ln -s /Applications "${DMG_DIR}/Applications"

hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${DMG_DIR}" \
    -ov -format UDZO \
    "${DMG_OUTPUT}"

# Optional notarization
if [ -n "${NOTARY_PROFILE}" ]; then
    if [ "${SIGN_IDENTITY}" = "-" ]; then
        echo "WARNING: NOTARY_PROFILE is set but SIGN_IDENTITY is ad-hoc. Skipping notarization."
    else
        echo "==> Submitting DMG for notarization..."
        xcrun notarytool submit "${DMG_OUTPUT}" --keychain-profile "${NOTARY_PROFILE}" --wait
        echo "==> Stapling notarization ticket..."
        xcrun stapler staple "${DMG_OUTPUT}"
        xcrun stapler validate "${DMG_OUTPUT}"
    fi
fi

echo ""
echo "==> Done!"
echo "    App: ${APP_DIR}"
echo "    DMG: ${DMG_OUTPUT}"
