#!/bin/bash
# create-dmg.sh — Create a branded macOS DMG installer for VaulType.
#
# Usage: ./scripts/create-dmg.sh <version> [path/to/VaulType.app]
#
# Uses native hdiutil + AppleScript. No external dependencies required.
# If 'create-dmg' (brew install create-dmg) is installed, uses it instead.
#
# Output: build/VaulType-<version>.dmg

set -euo pipefail

# Ensure Homebrew paths are available
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
DEFAULT_APP_PATH="$PROJECT_ROOT/build/Build/Products/Release/VaulType.app"
OUTPUT_DIR="$PROJECT_ROOT/build"
BACKGROUND_IMAGE="$PROJECT_ROOT/assets/dmg-background.png"
VOLUME_NAME="VaulType"

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $(basename "$0") <version> [path/to/VaulType.app]

Create a branded macOS DMG installer for VaulType.

Arguments:
  version               Release version string (e.g. 1.0.0)
  path/to/VaulType.app  Path to the built .app bundle
                        (default: $DEFAULT_APP_PATH)

Options:
  --help                Show this help message and exit

Output:
  build/VaulType-<version>.dmg

Examples:
  ./scripts/create-dmg.sh 1.0.0
  ./scripts/create-dmg.sh 1.0.0 /path/to/Release/VaulType.app
EOF
}

die() {
    echo "error: $*" >&2
    exit 1
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
if [[ ! -d "$APP_PATH" ]]; then
    die ".app bundle not found at: $APP_PATH
       Build the app first with:
         xcodebuild -scheme VaulType -configuration Release build"
fi

# ---------------------------------------------------------------------------
# Prepare output directory
# ---------------------------------------------------------------------------
mkdir -p "$OUTPUT_DIR"
OUTPUT_DMG="$OUTPUT_DIR/VaulType-${VERSION}.dmg"

# Remove stale DMG
if [[ -f "$OUTPUT_DMG" ]]; then
    echo "Removing existing DMG: $OUTPUT_DMG"
    rm -f "$OUTPUT_DMG"
fi

echo "=== VaulType: DMG Packaging ==="
echo ""
echo "Version    : $VERSION"
echo "App bundle : $APP_PATH"
echo "Output     : $OUTPUT_DMG"
echo ""

# ---------------------------------------------------------------------------
# Method 1: Use create-dmg if available (brew install create-dmg)
# ---------------------------------------------------------------------------
if command -v create-dmg &>/dev/null; then
    echo "Using: create-dmg (Homebrew)"
    echo ""

    CREATE_DMG_ARGS=(
        --volname "$VOLUME_NAME"
        --window-size 600 400
        --icon-size 128
        --icon "VaulType.app" 150 190
        --app-drop-link 450 190
        --hide-extension "VaulType.app"
    )

    if [[ -f "$BACKGROUND_IMAGE" ]]; then
        echo "Background: $BACKGROUND_IMAGE"
        CREATE_DMG_ARGS+=(--background "$BACKGROUND_IMAGE")
    fi

    echo "[1/1] Running create-dmg..."
    create-dmg \
        "${CREATE_DMG_ARGS[@]}" \
        "$OUTPUT_DMG" \
        "$APP_PATH"

    echo ""
    echo "=== DMG Created ==="
    echo "Output: $OUTPUT_DMG"
    echo "Size  : $(du -sh "$OUTPUT_DMG" | cut -f1)"
    exit 0
fi

# ---------------------------------------------------------------------------
# Method 2: Native hdiutil + AppleScript (no external dependencies)
# ---------------------------------------------------------------------------
echo "Using: native hdiutil + AppleScript"
echo ""

TEMP_DMG="$OUTPUT_DIR/VaulType-temp.dmg"
MOUNT_POINT="/Volumes/$VOLUME_NAME"

# Ensure no stale mount
if [[ -d "$MOUNT_POINT" ]]; then
    hdiutil detach "$MOUNT_POINT" -quiet -force 2>/dev/null || true
fi

# Step 1: Create writable temp DMG
echo "[1/5] Creating writable DMG..."
rm -f "$TEMP_DMG"
hdiutil create "$TEMP_DMG" \
    -volname "$VOLUME_NAME" \
    -srcfolder "$APP_PATH" \
    -fs HFS+ \
    -format UDRW \
    -size 200m \
    -quiet

# Step 2: Mount it
echo "[2/5] Mounting..."
DEVICE=$(hdiutil attach "$TEMP_DMG" -readwrite -noverify -noautoopen | grep "/Volumes/" | head -1 | awk '{print $1}')
sleep 1

# Step 3: Add Applications symlink
echo "[3/5] Adding Applications symlink..."
ln -sf /Applications "$MOUNT_POINT/Applications"

# Copy background image if available
if [[ -f "$BACKGROUND_IMAGE" ]]; then
    echo "      Setting background image..."
    mkdir -p "$MOUNT_POINT/.background"
    cp "$BACKGROUND_IMAGE" "$MOUNT_POINT/.background/background.png"
fi

# Step 4: Style the DMG window with AppleScript
echo "[4/5] Styling DMG window..."
HAS_BG="false"
[[ -f "$MOUNT_POINT/.background/background.png" ]] && HAS_BG="true"

osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {100, 100, 700, 500}

        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 128

        if $HAS_BG then
            set background picture of theViewOptions to file ".background:background.png"
        end if

        set position of item "VaulType.app" of container window to {150, 190}
        set position of item "Applications" of container window to {450, 190}

        -- Hide background folder
        try
            set extension hidden of item ".background" to true
        end try

        close
        open
        update without registering applications

        delay 1
        close
    end tell
end tell
APPLESCRIPT

# Sync and detach
sync
hdiutil detach "$DEVICE" -quiet

# Step 5: Convert to compressed read-only DMG
echo "[5/5] Compressing final DMG..."
hdiutil convert "$TEMP_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$OUTPUT_DMG" \
    -quiet

rm -f "$TEMP_DMG"

echo ""
echo "=== DMG Created ==="
echo ""
echo "Output: $OUTPUT_DMG"
echo "Size  : $(du -sh "$OUTPUT_DMG" | cut -f1)"
echo ""
echo "Next: notarize with ./scripts/notarize.sh $OUTPUT_DMG"
