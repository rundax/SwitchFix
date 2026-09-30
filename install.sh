#!/bin/bash
set -euo pipefail

# Public installs use native ad-hoc signed bundles; Gatekeeper approval is a user action.
APP_DEST="/Applications/SwitchFix.app"
RELEASE_URL="https://github.com/rundax/SwitchFix/releases/latest/download"
WORK_DIR=""
STAGE_DIR=""
LOCAL_APP_SOURCE=""
IS_LOCAL_SOURCE=0
HAD_PREVIOUS_APP=0
BACKUP=""
REPLACED=0
WAS_RUNNING=0
KEEP_BACKUP=0
INSTALL_MODE=release

fail() { echo "SwitchFix: $*" >&2; exit 1; }
case "$#" in
    0) ;;
    1)
        [ "$1" = "--local" ] || fail "Usage: $0 [--local]"
        INSTALL_MODE=local
        ;;
    *) fail "Usage: $0 [--local]" ;;
esac
if [ -n "${SWITCHFIX_APP_SOURCE:-}" ] && [ "$INSTALL_MODE" != local ]; then
    fail "SWITCHFIX_APP_SOURCE is no longer supported. Run ./install.sh --local from the SwitchFix source checkout to build and install locally."
fi

app_pids() {
    local pid
    for pid in $(pgrep -x SwitchFixApp 2>/dev/null || true); do
        if lsof -a -p "$pid" -d txt -Fn 2>/dev/null | grep -Fxq "n$APP_DEST/Contents/MacOS/SwitchFixApp"; then
            echo "$pid"
        fi
    done
}
cleanup() {
    local result=$?
    trap - EXIT HUP INT TERM
    if [ "$result" -ne 0 ] && [ "$REPLACED" -eq 1 ]; then
        for pid in $(app_pids); do kill "$pid" 2>/dev/null || true; done
        if [ -n "$BACKUP" ] && [ -d "$BACKUP" ]; then
            if ! rm -rf "$APP_DEST"; then
                KEEP_BACKUP=1
            elif mv "$BACKUP" "$APP_DEST"; then
                echo "Restored the previous SwitchFix installation." >&2
                if [ "$WAS_RUNNING" -eq 1 ]; then open "$APP_DEST" || true; fi
            else
                KEEP_BACKUP=1
            fi
        elif [ "$HAD_PREVIOUS_APP" -eq 0 ] && [ -e "$APP_DEST" ]; then
            rm -rf "$APP_DEST" || echo "SwitchFix: could not remove the incomplete installation at $APP_DEST." >&2
        fi
    fi
    if [ "$KEEP_BACKUP" -eq 1 ]; then
        echo "Restore the previous app from $BACKUP. The backup has been kept." >&2
    elif [ -n "$STAGE_DIR" ]; then
        rm -rf "$STAGE_DIR"
    fi
    if [ -n "$WORK_DIR" ]; then rm -rf "$WORK_DIR"; fi
    exit "$result"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

version_number() {
    awk -v version="$1" 'BEGIN {
        if (version !~ /^[0-9]+(\.[0-9]+){0,2}$/) exit 1;
        split(version, v, "."); print v[1] * 65536 + v[2] * 256 + v[3]
    }'
}

