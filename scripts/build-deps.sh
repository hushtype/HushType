#!/bin/bash
# build-deps.sh — Build all C/C++ dependencies (whisper.cpp + llama.cpp).
#
# Usage: ./scripts/build-deps.sh
#
# This is a convenience wrapper that runs setup-whisper.sh and setup-llama.sh
# in sequence. Each script clones, builds, and installs headers + static
# libraries for its respective dependency.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== VaulType: Building All Dependencies ==="
echo ""

# Build whisper.cpp
"$SCRIPT_DIR/setup-whisper.sh"
echo ""

# Build llama.cpp
"$SCRIPT_DIR/setup-llama.sh"
echo ""

echo "=== All Dependencies Built Successfully ==="
