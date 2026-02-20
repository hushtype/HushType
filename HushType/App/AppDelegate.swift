//
//  AppDelegate.swift
//  HushType
//
//  Created by Claude on 14.02.2026.
//

import AppKit
import SwiftData
import os.log

class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    var modelContainer: ModelContainer?
    private var dictationController: DictationController?
    private var appContextService: AppContextService?
    private var modelDownloader: ModelDownloader?
    private var llmModelDownloader: ModelDownloader?
    private var llmService: LLMService?
    private var registryService: ModelRegistryService?
    private var overlayWindow: OverlayWindow?

    // Track currently loaded models to detect selection changes
    private var currentWhisperModel: String?
    private var currentLLMModel: String?
    private var currentLLMContextLength: Int = 2048

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Kill any other running instances of HushType (skip during unit tests)
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            terminateOtherInstances()
        }

        // Hide dock icon - this is a menu bar only app
        NSApp.setActivationPolicy(.accessory)
        Logger.general.info("HushType launched - dock icon hidden, menu bar active")

        // Register observers before pipeline start so auto-download notifications aren't missed
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleModelDownloaded(_:)),
            name: .whisperModelDownloaded,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLLMModelDownloaded(_:)),
            name: .llmModelDownloaded,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSettingsChanged),
            name: .userSettingsChanged,
            object: nil
        )

        startPipeline()
    }

    @objc private func handleSettingsChanged() {
        guard let modelContainer, let controller = dictationController else { return }
        let context = modelContainer.mainContext
        do {
            let settings = try UserSettings.shared(in: context)
            controller.updateConfiguration(
                vadSensitivity: Float(settings.vadSensitivity),
                injectionMethod: settings.defaultInjectionMethod,
                keystrokeDelayMs: settings.keystrokeDelay,
                pushToTalkEnabled: settings.pushToTalkEnabled,
                playSoundEffects: settings.playSoundEffects,
                audioInputDeviceID: settings.audioInputDeviceID,
                useGPUAcceleration: settings.useGPUAcceleration,
                whisperThreadCount: settings.whisperThreadCount,
                defaultMode: settings.defaultMode,
                autoDetectLanguage: settings.autoDetectLanguage,
                defaultLanguage: settings.defaultLanguage,
                showOverlayEnabled: settings.showOverlayAfterDictation,
                commandsEnabled: settings.commandsEnabled,
                commandWakePhrase: settings.commandWakePhrase
            )
            try controller.reloadHotkey(settings.globalHotkey)

            // Reload whisper model if selection changed
            let newWhisperModel = settings.selectedWhisperModel
            if newWhisperModel != currentWhisperModel {
                currentWhisperModel = newWhisperModel
                Task {
                    await controller.loadWhisperModel(fileName: newWhisperModel)
                }
                Logger.general.info("Whisper model changed to: \(newWhisperModel)")
            }

            // Reload LLM model if selection changed
            let newLLMModel = settings.selectedLLMModel
            if newLLMModel != currentLLMModel {
                currentLLMModel = newLLMModel
                if let modelName = newLLMModel {
                    Task {
                        await controller.loadLLMModel(fileName: modelName)
                    }
                    Logger.general.info("LLM model changed to: \(modelName)")
                }
            }

            // Recreate LLM provider if context length changed
            let newContextLength = settings.llmContextLength
            if newContextLength != currentLLMContextLength {
                currentLLMContextLength = newContextLength
                let service = LLMService()
                let provider = LlamaCppProvider(contextSize: UInt32(newContextLength))
                service.setProvider(provider)
                controller.setLLMService(service)
                self.llmService = service

                // Reload current LLM model with new context
                if let modelName = settings.selectedLLMModel {
                    Task {
                        await controller.loadLLMModel(fileName: modelName)
                    }
                }
                Logger.general.info("LLM context length changed to: \(newContextLength)")
            }

            Logger.general.info("Pipeline config updated from settings (hotkey: \(settings.globalHotkey), pushToTalk: \(settings.pushToTalkEnabled), mode: \(settings.defaultMode.rawValue), lang: \(settings.autoDetectLanguage ? "auto" : settings.defaultLanguage))")
        } catch {
            Logger.general.error("Failed to reload settings: \(error.localizedDescription)")
        }
    }

    @objc private func handleModelDownloaded(_ notification: Notification) {
        guard let fileName = notification.userInfo?["fileName"] as? String else { return }

        // Persist isDownloaded = true to SwiftData (ModelDownloader sets it in memory only)
        if let context = modelContainer?.mainContext {
            try? context.save()
        }

        guard let controller = dictationController else { return }
        Task {
            await controller.loadWhisperModel(fileName: fileName)
        }
    }

    @objc private func handleLLMModelDownloaded(_ notification: Notification) {
        guard let fileName = notification.userInfo?["fileName"] as? String else { return }

        guard let context = modelContainer?.mainContext else { return }

        // Persist isDownloaded = true
        try? context.save()

        // Auto-select if no LLM model is currently selected
        if let settings = try? UserSettings.shared(in: context),
           settings.selectedLLMModel == nil {
            settings.selectedLLMModel = fileName
            try? context.save()
            Logger.general.info("Auto-selected LLM model: \(fileName)")
        }

        guard let controller = dictationController else { return }
        Task {
            await controller.loadLLMModel(fileName: fileName)
        }
    }

    private func terminateOtherInstances() {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier && $0.processIdentifier != currentPID
        }
        for app in runningApps {
            Logger.general.info("Terminating old HushType instance (PID \(app.processIdentifier))")
            app.terminate()
        }
    }

    // MARK: - Pipeline Setup

    @MainActor
    private func startPipeline() {
        // Skip pipeline when running inside XCTest host to prevent crashes
        // from audio hardware and model loading during unit tests
        if NSClassFromString("XCTestCase") != nil {
            Logger.general.info("Test environment detected — skipping pipeline startup")
            return
        }

        guard let modelContainer else {
            Logger.general.error("ModelContainer not set — pipeline not started")
            return
        }

        let controller = DictationController(appState: appState)
        controller.modelContainer = modelContainer

        // Wire app context service for per-app profile overrides
        let contextService = AppContextService()
        controller.setAppContextService(contextService)
        self.appContextService = contextService

        let context = modelContainer.mainContext
        do {
            let settings = try UserSettings.shared(in: context)
            controller.updateConfiguration(
                vadSensitivity: Float(settings.vadSensitivity),
                injectionMethod: settings.defaultInjectionMethod,
                keystrokeDelayMs: settings.keystrokeDelay,
                pushToTalkEnabled: settings.pushToTalkEnabled,
                playSoundEffects: settings.playSoundEffects,
                audioInputDeviceID: settings.audioInputDeviceID,
                useGPUAcceleration: settings.useGPUAcceleration,
                whisperThreadCount: settings.whisperThreadCount,
                defaultMode: settings.defaultMode,
                autoDetectLanguage: settings.autoDetectLanguage,
                defaultLanguage: settings.defaultLanguage,
                showOverlayEnabled: settings.showOverlayAfterDictation,
                commandsEnabled: settings.commandsEnabled,
                commandWakePhrase: settings.commandWakePhrase
            )

            // Track initial model selections for change detection
            currentWhisperModel = settings.selectedWhisperModel
            currentLLMModel = settings.selectedLLMModel
            currentLLMContextLength = settings.llmContextLength

            // Load whisper model — auto-download default if not on disk
            let modelFileName = settings.selectedWhisperModel
            Task {
                await controller.loadWhisperModel(fileName: modelFileName)
            }
            autoDownloadDefaultModelIfNeeded(in: context)
            autoDownloadDefaultLLMModelIfNeeded(in: context)

            // Wire voice command services
            let commandRegistry = CommandRegistry()
            let commandParser = CommandParser()
            let commandExecutor = CommandExecutor(registry: commandRegistry)
            controller.setCommandServices(
                parser: commandParser,
                executor: commandExecutor,
                registry: commandRegistry
            )

            // Configure LLM service with user's context length
            let service = LLMService()
            let provider = LlamaCppProvider(contextSize: UInt32(settings.llmContextLength))
            service.setProvider(provider)
            controller.setLLMService(service)
            self.llmService = service

            // Load LLM model if configured
            if let llmModelName = settings.selectedLLMModel {
                Task {
                    await controller.loadLLMModel(fileName: llmModelName)
                }
            }

            try controller.start(hotkey: settings.globalHotkey)
            appState.currentError = nil
            Logger.general.info("Dictation pipeline started")
        } catch {
            Logger.general.error("Pipeline startup failed: \(error.localizedDescription)")
            appState.currentError = "Startup error: \(error.localizedDescription)"
        }

        dictationController = controller

        // Create and wire overlay window for edit-before-inject
        let overlay = OverlayWindow()
        overlay.setContent(appState: appState)
        self.overlayWindow = overlay
        startOverlayObservation()

        // Note: ModelManagementView creates its own instance for UI state.
        // Both share lastRefreshDate via UserDefaults, preventing redundant fetches.
        let registry = ModelRegistryService(modelContainer: modelContainer)
        self.registryService = registry
        Task { await registry.refreshIfNeeded() }
    }

    // MARK: - Overlay Observation

    private func startOverlayObservation() {
        Task { @MainActor [weak self] in
            while let self = self {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    withObservationTracking {
                        _ = self.appState.showOverlay
                    } onChange: {
                        continuation.resume()
                    }
                }
                if self.appState.showOverlay {
                    self.overlayWindow?.showOverlay(position: .bottomCenter)
                } else {
                    self.overlayWindow?.hideOverlay()
                }
            }
        }
    }

    // MARK: - Auto-Download Default Model

    @MainActor
    private func autoDownloadDefaultModelIfNeeded(in context: ModelContext) {
        let descriptor = FetchDescriptor<ModelInfo>()
        guard let models = try? context.fetch(descriptor) else { return }

        let defaultModel = models.first { $0.isDefault && $0.type == .whisper }
        guard let model = defaultModel, !model.isDownloaded, !model.fileExistsOnDisk else { return }

        Logger.general.info("Default whisper model not downloaded — auto-downloading \(model.name)")
        let downloader = ModelDownloader()
        modelDownloader = downloader
        downloader.download(model)

        do {
            try context.save()
        } catch {
            Logger.general.error("Failed to save model state: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func autoDownloadDefaultLLMModelIfNeeded(in context: ModelContext) {
        let descriptor = FetchDescriptor<ModelInfo>()
        guard let models = try? context.fetch(descriptor) else { return }

        let defaultModel = models.first { $0.isDefault && $0.type == .llm }
        guard let model = defaultModel, !model.isDownloaded, !model.fileExistsOnDisk else { return }

        Logger.general.info("Default LLM model not downloaded — auto-downloading \(model.name)")
        let downloader = ModelDownloader()
        llmModelDownloader = downloader
        downloader.download(model)

        do {
            try context.save()
        } catch {
            Logger.general.error("Failed to save model state: \(error.localizedDescription)")
        }
    }
}
