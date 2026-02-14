import AppKit
import AVFoundation
import Observation
import os

@Observable
final class PermissionsManager {
    // MARK: - State

    /// Current microphone authorization status.
    private(set) var microphoneStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)

    /// Whether accessibility access has been granted.
    private(set) var accessibilityEnabled: Bool = AXIsProcessTrusted()

    // MARK: - Computed Properties

    /// Whether all required permissions are granted.
    var allPermissionsGranted: Bool {
        microphoneStatus == .authorized && accessibilityEnabled
    }

    // MARK: - Microphone

    /// Request microphone access. Updates `microphoneStatus` on completion.
    func requestMicrophoneAccess() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        await MainActor.run {
            microphoneStatus = granted ? .authorized : .denied
        }
        Logger.audio.info("Microphone access \(granted ? "granted" : "denied")")
    }

    /// Refresh the current microphone authorization status.
    func refreshMicrophoneStatus() {
        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    }

    // MARK: - Accessibility

    /// Check the current accessibility permission state.
    func refreshAccessibilityStatus() {
        accessibilityEnabled = AXIsProcessTrusted()
    }

    /// Open System Settings to the Accessibility pane so the user can grant access.
    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            Logger.general.error("Failed to create Accessibility settings URL")
            return
        }
        NSWorkspace.shared.open(url)
        Logger.general.info("Opened System Settings > Accessibility")
    }

    /// Open System Settings to the Microphone pane.
    func openMicrophoneSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
            Logger.general.error("Failed to create Microphone settings URL")
            return
        }
        NSWorkspace.shared.open(url)
        Logger.general.info("Opened System Settings > Microphone")
    }

    // MARK: - Polling

    /// Start polling accessibility status at the given interval.
    /// Accessibility has no callback API, so polling is required.
    func startAccessibilityPolling(interval: TimeInterval = 2.0) async {
        while !Task.isCancelled {
            refreshAccessibilityStatus()
            try? await Task.sleep(for: .seconds(interval))
        }
    }
}
