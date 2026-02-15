import Foundation
import os

// MARK: - Text Injection Protocol

/// Protocol for text injection strategies.
protocol TextInjecting: Sendable {
    /// Inject text using the specified method.
    /// - Parameters:
    ///   - text: The text to inject into the active application.
    ///   - method: The injection method to use.
    /// - Throws: TextInjectionError if injection fails.
    func inject(_ text: String, method: InjectionMethod) async throws
}

// MARK: - Text Injection Errors

enum TextInjectionError: Error, LocalizedError {
    case accessibilityNotGranted
    case eventCreationFailed
    case clipboardOperationFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityNotGranted:
            return "Accessibility permission not granted. Please enable it in System Settings."
        case .eventCreationFailed:
            return "Failed to create CGEvent for text injection."
        case .clipboardOperationFailed:
            return "Failed to perform clipboard operation."
        }
    }
}

// MARK: - Text Injection Service

/// Main text injection service that routes to appropriate injector based on method.
final class TextInjectionService: TextInjecting, @unchecked Sendable {
    // MARK: - Properties

    private let cgEventInjector: CGEventInjector
    private let clipboardInjector: ClipboardInjector
    private let permissionsManager: PermissionsManager

    /// Delay in milliseconds between simulated keystrokes (CGEvent mode).
    var keystrokeDelayMs: Int = 5

    // MARK: - Initialization

    init(permissionsManager: PermissionsManager, keystrokeDelayMs: Int = 5) {
        self.permissionsManager = permissionsManager
        self.cgEventInjector = CGEventInjector()
        self.clipboardInjector = ClipboardInjector()
        self.keystrokeDelayMs = keystrokeDelayMs
    }

    // MARK: - Text Injection

    func inject(_ text: String, method: InjectionMethod) async throws {
        Logger.injection.info("Starting text injection using method: \(method.rawValue)")

        permissionsManager.refreshAccessibilityStatus()
        let resolvedMethod = resolveMethod(for: text, preferred: method)
        Logger.injection.debug("Resolved injection method: \(String(describing: resolvedMethod))")

        switch resolvedMethod {
        case .cgEvent:
            // Check accessibility permission (refresh live — cached value may be stale)
            permissionsManager.refreshAccessibilityStatus()
            guard permissionsManager.accessibilityEnabled else {
                Logger.injection.error("CGEvent injection requires Accessibility permission")
                throw TextInjectionError.accessibilityNotGranted
            }

            try await cgEventInjector.inject(text, keystrokeDelay: keystrokeDelayMs)

        case .clipboard:
            try await clipboardInjector.inject(text)
        }

        Logger.injection.info("Text injection completed successfully")
    }

    // MARK: - Auto-Detection

    /// Determines the actual injection method to use based on the preferred method
    /// and text characteristics.
    private func resolveMethod(for text: String, preferred: InjectionMethod) -> ResolvedMethod {
        switch preferred {
        case .cgEvent:
            return .cgEvent
        case .clipboard:
            return .clipboard
        case .auto:
            // Prefer CGEvent for short ASCII text if accessibility is available,
            // otherwise fall back to clipboard
            if permissionsManager.accessibilityEnabled && text.count < 64 && text.allSatisfy({ $0.isASCII }) {
                Logger.injection.debug("Auto-detection: using CGEvent (short ASCII, accessibility granted)")
                return .cgEvent
            } else {
                Logger.injection.debug("Auto-detection: using clipboard")
                return .clipboard
            }
        }
    }
}

// MARK: - Resolved Method

/// Internal representation of resolved injection method.
private enum ResolvedMethod {
    case cgEvent
    case clipboard
}
