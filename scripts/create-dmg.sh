#!/bin/bash
set -euo pipefail

# Create a DMG containing SwitchFix.app
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$PROJECT_DIR/dist"
APP_BUNDLE="$DIST_DIR/SwitchFix.app"
DMG_NAME="${SWITCHFIX_DMG_NAME:-SwitchFix}"
DMG_PATH="$DIST_DIR/$DMG_NAME.dmg"

# Ensure the app bundle exists
if [ ! -d "$APP_BUNDLE" ]; then
    echo "Error: $APP_BUNDLE not found. Run build-app.sh first."
    exit 1
fi

# Remove old DMG if it exists
rm -f "$DMG_PATH"

# Create a temporary directory for DMG contents
DMG_TEMP="$DIST_DIR/dmg-temp"
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"

# Copy app to temp directory
cp -R "$APP_BUNDLE" "$DMG_TEMP/"

# Create a symbolic link to /Applications
ln -s /Applications "$DMG_TEMP/Applications"

# Create the DMG
echo "Creating DMG..."
hdiutil create -volname "$DMG_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov -format UDZO \
    "$DMG_PATH"

# Clean up
rm -rf "$DMG_TEMP"

echo ""
echo "DMG created: $DMG_PATH"
ls -la "$DMG_PATH"
