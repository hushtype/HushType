#!/bin/bash
# setup-whisper.sh — Clone and build whisper.cpp, install headers + static libraries.
#
# Usage: ./scripts/setup-whisper.sh
#
# This script:
# 1. Clones whisper.cpp (shallow) into vendor/whisper.cpp
# 2. Builds it with CMake (Metal GPU enabled, Metal shaders embedded, macOS only)
# 3. Copies headers into WhisperKit/Sources/CWhisper/include/
# 4. Consolidates all static libraries into vendor/whisper.cpp/build/lib/

set -euo pipefail

# Ensure Homebrew paths are available (Xcode Run Script uses a minimal PATH)
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Verify cmake is installed
if ! command -v cmake &>/dev/null; then
    echo "error: cmake is not installed. Install it with: brew install cmake"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VENDOR_DIR="$PROJECT_ROOT/vendor"
WHISPER_DIR="$VENDOR_DIR/whisper.cpp"
WHISPER_BUILD_DIR="$WHISPER_DIR/build"
LIB_DIR="$WHISPER_BUILD_DIR/lib"
CWHISPER_INCLUDE="$PROJECT_ROOT/WhisperKit/Sources/CWhisper/include"

WHISPER_REPO="https://github.com/ggerganov/whisper.cpp.git"
WHISPER_TAG="v1.7.4"

echo "=== HushType: whisper.cpp Setup ==="
echo ""

# Step 1: Clone whisper.cpp (check for CMakeLists.txt, not just directory existence)
if [ -f "$WHISPER_DIR/CMakeLists.txt" ]; then
    echo "[1/4] whisper.cpp already cloned at $WHISPER_DIR"
else
    echo "[1/4] Cloning whisper.cpp ($WHISPER_TAG)..."
    rm -rf "$WHISPER_DIR"
    mkdir -p "$VENDOR_DIR"
    git clone --depth 1 --branch "$WHISPER_TAG" "$WHISPER_REPO" "$WHISPER_DIR"
    echo "      Done."
fi

# Step 2: Build with CMake (skip if already built)
if [ -d "$LIB_DIR" ] && ls "$LIB_DIR"/*.a 1>/dev/null 2>&1; then
    echo "[2/4] whisper.cpp already built (libraries found in $LIB_DIR)"
else
    echo "[2/4] Building whisper.cpp with Metal support..."
    mkdir -p "$WHISPER_BUILD_DIR"
    cmake -B "$WHISPER_BUILD_DIR" -S "$WHISPER_DIR" \
        -DCMAKE_BUILD_TYPE=Release \
        -DWHISPER_METAL=ON \
        -DGGML_METAL_EMBED_LIBRARY=ON \
        -DWHISPER_COREML=OFF \
        -DBUILD_SHARED_LIBS=OFF \
        -DWHISPER_BUILD_EXAMPLES=OFF \
        -DWHISPER_BUILD_TESTS=OFF \
        -DWHISPER_BUILD_SERVER=OFF

    cmake --build "$WHISPER_BUILD_DIR" --config Release -j "$(sysctl -n hw.ncpu)"
    echo "      Done."

    # Step 3: Consolidate static libraries
    echo "[3/4] Consolidating static libraries..."
    mkdir -p "$LIB_DIR"
    find "$WHISPER_BUILD_DIR" -name "*.a" -not -path "$LIB_DIR/*" -exec cp {} "$LIB_DIR/" \;
    echo "      Libraries consolidated in $LIB_DIR:"
    ls -la "$LIB_DIR"/*.a 2>/dev/null || echo "      (no .a files found)"
fi

# Step 4: Copy whisper.h header only (ggml headers provided by llama.cpp via LlamaKit)
echo "[4/4] Installing headers..."
mkdir -p "$CWHISPER_INCLUDE"
cp "$WHISPER_DIR/include/whisper.h" "$CWHISPER_INCLUDE/"

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Libraries: $LIB_DIR/"
echo "Headers:   $CWHISPER_INCLUDE/"
