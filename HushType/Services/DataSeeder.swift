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

        if existingCount == 0 {
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
        } else {
            Logger.general.debug("Data already seeded (\(existingCount) templates found), skipping")
        }

        // Always check for LLM models — handles upgrades from pre-LLM versions
        seedLLMModelsIfNeeded(in: context)
    }

    /// Seeds missing LLM model entries.
    ///
    /// Checks each default LLM model by fileName and inserts any that
    /// don't exist yet. Handles both fresh installs and upgrades when
    /// new models are added to the registry.
    @MainActor
    static func seedLLMModelsIfNeeded(in context: ModelContext) {
        let allModels = (try? context.fetch(FetchDescriptor<ModelInfo>())) ?? []
        let existingFileNames = Set(allModels.map(\.fileName))

        let llmModels = ModelInfo.defaultModels.filter { $0.type == .llm }
        var inserted = 0
        for model in llmModels {
            guard !existingFileNames.contains(model.fileName) else { continue }
            context.insert(model)
            inserted += 1
        }

        if inserted > 0 {
            Logger.general.info("Seeded \(inserted) new LLM model entries")
        }
    }
}
