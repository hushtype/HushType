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
            ModelInfo.self,
            CustomCommand.self
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
            SettingsView()
                .environment(appDelegate.appState)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .modelContainer(modelContainer)
    }
}
