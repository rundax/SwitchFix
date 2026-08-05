#!/bin/bash
set -e

echo "=========================================="
echo "      SwitchFix Installer                 "
echo "=========================================="
echo ""

# Get the directory where the script is located (the mounted DMG)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_SOURCE="$SCRIPT_DIR/SwitchFix.app"
APP_DEST="/Applications/SwitchFix.app"

if [ ! -d "$APP_SOURCE" ]; then
    echo "❌ Error: Could not find SwitchFix.app in the same directory as this script."
    echo "Please run this script from inside the downloaded DMG."
    exit 1
fi

echo "📦 Installing SwitchFix to /Applications..."
# Stop running app if any
pkill -x SwitchFixApp || true

if [ -d "$APP_DEST" ]; then
    echo "Removing older version..."
    rm -rf "$APP_DEST"
fi
cp -R "$APP_SOURCE" "/Applications/"
echo "✅ Installed successfully."

echo ""
echo "🔓 Removing Gatekeeper quarantine..."
# This removes the "App is damaged" error for unsigned apps
xattr -cr "$APP_DEST"
echo "✅ Quarantine removed."

echo ""
echo "🔄 Setting up 'Start at Login'..."
osascript -e 'tell application "System Events" to delete login item "SwitchFix"' > /dev/null 2>&1 || true
osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/SwitchFix.app", hidden:false}' > /dev/null 2>&1
echo "✅ Added to startup items."

echo ""
echo "🛡️ Setting up macOS Permissions..."
echo "macOS requires explicit permissions for SwitchFix to intercept keyboard input."
echo ""
read -p "Press [Enter] to begin..."

echo ""
echo "Opening Privacy settings (Accessibility)..."
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" || true

echo "Opening Finder with SwitchFix selected (for drag and drop)..."
open -R "$APP_DEST"

cat <<EOF

==================================================
IMPORTANT: Due to macOS ad-hoc signature changes, 
you CANNOT just re-check the box in System Settings!
==================================================

Step 1: Accessibility
1. Select the existing 'SwitchFix' entry and click the '-' button to remove it.
2. Drag and drop the SwitchFix.app (from the opened Finder window) into the list.
3. Ensure the toggle/checkbox is enabled.

EOF

read -p "Press [Enter] when you are done with Accessibility to move to Input Monitoring... "

echo "Opening Privacy settings (Input Monitoring)..."
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent" || true

cat <<EOF

Step 2: Input Monitoring
1. Select the existing 'SwitchFix' entry and click the '-' button to remove it.
2. Drag and drop the SwitchFix.app (from the Finder window) into the list.
3. Ensure the toggle/checkbox is enabled.

EOF

read -p "Press [Enter] when you are done to launch SwitchFix... "

echo "Launching app: $APP_DEST"
open "$APP_DEST"

echo ""
echo "🎉 Setup Complete! You can now close this terminal window and unmount the DMG."
