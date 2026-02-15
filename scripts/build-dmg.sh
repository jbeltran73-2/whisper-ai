#!/bin/bash
set -e

# Configuration
APP_NAME="Hola-AI"
BUNDLE_ID="com.holaai.app"
VERSION="1.0.2"

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build/release"
DIST_DIR="$PROJECT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"

echo "🔨 Building $APP_NAME v$VERSION..."

# Clean previous build
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# Build release version
cd "$PROJECT_DIR"
swift build -c release

echo "📦 Creating app bundle..."

# Create app bundle structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp "$BUILD_DIR/HolaAI" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>Hola-AI</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Hola-AI needs access to your microphone to transcribe your speech.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Hola-AI needs accessibility access to insert transcribed text into other applications.</string>
</dict>
</plist>
EOF

# Copy app icon
if [ -f "$PROJECT_DIR/Sources/HolaAI/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Sources/HolaAI/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
    echo "📎 Added app icon"
fi

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Create entitlements file for permissions
cat > "$DIST_DIR/entitlements.plist" << EOF
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
EOF

# Copy any resources if they exist
if [ -d "$PROJECT_DIR/Sources/HolaAI/Resources" ]; then
    cp -r "$PROJECT_DIR/Sources/HolaAI/Resources"/* "$APP_BUNDLE/Contents/Resources/" 2>/dev/null || true
fi

echo "🔏 Signing app (ad-hoc)..."

# Sign with ad-hoc signature to avoid "damaged" error
codesign --force --deep --sign - --entitlements "$DIST_DIR/entitlements.plist" "$APP_BUNDLE"

# Remove quarantine attribute just in case
xattr -cr "$APP_BUNDLE"

echo "💿 Creating DMG..."

# Create DMG
DMG_NAME="$APP_NAME-$VERSION"
DMG_PATH="$DIST_DIR/$DMG_NAME.dmg"
DMG_TEMP="$DIST_DIR/dmg_temp"

# Create temporary directory for DMG contents
mkdir -p "$DMG_TEMP"
cp -r "$APP_BUNDLE" "$DMG_TEMP/"

# Create symbolic link to Applications folder
ln -s /Applications "$DMG_TEMP/Applications"

# Create README
cat > "$DMG_TEMP/README.txt" << EOF
Hola-AI - Voice Dictation App
================================

Installation:
1. Drag Hola-AI.app to the Applications folder
2. Open Hola-AI from Applications
3. The app will appear in your menu bar (top right)
4. Click the icon → Preferences to add your OpenRouter API key
5. Grant microphone and accessibility permissions when prompted

Usage:
- Press Cmd+Shift+D to start/stop dictation
- Press Cmd+Shift+C for voice command mode
- Speak naturally - the app will transcribe and insert text

Get your OpenRouter API key at: https://openrouter.ai/keys

Requirements:
- macOS 13.0 (Ventura) or later
- OpenRouter API key with access to your selected STT and prompt models

EOF

# Create DMG using hdiutil
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_TEMP" -ov -format UDZO "$DMG_PATH"

# Cleanup
rm -rf "$DMG_TEMP"

echo ""
echo "✅ Build complete!"
echo ""
echo "📍 App bundle: $APP_BUNDLE"
echo "📍 DMG file:   $DMG_PATH"
echo ""
echo "📤 Share the DMG with your team. They will need to:"
echo "   1. Open the DMG and drag the app to Applications"
echo "   2. Right-click → Open (first time, to bypass Gatekeeper)"
echo "   3. Add their own OpenRouter API key in Preferences"
echo "   4. Grant microphone + accessibility permissions"
