Last Updated: 2026-02-13

# macOS Permissions Guide

> **HushType** — Privacy-first, macOS-native speech-to-text. Your voice stays on your device. Always. Since HushType is a local-only app with no user accounts, no authentication, and no cloud services, this document replaces a traditional authentication guide. Instead of managing user identity, HushType manages **system permissions** — the macOS-native trust model that governs access to the microphone, keyboard simulation, and inter-app communication.

---

## Table of Contents

- [1. macOS Permissions Overview](#1-macos-permissions-overview)
  - [1.1 Required Permissions Summary](#11-required-permissions-summary)
  - [1.2 Why No Authentication](#12-why-no-authentication)
  - [1.3 The TCC Framework](#13-the-tcc-framework)
- [2. Permission Request Flow](#2-permission-request-flow)
  - [2.1 First-Launch Experience](#21-first-launch-experience)
  - [2.2 Permission Request Sequence](#22-permission-request-sequence)
  - [2.3 PermissionManager Implementation](#23-permissionmanager-implementation)
- [3. Accessibility Permission](#3-accessibility-permission)
  - [3.1 Why Accessibility Is Required](#31-why-accessibility-is-required)
  - [3.2 Checking Accessibility Status](#32-checking-accessibility-status)
  - [3.3 Requesting Accessibility Access](#33-requesting-accessibility-access)
  - [3.4 System Settings Navigation Path](#34-system-settings-navigation-path)
  - [3.5 Programmatic Guidance](#35-programmatic-guidance)
  - [3.6 Code Signature Invalidation](#36-code-signature-invalidation)
- [4. Microphone Permission](#4-microphone-permission)
  - [4.1 Why Microphone Is Required](#41-why-microphone-is-required)
  - [4.2 Requesting Microphone Access](#42-requesting-microphone-access)
  - [4.3 Handling Microphone Denial](#43-handling-microphone-denial)
  - [4.4 Audio Session Configuration](#44-audio-session-configuration)
- [5. Automation Permission](#5-automation-permission)
  - [5.1 Why Automation Is Optional](#51-why-automation-is-optional)
  - [5.2 Per-App Consent Model](#52-per-app-consent-model)
  - [5.3 NSAppleScript Permission Triggers](#53-nsapplescript-permission-triggers)
  - [5.4 Checking Automation Status](#54-checking-automation-status)
- [6. Handling Permission Denial Gracefully](#6-handling-permission-denial-gracefully)
  - [6.1 Degraded Mode Descriptions](#61-degraded-mode-descriptions)
  - [6.2 Graceful Degradation Implementation](#62-graceful-degradation-implementation)
  - [6.3 User-Facing Permission Status UI](#63-user-facing-permission-status-ui)
- [7. Re-requesting Permissions After Denial](#7-re-requesting-permissions-after-denial)
  - [7.1 macOS Re-request Limitations](#71-macos-re-request-limitations)
  - [7.2 Opening System Settings Programmatically](#72-opening-system-settings-programmatically)
  - [7.3 User Guidance Strategy](#73-user-guidance-strategy)
- [8. Enterprise MDM Permission Pre-Approval](#8-enterprise-mdm-permission-pre-approval)
  - [8.1 TCC Configuration Profiles](#81-tcc-configuration-profiles)
  - [8.2 Privacy Preferences Policy Control](#82-privacy-preferences-policy-control)
  - [8.3 Deploying via MDM](#83-deploying-via-mdm)
  - [8.4 MDM Providers](#84-mdm-providers)
- [9. Permission Status Monitoring](#9-permission-status-monitoring)
  - [9.1 Runtime Permission Observation](#91-runtime-permission-observation)
  - [9.2 DistributedNotificationCenter Approach](#92-distributednotificationcenter-approach)
  - [9.3 Polling Strategy](#93-polling-strategy)
- [10. Troubleshooting](#10-troubleshooting)
  - [10.1 Common Permission Issues](#101-common-permission-issues)
  - [10.2 Resetting Permissions via Terminal](#102-resetting-permissions-via-terminal)
  - [10.3 Diagnostic Commands](#103-diagnostic-commands)
  - [10.4 Known macOS Bugs](#104-known-macos-bugs)
- [Related Documentation](#related-documentation)

---

## 1. macOS Permissions Overview

### 1.1 Required Permissions Summary

HushType requires three macOS permissions to deliver its full feature set. Each permission is gated by Apple's Transparency, Consent, and Control (TCC) framework and requires explicit user approval.

| Permission | TCC Service | What It Enables | Why It Is Needed | Without It |
|------------|-------------|-----------------|------------------|------------|
| **Accessibility** | `kTCCServiceAccessibility` | CGEvent-based text injection into any application | Simulates keystrokes to type transcribed text at the cursor position in the frontmost app | Text injection falls back to clipboard-only mode (Cmd+V paste). Less reliable, briefly overwrites clipboard contents. |
| **Microphone** | `kTCCServiceMicrophone` | Audio capture via AVAudioEngine | Captures speech for on-device transcription by whisper.cpp | Core functionality is completely disabled. HushType cannot record or transcribe speech. |
| **Automation** | `kTCCServiceAppleEvents` | AppleScript execution for voice commands | Enables voice commands like "open Safari", "switch to Xcode", "play music" | Voice commands are disabled. Core dictation and text injection remain fully functional. |

> :lock: **Security**: HushType requests only the permissions strictly necessary for its functionality. It never requests Full Disk Access, Screen Recording, Camera, Contacts, Calendar, Location, or any other macOS permission. See [Security: Principle of Least Privilege](../security/SECURITY.md#63-principle-of-least-privilege) for details.

### 1.2 Why No Authentication

Traditional applications use authentication (usernames, passwords, OAuth tokens) to verify user identity and control access to resources. HushType has none of these because:

- **No server component** — There is no backend to authenticate against.
- **No user accounts** — There is no concept of a user identity in HushType's data model.
- **No cloud data** — All processing is local; there is nothing to protect behind a login wall.
- **No API keys** — HushType does not call external APIs for its core functionality.

Instead of authenticating users, HushType authenticates itself to the operating system through macOS permissions. The user grants trust to the HushType process, and macOS enforces those trust boundaries at the kernel level via TCC.

> :information_source: **Info**: For a detailed discussion of HushType's privacy architecture and why no authentication is needed, see [Legal Compliance: User Accounts and Authentication](../security/LEGAL_COMPLIANCE.md#45-user-accounts-and-authentication).

### 1.3 The TCC Framework

Apple's **Transparency, Consent, and Control (TCC)** framework is the system-level permission manager on macOS. Key properties:

- **Per-application**: Permissions are granted to specific application bundles identified by their code signature, not by file path.
- **Persistent**: Once granted, permissions survive app restarts and system reboots.
- **Revocable**: Users can revoke permissions at any time in System Settings > Privacy & Security.
- **Signature-bound**: If an app's code signature changes (e.g., after an update that changes the signing certificate), Accessibility permissions must be re-granted.
- **Database-backed**: TCC decisions are stored in `~/Library/Application Support/com.apple.TCC/TCC.db` (user-level) and `/Library/Application Support/com.apple.TCC/TCC.db` (system-level, MDM-managed).

```
+-----------------------------------------------------------+
|                    macOS TCC Framework                     |
+-----------------------------------------------------------+
|                                                           |
|  User-Level TCC Database                                  |
|  ~/Library/Application Support/com.apple.TCC/TCC.db      |
|  +-----------------------------------------------------+ |
|  | Service          | Client        | Allowed | Auth'd  | |
|  |------------------+---------------+---------+---------| |
|  | kTCCServiceMic   | com.hushtype  |    1    | user    | |
|  | kTCCServiceAcces | com.hushtype  |    1    | user    | |
|  | kTCCServiceApple | com.hushtype  |    1    | user    | |
|  +-----------------------------------------------------+ |
|                                                           |
|  System-Level TCC Database (MDM-managed)                  |
|  /Library/Application Support/com.apple.TCC/TCC.db       |
|  +-----------------------------------------------------+ |
|  | Service          | Client        | Allowed | Auth'd  | |
|  |------------------+---------------+---------+---------| |
|  | kTCCServiceAcces | com.hushtype  |    1    | mdm     | |
|  +-----------------------------------------------------+ |
|                                                           |
+-----------------------------------------------------------+
```

> :apple: **macOS-specific**: On macOS 14+ (Sonoma), TCC enforcement is stricter than on earlier versions. The system will no longer silently grant permissions that were previously authorized on an older macOS version if the app's code signature has changed.

---

## 2. Permission Request Flow

### 2.1 First-Launch Experience

When HushType launches for the first time, it guides the user through a permission onboarding flow. Permissions are requested sequentially, not simultaneously, to avoid overwhelming the user and to provide clear context for each request.

```
+------------------------------------------------------------------+
|                    First-Launch Permission Flow                    |
+------------------------------------------------------------------+
|                                                                  |
|  [1] Welcome Screen                                              |
|      "HushType needs a few permissions to work."                 |
|      [Continue]                                                  |
|          |                                                       |
|          v                                                       |
|  [2] Microphone Permission                                       |
|      "HushType needs your microphone to hear your voice."        |
|      "Audio never leaves your device."                           |
|      [Grant Microphone Access]                                   |
|          |                                                       |
|          +--- Granted --> [3]                                    |
|          +--- Denied  --> Show guidance, offer [Continue Anyway] |
|          |                                                       |
|          v                                                       |
|  [3] Accessibility Permission                                    |
|      "HushType needs Accessibility access to type text           |
|       into other apps."                                          |
|      "This opens System Settings. Toggle HushType on."           |
|      [Open System Settings]                                      |
|          |                                                       |
|          +--- Granted --> [4]                                    |
|          +--- Skipped --> Show clipboard-only mode notice         |
|          |                                                       |
|          v                                                       |
|  [4] Setup Complete                                              |
|      "You're all set! Press Cmd+Shift+Space to start             |
|       dictating."                                                |
|      [Start Using HushType]                                      |
|                                                                  |
|  Note: Automation permission is NOT requested during             |
|  onboarding. It is requested on-demand when the user first       |
|  triggers a voice command that requires AppleScript.             |
+------------------------------------------------------------------+
```

> :bulb: **Tip**: The onboarding flow runs only once. HushType tracks completion via `UserDefaults.hasCompletedOnboarding`. Users can re-visit permission status at any time in Settings > Permissions.

### 2.2 Permission Request Sequence

Permissions are requested in a deliberate order based on user experience principles:

| Order | Permission | Rationale for Order |
|-------|------------|---------------------|
| 1st | **Microphone** | Most familiar permission. Users expect a speech app to need the microphone. macOS shows a standard system dialog. High grant rate. |
| 2nd | **Accessibility** | Less familiar. Requires manual action in System Settings (not a simple dialog). Better to request after the user has already committed by granting microphone. |
| Deferred | **Automation** | Least essential. Only needed for voice commands, which most users will not use on first launch. Requested on-demand when first needed. |

### 2.3 PermissionManager Implementation

The central permission management class coordinates all permission checks, requests, and status monitoring.

```swift
import AVFoundation
import Cocoa
import Combine

/// Centralized manager for all macOS permission checks and requests.
@MainActor
final class PermissionManager: ObservableObject {

    // MARK: - Published State

    /// Current status of microphone permission.
    @Published private(set) var microphoneStatus: PermissionStatus = .unknown

    /// Current status of accessibility permission.
    @Published private(set) var accessibilityStatus: PermissionStatus = .unknown

    /// Current status of automation permission (per-app, so this reflects
    /// the most recent check target).
    @Published private(set) var automationStatus: PermissionStatus = .unknown

    /// Whether all required permissions (microphone + accessibility) are granted.
    var allRequiredPermissionsGranted: Bool {
        microphoneStatus == .granted && accessibilityStatus == .granted
    }

    /// Whether core functionality is available (at minimum, microphone is needed).
    var coreFunctionalityAvailable: Bool {
        microphoneStatus == .granted
    }

    // MARK: - Initialization

    init() {
        refreshAllStatuses()
    }

    // MARK: - Refresh All

    /// Refreshes the status of all permissions. Call on app activation
    /// (NSApplication.didBecomeActiveNotification) to detect changes
    /// made in System Settings while the app was in the background.
    func refreshAllStatuses() {
        microphoneStatus = checkMicrophoneStatus()
        accessibilityStatus = checkAccessibilityStatus()
    }

    // MARK: - Microphone

    /// Checks the current microphone authorization status.
    func checkMicrophoneStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notRequested
        @unknown default:
            return .unknown
        }
    }

    /// Requests microphone permission. Returns the result.
    func requestMicrophoneAccess() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        microphoneStatus = granted ? .granted : .denied
        UserDefaults.standard.set(
            true,
            forKey: "com.hushtype.hasRequestedMicrophone"
        )
        return granted
    }

    // MARK: - Accessibility

    /// Checks whether the app is trusted for Accessibility access.
    func checkAccessibilityStatus() -> PermissionStatus {
        let trusted = AXIsProcessTrusted()
        return trusted ? .granted : .denied
    }

    /// Prompts the user to grant Accessibility access by showing the
    /// system prompt and opening System Settings.
    func requestAccessibilityAccess() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeRetainedValue(): true
        ] as CFDictionary

        let trusted = AXIsProcessTrustedWithOptions(options)
        accessibilityStatus = trusted ? .granted : .denied
        UserDefaults.standard.set(
            true,
            forKey: "com.hushtype.hasRequestedAccessibility"
        )
    }

    // MARK: - Automation

    /// Checks whether HushType can send Apple Events to a target app.
    /// This check is per-target-app.
    func checkAutomationStatus(
        targetBundleIdentifier: String
    ) -> PermissionStatus {
        let target = NSAppleEventDescriptor(
            bundleIdentifier: targetBundleIdentifier
        )
        let status = AEDeterminePermissionToAutomateTarget(
            target.aeDesc,
            typeWildCard,
            typeWildCard,
            false  // false = don't prompt, just check
        )

        switch status {
        case noErr:
            return .granted
        case OSStatus(errAEEventNotPermitted):
            return .denied
        case OSStatus(procNotFound):
            return .unknown  // Target app not running
        default:
            return .notRequested
        }
    }

    /// Requests automation permission for a specific target app.
    /// This triggers the system consent dialog.
    func requestAutomationAccess(
        targetBundleIdentifier: String
    ) -> PermissionStatus {
        let target = NSAppleEventDescriptor(
            bundleIdentifier: targetBundleIdentifier
        )
        let status = AEDeterminePermissionToAutomateTarget(
            target.aeDesc,
            typeWildCard,
            typeWildCard,
            true  // true = prompt the user
        )

        let result: PermissionStatus
        switch status {
        case noErr:
            result = .granted
        case OSStatus(errAEEventNotPermitted):
            result = .denied
        default:
            result = .unknown
        }

        automationStatus = result
        return result
    }
}

// MARK: - Permission Status Enum

enum PermissionStatus: String, Codable {
    /// Permission has been explicitly granted by the user.
    case granted

    /// Permission has been explicitly denied by the user.
    case denied

    /// Permission is restricted by system policy (e.g., parental controls, MDM).
    case restricted

    /// Permission has not been requested yet.
    case notRequested

    /// Status could not be determined.
    case unknown

    var isUsable: Bool {
        self == .granted
    }

    var displayName: String {
        switch self {
        case .granted: "Granted"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .notRequested: "Not Requested"
        case .unknown: "Unknown"
        }
    }

    var systemImage: String {
        switch self {
        case .granted: "checkmark.circle.fill"
        case .denied: "xmark.circle.fill"
        case .restricted: "lock.circle.fill"
        case .notRequested: "questionmark.circle"
        case .unknown: "questionmark.circle"
        }
    }
}
```

> :warning: **Warning**: The `PermissionManager` must be instantiated on the `@MainActor` because `AXIsProcessTrusted()` and several AppKit calls must run on the main thread. Calling these from a background thread can produce incorrect results or crashes.

---

## 3. Accessibility Permission

### 3.1 Why Accessibility Is Required

HushType's primary text injection mechanism uses the macOS Accessibility API via `CGEvent` to simulate keystrokes in the frontmost application. This is the same mechanism used by text expanders (TextExpander, Raycast), keyboard macro tools (Keyboard Maestro), and other automation utilities.

**What CGEvent text injection does:**

```swift
// This code requires Accessibility permission to function
func injectText(_ text: String) {
    let source = CGEventSource(stateID: .hidSystemState)

    for character in text {
        var utf16 = Array(character.utf16)

        let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: 0,
            keyDown: true
        )
        keyDown?.keyboardSetUnicodeString(
            stringLength: utf16.count,
            unicodeString: &utf16
        )
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: 0,
            keyDown: false
        )
        keyUp?.keyboardSetUnicodeString(
            stringLength: utf16.count,
            unicodeString: &utf16
        )
        keyUp?.post(tap: .cghidEventTap)
    }
}
```

**Without Accessibility permission**, calling `CGEvent.post(tap:)` silently fails. No error is thrown, no exception is raised -- the events are simply dropped by the system. HushType detects this and falls back to clipboard-based injection.

> :lock: **Security**: The Accessibility permission is one of the most powerful permissions on macOS. Any app with this permission can simulate keystrokes, read UI element attributes, and observe events in other applications. HushType uses only the keystroke simulation capability. For a full security analysis, see [Security: Text Injection Security](../security/SECURITY.md#5-text-injection-security).

### 3.2 Checking Accessibility Status

The `AXIsProcessTrusted()` function is the canonical way to check whether the current process has Accessibility permission.

```swift
import ApplicationServices

/// Check if HushType has Accessibility permission.
/// Returns true if the app is listed and enabled in
/// System Settings > Privacy & Security > Accessibility.
func isAccessibilityGranted() -> Bool {
    return AXIsProcessTrusted()
}
```

**Key behaviors of `AXIsProcessTrusted()`:**

| Scenario | Return Value |
|----------|-------------|
| App is listed and toggled **on** in Accessibility settings | `true` |
| App is listed but toggled **off** | `false` |
| App has never been added to Accessibility list | `false` |
| App's code signature changed since permission was granted | `false` |
| Running in Xcode debug mode (unsigned) | Depends on Xcode's Accessibility status |

> :information_source: **Info**: `AXIsProcessTrusted()` is a synchronous, non-blocking call that reads from the TCC database. It is safe to call frequently (e.g., on every app activation) with negligible performance impact.

### 3.3 Requesting Accessibility Access

Unlike Microphone permission, Accessibility cannot be granted via a simple system dialog. The user must manually navigate to System Settings and toggle the app on. However, `AXIsProcessTrustedWithOptions` can show a guiding system alert:

```swift
import ApplicationServices

/// Request Accessibility permission. This shows a system alert
/// that offers to open System Settings > Privacy & Security >
/// Accessibility. The user must manually toggle HushType on.
///
/// Returns true if permission is already granted (the alert
/// is not shown in this case).
func requestAccessibilityPermission() -> Bool {
    let options = [
        kAXTrustedCheckOptionPrompt.takeRetainedValue(): true
    ] as CFDictionary

    return AXIsProcessTrustedWithOptions(options)
}
```

**What happens when this is called:**

1. If the app already has Accessibility permission, the function returns `true` and no dialog is shown.
2. If the app does not have permission, macOS displays a system alert:
   - Title: *"HushType" would like to control this computer using accessibility features.*
   - Buttons: **Deny** | **Open System Settings**
3. If the user clicks "Open System Settings", the Accessibility pane opens with HushType listed (but not yet enabled).
4. The user must toggle the switch next to HushType to **on**.
5. macOS may require the user to authenticate (Touch ID or password) to modify the Accessibility list.

> :warning: **Warning**: `AXIsProcessTrustedWithOptions` shows the system alert only once per app launch session. Subsequent calls in the same session return `false` without showing the alert. To show the alert again, the app must be relaunched or use the custom guidance approach described in [Section 3.5](#35-programmatic-guidance).

### 3.4 System Settings Navigation Path

The exact navigation path for granting Accessibility permission:

```
System Settings
  > Privacy & Security
    > Accessibility
      > [Toggle] HushType  -->  ON
```

On macOS 14+ (Sonoma), the direct URL scheme to open this pane is:

```
x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility
```

### 3.5 Programmatic Guidance

When the built-in system alert has already been shown, HushType provides its own in-app guidance panel with a button to open the correct System Settings pane:

```swift
import SwiftUI

struct AccessibilityPermissionGuideView: View {
    @EnvironmentObject var permissionManager: PermissionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Accessibility Permission Required", systemImage: "hand.raised.fill")
                .font(.headline)

            Text("""
                HushType needs Accessibility access to type transcribed \
                text directly into your apps. Without it, text will be \
                pasted via the clipboard instead.
                """)
                .font(.body)
                .foregroundStyle(.secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("1. Click \"Open System Settings\" below", systemImage: "1.circle")
                    Label("2. Find \"HushType\" in the list", systemImage: "2.circle")
                    Label("3. Toggle the switch to ON", systemImage: "3.circle")
                    Label("4. Authenticate if prompted (Touch ID or password)", systemImage: "4.circle")
                }
                .font(.callout)
            }

            HStack {
                Button("Open System Settings") {
                    openAccessibilitySettings()
                }
                .buttonStyle(.borderedProminent)

                Button("Continue Without") {
                    // Dismiss and use clipboard-only mode
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(width: 420)
    }

    private func openAccessibilitySettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )!
        NSWorkspace.shared.open(url)
    }
}
```

### 3.6 Code Signature Invalidation

A critical gotcha with Accessibility permission: **the permission is bound to the app's code signature**, not its file path. When HushType is updated and the new version has a different code signature (e.g., different signing certificate, modified binary), macOS may revoke the Accessibility permission.

**When this happens:**

- The app appears in the Accessibility list but the toggle is grayed out or automatically turned off.
- `AXIsProcessTrusted()` returns `false` even though the app was previously authorized.
- The user must toggle the app off and on again (or remove and re-add it).

**Mitigations:**

1. Always sign releases with the same Developer ID certificate.
2. Detect the condition on launch and notify the user:

```swift
func checkForSignatureInvalidation() {
    let wasGranted = UserDefaults.standard.bool(
        forKey: "com.hushtype.accessibilityWasGranted"
    )
    let isGranted = AXIsProcessTrusted()

    if wasGranted && !isGranted {
        // Permission was revoked, likely due to code signature change
        showSignatureInvalidationAlert()
    }

    UserDefaults.standard.set(
        isGranted,
        forKey: "com.hushtype.accessibilityWasGranted"
    )
}

func showSignatureInvalidationAlert() {
    let alert = NSAlert()
    alert.messageText = "Accessibility Permission Needs Re-authorization"
    alert.informativeText = """
        HushType was updated and macOS requires you to re-authorize \
        Accessibility access. Please open System Settings, find HushType \
        in the Accessibility list, toggle it off and back on.
        """
    alert.addButton(withTitle: "Open System Settings")
    alert.addButton(withTitle: "Later")

    if alert.runModal() == .alertFirstButtonReturn {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )!
        NSWorkspace.shared.open(url)
    }
}
```

> :apple: **macOS-specific**: Sparkle (HushType's update framework) preserves the code signature when replacing the app bundle, which typically avoids this issue. However, manual reinstallation (dragging a new .app to /Applications) may trigger it.

---

## 4. Microphone Permission

### 4.1 Why Microphone Is Required

HushType captures audio through Apple's `AVAudioEngine` framework for real-time speech-to-text transcription via whisper.cpp. Without microphone access, the entire speech capture pipeline is non-functional.

**Audio capture flow:**

```
Microphone Hardware
       |
       v
 AVAudioEngine inputNode
       |
       v
 AVAudioConverter (resample to 16kHz mono Float32)
       |
       v
 whisper.cpp inference (Metal GPU)
       |
       v
 Transcribed text -> Text injection
```

> :lock: **Security**: Audio data exists only as transient in-memory buffers. It is never written to disk, never transmitted over the network, and is zeroed with `memset_s` after whisper.cpp processing completes. For full details, see [Security: Audio Data Security](../security/SECURITY.md#3-audio-data-security).

### 4.2 Requesting Microphone Access

Microphone permission uses the standard `AVCaptureDevice` API, which triggers a system-provided consent dialog:

```swift
import AVFoundation

/// Request microphone access. This shows the standard macOS system dialog:
/// "HushType would like to access the microphone."
///
/// - Returns: true if permission was granted, false if denied.
func requestMicrophonePermission() async -> Bool {
    // Check current status first
    let currentStatus = AVCaptureDevice.authorizationStatus(for: .audio)

    switch currentStatus {
    case .authorized:
        return true

    case .notDetermined:
        // First request -- shows system dialog
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        return granted

    case .denied, .restricted:
        // Already denied or restricted -- cannot show dialog again
        return false

    @unknown default:
        return false
    }
}
```

**System dialog behavior:**

| Call # | Status | System Dialog Shown? | Result |
|--------|--------|----------------------|--------|
| 1st | `.notDetermined` | Yes -- standard macOS consent dialog | User chooses Allow or Deny |
| 2nd+ | `.authorized` | No | Returns `true` immediately |
| 2nd+ | `.denied` | No -- must go to System Settings | Returns `false` immediately |

> :information_source: **Info**: Unlike Accessibility, the Microphone permission dialog is shown by macOS automatically. HushType does not need to implement custom UI for the initial request. Custom UI is only needed for the denied/re-request flow.

### 4.3 Handling Microphone Denial

When the user denies microphone access, `AVCaptureDevice.requestAccess(for: .audio)` returns `false` and will never show the dialog again. HushType must guide the user to System Settings:

```swift
import AVFoundation

/// Handles the case where microphone permission has been denied.
/// Shows an alert guiding the user to System Settings.
func handleMicrophoneDenial() {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Microphone Access Required"
    alert.informativeText = """
        HushType cannot record speech without microphone access. \
        To enable it:

        1. Open System Settings
        2. Go to Privacy & Security > Microphone
        3. Toggle HushType to ON

        Without microphone access, HushType cannot function.
        """
    alert.addButton(withTitle: "Open System Settings")
    alert.addButton(withTitle: "Quit HushType")

    let response = alert.runModal()
    if response == .alertFirstButtonReturn {
        openMicrophoneSettings()
    } else {
        NSApplication.shared.terminate(nil)
    }
}

/// Opens System Settings to the Microphone privacy pane.
func openMicrophoneSettings() {
    let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
    )!
    NSWorkspace.shared.open(url)
}
```

### 4.4 Audio Session Configuration

After microphone permission is granted, HushType configures the audio session for optimal speech capture:

```swift
import AVFoundation

/// Configures the audio session for speech-to-text capture.
/// Must be called after microphone permission is granted.
func configureAudioSession() throws {
    let audioEngine = AVAudioEngine()
    let inputNode = audioEngine.inputNode
    let inputFormat = inputNode.outputFormat(forBus: 0)

    // Verify we have a valid input format
    guard inputFormat.sampleRate > 0 else {
        throw AudioError.noInputDevice
    }

    // Target format for whisper.cpp: 16kHz, mono, Float32
    guard let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000.0,
        channels: 1,
        interleaved: false
    ) else {
        throw AudioError.formatCreationFailed
    }

    // Create converter for sample rate conversion
    guard let converter = AVAudioConverter(
        from: inputFormat,
        to: targetFormat
    ) else {
        throw AudioError.converterCreationFailed
    }

    // Install tap -- this is where audio capture begins
    inputNode.installTap(
        onBus: 0,
        bufferSize: 1024,  // ~64ms at 16kHz
        format: inputFormat
    ) { buffer, time in
        // Process audio buffer...
    }

    audioEngine.prepare()
    try audioEngine.start()
}
```

> :apple: **macOS-specific**: On macOS, `AVAudioEngine` uses shared microphone access by default. Multiple apps can capture audio simultaneously. HushType does not monopolize the microphone.

---

## 5. Automation Permission

### 5.1 Why Automation Is Optional

Automation permission enables HushType's **voice command** feature, which uses AppleScript to control other applications. Unlike Accessibility and Microphone, Automation is entirely optional -- the core dictation pipeline works without it.

**Voice commands powered by Automation:**

| Voice Command | AppleScript Target | What It Does |
|---------------|-------------------|--------------|
| "Open Safari" | `com.apple.Safari` | Launches or activates Safari |
| "Switch to Xcode" | `com.apple.dt.Xcode` | Activates the Xcode window |
| "Play music" | `com.apple.Music` | Sends play command to Music app |
| "New document" | Frontmost app | Sends Cmd+N via Apple Events |
| "Save" | Frontmost app | Sends Cmd+S via Apple Events |

### 5.2 Per-App Consent Model

Automation permission is unique because it is **per-target-application**. HushType must obtain separate consent to send Apple Events to each application it wants to control.

```
+------------------------------------------------------------+
|              Automation Permission Model                    |
+------------------------------------------------------------+
|                                                            |
|  HushType --> Safari       [Consent needed for Safari]     |
|  HushType --> Xcode        [Consent needed for Xcode]      |
|  HushType --> Music        [Consent needed for Music]      |
|  HushType --> Finder       [Consent needed for Finder]     |
|  HushType --> Terminal     [Consent needed for Terminal]    |
|                                                            |
|  Each arrow requires a SEPARATE user consent dialog.       |
|  System Settings > Privacy & Security > Automation shows:  |
|                                                            |
|  HushType                                                  |
|    [x] Safari                                              |
|    [x] Xcode                                               |
|    [ ] Music  (denied)                                     |
|    [x] Finder                                              |
|                                                            |
+------------------------------------------------------------+
```

> :information_source: **Info**: The per-app model means HushType does not need a blanket Automation permission. Each voice command target is authorized independently. Users can selectively allow HushType to control some apps but not others.

### 5.3 NSAppleScript Permission Triggers

When HushType executes an AppleScript that targets another application, macOS automatically shows a consent dialog if permission has not been granted:

```swift
import Foundation

/// Executes a voice command by sending an Apple Event to the target app.
/// This may trigger a system consent dialog on first use per target app.
func executeVoiceCommand(
    script: String,
    targetBundleIdentifier: String
) throws -> String? {
    let appleScript = NSAppleScript(source: script)

    var error: NSDictionary?
    let result = appleScript?.executeAndReturnError(&error)

    if let error = error {
        let errorNumber = error[NSAppleScript.errorNumber] as? Int ?? 0

        if errorNumber == -1743 {
            // errAEEventNotPermitted -- user denied Automation
            throw VoiceCommandError.automationDenied(
                target: targetBundleIdentifier
            )
        }

        throw VoiceCommandError.scriptExecutionFailed(
            message: error[NSAppleScript.errorMessage] as? String
                ?? "Unknown error"
        )
    }

    return result?.stringValue
}

// Example: Activate Safari
let script = """
    tell application "Safari"
        activate
    end tell
    """

try executeVoiceCommand(
    script: script,
    targetBundleIdentifier: "com.apple.Safari"
)
```

**Consent dialog flow:**

1. HushType calls `NSAppleScript.executeAndReturnError`.
2. macOS detects that HushType is targeting another app via Apple Events.
3. System shows: *"HushType" wants access to control "Safari". Allowing control will provide access to documents and data in "Safari", and to perform actions within that app.*
4. User clicks **OK** (grants) or **Don't Allow** (denies).
5. Decision is stored in the TCC database under `kTCCServiceAppleEvents`.

### 5.4 Checking Automation Status

Before executing a voice command, check whether Automation permission has been granted for the target app:

```swift
import ApplicationServices

/// Checks whether HushType has Automation permission for a target app
/// without prompting the user.
///
/// - Parameter bundleIdentifier: The target app's bundle ID.
/// - Returns: The current permission status.
func checkAutomationPermission(
    for bundleIdentifier: String
) -> PermissionStatus {
    let target = NSAppleEventDescriptor(
        bundleIdentifier: bundleIdentifier
    )

    let status = AEDeterminePermissionToAutomateTarget(
        target.aeDesc,
        typeWildCard,
        typeWildCard,
        false  // false = check only, do not prompt
    )

    switch status {
    case noErr:
        return .granted
    case OSStatus(errAEEventNotPermitted):
        return .denied
    case OSStatus(procNotFound):
        // Target app is not running -- cannot determine status
        return .unknown
    default:
        // -1744 typically means "not yet determined"
        return .notRequested
    }
}
```

> :warning: **Warning**: `AEDeterminePermissionToAutomateTarget` requires the target app to be running. If the target app is not launched, the function returns `procNotFound` and the permission status cannot be determined. HushType handles this by attempting the AppleScript execution directly, which will launch the target app and trigger the consent dialog if needed.

---

## 6. Handling Permission Denial Gracefully

### 6.1 Degraded Mode Descriptions

HushType is designed to degrade gracefully when permissions are missing. Each missing permission disables a specific feature set while leaving the rest functional.

| Missing Permission | Feature Impact | Degraded Behavior |
|-------------------|----------------|-------------------|
| **Microphone** | Core dictation disabled | HushType cannot capture audio. The app shows a persistent banner: "Microphone access required. Grant access in System Settings to start dictating." The app remains open for settings configuration and model management. |
| **Accessibility** | CGEvent injection disabled | Text injection falls back to **clipboard-only mode**: transcribed text is copied to the clipboard and pasted via simulated Cmd+V. This briefly overwrites the clipboard and may not work in all apps (e.g., Terminal secure input mode). The app shows a subtle indicator: "Running in clipboard mode. Grant Accessibility access for direct typing." |
| **Automation** | Voice commands disabled | Voice commands that target other apps via AppleScript silently fail. The transcription pipeline and text injection continue to work normally. The app shows a contextual message only when a voice command fails: "Automation access needed for this command." |
| **Microphone + Accessibility** | Dictation and injection disabled | HushType is essentially non-functional for its primary purpose but remains usable for settings, model management, and history browsing. |

### 6.2 Graceful Degradation Implementation

```swift
import AVFoundation

/// Determines the current operational mode based on granted permissions.
enum OperationalMode {
    /// All permissions granted -- full functionality.
    case full

    /// Microphone granted, Accessibility denied -- clipboard injection only.
    case clipboardOnly

    /// Microphone denied -- cannot record, app is in setup mode.
    case setupRequired

    /// All denied -- minimal functionality.
    case minimal

    var canRecord: Bool {
        switch self {
        case .full, .clipboardOnly: true
        case .setupRequired, .minimal: false
        }
    }

    var canInjectViaKeystrokes: Bool {
        switch self {
        case .full: true
        case .clipboardOnly, .setupRequired, .minimal: false
        }
    }

    var canInjectViaClipboard: Bool {
        switch self {
        case .full, .clipboardOnly: true
        case .setupRequired, .minimal: false
        }
    }

    var canExecuteVoiceCommands: Bool {
        // Voice commands are checked per-target-app at runtime
        false  // Determined dynamically
    }

    var statusDescription: String {
        switch self {
        case .full:
            "All systems operational"
        case .clipboardOnly:
            "Running in clipboard mode (Accessibility access not granted)"
        case .setupRequired:
            "Microphone access required to start dictating"
        case .minimal:
            "Permissions required -- open Settings to configure"
        }
    }
}

/// Resolves the current operational mode from permission states.
func resolveOperationalMode(
    microphone: PermissionStatus,
    accessibility: PermissionStatus
) -> OperationalMode {
    switch (microphone, accessibility) {
    case (.granted, .granted):
        return .full
    case (.granted, _):
        return .clipboardOnly
    case (_, .granted):
        return .setupRequired
    default:
        return .minimal
    }
}
```

**Text injection with graceful fallback:**

```swift
/// Injects text using the best available method based on current permissions.
func injectText(
    _ text: String,
    mode: OperationalMode,
    preferredMethod: InjectionMethod = .auto
) {
    switch mode {
    case .full:
        // Full mode: use preferred method
        switch preferredMethod {
        case .cgEvent:
            injectViaCGEvent(text)
        case .clipboard:
            injectViaClipboard(text)
        case .auto:
            // Short text via CGEvent, long text via clipboard
            if text.count < 50 {
                injectViaCGEvent(text)
            } else {
                injectViaClipboard(text)
            }
        }

    case .clipboardOnly:
        // Clipboard-only fallback
        injectViaClipboard(text)
        showSubtleNotification(
            "Text pasted via clipboard. Grant Accessibility "
            + "access for direct typing."
        )

    case .setupRequired, .minimal:
        // Cannot inject at all -- copy to clipboard and notify
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showSubtleNotification(
            "Text copied to clipboard. Grant required permissions "
            + "to enable direct text injection."
        )
    }
}
```

### 6.3 User-Facing Permission Status UI

HushType's Settings window includes a dedicated Permissions tab that shows the current status of all permissions with actionable guidance:

```swift
import SwiftUI

struct PermissionStatusView: View {
    @EnvironmentObject var permissionManager: PermissionManager

    var body: some View {
        Form {
            Section("Required Permissions") {
                PermissionRow(
                    name: "Microphone",
                    description: "Capture speech for transcription",
                    status: permissionManager.microphoneStatus,
                    settingsAction: openMicrophoneSettings
                )

                PermissionRow(
                    name: "Accessibility",
                    description: "Type transcribed text into apps",
                    status: permissionManager.accessibilityStatus,
                    settingsAction: openAccessibilitySettings
                )
            }

            Section("Optional Permissions") {
                PermissionRow(
                    name: "Automation",
                    description: "Control other apps via voice commands",
                    status: permissionManager.automationStatus,
                    settingsAction: openAutomationSettings
                )
            }

            Section {
                Button("Refresh Permission Status") {
                    permissionManager.refreshAllStatuses()
                }
                .buttonStyle(.bordered)

                Text(
                    "Permissions can be changed at any time in "
                    + "System Settings > Privacy & Security."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            // Refresh when user returns from System Settings
            permissionManager.refreshAllStatuses()
        }
    }

    private func openMicrophoneSettings() {
        NSWorkspace.shared.open(URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        )!)
    }

    private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )!)
    }

    private func openAutomationSettings() {
        NSWorkspace.shared.open(URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        )!)
    }
}

struct PermissionRow: View {
    let name: String
    let description: String
    let status: PermissionStatus
    let settingsAction: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: status.systemImage)
                        .foregroundStyle(status.isUsable ? .green : .red)
                    Text(name)
                        .font(.body.weight(.medium))
                }
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if status.isUsable {
                Text("Granted")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button("Open Settings") {
                    settingsAction()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}
```

---

## 7. Re-requesting Permissions After Denial

### 7.1 macOS Re-request Limitations

A critical aspect of the macOS TCC framework: **once a user denies a permission, the app cannot programmatically show the system dialog again.** The only way to change the permission is for the user to manually navigate to System Settings.

| Permission | Can Re-request Programmatically? | How to Change After Denial |
|------------|----------------------------------|----------------------------|
| **Microphone** | No -- `AVCaptureDevice.requestAccess` returns `false` immediately without showing a dialog | System Settings > Privacy & Security > Microphone > Toggle HushType ON |
| **Accessibility** | Partially -- `AXIsProcessTrustedWithOptions(prompt: true)` shows the system alert once per launch, but the user still must toggle manually in Settings | System Settings > Privacy & Security > Accessibility > Toggle HushType ON |
| **Automation** | No -- `AEDeterminePermissionToAutomateTarget(prompt: true)` does not re-show the dialog after denial | System Settings > Privacy & Security > Automation > HushType > Toggle target app ON |

> :warning: **Warning**: There is no API to reset the TCC database entry for your app. Calling `tccutil reset` from the command line affects all apps for that service, not individual apps. Do not instruct users to run `tccutil reset` unless absolutely necessary, as it resets permissions for all applications.

### 7.2 Opening System Settings Programmatically

HushType provides convenience methods to open the exact System Settings pane for each permission:

```swift
import AppKit

enum SystemSettingsPane {
    case microphone
    case accessibility
    case automation
    case privacyMain

    /// The URL scheme that opens the correct System Settings pane
    /// on macOS 14+ (Sonoma).
    var url: URL {
        switch self {
        case .microphone:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        case .accessibility:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        case .automation:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
        case .privacyMain:
            URL(string: "x-apple.systempreferences:com.apple.preference.security")!
        }
    }

    /// Opens the System Settings pane.
    func open() {
        NSWorkspace.shared.open(url)
    }
}
```

**Usage in a denied-permission flow:**

```swift
func handleDeniedPermission(_ permission: SystemSettingsPane) {
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = "Permission Change Required"
    alert.informativeText = """
        This permission was previously denied. macOS does not allow \
        apps to re-request permissions. You can change this in \
        System Settings.
        """
    alert.addButton(withTitle: "Open System Settings")
    alert.addButton(withTitle: "Not Now")

    if alert.runModal() == .alertFirstButtonReturn {
        permission.open()
    }
}
```

### 7.3 User Guidance Strategy

HushType uses a tiered notification strategy for denied permissions:

| Context | Notification Type | Message |
|---------|------------------|---------|
| **First denial** (during onboarding) | Modal alert with System Settings button | "HushType needs [permission] to [function]. Open System Settings to grant access." |
| **Subsequent app launches** (permission still denied) | Non-modal banner in main window | "Some features are limited. [Permission] access is needed for [function]. [Open Settings]" |
| **When user triggers a feature that requires the denied permission** | Contextual toast notification | "[Feature] requires [permission] access. Tap to open Settings." |
| **Settings > Permissions tab** | Persistent status indicator | Full status dashboard with per-permission Open Settings buttons |

> :bulb: **Tip**: Avoid nagging the user. Show the non-modal banner at most once per app launch. Show contextual toasts only when the user explicitly attempts a feature that requires the missing permission.

---

## 8. Enterprise MDM Permission Pre-Approval

### 8.1 TCC Configuration Profiles

Enterprise IT administrators can pre-approve HushType's permissions using Mobile Device Management (MDM) configuration profiles. This allows silent deployment without requiring end-user interaction for permission dialogs.

The relevant MDM payload is the **Privacy Preferences Policy Control** payload (`com.apple.TCC.configuration-profile-policy`), which writes entries directly to the system-level TCC database.

> :information_source: **Info**: MDM-managed TCC entries take precedence over user-level TCC entries. If an MDM profile grants a permission, the user cannot revoke it (it appears grayed out in System Settings). If the MDM profile denies a permission, the user cannot grant it.

### 8.2 Privacy Preferences Policy Control

The following configuration profile pre-approves all three permissions for HushType:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>PayloadContent</key>
    <array>
        <dict>
            <key>PayloadType</key>
            <string>com.apple.TCC.configuration-profile-policy</string>
            <key>PayloadIdentifier</key>
            <string>com.hushtype.tcc.policy</string>
            <key>PayloadUUID</key>
            <string>A1B2C3D4-E5F6-7890-ABCD-EF1234567890</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
            <key>PayloadDisplayName</key>
            <string>HushType Permission Policy</string>

            <key>Services</key>
            <dict>
                <!-- Microphone Permission -->
                <key>Microphone</key>
                <array>
                    <dict>
                        <key>Identifier</key>
                        <string>com.hushtype.app</string>
                        <key>IdentifierType</key>
                        <string>bundleID</string>
                        <key>CodeRequirement</key>
                        <string>identifier "com.hushtype.app" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = "TEAM_ID_HERE"</string>
                        <key>Allowed</key>
                        <true/>
                        <key>StaticCode</key>
                        <false/>
                    </dict>
                </array>

                <!-- Accessibility Permission -->
                <key>Accessibility</key>
                <array>
                    <dict>
                        <key>Identifier</key>
                        <string>com.hushtype.app</string>
                        <key>IdentifierType</key>
                        <string>bundleID</string>
                        <key>CodeRequirement</key>
                        <string>identifier "com.hushtype.app" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = "TEAM_ID_HERE"</string>
                        <key>Allowed</key>
                        <true/>
                        <key>StaticCode</key>
                        <false/>
                    </dict>
                </array>

                <!-- Automation Permission (per-target-app) -->
                <key>AppleEvents</key>
                <array>
                    <dict>
                        <key>Identifier</key>
                        <string>com.hushtype.app</string>
                        <key>IdentifierType</key>
                        <string>bundleID</string>
                        <key>CodeRequirement</key>
                        <string>identifier "com.hushtype.app" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = "TEAM_ID_HERE"</string>
                        <key>Allowed</key>
                        <true/>
                        <key>AEReceiverIdentifier</key>
                        <string>com.apple.Safari</string>
                        <key>AEReceiverIdentifierType</key>
                        <string>bundleID</string>
                        <key>AEReceiverCodeRequirement</key>
                        <string>identifier "com.apple.Safari" and anchor apple</string>
                    </dict>
                    <!-- Repeat for each target app -->
                </array>
            </dict>
        </dict>
    </array>

    <!-- Profile-level metadata -->
    <key>PayloadDisplayName</key>
    <string>HushType Permissions</string>
    <key>PayloadIdentifier</key>
    <string>com.hushtype.mdm.permissions</string>
    <key>PayloadOrganization</key>
    <string>Your Organization</string>
    <key>PayloadScope</key>
    <string>System</string>
    <key>PayloadType</key>
    <string>Configuration</string>
    <key>PayloadUUID</key>
    <string>F1E2D3C4-B5A6-7890-FEDC-BA9876543210</string>
    <key>PayloadVersion</key>
    <integer>1</integer>
</dict>
</plist>
```

> :warning: **Warning**: Replace `TEAM_ID_HERE` with the actual Apple Developer Team ID used to sign HushType. The `CodeRequirement` string must match the app's actual code signature. Use `codesign -dr - /Applications/HushType.app` to obtain the correct designated requirement.

### 8.3 Deploying via MDM

**Steps for IT administrators:**

1. **Obtain the code requirement** for the signed HushType binary:

```bash
# Get the designated requirement for HushType
codesign -dr - /Applications/HushType.app 2>&1

# Output example:
# designated => identifier "com.hushtype.app" and anchor apple generic
# and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */
# and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */
# and certificate leaf[subject.OU] = "ABC123DEF4"
```

2. **Create the configuration profile** using the XML template above, substituting the correct `CodeRequirement` and Team ID.

3. **Sign the profile** with your organization's MDM signing certificate (required for deployment).

4. **Deploy the profile** through your MDM solution before or simultaneously with deploying HushType.

5. **Verify deployment** on a test machine:

```bash
# List installed profiles
sudo profiles list -verbose

# Check TCC database for the MDM-managed entries
sudo sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" \
    "SELECT service, client, allowed, auth_reason FROM access WHERE client = 'com.hushtype.app';"
```

### 8.4 MDM Providers

The Privacy Preferences Policy Control payload is supported by all major MDM solutions:

| MDM Solution | PPPC Support | Profile Signing | Notes |
|-------------|-------------|-----------------|-------|
| **Jamf Pro** | Full (GUI builder) | Built-in | Has a dedicated PPPC profile builder with GUI |
| **Mosyle** | Full | Built-in | Supports uploading custom profiles |
| **Kandji** | Full | Built-in | Provides PPPC templates |
| **Fleet** | Full | Manual | Uses custom configuration profiles |
| **Munki** | Via profiles | Manual | Profile deployment via `profiles` command |
| **Apple Business Manager** | Via profiles | Built-in | Native profile distribution |

> :bulb: **Tip**: For Jamf Pro users, the [PPPC Utility](https://github.com/jamf/PPPC-Utility) (open source, by Jamf) can generate PPPC configuration profiles from a running application by analyzing its code signature and required permissions.

---

## 9. Permission Status Monitoring

### 9.1 Runtime Permission Observation

HushType needs to detect when the user changes permissions in System Settings while the app is running. macOS does not provide a notification-based API for all permission changes, so HushType uses a combination of strategies.

### 9.2 DistributedNotificationCenter Approach

For Accessibility permission, macOS posts a distributed notification when the TCC database changes:

```swift
import Foundation

/// Observes changes to the Accessibility permission via
/// DistributedNotificationCenter.
final class AccessibilityPermissionObserver {
    private var observer: NSObjectProtocol?

    /// Starts observing Accessibility permission changes.
    /// The callback is invoked whenever the TCC database is modified
    /// (which includes changes to Accessibility permissions for any app).
    func startObserving(onChange: @escaping (Bool) -> Void) {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { _ in
            let isGranted = AXIsProcessTrusted()
            onChange(isGranted)
        }
    }

    /// Stops observing.
    func stopObserving() {
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observer = nil
    }

    deinit {
        stopObserving()
    }
}
```

> :warning: **Warning**: The `com.apple.accessibility.api` distributed notification fires when any app's Accessibility permission changes, not just HushType's. Always re-check `AXIsProcessTrusted()` when receiving this notification to determine if the change is relevant to HushType.

### 9.3 Polling Strategy

For Microphone and Automation permissions, no reliable notification mechanism exists. HushType uses event-driven polling:

```swift
import AVFoundation
import Combine

/// Monitors permission status changes using app lifecycle events.
@MainActor
final class PermissionMonitor: ObservableObject {
    @Published var currentMode: OperationalMode = .minimal

    private let permissionManager: PermissionManager
    private var accessibilityObserver: AccessibilityPermissionObserver?
    private var cancellables = Set<AnyCancellable>()

    init(permissionManager: PermissionManager) {
        self.permissionManager = permissionManager
        setupMonitoring()
    }

    private func setupMonitoring() {
        // 1. Refresh on app activation (user returns from System Settings)
        NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )
        .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
        .sink { [weak self] _ in
            self?.refreshPermissions()
        }
        .store(in: &cancellables)

        // 2. Observe Accessibility changes via distributed notification
        accessibilityObserver = AccessibilityPermissionObserver()
        accessibilityObserver?.startObserving { [weak self] isGranted in
            self?.permissionManager.accessibilityStatus =
                isGranted ? .granted : .denied
            self?.updateOperationalMode()
        }

        // 3. Initial check
        refreshPermissions()
    }

    func refreshPermissions() {
        permissionManager.refreshAllStatuses()
        updateOperationalMode()
    }

    private func updateOperationalMode() {
        currentMode = resolveOperationalMode(
            microphone: permissionManager.microphoneStatus,
            accessibility: permissionManager.accessibilityStatus
        )
    }
}
```

**Polling triggers and their rationale:**

| Trigger | Why |
|---------|-----|
| `NSApplication.didBecomeActiveNotification` | Detects changes when user returns from System Settings. This is the most common path for permission changes. |
| `com.apple.accessibility.api` distributed notification | Real-time notification for Accessibility changes specifically. |
| Timer (every 30 seconds, only in Settings window) | Fallback for edge cases where the above notifications are missed. Only active when the Permissions settings tab is visible. |
| Manual refresh button in Settings | User-initiated check for immediate feedback. |

> :information_source: **Info**: HushType does not use continuous background polling for permission status, as this would waste CPU cycles. Polling is strictly event-driven (app activation, distributed notifications) with a manual fallback in the Settings UI.

---

## 10. Troubleshooting

### 10.1 Common Permission Issues

| Issue | Symptoms | Cause | Solution |
|-------|----------|-------|----------|
| **Accessibility permission lost after update** | Text injection stops working. `AXIsProcessTrusted()` returns `false`. HushType appears in Accessibility list but is disabled. | App's code signature changed between versions (different signing certificate or unsigned build). | Open System Settings > Privacy & Security > Accessibility. Remove HushType from the list (select and click "-"), then re-add it (click "+", navigate to /Applications/HushType.app). |
| **Microphone permission not prompting** | No system dialog appears when HushType starts. `AVCaptureDevice.authorizationStatus(for: .audio)` returns `.denied`. | Permission was previously denied and macOS does not re-prompt. | Open System Settings > Privacy & Security > Microphone. Toggle HushType to ON. |
| **"HushType is not in the Accessibility list"** | User opens System Settings > Accessibility but HushType is not listed. | HushType has never called `AXIsProcessTrustedWithOptions(prompt: true)`, or the app binary path has changed. | In HushType, go to Settings > Permissions > click "Request Accessibility Access". Alternatively, manually add HushType via the "+" button in System Settings > Accessibility. |
| **Automation permission denied for all apps** | Voice commands fail for every target app with error -1743. | User denied the first Automation prompt and the system applied it broadly. | Open System Settings > Privacy & Security > Automation > HushType. Toggle each target app to ON. |
| **Permission dialogs appear in wrong language** | System permission dialogs show in a language different from the system locale. | macOS bug with localization. | Ensure System Settings > General > Language & Region has the correct primary language. Reboot if necessary. |
| **"HushType would like to control this computer" keeps appearing** | Accessibility system alert shows every time the app launches. | Permission is being requested but never successfully granted (e.g., due to MDM restriction or corrupted TCC database). | Try resetting the TCC database (see [10.2](#102-resetting-permissions-via-terminal)). Check for MDM-managed restrictions with your IT department. |

### 10.2 Resetting Permissions via Terminal

If permissions become corrupted or stuck, the `tccutil` command can reset the TCC database for specific services. **Use with caution -- this affects ALL applications for the specified service.**

```bash
# Reset Microphone permissions for ALL apps
tccutil reset Microphone

# Reset Accessibility permissions for ALL apps
tccutil reset Accessibility

# Reset Automation (Apple Events) permissions for ALL apps
tccutil reset AppleEvents

# Reset ALL privacy permissions for ALL apps (nuclear option)
tccutil reset All
```

> :x: **Don't**: Do not run `tccutil reset All` unless absolutely necessary. This resets every privacy permission for every application on the system, requiring the user to re-grant permissions for all apps (not just HushType).

> :white_check_mark: **Do**: Prefer resetting only the specific service that is problematic (e.g., `tccutil reset Accessibility` if only Accessibility is stuck).

**After running `tccutil reset`:**

1. Quit HushType completely (`Cmd+Q`).
2. Relaunch HushType.
3. The permission request flow will restart as if it were a fresh install.
4. Other apps affected by the reset will also need to re-request permissions.

### 10.3 Diagnostic Commands

Use these terminal commands to diagnose permission issues:

```bash
# Check if HushType has Accessibility permission
# (requires the app to be running)
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
    "SELECT service, client, allowed FROM access WHERE client LIKE '%hushtype%';"

# List all Accessibility-trusted apps
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
    "SELECT client, allowed FROM access WHERE service = 'kTCCServiceAccessibility';"

# Check for MDM-managed permissions (system-level TCC)
sudo sqlite3 /Library/Application\ Support/com.apple.TCC/TCC.db \
    "SELECT service, client, allowed, auth_reason FROM access WHERE client LIKE '%hushtype%';"

# Verify HushType's code signature
codesign --verify --deep --strict --verbose=4 /Applications/HushType.app

# Display signing authority chain
codesign -dv --verbose=4 /Applications/HushType.app 2>&1 | grep "Authority"

# Check if HushType's designated requirement matches
# what TCC expects
codesign -dr - /Applications/HushType.app

# Monitor TCC database changes in real-time (useful for debugging)
log stream --predicate 'subsystem == "com.apple.TCC"' --level debug

# Check for MDM configuration profiles that affect TCC
sudo profiles list -verbose 2>&1 | grep -A 5 -i "privacy\|TCC\|hushtype"
```

> :apple: **macOS-specific**: On macOS 14+ (Sonoma), direct SQLite access to the user-level TCC database (`~/Library/Application Support/com.apple.TCC/TCC.db`) may be restricted by SIP (System Integrity Protection). The `log stream` approach is more reliable for debugging.

### 10.4 Known macOS Bugs

| Bug | Affected macOS Versions | Description | Workaround |
|-----|-------------------------|-------------|------------|
| **Accessibility toggle visually on but not functional** | macOS 14.0-14.2 | After toggling Accessibility ON, `AXIsProcessTrusted()` still returns `false` until the app is quit and relaunched. | Quit HushType (Cmd+Q), wait 2 seconds, relaunch. Apple fixed this in macOS 14.3. |
| **Microphone status stuck on `.notDetermined`** | macOS 14.0 | `AVCaptureDevice.authorizationStatus(for: .audio)` returns `.notDetermined` even after the user has responded to the dialog. | Call `requestAccess(for: .audio)` again. If still stuck, reset with `tccutil reset Microphone` and retry. |
| **Automation permission dialog not appearing** | macOS 14.x | The Apple Events consent dialog sometimes fails to appear when the target app is not in the foreground. | Ensure the target app is launched and visible before executing the AppleScript command. |
| **System Settings does not scroll to the correct app** | macOS 14.0-14.1 | Opening via URL scheme `x-apple.systempreferences:...` opens the correct pane but does not scroll to HushType in a long list. | User must manually scroll to find HushType in the alphabetical list. |
| **Permission revoked after macOS minor update** | macOS 14.x (intermittent) | macOS minor updates (e.g., 14.3 to 14.4) occasionally invalidate Accessibility permissions for non-App-Store apps. | Re-toggle the Accessibility permission after macOS updates. HushType detects this and shows a re-authorization alert (see [Section 3.6](#36-code-signature-invalidation)). |

---

## Related Documentation

- [Security](../security/SECURITY.md) -- Full security documentation including threat model, permissions analysis, and entitlements breakdown
- [Security: macOS Permissions & Entitlements](../security/SECURITY.md#6-macos-permissions--entitlements) -- Entitlement-level details and least-privilege analysis
- [Security: Text Injection Security](../security/SECURITY.md#5-text-injection-security) -- CGEvent and clipboard injection security properties
- [Legal Compliance](../security/LEGAL_COMPLIANCE.md) -- Privacy policy, data handling, and why no authentication is needed
- [Tech Stack: Text Injection](../architecture/TECH_STACK.md#text-injection) -- Technical deep dive into CGEvent vs Accessibility API
- [Tech Stack: Audio Pipeline](../architecture/TECH_STACK.md#audio-pipeline) -- AVAudioEngine configuration and microphone capture
- [Database Schema: UserDefaults Keys](../architecture/DATABASE_SCHEMA.md#userdefaults-keys) -- Permission-related UserDefaults keys (`hasRequestedAccessibility`, `hasRequestedMicrophone`)

---

*This document is part of the [HushType Documentation](../). For questions or corrections, please open an issue on the [GitHub repository](https://github.com/user/hushtype).*
