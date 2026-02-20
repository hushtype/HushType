#!/bin/bash
# notarize.sh — Submit a macOS app or DMG for Apple notarization.
#
# Usage:
#   Local:  ./scripts/notarize.sh path/to/HushType.app
#   CI:     APPLE_ID=... APPLE_TEAM_ID=... APPLE_APP_PASSWORD=... CI=true ./scripts/notarize.sh path/to/HushType.dmg
#
# Modes:
#   Keychain profile (local dev): Credentials are stored via:
#     xcrun notarytool store-credentials "HushType-Notarize" \
#       --apple-id "your@email.com" \
#       --team-id "L6UMTZRQRM" \
#       --password "app-specific-password"
#
#   CI mode (when CI=true): Reads credentials from environment variables:
#     APPLE_ID           — Apple ID email
#     APPLE_TEAM_ID      — 10-character Team ID
#     APPLE_APP_PASSWORD — App-specific password

set -euo pipefail

KEYCHAIN_PROFILE="HushType-Notarize"
TIMEOUT="30m"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

usage() {
    cat <<EOF
Usage: $(basename "$0") [--help] <path>

  <path>   Path to a .app bundle or .dmg file to notarize.

Modes:
  Local (default): Uses keychain profile "$KEYCHAIN_PROFILE".
    Store credentials once with:
      xcrun notarytool store-credentials "$KEYCHAIN_PROFILE" \\
        --apple-id "your@email.com" \\
        --team-id "YOUR_TEAM_ID" \\
        --password "app-specific-password"

  CI (when CI=true): Reads from environment variables:
      APPLE_ID           Apple ID email address
      APPLE_TEAM_ID      10-character Apple Team ID
      APPLE_APP_PASSWORD App-specific password (from appleid.apple.com)

Examples:
  ./scripts/notarize.sh build/HushType.app
  ./scripts/notarize.sh build/HushType.dmg
  CI=true APPLE_ID=dev@example.com APPLE_TEAM_ID=L6UMTZRQRM APPLE_APP_PASSWORD=xxxx-xxxx \\
    ./scripts/notarize.sh build/HushType.dmg
EOF
}

die() {
    echo "error: $*" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

if [[ $# -eq 0 || "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

TARGET="$1"

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

echo "=== HushType: Notarization ==="
echo ""

echo "[1/4] Validating input..."
[ -e "$TARGET" ] || die "Path does not exist: $TARGET"

case "$TARGET" in
    *.app | *.dmg) ;;
    *) die "Expected a .app or .dmg file, got: $TARGET" ;;
esac

echo "      Target: $TARGET"

# ---------------------------------------------------------------------------
# Build notarytool credential flags
# ---------------------------------------------------------------------------

echo "[2/4] Detecting credential mode..."

if [[ "${CI:-}" == "true" ]]; then
    echo "      Mode: CI (environment variables)"

    [ -n "${APPLE_ID:-}"           ] || die "APPLE_ID is not set"
    [ -n "${APPLE_TEAM_ID:-}"      ] || die "APPLE_TEAM_ID is not set"
    [ -n "${APPLE_APP_PASSWORD:-}" ] || die "APPLE_APP_PASSWORD is not set"

    CREDENTIAL_FLAGS=(
        --apple-id "$APPLE_ID"
        --team-id  "$APPLE_TEAM_ID"
        --password "$APPLE_APP_PASSWORD"
    )
else
    echo "      Mode: Keychain profile (\"$KEYCHAIN_PROFILE\")"
    CREDENTIAL_FLAGS=(--keychain-profile "$KEYCHAIN_PROFILE")
fi

# ---------------------------------------------------------------------------
# Submit for notarization
# ---------------------------------------------------------------------------

echo "[3/4] Submitting to Apple Notary Service (timeout: $TIMEOUT)..."
echo "      This may take several minutes..."
echo ""

SUBMISSION_OUTPUT=$(xcrun notarytool submit "$TARGET" \
    "${CREDENTIAL_FLAGS[@]}" \
    --wait \
    --timeout "$TIMEOUT" 2>&1) || NOTARIZE_EXIT=$?

echo "$SUBMISSION_OUTPUT"
echo ""

# Extract submission ID from output (present in both success and failure cases)
SUBMISSION_ID=$(echo "$SUBMISSION_OUTPUT" | grep -E '^\s*id:' | head -1 | awk '{print $2}' || true)

# Determine result status
NOTARIZE_STATUS=$(echo "$SUBMISSION_OUTPUT" | grep -E '^\s*status:' | head -1 | awk '{print $2}' || true)

if [[ "${NOTARIZE_EXIT:-0}" -ne 0 || "$NOTARIZE_STATUS" != "Accepted" ]]; then
    echo "error: Notarization failed (status: ${NOTARIZE_STATUS:-unknown})" >&2
    echo ""

    if [[ -n "$SUBMISSION_ID" ]]; then
        echo "--- Notarization Log (ID: $SUBMISSION_ID) ---"
        xcrun notarytool log "$SUBMISSION_ID" "${CREDENTIAL_FLAGS[@]}" 2>&1 || true
        echo "----------------------------------------------"
    else
        echo "(No submission ID found — cannot fetch log)"
    fi

    exit 1
fi

# ---------------------------------------------------------------------------
# Staple the ticket
# ---------------------------------------------------------------------------

echo "[4/4] Stapling notarization ticket..."
xcrun stapler staple "$TARGET"
echo "      Ticket stapled successfully."

echo ""
echo "=== Notarization Complete ==="
echo ""
echo "Target:        $TARGET"
[ -n "$SUBMISSION_ID" ] && echo "Submission ID: $SUBMISSION_ID"
echo ""
echo "The app is notarized and ready for distribution."
