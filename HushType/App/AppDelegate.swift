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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Kill any other running instances of HushType
        terminateOtherInstances()

        // Hide dock icon - this is a menu bar only app
        NSApp.setActivationPolicy(.accessory)
        Logger.general.info("HushType launched - dock icon hidden, menu bar active")

        startPipeline()

        // Listen for model downloads to hot-load them
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleModelDownloaded(_:)),
            name: .whisperModelDownloaded,
            object: nil
        )
    }

    @objc private func handleModelDownloaded(_ notification: Notification) {
        guard let fileName = notification.userInfo?["fileName"] as? String else { return }
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
                keystrokeDelayMs: settings.keystrokeDelay
            )

            // Load whisper model in background
            let modelFileName = settings.selectedWhisperModel
            Task {
                await controller.loadWhisperModel(fileName: modelFileName)
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
}
