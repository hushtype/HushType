#!/bin/bash
# update-appcast.sh — Add a new release entry to the Sparkle appcast.
#
# Usage: ./scripts/update-appcast.sh <version> <dmg-path> <ed-signature>
#
# Arguments:
#   version       Release version (e.g. 1.0.0)
#   dmg-path      Path to the .dmg file
#   ed-signature  EdDSA signature from Sparkle's sign_update tool
#
# The script updates appcast.xml with the new release entry.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
APPCAST="$PROJECT_ROOT/appcast.xml"
GITHUB_REPO="harungungorer/HushType"

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $(basename "$0") <version> <dmg-path> <ed-signature>

Add a new release entry to the Sparkle appcast.

Arguments:
  version       Release version string (e.g. 1.0.0)
  dmg-path      Path to the signed .dmg file
  ed-signature  EdDSA signature from: sparkle/bin/sign_update <dmg>

Prerequisites:
  - appcast.xml must exist at project root
  - DMG must be built and signed

Output:
  Updates appcast.xml with the new <item> entry.

Examples:
  ./scripts/update-appcast.sh 1.0.0 build/HushType-1.0.0.dmg "BASE64_SIGNATURE"
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

if [[ $# -lt 3 ]]; then
    echo "error: requires 3 arguments: version, dmg-path, ed-signature"
    echo ""
    usage
    exit 1
fi

VERSION="$1"
DMG_PATH="$2"
ED_SIGNATURE="$3"

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
if [[ ! -f "$APPCAST" ]]; then
    echo "error: appcast.xml not found at: $APPCAST"
    exit 1
fi

if [[ ! -f "$DMG_PATH" ]]; then
    echo "error: DMG not found at: $DMG_PATH"
    exit 1
fi

# Compute file size and publication date
DMG_SIZE=$(stat -f%z "$DMG_PATH")
PUB_DATE=$(date -R)
DOWNLOAD_URL="https://github.com/$GITHUB_REPO/releases/download/v${VERSION}/HushType-${VERSION}.dmg"
MIN_SYSTEM_VERSION="14.0"

echo "=== HushType: Appcast Update ==="
echo ""
echo "Version    : $VERSION"
echo "DMG        : $DMG_PATH"
echo "Size       : $DMG_SIZE bytes"
echo "Download   : $DOWNLOAD_URL"
echo ""

# ---------------------------------------------------------------------------
# Build the new <item> XML entry
# ---------------------------------------------------------------------------
NEW_ITEM=$(cat <<ITEM_EOF
        <item>
            <title>Version ${VERSION}</title>
            <pubDate>${PUB_DATE}</pubDate>
            <sparkle:version>${VERSION}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>${MIN_SYSTEM_VERSION}</sparkle:minimumSystemVersion>
            <enclosure
                url="${DOWNLOAD_URL}"
                length="${DMG_SIZE}"
                type="application/octet-stream"
                sparkle:edSignature="${ED_SIGNATURE}"
            />
        </item>
ITEM_EOF
)

# ---------------------------------------------------------------------------
# Insert the new item before the closing </channel> tag
# ---------------------------------------------------------------------------
# Use a temp file for safe in-place editing
TEMP_FILE=$(mktemp)

# Insert new item before </channel>
awk -v item="$NEW_ITEM" '
    /<\/channel>/ { print item }
    { print }
' "$APPCAST" > "$TEMP_FILE"

mv "$TEMP_FILE" "$APPCAST"

echo "[done] appcast.xml updated with v${VERSION}"
echo ""
echo "Next steps:"
echo "  1. Commit appcast.xml"
echo "  2. Push to gh-pages branch for GitHub Pages deployment"
