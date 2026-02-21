Last Updated: 2026-02-20

# Deployment Guide

> Building, signing, notarizing, and distributing VaulType for macOS.

## Table of Contents

- [Overview](#overview)
- [Build Configuration](#build-configuration)
- [Code Signing](#code-signing)
- [Notarization](#notarization)
- [DMG Creation](#dmg-creation)
- [Universal Binary Packaging](#universal-binary-packaging)
- [Sparkle Auto-Update](#sparkle-auto-update)
- [GitHub Release Automation](#github-release-automation)
- [Homebrew Cask](#homebrew-cask)
- [Release Checklist](#release-checklist)
- [Next Steps](#next-steps)

---

## Overview

VaulType is distributed as a native macOS application through multiple channels:

```
┌─────────────────────────────────────────────────────────┐
│                    Release Pipeline                      │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  Tag v0.x.0                                              │
│      │                                                   │
│      ▼                                                   │
│  Build Universal Binary (arm64 + x86_64)                │
│      │                                                   │
│      ▼                                                   │
│  Code Sign (Developer ID Application)                    │
│      │                                                   │
│      ▼                                                   │
│  Notarize (Apple notarytool)                             │
│      │                                                   │
│      ▼                                                   │
│  Staple Notarization Ticket                              │
│      │                                                   │
│      ├──► Create DMG ──► GitHub Release                  │
│      ├──► Update Sparkle appcast.xml                     │
│      └──► Update Homebrew Cask formula                   │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### Distribution Channels

| Channel | Method | Status |
|---------|--------|--------|
| GitHub Releases | Signed, notarized DMG | Active (Phase 6) |
| Sparkle Auto-Update | In-app updater with EdDSA signatures | Integrated (Sparkle 2.x) |
| Homebrew Cask | `brew install --cask vaultype` | Planned |
| Mac App Store | App Store submission | Future (requires sandbox adjustments) |

---

## Build Configuration

### Release Build Settings

Configure these in Xcode's Release build configuration or via `xcodebuild`:

```bash
# Build for Release
xcodebuild \
    -project VaulType.xcodeproj \
    -scheme VaulType \
    -configuration Release \
    -archivePath build/VaulType.xcarchive \
    archive
```

### Key Build Settings

| Setting | Value | Notes |
|---------|-------|-------|
| `SWIFT_OPTIMIZATION_LEVEL` | `-O` (Release) | Full optimization |
| `DEPLOYMENT_TARGET` | `14.0` | macOS Sonoma minimum |
| `ARCHS` | `arm64 x86_64` | Universal binary |
| `ENABLE_HARDENED_RUNTIME` | `YES` | Required for notarization |
| `CODE_SIGN_INJECT_BASE_ENTITLEMENTS` | `YES` | Inject entitlements |
| `STRIP_INSTALLED_PRODUCT` | `YES` | Strip debug symbols |
| `COPY_PHASE_STRIP` | `YES` | Strip in copy phase |
| `ENABLE_BITCODE` | `NO` | Not supported on macOS |

### C Dependency Versions

| Library | Version | Build Script |
|---------|---------|--------------|
| whisper.cpp | v1.7.4 | `scripts/setup-whisper.sh` |
| llama.cpp | b8059 | `scripts/setup-llama.sh` |

Both are built with Metal GPU acceleration (`GGML_METAL_EMBED_LIBRARY=ON`) and linked as static libraries.

### Entitlements

The hardened runtime requires specific entitlements for VaulType's features:

```xml
<!-- VaulType.entitlements -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <!-- Required for whisper.cpp and llama.cpp Metal acceleration -->
    <key>com.apple.security.device.gpu</key>
    <true/>

    <!-- Required for microphone audio capture -->
    <key>com.apple.security.device.audio-input</key>
    <true/>

    <!-- Required for CGEvent text injection -->
    <key>com.apple.security.automation.apple-events</key>
    <true/>

    <!-- Required for loading whisper.cpp/llama.cpp dylibs -->
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>

    <!-- Required for JIT in llama.cpp (some model formats) -->
    <key>com.apple.security.cs.allow-jit</key>
    <true/>

    <!-- Required for Metal GPU acceleration -->
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
</dict>
</plist>
```

> ⚠️ These entitlements are necessary for VaulType's local AI features. Each one is documented for Apple's notarization review.

---

## Code Signing

### Prerequisites

1. **Apple Developer Program** membership ($99/year)
2. **Developer ID Application** certificate (for distribution outside App Store)
3. **Developer ID Installer** certificate (optional, for PKG distribution)

### Certificate Setup

```bash
# List available signing identities
security find-identity -v -p codesigning

# Expected output:
# 1) ABC123... "Developer ID Application: Your Name (TEAM_ID)"
# 2) DEF456... "Developer ID Installer: Your Name (TEAM_ID)"
```

### Signing the App

```bash
# Export the archive with code signing
xcodebuild \
    -exportArchive \
    -archivePath build/VaulType.xcarchive \
    -exportOptionsPlist ExportOptions.plist \
    -exportPath build/export
```

**ExportOptions.plist:**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>YOUR_TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
```

### Verifying the Signature

```bash
# Verify code signature
codesign --verify --deep --strict --verbose=2 build/export/VaulType.app

# Check entitlements
codesign -d --entitlements :- build/export/VaulType.app

# Verify Gatekeeper approval
spctl --assess --type execute --verbose build/export/VaulType.app
```

> 🔒 **Security Note:** Never commit signing certificates or provisioning profiles to the repository. Use CI/CD secrets for automated signing.

---

## Notarization

Apple notarization ensures the app is scanned for malware and issues a notarization ticket that Gatekeeper trusts.

### Using notarize.sh

The `scripts/notarize.sh` script is included in the repository and handles submission and stapling:

```bash
./scripts/notarize.sh <path-to-dmg>
# Example: ./scripts/notarize.sh build/VaulType-0.5.0-universal.dmg
```

It requires `APPLE_ID`, `APPLE_TEAM_ID`, and `APPLE_APP_PASSWORD` to be set (either as environment variables or in a local `.env` file — never committed). Internally it uses:

```bash
xcrun notarytool submit "$DMG" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --wait --timeout 30m

xcrun stapler staple "$DMG"
```

### Storing Credentials

Store your App Store Connect app-specific password in the Keychain:

```bash
xcrun notarytool store-credentials "AC_PASSWORD" \
    --apple-id "your@email.com" \
    --team-id "TEAM_ID" \
    --password "app-specific-password"
```

> Use an app-specific password generated at [appleid.apple.com](https://appleid.apple.com). Never use your main Apple ID password.

---

## DMG Creation

### Using create-dmg

```bash
# Install create-dmg
brew install create-dmg

# Create the DMG
create-dmg \
    --volname "VaulType" \
    --volicon "assets/dmg-icon.icns" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "VaulType.app" 150 190 \
    --hide-extension "VaulType.app" \
    --app-drop-link 450 190 \
    --background "assets/dmg-background.png" \
    --no-internet-enable \
    "build/VaulType-${VERSION}-universal.dmg" \
    "build/export/VaulType.app"
```

### DMG Naming Convention

```
VaulType-0.1.0-universal.dmg      # Universal binary (arm64 + x86_64)
VaulType-0.1.0-arm64.dmg          # Apple Silicon only (future, if needed)
VaulType-0.1.0-x86_64.dmg         # Intel only (future, if needed)
```

### Automated DMG Script

The `scripts/create-dmg.sh` script is included in the repository. Run it with:

```bash
./scripts/create-dmg.sh <version>
# Example: ./scripts/create-dmg.sh 0.5.0
```

The script uses `create-dmg` (install with `brew install create-dmg`) to produce:

```
build/VaulType-<version>-universal.dmg
```

---

## Universal Binary Packaging

VaulType builds as a universal binary supporting both Apple Silicon (arm64) and Intel (x86_64) Macs.

### Building Universal Binary

Xcode handles this automatically when `ARCHS` is set to `arm64 x86_64`. For manual builds:

```bash
# Build for Apple Silicon
xcodebuild -scheme VaulType -configuration Release \
    -arch arm64 \
    -derivedDataPath build/arm64

# Build for Intel
xcodebuild -scheme VaulType -configuration Release \
    -arch x86_64 \
    -derivedDataPath build/x86_64

# Create universal binary with lipo
lipo -create \
    build/arm64/Build/Products/Release/VaulType.app/Contents/MacOS/VaulType \
    build/x86_64/Build/Products/Release/VaulType.app/Contents/MacOS/VaulType \
    -output build/universal/VaulType
```

### C Library Universal Builds

whisper.cpp and llama.cpp must also be built as universal libraries:

```bash
# scripts/build-deps.sh (excerpt)

# Build whisper.cpp for arm64
cmake -B build-whisper-arm64 -S vendor/whisper.cpp \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DWHISPER_METAL=ON \
    -DCMAKE_BUILD_TYPE=Release
cmake --build build-whisper-arm64

# Build whisper.cpp for x86_64
cmake -B build-whisper-x86_64 -S vendor/whisper.cpp \
    -DCMAKE_OSX_ARCHITECTURES=x86_64 \
    -DWHISPER_METAL=OFF \
    -DCMAKE_BUILD_TYPE=Release
cmake --build build-whisper-x86_64

# Merge into universal static library
lipo -create \
    build-whisper-arm64/libwhisper.a \
    build-whisper-x86_64/libwhisper.a \
    -output lib/libwhisper-universal.a
```

> 🍎 **Note:** Metal acceleration is only available on Apple Silicon. Intel builds fall back to CPU-only inference.

---

## Sparkle Auto-Update

VaulType uses [Sparkle](https://sparkle-project.org/) for in-app auto-updates.

### Integration

```swift
// VaulType/App/AppDelegate.swift

import Sparkle

class AppDelegate: NSObject, NSApplicationDelegate {
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Sparkle automatically checks for updates on launch
    }
}
```

### Appcast Configuration

Host an `appcast.xml` file that Sparkle checks for updates:

```xml
<!-- appcast.xml -->
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>VaulType Updates</title>
    <language>en</language>
    <item>
      <title>Version 0.1.0</title>
      <pubDate>Mon, 13 Feb 2026 12:00:00 +0000</pubDate>
      <sparkle:version>1</sparkle:version>
      <sparkle:shortVersionString>0.1.0</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
        <h2>VaulType 0.1.0 — Initial Release</h2>
        <ul>
          <li>Menu bar app with global hotkey dictation</li>
          <li>Local speech recognition via whisper.cpp</li>
          <li>Universal text injection into any app</li>
          <li>Model management and download</li>
        </ul>
      ]]></description>
      <enclosure
        url="https://github.com/vaultype/vaultype/releases/download/v0.1.0/VaulType-0.1.0-universal.dmg"
        type="application/octet-stream"
        sparkle:edSignature="BASE64_ED_SIGNATURE"
        length="45678900"
      />
    </item>
  </channel>
</rss>
```

### Generating EdDSA Signatures

Sparkle 2 uses EdDSA (Ed25519) signatures:

```bash
# Generate a signing key (one-time setup)
./bin/generate_keys

# Sign a DMG
./bin/sign_update build/VaulType-0.1.0-universal.dmg

# Output: sparkle:edSignature="..." length="..."
```

> 🔒 **Security Note:** Store the Sparkle EdDSA private key securely. Add it as a CI/CD secret, never commit it.

### Info.plist Configuration

```xml
<!-- Info.plist -->
<key>SUFeedURL</key>
<string>https://vaultype.app/appcast.xml</string>
<key>SUPublicEDKey</key>
<string>YOUR_ED25519_PUBLIC_KEY</string>
<key>SUEnableAutomaticChecks</key>
<true/>
```

---

## GitHub Release Automation

### Release Script

```bash
#!/bin/bash
# scripts/release.sh

set -euo pipefail

VERSION="${1:?Usage: release.sh <version>}"
TAG="v${VERSION}"

echo "=== VaulType Release ${TAG} ==="

# 1. Build
echo "Building..."
xcodebuild -project VaulType.xcodeproj \
    -scheme VaulType \
    -configuration Release \
    -archivePath "build/VaulType.xcarchive" \
    archive

# 2. Export
echo "Exporting..."
xcodebuild -exportArchive \
    -archivePath "build/VaulType.xcarchive" \
    -exportOptionsPlist ExportOptions.plist \
    -exportPath "build/export"

# 3. Create DMG
echo "Creating DMG..."
./scripts/create-dmg.sh "$VERSION"

# 4. Notarize
echo "Notarizing..."
xcrun notarytool submit "build/VaulType-${VERSION}-universal.dmg" \
    --keychain-profile "AC_PASSWORD" \
    --wait

# 5. Staple
echo "Stapling..."
xcrun stapler staple "build/VaulType-${VERSION}-universal.dmg"

# 6. Create GitHub Release
echo "Creating GitHub Release..."
gh release create "$TAG" \
    "build/VaulType-${VERSION}-universal.dmg" \
    --title "VaulType ${TAG}" \
    --notes-file "release-notes/${VERSION}.md" \
    --draft

echo "=== Release ${TAG} created as draft ==="
echo "Review at: https://github.com/vaultype/vaultype/releases"
```

### GitHub Release Notes Template

```markdown
<!-- release-notes/0.1.0.md -->
## VaulType v0.1.0 — MVP Release

### What's New
- Menu bar app with status indicator
- Global hotkey dictation (push-to-talk and toggle modes)
- Local speech recognition via whisper.cpp with Metal acceleration
- Universal text injection into any macOS app
- Model downloader with support for Whisper tiny through large-v3
- Settings window for audio, models, and preferences
- 90+ language support

### System Requirements
- macOS 14.0 (Sonoma) or later
- Apple Silicon recommended (Intel supported)
- 8GB RAM minimum (16GB recommended)
- 2GB free disk space for models

### Installation
- **Homebrew:** `brew install --cask vaultype`
- **DMG:** Download from the link below

### Checksums
```
SHA256: <checksum> VaulType-0.1.0-universal.dmg
```
```

---

## Homebrew Cask

### Creating the Cask Formula

```ruby
# Casks/vaultype.rb

cask "vaultype" do
  version "0.1.0"
  sha256 "COMPUTED_SHA256_HASH"

  url "https://github.com/vaultype/vaultype/releases/download/v#{version}/VaulType-#{version}-universal.dmg"
  name "VaulType"
  desc "Privacy-first, offline speech-to-text for macOS with local AI"
  homepage "https://vaultype.app"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "VaulType.app"

  zap trash: [
    "~/Library/Application Support/VaulType",
    "~/Library/Caches/com.vaultype.app",
    "~/Library/Preferences/com.vaultype.app.plist",
    "~/Library/Saved Application State/com.vaultype.app.savedState",
  ]
end
```

### Submitting to Homebrew

```bash
# Fork homebrew-cask, create a branch, add the cask
brew tap homebrew/cask
cd "$(brew --repository homebrew/cask)"

# Create/update the formula
cp /path/to/vaultype.rb Casks/h/vaultype.rb

# Test locally
brew audit --cask vaultype
brew install --cask vaultype

# Submit PR to homebrew/homebrew-cask
```

### Automated Cask Updates

Include in CI/CD to auto-submit Homebrew Cask PR on each release:

```bash
# scripts/update-homebrew.sh
VERSION="${1}"
SHA256=$(shasum -a 256 "build/VaulType-${VERSION}-universal.dmg" | awk '{print $1}')

# Update the cask formula
sed -i '' "s/version \".*\"/version \"${VERSION}\"/" Casks/vaultype.rb
sed -i '' "s/sha256 \".*\"/sha256 \"${SHA256}\"/" Casks/vaultype.rb
```

---

## Release Checklist

Use this checklist before every release:

### Pre-Release

- [ ] All tests pass (`xcodebuild test -scheme VaulType`)
- [ ] No critical bugs in issue tracker
- [ ] CHANGELOG.md updated with release notes
- [ ] Version number bumped in Xcode (CFBundleShortVersionString + CFBundleVersion)
- [ ] README.md updated if features changed
- [ ] Release notes written in `release-notes/X.Y.Z.md`

### Build & Sign

- [ ] Archive builds successfully for Release configuration
- [ ] Universal binary contains both arm64 and x86_64 (`lipo -info`)
- [ ] Code signature is valid (`codesign --verify --deep --strict`)
- [ ] Entitlements are correct (`codesign -d --entitlements :-`)
- [ ] DMG created and opens correctly
- [ ] Notarization succeeds
- [ ] Ticket stapled to DMG

### Test Release

- [ ] Fresh install from DMG works on Apple Silicon Mac
- [ ] Fresh install from DMG works on Intel Mac (if available)
- [ ] Accessibility permission prompt appears
- [ ] Microphone permission prompt appears
- [ ] Model download works
- [ ] Dictation works end-to-end
- [ ] Auto-update from previous version works (Sparkle)

### Publish

- [ ] GitHub Release created (initially as draft, then published)
- [ ] Sparkle appcast.xml updated and deployed
- [ ] Homebrew Cask formula PR submitted
- [ ] Project website updated
- [ ] Announcement posted (if applicable)

---

## Next Steps

- [CI/CD](CI_CD.md) — GitHub Actions pipeline configuration
- [Security](../security/SECURITY.md) — Security practices and hardened runtime
- [Monitoring & Logging](../operations/MONITORING_LOGGING.md) — Diagnostics in production
