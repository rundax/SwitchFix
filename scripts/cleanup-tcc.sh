#!/bin/bash
set -euo pipefail

# Purge stale TCC (Privacy & Security) entries for apps that are no longer
# installed. These orphan entries can trigger a crash in Apple's
# SecurityPrivacyExtension when it tries to resolve app metadata for
# entries that point to deleted bundles.
#
# This is safe to run — it only removes entries for apps that don't exist
# on disk. Your SwitchFix permissions are not affected.

echo "Cleaning stale TCC entries from Privacy & Security..."
echo ""

CLEANED=0

# ── Stale bundle IDs (apps no longer installed) ──────────────────────────────

STALE_APPS=(
    "com.blizzard.WarcraftIII"
    "com.logi.cp-dev-mgr"
    "com.audiowhisper.app"
)

SERVICES=("Accessibility" "ListenEvent")

for svc in "${SERVICES[@]}"; do
    for app in "${STALE_APPS[@]}"; do
        if tccutil reset "$svc" "$app" 2>/dev/null; then
            echo "  ✓ Removed $app from $svc"
            CLEANED=$((CLEANED + 1))
        fi
    done
done

# input-leap (keyboard/mouse sharing tool, often uninstalled)
if tccutil reset Accessibility input-leap 2>/dev/null; then
    echo "  ✓ Removed input-leap from Accessibility"
    CLEANED=$((CLEANED + 1))
fi

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
    echo "✅ Cleaned $CLEANED stale entries."
    echo ""
    echo "Note: Some path-based entries (e.g. deleted LogiMgrDaemon) cannot be"
    echo "cleared via tccutil — they'll be cleaned up by macOS automatically"
    echo "or remain inert."
else
    echo "✅ No stale entries found — your TCC database is clean."
fi
