import Foundation
import SwiftData

@Model
final class DictationEntry {
    // MARK: - Identity

    /// Unique identifier for this entry.
    @Attribute(.unique)
    var id: UUID

    // MARK: - Content

    /// Raw transcription text from whisper.cpp before any post-processing.
    var rawText: String

    /// Post-processed text after LLM processing, or nil if mode is .raw.
    var processedText: String?

    /// The processing mode used for this transcription.
    var mode: ProcessingMode

    /// BCP-47 language code of the detected or selected language (e.g., "en", "tr").
    var language: String

    // MARK: - Target Application Context

    /// Bundle identifier of the app that was focused when dictation occurred.
    var appBundleIdentifier: String?

    /// Display name of the focused application.
    var appName: String?

    // MARK: - Metrics

    /// Duration of the audio recording in seconds.
    var audioDuration: TimeInterval

    /// Number of words in the final output text (processedText ?? rawText).
    var wordCount: Int

    // MARK: - Metadata

    /// When this transcription was created.
    var timestamp: Date

    /// Whether the user has marked this entry as a favorite.
    var isFavorite: Bool

    // MARK: - Initializer

    init(
        id: UUID = UUID(),
        rawText: String,
        processedText: String? = nil,
        mode: ProcessingMode = .raw,
        language: String = "en",
        appBundleIdentifier: String? = nil,
        appName: String? = nil,
        audioDuration: TimeInterval = 0,
        wordCount: Int = 0,
        timestamp: Date = .now,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.rawText = rawText
        self.processedText = processedText
        self.mode = mode
        self.language = language
        self.appBundleIdentifier = appBundleIdentifier
        self.appName = appName
        self.audioDuration = audioDuration
        self.wordCount = wordCount
        self.timestamp = timestamp
        self.isFavorite = isFavorite
    }

    // MARK: - Computed Properties

    /// The text that was actually delivered to the target application.
    var outputText: String {
        processedText ?? rawText
    }

    /// Words per minute based on audio duration.
    var wordsPerMinute: Double {
        guard audioDuration > 0 else { return 0 }
        return Double(wordCount) / (audioDuration / 60.0)
    }
}
