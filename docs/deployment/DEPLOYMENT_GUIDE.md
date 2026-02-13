Last Updated: 2026-02-13

# Deployment Guide

> Building, signing, notarizing, and distributing HushType for macOS.

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

HushType is distributed as a native macOS application through multiple channels:

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

| Channel | Method | Audience |
|---------|--------|----------|
| GitHub Releases | DMG download | Primary distribution |
| Homebrew Cask | `brew install --cask hushtype` | Developer-friendly |
| Sparkle Auto-Update | In-app updater | Existing users |
| Project Website | Direct download | General users |
| Mac App Store | App Store submission | Future (requires sandbox adjustments) |

---

## Build Configuration

### Release Build Settings

Configure these in Xcode's Release build configuration or via `xcodebuild`:

```bash
# Build for Release
xcodebuild \
    -project HushType.xcodeproj \
    -scheme HushType \
    -configuration Release \
    -archivePath build/HushType.xcarchive \
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

### Entitlements

The hardened runtime requires specific entitlements for HushType's features:

```xml
<!-- HushType.entitlements -->
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

> ⚠️ These entitlements are necessary for HushType's local AI features. Each one is documented for Apple's notarization review.

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
    -archivePath build/HushType.xcarchive \
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
codesign --verify --deep --strict --verbose=2 build/export/HushType.app

# Check entitlements
codesign -d --entitlements :- build/export/HushType.app

# Verify Gatekeeper approval
spctl --assess --type execute --verbose build/export/HushType.app
```

> 🔒 **Security Note:** Never commit signing certificates or provisioning profiles to the repository. Use CI/CD secrets for automated signing.

---

## Notarization

Apple notarization ensures the app is scanned for malware and issues a notarization ticket that Gatekeeper trusts.

### Using notarytool

```bash
# Submit for notarization
xcrun notarytool submit build/HushType.dmg \
    --apple-id "your@email.com" \
    --team-id "TEAM_ID" \
    --password "@keychain:AC_PASSWORD" \
    --wait

# Check notarization status
xcrun notarytool info <submission-id> \
    --apple-id "your@email.com" \
    --team-id "TEAM_ID" \
    --password "@keychain:AC_PASSWORD"

# View notarization log (if issues)
xcrun notarytool log <submission-id> \
    --apple-id "your@email.com" \
    --team-id "TEAM_ID" \
    --password "@keychain:AC_PASSWORD"
```

### Stapling the Ticket

After successful notarization, staple the ticket to the app and DMG:

```bash
# Staple to the app bundle
xcrun stapler staple build/export/HushType.app

# Staple to the DMG
xcrun stapler staple build/HushType.dmg

# Verify stapling
xcrun stapler validate build/HushType.dmg
```

### Storing Credentials

Store your App Store Connect password in the Keychain:

```bash
xcrun notarytool store-credentials "AC_PASSWORD" \
    --apple-id "your@email.com" \
    --team-id "TEAM_ID" \
    --password "app-specific-password"
```

> 💡 **Tip:** Use an app-specific password generated at [appleid.apple.com](https://appleid.apple.com). Never use your main Apple ID password.

---

## DMG Creation

### Using create-dmg

```bash
# Install create-dmg
brew install create-dmg

# Create the DMG
create-dmg \
    --volname "HushType" \
    --volicon "assets/dmg-icon.icns" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "HushType.app" 150 190 \
    --hide-extension "HushType.app" \
    --app-drop-link 450 190 \
    --background "assets/dmg-background.png" \
    --no-internet-enable \
    "build/HushType-${VERSION}-universal.dmg" \
    "build/export/HushType.app"
```

### DMG Naming Convention

```
HushType-0.1.0-universal.dmg      # Universal binary (arm64 + x86_64)
HushType-0.1.0-arm64.dmg          # Apple Silicon only (future, if needed)
HushType-0.1.0-x86_64.dmg         # Intel only (future, if needed)
```

### Automated DMG Script

```bash
#!/bin/bash
# scripts/create-dmg.sh

set -euo pipefail

VERSION="${1:?Usage: create-dmg.sh <version>}"
APP_PATH="build/export/HushType.app"
DMG_PATH="build/HushType-${VERSION}-universal.dmg"

echo "Creating DMG for HushType v${VERSION}..."

# Remove old DMG if exists
rm -f "$DMG_PATH"

create-dmg \
    --volname "HushType ${VERSION}" \
    --volicon "assets/dmg-icon.icns" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "HushType.app" 150 190 \
    --hide-extension "HushType.app" \
    --app-drop-link 450 190 \
    --background "assets/dmg-background.png" \
    --no-internet-enable \
    "$DMG_PATH" \
    "$APP_PATH"

echo "DMG created: $DMG_PATH"
echo "Size: $(du -h "$DMG_PATH" | cut -f1)"
```

---

## Universal Binary Packaging

HushType builds as a universal binary supporting both Apple Silicon (arm64) and Intel (x86_64) Macs.

### Building Universal Binary

Xcode handles this automatically when `ARCHS` is set to `arm64 x86_64`. For manual builds:

```bash
# Build for Apple Silicon
xcodebuild -scheme HushType -configuration Release \
    -arch arm64 \
    -derivedDataPath build/arm64

# Build for Intel
xcodebuild -scheme HushType -configuration Release \
    -arch x86_64 \
    -derivedDataPath build/x86_64

