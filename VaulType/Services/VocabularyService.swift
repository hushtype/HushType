import os

/// A stateless service that applies vocabulary replacements to transcription text.
///
/// Per-app entries are applied before global entries, as they are more specific
/// to the current context.
struct VocabularyService {

    // MARK: - Public API

    /// Applies vocabulary replacements to the given text.
    ///
    /// - Parameters:
    ///   - text: The transcription text to process.
    ///   - globalEntries: Global vocabulary entries applied to all apps.
    ///   - appEntries: Per-app vocabulary entries for the active application.
    /// - Returns: The text with all matching vocabulary replacements applied.
    static func apply(
        to text: String,
        globalEntries: [VocabularyEntry],
        appEntries: [VocabularyEntry]
    ) -> String {
        var result = text
        var replacementCount = 0

        // Apply per-app entries first (more specific)
        for entry in appEntries {
            let updated = entry.apply(to: result)
            if updated != result {
                replacementCount += 1
                result = updated
            }
        }

        // Apply global entries second
        for entry in globalEntries {
            let updated = entry.apply(to: result)
            if updated != result {
                replacementCount += 1
                result = updated
            }
        }

        Logger.general.debug("VocabularyService: applied \(replacementCount) replacement(s) (appEntries: \(appEntries.count), globalEntries: \(globalEntries.count))")

        return result
    }
}
