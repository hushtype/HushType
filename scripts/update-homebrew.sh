#!/bin/bash
# update-homebrew.sh — Update the Homebrew cask formula with a new version and SHA256.
#
# Usage: ./scripts/update-homebrew.sh <version> <sha256>
#
# This updates Casks/hushtype.rb with the new version and checksum.
# After updating, submit a PR to homebrew-cask or use a tap.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CASK_FILE="$PROJECT_ROOT/Casks/hushtype.rb"

usage() {
    cat <<EOF
Usage: $(basename "$0") <version> <sha256>

Update the Homebrew cask formula for HushType.

Arguments:
  version   Release version (e.g. 1.0.0)
  sha256    SHA256 checksum of the DMG file

Examples:
  ./scripts/update-homebrew.sh 1.0.0 abc123def456...
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

if [[ $# -lt 2 ]]; then
    echo "error: requires 2 arguments: version and sha256"
    echo ""
    usage
    exit 1
fi

VERSION="$1"
SHA256="$2"

if [[ ! -f "$CASK_FILE" ]]; then
    echo "error: cask file not found at: $CASK_FILE"
    exit 1
fi

echo "=== HushType: Homebrew Cask Update ==="
echo ""
echo "Version : $VERSION"
echo "SHA256  : $SHA256"
echo ""

# Update version line
sed -i '' "s/version \".*\"/version \"${VERSION}\"/" "$CASK_FILE"

# Update sha256 line
sed -i '' "s/sha256 \".*\"/sha256 \"${SHA256}\"/" "$CASK_FILE"

echo "[done] Casks/hushtype.rb updated"
echo ""
echo "Next steps:"
echo "  1. Test locally: brew install --cask ./Casks/hushtype.rb"
echo "  2. Submit PR to homebrew/homebrew-cask"
echo "     or publish via your own tap: harungungorer/homebrew-hushtype"
