//
//  AppDelegate.swift
//  HushType
//
//  Created by Claude on 14.02.2026.
//

import AppKit
import Sparkle
import SwiftData
import os

private let startupLog = OSLog(subsystem: Constants.logSubsystem, category: "startup")
private let startupSignpostID = OSSignpostID(log: startupLog)

class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    var modelContainer: ModelContainer?
    let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    private var dictationController: DictationController?
    private var appContextService: AppContextService?
    private var modelDownloader: ModelDownloader?
    private var llmModelDownloader: ModelDownloader?
    private var llmService: LLMService?
    private var registryService: ModelRegistryService?
    private var overlayWindow: OverlayWindow?
    private var powerManagementService: PowerManagementService?

    // Track currently loaded models and hotkey to detect selection changes
    private var currentWhisperModel: String?
    private var currentLLMModel: String?
    private var currentLLMContextLength: Int = 2048
    private var currentHotkey: String = ""
    private var currentWhisperThreadCount: Int = 0

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
            // Track user's thread count setting for battery-aware mode
            currentWhisperThreadCount = settings.whisperThreadCount

            controller.updateConfiguration(
                vadSensitivity: Float(settings.vadSensitivity),
                injectionMethod: settings.defaultInjectionMethod,
                keystrokeDelayMs: settings.keystrokeDelay,
                pushToTalkEnabled: settings.pushToTalkEnabled,
                playSoundEffects: settings.playSoundEffects,
                soundTheme: settings.soundTheme,
                soundVolume: settings.soundVolume,
                audioInputDeviceID: settings.audioInputDeviceID,
                whisperThreadCount: settings.whisperThreadCount,
                defaultMode: settings.defaultMode,
                autoDetectLanguage: settings.autoDetectLanguage,
                defaultLanguage: settings.defaultLanguage,
                showOverlayEnabled: settings.showOverlayAfterDictation,
                commandsEnabled: settings.commandsEnabled,
                commandWakePhrase: settings.commandWakePhrase,
                globalShortcutAliases: settings.globalShortcutAliases
            )

            // Sync disabled command intents to the pipeline registry
            appState.commandRegistry?.loadDisabledIntents(settings.disabledCommandIntents)

            // Sync power management settings
            powerManagementService?.batteryAwareModeEnabled = settings.batteryAwareModeEnabled

            // Reload hotkey only if it changed
            if settings.globalHotkey != currentHotkey {
                currentHotkey = settings.globalHotkey
                try controller.reloadHotkey(settings.globalHotkey)
            }

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
        os_signpost(.begin, log: startupLog, name: "startPipeline", signpostID: startupSignpostID)

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

        // --- Phase 1: Immediate — get menu bar responsive ASAP ---
        os_signpost(.begin, log: startupLog, name: "pipelineCore", signpostID: startupSignpostID)

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
                soundTheme: settings.soundTheme,
                soundVolume: settings.soundVolume,
                audioInputDeviceID: settings.audioInputDeviceID,
                whisperThreadCount: settings.whisperThreadCount,
                defaultMode: settings.defaultMode,
                autoDetectLanguage: settings.autoDetectLanguage,
                defaultLanguage: settings.defaultLanguage,
                showOverlayEnabled: settings.showOverlayAfterDictation,
                commandsEnabled: settings.commandsEnabled,
                commandWakePhrase: settings.commandWakePhrase,
                globalShortcutAliases: settings.globalShortcutAliases
            )

            // Track initial model selections for change detection
            currentWhisperModel = settings.selectedWhisperModel
            currentLLMModel = settings.selectedLLMModel
            currentLLMContextLength = settings.llmContextLength

            // Wire voice command services (lightweight — no I/O)
            let commandRegistry = CommandRegistry()
            commandRegistry.loadDisabledIntents(settings.disabledCommandIntents)
            let commandParser = CommandParser()
            let commandExecutor = CommandExecutor(registry: commandRegistry)
            controller.setCommandServices(
                parser: commandParser,
                executor: commandExecutor,
                registry: commandRegistry
            )
            appState.commandRegistry = commandRegistry

            // Wire plugin manager for pipeline integration
            appState.pluginManager.discoverPlugins()
            controller.setPluginManager(appState.pluginManager)

            // Configure LLM service (lightweight — no model loading yet)
            let service = LLMService()
            let provider = LlamaCppProvider(contextSize: UInt32(settings.llmContextLength))
            service.setProvider(provider)
            controller.setLLMService(service)
            self.llmService = service

            // Wire power management (lightweight — no I/O, just timers and observers)
            currentWhisperThreadCount = settings.whisperThreadCount
            let powerService = PowerManagementService()
            powerService.batteryAwareModeEnabled = settings.batteryAwareModeEnabled

            powerService.onPowerStateChanged = { [weak self, weak controller] isOnBattery in
                guard let self, let controller else { return }
                let userThreadCount = self.currentWhisperThreadCount
                // On battery: cap at 2 threads; on AC: restore user setting
                let threadCount = isOnBattery
                    ? (userThreadCount == 0 ? 2 : min(userThreadCount, 2))
                    : userThreadCount
                controller.setWhisperThreadCount(threadCount)
                Logger.performance.info("Battery-aware: whisper threads set to \(threadCount) (user: \(userThreadCount))")
            }

            powerService.onThermalThrottleNeeded = { [weak self] state in
                self?.appState.currentError = state == .critical
                    ? "System overheating — inference paused"
                    : "System warm — performance reduced"
                Logger.performance.warning("Thermal throttle: \(state.rawValue)")
            }

            powerService.onMemoryPressure = { [weak self] level in
                guard let self else { return }
                Task {
                    switch level {
                    case .warning:
                        await self.dictationController?.unloadLLMModel()
                        Logger.performance.warning("Memory pressure: LLM model unloaded")
                    case .critical:
                        await self.dictationController?.unloadLLMModel()
                        self.dictationController?.unloadWhisperModel()
                        Logger.performance.warning("Memory pressure: all models unloaded")
                    case .normal:
                        if let whisperModel = self.currentWhisperModel {
                            await self.dictationController?.loadWhisperModel(fileName: whisperModel)
                        }
                        if let llmModel = self.currentLLMModel {
                            await self.dictationController?.loadLLMModel(fileName: llmModel)
                        }
                        Logger.performance.info("Memory pressure subsided: models reloading")
                    }
                }
            }

            powerService.start()
            self.powerManagementService = powerService
            controller.setPowerManagementService(powerService)

            // Track initial hotkey for change detection
            currentHotkey = settings.globalHotkey

            // Register hotkey — menu bar is now responsive
            try controller.start(hotkey: settings.globalHotkey)
            appState.currentError = nil
            Logger.general.info("Dictation pipeline started (hotkey active)")
        } catch {
            Logger.general.error("Pipeline startup failed: \(error.localizedDescription)")
            appState.currentError = "Startup error: \(error.localizedDescription)"
        }

        dictationController = controller

        // Create overlay window (lightweight NSPanel)
        let overlay = OverlayWindow()
        overlay.setContent(appState: appState)
        self.overlayWindow = overlay
        startOverlayObservation()

        os_signpost(.end, log: startupLog, name: "pipelineCore", signpostID: startupSignpostID)
        Logger.performance.info("Pipeline core ready — menu bar active")

        // --- Phase 2: Deferred — model loading and network I/O ---
        // Defer heavy work so the menu bar icon and hotkey are responsive immediately.
        Task { @MainActor [weak self] in
            guard let self else { return }
            os_signpost(.begin, log: startupLog, name: "deferredSetup", signpostID: startupSignpostID)

            // Load whisper model in background
            if let whisperFileName = self.currentWhisperModel {
                await controller.loadWhisperModel(fileName: whisperFileName)
            }

            // Auto-download default models if needed
            self.autoDownloadDefaultModelIfNeeded(in: context)
            self.autoDownloadDefaultLLMModelIfNeeded(in: context)

            // Load LLM model if configured
            if let llmModelName = self.currentLLMModel {
                await controller.loadLLMModel(fileName: llmModelName)
            }

            // Refresh model registry (network I/O)
            let registry = ModelRegistryService(modelContainer: modelContainer)
            self.registryService = registry
            await registry.refreshIfNeeded()

            os_signpost(.end, log: startupLog, name: "deferredSetup", signpostID: startupSignpostID)
            os_signpost(.end, log: startupLog, name: "startPipeline", signpostID: startupSignpostID)
            Logger.performance.info("Deferred setup complete — all models loaded")
        }
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
