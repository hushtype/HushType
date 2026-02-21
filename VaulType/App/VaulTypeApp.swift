//
//  VaulTypeApp.swift
//  VaulType
//
//  Created by Harun Güngörer on 13.02.2026.
//

import Sparkle
import SwiftData
import SwiftUI
import os

@main
struct VaulTypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let modelContainer: ModelContainer

    init() {
        let schema = Schema([
            DictationEntry.self,
            PromptTemplate.self,
            AppProfile.self,
            VocabularyEntry.self,
            UserSettings.self,
            ModelInfo.self,
            CustomCommand.self
        ])

        let configuration = ModelConfiguration(
            "VaulType",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        do {
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
        } catch {
            Logger.general.error("SwiftData migration failed, recreating store: \(error.localizedDescription)")
            // Delete the incompatible store and retry with a fresh database
            let storePath = URL.applicationSupportDirectory.appendingPathComponent("VaulType.store").path
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: storePath + suffix)
            }
            do {
                modelContainer = try ModelContainer(
                    for: schema,
                    configurations: [configuration]
                )
                Logger.general.info("SwiftData store recreated successfully")
            } catch {
                fatalError("Failed to initialize SwiftData container after reset: \(error)")
            }
        }

        // Seed built-in data on first launch
        DataSeeder.seedIfNeeded(in: modelContainer.mainContext)

        // Wire model container to delegate for pipeline startup
        appDelegate.modelContainer = modelContainer
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appDelegate.appState)
        } label: {
            Image(nsImage: appDelegate.appState.menuBarImage)
        }
        .menuBarExtraStyle(.window)
        .modelContainer(modelContainer)

        Window("Dictation History", id: "history") {
            HistoryView()
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .modelContainer(modelContainer)

        Settings {
            SettingsView(updater: appDelegate.updaterController.updater)
                .environment(appDelegate.appState)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .modelContainer(modelContainer)

        Window("Welcome to VaulType", id: "onboarding") {
            OnboardingView()
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                    DispatchQueue.main.async {
                        for window in NSApp.windows where window.title == "Welcome to VaulType" {
                            window.level = .floating
                            window.orderFrontRegardless()
                        }
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .modelContainer(modelContainer)
    }
}