# Create universal binary with lipo
lipo -create \
    build/arm64/Build/Products/Release/HushType.app/Contents/MacOS/HushType \
    build/x86_64/Build/Products/Release/HushType.app/Contents/MacOS/HushType \
    -output build/universal/HushType
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

HushType uses [Sparkle](https://sparkle-project.org/) for in-app auto-updates.

### Integration

```swift
// HushType/App/AppDelegate.swift

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
    <title>HushType Updates</title>
    <language>en</language>
    <item>
      <title>Version 0.1.0</title>
      <pubDate>Mon, 13 Feb 2026 12:00:00 +0000</pubDate>
      <sparkle:version>1</sparkle:version>
      <sparkle:shortVersionString>0.1.0</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
        <h2>HushType 0.1.0 — Initial Release</h2>
        <ul>
          <li>Menu bar app with global hotkey dictation</li>
          <li>Local speech recognition via whisper.cpp</li>
          <li>Universal text injection into any app</li>
          <li>Model management and download</li>
        </ul>
      ]]></description>
      <enclosure
        url="https://github.com/hushtype/hushtype/releases/download/v0.1.0/HushType-0.1.0-universal.dmg"
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
./bin/sign_update build/HushType-0.1.0-universal.dmg

# Output: sparkle:edSignature="..." length="..."
```

> 🔒 **Security Note:** Store the Sparkle EdDSA private key securely. Add it as a CI/CD secret, never commit it.

### Info.plist Configuration

```xml
<!-- Info.plist -->
<key>SUFeedURL</key>
<string>https://hushtype.app/appcast.xml</string>
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

echo "=== HushType Release ${TAG} ==="

# 1. Build
echo "Building..."
xcodebuild -project HushType.xcodeproj \
    -scheme HushType \
    -configuration Release \
    -archivePath "build/HushType.xcarchive" \
    archive

# 2. Export
echo "Exporting..."
xcodebuild -exportArchive \
    -archivePath "build/HushType.xcarchive" \
    -exportOptionsPlist ExportOptions.plist \
    -exportPath "build/export"

# 3. Create DMG
echo "Creating DMG..."
./scripts/create-dmg.sh "$VERSION"

# 4. Notarize
echo "Notarizing..."
xcrun notarytool submit "build/HushType-${VERSION}-universal.dmg" \
    --keychain-profile "AC_PASSWORD" \
    --wait

# 5. Staple
echo "Stapling..."
xcrun stapler staple "build/HushType-${VERSION}-universal.dmg"

# 6. Create GitHub Release
echo "Creating GitHub Release..."
gh release create "$TAG" \
    "build/HushType-${VERSION}-universal.dmg" \
    --title "HushType ${TAG}" \
    --notes-file "release-notes/${VERSION}.md" \
    --draft

echo "=== Release ${TAG} created as draft ==="
echo "Review at: https://github.com/hushtype/hushtype/releases"
```

### GitHub Release Notes Template

```markdown
<!-- release-notes/0.1.0.md -->
## HushType v0.1.0 — MVP Release

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
- **Homebrew:** `brew install --cask hushtype`
- **DMG:** Download from the link below

### Checksums
```
SHA256: <checksum> HushType-0.1.0-universal.dmg
```
```

---

## Homebrew Cask

### Creating the Cask Formula

```ruby
# Casks/hushtype.rb

cask "hushtype" do
  version "0.1.0"
  sha256 "COMPUTED_SHA256_HASH"

  url "https://github.com/hushtype/hushtype/releases/download/v#{version}/HushType-#{version}-universal.dmg"
  name "HushType"
  desc "Privacy-first, offline speech-to-text for macOS with local AI"
  homepage "https://hushtype.app"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "HushType.app"

  zap trash: [
    "~/Library/Application Support/HushType",
    "~/Library/Caches/com.hushtype.app",
    "~/Library/Preferences/com.hushtype.app.plist",
    "~/Library/Saved Application State/com.hushtype.app.savedState",
  ]
end
```

### Submitting to Homebrew

```bash
# Fork homebrew-cask, create a branch, add the cask
brew tap homebrew/cask
cd "$(brew --repository homebrew/cask)"

# Create/update the formula
cp /path/to/hushtype.rb Casks/h/hushtype.rb

# Test locally
brew audit --cask hushtype
brew install --cask hushtype

# Submit PR to homebrew/homebrew-cask
```

### Automated Cask Updates

Include in CI/CD to auto-submit Homebrew Cask PR on each release:

```bash
# scripts/update-homebrew.sh
VERSION="${1}"
SHA256=$(shasum -a 256 "build/HushType-${VERSION}-universal.dmg" | awk '{print $1}')

# Update the cask formula
sed -i '' "s/version \".*\"/version \"${VERSION}\"/" Casks/hushtype.rb
sed -i '' "s/sha256 \".*\"/sha256 \"${SHA256}\"/" Casks/hushtype.rb
```

---

## Release Checklist

Use this checklist before every release:

### Pre-Release

- [ ] All tests pass (`xcodebuild test -scheme HushType`)
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
- [Scaling Guide](SCALING_GUIDE.md) — Performance and model scaling
- [Security](../security/SECURITY.md) — Security practices and hardened runtime
- [Monitoring & Logging](../operations/MONITORING_LOGGING.md) — Diagnostics in production
