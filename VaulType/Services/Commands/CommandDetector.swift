import Foundation
import os

/// Detects voice commands by checking for a wake phrase prefix in transcribed text.
/// When a user says "Hey Type, open Safari", this strips the wake phrase and returns
/// the command portion ("open Safari") for parsing.
struct CommandDetector {
    /// Result of wake phrase detection.
    struct DetectionResult {
        /// The command text after the wake phrase has been stripped.
        let commandText: String
    }

    /// Detect a wake phrase prefix in the transcription.
    /// - Parameters:
    ///   - text: Raw transcription text from whisper (after vocabulary replacements).
    ///   - wakePhrase: The wake phrase to detect (e.g., "Hey Type", "Computer").
    /// - Returns: Detection result with command text, or nil if no wake phrase found.
    static func detect(
        in text: String,
        wakePhrase: String = "Hey Type"
    ) -> DetectionResult? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !wakePhrase.isEmpty else { return nil }

        let lowered = trimmed.lowercased()
        let lowerPhrase = wakePhrase.lowercased()

        // Exact prefix match (case-insensitive)
        guard lowered.hasPrefix(lowerPhrase) else { return nil }

        // Strip the wake phrase and any trailing separators
        let afterPrefix = trimmed.dropFirst(wakePhrase.count)
        let commandText = stripLeadingSeparators(String(afterPrefix))

        // Wake phrase only, no command text — not a valid command
        guard !commandText.isEmpty else { return nil }

        Logger.commands.info("Wake phrase detected: \"\(wakePhrase)\", command: \"\(commandText)\"")
        return DetectionResult(commandText: commandText)
    }

    /// Remove leading punctuation, whitespace, and common separator patterns
    /// that whisper may insert between the wake phrase and command.
    private static func stripLeadingSeparators(_ text: String) -> String {
        var result = text
        let separators = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ":,.-"))
        while let first = result.unicodeScalars.first, separators.contains(first) {
            result = String(result.dropFirst())
        }
        return result
    }
}