# Read thin 64-bit Mach-O load commands with tools included in macOS (no Xcode).
binary_minimum_os() {
    local binary="$1" header command_count command_bytes expected_cpu
    header=$(od -An -N32 -tu4 "$binary") || return 1
    set -- $header
    [ "$#" -eq 8 ] && [ "$1" = 4277009103 ] || return 1
    expected_cpu=16777223
    [ "$ARCH" != arm64 ] || expected_cpu=16777228
    [ "$2" = "$expected_cpu" ] && [ "$4" = 2 ] || return 1
    command_count="$5"
    command_bytes="$6"
    [ "$command_count" -gt 0 ] && [ "$command_bytes" -ge 16 ] && [ "$command_bytes" -le 262144 ] || return 1
    od -An -v -j32 -N "$command_bytes" -tu4 "$binary" | awk -v count="$command_count" -v bytes="$command_bytes" '
        { for (i = 1; i <= NF; i++) words[++n] = $i }
        END {
            if (n * 4 != bytes) exit 1;
            pos = 1; minimum = 0;
            for (i = 0; i < count; i++) {
                command = words[pos]; size = words[pos + 1];
                if (size < 8 || size % 4 || pos + size / 4 - 1 > n) exit 1;
                if (command == 50) {
                    if (size < 24 || words[pos + 2] != 1) exit 1;
                    minimum = words[pos + 3];
                } else if (command == 36) {
                    if (size < 16) exit 1;
                    minimum = words[pos + 2];
                }
                pos += size / 4;
            }
            if (pos != n + 1 || minimum == 0) exit 1;
            print minimum;
        }'
}

[ "$(uname -s)" = Darwin ] || fail "This installer requires macOS 13 or later."
[ "$(id -u)" -ne 0 ] || fail "Run this installer as your signed-in user, without sudo, so SwitchFix opens in your session."
OS_VERSION=$(sw_vers -productVersion)
OS_NUMBER=$(version_number "$OS_VERSION") || fail "Could not read the macOS version. Run sw_vers and check for system updates."
[ "$OS_NUMBER" -ge 851968 ] || fail "macOS $OS_VERSION is unsupported. Update to macOS 13 or later."
# hw.optional.arm64 reports the physical machine even when Terminal runs in Rosetta.
if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" = 1 ]; then
    ARCH=arm64
    ASSET=arm64
else
    ARCH=$(uname -m)
    [ "$ARCH" = x86_64 ] || fail "Unsupported Mac architecture: $ARCH. Use an Intel or Apple Silicon Mac."
    ASSET=intel
fi
[ -d /Applications ] && [ -w /Applications ] || fail "Cannot write to /Applications. Sign in with an account allowed to install apps there, then retry without sudo."
[ ! -L "$APP_DEST" ] || fail "$APP_DEST is a symbolic link. Move that link aside before installing."
if [ -e "$APP_DEST" ]; then
    [ -d "$APP_DEST" ] && [ -w "$APP_DEST" ] || fail "Cannot replace $APP_DEST. Ask its owner or an administrator to grant your account access."
    HAD_PREVIOUS_APP=1
fi
if [ "$INSTALL_MODE" = local ]; then
    SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    PROJECT_DIR=$(cd "$SCRIPT_DIR" && pwd)
    [ -f "$PROJECT_DIR/scripts/build-app.sh" ] || fail "--local must be run from a SwitchFix source checkout containing scripts/build-app.sh."
    echo "Building a local ${ARCH} release…"
    SWITCHFIX_CODESIGN_IDENTITY=- bash "$PROJECT_DIR/scripts/build-app.sh" || fail "The local build failed. Your installed app has not changed."
    LOCAL_APP_SOURCE="$PROJECT_DIR/dist/SwitchFix.app"
fi
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/switchfix-download.XXXXXX") || fail "Cannot create download staging space. Free disk space and retry."
if [ -n "$LOCAL_APP_SOURCE" ]; then
    [ -d "$LOCAL_APP_SOURCE" ] || fail "The local build did not produce an app at $LOCAL_APP_SOURCE."
    APP_SOURCE="$LOCAL_APP_SOURCE"
    IS_LOCAL_SOURCE=1
    echo "Using local SwitchFix build at $APP_SOURCE."
