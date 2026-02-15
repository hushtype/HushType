import AppKit
import Foundation
import SwiftData
import os

// MARK: - Dictation State

/// State machine for the dictation pipeline.
enum DictationState: Equatable {
    case idle
    case recording
    case transcribing
    case processing
    case injecting
    case error(String)

    var isActive: Bool {
        switch self {
        case .idle, .error: false
        case .recording, .transcribing, .processing, .injecting: true
        }
    }
}

// MARK: - DictationController

/// Orchestrates the full dictation pipeline:
/// hotkey → audio capture → VAD trim → whisper transcription → LLM processing → text injection → history save.
@Observable
final class DictationController: @unchecked Sendable {
    // MARK: - State

    private(set) var state: DictationState = .idle

    // MARK: - Services

    private let audioService: AudioCaptureService
    private let vad: VoiceActivityDetector
    private let whisperService: WhisperService
    private let injectionService: TextInjectionService
    private let hotkeyManager: HotkeyManager
    private var llmService: LLMService?
    private var processingRouter: ProcessingModeRouter?

    // MARK: - App State

    private let appState: AppState

    // MARK: - Configuration

    private var vadSensitivity: Float = 0.5
    private var injectionMethod: InjectionMethod = .auto
    private var pushToTalkEnabled: Bool = false
    private var playSoundEffects: Bool = true

    // MARK: - SwiftData (set after init)

    var modelContainer: ModelContainer?

    // MARK: - Initialization

    init(
        appState: AppState,
        audioService: AudioCaptureService = AudioCaptureService(),
        vad: VoiceActivityDetector = VoiceActivityDetector(),
        whisperService: WhisperService = WhisperService(),
        injectionService: TextInjectionService? = nil,
        hotkeyManager: HotkeyManager = HotkeyManager(),
        permissionsManager: PermissionsManager = PermissionsManager()
    ) {
        self.appState = appState
        self.audioService = audioService
        self.vad = vad
        self.whisperService = whisperService
        self.injectionService = injectionService ?? TextInjectionService(permissionsManager: permissionsManager)
        self.hotkeyManager = hotkeyManager

        setupHotkeyCallbacks()
        Logger.general.info("DictationController initialized")
    }

    // MARK: - Hotkey Setup

    private func setupHotkeyCallbacks() {
        hotkeyManager.onHotkeyDown = { [weak self] binding in
            guard let self else { return }
            Task { @MainActor in
                if self.pushToTalkEnabled {
                    // Push-to-talk: hold to record, release to stop
                    if self.state == .idle {
                        await self.startRecording(mode: binding.mode)
                    }
                } else {
                    // Toggle mode: press to start/stop
                    await self.toggleRecording(mode: binding.mode)
                }
            }
        }

        hotkeyManager.onHotkeyUp = { [weak self] binding in
            guard let self else { return }
            Task { @MainActor in
                if self.pushToTalkEnabled && self.state == .recording {
                    await self.stopRecordingAndProcess()
                }
                // Toggle mode: do nothing on key up
            }
        }
    }

    // MARK: - Lifecycle

    /// Start the controller — registers hotkeys and prepares services.
    func start(hotkey: String = "fn") throws {
        try hotkeyManager.loadFromSettings(hotkey: hotkey)
        try hotkeyManager.start()
        Logger.general.info("DictationController started")
    }

    /// Stop the controller — unregisters hotkeys and stops services.
    func stop() {
        hotkeyManager.stop()

        if state == .recording {
            Task {
                _ = await audioService.stopCapture()
            }
        }

        updateState(.idle)
        Logger.general.info("DictationController stopped")
    }

    // MARK: - Pipeline

    /// Toggle recording on/off (for toggle mode).
    @MainActor
    func toggleRecording(mode: ProcessingMode? = nil) async {
        switch state {
        case .idle:
            await startRecording(mode: mode)
        case .recording:
            await stopRecordingAndProcess()
        default:
            Logger.general.warning("Cannot toggle recording in state: \(String(describing: self.state))")
        }
    }

    /// Start recording audio.
    @MainActor
    func startRecording(mode: ProcessingMode? = nil) async {
        guard state == .idle else {
            Logger.general.warning("Cannot start recording — not idle (state: \(String(describing: self.state)))")
            return
        }

        if let mode {
            appState.activeMode = mode
        }

        updateState(.recording)
        playSound(.start)

        do {
            try await audioService.startCapture()
            Logger.general.info("Recording started (mode: \(self.appState.activeMode.displayName))")
        } catch {
            Logger.general.error("Failed to start recording: \(error.localizedDescription)")
            updateState(.error(error.localizedDescription))
            updateState(.idle)
        }
    }

