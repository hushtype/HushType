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

        // Always check for app profiles — handles upgrades from pre-Phase 3 versions
        seedAppProfilesIfNeeded(in: context)
    }

    /// Pre-seeds AppProfile records for well-known macOS applications.
    ///
    /// Checks each known bundle ID and inserts a profile with smart defaults
    /// only if one doesn't already exist. Handles both fresh installs and
    /// upgrades from pre-Phase 3 versions.
    @MainActor
    static func seedAppProfilesIfNeeded(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<AppProfile>())) ?? []
        let existingBundleIDs = Set(existing.map(\.bundleIdentifier))

        let knownApps: [(bundleID: String, name: String, mode: ProcessingMode, aliases: [String: String])] = [
            ("com.apple.dt.Xcode", "Xcode", .code, [
                "build and run": "cmd+r",
                "build": "cmd+b",
                "stop": "cmd+.",
                "clean build": "cmd+shift+k",
                "open quickly": "cmd+shift+o",
                "new file": "cmd+n",
                "save all": "cmd+option+s",
            ]),
            ("com.microsoft.VSCode", "Visual Studio Code", .code, [:]),
            ("com.apple.mail",             "Mail",           .clean, [:]),
            ("com.apple.Terminal", "Terminal", .raw, [
                "new tab": "cmd+t",
                "close tab": "cmd+w",
                "clear": "cmd+k",
            ]),
            ("com.apple.Notes",            "Notes",          .structure, [:]),
            ("com.apple.Safari", "Safari", .clean, [
                "new tab": "cmd+t",
                "close tab": "cmd+w",
                "reload": "cmd+r",
                "new window": "cmd+n",
                "new private window": "cmd+shift+n",
            ]),
            ("com.google.Chrome",          "Google Chrome",  .clean, [:]),
            ("com.apple.TextEdit",         "TextEdit",       .clean, [:]),
            ("com.tinyspeck.slackmacgap",  "Slack",          .clean, [:]),
            ("com.apple.iWork.Pages",      "Pages",          .structure, [:]),
            ("com.microsoft.Word",         "Microsoft Word", .structure, [:]),
            ("com.apple.MobileSMS",        "Messages",       .clean, [:]),
        ]

        var inserted = 0
        for app in knownApps {
            guard !existingBundleIDs.contains(app.bundleID) else { continue }
            let profile = AppProfile(
                bundleIdentifier: app.bundleID,
                appName: app.name,
                defaultMode: app.mode,
                shortcutAliases: app.aliases
            )
            context.insert(profile)
            inserted += 1
        }

        if inserted > 0 {
            try? context.save()
            Logger.general.info("Seeded \(inserted) default app profiles")
        }
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