else
    ARCHIVE="$WORK_DIR/SwitchFix.app.zip"
    echo "Downloading SwitchFix for ${ARCH}…"
    curl --fail --location --proto '=https' --proto-redir '=https' --retry 2 --connect-timeout 20 --max-time 300 \
        "$RELEASE_URL/SwitchFix-$ASSET.app.zip" --output "$ARCHIVE" || fail "Download failed. Check your connection and the GitHub release, then retry. Your installed app has not changed."
    unzip -tq "$ARCHIVE" >/dev/null || fail "The downloaded archive is corrupt. Retry the download."
    unzip -Z1 "$ARCHIVE" > "$WORK_DIR/entries" || fail "Cannot inspect the release archive. Download it again."
    awk '
        /^\// || /(^|\/)\.\.?(\/|$)/ || /\\/ { exit 1 }
        !/^SwitchFix\.app\// && !/^__MACOSX\/SwitchFix\.app\// && $0 != "__MACOSX/" { exit 1 }
        END { if (NR == 0) exit 1 }
    ' "$WORK_DIR/entries" || fail "The release archive has unsafe or unexpected paths. Report this release to the maintainer."
    if unzip -Z -l "$ARCHIVE" | awk '$1 ~ /^l/ { found = 1 } END { exit !found }'; then
        fail "The release archive contains unexpected symbolic links. Report this release to the maintainer."
    fi
    ditto -x -k "$ARCHIVE" "$WORK_DIR/unpacked" || fail "Could not extract the release. Free disk space and download it again."
    APP_SOURCE="$WORK_DIR/unpacked/SwitchFix.app"
fi
PLIST="$APP_SOURCE/Contents/Info.plist"
BINARY="$APP_SOURCE/Contents/MacOS/SwitchFixApp"
[ -f "$PLIST" ] && [ -f "$BINARY" ] && [ -x "$BINARY" ] || fail "The app bundle is missing its executable. Check the build or report this release to the maintainer."
[ "$(plutil -extract CFBundleIdentifier raw -o - "$PLIST")" = com.switchfix.app ] || fail "The app has the wrong identity. Check the build or report this release to the maintainer."
[ "$(plutil -extract CFBundleExecutable raw -o - "$PLIST")" = SwitchFixApp ] || fail "The app has an unexpected executable. Check the build or report this release to the maintainer."
BUILD_NUMBER=$(plutil -extract CFBundleVersion raw -o - "$PLIST") || fail "The app has no build number. Check the build or report this release to the maintainer."
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || fail "The app has an invalid build number. Check the build or report this release to the maintainer."
[ "$BUILD_NUMBER" -ge 10 ] || fail "This app build predates guided permission setup. Nothing was installed; build a newer local version or wait for SwitchFix 0.0.10 or later."
MINIMUM=$(plutil -extract LSMinimumSystemVersion raw -o - "$PLIST") || fail "The app has no minimum macOS version. Check the build or report this release to the maintainer."
MINIMUM_NUMBER=$(version_number "$MINIMUM") || fail "The app has an invalid minimum macOS version. Check the build or report this release to the maintainer."
[ "$MINIMUM_NUMBER" -ge 851968 ] && [ "$MINIMUM_NUMBER" -le "$OS_NUMBER" ] || fail "This app requires macOS $MINIMUM. Update macOS or use a compatible version."
BINARY_MINIMUM=$(binary_minimum_os "$BINARY") || fail "The app executable is corrupt or is not a native $ARCH macOS app. Check the build or report this release to the maintainer."
[ "$BINARY_MINIMUM" -eq "$MINIMUM_NUMBER" ] || fail "The app executable and bundle disagree on the minimum macOS version. Check the build or report this release to the maintainer."
codesign --verify --deep --strict "$APP_SOURCE" || fail "The app bundle failed its code-seal check. Do not install it; rebuild locally or report this release to the maintainer."
SIGNATURE=$(codesign -dv --verbose=4 "$APP_SOURCE" 2>&1) || fail "Cannot inspect the app signature. Check the build or report this release to the maintainer."
FLAGS=$(printf '%s\n' "$SIGNATURE" | sed -n 's/^CodeDirectory .* flags=\([^ ]*\) .*/\1/p')
TEAM=$(printf '%s\n' "$SIGNATURE" | sed -n 's/^TeamIdentifier=//p')
[ "$TEAM" = "not set" ] && [[ "$FLAGS" == *"(adhoc)"* ]] || fail "The release does not match SwitchFix's free ad-hoc release format. Report this release to the maintainer."
if [ "$IS_LOCAL_SOURCE" -eq 1 ]; then
    # Local builds are not downloads; clear quarantine left by an earlier local install test.
    xattr -d com.apple.quarantine "$APP_SOURCE" 2>/dev/null || true
