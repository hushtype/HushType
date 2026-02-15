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
    case injecting
    case error(String)

    var isActive: Bool {
        switch self {
        case .idle, .error: false
        case .recording, .transcribing, .injecting: true
        }
    }
}

// MARK: - DictationController

/// Orchestrates the full dictation pipeline:
/// hotkey → audio capture → VAD trim → whisper transcription → text injection → history save.
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

    // MARK: - App State

    private let appState: AppState

    // MARK: - Configuration

    private var vadSensitivity: Float = 0.5
    private var injectionMethod: InjectionMethod = .auto

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
                if self.state == .idle {
                    await self.startRecording(mode: binding.mode)
                }
            }
        }

        hotkeyManager.onHotkeyUp = { [weak self] binding in
            guard let self else { return }
            Task { @MainActor in
                if self.state == .recording {
                    await self.stopRecordingAndProcess()
                }
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

            // Inject text
            updateState(.injecting)
            try await injectionService.inject(result.text, method: injectionMethod)

            // Save history entry
            let frontmostApp = NSWorkspace.shared.frontmostApplication
            await saveDictationEntry(
                rawText: result.text,
                language: result.language,
                audioDuration: result.audioDuration,
                appBundleIdentifier: frontmostApp?.bundleIdentifier,
                appName: frontmostApp?.localizedName
            )

            // Update preview
            appState.lastTranscriptionPreview = result.text
            Logger.general.info("Dictation complete: \(result.text.count) chars injected")

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
        case .transcribing, .injecting:
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

    // MARK: - Configuration

    /// Update settings from UserSettings.
    func updateConfiguration(
        vadSensitivity: Float,
        injectionMethod: InjectionMethod,
        keystrokeDelayMs: Int = 5
    ) {
        self.vadSensitivity = vadSensitivity
        self.injectionMethod = injectionMethod
        self.injectionService.keystrokeDelayMs = keystrokeDelayMs
    }

    // MARK: - History

    @MainActor
    private func saveDictationEntry(
        rawText: String,
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
        let wordCount = rawText.split(separator: " ").count

        let entry = DictationEntry(
            rawText: rawText,
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
            Logger.general.info("DictationEntry saved (\(wordCount) words, \(String(format: "%.1f", audioDuration))s)")
        } catch {
            Logger.general.error("Failed to save DictationEntry: \(error.localizedDescription)")
        }
    }
}
