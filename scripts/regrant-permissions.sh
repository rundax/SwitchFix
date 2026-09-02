#!/bin/bash
set -euo pipefail

# Re-grant TCC permissions after an ad-hoc rebuild.
#
# ⚠️  THIS SCRIPT IS A WORKAROUND, NOT THE FIX.
# Opening the Privacy & Security pane while TCC entries are stale can crash
# Apple's SecurityPrivacyExtension (SIGSEGV in objc_release during
# swift_arrayDestroy — a use-after-free in Apple's code).
#
# The real fix: run scripts/setup-codesign.sh ONCE to create a stable
# code-signing certificate. After that, permissions survive rebuilds
# and you never need this script again.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_BUNDLE="${1:-$PROJECT_DIR/dist/SwitchFix.app}"
BUNDLE_ID="${2:-com.switchfix.app}"
IDENTITY_FILE="$PROJECT_DIR/.codesign-identity"

# ── Suggest the proper fix ───────────────────────────────────────────────────

if [ -f "$IDENTITY_FILE" ]; then
    IDENTITY="$(cat "$IDENTITY_FILE")"
    echo "✅ You have a code-signing certificate configured: \"$IDENTITY\""
    echo "   If you just rebuilt with build-app.sh, permissions should still work."
    echo "   You probably don't need to re-grant."
    echo ""
    read -p "Continue anyway? (y/N) " CONTINUE
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
        exit 0
    fi
else
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║  ⚠️  You're using ad-hoc signing — permissions break every build ║"
    echo "║                                                                ║"
    echo "║  Run scripts/setup-codesign.sh to create a stable certificate. ║"
    echo "║  This is a ONE-TIME setup that eliminates this re-grant cycle. ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""
fi

# ── Clean stale entries first to reduce pane crash risk ──────────────────────

echo "Cleaning stale TCC entries to reduce crash risk..."
"$SCRIPT_DIR/cleanup-tcc.sh" 2>/dev/null || true
echo ""

echo "Stopping running SwitchFix..."
pkill -x SwitchFixApp || true

echo "Resetting TCC permissions for $BUNDLE_ID..."
tccutil reset Accessibility "$BUNDLE_ID" || true
tccutil reset ListenEvent "$BUNDLE_ID" || true

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  IMPORTANT: Close any Privacy & Security windows BEFORE        ║"
echo "║  proceeding. Opening the pane while entries are being           ║"
echo "║  modified can crash Apple's SecurityPrivacyExtension.           ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""
read -p "Press [Enter] when you've closed System Settings... "

echo "Opening Privacy settings (Accessibility)..."
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" || true

echo "Opening Finder with SwitchFix selected (for drag and drop)..."
open -R "$APP_BUNDLE"

cat <<EOF

Step 1: Accessibility
1. If there's an existing 'SwitchFix' entry, select it and click '-' to remove.
2. Drag and drop SwitchFix.app (from the Finder window) into the list.
3. Ensure the toggle is enabled.

EOF

read -p "Press [Enter] when done with Accessibility to continue to Input Monitoring... "

echo "Opening Privacy settings (Input Monitoring)..."
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent" || true

cat <<EOF

Step 2: Input Monitoring
1. If there's an existing 'SwitchFix' entry, select it and click '-' to remove.
2. Drag and drop SwitchFix.app (from the Finder window) into the list.
3. Ensure the toggle is enabled.

EOF

read -p "Press [Enter] when done to launch SwitchFix... "

echo "Launching app: $APP_BUNDLE"
open "$APP_BUNDLE"
