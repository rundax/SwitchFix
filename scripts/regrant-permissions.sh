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

echo "Launching app: $APP_BUNDLE"
open "$APP_BUNDLE"

cat <<EOF

Next steps in System Settings:
1. Enable SwitchFix in Accessibility.
2. Enable SwitchFix in Input Monitoring.
3. If asked, quit and re-open the app.

EOF
