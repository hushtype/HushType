import AppKit
import AVFoundation
import Observation
import os

@Observable
final class PermissionsManager {
    // MARK: - State

    /// Whether accessibility access has been granted.
    private(set) var accessibilityEnabled: Bool = AXIsProcessTrusted()

    // MARK: - Accessibility

    /// Check the current accessibility permission state.
    func refreshAccessibilityStatus() {
        accessibilityEnabled = AXIsProcessTrusted()
    }

    // MARK: - Microphone

    /// Request microphone access (shows system dialog).
    func requestMicrophoneAccess() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Logger.general.info("Microphone access \(granted ? "granted" : "denied")")
        }
    }

    // MARK: - Accessibility Settings

    /// Open System Settings to the Accessibility pane.
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
