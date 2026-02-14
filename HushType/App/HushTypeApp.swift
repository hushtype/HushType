//
//  HushTypeApp.swift
//  HushType
//
//  Created by Harun Güngörer on 13.02.2026.
//

import SwiftData
import SwiftUI
import os

@main
struct HushTypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()
    @State private var dictationController: DictationController?
    let modelContainer: ModelContainer

    init() {
        let schema = Schema([
            DictationEntry.self,
            PromptTemplate.self,
            AppProfile.self,
            VocabularyEntry.self,
            UserSettings.self,
            ModelInfo.self
        ])

        let configuration = ModelConfiguration(
            "HushType",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        do {
            modelContainer = try ModelContainer(
                for: schema,
                migrationPlan: HushTypeMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            fatalError("Failed to initialize SwiftData container: \(error)")
        }

        // Seed built-in data on first launch
        DataSeeder.seedIfNeeded(in: modelContainer.mainContext)
    }

    var body: some Scene {
        MenuBarExtra("HushType", systemImage: appState.menuBarIcon) {
            MenuBarView()
                .environment(appState)
        }
        .menuBarExtraStyle(.window)
        .modelContainer(modelContainer)

        Settings {
            SettingsView()
        }
        .modelContainer(modelContainer)
    }

    // MARK: - Pipeline Setup

    private func setupPipeline() {
        let controller = DictationController(appState: appState)
        controller.modelContainer = modelContainer

        // Load settings and start
        let context = modelContainer.mainContext
        if let settings = UserSettings.shared(in: context) {
            controller.updateConfiguration(
                vadSensitivity: Float(settings.vadSensitivity),
                injectionMethod: settings.defaultInjectionMethod
            )

            do {
                try controller.start(hotkey: settings.globalHotkey)
                Logger.general.info("Dictation pipeline started")
            } catch {
                Logger.general.error("Failed to start dictation pipeline: \(error.localizedDescription)")
                appState.currentError = "Failed to start hotkey listener: \(error.localizedDescription)"
            }
        }

        dictationController = controller
    }
}
