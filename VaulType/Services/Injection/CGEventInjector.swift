import CoreGraphics
import Foundation
import os

/// Injects text by simulating keyboard events via CGEvent.
/// Supports Unicode characters including emoji, CJK, and diacritics.
final class CGEventInjector: @unchecked Sendable {
    // MARK: - Text Injection

    /// Inject text by simulating keystrokes for each character.
    /// - Parameters:
    ///   - text: The text to inject.
    ///   - keystrokeDelay: Delay in milliseconds between keystrokes.
    /// - Throws: TextInjectionError if event creation fails.
    func inject(_ text: String, keystrokeDelay: Int) async throws {
        Logger.injection.info("CGEvent injection started for \(text.count) characters")

        // Create a CGEventSource with combined session state
        guard let eventSource = CGEventSource(stateID: .combinedSessionState) else {
            Logger.injection.error("Failed to create CGEventSource")
            throw TextInjectionError.eventCreationFailed
        }

        // Process each character
        for character in text {
            try await injectCharacter(character, eventSource: eventSource)

            // Apply keystroke delay if specified
            if keystrokeDelay > 0 {
                try await Task.sleep(for: .milliseconds(keystrokeDelay))
            }
        }

        Logger.injection.info("CGEvent injection completed")
    }

    // MARK: - Character Injection

    /// Inject a single character using CGEvent keyboard API.
    private func injectCharacter(_ character: Character, eventSource: CGEventSource) async throws {
        // Convert character to UTF-16 code units
        let utf16CodeUnits = Array(character.utf16)

        // Create keyboard event
        guard let keyDownEvent = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true) else {
            Logger.injection.error("Failed to create key down event for character: \(character)")
            throw TextInjectionError.eventCreationFailed
        }

        guard let keyUpEvent = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: false) else {
            Logger.injection.error("Failed to create key up event for character: \(character)")
            throw TextInjectionError.eventCreationFailed
        }

        // Set Unicode string for the key event
        keyDownEvent.keyboardSetUnicodeString(stringLength: utf16CodeUnits.count, unicodeString: utf16CodeUnits)
        keyUpEvent.keyboardSetUnicodeString(stringLength: utf16CodeUnits.count, unicodeString: utf16CodeUnits)

        // Post the events
        keyDownEvent.post(tap: .cghidEventTap)
        keyUpEvent.post(tap: .cghidEventTap)
    }
}
