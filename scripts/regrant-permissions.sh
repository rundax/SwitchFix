#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_BUNDLE="${1:-$PROJECT_DIR/dist/SwitchFix.app}"
BUNDLE_ID="${2:-com.switchfix.app}"

if [ ! -d "$APP_BUNDLE" ]; then
  echo "Error: app bundle not found at $APP_BUNDLE" >&2
  exit 1
fi

echo "Stopping running SwitchFix..."
pkill -x SwitchFixApp || true

echo "Resetting TCC permissions for $BUNDLE_ID..."
if ! tccutil reset Accessibility "$BUNDLE_ID"; then
  echo "Warning: failed to reset Accessibility permissions for $BUNDLE_ID" >&2
fi
if ! tccutil reset ListenEvent "$BUNDLE_ID"; then
  echo "Warning: failed to reset Input Monitoring permissions for $BUNDLE_ID" >&2
fi

echo "Opening Privacy settings (Accessibility)..."
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" || true

echo "Opening Finder with SwitchFix selected (for drag and drop)..."
open -R "$APP_BUNDLE"

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

echo "Launching app: $APP_BUNDLE"
open "$APP_BUNDLE"
