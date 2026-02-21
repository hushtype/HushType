Last Updated: 2026-02-20

# CI/CD Pipeline

> GitHub Actions workflows for building, testing, linting, and releasing VaulType.

## Table of Contents

- [Overview](#overview)
- [Workflow Architecture](#workflow-architecture)
- [Build Workflow](#build-workflow)
- [Test Workflow](#test-workflow)
- [Lint Workflow](#lint-workflow)
- [Release Pipeline](#release-pipeline)
- [Code Signing in CI](#code-signing-in-ci)
- [Notarization Automation](#notarization-automation)
- [Sparkle Appcast Update](#sparkle-appcast-update)
- [Homebrew Cask Automation](#homebrew-cask-automation)
- [Secrets Management](#secrets-management)
- [Next Steps](#next-steps)

---

## Overview

VaulType uses GitHub Actions for all CI/CD operations. Since VaulType is a native macOS application, all builds run on macOS runners with Xcode. There are no Docker containers or Linux runners in this project.

```
Push/PR to main ──► Build (Debug + Release) ──► Test ──► Lint

Tag v* ──► Build ──► Sign ──► Notarize ──► DMG ──► GitHub Release
               │
               ├──► Sparkle Appcast Update
               └──► Homebrew Cask PR (planned)
```

### Runners

| Workflow | Runner | Reason |
|----------|--------|--------|
| Build & Test | `macos-15` | Native macOS build, Metal support, Xcode 16.2 |
| Lint | `macos-14` | SwiftLint/SwiftFormat require macOS |
| Release | `macos-15` | Code signing, notarization |

### Library Versions

| Library | Version | Notes |
|---------|---------|-------|
| whisper.cpp | v1.7.4 | Built via `scripts/setup-whisper.sh`, cached in CI |
| llama.cpp | b8059 | Built via `scripts/setup-llama.sh`, cached in CI |
| Xcode | 16.2 | Selected on runner via `xcode-select` |

---

## Workflow Architecture

### File Structure

```
.github/
└── workflows/
    ├── build.yml     # Build Debug + Release on push/PR to main
    ├── test.yml      # Run unit tests on push/PR to main
    └── lint.yml      # SwiftLint + SwiftFormat on Swift file changes
```

---

## Build Workflow

Triggered on every push and pull request to `main`. Builds both Debug and Release configurations in a matrix.

```yaml
# .github/workflows/build.yml
name: Build

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

concurrency:
  group: build-${{ github.ref }}
  cancel-in-progress: true

env:
  WHISPER_TAG: "v1.7.4"
  LLAMA_TAG: "b8059"
  XCODE_VERSION: "16.2"

jobs:
  build:
    name: Build (${{ matrix.configuration }})
    runs-on: macos-15
    strategy:
      matrix:
        configuration: [Debug, Release]

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_${XCODE_VERSION}.app

      - name: Install CMake
        run: |
          if ! command -v cmake &>/dev/null; then
            brew install cmake
          fi

      - name: Cache vendor libraries
        id: vendor-cache
        uses: actions/cache@v4
        with:
          path: |
            vendor/whisper.cpp
            vendor/llama.cpp
            WhisperKit/Sources/CWhisper/include
          key: vendor-${{ env.WHISPER_TAG }}-${{ env.LLAMA_TAG }}-${{ runner.arch }}

      - name: Build whisper.cpp
        if: steps.vendor-cache.outputs.cache-hit != 'true'
        run: ./scripts/setup-whisper.sh

      - name: Build llama.cpp
        if: steps.vendor-cache.outputs.cache-hit != 'true'
        run: ./scripts/setup-llama.sh

      - name: Restore whisper headers (cache hit)
        if: steps.vendor-cache.outputs.cache-hit == 'true'
        run: |
          mkdir -p WhisperKit/Sources/CWhisper/include
          if [ ! -f WhisperKit/Sources/CWhisper/include/whisper.h ]; then
            cp vendor/whisper.cpp/include/whisper.h WhisperKit/Sources/CWhisper/include/
          fi

      - name: Build
        run: |
          xcodebuild build \
            -scheme VaulType \
            -configuration ${{ matrix.configuration }} \
            -destination 'platform=macOS,arch=arm64' \
            -derivedDataPath DerivedData \
            CODE_SIGN_IDENTITY="-" \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGNING_ALLOWED=NO \
            ONLY_ACTIVE_ARCH=YES

      - name: Upload build artifacts
        if: matrix.configuration == 'Release'
        uses: actions/upload-artifact@v4
        with:
          name: VaulType-Release
          path: DerivedData/Build/Products/Release/VaulType.app
          retention-days: 7
```

---

## Test Workflow

Triggered on every push and pull request to `main`.

```yaml
# .github/workflows/test.yml
name: Test

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

concurrency:
  group: test-${{ github.ref }}
  cancel-in-progress: true

env:
  WHISPER_TAG: "v1.7.4"
  LLAMA_TAG: "b8059"
  XCODE_VERSION: "16.2"

jobs:
  test:
    name: Unit Tests
    runs-on: macos-15

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_${XCODE_VERSION}.app

      - name: Install CMake
        run: |
          if ! command -v cmake &>/dev/null; then
            brew install cmake
          fi

      - name: Cache vendor libraries
        id: vendor-cache
        uses: actions/cache@v4
        with:
          path: |
            vendor/whisper.cpp
            vendor/llama.cpp
            WhisperKit/Sources/CWhisper/include
          key: vendor-${{ env.WHISPER_TAG }}-${{ env.LLAMA_TAG }}-${{ runner.arch }}

      - name: Build whisper.cpp
        if: steps.vendor-cache.outputs.cache-hit != 'true'
        run: ./scripts/setup-whisper.sh

      - name: Build llama.cpp
        if: steps.vendor-cache.outputs.cache-hit != 'true'
        run: ./scripts/setup-llama.sh

      - name: Restore whisper headers (cache hit)
        if: steps.vendor-cache.outputs.cache-hit == 'true'
        run: |
          mkdir -p WhisperKit/Sources/CWhisper/include
          if [ ! -f WhisperKit/Sources/CWhisper/include/whisper.h ]; then
            cp vendor/whisper.cpp/include/whisper.h WhisperKit/Sources/CWhisper/include/
          fi

      - name: Run tests
        env:
          CI: "true"
        run: |
          xcodebuild test \
            -scheme VaulType \
            -destination 'platform=macOS,arch=arm64' \
            -derivedDataPath DerivedData \
            -resultBundlePath TestResults.xcresult \
            CODE_SIGN_IDENTITY="-" \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGNING_ALLOWED=NO \
            ONLY_ACTIVE_ARCH=YES

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-results
          path: TestResults.xcresult
          retention-days: 14
```

---

## Lint Workflow

Triggered on pull requests and pushes to `main` when Swift files or SwiftLint config change.

```yaml
# .github/workflows/lint.yml
name: Lint

on:
  pull_request:
    branches: [main]
    paths:
      - '**/*.swift'
      - '.swiftlint.yml'
      - '.github/workflows/lint.yml'
  push:
    branches: [main]
    paths:
      - '**/*.swift'
      - '.swiftlint.yml'

concurrency:
  group: lint-${{ github.ref }}
  cancel-in-progress: true

jobs:
  swiftlint:
    name: SwiftLint
    runs-on: macos-14
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install SwiftLint
        run: brew install swiftlint

      - name: Run SwiftLint
        run: swiftlint lint --strict --reporter github-actions-logging

  swiftformat:
    name: SwiftFormat
    runs-on: macos-14
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install SwiftFormat
        run: brew install swiftformat

      - name: Check formatting
        run: swiftformat --lint . 2>&1 || true
```

---

## Release Pipeline

The release workflow is planned but not yet created (Phase 6 task). When implemented, it will trigger on version tags (`v*`) and produce a signed, notarized DMG via the existing scripts.

### Planned Release Flow

```
Tag v0.x.0
    │
    ▼
Build Release (arm64, macos-15)
    │
    ▼
Code Sign (Developer ID Application)
    │
    ▼
Create DMG (scripts/create-dmg.sh)
    │
    ▼
Notarize (scripts/notarize.sh via xcrun notarytool)
    │
    ▼
Staple ticket to DMG
    │
    ├──► Create GitHub Release (draft)
    ├──► Update Sparkle appcast.xml (scripts/update-appcast.sh)
    └──► Homebrew Cask PR (planned)
```

### Existing Release Scripts

| Script | Purpose |
|--------|---------|
| `scripts/create-dmg.sh` | Creates the DMG installer with drag-to-Applications layout |
| `scripts/notarize.sh` | Submits DMG to Apple notarization and staples the ticket |
| `scripts/update-appcast.sh` | Updates the Sparkle appcast.xml with the new release |

---

## Code Signing in CI

### Certificate Management

For the planned release workflow, code signing uses a Developer ID Application certificate loaded into a temporary keychain:

```bash
# Export from Keychain Access as .p12, then:
base64 -i DeveloperIDApplication.p12 -o cert.b64

# Add cert.b64 contents as GitHub secret: DEVELOPER_ID_CERTIFICATE_BASE64
# Add the .p12 password as: DEVELOPER_ID_CERTIFICATE_PASSWORD
```

The certificate is decoded and imported into a temporary keychain in the CI runner:

```yaml
- name: Install Signing Certificate
  env:
    CERTIFICATE_BASE64: ${{ secrets.DEVELOPER_ID_CERTIFICATE_BASE64 }}
    CERTIFICATE_PASSWORD: ${{ secrets.DEVELOPER_ID_CERTIFICATE_PASSWORD }}
    KEYCHAIN_PASSWORD: ${{ secrets.KEYCHAIN_PASSWORD }}
  run: |
    KEYCHAIN_PATH="$RUNNER_TEMP/signing.keychain-db"
    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
    security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

    CERT_PATH="$RUNNER_TEMP/certificate.p12"
    echo -n "$CERTIFICATE_BASE64" | base64 --decode -o "$CERT_PATH"
    security import "$CERT_PATH" \
      -P "$CERTIFICATE_PASSWORD" \
      -A -t cert -f pkcs12 \
      -k "$KEYCHAIN_PATH"

    security list-keychain -d user -s "$KEYCHAIN_PATH"
```

> The temporary keychain is deleted at the end of the job regardless of success or failure.

---

## Notarization Automation

Notarization uses `xcrun notarytool` with `--wait` to block until Apple's notary service returns a result. The existing `scripts/notarize.sh` wraps this:

```bash
xcrun notarytool submit "VaulType-${VERSION}-universal.dmg" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_PASSWORD" \
    --wait --timeout 30m

xcrun stapler staple "VaulType-${VERSION}-universal.dmg"
```

Notarization typically takes 5-15 minutes. The `--timeout 30m` flag handles slow responses.

---

## Sparkle Appcast Update

VaulType uses Sparkle 2.x with EdDSA (Ed25519) signatures. The `scripts/update-appcast.sh` script inserts a new `<item>` at the top of `appcast.xml` after each release:

```xml
<item>
  <title>Version ${VERSION}</title>
  <pubDate>${DATE}</pubDate>
  <sparkle:version>${BUILD_NUMBER}</sparkle:version>
  <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
  <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
  <enclosure
    url="https://github.com/vaultype/vaultype/releases/download/v${VERSION}/VaulType-${VERSION}-universal.dmg"
    type="application/octet-stream"
    sparkle:edSignature="${SIGNATURE}"
    length="${SIZE}"
  />
</item>
```

`appcast.xml` is hosted on the project website. The Sparkle EdDSA private key is stored as a GitHub secret and never committed.

---

## Homebrew Cask Automation

Homebrew Cask submission is a planned Phase 6 task. When complete, a workflow will auto-submit a PR to `homebrew/homebrew-cask` on each published GitHub Release:

```bash
# Homebrew cask formula (planned)
cask "vaultype" do
  version "0.x.0"
  sha256 "COMPUTED_SHA256"

  url "https://github.com/vaultype/vaultype/releases/download/v#{version}/VaulType-#{version}-universal.dmg"
  name "VaulType"
  desc "Privacy-first, offline speech-to-text for macOS with local AI"
  homepage "https://vaultype.app"

  depends_on macos: ">= :sonoma"

  app "VaulType.app"

  zap trash: [
    "~/Library/Application Support/VaulType",
    "~/Library/Caches/com.vaultype.app",
    "~/Library/Preferences/com.vaultype.app.plist",
  ]
end
```

---

## Secrets Management

### Required GitHub Secrets

| Secret | Description | Used In |
|--------|-------------|---------|
| `DEVELOPER_ID_CERTIFICATE_BASE64` | Base64 Developer ID certificate (.p12) | Release (planned) |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password for .p12 file | Release (planned) |
| `KEYCHAIN_PASSWORD` | Temporary keychain password | Release (planned) |
| `APPLE_ID` | Apple ID email for notarization | Release (planned) |
| `APPLE_TEAM_ID` | Apple Developer Team ID | Release (planned) |
| `APPLE_APP_PASSWORD` | App-specific password for notarization | Release (planned) |
| `SPARKLE_ED_PRIVATE_KEY` | Sparkle EdDSA signing key | Release (planned) |
| `HOMEBREW_GITHUB_TOKEN` | PAT with `public_repo` scope | Homebrew (planned) |

Use GitHub Environments with required reviewers for the `production` environment to protect signing secrets.

---

## Next Steps

- [Deployment Guide](DEPLOYMENT_GUIDE.md) — Manual build and release process
- [Testing](../testing/TESTING.md) — Test strategy and execution
- [Security](../security/SECURITY.md) — Code signing and security practices
