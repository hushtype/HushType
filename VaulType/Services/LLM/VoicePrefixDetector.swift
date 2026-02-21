import Foundation
import os

/// Detects mode-switching voice prefixes at the start of transcribed text.
/// When a user says "code mode: print hello world", this strips the prefix
/// and switches to the appropriate ProcessingMode.
struct VoicePrefixDetector {
    /// Result of prefix detection.
    struct DetectionResult {
        let mode: ProcessingMode
        let strippedText: String
    }

    /// Mapping of spoken phrases to processing modes.
    /// Ordered longest-first so "clean this up" matches before "clean".
    private static let prefixes: [(phrase: String, mode: ProcessingMode)] = [
        ("clean this up", .clean),
        ("clean mode", .clean),
        ("clean text", .clean),
        ("structure mode", .structure),
        ("structured mode", .structure),
        ("structured notes", .structure),
        ("note mode", .structure),
        ("notes mode", .structure),
        ("code mode", .code),
        ("coding mode", .code),
        ("prompt mode", .prompt),
        ("template mode", .prompt),
        ("email mode", .prompt),
        ("custom mode", .custom),
        ("raw mode", .raw),
        ("dictation mode", .raw),
        ("raw text", .raw),
    ]

    /// Detect a mode-switching prefix in the transcription.
    /// - Parameter text: Raw transcription text from whisper.
    /// - Returns: Detection result with mode and stripped text, or nil if no prefix found.
    static func detect(in text: String) -> DetectionResult? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()

        for (phrase, mode) in prefixes {
            if lowered.hasPrefix(phrase) {
                let afterPrefix = trimmed.dropFirst(phrase.count)
                let stripped = stripLeadingSeparators(String(afterPrefix))

                guard !stripped.isEmpty else {
                    // Prefix only, no actual content — skip detection
                    return nil
                }

                Logger.general.info("Voice prefix detected: \"\(phrase)\" → \(mode.rawValue)")
                return DetectionResult(mode: mode, strippedText: stripped)
            }
        }

        return nil
    }

    /// Remove leading punctuation, whitespace, and common separator patterns
    /// that whisper may insert between the prefix and content.
    private static func stripLeadingSeparators(_ text: String) -> String {
        var result = text
        // Strip leading colons, commas, periods, dashes, whitespace
        let separators = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ":,.-"))
        while let first = result.unicodeScalars.first, separators.contains(first) {
            result = String(result.dropFirst())
        }
        return result
    }
}