    /// Stop recording and process the audio.
    @MainActor
    func stopRecordingAndProcess() async {
        guard state == .recording else {
            Logger.general.warning("Cannot stop recording — not recording")
            return
        }

        playSound(.stop)

        // Stop capture and get samples
        let rawSamples = await audioService.stopCapture()
        Logger.general.info("Captured \(rawSamples.count) raw samples")

        guard !rawSamples.isEmpty else {
            Logger.general.warning("No audio captured")
            updateState(.idle)
            return
        }

        // Trim silence with VAD
        var trimmedSamples = vad.trimSilence(from: rawSamples, sensitivity: vadSensitivity)
        guard !trimmedSamples.isEmpty else {
            Logger.general.info("No voice activity detected in recording")
            updateState(.idle)
            return
        }

        // Pad to minimum 1 second (16000 samples at 16kHz) — whisper requirement
        let minSamples = 16000
        if trimmedSamples.count < minSamples {
            trimmedSamples.append(contentsOf: [Float](repeating: 0, count: minSamples - trimmedSamples.count))
        }

        // Transcribe
        updateState(.transcribing)

        do {
            let result = try await whisperService.transcribe(samples: trimmedSamples)

            guard !result.text.isEmpty else {
                Logger.general.warning("Transcription returned empty text")
                updateState(.idle)
                return
            }

            Logger.general.info("Transcription: \"\(result.text.prefix(80))...\"")

            // LLM processing (if mode requires it)
            let rawText = result.text
            var outputText = rawText

            if appState.activeMode.requiresLLM, let router = processingRouter {
                updateState(.processing)
                do {
                    outputText = try await router.process(
                        text: rawText,
                        mode: appState.activeMode
                    )
                    Logger.general.info("LLM processed: \(outputText.count) chars")
                } catch {
                    Logger.general.warning("LLM processing failed, using raw text: \(error.localizedDescription)")
                    outputText = rawText
                }
            }

            // Inject text
            updateState(.injecting)
            try await injectionService.inject(outputText, method: injectionMethod)

            // Save history entry
            let frontmostApp = NSWorkspace.shared.frontmostApplication
            let processedText = (outputText != rawText) ? outputText : nil
            await saveDictationEntry(
                rawText: rawText,
                processedText: processedText,
                language: result.language,
                audioDuration: result.audioDuration,
                appBundleIdentifier: frontmostApp?.bundleIdentifier,
                appName: frontmostApp?.localizedName
            )

            // Update preview
            appState.lastTranscriptionPreview = outputText
            Logger.general.info("Dictation complete: \(outputText.count) chars injected")

        } catch {
            Logger.general.error("Pipeline error: \(error.localizedDescription)")
            appState.currentError = error.localizedDescription
        }

        updateState(.idle)
    }

    // MARK: - State Management

    @MainActor
    private func updateState(_ newState: DictationState) {
        state = newState

        switch newState {
        case .idle:
            appState.isRecording = false
            appState.isProcessing = false
            appState.currentError = nil
        case .recording:
            appState.isRecording = true
            appState.isProcessing = false
        case .transcribing, .processing, .injecting:
            appState.isRecording = false
            appState.isProcessing = true
        case .error(let message):
            appState.isRecording = false
            appState.isProcessing = false
            appState.currentError = message
        }
    }

    // MARK: - Model Loading

    /// Load the whisper model by file name.
    /// - Parameter fileName: Model file name (e.g., "ggml-base.en.bin").
    func loadWhisperModel(fileName: String) async {
        let modelRef = ModelInfoRef(fileName: fileName, type: "whisper")
        let path = modelRef.filePath

        guard FileManager.default.fileExists(atPath: path.path) else {
            Logger.general.warning("Whisper model not found at \(path.path) — transcription will fail until model is downloaded")
            return
        }

        do {
            try await whisperService.loadModel(at: path)
            Logger.general.info("Whisper model loaded: \(fileName)")
        } catch {
            Logger.general.error("Failed to load whisper model: \(error.localizedDescription)")
        }
    }

    // MARK: - LLM Setup

    /// Configure the LLM service and processing router.
    func setLLMService(_ service: LLMService) {
        self.llmService = service
        self.processingRouter = ProcessingModeRouter(llmService: service)
        Logger.general.info("LLM service configured for pipeline")
    }

