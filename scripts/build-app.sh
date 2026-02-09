#!/bin/bash
set -euo pipefail

# Build SwitchFix.app bundle from SPM release build
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build"
APP_NAME="SwitchFix"
APP_BUNDLE="$PROJECT_DIR/dist/$APP_NAME.app"

echo "Building $APP_NAME in release mode..."
cd "$PROJECT_DIR"
swift build -c release

# Determine the build products directory
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    PRODUCTS_DIR="$BUILD_DIR/arm64-apple-macosx/release"
else
    PRODUCTS_DIR="$BUILD_DIR/x86_64-apple-macosx/release"
fi

# Fallback: check which directory exists
if [ ! -d "$PRODUCTS_DIR" ]; then
    PRODUCTS_DIR="$BUILD_DIR/release"
fi

echo "Products directory: $PRODUCTS_DIR"

# Clean previous bundle
rm -rf "$APP_BUNDLE"

# Create .app bundle structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy Info.plist
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/"

# Copy the executable
cp "$PRODUCTS_DIR/SwitchFixApp" "$APP_BUNDLE/Contents/MacOS/"

# Copy the dictionary bundle
if [ -d "$PRODUCTS_DIR/SwitchFix_Dictionary.bundle" ]; then
    cp -R "$PRODUCTS_DIR/SwitchFix_Dictionary.bundle" "$APP_BUNDLE/Contents/Resources/"
    echo "Copied dictionary bundle."
fi

# Ad-hoc code sign
echo "Signing with ad-hoc identity..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo ""
echo "Build complete: $APP_BUNDLE"
echo ""
ls -la "$APP_BUNDLE/Contents/MacOS/"
echo ""
du -sh "$APP_BUNDLE"
