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
    private var modelDownloader: ModelDownloader?
    private var llmService: LLMService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Kill any other running instances of HushType
        terminateOtherInstances()

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
                whisperThreadCount: settings.whisperThreadCount
            )
            try controller.reloadHotkey(settings.globalHotkey)
            Logger.general.info("Pipeline config updated from settings (hotkey: \(settings.globalHotkey), pushToTalk: \(settings.pushToTalkEnabled))")
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
                whisperThreadCount: settings.whisperThreadCount
            )

            // Load whisper model — auto-download default if not on disk
            let modelFileName = settings.selectedWhisperModel
            Task {
                await controller.loadWhisperModel(fileName: modelFileName)
            }
            autoDownloadDefaultModelIfNeeded(in: context)

            // Configure LLM service
            let service = LLMService()
            let provider = LlamaCppProvider()
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
}
