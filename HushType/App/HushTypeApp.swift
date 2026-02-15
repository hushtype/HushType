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

        // Wire model container to delegate for pipeline startup
        appDelegate.modelContainer = modelContainer
    }

    var body: some Scene {
        MenuBarExtra("HushType", systemImage: appDelegate.appState.menuBarIcon) {
            MenuBarView(appState: appDelegate.appState)
        }
        .menuBarExtraStyle(.window)
        .modelContainer(modelContainer)

        Settings {
            SettingsView()
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .modelContainer(modelContainer)
    }
}
