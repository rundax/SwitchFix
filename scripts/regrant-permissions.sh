#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_BUNDLE="${1:-$PROJECT_DIR/dist/SwitchFix.app}"
BUNDLE_ID="${2:-com.switchfix.app}"

echo "Stopping running SwitchFix..."
pkill -x SwitchFixApp || true

echo "Resetting TCC permissions for $BUNDLE_ID..."
tccutil reset Accessibility "$BUNDLE_ID" || true
tccutil reset ListenEvent "$BUNDLE_ID" || true

echo "Opening Privacy settings..."
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" || true
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent" || true

echo "Opening Finder with SwitchFix selected (for drag and drop)..."
open -R "$APP_BUNDLE"

cat <<EOF

==================================================
IMPORTANT: Due to macOS ad-hoc signature changes, 
you CANNOT just re-check the box in System Settings!
==================================================

Next steps in System Settings (for both Accessibility AND Input Monitoring):
1. Select the existing 'SwitchFix' entry and click the '-' button to remove it.
2. Drag and drop the SwitchFix.app (from the opened Finder window) into the list.
3. Ensure the toggle/checkbox is enabled.

EOF

echo "Launching app: $APP_BUNDLE"
open "$APP_BUNDLE"
