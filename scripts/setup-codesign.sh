#!/bin/bash
set -euo pipefail

# Create a self-signed code-signing certificate for SwitchFix development.
#
# This eliminates the ad-hoc signing problem: with a stable certificate,
# macOS TCC (Accessibility & Input Monitoring permissions) survives rebuilds
# because TCC matches by certificate identity, not by binary hash.
#
# The certificate name is saved to .codesign-identity so build-app.sh
# picks it up automatically.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
IDENTITY_FILE="$PROJECT_DIR/.codesign-identity"
CERT_NAME="${1:-SwitchFix Development}"

# ── Check if already configured ──────────────────────────────────────────────

if [ -f "$IDENTITY_FILE" ]; then
    EXISTING="$(cat "$IDENTITY_FILE")"
    if security find-identity -v -p codesigning | grep -qF "$EXISTING"; then
        echo "✅ Already configured: signing identity \"$EXISTING\" exists in keychain."
        echo "   build-app.sh will use it automatically."
        echo ""
        echo "   To reset, delete $IDENTITY_FILE and re-run this script."
        exit 0
    else
        echo "⚠️  Identity file exists but certificate \"$EXISTING\" not found in keychain."
        echo "   Creating a new certificate..."
    fi
fi

# ── Check if a certificate with this name already exists ─────────────────────

if security find-identity -v -p codesigning | grep -qF "$CERT_NAME"; then
    echo "✅ Certificate \"$CERT_NAME\" already exists in your keychain."
    echo "$CERT_NAME" > "$IDENTITY_FILE"
    echo "   Saved to .codesign-identity — build-app.sh will use it automatically."
    exit 0
fi

# ── Create the certificate via Keychain Access certificate assistant ─────────
#
# macOS's `security` CLI doesn't fully support creating code-signing
# certificates that pass the codesigning policy check. The only reliable
# method is the Certificate Assistant built into Keychain Access, which
# we can drive via AppleScript/osascript.

echo "Creating self-signed code-signing certificate: \"$CERT_NAME\""
echo ""
echo "This uses macOS Certificate Assistant — you may see a brief Keychain"
echo "Access window. No manual steps required."
echo ""

# The Certificate Assistant can be driven via its command-line interface
# embedded in the Security framework. We use a signing identity that
# macOS will recognize for the codesigning policy.
#
# Fallback: if the command-line approach doesn't work, we guide the user
# through the Keychain Access GUI.

# Try the command-line certificate creation first
CREATED=false

# Method: Use certtool (ships with macOS) to create a self-signed cert
# certtool is Apple's tool and creates certs that macOS trusts for codesigning
if command -v certtool >/dev/null 2>&1; then
    # Create a temporary certificate request config
    CERT_CONFIG="/tmp/switchfix-cert-config"
    cat > "$CERT_CONFIG" <<CERTEOF
## cert/key parameters
certType       = 00
serial         = 01
hashType       = sha256
p              = ~/Library/Keychains/login.keychain-db

## Subject
commonName     = $CERT_NAME

## Extensions
keyUsage       = digitalSignature
extendedKeyUsage = codeSigning
CERTEOF

    # Try creating with certtool
    if certtool c k="$CERT_CONFIG" 2>/dev/null; then
        CREATED=true
    fi
    rm -f "$CERT_CONFIG"
fi

# Note: security create-keypair only creates key pairs, not certificates.
# If certtool didn't work, fall through to manual instructions below.

# If automated methods failed, guide the user through manual creation
if [ "$CREATED" = false ] || ! security find-identity -v -p codesigning 2>/dev/null | grep -qF "$CERT_NAME"; then
    echo "Automated certificate creation didn't work on this macOS version."
    echo ""
    echo "Creating via Keychain Access (this takes 10 seconds)..."
    echo ""

    # Open Keychain Access and guide the user
    open -a "Keychain Access"
    sleep 1

    cat <<EOF
╔══════════════════════════════════════════════════════════════════╗
║  Create a code-signing certificate in Keychain Access:          ║
║                                                                 ║
║  1. Menu: Keychain Access → Certificate Assistant               ║
║     → Create a Certificate...                                   ║
║  2. Name: $CERT_NAME
║  3. Identity Type: Self-Signed Root                             ║
║  4. Certificate Type: Code Signing                              ║
║  5. Click "Create", then "Continue", then "Done"                ║
╚══════════════════════════════════════════════════════════════════╝

EOF

    read -p "Press [Enter] when done... "

    # Verify
    if ! security find-identity -v -p codesigning 2>/dev/null | grep -qF "$CERT_NAME"; then
        echo ""
        echo "❌ Certificate \"$CERT_NAME\" not found."
        echo "   Please verify you followed the steps above, or check:"
        echo "   security find-identity -v -p codesigning"
        exit 1
    fi
fi

# ── Save and confirm ────────────────────────────────────────────────────────

echo ""
echo "✅ Certificate \"$CERT_NAME\" is ready for code signing."
echo "$CERT_NAME" > "$IDENTITY_FILE"
echo "   Saved to .codesign-identity — build-app.sh will use it automatically."
echo ""
echo "   TCC permissions will now survive rebuilds. No more regrant-permissions.sh!"
