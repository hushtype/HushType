import Foundation
import SwiftData

@Model
final class UserSettings {
    // MARK: - Identity

    /// Singleton identifier — always "default".
    @Attribute(.unique)
    var id: String

    // MARK: - Model Selection

    /// File name of the currently selected whisper.cpp model.
    var selectedWhisperModel: String

    /// File name of the currently selected llama.cpp model.
    var selectedLLMModel: String?

    // MARK: - Input Configuration

    /// Global keyboard shortcut for toggling dictation (serialized).
    /// Format: modifiers+keyCode (e.g., "cmd+shift+space").
    var globalHotkey: String

    /// Whether push-to-talk mode is enabled (hold to record, release to stop).
    /// When false, toggle mode is used (press to start, press to stop).
    var pushToTalkEnabled: Bool

    /// Audio input device identifier. Nil means use system default.
    var audioInputDeviceID: String?

    // MARK: - Processing Defaults

    /// Default processing mode applied when no AppProfile override exists.
    var defaultMode: ProcessingMode

    /// Default BCP-47 language code for transcription.
    var defaultLanguage: String

    /// Whether to auto-detect the spoken language (overrides defaultLanguage).
    var autoDetectLanguage: Bool

    // MARK: - UI Preferences

    /// Launch HushType at macOS login.
    var launchAtLogin: Bool

    /// Show the HushType icon in the menu bar.
    var showMenuBarIcon: Bool

    /// Show a floating indicator while recording.
    var showRecordingIndicator: Bool

    /// Play audio feedback when recording starts/stops.
    var playSoundEffects: Bool

    // MARK: - History & Privacy

    /// Maximum number of DictationEntry records to retain.
    /// 0 means unlimited. Oldest entries are purged first.
    var maxHistoryEntries: Int

    /// Number of days to retain DictationEntry records.
    /// 0 means indefinite retention.
    var historyRetentionDays: Int

    /// Whether to store the raw transcription text in history.
    /// When false, only metadata (duration, word count, timestamp) is kept.
    var storeTranscriptionText: Bool

    // MARK: - Performance

    /// Number of CPU threads for whisper.cpp inference.
    /// 0 means auto-detect (use physical core count).
    var whisperThreadCount: Int

    /// Whether to use Metal GPU acceleration for whisper.cpp.
    var useGPUAcceleration: Bool

    /// Maximum context length (tokens) for LLM inference.
    var llmContextLength: Int

    // MARK: - Text Injection

    /// Default text injection method when no AppProfile override exists.
    var defaultInjectionMethod: InjectionMethod

    /// Delay in milliseconds between simulated keystrokes (CGEvent mode).
    var keystrokeDelay: Int

    // MARK: - Initializer

    init(
        id: String = "default",
        selectedWhisperModel: String = "ggml-base.en.bin",
        selectedLLMModel: String? = nil,
        globalHotkey: String = "cmd+shift+space",
        pushToTalkEnabled: Bool = false,
        audioInputDeviceID: String? = nil,
        defaultMode: ProcessingMode = .clean,
        defaultLanguage: String = "en",
        autoDetectLanguage: Bool = false,
        launchAtLogin: Bool = false,
        showMenuBarIcon: Bool = true,
        showRecordingIndicator: Bool = true,
        playSoundEffects: Bool = true,
        maxHistoryEntries: Int = 5000,
        historyRetentionDays: Int = 90,
        storeTranscriptionText: Bool = true,
        whisperThreadCount: Int = 0,
        useGPUAcceleration: Bool = true,
        llmContextLength: Int = 2048,
        defaultInjectionMethod: InjectionMethod = .auto,
        keystrokeDelay: Int = 5
    ) {
        self.id = id
        self.selectedWhisperModel = selectedWhisperModel
        self.selectedLLMModel = selectedLLMModel
        self.globalHotkey = globalHotkey
        self.pushToTalkEnabled = pushToTalkEnabled
        self.audioInputDeviceID = audioInputDeviceID
        self.defaultMode = defaultMode
        self.defaultLanguage = defaultLanguage
        self.autoDetectLanguage = autoDetectLanguage
        self.launchAtLogin = launchAtLogin
        self.showMenuBarIcon = showMenuBarIcon
        self.showRecordingIndicator = showRecordingIndicator
        self.playSoundEffects = playSoundEffects
        self.maxHistoryEntries = maxHistoryEntries
        self.historyRetentionDays = historyRetentionDays
        self.storeTranscriptionText = storeTranscriptionText
        self.whisperThreadCount = whisperThreadCount
        self.useGPUAcceleration = useGPUAcceleration
        self.llmContextLength = llmContextLength
        self.defaultInjectionMethod = defaultInjectionMethod
        self.keystrokeDelay = keystrokeDelay
    }

    // MARK: - Singleton Access

    /// Fetches the singleton UserSettings, creating a default instance if needed.
    @MainActor
    static func shared(in context: ModelContext) throws -> UserSettings {
        let descriptor = FetchDescriptor<UserSettings>(
            predicate: #Predicate { $0.id == "default" }
        )

        if let existing = try context.fetch(descriptor).first {
            return existing
        }

        let settings = UserSettings()
        context.insert(settings)
        return settings
    }
}
