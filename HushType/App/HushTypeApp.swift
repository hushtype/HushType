//
//  HushTypeApp.swift
//  HushType
//
//  Created by Harun Güngörer on 13.02.2026.
//

import SwiftData
import SwiftUI

@main
struct HushTypeApp: App {
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
        MenuBarExtra("HushType", systemImage: "mic.fill") {
            Text("HushType Menu Bar App")
        }
        .menuBarExtraStyle(.window)
        .modelContainer(modelContainer)

        Settings {
            Text("Settings placeholder")
        }
        .modelContainer(modelContainer)
    }
}
