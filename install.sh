#!/bin/bash
set -e

# ==========================================
# SwitchFix User-Friendly Installer
# ==========================================

echo "=========================================="
echo "      Welcome to SwitchFix Setup!         "
echo "=========================================="
echo ""
echo "This script will:"
echo " 1. Build the app from source"
echo " 2. Install it to your Applications folder"
echo " 3. Set it to automatically start at login"
echo " 4. Guide you through the privacy permissions"
echo ""
sleep 2

# 1. Check for Swift (Xcode Command Line Tools)
if ! command -v swift &> /dev/null; then
    echo "⚠️ Apple's Command Line Tools are required to build SwitchFix."
    echo "A system prompt should appear to install them. Please follow the instructions, and then run this script again."
    xcode-select --install
    exit 1
fi

# 2. Build the app
echo "🚀 Step 1: Building SwitchFix..."
if [ -f "./scripts/build-app.sh" ]; then
    ./scripts/build-app.sh
else
    echo "❌ Error: Could not find scripts/build-app.sh. Make sure you are running this from the root of the SwitchFix repository."
    exit 1
fi

# 3. Install to /Applications
echo ""
echo "📦 Step 2: Installing to Applications folder..."

APP_WAS_RUNNING=0
if pgrep -x "SwitchFixApp" > /dev/null; then
    APP_WAS_RUNNING=1
    echo "Stopping currently running SwitchFixApp..."
    pkill -x "SwitchFixApp" || true
    sleep 1
fi

if [ -d "/Applications/SwitchFix.app" ]; then
    echo "Removing older version from /Applications..."
    rm -rf "/Applications/SwitchFix.app"
fi
cp -R "./dist/SwitchFix.app" "/Applications/"
echo "✅ Installed to /Applications/SwitchFix.app"

# 4. Add to Startup (Login Items)
echo ""
echo "🔄 Step 3: Setting up 'Start at Login'..."
# Remove any existing login item to avoid duplicates (ignoring errors if it doesn't exist)
osascript -e 'tell application "System Events" to delete login item "SwitchFix"' > /dev/null 2>&1 || true
# Add the new login item
osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/SwitchFix.app", hidden:false}' > /dev/null 2>&1
echo "✅ SwitchFix has been added to your startup items."

# 5. Handle Permissions
echo ""
if [ -f ".codesign-identity" ]; then
    # Stable certificate — permissions survive rebuilds.
    # Check if SwitchFix already has Accessibility permission by attempting
    # a quick AX trust check (the app itself does this on launch).
    echo "✅ Signed with stable certificate — permissions survive rebuilds."
    echo ""
    echo "   If this is your first install, you'll need to grant Accessibility"
    echo "   and Input Monitoring permissions manually:"
    echo "   System Settings → Privacy & Security → Accessibility → add SwitchFix"
    echo "   System Settings → Privacy & Security → Input Monitoring → add SwitchFix"
    echo ""
    echo "Launching SwitchFix..."
    open "/Applications/SwitchFix.app"
else
    echo "🛡️ Step 4: Setting up macOS Permissions..."
    echo "Because SwitchFix intercepts keyboard input to fix layouts, macOS requires you to grant it explicit permissions."
    echo ""
    read -p "Press [Enter] to begin the permission setup..."

    ./scripts/regrant-permissions.sh "/Applications/SwitchFix.app"
fi

echo ""
echo "🎉 Setup Complete! SwitchFix is now installed and running."
echo ""
echo "📋 To watch live debug logs, run:"
echo "   log stream --level debug --style compact --predicate 'subsystem == \"com.switchfix\"'"
echo ""

