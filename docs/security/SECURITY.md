Last Updated: 2026-02-13

# HushType Security Documentation

> **HushType** — Privacy-first, macOS-native speech-to-text. Your voice stays on your device. Always.

---

## Table of Contents

- [1. Security Philosophy](#1-security-philosophy)
  - [1.1 Privacy-First Architecture](#11-privacy-first-architecture)
  - [1.2 Zero-Trust-Cloud Model](#12-zero-trust-cloud-model)
  - [1.3 Defense in Depth](#13-defense-in-depth)
- [2. Network Security](#2-network-security)
  - [2.1 Core Functionality: Zero Network](#21-core-functionality-zero-network)
  - [2.2 Network Endpoint Inventory](#22-network-endpoint-inventory)
  - [2.3 Network Monitoring & Verification](#23-network-monitoring--verification)
  - [2.4 Certificate Pinning](#24-certificate-pinning)
- [3. Audio Data Security](#3-audio-data-security)
  - [3.1 Audio Capture Pipeline](#31-audio-capture-pipeline)
  - [3.2 Memory Handling](#32-memory-handling)
  - [3.3 Audio Data Lifecycle](#33-audio-data-lifecycle)
- [4. Data at Rest](#4-data-at-rest)
  - [4.1 SwiftData Database](#41-swiftdata-database)
  - [4.2 Keychain Usage](#42-keychain-usage)
  - [4.3 Temporary Files](#43-temporary-files)
  - [4.4 Model Files](#44-model-files)
- [5. Text Injection Security](#5-text-injection-security)
  - [5.1 CGEvent Text Injection](#51-cgevent-text-injection)
  - [5.2 Clipboard Operations](#52-clipboard-operations)
  - [5.3 Known Risks & Mitigations](#53-known-risks--mitigations)
- [6. macOS Permissions & Entitlements](#6-macos-permissions--entitlements)
  - [6.1 Required Permissions](#61-required-permissions)
  - [6.2 Entitlements Breakdown](#62-entitlements-breakdown)
  - [6.3 Principle of Least Privilege](#63-principle-of-least-privilege)
- [7. Code Signing & Notarization](#7-code-signing--notarization)
  - [7.1 Developer ID Signing](#71-developer-id-signing)
  - [7.2 Notarization](#72-notarization)
  - [7.3 Hardened Runtime](#73-hardened-runtime)
- [8. Third-Party Dependency Audit](#8-third-party-dependency-audit)
  - [8.1 Dependency Inventory](#81-dependency-inventory)
  - [8.2 Supply Chain Security](#82-supply-chain-security)
  - [8.3 Update Policy](#83-update-policy)
- [9. Sandboxing Analysis](#9-sandboxing-analysis)
  - [9.1 App Sandbox Limitations](#91-app-sandbox-limitations)
  - [9.2 Distribution Tradeoffs](#92-distribution-tradeoffs)
  - [9.3 Compensating Controls](#93-compensating-controls)
- [10. Threat Model](#10-threat-model)
  - [10.1 Threat Matrix](#101-threat-matrix)
  - [10.2 Attack Surface Analysis](#102-attack-surface-analysis)
  - [10.3 Out-of-Scope Threats](#103-out-of-scope-threats)
- [11. Security Hardening Checklist](#11-security-hardening-checklist)
  - [11.1 Build & Release Checklist](#111-build--release-checklist)
  - [11.2 Code Review Checklist](#112-code-review-checklist)
  - [11.3 Runtime Checklist](#113-runtime-checklist)
- [12. Responsible Disclosure Policy](#12-responsible-disclosure-policy)
  - [12.1 Reporting a Vulnerability](#121-reporting-a-vulnerability)
  - [12.2 Response Timeline](#122-response-timeline)
  - [12.3 Safe Harbor](#123-safe-harbor)
- [13. Security Best Practices for Users](#13-security-best-practices-for-users)
  - [13.1 System-Level Recommendations](#131-system-level-recommendations)
  - [13.2 HushType-Specific Recommendations](#132-hushtype-specific-recommendations)
  - [13.3 Verifying Installation Integrity](#133-verifying-installation-integrity)
- [Related Documentation](#related-documentation)

---

## 1. Security Philosophy

### 1.1 Privacy-First Architecture

HushType is designed from the ground up with a single, unwavering principle: **your voice data never leaves your device**. Every architectural decision flows from this commitment.

The core speech-to-text pipeline operates entirely on-device using [whisper.cpp](https://github.com/ggerganov/whisper.cpp) for speech recognition and [llama.cpp](https://github.com/ggerganov/llama.cpp) for optional LLM post-processing. Both engines leverage Apple Metal for GPU acceleration and require zero network connectivity.

> 🔒 **Security**: HushType can function with all network interfaces disabled. Core STT functionality requires only microphone access and a local ML model — nothing else.

```
┌─────────────────────────────────────────────────────────┐
│                    HushType Process                      │
│                                                         │
│  Microphone ──► AVAudioEngine ──► whisper.cpp (Metal)   │
│                    (memory)          │                   │
│                                      ▼                  │
│                              llama.cpp (Metal)          │
│                                      │                  │
│                                      ▼                  │
│                              CGEvent / Paste            │
│                                      │                  │
│                                      ▼                  │
│                              Target Application         │
│                                                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │  NO network calls · NO cloud APIs · NO telemetry │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

### 1.2 Zero-Trust-Cloud Model

HushType adopts a zero-trust approach toward cloud services:

- **No cloud STT APIs**: Unlike Whisper API, Google Speech-to-Text, or Azure Cognitive Services, HushType never transmits audio to external servers.
- **No analytics or telemetry**: No usage data, no crash reports (unless explicitly opted in by the user), no feature flags fetched from remote servers.
- **No account system**: HushType does not require user registration, authentication tokens, or any form of identity.
- **No remote configuration**: All settings are stored locally. The app never fetches configuration from a remote server.

> ℹ️ **Info**: The only network activity that can occur is explicitly user-initiated (model downloads, update checks, optional crash reporting). See [Section 2: Network Security](#2-network-security) for the complete inventory.

### 1.3 Defense in Depth

HushType employs multiple layers of security:

| Layer | Mechanism |
|-------|-----------|
| **Architecture** | Local-only processing, no cloud dependencies |
| **Memory** | Audio buffers zeroed after processing, no persistent audio storage by default |
| **Storage** | macOS FileVault encryption, Keychain for secrets, app container isolation |
| **Code** | Hardened runtime, code signing, notarization |
| **Dependencies** | Pinned versions, source audits, minimal dependency surface |
| **Permissions** | Principle of least privilege, only requested permissions are used |
| **User Control** | Granular opt-in for any network feature, full transparency |

---

## 2. Network Security

### 2.1 Core Functionality: Zero Network

HushType's core speech-to-text pipeline makes **zero network requests**. The following features operate entirely offline:

- Audio capture and processing
- Speech-to-text transcription (whisper.cpp)
- LLM post-processing (llama.cpp)
- Text injection via Accessibility API
- Clipboard-based paste operations
- Voice command execution
- All user settings and preferences

> ✅ **Do**: Verify HushType's offline capability by disabling all network interfaces. Core STT functionality will continue to work without interruption.

### 2.2 Network Endpoint Inventory

The following table is a **complete and exhaustive** list of all network endpoints HushType may contact. Any network activity not listed here is a bug and should be reported immediately.

| Endpoint | Purpose | When Contacted | User Control | Protocol |
|----------|---------|----------------|--------------|----------|
| `huggingface.co` | ML model downloads | User-initiated only (clicking "Download Model") | Fully opt-in; never automatic | HTTPS (TLS 1.2+) |
| `cdn-lfs.huggingface.co` | ML model file CDN | During model downloads (redirected from huggingface.co) | Fully opt-in; part of model download flow | HTTPS (TLS 1.2+) |
| `sparkle-project.org` / custom feed URL | Sparkle update checks | Configurable: automatic, manual, or disabled | Settings > Updates > Check Frequency | HTTPS (TLS 1.2+) |
| `*.ingest.sentry.io` | Crash reporting | Only if user explicitly enables crash reporting | Settings > Privacy > Send Crash Reports (default: **OFF**) | HTTPS (TLS 1.2+) |

> ⚠️ **Warning**: If you observe any network requests to endpoints not listed in this table, this is a potential security issue. Please report it immediately via our [Responsible Disclosure Policy](#12-responsible-disclosure-policy).

### 2.3 Network Monitoring & Verification

Users and auditors can verify HushType's network behavior:

```bash
# Monitor all HushType network connections in real-time
sudo lsof -i -n -P | grep HushType

# Use Little Snitch, LuLu, or similar tools
# to verify no unexpected outbound connections

# Use tcpdump to capture all HushType traffic on a specific interface
sudo tcpdump -i en0 -n proc HushType

# Verify with nettop
nettop -p $(pgrep HushType) -J bytes_in,bytes_out
```

> 💡 **Tip**: For maximum assurance, use a network-level firewall like [LuLu](https://objective-see.org/products/lulu.html) (free, open source) to block all HushType network access. Core functionality will remain fully operational.

### 2.4 Certificate Pinning

For the limited network operations that do occur:

- **Sparkle updates**: Sparkle uses EdDSA (Ed25519) signature verification for update packages. The public key is embedded in the app at build time. Even if a TLS connection were compromised, unsigned or incorrectly signed updates would be rejected.
- **Model downloads**: Downloads from Hugging Face are verified via SHA-256 checksums published in model repository metadata. Checksums are compared after download.
- **Sentry (opt-in)**: Uses the official Sentry SDK with default TLS certificate validation.

```swift
// Example: Model download integrity verification
func verifyModelIntegrity(at path: URL, expectedSHA256: String) throws -> Bool {
    let fileData = try Data(contentsOf: path)
    let digest = SHA256.hash(data: fileData)
    let hashString = digest.compactMap { String(format: "%02x", $0) }.joined()

    guard hashString == expectedSHA256 else {
        try FileManager.default.removeItem(at: path)
        throw ModelError.integrityCheckFailed(
            expected: expectedSHA256,
            actual: hashString
        )
    }
    return true
}
```

---

## 3. Audio Data Security

### 3.1 Audio Capture Pipeline

Audio is captured using Apple's `AVAudioEngine` framework and processed in-memory with strict lifecycle controls:

```swift
// Audio capture configuration — minimal buffer, mono channel, 16kHz for whisper.cpp
let inputFormat = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: 16000.0,
    channels: 1,
    interleaved: false
)

audioEngine.inputNode.installTap(
    onBus: 0,
    bufferSize: 4096,  // ~256ms of audio per buffer
    format: inputFormat
) { [weak self] buffer, time in
    // Buffer is processed in-memory only
    self?.processAudioBuffer(buffer)
    // Buffer is released by ARC — no disk writes
}
```

> 🔒 **Security**: Audio data exists only as transient `AVAudioPCMBuffer` objects in process memory. These buffers are consumed by whisper.cpp inference and immediately discarded. At no point in the default pipeline is audio data written to the filesystem.

### 3.2 Memory Handling

HushType implements explicit memory hygiene for audio data:

```swift
/// Securely clears audio buffer contents after processing
func securelyReleaseAudioBuffer(_ buffer: AVAudioPCMBuffer) {
    guard let channelData = buffer.floatChannelData else { return }
    let frameCount = Int(buffer.frameLength)

    for channel in 0..<Int(buffer.format.channelCount) {
        // Zero the audio samples to prevent memory forensics recovery
        memset_s(
            channelData[channel],
            frameCount * MemoryLayout<Float>.stride,
            0,
            frameCount * MemoryLayout<Float>.stride
        )
    }
}
```

Key memory security properties:

- **Buffer zeroing**: Audio sample buffers are explicitly zeroed with `memset_s` (which cannot be optimized away by the compiler) after whisper.cpp processing completes.
- **No swap protection**: macOS may swap process memory to disk. We mitigate this by relying on FileVault full-disk encryption (see [Section 4](#4-data-at-rest)) and by processing audio in small, short-lived buffers.
- **No memory mapping of audio**: Audio data is never memory-mapped from files; it exists only as heap-allocated buffers.

> ⚠️ **Warning**: If the user enables **transcription history**, the resulting text (not audio) is stored in the SwiftData database. Audio is never persisted, even when history is enabled.

### 3.3 Audio Data Lifecycle

```
Microphone Hardware
       │
       ▼
 AVAudioEngine Tap (in-memory buffer, ~256ms)
       │
       ▼
 whisper.cpp Inference (Metal GPU / CPU)
       │
       ├──► Text output ──► [Optional: SwiftData history]
       │                           ──► Text injection to target app
       │
       ▼
 Buffer zeroed via memset_s()
       │
       ▼
 Buffer deallocated (ARC)
```

| Stage | Data Form | Duration | Persisted? |
|-------|-----------|----------|------------|
| Capture | PCM Float32 samples | ~256ms per buffer | Never |
| Inference | Internal whisper.cpp state | Duration of transcription | Never |
| Output | UTF-8 text string | Until injected | Only if history is enabled |
| Post-processing | llama.cpp internal state | Duration of LLM pass | Never |
| Cleanup | Zeroed memory | Instant | N/A |

---

## 4. Data at Rest

### 4.1 SwiftData Database

HushType uses SwiftData for persistent storage of user preferences and optional transcription history.

**Storage location:**
```
~/Library/Containers/com.hushtype.app/Data/Library/Application Support/
```

If running outside of the App Sandbox (required for Accessibility API):
```
~/Library/Application Support/HushType/
```

**What is stored:**

| Data | Stored? | Encryption | Notes |
|------|---------|------------|-------|
| User preferences | Yes | FileVault | Theme, shortcuts, model selection |
| Transcription history | Opt-in | FileVault | Text only, never audio |
| Model download metadata | Yes | FileVault | File paths, checksums, download dates |
| Audio recordings | **Never** | N/A | Audio is never written to disk |
| API keys / tokens | **Never** | N/A | No cloud services used |

> 🍎 **macOS-specific**: SwiftData databases in the app container are protected by macOS Data Protection and FileVault full-disk encryption when enabled. HushType strongly recommends FileVault be enabled (see [Section 13](#13-security-best-practices-for-users)).

### 4.2 Keychain Usage

Sensitive configuration values are stored in the macOS Keychain rather than in UserDefaults or plaintext files:

```swift
// Keychain storage for sensitive settings
enum KeychainItem: String {
    case sparkleEdDSAPublicKey = "com.hushtype.sparkle.eddsaPublicKey"
    case sentryDSN = "com.hushtype.sentry.dsn"  // Only if crash reporting opted in
}

func storeInKeychain(item: KeychainItem, data: Data) throws {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: item.rawValue,
        kSecAttrAccount as String: "HushType",
        kSecValueData as String: data,
        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    ]

    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess || status == errSecDuplicateItem else {
        throw KeychainError.unableToStore(status: status)
    }
}
```

> 🔒 **Security**: Keychain items use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, which ensures they are available only when the device is unlocked and are never included in backups or synced to other devices.

### 4.3 Temporary Files

HushType avoids temporary files for audio data. The only temporary files created are:

| Temporary File | Purpose | Lifetime | Cleanup |
|----------------|---------|----------|---------|
| Model download `.part` files | Partial model downloads | During download | Deleted on completion or failure |
| Sparkle update DMG/ZIP | App update packages | During update | Deleted by Sparkle after install |

```swift
// Temporary file cleanup on app launch
func cleanStaleTempFiles() {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("HushType", isDirectory: true)

    if FileManager.default.fileExists(atPath: tempDir.path) {
        try? FileManager.default.removeItem(at: tempDir)
    }
}
```

### 4.4 Model Files

ML model files (`.gguf` format for both whisper.cpp and llama.cpp) are stored locally:

```
~/Library/Application Support/HushType/Models/
├── whisper/
│   └── ggml-base.en.bin          # Whisper STT model
└── llama/
    └── Meta-Llama-3-8B-Q4_K_M.gguf  # LLM post-processing model
```

**Model file security considerations:**

- Models are downloaded over HTTPS from Hugging Face with SHA-256 integrity verification.
- Models are read-only after download; HushType does not modify model files.
- Models do not contain executable code — they are weight tensors loaded by whisper.cpp/llama.cpp.
- Model files should be treated as untrusted input; both whisper.cpp and llama.cpp include input validation for GGUF/GGML file parsing.

> ⚠️ **Warning**: Users who manually place model files (e.g., downloaded from third-party sources) bypass integrity verification. Only models downloaded through HushType's built-in model manager are checksum-verified. See [Threat Model: Malicious Model Files](#101-threat-matrix).

---

## 5. Text Injection Security

### 5.1 CGEvent Text Injection

HushType injects transcribed text into the active application using macOS Accessibility APIs via `CGEvent`:

```swift
func injectTextViaCGEvent(_ text: String) {
    for character in text {
        let utf16 = Array(String(character).utf16)

        let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
        keyDown?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
        keyUp?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        keyUp?.post(tap: .cghidEventTap)
    }
}
```

**Security properties of CGEvent injection:**

- Requires explicit Accessibility permission granted by the user in System Settings.
- Events are posted at the HID (Human Interface Device) level, simulating real keyboard input.
- The target application receives standard keyboard events — no special APIs or hooks are involved.
- CGEvent injection is rate-limited by the system to prevent event flooding.

> 🍎 **macOS-specific**: CGEvent injection requires the calling process to be listed in System Settings > Privacy & Security > Accessibility. This permission survives app restarts but must be re-granted after app updates that change the code signature.

### 5.2 Clipboard Operations

For long text blocks or text containing special characters that CGEvent handles poorly, HushType offers a clipboard-based paste fallback:

```swift
func injectTextViaClipboard(_ text: String) {
    let pasteboard = NSPasteboard.general

    // 1. Preserve the current clipboard contents
    let previousContents = pasteboard.pasteboardItems?.compactMap { item -> NSPasteboardItem? in
        let preserved = NSPasteboardItem()
        for type in item.types {
            if let data = item.data(forType: type) {
                preserved.setData(data, forType: type)
            }
        }
        return preserved
    }

    // 2. Set the transcribed text
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)

    // 3. Simulate Cmd+V paste
    let cmdVDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true) // 'v'
    cmdVDown?.flags = .maskCommand
    cmdVDown?.post(tap: .cghidEventTap)

    let cmdVUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false)
    cmdVUp?.flags = .maskCommand
    cmdVUp?.post(tap: .cghidEventTap)

    // 4. Restore the original clipboard after a short delay
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
        pasteboard.clearContents()
        if let previousContents {
            pasteboard.writeObjects(previousContents)
        }
    }
}
```

### 5.3 Known Risks & Mitigations

| Risk | Severity | Description | Mitigation |
|------|----------|-------------|------------|
| **Clipboard snooping** | Medium | Clipboard managers (e.g., Paste, Maccy) may capture transcribed text during the brief window (~150ms) where it occupies the clipboard. | HushType restores the original clipboard within 150ms. Use CGEvent injection (default) instead of clipboard paste for sensitive content. Consider documenting clipboard manager exclusions. |
| **Clipboard history exposure** | Low | Some clipboard managers maintain persistent history databases that may retain briefly pasted content. | Users handling sensitive transcriptions should prefer CGEvent injection mode or configure their clipboard manager to exclude HushType. |
| **Injected text visibility** | Low | Other processes with Accessibility permissions could observe injected keystrokes. | This is a fundamental property of the macOS Accessibility system; it cannot be mitigated at the application level. Users should audit which apps have Accessibility permissions. |
| **Race condition on paste** | Low | If the user copies something to the clipboard during the 150ms paste window, that content will be overwritten by the clipboard restore operation. | The 150ms window is intentionally short. A future enhancement could use `NSPasteboard.changeCount` to detect external clipboard changes. |

> ❌ **Don't**: Do not use clipboard paste mode for highly sensitive content (e.g., passwords, medical records). Prefer CGEvent injection, which bypasses the clipboard entirely.

> ✅ **Do**: Use CGEvent injection (the default mode) for most text injection. It is both more secure and more reliable than clipboard-based paste.

---

## 6. macOS Permissions & Entitlements

### 6.1 Required Permissions

HushType requests only the permissions strictly necessary for its functionality:

| Permission | System Prompt | Why Required | Revocable? |
|------------|---------------|--------------|------------|
| **Microphone** | "HushType would like to access the microphone" | Audio capture for speech-to-text via AVAudioEngine | Yes, in System Settings > Privacy & Security > Microphone |
| **Accessibility** | Listed in System Settings > Privacy & Security > Accessibility | CGEvent text injection into target applications | Yes, by toggling off in System Settings |
| **Automation** (optional) | "HushType wants to control [App]" | AppleScript-based voice commands (e.g., "open Safari") | Yes, per-app in System Settings > Privacy & Security > Automation |

> 🍎 **macOS-specific**: HushType will function in a degraded mode if Microphone or Accessibility permissions are denied. The app will guide the user to grant permissions but will never attempt to circumvent macOS permission controls.

### 6.2 Entitlements Breakdown

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Audio capture for speech-to-text -->
    <key>com.apple.security.device.audio-input</key>
    <true/>

    <!-- Hardened runtime: allow unsigned executable memory for whisper.cpp/llama.cpp JIT -->
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>

    <!-- Hardened runtime: allow loading third-party libraries (whisper.cpp, llama.cpp) -->
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>

    <!-- Hardened runtime: allow DYLD environment variables (development only) -->
    <!-- REMOVED in release builds -->
    <!-- <key>com.apple.security.cs.allow-dyld-environment-variables</key> -->
    <!-- <true/> -->
</dict>
</plist>
```

**Entitlement-by-entitlement justification:**

| Entitlement | Justification | Risk | Mitigation |
|-------------|---------------|------|------------|
| `device.audio-input` | Required for AVAudioEngine microphone access. Without this, no audio capture is possible. | Microphone access | Permission gated by macOS; user must explicitly grant. App clearly shows recording state via menu bar indicator. |
| `cs.allow-unsigned-executable-memory` | whisper.cpp and llama.cpp use Metal compute shaders and may allocate executable memory for optimized inference paths. | Potential code injection vector | Hardened runtime still active for all other code. Only the ML inference engine uses this entitlement. |
| `cs.disable-library-validation` | Required to load whisper.cpp and llama.cpp dynamic libraries that are not signed with the same Team ID. | Library injection | Libraries are bundled within the signed app bundle and verified during notarization. |

> ⚠️ **Warning**: The `cs.allow-dyld-environment-variables` entitlement is **never** included in release builds. It is only used during development for debugging purposes. CI/CD pipelines validate its absence before signing release builds.

### 6.3 Principle of Least Privilege

HushType follows the principle of least privilege rigorously:

- **No Full Disk Access**: HushType does not request or require Full Disk Access.
- **No Screen Recording**: HushType does not capture screen content.
- **No Camera**: HushType does not access the camera.
- **No Contacts / Calendars / Reminders**: No personal data access.
- **No Location**: No location services.
- **No Network (for core features)**: Network is only used for optional, user-initiated features.
- **Automation is optional**: Voice commands using AppleScript are opt-in and per-application.

> 🔒 **Security**: Users should regularly audit which applications have Accessibility and Microphone permissions in System Settings > Privacy & Security. Remove permissions from any application you no longer use.

---

## 7. Code Signing & Notarization

### 7.1 Developer ID Signing

All HushType releases are signed with a valid Apple Developer ID:

```bash
# Verify code signature of HushType.app
codesign --verify --deep --strict --verbose=4 /Applications/HushType.app

# Display signing details
codesign -dv --verbose=4 /Applications/HushType.app

# Expected output includes:
# Authority=Developer ID Application: [Developer Name] ([Team ID])
# Authority=Developer ID Certification Authority
# Authority=Apple Root CA
# Flags=0x10000(runtime)      <-- Hardened Runtime enabled
```

All binaries within the app bundle are signed, including:

- `HushType.app/Contents/MacOS/HushType` (main executable)
- `HushType.app/Contents/Frameworks/libwhisper.dylib`
- `HushType.app/Contents/Frameworks/libllama.dylib`
- `HushType.app/Contents/Frameworks/Sparkle.framework`

### 7.2 Notarization

Every release build is submitted to Apple's notarization service:

```bash
# Notarization submission (performed by CI/CD)
xcrun notarytool submit HushType.dmg \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_SPECIFIC_PASSWORD" \
    --wait

# Staple the notarization ticket to the DMG
xcrun stapler staple HushType.dmg

# Verify notarization
spctl --assess --verbose=4 --type execute /Applications/HushType.app
# Expected: /Applications/HushType.app: accepted
# source=Notarized Developer ID
```

Notarization ensures:
- Apple has scanned the binary for known malware.
- The binary has not been tampered with since signing.
- Gatekeeper will allow the app to run without warning on macOS.

### 7.3 Hardened Runtime

HushType enables the Hardened Runtime, which provides the following protections:

| Protection | Status | Notes |
|------------|--------|-------|
| Code signature enforcement | Enabled | App will not launch if signature is invalid |
| Library validation | Partially disabled | Required for whisper.cpp/llama.cpp; see entitlements |
| DYLD environment variable restrictions | Enabled (release) | Prevents library injection via environment |
| Debugging restrictions | Enabled (release) | Prevents unauthorized debugger attachment |
| Memory protection | Partially relaxed | `allow-unsigned-executable-memory` for ML inference |
| Resource access control | Enabled | Microphone access gated by entitlement + user permission |

> ℹ️ **Info**: The hardened runtime exceptions (`allow-unsigned-executable-memory` and `disable-library-validation`) are the minimum required for local ML inference with whisper.cpp and llama.cpp. These entitlements are reviewed during Apple's notarization process.

---

## 8. Third-Party Dependency Audit

### 8.1 Dependency Inventory

| Dependency | Version Policy | License | Purpose | Network Access? | Security Track Record |
|------------|---------------|---------|---------|-----------------|----------------------|
| **whisper.cpp** | Pinned to tested commit hash | MIT | Speech-to-text inference engine | None | Active maintainer (Georgi Gerganov), regular security patches, widely audited by community |
| **llama.cpp** | Pinned to tested commit hash | MIT | LLM post-processing inference engine | None | Same maintainer as whisper.cpp, extensive community review, used in production by multiple companies |
| **Sparkle** | Latest stable release (2.x) | MIT | App update framework | Yes (update checks) | Long-standing macOS update framework, EdDSA signature verification, well-audited |
| **Sentry SDK** (optional) | Latest stable release | MIT | Crash reporting (opt-in only) | Yes (crash reports) | Widely used, SOC 2 certified, data can be self-hosted |
| **Swift Argument Parser** | Latest stable release | Apache 2.0 | CLI argument parsing (if applicable) | None | Apple-maintained |
| **KeyboardShortcuts** | Latest stable release | MIT | Global hotkey management | None | Well-maintained, small codebase |

### 8.2 Supply Chain Security

HushType takes the following steps to secure its dependency supply chain:

- **Pinned versions**: All dependencies are pinned to specific versions or commit hashes in `Package.swift`. No floating version ranges for security-critical dependencies.
- **Source review**: Major version updates of whisper.cpp and llama.cpp are reviewed before adoption, with particular attention to GGUF/GGML file parsing code.
- **Swift Package Manager**: Dependencies are fetched via SPM with checksum verification.
- **No binary dependencies**: All C/C++ dependencies (whisper.cpp, llama.cpp) are compiled from source as part of the build process, ensuring full auditability.

```swift
// Package.swift — Pinned dependency example
dependencies: [
    .package(
        url: "https://github.com/ggerganov/whisper.cpp",
        exact: "1.7.3"  // Pinned to audited version
    ),
    .package(
        url: "https://github.com/sparkle-project/Sparkle",
        exact: "2.6.4"  // Pinned to audited version
    ),
]
```

> ❌ **Don't**: Never use `.upToNextMajor()` or `.branch("main")` for security-critical dependencies. Always pin to an exact version or commit hash that has been reviewed.

### 8.3 Update Policy

| Dependency | Update Frequency | Review Process |
|------------|-----------------|----------------|
| whisper.cpp | Every 2-4 weeks | Review GGML parser changes, test with model suite, verify Metal compatibility |
| llama.cpp | Every 2-4 weeks | Review GGUF parser changes, test post-processing pipeline, verify Metal compatibility |
| Sparkle | On security releases | Review changelog for security fixes, test update flow |
| Sentry SDK | Quarterly | Review changelog, verify no new data collection behaviors |

---

## 9. Sandboxing Analysis

### 9.1 App Sandbox Limitations

HushType **cannot use the full macOS App Sandbox** due to its core functionality requirements:

| Feature | Sandbox Compatibility | Reason |
|---------|----------------------|--------|
| Accessibility API (CGEvent) | Incompatible | App Sandbox prohibits CGEvent injection. The `com.apple.security.temporary-exception.apple-events` entitlement is insufficient — full Accessibility access requires running outside the sandbox or using a privileged helper. |
| AVAudioEngine (Microphone) | Compatible | Works within sandbox with `com.apple.security.device.audio-input` entitlement. |
| SwiftData / File Access | Compatible | Works within sandbox using app container. |
| Metal GPU Compute | Compatible | Works within sandbox. |
| AppleScript Automation | Partially compatible | Requires `com.apple.security.automation.apple-events` and per-app consent prompts. Limited in sandbox. |

> 🍎 **macOS-specific**: The Accessibility API (`AXUIElement`, `CGEvent`) is fundamentally incompatible with the App Sandbox. This is a well-known limitation acknowledged by Apple. Apps that require Accessibility-based text injection (including all third-party text expanders and keyboard macro tools) must run without the App Sandbox.

### 9.2 Distribution Tradeoffs

| Distribution Method | App Sandbox | Accessibility API | Auto-Update | Gatekeeper | Notes |
|--------------------|-------------|-------------------|-------------|------------|-------|
| **Mac App Store** | Required | Not possible (standard sandbox) | Via App Store | Yes | Would require removing core text injection functionality |
| **Direct (Developer ID + Notarization)** | Not required | Full support | Via Sparkle | Yes (notarized) | **HushType's chosen distribution method** |
| **Direct (unsigned)** | Not required | Full support | Manual | No (Gatekeeper warning) | Not recommended; requires user to bypass Gatekeeper |

HushType is distributed directly via Developer ID signing and notarization. This provides:
- Full Accessibility API support for text injection
- Gatekeeper approval via notarization (no security warnings)
- Automatic updates via Sparkle with EdDSA signature verification
- User trust via Apple's notarization malware scan

### 9.3 Compensating Controls

Since HushType cannot use the App Sandbox, the following compensating security controls are in place:

1. **Hardened Runtime**: Enables most sandbox-like protections (code injection prevention, library validation, debugger restrictions) without the full sandbox.
2. **Minimal file system access**: HushType only reads/writes to its own Application Support directory and the user-selected model storage directory.
3. **No network access for core features**: Eliminates the largest attack surface that sandboxing typically protects against.
4. **Principle of least privilege**: Only the entitlements strictly required for functionality are included.
5. **Notarization**: Apple scans the binary for malware before distribution.
6. **Open source (GPL-3.0)**: The full source code is available for audit, providing transparency that closed-source sandboxed apps cannot offer.

> ℹ️ **Info**: For a detailed discussion of HushType's architecture and the rationale behind these design decisions, see [Architecture](../architecture/ARCHITECTURE.md).

---

## 10. Threat Model

### 10.1 Threat Matrix

| # | Threat | Likelihood | Impact | Severity | Mitigation | Status |
|---|--------|-----------|--------|----------|------------|--------|
| T1 | **Malicious model files** — Crafted GGUF/GGML files exploiting parser vulnerabilities in whisper.cpp or llama.cpp | Low | High | High | SHA-256 integrity checks on downloaded models. Only official Hugging Face repositories used. Users warned about manually placed models. Parser hardening upstream. | Mitigated |
| T2 | **Clipboard snooping** — Third-party clipboard managers capturing transcribed text during paste operations | Medium | Medium | Medium | CGEvent injection (default) bypasses clipboard entirely. Clipboard restore within 150ms for paste mode. Users advised to exclude HushType from clipboard managers. | Partially mitigated |
| T3 | **Audio eavesdropping via compromised microphone permission** — Malware leveraging HushType's microphone access | Low | High | Medium | HushType does not expose audio to other processes. Microphone permission is per-app in macOS. macOS shows orange dot indicator when mic is active. Audio never leaves process memory. | Mitigated |
| T4 | **Supply chain compromise** — Malicious code injected into whisper.cpp, llama.cpp, or Sparkle dependencies | Low | Critical | High | Pinned dependency versions, source code review for updates, compiled from source (no binary dependencies), notarization scan by Apple. | Mitigated |
| T5 | **Update hijacking** — Man-in-the-middle attack on Sparkle update channel | Low | Critical | High | Sparkle uses EdDSA (Ed25519) signatures. Public key embedded at build time. Even compromised HTTPS cannot inject unsigned updates. | Mitigated |
| T6 | **Accessibility API abuse** — A compromised HushType process using Accessibility permissions to control other apps | Very Low | Critical | Medium | Hardened runtime prevents code injection. Code signing prevents binary tampering. Notarization validates at distribution. macOS kernel enforces code signature at runtime. | Mitigated |
| T7 | **Memory forensics** — Extracting audio data from process memory or swap | Very Low | High | Low | Audio buffers zeroed with `memset_s` after processing. FileVault encrypts swap. Small buffer sizes minimize exposure window. | Mitigated |
| T8 | **Transcription history exposure** — Unauthorized access to SwiftData database containing transcription history | Low | Medium | Medium | Database stored in app container with macOS file permissions. FileVault encrypts at rest. History is opt-in (disabled by default). Users can purge history. | Mitigated |
| T9 | **Keystroke injection manipulation** — Malicious process altering CGEvent stream | Very Low | Medium | Low | CGEvents are posted at HID level. The sending process (HushType) is code-signed. No inter-process channel for injection manipulation. | Mitigated |
| T10 | **Denial of service via microphone monopolization** — HushType holding exclusive mic access | Low | Low | Low | AVAudioEngine uses shared mic access by default. Other apps can capture audio simultaneously. HushType releases mic when not actively transcribing. | Mitigated |

### 10.2 Attack Surface Analysis

```
┌─────────────────────────────────────────────────────────────┐
│                    Attack Surface Map                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  EXTERNAL INPUTS                                            │
│  ├── Microphone audio ──────────── [AVAudioEngine]          │
│  ├── ML model files (GGUF) ─────── [whisper.cpp parser]     │
│  ├── Sparkle update feed (XML) ──── [Sparkle framework]     │
│  └── User settings / preferences ── [SwiftData / UserDefaults] │
│                                                             │
│  EXTERNAL OUTPUTS                                           │
│  ├── CGEvent keystrokes ─────────── [Accessibility API]     │
│  ├── Clipboard write/restore ────── [NSPasteboard]          │
│  ├── AppleScript commands ───────── [NSAppleScript]         │
│  └── Sentry crash reports (opt-in)─ [Sentry SDK → HTTPS]   │
│                                                             │
│  TRUST BOUNDARIES                                           │
│  ├── Process boundary ───────────── Hardened runtime        │
│  ├── Microphone permission ──────── macOS TCC framework     │
│  ├── Accessibility permission ───── macOS TCC framework     │
│  ├── File system ────────────────── App container + POSIX   │
│  └── Network ────────────────────── TLS 1.2+ (when used)   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 10.3 Out-of-Scope Threats

The following threats are considered out of scope for HushType's threat model, as they require a fundamentally compromised system:

- **Kernel-level rootkits**: A compromised kernel can intercept any process's memory, audio, or keystrokes regardless of application-level mitigations.
- **Physical access attacks**: An attacker with physical access to an unlocked Mac can access any running application's data.
- **Compromised macOS TCC database**: If the TCC (Transparency, Consent, and Control) database is tampered with, permission controls are ineffective.
- **Hardware-level microphone taps**: Physical microphone interception is outside software control.
- **Side-channel attacks on Metal GPU**: Theoretical GPU memory leakage between processes during Metal compute operations.

---

## 11. Security Hardening Checklist

### 11.1 Build & Release Checklist

- [ ] All dependencies pinned to reviewed versions in `Package.swift`
- [ ] No `cs.allow-dyld-environment-variables` entitlement in release builds
- [ ] Hardened Runtime enabled (`Flags=0x10000(runtime)`)
- [ ] Code signed with valid Developer ID certificate
- [ ] All frameworks and dylibs within the bundle are signed
- [ ] Notarization submitted and approved by Apple
- [ ] Notarization ticket stapled to DMG
- [ ] Sparkle EdDSA public key embedded and matches signing key
- [ ] No debug symbols in release binary (`STRIP_INSTALLED_PRODUCT = YES`)
- [ ] No `NSLog` or `print` statements leaking sensitive data in release builds
- [ ] Sentry DSN not hardcoded — loaded from Keychain or build configuration
- [ ] Model download URLs use HTTPS only
- [ ] SHA-256 checksums updated for any new model versions
- [ ] CHANGELOG updated with security-relevant changes
- [ ] `codesign --verify --deep --strict` passes on final artifact
- [ ] `spctl --assess --type execute` reports "accepted, Notarized Developer ID"

### 11.2 Code Review Checklist

- [ ] No audio data written to disk (search for `write`, `FileHandle`, `OutputStream` near audio buffers)
- [ ] All audio buffers zeroed after use (search for `memset_s` or equivalent)
- [ ] No hardcoded secrets, API keys, or credentials
- [ ] Clipboard contents restored after paste operations
- [ ] User-facing permission requests include clear explanations
- [ ] Error messages do not leak sensitive information (file paths, internal state)
- [ ] All file I/O uses the app's designated container directories
- [ ] Network calls only occur in explicitly documented code paths
- [ ] GGUF/GGML file parsing uses bounds checking (upstream review)
- [ ] No `NSAppleScript` execution with user-controlled input without sanitization

### 11.3 Runtime Checklist

- [ ] Microphone indicator (menu bar icon state change) is visible when recording
- [ ] Microphone session is released when not actively transcribing
- [ ] Stale temporary files are cleaned on launch
- [ ] Failed model downloads do not leave partial files
- [ ] Sentry crash reporting is default OFF and requires explicit opt-in
- [ ] Sparkle update checks respect the user's configured frequency
- [ ] Accessibility permission is checked before attempting text injection (graceful failure)

---

## 12. Responsible Disclosure Policy

### 12.1 Reporting a Vulnerability

We take security vulnerabilities seriously. If you discover a security issue in HushType, please report it responsibly.

**How to report:**

1. **Email**: Send a detailed report to **security@hushtype.app** (preferred).
2. **GitHub Security Advisory**: Use the [GitHub Security Advisory](https://github.com/hushtype/hushtype/security/advisories/new) feature to create a private vulnerability report.

**What to include:**

- Description of the vulnerability
- Steps to reproduce
- Affected versions
- Potential impact assessment
- Suggested mitigation (if any)
- Your name/handle for credit (optional)

> 🔒 **Security**: Do **not** disclose security vulnerabilities via public GitHub issues, public forums, or social media before a fix is available.

### 12.2 Response Timeline

| Stage | Timeline | Description |
|-------|----------|-------------|
| **Acknowledgment** | Within 48 hours | We will confirm receipt of your report. |
| **Triage** | Within 7 days | We will assess severity, reproduce the issue, and assign a priority. |
| **Fix Development** | Within 30 days (critical), 90 days (non-critical) | A patch will be developed and tested. |
| **Release** | As soon as fix is verified | A security update will be released via Sparkle and GitHub Releases. |
| **Disclosure** | After fix release, coordinated with reporter | A security advisory will be published with full details and credit. |

### 12.3 Safe Harbor

We consider security research conducted in good faith to be authorized activity. We will not pursue legal action against researchers who:

- Make a good faith effort to avoid privacy violations, data destruction, or service disruption.
- Report vulnerabilities through the channels listed above.
- Allow reasonable time for a fix before public disclosure.
- Do not exploit the vulnerability beyond what is necessary to demonstrate the issue.

We will acknowledge security researchers who report valid vulnerabilities (with their permission) in our release notes and security advisories.

---

## 13. Security Best Practices for Users

### 13.1 System-Level Recommendations

| Recommendation | Priority | How |
|----------------|----------|-----|
| **Enable FileVault** | Critical | System Settings > Privacy & Security > FileVault > Turn On. Encrypts your entire disk, protecting all HushType data at rest. |
| **Keep macOS updated** | Critical | System Settings > General > Software Update. Security patches protect the TCC framework, kernel, and audio subsystem that HushType depends on. |
| **Use a strong login password** | Critical | Your macOS login password protects FileVault encryption and Keychain access. |
| **Audit Accessibility permissions** | High | System Settings > Privacy & Security > Accessibility. Remove apps you no longer use. Any app with Accessibility permission can inject keystrokes and observe UI elements. |
| **Audit Microphone permissions** | High | System Settings > Privacy & Security > Microphone. Remove apps that should not have microphone access. |
| **Use a firewall** | Medium | System Settings > Network > Firewall > Turn On. Or use a third-party firewall like LuLu for per-app network control. |
| **Enable Lockdown Mode** (if applicable) | Optional | System Settings > Privacy & Security > Lockdown Mode. Note: This may affect HushType's ability to load ML models. Test before enabling in production use. |

### 13.2 HushType-Specific Recommendations

| Recommendation | Priority | How |
|----------------|----------|-----|
| **Use CGEvent injection (default)** | High | Prefer CGEvent over clipboard paste for text injection. CGEvent never touches the clipboard. |
| **Disable transcription history for sensitive work** | High | Settings > Privacy > Transcription History > Off. When disabled, no text is persisted after injection. |
| **Download models only through HushType** | High | Use the built-in model manager (Settings > Models > Download). This ensures SHA-256 integrity verification. |
| **Review Sparkle update settings** | Medium | Settings > Updates. Choose between automatic checks, manual checks, or disabled. |
| **Keep crash reporting opt-in conscious** | Medium | Settings > Privacy > Send Crash Reports. Default is OFF. Only enable if you want to help improve HushType and are comfortable sharing crash data with Sentry. |
| **Purge transcription history regularly** | Medium | Settings > Privacy > Clear History. If you use transcription history, clear it periodically. |
| **Exclude HushType from clipboard managers** | Medium | If you use a clipboard manager (Paste, Maccy, etc.), add HushType to its exclusion list to prevent it from capturing brief clipboard operations during paste-mode injection. |

### 13.3 Verifying Installation Integrity

After downloading HushType, verify the installation is authentic and untampered:

```bash
# 1. Verify code signature
codesign --verify --deep --strict /Applications/HushType.app
# Expected: valid on disk

# 2. Verify notarization
spctl --assess --verbose=4 --type execute /Applications/HushType.app
# Expected: accepted / source=Notarized Developer ID

# 3. Check the signing authority
codesign -dv /Applications/HushType.app 2>&1 | grep "Authority"
# Expected: Three lines showing Developer ID → Apple chain

# 4. Verify no modifications since signing
codesign --verify --verbose=4 /Applications/HushType.app 2>&1 | grep "valid"
# Expected: "valid on disk" and "satisfies its Designated Requirement"
```

> 💡 **Tip**: If any of the above commands report errors, do **not** run the application. Re-download HushType from the official source and verify again.

```bash
# Optional: Compare SHA-256 of the downloaded DMG against published checksums
shasum -a 256 ~/Downloads/HushType-*.dmg
# Compare output against checksums published on the GitHub Releases page
```

---

## Related Documentation

- [Architecture](../architecture/ARCHITECTURE.md) — System architecture, data flow diagrams, and component design
- [Permissions](../features/PERMISSIONS.md) — Detailed guide to macOS permissions, user flows, and troubleshooting
- [Privacy Policy](../legal/PRIVACY.md) — User-facing privacy policy and data handling commitments
- [Contributing](../../CONTRIBUTING.md) — Development setup, code review process, and security review requirements
- [Build & Release](../development/BUILD.md) — CI/CD pipeline, code signing, and notarization automation
- [Model Management](../features/MODELS.md) — Model download, verification, and storage documentation
- [Changelog](../../CHANGELOG.md) — Release history including security fixes
