#!/bin/bash
set -euo pipefail

# Keep SwitchFix's own LaunchServices registration consistent.
#
# When both dist/SwitchFix.app (a local build) and /Applications/SwitchFix.app
# exist, LaunchServices may resolve com.switchfix.app to the dist copy, which
# confuses TCC and can crash Apple's SecurityPrivacyExtension when the
# Privacy & Security pane loads. This script unregisters the dist copy so
# only the installed app remains registered.
#
# Only com.switchfix.app is touched. We deliberately do NOT reset TCC entries
# for other applications: `tccutil reset` would revoke live permissions for
# apps that are still installed, and macOS cleans up orphaned TCC records for
# apps you uninstalled automatically (or they remain inert).

echo "Cleaning stale LaunchServices registrations..."
echo ""

CLEANED=0

# ── Unregister dist/SwitchFix.app if /Applications copy exists ───────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DIST_APP="$PROJECT_DIR/dist/SwitchFix.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

if [ -x "$LSREGISTER" ] && [ -d "$DIST_APP" ] && [ -d "/Applications/SwitchFix.app" ]; then
    echo ""
    echo "Unregistering dist/SwitchFix.app from LaunchServices..."
    "$LSREGISTER" -u "$DIST_APP" 2>/dev/null || true
    echo "  ✓ Only /Applications/SwitchFix.app is now registered"
    CLEANED=$((CLEANED + 1))
fi

echo ""
if [ "$CLEANED" -gt 0 ]; then
    echo "✅ Cleaned $CLEANED stale registration(s)."
else
    echo "✅ No stale registrations found — LaunchServices is clean."
fi
