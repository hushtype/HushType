import Foundation
import os
import SwiftData

struct DataSeeder {
    /// Seeds built-in data on first launch.
    ///
    /// Checks if any PromptTemplates exist — if not, this is a fresh install
    /// and we insert:
    /// - 4 built-in PromptTemplates
    /// - 5 default whisper model registry entries
    /// - 1 default UserSettings singleton
    @MainActor
    static func seedIfNeeded(in context: ModelContext) {
        let descriptor = FetchDescriptor<PromptTemplate>()
        let existingCount = (try? context.fetchCount(descriptor)) ?? 0

        guard existingCount == 0 else {
            Logger.general.debug("Data already seeded (\(existingCount) templates found), skipping")
            return
        }

        Logger.general.info("First launch detected — seeding built-in data")

        // Seed built-in prompt templates
        for template in PromptTemplate.builtInTemplates {
            context.insert(template)
        }
        Logger.general.info("Seeded \(PromptTemplate.builtInTemplates.count) built-in templates")

        // Seed default whisper model registry
        for model in ModelInfo.defaultModels {
            context.insert(model)
        }
        Logger.general.info("Seeded \(ModelInfo.defaultModels.count) default model entries")

        // Ensure default UserSettings singleton exists
        _ = try? UserSettings.shared(in: context)
        Logger.general.info("Ensured default UserSettings singleton")
    }
}
