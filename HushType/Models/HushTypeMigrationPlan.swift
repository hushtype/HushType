import Foundation
import SwiftData

// MARK: - Schema Versions

enum HushTypeSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            DictationEntry.self,
            PromptTemplate.self,
            AppProfile.self,
            VocabularyEntry.self,
            UserSettings.self,
            ModelInfo.self
        ]
    }
}

// MARK: - Migration Plan

enum HushTypeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            HushTypeSchemaV1.self
        ]
    }

    static var stages: [MigrationStage] {
        []
    }
}
