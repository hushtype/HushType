#!/bin/bash
# setup-llama.sh — Clone and build llama.cpp, install headers + static libraries.
#
# Usage: ./scripts/setup-llama.sh
#
# This script:
# 1. Clones llama.cpp (shallow) into vendor/llama.cpp
# 2. Builds it with CMake (Metal GPU enabled, Metal shaders embedded, macOS only)
# 3. Copies headers into LlamaKit/Sources/CLlama/include/
# 4. Consolidates all static libraries into vendor/llama.cpp/build/lib/

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
LLAMA_DIR="$VENDOR_DIR/llama.cpp"
LLAMA_BUILD_DIR="$LLAMA_DIR/build"
LIB_DIR="$LLAMA_BUILD_DIR/lib"
CLLAMA_INCLUDE="$PROJECT_ROOT/LlamaKit/Sources/CLlama/include"

LLAMA_REPO="https://github.com/ggerganov/llama.cpp.git"
LLAMA_TAG="b8059"

echo "=== HushType: llama.cpp Setup ==="
echo ""

# Step 1: Clone llama.cpp (check for CMakeLists.txt, not just directory existence)
if [ -f "$LLAMA_DIR/CMakeLists.txt" ]; then
    echo "[1/4] llama.cpp already cloned at $LLAMA_DIR"
else
    echo "[1/4] Cloning llama.cpp ($LLAMA_TAG)..."
    rm -rf "$LLAMA_DIR"
    mkdir -p "$VENDOR_DIR"
    git clone --depth 1 --branch "$LLAMA_TAG" "$LLAMA_REPO" "$LLAMA_DIR"
    echo "      Done."
fi

# Step 2: Build with CMake (skip if already built)
if [ -d "$LIB_DIR" ] && ls "$LIB_DIR"/*.a 1>/dev/null 2>&1; then
    echo "[2/4] llama.cpp already built (libraries found in $LIB_DIR)"
else
    echo "[2/4] Building llama.cpp with Metal support..."
    mkdir -p "$LLAMA_BUILD_DIR"
    cmake -B "$LLAMA_BUILD_DIR" -S "$LLAMA_DIR" \
        -DCMAKE_BUILD_TYPE=Release \
        -DGGML_METAL=ON \
        -DGGML_METAL_EMBED_LIBRARY=ON \
        -DBUILD_SHARED_LIBS=OFF \
        -DLLAMA_BUILD_EXAMPLES=OFF \
        -DLLAMA_BUILD_TESTS=OFF \
        -DLLAMA_BUILD_SERVER=OFF \
        -DLLAMA_BUILD_TOOLS=OFF \
        -DLLAMA_BUILD_COMMON=OFF

    cmake --build "$LLAMA_BUILD_DIR" --config Release -j "$(sysctl -n hw.ncpu)"
    echo "      Done."

    # Step 3: Consolidate static libraries
    echo "[3/4] Consolidating static libraries..."
    mkdir -p "$LIB_DIR"
    find "$LLAMA_BUILD_DIR" -name "*.a" -not -path "$LIB_DIR/*" -exec cp {} "$LIB_DIR/" \;
    echo "      Libraries consolidated in $LIB_DIR:"
    ls -la "$LIB_DIR"/*.a 2>/dev/null || echo "      (no .a files found)"
fi

# Step 4: Copy headers (llama.h + all ggml headers it depends on)
echo "[4/4] Installing headers..."
mkdir -p "$CLLAMA_INCLUDE"
cp "$LLAMA_DIR/include/llama.h" "$CLLAMA_INCLUDE/"
cp "$LLAMA_DIR/ggml/include/"*.h "$CLLAMA_INCLUDE/"

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Libraries: $LIB_DIR/"
echo "Headers:   $CLLAMA_INCLUDE/"
