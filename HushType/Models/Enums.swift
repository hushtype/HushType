import Foundation

// MARK: - Processing Mode

/// Defines how transcribed text is post-processed before injection.
enum ProcessingMode: String, Codable, CaseIterable, Identifiable {
    /// Raw transcription output — no post-processing applied.
    case raw

    /// Clean up punctuation, capitalization, and filler words.
    case clean

    /// Structure into paragraphs, lists, or headings based on content.
    case structure

    /// Apply a user-defined LLM prompt template.
    case prompt

    /// Optimize output for code — variable names, syntax, formatting.
    case code

    /// Fully custom pipeline with user-defined pre/post processors.
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .raw: "Raw Transcription"
        case .clean: "Clean Text"
        case .structure: "Structured Output"
        case .prompt: "Prompt Template"
        case .code: "Code Mode"
        case .custom: "Custom Pipeline"
        }
    }

    var description: String {
        switch self {
        case .raw: "Unprocessed whisper output exactly as transcribed"
        case .clean: "Removes filler words, fixes punctuation and capitalization"
        case .structure: "Organizes text into paragraphs, lists, or headings"
        case .prompt: "Processes text through a custom LLM prompt template"
        case .code: "Optimized for dictating source code and technical content"
        case .custom: "User-defined processing pipeline with custom rules"
        }
    }

    /// Whether this mode requires the LLM engine to be loaded.
    var requiresLLM: Bool {
        switch self {
        case .raw: false
        case .clean, .structure, .prompt, .code, .custom: true
        }
    }
}

// MARK: - Model Type

/// Categorizes ML models used by HushType.
enum ModelType: String, Codable, CaseIterable, Identifiable {
    /// Whisper speech-to-text model (whisper.cpp compatible).
    case whisper

    /// Large language model for post-processing (llama.cpp compatible).
    case llm

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .whisper: "Speech-to-Text (Whisper)"
        case .llm: "Language Model (LLM)"
        }
    }

    /// File extension expected for this model type.
    var expectedExtension: String {
        switch self {
        case .whisper: "bin"
        case .llm: "gguf"
        }
    }

    /// Directory name within the app's model storage.
    var storageDirectory: String {
        switch self {
        case .whisper: "whisper-models"
        case .llm: "llm-models"
        }
    }
}

// MARK: - Injection Method

/// How transcribed text is injected into the target application.
enum InjectionMethod: String, Codable, CaseIterable, Identifiable {
    /// Simulate keyboard events via CGEvent (most compatible, requires
    /// Accessibility permission).
    case cgEvent

    /// Copy to clipboard and paste via Cmd+V (fallback for apps that
    /// block synthetic keyboard events).
    case clipboard

    /// Automatically detect the best method for the target app.
    case auto

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cgEvent: "Keyboard Simulation (CGEvent)"
        case .clipboard: "Clipboard Paste"
        case .auto: "Automatic Detection"
        }
    }

    var description: String {
        switch self {
        case .cgEvent:
            "Simulates keystrokes directly — preserves clipboard contents "
            + "but requires Accessibility permission"
        case .clipboard:
            "Copies text to clipboard and pastes — works everywhere but "
            + "overwrites clipboard contents"
        case .auto:
            "Tries CGEvent first, falls back to clipboard if the target "
            + "app blocks synthetic events"
        }
    }
}
