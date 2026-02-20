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
    private var appContextService: AppContextService?
    private var commandParser: CommandParser?
    private var commandExecutor: CommandExecutor?
    private var commandRegistry: CommandRegistry?

    // MARK: - App State

    private let appState: AppState

    // MARK: - Configuration

    private var vadSensitivity: Float = 0.5
    private var injectionMethod: InjectionMethod = .auto
    private var pushToTalkEnabled: Bool = false
    private var defaultMode: ProcessingMode = .raw
    private var playSoundEffects: Bool = true
    private var autoDetectLanguage: Bool = false
    private var defaultLanguage: String = "en"
    private var showOverlayEnabled: Bool = true
    private var commandsEnabled: Bool = true
    private var commandWakePhrase: String = "Hey Type"

    // Per-recording snapshots (captured at startRecording to avoid mid-recording app-switch race)
    private var recordingInjectionMethod: InjectionMethod = .auto
    private var recordingBundleIdentifier: String?
    private var recordingAppName: String?

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

        // Resolve per-app profile overrides and snapshot state before recording
        resolveAppProfileOverrides()
        recordingInjectionMethod = activeInjectionMethod
        recordingBundleIdentifier = appContextService?.currentBundleIdentifier
            ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        recordingAppName = appContextService?.currentAppName
            ?? NSWorkspace.shared.frontmostApplication?.localizedName

        appState.activeMode = mode ?? activeMode

        updateState(.recording)
        playSound(.start)

        do {
            try await audioService.startCapture()
            Logger.general.info("Recording started (mode: \(self.appState.activeMode.displayName))")
        } catch {
            Logger.general.error("Failed to start recording: \(error.localizedDescription)")
            updateState(.error(error.localizedDescription))
            // Delay idle transition so the error is observable by the UI
            try? await Task.sleep(for: .seconds(3))
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

            Logger.general.info("Transcription: \(result.text)")

            // Update detected language in app state
            appState.detectedLanguage = result.language

            // Voice prefix detection — switch mode if user said "code mode:", "clean this up:", etc.
            var rawText = result.text
            if let detection = VoicePrefixDetector.detect(in: rawText) {
                appState.activeMode = detection.mode
                rawText = detection.strippedText
                Logger.general.info("Voice prefix switched to \(detection.mode.rawValue), stripped text: \(rawText.count) chars")
            }

            // Vocabulary replacements (per-app first, then global)
            if let container = modelContainer {
                let vocabContext = ModelContext(container)
                let appEntries = appContextService?.currentProfile?.vocabularyEntries ?? []
                let globalDescriptor = FetchDescriptor<VocabularyEntry>(
                    predicate: #Predicate { $0.isGlobal }
                )
                let globalEntries = (try? vocabContext.fetch(globalDescriptor)) ?? []
                if !appEntries.isEmpty || !globalEntries.isEmpty {
                    rawText = VocabularyService.apply(to: rawText, globalEntries: globalEntries, appEntries: appEntries)
                }
            }

            // Voice command detection (after vocabulary, before LLM)
            if commandsEnabled,
               let detection = CommandDetector.detect(
                   in: rawText,
                   wakePhrase: commandWakePhrase
               ) {
                Logger.commands.info("Wake phrase detected, command: \(detection.commandText)")
                await handleVoiceCommand(detection.commandText)
                updateState(.idle)
                return
            }

            // LLM processing (if mode requires it)
            var outputText = rawText

            let activeMode = self.appState.activeMode
            if activeMode.requiresLLM, let router = processingRouter {
                updateState(.processing)
                Logger.general.info("LLM input [\(activeMode.rawValue)]: \(rawText)")

                // Fetch appropriate PromptTemplate for prompt/custom modes
                var template: PromptTemplate?
                if (activeMode == .prompt || activeMode == .custom),
                   let container = modelContainer {
                    let ctx = ModelContext(container)
                    let targetModeRaw = activeMode.rawValue
                    var desc = FetchDescriptor<PromptTemplate>(
                        predicate: #Predicate<PromptTemplate> { $0.mode.rawValue == targetModeRaw && $0.isDefault }
                    )
                    desc.fetchLimit = 1
                    template = try? ctx.fetch(desc).first

                    // Fallback: any template matching this mode
                    if template == nil {
                        var fallback = FetchDescriptor<PromptTemplate>(
                            predicate: #Predicate<PromptTemplate> { $0.mode.rawValue == targetModeRaw }
                        )
                        fallback.fetchLimit = 1
                        template = try? ctx.fetch(fallback).first
                    }

                    if let tmpl = template {
                        Logger.general.info("Using template '\(tmpl.name)' for \(activeMode.rawValue) mode")
                    }
                }

                do {
                    outputText = try await router.process(
                        text: rawText,
                        mode: activeMode,
                        template: template,
                        detectedLanguage: result.language
                    )
                    Logger.general.info("LLM output [\(activeMode.rawValue)]: \(outputText)")
                } catch {
                    Logger.general.warning("LLM processing failed, using raw text: \(error.localizedDescription)")
                    outputText = rawText
                }
            } else {
                Logger.general.info("Skipping LLM (mode: \(activeMode.rawValue))")
            }

            // Determine final text — wait for overlay if enabled
            appState.overlayText = outputText

            let finalText: String
            if showOverlayEnabled {
                // Clear processing state so overlay shows the result (not spinner)
                appState.isProcessing = false

                // Reset overlay flags and show
                appState.overlayEditConfirmed = false
                appState.overlayEditCancelled = false
                appState.overlayEditedText = nil
                appState.showOverlay = true

                // Wait for user decision in overlay
                let confirmed = await waitForOverlayDecision()
                appState.showOverlay = false

                guard confirmed else {
                    Logger.general.info("Dictation cancelled from overlay")
                    resetOverlayState()
                    updateState(.idle)
                    return
                }
                finalText = appState.overlayEditedText ?? outputText
                resetOverlayState()
            } else {
                finalText = outputText
            }

            // Inject text (use snapshotted per-app injection method from recording start)
            updateState(.injecting)
            try await injectionService.inject(finalText, method: recordingInjectionMethod)

            // Save history entry (use snapshotted app info from recording start)
            let processedText = (finalText != rawText) ? finalText : nil
            await saveDictationEntry(
                rawText: rawText,
                processedText: processedText,
                language: result.language,
                audioDuration: result.audioDuration,
                appBundleIdentifier: recordingBundleIdentifier,
                appName: recordingAppName
            )

            // Update preview
            appState.lastTranscriptionPreview = finalText
            Logger.general.info("Dictation complete: \(finalText.count) chars injected")

        } catch {
            Logger.general.error("Pipeline error: \(error.localizedDescription)")
            appState.currentError = error.localizedDescription
        }

        updateState(.idle)
    }

    // MARK: - Overlay Helpers

    /// Poll for overlay user decision (confirm or cancel).
    /// Returns true if confirmed, false if cancelled or timed out.
    @MainActor
    private func waitForOverlayDecision() async -> Bool {
        let deadline = Date().addingTimeInterval(60)
        while !appState.overlayEditConfirmed && !appState.overlayEditCancelled {
            if Date() > deadline {
                Logger.general.warning("Overlay decision timeout — auto-confirming")
                return true
            }
            if !appState.showOverlay {
                return false
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return appState.overlayEditConfirmed
    }

    /// Reset all overlay-related state after handling.
    @MainActor
    private func resetOverlayState() {
        appState.showOverlay = false
        appState.overlayText = nil
        appState.overlayEditedText = nil
        appState.overlayEditConfirmed = false
        appState.overlayEditCancelled = false
    }

    // MARK: - Per-App Profile Resolution

    /// The effective processing mode — per-app override if available, else global default.
    private var activeMode: ProcessingMode {
        if let profile = appContextService?.currentProfile,
           profile.isEnabled,
           let mode = profile.defaultMode {
            return mode
        }
        return defaultMode
    }

    /// The effective injection method — per-app override if available, else global default.
    private var activeInjectionMethod: InjectionMethod {
        if let profile = appContextService?.currentProfile,
           profile.isEnabled {
            return profile.injectionMethod
        }
        return injectionMethod
    }

    /// Resolve the current app's profile via AppContextService + SwiftData.
    @MainActor
    private func resolveAppProfileOverrides() {
        guard let service = appContextService, let container = modelContainer else { return }
        let context = container.mainContext
        service.resolveProfile(in: context)

        if let profile = service.currentProfile, profile.isEnabled {
            // Apply per-app language override if set
            if let lang = profile.preferredLanguage, !lang.isEmpty {
                whisperService.language = lang
                Logger.general.info("Per-app language override: \(lang) for \(service.currentAppName ?? "unknown")")
            } else if autoDetectLanguage {
                whisperService.language = "auto"
            } else {
                whisperService.language = defaultLanguage
            }

            Logger.general.info("Per-app profile active: \(service.currentAppName ?? "unknown") — mode: \(profile.defaultMode?.rawValue ?? "global"), injection: \(profile.injectionMethod.rawValue)")
        } else {
            // Reset to global defaults
            whisperService.language = autoDetectLanguage ? "auto" : defaultLanguage
        }
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

    /// Set the app context service for per-app profile resolution.
    func setAppContextService(_ service: AppContextService) {
        self.appContextService = service
        Logger.general.info("AppContextService configured for pipeline")
    }

    /// Configure the voice command services for the pipeline.
    func setCommandServices(parser: CommandParser, executor: CommandExecutor, registry: CommandRegistry) {
        self.commandParser = parser
        self.commandExecutor = executor
        self.commandRegistry = registry
        Logger.commands.info("Command services configured for pipeline")
    }

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
        whisperThreadCount: Int = 0,
        defaultMode: ProcessingMode = .raw,
        autoDetectLanguage: Bool = false,
        defaultLanguage: String = "en",
        showOverlayEnabled: Bool = true,
        commandsEnabled: Bool = true,
        commandWakePhrase: String = "Hey Type"
    ) {
        self.vadSensitivity = vadSensitivity
        self.injectionMethod = injectionMethod
        self.injectionService.keystrokeDelayMs = keystrokeDelayMs
        self.pushToTalkEnabled = pushToTalkEnabled
        self.playSoundEffects = playSoundEffects
        self.audioService.setInputDevice(id: audioInputDeviceID)
        self.whisperService.useGPU = useGPUAcceleration
        self.whisperService.threadCount = whisperThreadCount
        self.defaultMode = defaultMode
        self.autoDetectLanguage = autoDetectLanguage
        self.defaultLanguage = defaultLanguage
        self.showOverlayEnabled = showOverlayEnabled
        self.commandsEnabled = commandsEnabled
        self.commandWakePhrase = commandWakePhrase

        // Update whisper language setting
        self.whisperService.language = autoDetectLanguage ? "auto" : defaultLanguage

        // Update displayed mode when idle so menu bar reflects the setting
        if state == .idle {
            appState.activeMode = defaultMode
        }
    }

    // MARK: - Voice Command Handling

    /// Parse and execute a detected voice command (supports chained commands).
    @MainActor
    private func handleVoiceCommand(_ commandText: String) async {
        guard let parser = commandParser, let executor = commandExecutor else {
            Logger.commands.warning("Command services not configured — ignoring command")
            appState.isExecutingCommand = false
            return
        }

        appState.isExecutingCommand = true

        // Check custom commands first (SwiftData-stored user-defined commands)
        if let registry = commandRegistry, let container = modelContainer {
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<CustomCommand>()
            if let customCommands = try? context.fetch(descriptor),
               let actionSteps = registry.resolveCustomCommand(commandText, customCommands: customCommands) {
                let parsedCommands = actionSteps.map { step in
                    ParsedCommand(
                        intent: step.intent,
                        entities: step.parameters,
                        rawText: commandText,
                        displayName: step.intent.displayName
                    )
                }
                let results = await executor.executeChain(parsedCommands)
                let allSucceeded = results.allSatisfy { $0.success }
                let summary = results.map { $0.message }.joined(separator: "; ")
                appState.lastCommandResult = summary
                appState.lastTranscriptionPreview = allSucceeded ? summary : "Failed: \(summary)"
                appState.isExecutingCommand = false
                if allSucceeded {
                    playSound(.stop)
                    Logger.commands.info("Custom command executed: \(summary)")
                } else {
                    Logger.commands.warning("Custom command failed: \(summary)")
                }
                return
            }
        }

        // Fall through to regex-based parsing for built-in commands
        let commands = parser.parseChain(commandText)
        guard !commands.isEmpty else {
            Logger.commands.info("No parseable command in: \(commandText)")
            appState.lastCommandResult = "Unrecognized command: \(commandText)"
            appState.lastTranscriptionPreview = "? \(commandText)"
            appState.isExecutingCommand = false
            return
        }

        let results = await executor.executeChain(commands)

        let allSucceeded = results.allSatisfy { $0.success }
        let summary = results.map { $0.message }.joined(separator: "; ")

        appState.lastCommandResult = summary
        appState.lastTranscriptionPreview = allSucceeded ? summary : "Failed: \(summary)"
        appState.isExecutingCommand = false

        if allSucceeded {
            playSound(.stop)
            Logger.commands.info("Command executed: \(summary)")
        } else {
            Logger.commands.warning("Command failed: \(summary)")
        }
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

        // Enforce retention policies using HistoryCleanupService (count + age limits, favorites exempt)
        let cleanup = HistoryCleanupService(modelContainer: modelContainer)
        cleanup.runCleanup()
    }
}