else
    # curl does not add browser quarantine; preserve Gatekeeper's first-launch check.
    xattr -w com.apple.quarantine "0083;$(printf '%x' "$(date +%s)");SwitchFix Installer;" "$APP_SOURCE" || fail "Could not mark the downloaded app for Gatekeeper. Check staging-folder permissions and retry."
fi

# Copy fully on the destination volume before stopping or moving the existing app.
STAGE_DIR=$(mktemp -d /Applications/.switchfix-install.XXXXXX) || fail "Cannot stage in /Applications. Check write access and free disk space."
ditto "$APP_SOURCE" "$STAGE_DIR/SwitchFix.app" || fail "Copying the new app failed. Free disk space or fix /Applications access and retry. Your installed app has not changed."
codesign --verify --deep --strict "$STAGE_DIR/SwitchFix.app" || fail "The staged copy failed verification. Check the disk and retry. Your installed app has not changed."
PIDS=$(app_pids)
if [ -n "$PIDS" ]; then
    WAS_RUNNING=1
    for pid in $PIDS; do kill "$pid" || fail "Could not stop SwitchFix. Quit the app yourself and retry."; done
    for attempt in 1 2 3 4 5; do
        [ -n "$(app_pids)" ] || break
        sleep 1
    done
    [ -z "$(app_pids)" ] || fail "SwitchFix did not quit. Quit it yourself and retry. Your installed app has not changed."
fi
if [ -d "$APP_DEST" ]; then
    BACKUP="$STAGE_DIR/Previous-SwitchFix.app"
fi
REPLACED=1
if [ -n "$BACKUP" ]; then
    if ! mv "$APP_DEST" "$BACKUP"; then
        REPLACED=0
        fail "Could not preserve the previous app. Check /Applications access and retry."
    fi
fi
mv "$STAGE_DIR/SwitchFix.app" "$APP_DEST" || fail "Installing the new app failed. Check /Applications access and free disk space; the previous app will be restored."
REPLACED=0

# Reset stale permissions from previous installations so System Settings
# does not retain invalid ad-hoc signatures for SwitchFix.
echo "Clearing previous permissions for SwitchFix…"
tccutil reset Accessibility com.switchfix.app >/dev/null 2>&1 || true
tccutil reset ListenEvent com.switchfix.app >/dev/null 2>&1 || true
tccutil reset PostEvent com.switchfix.app >/dev/null 2>&1 || true
tccutil reset All com.switchfix.app >/dev/null 2>&1 || true

# Force LaunchServices to refresh registration for the new app bundle
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -f "$APP_DEST" 2>/dev/null || true
fi

# Close System Settings if open so its Privacy & Security cache reloads fresh
if pgrep -x "System Settings" >/dev/null 2>&1; then
    osascript -e 'tell application "System Settings" to quit' 2>/dev/null || true
fi

if open "$APP_DEST"; then
    for attempt in 1 2 3 4 5; do
        [ -n "$(app_pids)" ] && break
        sleep 1
    done
fi
if [ -n "$(app_pids)" ]; then
    echo "SwitchFix is open. Follow its setup window to grant Accessibility and Input Monitoring, then run Try a correction."
else
    echo "SwitchFix is installed. If macOS blocked it, click Done, then open System Settings > Privacy & Security, scroll to Security, click Open Anyway for SwitchFix, confirm Open, and launch it from Applications."
fi
if [ "$HAD_PREVIOUS_APP" -eq 1 ]; then
    echo "Stale permissions from the previous installation have been removed automatically. Follow the setup window to grant Accessibility and Input Monitoring for the new version."
fi
echo "Easy setup guide (with interactive visuals): https://rundax.github.io/SwitchFix/"
