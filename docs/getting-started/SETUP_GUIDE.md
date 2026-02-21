Last Updated: 2026-02-13

# Development Environment Setup Guide

> **VaulType** — Privacy-first, macOS-native speech-to-text with local LLM post-processing.
> This guide walks you through every step of setting up a local development environment for VaulType, from installing prerequisites through building native C/C++ dependencies, configuring Xcode, and running the app in debug mode.

---

## Table of Contents

- [1. Prerequisites](#1-prerequisites)
  - [1.1 Required Software](#11-required-software)
  - [1.2 Installing Homebrew](#12-installing-homebrew)
  - [1.3 Installing CMake](#13-installing-cmake)
  - [1.4 Installing Xcode and Command Line Tools](#14-installing-xcode-and-command-line-tools)
  - [1.5 Verifying Your Environment](#15-verifying-your-environment)
- [2. System Requirements](#2-system-requirements)
  - [2.1 Hardware Requirements](#21-hardware-requirements)
  - [2.2 Software Requirements](#22-software-requirements)
  - [2.3 Disk Space Budget](#23-disk-space-budget)
- [3. Clone the VaulType Repository](#3-clone-the-vaultype-repository)
- [4. Build whisper.cpp as a Static Library](#4-build-whispercpp-as-a-static-library)
  - [4.1 Clone whisper.cpp](#41-clone-whispercpp)
  - [4.2 Configure CMake with Metal Support](#42-configure-cmake-with-metal-support)
  - [4.3 Build the Universal Binary](#43-build-the-universal-binary)
  - [4.4 Install to the Vendor Directory](#44-install-to-the-vendor-directory)
  - [4.5 Verify the whisper.cpp Build](#45-verify-the-whispercpp-build)
- [5. Build llama.cpp as a Static Library](#5-build-llamacpp-as-a-static-library)
  - [5.1 Clone llama.cpp](#51-clone-llamacpp)
  - [5.2 Configure CMake with Metal Support](#52-configure-cmake-with-metal-support)
  - [5.3 Build the Universal Binary](#53-build-the-universal-binary)
  - [5.4 Install to the Vendor Directory](#54-install-to-the-vendor-directory)
  - [5.5 Verify the llama.cpp Build](#55-verify-the-llamacpp-build)
- [6. Xcode Project Setup](#6-xcode-project-setup)
  - [6.1 Open the Project](#61-open-the-project)
  - [6.2 Configure Header Search Paths](#62-configure-header-search-paths)
  - [6.3 Configure Library Search Paths](#63-configure-library-search-paths)
  - [6.4 Link Static Libraries](#64-link-static-libraries)
  - [6.5 Module Map Setup](#65-module-map-setup)
  - [6.6 Bridging Header Configuration](#66-bridging-header-configuration)
  - [6.7 Other Linker Flags](#67-other-linker-flags)
- [7. Code Signing Configuration](#7-code-signing-configuration)
  - [7.1 Developer ID and Team Selection](#71-developer-id-and-team-selection)
  - [7.2 Provisioning Profile Setup](#72-provisioning-profile-setup)
  - [7.3 Hardened Runtime Settings](#73-hardened-runtime-settings)
  - [7.4 Local Development Signing](#74-local-development-signing)
- [8. Entitlements Setup](#8-entitlements-setup)
  - [8.1 Required Entitlements File](#81-required-entitlements-file)
  - [8.2 Info.plist Privacy Keys](#82-infoplist-privacy-keys)
  - [8.3 Hardened Runtime Exceptions](#83-hardened-runtime-exceptions)
- [9. Running the App in Debug Mode](#9-running-the-app-in-debug-mode)
  - [9.1 Build and Run from Xcode](#91-build-and-run-from-xcode)
  - [9.2 Granting Permissions on First Launch](#92-granting-permissions-on-first-launch)
  - [9.3 Debug Console Output](#93-debug-console-output)
  - [9.4 Environment Variables for Debugging](#94-environment-variables-for-debugging)
- [10. Downloading Initial Models for Development](#10-downloading-initial-models-for-development)
  - [10.1 Using the Built-in Model Manager](#101-using-the-built-in-model-manager)
  - [10.2 Manual Model Download](#102-manual-model-download)
  - [10.3 Recommended Development Models](#103-recommended-development-models)
  - [10.4 Verifying Model Files](#104-verifying-model-files)
- [11. Common Setup Issues and Solutions](#11-common-setup-issues-and-solutions)
  - [11.1 CMake Not Found or Wrong Version](#111-cmake-not-found-or-wrong-version)
  - [11.2 Metal Compilation Errors](#112-metal-compilation-errors)
  - [11.3 Linker Errors](#113-linker-errors)
  - [11.4 Permission Issues](#114-permission-issues)
  - [11.5 Code Signing Errors](#115-code-signing-errors)
  - [11.6 Xcode Build Failures](#116-xcode-build-failures)
  - [11.7 Runtime Crashes](#117-runtime-crashes)
- [Related Documentation](#related-documentation)

---

## 1. Prerequisites

### 1.1 Required Software

Before you begin, ensure the following tools are installed on your Mac:

| Tool | Minimum Version | Purpose |
|---|---|---|
| **macOS** | 14.0 (Sonoma) | Base operating system |
| **Xcode** | 15.0+ | IDE, Swift compiler, Metal SDK |
| **Command Line Tools** | Xcode 15+ | `clang`, `ld`, `make`, system headers |
| **CMake** | 3.21+ | Build system for whisper.cpp and llama.cpp |
| **Git** | 2.39+ | Source control |
| **Homebrew** | 4.0+ | Package manager for installing CMake and other tools |

> ℹ️ **Note**: Git is bundled with Xcode Command Line Tools. You do not need to install it separately unless you want a newer version.

### 1.2 Installing Homebrew

If you do not already have Homebrew installed:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

After installation, follow the shell configuration instructions printed by the installer. On Apple Silicon Macs, Homebrew installs to `/opt/homebrew`. Ensure it is on your `PATH`:

```bash
# For Apple Silicon (add to ~/.zshrc if not already present)
eval "$(/opt/homebrew/bin/brew shellenv)"

# Verify installation
brew --version
```

### 1.3 Installing CMake

CMake is required to build both whisper.cpp and llama.cpp from source:

```bash
brew install cmake

# Verify the installed version (must be 3.21+)
cmake --version
```

> ⚠️ **Warning**: Do not use the CMake.app GUI bundle from cmake.org — the Homebrew version integrates correctly with the command-line toolchain and avoids `PATH` confusion.

### 1.4 Installing Xcode and Command Line Tools

1. Install Xcode 15+ from the Mac App Store or [Apple Developer Downloads](https://developer.apple.com/download/applications/).

2. Launch Xcode once and accept the license agreement.

3. Install Command Line Tools:

```bash
xcode-select --install
```

4. If you have multiple Xcode versions, ensure the correct one is selected:

```bash
# Check the currently active Xcode
xcode-select -p

# Switch if needed (adjust path to your Xcode version)
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

5. Accept the Xcode license from the command line (if not already done):

```bash
sudo xcodebuild -license accept
```

### 1.5 Verifying Your Environment

Run the following verification commands. All should succeed before proceeding:

```bash
# macOS version (must be 14.0+)
sw_vers -productVersion

# Xcode version (must be 15.0+)
xcodebuild -version

# Swift version (must be 5.9+)
swift --version

# CMake version (must be 3.21+)
cmake --version

# Git version
git --version

# Metal compiler availability
xcrun -f metal
```

Expected output (versions may vary):

```
14.5                              # macOS Sonoma or later
Xcode 15.4                        # Xcode 15+
swift-driver version: 1.90.11.1   # Swift 5.9+
cmake version 3.28.1              # CMake 3.21+
git version 2.43.0                # Git 2.39+
/usr/bin/metal                     # Metal compiler path
```

> ✅ **Checkpoint**: If all six commands succeed, your prerequisites are ready. Proceed to Section 2.

---

## 2. System Requirements

### 2.1 Hardware Requirements

| Component | Minimum | Recommended | Notes |
|---|---|---|---|
| **Processor** | Intel Core i5 (2019+) | Apple Silicon (M1/M2/M3/M4) | Metal GPU required for accelerated inference |
| **RAM** | 8 GB | 16 GB+ | LLM models load entirely into memory |
| **GPU** | Integrated Intel/Apple GPU | Apple Silicon unified memory | Metal 3 recommended for best performance |
| **Disk (app)** | 500 MB | 500 MB | Application bundle and build artifacts |
| **Disk (models)** | 2 GB | 6 GB+ | Whisper + LLM model files (see Section 2.3) |

> 🍎 **Apple Silicon Recommended**: VaulType is designed for Apple Silicon. While Intel Macs are supported, inference performance on Apple Silicon is 3-10x faster thanks to unified memory architecture and Metal GPU acceleration. See `../architecture/TECH_STACK.md` for detailed performance comparisons.

### 2.2 Software Requirements

| Requirement | Version | Notes |
|---|---|---|
| **macOS** | 14.0+ (Sonoma) | Required for SwiftUI 5, SwiftData, Metal 3 APIs |
| **Xcode** | 15.0+ | Swift 5.9, macOS 14 SDK |
| **CMake** | 3.21+ | Required for Metal shader compilation in C++ libraries |
| **Python** (optional) | 3.9+ | Only needed if running whisper.cpp test scripts |

> ⚠️ **Warning**: macOS 13 (Ventura) and earlier are **not supported**. VaulType depends on SwiftData and SwiftUI 5.0 APIs introduced in macOS 14.

### 2.3 Disk Space Budget

Plan for the following disk usage during development:

| Component | Size | Notes |
|---|---|---|
| VaulType source code | ~50 MB | Including git history |
| whisper.cpp source + build | ~200 MB | Build artifacts are temporary |
| llama.cpp source + build | ~300 MB | Build artifacts are temporary |
| Vendor libraries (installed) | ~100 MB | Static libraries + headers |
| Xcode build (DerivedData) | ~500 MB | Debug build artifacts |
| Whisper model (tiny) | ~75 MB | Minimum for development |
| Whisper model (base) | ~150 MB | Good quality for testing |
| Whisper model (small) | ~500 MB | Production-quality STT |
| LLM model (small, Q4) | ~2-4 GB | e.g., Phi-3-mini, Qwen2-1.5B |
| **Total (minimum dev)** | **~1.5 GB** | With tiny Whisper + small LLM |
| **Total (recommended dev)** | **~4-6 GB** | With base/small Whisper + capable LLM |

> 💡 **Tip**: Model files are stored in `~/Library/Application Support/VaulType/Models/`. You can symlink this directory to an external drive if disk space is limited.

---

## 3. Clone the VaulType Repository

```bash
# Clone the repository
git clone https://github.com/your-org/vaultype.git
cd vaultype

# Verify the project structure
ls -la
```

You should see a directory structure similar to:

```
vaultype/
├── VaulType/                 # Main Xcode project source
│   ├── App/                  # Application entry point
│   ├── Features/             # Feature modules
│   ├── Infrastructure/       # C/C++ bridge, audio, injection
│   └── Resources/            # Assets, entitlements, Info.plist
├── VaulType.xcodeproj/       # Xcode project file
├── vendor/                   # Third-party static libraries (created during setup)
├── scripts/                  # Build and utility scripts
├── docs/                     # Documentation
├── tests/                    # Unit and integration tests
└── Package.swift             # SPM dependencies (Sparkle, etc.)
```

> ℹ️ **Note**: The `vendor/` directory may not exist yet. It will be created in Sections 4 and 5 when you build and install the C/C++ dependencies.

---

## 4. Build whisper.cpp as a Static Library

whisper.cpp provides the speech-to-text inference engine. We build it as a static library with Metal GPU acceleration and link it into the Xcode project.

### 4.1 Clone whisper.cpp

```bash
# From outside the VaulType project directory
cd ~/dev

# Clone the latest whisper.cpp
git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp

# Pin to a known-good release tag (recommended for stability)
git checkout v1.7.4
```

> 💡 **Tip**: Check the [whisper.cpp releases page](https://github.com/ggerganov/whisper.cpp/releases) for the latest stable tag. Using a tagged release avoids potential breakage from `master` branch changes.

### 4.2 Configure CMake with Metal Support

Create a build directory and configure CMake for a static library build with Metal acceleration:

```bash
# Create build directory
mkdir -p build && cd build

# Configure for Apple Silicon (arm64)
cmake .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DWHISPER_METAL=ON \
  -DWHISPER_COREML=OFF \
  -DWHISPER_NO_ACCELERATE=OFF \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_EXAMPLES=OFF \
  -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DCMAKE_INSTALL_PREFIX="$(pwd)/install"
```

**CMake flags explained**:

| Flag | Value | Purpose |
|---|---|---|
| `CMAKE_BUILD_TYPE` | `Release` | Optimized build (-O3) |
| `BUILD_SHARED_LIBS` | `OFF` | Produce `.a` static library, not `.dylib` |
| `WHISPER_METAL` | `ON` | Enable Metal GPU acceleration |
| `WHISPER_COREML` | `OFF` | We use Metal directly, not CoreML |
| `WHISPER_NO_ACCELERATE` | `OFF` | Keep Accelerate framework for CPU fallback |
| `WHISPER_BUILD_TESTS` | `OFF` | Skip building test binaries |
| `WHISPER_BUILD_EXAMPLES` | `OFF` | Skip building example binaries |
| `CMAKE_OSX_ARCHITECTURES` | `arm64;x86_64` | Universal binary for both architectures |
| `CMAKE_OSX_DEPLOYMENT_TARGET` | `14.0` | Minimum macOS version |

> ⚠️ **Warning**: If you are building **only** for Apple Silicon (faster build), replace `"arm64;x86_64"` with `"arm64"`. The universal binary is required only for distribution or if you test on Intel hardware.

### 4.3 Build the Universal Binary

```bash
# Build using all available cores
cmake --build . --config Release -j $(sysctl -n hw.logicalcpu)
```

The build typically takes 2-5 minutes depending on your hardware. You should see Metal shader compilation output during the build:

```
[  5%] Building C object CMakeFiles/whisper.dir/ggml/src/ggml.c.o
[ 10%] Building C object CMakeFiles/whisper.dir/ggml/src/ggml-metal.m.o
...
[100%] Built target whisper
```

> ✅ **Checkpoint**: The build should complete without errors. If you see Metal-related errors, refer to Section 11.2.

### 4.4 Install to the Vendor Directory

Copy the built libraries and headers into the VaulType vendor directory:

```bash
# Create the vendor directory structure in the VaulType project
VAULTYPE_DIR=~/dev/vaultype
mkdir -p "$VAULTYPE_DIR/vendor/whisper/lib"
mkdir -p "$VAULTYPE_DIR/vendor/whisper/include"

# Install the static library
cmake --install . --config Release

# Copy the static library (or libraries)
cp install/lib/libwhisper.a "$VAULTYPE_DIR/vendor/whisper/lib/"

# If ggml is built as a separate static library, copy it too
if [ -f install/lib/libggml.a ]; then
  cp install/lib/libggml.a "$VAULTYPE_DIR/vendor/whisper/lib/"
fi

# Copy additional ggml libraries if present
for lib in install/lib/libggml-*.a; do
  [ -f "$lib" ] && cp "$lib" "$VAULTYPE_DIR/vendor/whisper/lib/"
done

# Copy headers
cp install/include/whisper.h "$VAULTYPE_DIR/vendor/whisper/include/"
cp -r install/include/ggml*.h "$VAULTYPE_DIR/vendor/whisper/include/" 2>/dev/null || true

# Copy Metal shader resources
if [ -f bin/ggml-metal.metal ]; then
  mkdir -p "$VAULTYPE_DIR/vendor/whisper/resources"
  cp bin/ggml-metal.metal "$VAULTYPE_DIR/vendor/whisper/resources/"
  cp bin/default.metallib "$VAULTYPE_DIR/vendor/whisper/resources/" 2>/dev/null || true
fi
```

### 4.5 Verify the whisper.cpp Build

```bash
# Verify the static library exists and contains both architectures
file "$VAULTYPE_DIR/vendor/whisper/lib/libwhisper.a"
# Expected: "current ar archive" or similar

lipo -info "$VAULTYPE_DIR/vendor/whisper/lib/libwhisper.a"
# Expected for universal: "Architectures in the fat file: ... are: x86_64 arm64"
# Expected for arm64 only: "Non-fat file: ... is architecture: arm64"

# Verify headers are present
ls "$VAULTYPE_DIR/vendor/whisper/include/"
# Expected: whisper.h ggml.h (and possibly others)

# Verify the library exports whisper symbols
nm "$VAULTYPE_DIR/vendor/whisper/lib/libwhisper.a" | grep "whisper_init" | head -5
# Should show symbol entries for whisper_init_from_file and related functions
```

> ✅ **Checkpoint**: You should have `libwhisper.a` (and possibly `libggml.a`) in `vendor/whisper/lib/` and `whisper.h` in `vendor/whisper/include/`. Proceed to Section 5.

---

## 5. Build llama.cpp as a Static Library

llama.cpp provides the LLM inference engine for text post-processing (grammar correction, formatting, rephrasing). The build process mirrors whisper.cpp.

### 5.1 Clone llama.cpp

```bash
# From outside the VaulType project directory
cd ~/dev

# Clone the latest llama.cpp
git clone https://github.com/ggerganov/llama.cpp.git
cd llama.cpp

# Pin to a known-good release tag
git checkout b4568
```

> 💡 **Tip**: llama.cpp uses build number tags (e.g., `b4568`). Check the [llama.cpp releases page](https://github.com/ggerganov/llama.cpp/releases) for the latest stable build.

### 5.2 Configure CMake with Metal Support

```bash
# Create build directory
mkdir -p build && cd build

# Configure for static library with Metal
cmake .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DGGML_METAL=ON \
  -DGGML_ACCELERATE=ON \
  -DGGML_BLAS=OFF \
  -DLLAMA_BUILD_TESTS=OFF \
  -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_BUILD_SERVER=OFF \
  -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DCMAKE_INSTALL_PREFIX="$(pwd)/install"
```

**CMake flags explained**:

| Flag | Value | Purpose |
|---|---|---|
| `GGML_METAL` | `ON` | Enable Metal GPU acceleration |
| `GGML_ACCELERATE` | `ON` | Use Apple Accelerate framework for BLAS |
| `GGML_BLAS` | `OFF` | Disable generic BLAS (use Accelerate instead) |
| `LLAMA_BUILD_TESTS` | `OFF` | Skip test binaries |
| `LLAMA_BUILD_EXAMPLES` | `OFF` | Skip example binaries |
| `LLAMA_BUILD_SERVER` | `OFF` | Skip the HTTP server binary |

### 5.3 Build the Universal Binary

```bash
# Build using all available cores
cmake --build . --config Release -j $(sysctl -n hw.logicalcpu)
```

Build time is typically 3-8 minutes. The output includes Metal shader compilation:

```
[  2%] Building C object ggml/src/CMakeFiles/ggml.dir/ggml.c.o
[  5%] Building CXX object ggml/src/CMakeFiles/ggml.dir/ggml-metal.m.o
...
[100%] Built target llama
```

### 5.4 Install to the Vendor Directory

```bash
# Create the vendor directory structure
VAULTYPE_DIR=~/dev/vaultype
mkdir -p "$VAULTYPE_DIR/vendor/llama/lib"
mkdir -p "$VAULTYPE_DIR/vendor/llama/include"

# Install
cmake --install . --config Release

# Copy the static libraries
cp install/lib/libllama.a "$VAULTYPE_DIR/vendor/llama/lib/"
cp install/lib/libggml.a "$VAULTYPE_DIR/vendor/llama/lib/" 2>/dev/null || true

# Copy additional ggml libraries if present
for lib in install/lib/libggml-*.a; do
  [ -f "$lib" ] && cp "$lib" "$VAULTYPE_DIR/vendor/llama/lib/"
done

# Copy the common library if present
cp install/lib/libcommon.a "$VAULTYPE_DIR/vendor/llama/lib/" 2>/dev/null || true

# Copy headers
cp install/include/llama.h "$VAULTYPE_DIR/vendor/llama/include/"
cp install/include/ggml*.h "$VAULTYPE_DIR/vendor/llama/include/" 2>/dev/null || true

# Copy Metal shader resources
if [ -f bin/ggml-metal.metal ]; then
  mkdir -p "$VAULTYPE_DIR/vendor/llama/resources"
  cp bin/ggml-metal.metal "$VAULTYPE_DIR/vendor/llama/resources/"
  cp bin/default.metallib "$VAULTYPE_DIR/vendor/llama/resources/" 2>/dev/null || true
fi
```

> ℹ️ **Note**: Both whisper.cpp and llama.cpp depend on ggml. If llama.cpp's `libggml.a` conflicts with whisper.cpp's version, you may need to use only one copy. In practice, VaulType's Xcode project is configured to handle this — see Section 6.4.

### 5.5 Verify the llama.cpp Build

```bash
# Verify the static library
file "$VAULTYPE_DIR/vendor/llama/lib/libllama.a"
lipo -info "$VAULTYPE_DIR/vendor/llama/lib/libllama.a"

# Verify headers
ls "$VAULTYPE_DIR/vendor/llama/include/"
# Expected: llama.h ggml.h (and possibly others)

# Verify symbol exports
nm "$VAULTYPE_DIR/vendor/llama/lib/libllama.a" | grep "llama_init" | head -5
```

After completing both builds, your vendor directory should look like:

```
vendor/
├── whisper/
│   ├── include/
│   │   ├── whisper.h
│   │   └── ggml.h
│   ├── lib/
│   │   ├── libwhisper.a
│   │   └── libggml.a         (if separate)
│   └── resources/
│       ├── ggml-metal.metal   (if present)
│       └── default.metallib   (if present)
└── llama/
    ├── include/
    │   ├── llama.h
    │   └── ggml.h
    ├── lib/
    │   ├── libllama.a
    │   └── libggml.a          (if separate)
    └── resources/
        ├── ggml-metal.metal    (if present)
        └── default.metallib    (if present)
```

> ✅ **Checkpoint**: Both libraries are built and installed. Proceed to Xcode configuration.

---

## 6. Xcode Project Setup

### 6.1 Open the Project

```bash
# Open the Xcode project
open ~/dev/vaultype/VaulType.xcodeproj
```

Alternatively, double-click `VaulType.xcodeproj` in Finder. When prompted, allow Xcode to resolve Swift Package Manager dependencies (Sparkle, etc.).

> ℹ️ **Note**: The first time you open the project, SPM will fetch and resolve dependencies. This may take 1-2 minutes depending on your internet connection.

### 6.2 Configure Header Search Paths

In Xcode, select the **VaulType** target, navigate to **Build Settings**, and configure the following:

1. Search for **"Header Search Paths"** (`HEADER_SEARCH_PATHS`).
2. Add the following paths (set to **recursive** is not needed; use non-recursive):

```
$(PROJECT_DIR)/vendor/whisper/include
$(PROJECT_DIR)/vendor/llama/include
```

In the Xcode build settings UI:

| Setting | Value | Recursive |
|---|---|---|
| Header Search Paths | `$(PROJECT_DIR)/vendor/whisper/include` | No |
| Header Search Paths | `$(PROJECT_DIR)/vendor/llama/include` | No |

> 💡 **Tip**: You can also set these in the `.xcconfig` file if the project uses one:

```
// VaulType.xcconfig
HEADER_SEARCH_PATHS = $(inherited) $(PROJECT_DIR)/vendor/whisper/include $(PROJECT_DIR)/vendor/llama/include
```

### 6.3 Configure Library Search Paths

1. Search for **"Library Search Paths"** (`LIBRARY_SEARCH_PATHS`) in Build Settings.
2. Add:

```
$(PROJECT_DIR)/vendor/whisper/lib
$(PROJECT_DIR)/vendor/llama/lib
```

| Setting | Value |
|---|---|
| Library Search Paths | `$(PROJECT_DIR)/vendor/whisper/lib` |
| Library Search Paths | `$(PROJECT_DIR)/vendor/llama/lib` |

### 6.4 Link Static Libraries

Navigate to the target's **Build Phases** tab and configure **Link Binary With Libraries**:

1. Click the **+** button under "Link Binary With Libraries."
2. Click **Add Other... > Add Files...** and navigate to:
   - `vendor/whisper/lib/libwhisper.a`
   - `vendor/llama/lib/libllama.a`
   - `vendor/whisper/lib/libggml.a` (or `vendor/llama/lib/libggml.a` — use one copy)
   - Any additional `libggml-*.a` files present in the vendor directories

3. Also link the following **system frameworks** (if not already linked):

| Framework | Purpose |
|---|---|
| `Metal.framework` | GPU-accelerated ML inference |
| `MetalKit.framework` | Metal resource management |
| `MetalPerformanceShaders.framework` | Optimized Metal compute kernels |
| `Accelerate.framework` | CPU-optimized BLAS, DSP, vectorized math |
| `Foundation.framework` | Core system services |
| `AVFoundation.framework` | Audio capture engine |
| `CoreAudio.framework` | Low-level audio services |
| `ApplicationServices.framework` | CGEvent accessibility APIs |

> ⚠️ **Warning**: If you include `libggml.a` from **both** whisper and llama vendor directories, you will get duplicate symbol linker errors. Use only one copy. Typically, the llama.cpp version is newer and compatible with both.

### 6.5 Module Map Setup

To use the C libraries from Swift, create module maps. VaulType ships with pre-configured module maps in the project, but if you need to recreate them:

**`vendor/whisper/include/module.modulemap`**:

```c
module CWhisper {
    header "whisper.h"
    link "whisper"
    export *
}
```

**`vendor/llama/include/module.modulemap`**:

```c
module CLlama {
    header "llama.h"
    link "llama"
    export *
}
```

Then add the module map directories to **Import Paths** in Build Settings:

1. Search for **"Import Paths"** (`SWIFT_INCLUDE_PATHS`).
2. Add:

```
$(PROJECT_DIR)/vendor/whisper/include
$(PROJECT_DIR)/vendor/llama/include
```

With module maps in place, you can import the C libraries directly in Swift:

```swift
import CWhisper
import CLlama
```

### 6.6 Bridging Header Configuration

If the project uses a bridging header instead of (or in addition to) module maps, the bridging header is located at:

```
VaulType/Infrastructure/Bridge/VaulType-Bridging-Header.h
```

Contents:

```c
//
//  VaulType-Bridging-Header.h
//  VaulType
//

#ifndef VaulType_Bridging_Header_h
#define VaulType_Bridging_Header_h

// whisper.cpp
#include "whisper.h"

// llama.cpp
#include "llama.h"

// ggml (shared)
#include "ggml.h"

#endif /* VaulType_Bridging_Header_h */
```

Verify the bridging header path in Build Settings:

1. Search for **"Objective-C Bridging Header"** (`SWIFT_OBJC_BRIDGING_HEADER`).
2. Ensure it is set to:

```
VaulType/Infrastructure/Bridge/VaulType-Bridging-Header.h
```

### 6.7 Other Linker Flags

In Build Settings, search for **"Other Linker Flags"** (`OTHER_LDFLAGS`) and ensure the following are set:

```
-lstdc++
-lc++
```

These flags are required because whisper.cpp and llama.cpp are C++ libraries. Without them, you will encounter undefined symbol errors for C++ standard library functions.

> ℹ️ **Note**: If you use module maps (`import CWhisper`), the `link` directive in the module map handles library linking. You may still need `-lstdc++` for C++ runtime support.

---

## 7. Code Signing Configuration

### 7.1 Developer ID and Team Selection

For local development, you can use either a free Apple ID or a paid Apple Developer account:

1. Open Xcode **Settings** (⌘,) > **Accounts** tab.
2. Click **+** and sign in with your Apple ID.
3. In the project settings, select the **VaulType** target.
4. Under **Signing & Capabilities**:
   - Set **Team** to your Apple ID or Developer team.
   - Set **Bundle Identifier** to `com.yourname.vaultype` (for local development).

| Setting | Local Development | Distribution |
|---|---|---|
| Team | Personal Team / Apple ID | Developer ID team |
| Signing Certificate | Sign to Run Locally | Developer ID Application |
| Provisioning | Automatic | Manual or Automatic |

> 🔒 **Security Note**: For distribution builds, you must use a paid Apple Developer account ($99/year) with a Developer ID Application certificate. Local development works with a free Apple ID.

### 7.2 Provisioning Profile Setup

For local development with a free Apple ID:

1. Under **Signing & Capabilities**, check **"Automatically manage signing"**.
2. Xcode will create a provisioning profile automatically.
3. The first time you build, Xcode may prompt you to register the device (your Mac).

For distribution with a paid developer account:

1. Create a Developer ID Application certificate in the [Apple Developer Portal](https://developer.apple.com/account).
2. Xcode will automatically download and use the certificate when you select your team.

### 7.3 Hardened Runtime Settings

VaulType requires **Hardened Runtime** for notarization and certain entitlements. Under **Signing & Capabilities**:

1. Click **+ Capability**.
2. Add **Hardened Runtime**.
3. Under the Hardened Runtime section, enable these exceptions:

| Exception | Required | Purpose |
|---|---|---|
| Allow Unsigned Executable Memory | Yes | whisper.cpp / llama.cpp JIT-compiled Metal shaders |
| Allow DYLD Environment Variables | No | Only for debugging if needed |
| Disable Library Validation | Yes | Loading Metal shader libraries at runtime |

In the `.entitlements` file, these appear as:

```xml
<key>com.apple.security.cs.allow-unsigned-executable-memory</key>
<true/>
<key>com.apple.security.cs.disable-library-validation</key>
<true/>
```

> ⚠️ **Warning**: These hardened runtime exceptions are necessary for Metal shader compilation at runtime. Without them, whisper.cpp and llama.cpp will fail to initialize their Metal compute pipelines.

### 7.4 Local Development Signing

For the quickest local development setup:

1. In **Signing & Capabilities**, ensure:
   - **Automatically manage signing** is checked.
   - **Team** is set to your personal team.
2. Under **Build Settings**, search for **"Code Signing Identity"**:
   - Debug: `Apple Development`
   - Release: `Apple Development` (or `Developer ID Application` for distribution)

```
// Build Settings
CODE_SIGN_IDENTITY = "Apple Development"
CODE_SIGN_STYLE = Automatic
DEVELOPMENT_TEAM = YOUR_TEAM_ID
```

---

## 8. Entitlements Setup

### 8.1 Required Entitlements File

The entitlements file is located at `VaulType/Resources/VaulType.entitlements`. It must contain the following keys:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- App Sandbox disabled (required for CGEvent, Accessibility APIs) -->
    <key>com.apple.security.app-sandbox</key>
    <false/>

    <!-- Hardened Runtime exceptions -->
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>

    <!-- Audio input (microphone) -->
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
```

**Entitlements explained**:

| Entitlement | Value | Purpose |
|---|---|---|
| `app-sandbox` | `false` | CGEvent and Accessibility APIs require running outside the sandbox |
| `allow-unsigned-executable-memory` | `true` | Metal shader JIT compilation |
| `disable-library-validation` | `true` | Loading Metal shader `.metallib` files |
| `device.audio-input` | `true` | Microphone access for speech capture |

> 🔒 **Security Note**: VaulType runs **outside** the App Sandbox because macOS sandboxing blocks the CGEvent and Accessibility APIs that are essential for text injection. Privacy is enforced at the application level — all data stays local, no network calls for user data, no telemetry. See `../security/SECURITY.md` for the full security model.

### 8.2 Info.plist Privacy Keys

The `Info.plist` must include usage description strings for protected resources. macOS displays these strings when requesting user permission:

```xml
<!-- Info.plist -->
<key>NSMicrophoneUsageDescription</key>
<string>VaulType needs microphone access to capture your speech for local, on-device transcription. Audio is never sent to any server.</string>

<key>NSAccessibilityUsageDescription</key>
<string>VaulType needs Accessibility access to type transcribed text into your active application.</string>
```

> ❌ **Critical**: If `NSMicrophoneUsageDescription` is missing from `Info.plist`, the app will **crash** immediately when attempting to access the microphone. macOS enforces this at the system level.

### 8.3 Hardened Runtime Exceptions

The following hardened runtime exceptions are configured in the entitlements file and must match the Xcode capability settings from Section 7.3:

| Exception Key | Required For |
|---|---|
| `com.apple.security.cs.allow-unsigned-executable-memory` | Metal compute pipeline compilation (whisper.cpp, llama.cpp) |
| `com.apple.security.cs.disable-library-validation` | Loading compiled `.metallib` shader bundles |
| `com.apple.security.device.audio-input` | AVAudioEngine microphone capture |

Verify the entitlements are correctly applied by building and checking the signed binary:

```bash
# After building in Xcode, check the entitlements of the built app
codesign -d --entitlements - ~/Library/Developer/Xcode/DerivedData/VaulType-*/Build/Products/Debug/VaulType.app
```

You should see the entitlements listed in the output XML.

---

## 9. Running the App in Debug Mode

### 9.1 Build and Run from Xcode

1. Select the **VaulType** scheme in the Xcode toolbar.
2. Ensure the destination is set to **My Mac**.
3. Press **⌘R** (or click the Run button) to build and launch.

The first build may take 3-5 minutes as Xcode compiles all Swift sources and links the C/C++ static libraries. Subsequent incremental builds are typically under 30 seconds.

> 💡 **Tip**: If you want to build without running (to check for compilation errors), press **⌘B**.

### 9.2 Granting Permissions on First Launch

On the first launch, VaulType requests two critical permissions. You must grant both for full functionality:

**Step 1: Microphone Permission**

A system dialog appears:

```
"VaulType" would like to access the microphone.

VaulType needs microphone access to capture your speech for local,
on-device transcription. Audio is never sent to any server.

[Don't Allow]  [OK]
```

Click **OK** to grant microphone access.

**Step 2: Accessibility Permission**

VaulType opens a guided dialog explaining why Accessibility access is needed, then directs you to System Settings:

1. Open **System Settings > Privacy & Security > Accessibility**.
2. Click the **lock icon** to allow changes.
3. Toggle **VaulType** to **ON** in the list.
4. If VaulType does not appear in the list, click **+** and navigate to the app in `/Applications` or `DerivedData`.

> ⚠️ **Warning**: During development, Accessibility permissions are tied to the **code signature**. Every time you rebuild with a different signing identity or the binary changes significantly, macOS may revoke the Accessibility permission. You will need to re-grant it. This is a known development friction point.

**Resetting permissions during development**:

```bash
# Reset Accessibility permission for VaulType (requires admin password)
sudo tccutil reset Accessibility com.yourname.vaultype

# Reset Microphone permission
tccutil reset Microphone com.yourname.vaultype
```

See `../features/PERMISSIONS.md` for the complete permission management system, including handling denied permissions gracefully.

### 9.3 Debug Console Output

VaulType uses `os_log` and Swift `Logger` for structured logging. In Xcode's debug console, you will see output like:

```
[VaulType/Audio] INFO: Audio engine started - sample rate: 16000 Hz, format: PCM Float32
[VaulType/Audio] INFO: Ring buffer allocated - capacity: 480000 samples (30.0 seconds)
[VaulType/Whisper] INFO: Loading whisper model: ggml-base.bin (147.4 MB)
[VaulType/Whisper] INFO: Model loaded in 1.23s - using Metal GPU acceleration
[VaulType/LLM] INFO: Loading LLM model: phi-3-mini-Q4_K_M.gguf (2.3 GB)
[VaulType/LLM] INFO: Model loaded in 3.45s - Metal layers: 32/32
[VaulType/App] INFO: VaulType ready - all services initialized
```

To filter debug output by subsystem in the Xcode console, use the filter bar at the bottom and type `VaulType`.

### 9.4 Environment Variables for Debugging

You can configure additional debugging behavior through Xcode's scheme environment variables:

1. Click the scheme selector > **Edit Scheme...** (⌘<).
2. Select **Run** > **Arguments** > **Environment Variables**.
3. Add any of the following:

| Variable | Value | Purpose |
|---|---|---|
| `VAULTYPE_LOG_LEVEL` | `debug` | Enable verbose debug logging |
| `VAULTYPE_SKIP_MODEL_LOAD` | `1` | Skip model loading (for UI development) |
| `VAULTYPE_MOCK_AUDIO` | `1` | Use simulated audio input |
| `VAULTYPE_METAL_VALIDATION` | `1` | Enable Metal API validation layer |
| `METAL_DEVICE_WRAPPER_TYPE` | `1` | Enable Metal debug layer (system variable) |

> 💡 **Tip**: Enable `METAL_DEVICE_WRAPPER_TYPE=1` when debugging Metal-related issues. It adds runtime validation for Metal API calls and reports errors that would otherwise be silent.

---

## 10. Downloading Initial Models for Development

VaulType requires at least one Whisper model (for speech-to-text) and one LLM model (for text processing) to function. For development, we recommend lightweight models that load quickly and use minimal memory.

### 10.1 Using the Built-in Model Manager

The easiest way to download models is through VaulType's built-in Model Manager:

1. Launch VaulType.
2. Click the menu bar icon > **Settings** (or press **⌘,**).
3. Navigate to the **Models** tab.
4. Under **Whisper Models**, click **Download** next to **tiny** or **base**.
5. Under **LLM Models**, click **Browse Available Models** to see recommended options.
6. Select a small model (e.g., Qwen2-1.5B Q4_K_M) and click **Download**.

The Model Manager shows download progress with estimated time remaining and supports pause/resume.

> ℹ️ **Note**: If the app cannot start because no models are present, it will display a first-run setup wizard that guides you through model selection and download. See `../features/MODEL_MANAGEMENT.md` for complete details on the model lifecycle.

### 10.2 Manual Model Download

If you prefer to download models manually (e.g., for offline setups or CI environments):

**Whisper models** (GGML format):

```bash
# Create the model directory
MODEL_DIR="$HOME/Library/Application Support/VaulType/Models/whisper"
mkdir -p "$MODEL_DIR"

# Download whisper-tiny (75 MB) - fastest, lowest quality
curl -L -o "$MODEL_DIR/ggml-tiny.bin" \
  "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin"

# Download whisper-base (147 MB) - good balance for development
curl -L -o "$MODEL_DIR/ggml-base.bin" \
  "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"

# Download whisper-small (488 MB) - higher quality, slower
curl -L -o "$MODEL_DIR/ggml-small.bin" \
  "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"
```

**LLM models** (GGUF format):

```bash
# Create the model directory
LLM_DIR="$HOME/Library/Application Support/VaulType/Models/llm"
mkdir -p "$LLM_DIR"

# Download a small, capable LLM for development
# Example: Qwen2-1.5B (Q4_K_M quantization, ~1.1 GB)
curl -L -o "$LLM_DIR/qwen2-1.5b-instruct-q4_k_m.gguf" \
  "https://huggingface.co/Qwen/Qwen2-1.5B-Instruct-GGUF/resolve/main/qwen2-1_5b-instruct-q4_k_m.gguf"

# Alternative: Phi-3-mini (Q4_K_M, ~2.3 GB)
curl -L -o "$LLM_DIR/phi-3-mini-4k-instruct-q4_k_m.gguf" \
  "https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/resolve/main/Phi-3-mini-4k-instruct-q4.gguf"
```

### 10.3 Recommended Development Models

| Model | Type | Size | RAM Usage | Quality | Use Case |
|---|---|---|---|---|---|
| `ggml-tiny.bin` | Whisper | 75 MB | ~200 MB | Fair | Quick iteration, UI testing |
| `ggml-base.bin` | Whisper | 147 MB | ~400 MB | Good | **Recommended for development** |
| `ggml-small.bin` | Whisper | 488 MB | ~1 GB | Very Good | Testing production quality |
| Qwen2-1.5B Q4 | LLM | 1.1 GB | ~2 GB | Good | **Recommended for development** |
| Phi-3-mini Q4 | LLM | 2.3 GB | ~4 GB | Very Good | Testing production quality |
| Llama-3.2-1B Q4 | LLM | 0.8 GB | ~1.5 GB | Fair | Minimal resource usage |

> 💡 **Tip**: For the fastest development cycle, start with `ggml-tiny.bin` and Qwen2-1.5B. These models load in under 2 seconds on Apple Silicon and provide acceptable quality for testing the full pipeline.

### 10.4 Verifying Model Files

After downloading, verify the models are correctly placed and valid:

```bash
# List downloaded models
ls -lh "$HOME/Library/Application Support/VaulType/Models/whisper/"
ls -lh "$HOME/Library/Application Support/VaulType/Models/llm/"

# Verify file sizes (approximate)
# ggml-tiny.bin  should be ~75 MB
# ggml-base.bin  should be ~147 MB

# Check file integrity (GGML/GGUF magic bytes)
xxd -l 4 "$HOME/Library/Application Support/VaulType/Models/whisper/ggml-tiny.bin" | head -1
# Should show: 0x67676d6c (ggml magic)

xxd -l 4 "$HOME/Library/Application Support/VaulType/Models/llm/qwen2-1.5b-instruct-q4_k_m.gguf" | head -1
# Should show: 0x47475546 (GGUF magic)
```

> ✅ **Checkpoint**: With models downloaded and verified, VaulType is ready to run. Launch the app and test the full speech-to-text pipeline.

---

## 11. Common Setup Issues and Solutions

### 11.1 CMake Not Found or Wrong Version

**Symptom**: `cmake: command not found` or version mismatch.

```bash
# Check if CMake is installed
which cmake

# If not found, install via Homebrew
brew install cmake

# If version is too old
brew upgrade cmake

# Verify version (must be 3.21+)
cmake --version
```

**Symptom**: CMake is installed but not on `PATH` (Apple Silicon).

```bash
# Add Homebrew to PATH for Apple Silicon
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zshrc
source ~/.zshrc

# Verify
which cmake
# Expected: /opt/homebrew/bin/cmake
```

> ❌ **Common Mistake**: Installing CMake via the `.dmg` GUI installer from cmake.org puts it in `/Applications/CMake.app` and requires manual PATH configuration. Use `brew install cmake` instead.

### 11.2 Metal Compilation Errors

**Symptom**: Errors during the whisper.cpp or llama.cpp build related to Metal shaders.

```
error: use of undeclared identifier 'MTLGPUFamilyApple7'
error: 'metal_stdlib' file not found
```

**Solutions**:

1. Ensure Xcode Command Line Tools point to the full Xcode (not standalone CLT):

```bash
# Check the current developer directory
xcode-select -p
# Should be: /Applications/Xcode.app/Contents/Developer

# If it shows /Library/Developer/CommandLineTools, switch:
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

2. Verify the Metal compiler is available:

```bash
xcrun -f metal
# Should output: /Applications/Xcode.app/.../metal

xcrun metal --version
```

3. If on Intel Mac, some Metal features may not be available. Ensure your GPU supports Metal:

```bash
system_profiler SPDisplaysDataType | grep Metal
# Should show: Metal Support: Metal 3 (or Metal 2, etc.)
```

**Symptom**: Metal shader compilation succeeds but runtime initialization fails.

Check that the `default.metallib` file is being copied to the app bundle. In Xcode:

1. Go to **Build Phases** > **Copy Bundle Resources**.
2. Ensure `ggml-metal.metal` or `default.metallib` from the vendor resources is included.

### 11.3 Linker Errors

**Symptom**: `Undefined symbols for architecture arm64` during Xcode build.

```
Undefined symbols for architecture arm64:
  "_whisper_init_from_file_with_params", referenced from: ...
  "_llama_model_load", referenced from: ...
```

**Solutions**:

1. Verify Library Search Paths are correctly set (Section 6.3):

```bash
# Check that the libraries exist at the expected paths
ls -la ~/dev/vaultype/vendor/whisper/lib/
ls -la ~/dev/vaultype/vendor/llama/lib/
```

2. Verify the libraries are linked in Build Phases (Section 6.4).

3. Ensure architectures match:

```bash
# Check the library architecture
lipo -info ~/dev/vaultype/vendor/whisper/lib/libwhisper.a

# If building for arm64 but library is x86_64 only, rebuild with correct architecture
```

**Symptom**: `Duplicate symbol` errors for ggml functions.

```
duplicate symbol '_ggml_init' in:
    vendor/whisper/lib/libggml.a(ggml.c.o)
    vendor/llama/lib/libggml.a(ggml.c.o)
```

**Solution**: Remove one copy of `libggml.a` from the linked libraries. Use only the llama.cpp version (usually newer):

1. In **Build Phases** > **Link Binary With Libraries**, remove `vendor/whisper/lib/libggml.a`.
2. Keep only `vendor/llama/lib/libggml.a` (or whichever is newer).

**Symptom**: `Undefined symbols` for C++ standard library functions.

```
Undefined symbols:
  "std::__1::basic_string<...>", referenced from: ...
```

**Solution**: Add C++ standard library to Other Linker Flags (Section 6.7):

```
OTHER_LDFLAGS = -lstdc++ -lc++
```

### 11.4 Permission Issues

**Symptom**: Microphone not working — no audio captured.

1. Check System Settings > Privacy & Security > Microphone. Ensure VaulType is listed and enabled.
2. If VaulType does not appear, the `NSMicrophoneUsageDescription` key may be missing from `Info.plist` (see Section 8.2).
3. Reset and re-request:

```bash
tccutil reset Microphone com.yourname.vaultype
```

4. Rebuild and relaunch the app.

**Symptom**: Text injection not working — no keystrokes simulated.

1. Check System Settings > Privacy & Security > Accessibility. Ensure VaulType is toggled ON.
2. If you see the app but it is grayed out, the code signature may have changed. Remove and re-add it:

```bash
# Reset accessibility permissions
sudo tccutil reset Accessibility com.yourname.vaultype
```

3. Relaunch VaulType and follow the Accessibility permission prompt.

> ⚠️ **Warning**: During active development, code signature changes with every build. This causes macOS to revoke Accessibility permissions frequently. Consider using `VAULTYPE_MOCK_AUDIO=1` and testing text injection separately. See `../features/PERMISSIONS.md` Section 3.6 for details on code signature invalidation.

**Symptom**: Permission prompts never appear.

```bash
# Check if the app has a valid bundle identifier
defaults read ~/Library/Developer/Xcode/DerivedData/VaulType-*/Build/Products/Debug/VaulType.app/Contents/Info.plist CFBundleIdentifier

# Check TCC database for existing entries
# (This requires Full Disk Access for Terminal or SIP disabled)
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT service, client, auth_value FROM access WHERE client LIKE '%vaultype%';"
```

### 11.5 Code Signing Errors

**Symptom**: `Code signing "VaulType" requires a development team.`

**Solution**: Select a team in Signing & Capabilities:

1. Open the VaulType target settings.
2. Under **Signing & Capabilities**, set **Team** to your Apple ID personal team.
3. If you do not have a team listed, add your Apple ID in Xcode > Settings > Accounts.

**Symptom**: `Provisioning profile doesn't include signing certificate.`

**Solution**: Let Xcode manage signing automatically:

1. Check **"Automatically manage signing"** under Signing & Capabilities.
2. Select your team.
3. If the error persists, try deleting derived data:

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/VaulType-*
```

4. Clean build folder: **Product > Clean Build Folder** (⇧⌘K).

**Symptom**: `The executable was signed with invalid entitlements.`

**Solution**: Verify the entitlements file is correctly referenced:

1. In Build Settings, search for **"Code Signing Entitlements"** (`CODE_SIGN_ENTITLEMENTS`).
2. Ensure it points to the correct `.entitlements` file:

```
CODE_SIGN_ENTITLEMENTS = VaulType/Resources/VaulType.entitlements
```

3. Verify the entitlements file contains valid XML (Section 8.1).

### 11.6 Xcode Build Failures

**Symptom**: `Module 'CWhisper' not found` or `Module 'CLlama' not found`.

**Solutions**:

1. Verify Import Paths include the module map directories (Section 6.5):

```
SWIFT_INCLUDE_PATHS = $(PROJECT_DIR)/vendor/whisper/include $(PROJECT_DIR)/vendor/llama/include
```

2. Verify the `module.modulemap` files exist:

```bash
cat ~/dev/vaultype/vendor/whisper/include/module.modulemap
cat ~/dev/vaultype/vendor/llama/include/module.modulemap
```

3. Clean the build folder and module cache:

```bash
# Clean derived data
rm -rf ~/Library/Developer/Xcode/DerivedData/VaulType-*

# Clean module cache
rm -rf ~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/

# Also accessible via Xcode: Product > Clean Build Folder (⇧⌘K)
```

**Symptom**: SPM dependency resolution failure.

```bash
# Reset SPM package caches
rm -rf ~/dev/vaultype/.build
rm -rf ~/Library/Caches/org.swift.swiftpm

# In Xcode: File > Packages > Reset Package Caches
# Then: File > Packages > Resolve Package Versions
```

**Symptom**: Build succeeds but app crashes immediately on launch.

1. Check the crash log in Xcode's debug console.
2. Common causes:
   - Missing Metal shader files in the app bundle (Section 11.2).
   - Missing or corrupted model files (Section 10.4).
   - Entitlements not applied (Section 8.3).

### 11.7 Runtime Crashes

**Symptom**: `EXC_BAD_ACCESS` in `whisper_init` or `llama_model_load`.

1. The model file may be corrupted or truncated. Re-download it (Section 10.2).
2. Enable Address Sanitizer for debugging:
   - Edit Scheme (⌘<) > Run > Diagnostics > check **Address Sanitizer**.
3. Check available memory:

```bash
# Check available RAM
sysctl -n hw.memsize | awk '{print $0/1024/1024/1024 " GB total"}'
memory_pressure
```

**Symptom**: `Metal device not found` or Metal initialization failure.

1. Verify Metal support:

```bash
system_profiler SPDisplaysDataType | grep -A 5 "Metal"
```

2. On Intel Macs, ensure you have a Metal-compatible GPU. Macs from 2012 onwards support Metal.
3. If running in a VM, Metal is not supported — you must use a physical Mac.

**Symptom**: App launches but freezes during model loading.

1. Check that you are not running multiple copies of VaulType simultaneously.
2. Ensure sufficient free memory (model loading is memory-intensive):

```bash
# Check memory pressure
memory_pressure -l warn
```

3. Use a smaller model during development (Section 10.3).

---

## Related Documentation

| Document | Description |
|---|---|
| [`DEVELOPMENT_GUIDE.md`](DEVELOPMENT_GUIDE.md) | Day-to-day development workflow, coding standards, testing |
| [`../architecture/ARCHITECTURE.md`](../architecture/ARCHITECTURE.md) | System architecture, layer diagram, component breakdown |
| [`../architecture/TECH_STACK.md`](../architecture/TECH_STACK.md) | Technology choices, version matrix, performance analysis |
| [`../features/PERMISSIONS.md`](../features/PERMISSIONS.md) | macOS permission model, TCC framework, permission management |
| [`../features/MODEL_MANAGEMENT.md`](../features/MODEL_MANAGEMENT.md) | Model lifecycle, download manager, Hugging Face integration |
| [`../features/SPEECH_RECOGNITION.md`](../features/SPEECH_RECOGNITION.md) | Whisper integration, audio pipeline, VAD |
| [`../features/LLM_PROCESSING.md`](../features/LLM_PROCESSING.md) | LLM inference, prompt templates, processing modes |
| [`../features/TEXT_INJECTION.md`](../features/TEXT_INJECTION.md) | CGEvent keystroke simulation, clipboard management |
| [`../security/SECURITY.md`](../security/SECURITY.md) | Security model, threat analysis, privacy architecture |
| [`../deployment/SCALING_GUIDE.md`](../deployment/SCALING_GUIDE.md) | Distribution, notarization, Sparkle auto-update |
