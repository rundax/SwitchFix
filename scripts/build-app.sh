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

# Build AppIcon.icns from AppIcon.svg for Finder/Launchpad
ICON_SVG="$PROJECT_DIR/Resources/Assets.xcassets/AppIcon.svg"
if [ -f "$ICON_SVG" ]; then
    if command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then
        ICON_TMP_DIR="$(mktemp -d)"
        ICONSET_DIR="$ICON_TMP_DIR/AppIcon.iconset"
        MASTER_PNG="$ICON_TMP_DIR/AppIcon-1024.png"
        mkdir -p "$ICONSET_DIR"

        sips -s format png "$ICON_SVG" --out "$MASTER_PNG" >/dev/null
        sips -z 16 16 "$MASTER_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
        sips -z 32 32 "$MASTER_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
        sips -z 32 32 "$MASTER_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
        sips -z 64 64 "$MASTER_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
        sips -z 128 128 "$MASTER_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
        sips -z 256 256 "$MASTER_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
        sips -z 256 256 "$MASTER_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
        sips -z 512 512 "$MASTER_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
        sips -z 512 512 "$MASTER_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
        cp "$MASTER_PNG" "$ICONSET_DIR/icon_512x512@2x.png"

        iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
        cp "$ICON_SVG" "$APP_BUNDLE/Contents/Resources/"

        rm -rf "$ICON_TMP_DIR"
        echo "Generated AppIcon.icns from AppIcon.svg."
        echo "Copied AppIcon.svg to Contents/Resources/."
    else
        echo "WARNING: sips/iconutil not available. App icon was not generated."
    fi
fi

# Copy the dictionary bundle to Contents/Resources (standard macOS location)
if [ -d "$PRODUCTS_DIR/SwitchFix_Dictionary.bundle" ]; then
    cp -R "$PRODUCTS_DIR/SwitchFix_Dictionary.bundle" "$APP_BUNDLE/Contents/Resources/"
    echo "Copied dictionary bundle to Contents/Resources/."
fi

# Code sign
# Prefer a stable signing identity (set via SWITCHFIX_CODESIGN_IDENTITY) so
# macOS TCC permissions survive across rebuilds.
if [ -n "${SWITCHFIX_CODESIGN_IDENTITY:-}" ]; then
    echo "Signing with identity: $SWITCHFIX_CODESIGN_IDENTITY"
    codesign --force --deep --sign "$SWITCHFIX_CODESIGN_IDENTITY" "$APP_BUNDLE"
else
    echo "Signing with ad-hoc identity..."
    codesign --force --deep --sign - "$APP_BUNDLE"
    echo "WARNING: ad-hoc signature changes on each rebuild."
    echo "         Accessibility/Input Monitoring may need to be granted again."
    echo "         Use scripts/regrant-permissions.sh after rebuilding."
fi

echo ""
echo "Build complete: $APP_BUNDLE"
echo ""
ls -la "$APP_BUNDLE/Contents/MacOS/"
echo ""
du -sh "$APP_BUNDLE"
