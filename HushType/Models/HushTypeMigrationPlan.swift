import Foundation
import SwiftData

// MARK: - Current Schema

/// Single schema definition listing all SwiftData model types.
///
/// SwiftData handles lightweight migrations automatically when properties are
/// added with default values. No explicit `SchemaMigrationPlan` is needed
/// because all schema changes so far (e.g., new nullable or defaulted fields
/// on `ModelInfo`) qualify as lightweight.
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
