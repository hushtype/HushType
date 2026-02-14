import Foundation
import SwiftData

@Model
final class VocabularyEntry {
    // MARK: - Identity

    @Attribute(.unique)
    var id: UUID

    // MARK: - Replacement Rule

    /// What whisper typically outputs (the incorrect or abbreviated form).
    /// Example: "ecks code" or "jay son"
    var spokenForm: String

    /// What should replace the spoken form.
    /// Example: "Xcode" or "JSON"
    var replacement: String

    /// Limit this entry to a specific language. If nil, applies to all languages.
    var language: String?

    /// Whether this entry applies globally across all apps.
    /// If false, it only applies within the linked AppProfile.
    var isGlobal: Bool

    /// Whether the replacement is case-sensitive.
    /// When true: "json" won't match "JSON". When false: both match.
    var caseSensitive: Bool

    // MARK: - Relationships

    /// The app profile this vocabulary entry belongs to.
    /// Nil for global entries (isGlobal == true).
    var appProfile: AppProfile?

    // MARK: - Initializer

    init(
        id: UUID = UUID(),
        spokenForm: String,
        replacement: String,
        language: String? = nil,
        isGlobal: Bool = true,
        caseSensitive: Bool = false,
        appProfile: AppProfile? = nil
    ) {
        self.id = id
        self.spokenForm = spokenForm
        self.replacement = replacement
        self.language = language
        self.isGlobal = isGlobal
        self.caseSensitive = caseSensitive
        self.appProfile = appProfile
    }

    // MARK: - Matching

    /// Tests whether this entry matches the given text.
    func matches(in text: String) -> Bool {
        if caseSensitive {
            return text.contains(spokenForm)
        } else {
            return text.localizedCaseInsensitiveContains(spokenForm)
        }
    }

    /// Applies the replacement to the given text.
    func apply(to text: String) -> String {
        if caseSensitive {
            return text.replacingOccurrences(of: spokenForm, with: replacement)
        } else {
            return text.replacingOccurrences(
                of: spokenForm,
                with: replacement,
                options: .caseInsensitive
            )
        }
    }
}