    /// Load an LLM model by file name.
    func loadLLMModel(fileName: String) async {
        let modelRef = ModelInfoRef(fileName: fileName, type: "llm")
        let path = modelRef.filePath

        guard FileManager.default.fileExists(atPath: path.path) else {
            Logger.general.warning("LLM model not found at \(path.path)")
            return
        }

        guard let service = llmService else {
            Logger.general.warning("No LLM service — cannot load model")
            return
        }

        do {
            try await service.loadModel(at: path.path)
            Logger.general.info("LLM model loaded: \(fileName)")
        } catch {
            Logger.general.error("Failed to load LLM model: \(error.localizedDescription)")
        }
    }

    // MARK: - Configuration

    /// Reload the hotkey binding from a serialized string (e.g. "cmd+shift+d").
    func reloadHotkey(_ hotkey: String) throws {
        try hotkeyManager.loadFromSettings(hotkey: hotkey)
        Logger.general.info("Hotkey reloaded: \(hotkey)")
    }

    /// Update settings from UserSettings.
    func updateConfiguration(
        vadSensitivity: Float,
        injectionMethod: InjectionMethod,
        keystrokeDelayMs: Int = 5,
        pushToTalkEnabled: Bool = false,
        playSoundEffects: Bool = true,
        audioInputDeviceID: String? = nil,
        useGPUAcceleration: Bool = true,
        whisperThreadCount: Int = 0
    ) {
        self.vadSensitivity = vadSensitivity
        self.injectionMethod = injectionMethod
        self.injectionService.keystrokeDelayMs = keystrokeDelayMs
        self.pushToTalkEnabled = pushToTalkEnabled
        self.playSoundEffects = playSoundEffects
        self.audioService.setInputDevice(id: audioInputDeviceID)
        self.whisperService.useGPU = useGPUAcceleration
        self.whisperService.threadCount = whisperThreadCount
    }

    // MARK: - Sound Effects

    private enum SoundEvent {
        case start, stop
    }

    private func playSound(_ event: SoundEvent) {
        guard playSoundEffects else { return }
        switch event {
        case .start:
            NSSound(named: "Tink")?.play()
        case .stop:
            NSSound(named: "Pop")?.play()
        }
    }

    // MARK: - History

    @MainActor
    private func saveDictationEntry(
        rawText: String,
        processedText: String? = nil,
        language: String,
        audioDuration: TimeInterval,
        appBundleIdentifier: String?,
        appName: String?
    ) async {
        guard let container = modelContainer else {
            Logger.general.warning("No ModelContainer — skipping history save")
            return
        }

        let context = ModelContext(container)
        let outputText = processedText ?? rawText
        let wordCount = outputText.split(separator: " ").count

        // Load privacy settings
        let settings = try? UserSettings.shared(in: context)
        let storeText = settings?.storeTranscriptionText ?? true

        let entry = DictationEntry(
            rawText: storeText ? rawText : "",
            processedText: storeText ? processedText : nil,
            mode: appState.activeMode,
            language: language,
            appBundleIdentifier: appBundleIdentifier,
            appName: appName,
            audioDuration: audioDuration,
            wordCount: wordCount
        )

        context.insert(entry)

        do {
            try context.save()
            Logger.general.info("DictationEntry saved (\(wordCount) words, \(String(format: "%.1f", audioDuration))s, text stored: \(storeText))")
        } catch {
            Logger.general.error("Failed to save DictationEntry: \(error.localizedDescription)")
        }

        // Enforce retention policies
        enforceHistoryLimits(in: context, settings: settings)
    }

    @MainActor
    private func enforceHistoryLimits(in context: ModelContext, settings: UserSettings?) {
        let maxEntries = settings?.maxHistoryEntries ?? 5000
        let retentionDays = settings?.historyRetentionDays ?? 90

        do {
            // Purge entries exceeding max count (oldest first)
            if maxEntries > 0 {
                let allEntries = FetchDescriptor<DictationEntry>(
                    sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
                )
                let entries = try context.fetch(allEntries)
                if entries.count > maxEntries {
                    for entry in entries.dropFirst(maxEntries) {
                        context.delete(entry)
                    }
                    Logger.general.info("Purged \(entries.count - maxEntries) old history entries (max: \(maxEntries))")
                }
            }

            // Delete entries older than retention period
            if retentionDays > 0 {
                let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
                let expiredDescriptor = FetchDescriptor<DictationEntry>(
                    predicate: #Predicate { $0.timestamp < cutoff }
                )
                let expired = try context.fetch(expiredDescriptor)
                for entry in expired {
                    context.delete(entry)
                }
                if !expired.isEmpty {
                    Logger.general.info("Purged \(expired.count) expired history entries (retention: \(retentionDays) days)")
                }
            }

            try context.save()
        } catch {
            Logger.general.error("Failed to enforce history limits: \(error.localizedDescription)")
        }
    }
}
