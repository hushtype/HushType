#!/bin/bash
# create-dmg.sh — Create a macOS DMG installer for HushType.
#
# Usage: ./scripts/create-dmg.sh <version> [path/to/HushType.app]
#
# Prerequisites: brew install create-dmg
#
# Output: build/HushType-<version>.dmg

set -euo pipefail

# Ensure Homebrew paths are available
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
DEFAULT_APP_PATH="$PROJECT_ROOT/build/Build/Products/Release/HushType.app"
OUTPUT_DIR="$PROJECT_ROOT/build"
BACKGROUND_IMAGE="$PROJECT_ROOT/assets/dmg-background.png"

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $(basename "$0") <version> [path/to/HushType.app]

Create a macOS DMG installer for HushType.

Arguments:
  version             Release version string (e.g. 1.0.0)
  path/to/HushType.app  Path to the built .app bundle
                      (default: $DEFAULT_APP_PATH)

Options:
  --help              Show this help message and exit

Prerequisites:
  brew install create-dmg

Output:
  build/HushType-<version>.dmg

Examples:
  ./scripts/create-dmg.sh 1.0.0
  ./scripts/create-dmg.sh 1.0.0 /path/to/Release/HushType.app
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

if [[ $# -lt 1 ]]; then
    echo "error: version argument is required."
    echo ""
    usage
    exit 1
fi

VERSION="$1"
APP_PATH="${2:-$DEFAULT_APP_PATH}"

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
if ! command -v create-dmg &>/dev/null; then
    echo "error: 'create-dmg' is not installed."
    echo "       Install it with: brew install create-dmg"
    exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
    echo "error: .app bundle not found at: $APP_PATH"
    echo "       Build the app first with:"
    echo "         xcodebuild -scheme HushType -configuration Release build"
    exit 1
fi

# ---------------------------------------------------------------------------
# Prepare output directory
# ---------------------------------------------------------------------------
mkdir -p "$OUTPUT_DIR"
OUTPUT_DMG="$OUTPUT_DIR/HushType-${VERSION}.dmg"

# Remove a stale DMG if one already exists (create-dmg refuses to overwrite)
if [[ -f "$OUTPUT_DMG" ]]; then
    echo "Removing existing DMG: $OUTPUT_DMG"
    rm -f "$OUTPUT_DMG"
fi

echo "=== HushType: DMG Packaging ==="
echo ""
echo "Version    : $VERSION"
echo "App bundle : $APP_PATH"
echo "Output     : $OUTPUT_DMG"
echo ""

# ---------------------------------------------------------------------------
# Build create-dmg argument list
# ---------------------------------------------------------------------------
CREATE_DMG_ARGS=(
    --volname "HushType ${VERSION}"
    --window-size 600 400
    --icon-size 128
    --icon "HushType.app" 150 190
    --app-drop-link 450 190
    --hide-extension "HushType.app"
)

if [[ -f "$BACKGROUND_IMAGE" ]]; then
    echo "Using background image: $BACKGROUND_IMAGE"
    CREATE_DMG_ARGS+=(--background "$BACKGROUND_IMAGE")
else
    echo "No background image found at assets/dmg-background.png — using plain DMG."
fi

# ---------------------------------------------------------------------------
# Create DMG
# ---------------------------------------------------------------------------
echo ""
echo "[1/1] Running create-dmg..."
create-dmg \
    "${CREATE_DMG_ARGS[@]}" \
    "$OUTPUT_DMG" \
    "$APP_PATH"

echo ""
echo "=== DMG Created ==="
echo ""
echo "Output: $OUTPUT_DMG"
echo "Size  : $(du -sh "$OUTPUT_DMG" | cut -f1)"
