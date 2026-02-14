#!/bin/bash
# setup-whisper.sh — Clone and build whisper.cpp, install headers + static library.
#
# Usage: ./scripts/setup-whisper.sh
#
# This script:
# 1. Clones whisper.cpp (shallow) into vendor/whisper.cpp
# 2. Builds it with CMake (Metal GPU enabled, macOS only)
# 3. Copies whisper.h into WhisperKit/Sources/CWhisper/include/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VENDOR_DIR="$PROJECT_ROOT/vendor"
WHISPER_DIR="$VENDOR_DIR/whisper.cpp"
WHISPER_BUILD_DIR="$WHISPER_DIR/build"
CWHISPER_INCLUDE="$PROJECT_ROOT/WhisperKit/Sources/CWhisper/include"

WHISPER_REPO="https://github.com/ggerganov/whisper.cpp.git"
WHISPER_TAG="v1.7.4"

echo "=== HushType: whisper.cpp Setup ==="
echo ""

# Step 1: Clone whisper.cpp
if [ -d "$WHISPER_DIR" ]; then
    echo "[1/3] whisper.cpp already cloned at $WHISPER_DIR"
else
    echo "[1/3] Cloning whisper.cpp ($WHISPER_TAG)..."
    mkdir -p "$VENDOR_DIR"
    git clone --depth 1 --branch "$WHISPER_TAG" "$WHISPER_REPO" "$WHISPER_DIR"
    echo "      Done."
fi

# Step 2: Build with CMake
echo "[2/3] Building whisper.cpp with Metal support..."
mkdir -p "$WHISPER_BUILD_DIR"
cmake -B "$WHISPER_BUILD_DIR" -S "$WHISPER_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DWHISPER_METAL=ON \
    -DWHISPER_COREML=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DWHISPER_BUILD_EXAMPLES=OFF \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_SERVER=OFF

cmake --build "$WHISPER_BUILD_DIR" --config Release -j "$(sysctl -n hw.ncpu)"
echo "      Done."

# Step 3: Copy headers
echo "[3/3] Installing headers..."
mkdir -p "$CWHISPER_INCLUDE"
cp "$WHISPER_DIR/include/whisper.h" "$CWHISPER_INCLUDE/whisper.h"

# Copy ggml.h if needed for type definitions
if [ -f "$WHISPER_DIR/ggml/include/ggml.h" ]; then
    cp "$WHISPER_DIR/ggml/include/ggml.h" "$CWHISPER_INCLUDE/ggml.h"
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Library: $WHISPER_BUILD_DIR/src/libwhisper.a"
echo "Headers: $CWHISPER_INCLUDE/"
echo ""
echo "To use in Xcode, add to your target:"
echo "  - Library Search Paths: $WHISPER_BUILD_DIR/src"
echo "  - Header Search Paths: $CWHISPER_INCLUDE"
echo "  - Link: libwhisper.a, Metal.framework, Accelerate.framework"
