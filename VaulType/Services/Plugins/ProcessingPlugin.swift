import Foundation

/// A plugin that transforms text in the dictation pipeline.
///
/// Processing plugins are called after whisper transcription and before
/// text injection. They can modify, format, or enhance the transcribed text.
///
/// Multiple processing plugins can be active simultaneously. They are
/// applied in the order they were activated. Each plugin receives the
/// output of the previous plugin.
///
/// Example usage:
/// ```swift
/// class AutoCapitalizePlugin: ProcessingPlugin {
///     let identifier = "com.example.auto-capitalize"
///     let displayName = "Auto Capitalize"
///     let version = "1.0.0"
///
///     func activate() throws {}
///     func deactivate() throws {}
///
///     func process(text: String, context: ProcessingContext) async throws -> String {
///         text.capitalized
///     }
/// }
/// ```
protocol ProcessingPlugin: VaulTypePlugin {
    /// Transform text in the dictation pipeline.
    ///
    /// - Parameters:
    ///   - text: Input text (raw transcription or output from previous plugin).
    ///   - context: Metadata about the current dictation session.
    /// - Returns: Transformed text to pass to the next stage.
    /// - Throws: If processing fails. The pipeline will use the input text as fallback.
    func process(text: String, context: ProcessingContext) async throws -> String

    /// Processing modes this plugin applies to. Empty means all modes.
    var applicableModes: Set<ProcessingMode> { get }

    /// Priority for ordering among multiple active processing plugins.
    /// Lower values run first. Default is 100.
    var priority: Int { get }
}

// MARK: - Default Implementations

extension ProcessingPlugin {
    var applicableModes: Set<ProcessingMode> { [] }
    var priority: Int { 100 }
}

// MARK: - Processing Context

/// Metadata about the current dictation session, passed to processing plugins.
struct ProcessingContext: Sendable {
    /// The processing mode selected for this dictation.
    let mode: ProcessingMode

    /// BCP-47 language code detected by whisper (e.g., "en", "de").
    let detectedLanguage: String?

    /// Bundle identifier of the app that was active when recording started.
    let sourceBundleIdentifier: String?

    /// Name of the app that was active when recording started.
    let sourceAppName: String?

    /// Duration of the audio recording in seconds.
    let recordingDuration: TimeInterval
}
