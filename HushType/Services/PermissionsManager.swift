import AppKit
import Observation

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
}
