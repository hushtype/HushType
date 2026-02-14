import Foundation
import SwiftData

@Model
final class AppProfile {
    // MARK: - Identity

    @Attribute(.unique)
    var id: UUID

    /// The macOS bundle identifier (e.g., "com.apple.dt.Xcode").
    @Attribute(.unique)
    var bundleIdentifier: String

    /// Display name of the application.
    var appName: String

    // MARK: - Behavior Configuration

    /// Override the global default processing mode for this app.
    /// If nil, the global default is used.
    var defaultMode: ProcessingMode?

    /// App-specific vocabulary words and technical terms that whisper
    /// may not recognize correctly.
    var customVocabulary: [String]

    /// Override the global language setting for this app.
    /// If nil, the global default language is used.
    var preferredLanguage: String?

    /// How text should be injected into this application.
    var injectionMethod: InjectionMethod

    /// Whether this profile is active. Disabled profiles use global defaults.
    var isEnabled: Bool

    // MARK: - Relationships

    /// Vocabulary entries specific to this application.
    @Relationship(deleteRule: .cascade, inverse: \VocabularyEntry.appProfile)
    var vocabularyEntries: [VocabularyEntry]

    // MARK: - Initializer

    init(
        id: UUID = UUID(),
        bundleIdentifier: String,
        appName: String,
        defaultMode: ProcessingMode? = nil,
        customVocabulary: [String] = [],
        preferredLanguage: String? = nil,
        injectionMethod: InjectionMethod = .auto,
        isEnabled: Bool = true,
        vocabularyEntries: [VocabularyEntry] = []
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.defaultMode = defaultMode
        self.customVocabulary = customVocabulary
        self.preferredLanguage = preferredLanguage
        self.injectionMethod = injectionMethod
        self.isEnabled = isEnabled
        self.vocabularyEntries = vocabularyEntries
    }
}
