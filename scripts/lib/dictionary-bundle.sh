# Shared helpers for packaging SwitchFix_Dictionary.bundle. Sourced by
# scripts/build-app.sh and scripts/test-dictionary-bundle.sh.

# Older SwiftPM toolchains emit a flat resource bundle; newer ones (Swift 6.4+)
# emit a macOS-style bundle with Contents/Resources. Bundle.url(forResource:)
# only searches Contents/Resources when it exists, so binaries copied to the
# bundle root are never found (#14).
dictionary_resource_dir() {
    local bundle="$1"
    if [ -d "$bundle/Contents/Resources" ]; then
        printf '%s\n' "$bundle/Contents/Resources"
    else
        printf '%s\n' "$bundle"
    fi
}

# install_dictionary_binaries BUNDLE BIN_DIR LANG...
# Production uses mmap binaries only; text resources are test-tool fallback inputs.
install_dictionary_binaries() {
    local bundle="$1" bin_dir="$2"
    shift 2
    local resources
    resources="$(dictionary_resource_dir "$bundle")"
    local lang
    for lang in "$@"; do
        if [ -f "$bin_dir/$lang.bin" ]; then
            cp "$bin_dir/$lang.bin" "$resources/"
        fi
        rm -f "$resources/$lang.txt"
    done
}

# verify_dictionary_bundle BUNDLE LANG...
# Fails when a binary is missing from the directory Foundation searches, a text
# fallback is still packaged, or a binary sits where Foundation will not look.
verify_dictionary_bundle() {
    local bundle="$1"
    shift
    local resources status=0 lang
    resources="$(dictionary_resource_dir "$bundle")"
    for lang in "$@"; do
        if [ ! -s "$resources/$lang.bin" ]; then
            echo "ERROR: $lang.bin is missing from $resources" >&2
            status=1
        fi
        if [ -n "$(find "$bundle" -name "$lang.txt" -print -quit)" ]; then
            echo "ERROR: text dictionary $lang.txt is still packaged in $bundle" >&2
            status=1
        fi
        if [ "$resources" != "$bundle" ] && [ -e "$bundle/$lang.bin" ]; then
            echo "ERROR: $lang.bin is in the bundle root, where Foundation does not look" >&2
            status=1
        fi
    done
    return "$status"
}
