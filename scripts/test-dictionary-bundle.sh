#!/bin/bash
set -euo pipefail

# Regression check for #14: dictionary binaries must land where Foundation
# looks for them in both the flat and the macOS-style (Contents/Resources)
# SwiftPM resource bundle layouts.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/dictionary-bundle.sh
source "$SCRIPT_DIR/lib/dictionary-bundle.sh"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
LANGS=(en_US ru_RU uk_UA)
FAILURES=0

fail() {
    echo "FAIL: $*" >&2
    FAILURES=$((FAILURES + 1))
}

mkdir -p "$WORK_DIR/bin"
for lang in "${LANGS[@]}"; do
    printf 'binary-%s' "$lang" > "$WORK_DIR/bin/$lang.bin"
done

# make_bundle NAME LAYOUT -> a bundle as SwiftPM emits it, before packaging.
make_bundle() {
    local bundle="$WORK_DIR/$1/SwitchFix_Dictionary.bundle" resources
    if [ "$2" = nested ]; then
        resources="$bundle/Contents/Resources"
        mkdir -p "$resources"
        cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>SwitchFix.Dictionary.resources</string>
</dict></plist>
PLIST
    else
        resources="$bundle"
        mkdir -p "$resources"
    fi
    mkdir -p "$resources/overrides"
    printf 'vnc\n' > "$resources/overrides/en_US_allow.txt"
    for lang in "${LANGS[@]}"; do
        printf 'text\n' > "$resources/$lang.txt"
    done
    printf '%s\n' "$bundle"
}

for layout in flat nested; do
    bundle="$(make_bundle "$layout" "$layout")"
    expected="$bundle"
    [ "$layout" = nested ] && expected="$bundle/Contents/Resources"

    [ "$(dictionary_resource_dir "$bundle")" = "$expected" ] ||
        fail "$layout: resource directory is $(dictionary_resource_dir "$bundle"), expected $expected"

    install_dictionary_binaries "$bundle" "$WORK_DIR/bin" "${LANGS[@]}"
    verify_dictionary_bundle "$bundle" "${LANGS[@]}" || fail "$layout: packaged bundle did not verify"

    if ! swift "$SCRIPT_DIR/check_bundle_lookup.swift" "$bundle" "${LANGS[@]}" > "$WORK_DIR/$layout.lookup"; then
        cat "$WORK_DIR/$layout.lookup" >&2
        fail "$layout: Foundation could not resolve the packaged binaries"
    fi
    # Foundation may report /private/var for /var; compare inside the work directory.
    relative="${expected#"$WORK_DIR"}"
    while read -r line; do
        case "$line" in
            *"$relative/"*) ;;
            *) fail "$layout: unexpected lookup result: $line" ;;
        esac
    done < "$WORK_DIR/$layout.lookup"
done

# The verifier must reject the pre-fix packaging: binaries in the root of a nested bundle.
broken="$(make_bundle broken nested)"
cp "$WORK_DIR/bin/"*.bin "$broken/"
if verify_dictionary_bundle "$broken" "${LANGS[@]}" 2>/dev/null; then
    fail "broken: binaries in the bundle root of a nested bundle were accepted"
fi

if [ "$FAILURES" -ne 0 ]; then
    echo "$FAILURES dictionary bundle check(s) failed." >&2
    exit 1
fi
echo "Dictionary bundle checks passed (flat, nested, broken layout rejected)."
