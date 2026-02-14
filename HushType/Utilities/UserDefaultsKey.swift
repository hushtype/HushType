import Foundation

// MARK: - UserDefaults Key Registry

/// Centralized registry of all UserDefaults keys used by HushType.
///
/// All keys use the `com.hushtype` prefix to avoid collisions with other
/// defaults domains. These keys store lightweight, non-sensitive state
/// that does not require SwiftData or Keychain.
enum UserDefaultsKey {
    // MARK: - Onboarding

    static let hasCompletedOnboarding = "com.hushtype.hasCompletedOnboarding"
    static let onboardingVersion = "com.hushtype.onboardingVersion"

    // MARK: - Feature Flags

    static let experimentalFeaturesEnabled = "com.hushtype.experimentalFeaturesEnabled"
    static let betaUpdatesEnabled = "com.hushtype.betaUpdatesEnabled"

    // MARK: - Window State

    static let settingsWindowFrame = "com.hushtype.settingsWindowFrame"
    static let historyWindowFrame = "com.hushtype.historyWindowFrame"
    static let lastActiveSettingsTab = "com.hushtype.lastActiveSettingsTab"

    // MARK: - Cache & Timestamps

    static let lastModelRegistryUpdate = "com.hushtype.lastModelRegistryUpdate"
    static let lastHistoryCleanup = "com.hushtype.lastHistoryCleanup"
    static let lastVocabularySync = "com.hushtype.lastVocabularySync"

    // MARK: - Usage State

    static let totalDictationCount = "com.hushtype.totalDictationCount"
    static let totalAudioDuration = "com.hushtype.totalAudioDuration"
    static let lastUsedLanguage = "com.hushtype.lastUsedLanguage"
    static let lastUsedMode = "com.hushtype.lastUsedMode"

    // MARK: - Permissions

    static let hasRequestedAccessibility = "com.hushtype.hasRequestedAccessibility"
    static let hasRequestedMicrophone = "com.hushtype.hasRequestedMicrophone"

    // MARK: - UI State

    static let menuBarIconStyle = "com.hushtype.menuBarIconStyle"
    static let recordingIndicatorPosition = "com.hushtype.recordingIndicatorPosition"
    static let historySearchScope = "com.hushtype.historySearchScope"
}

// MARK: - Type-Safe Property Wrapper

/// Property wrapper for type-safe UserDefaults access.
///
/// Usage:
/// ```swift
/// @AppDefault(UserDefaultsKey.hasCompletedOnboarding, defaultValue: false)
/// var hasCompletedOnboarding: Bool
/// ```
@propertyWrapper
struct AppDefault<Value> {
    let key: String
    let defaultValue: Value
    let defaults: UserDefaults

    init(
        _ key: String,
        defaultValue: Value,
        defaults: UserDefaults = .standard
    ) {
        self.key = key
        self.defaultValue = defaultValue
        self.defaults = defaults
    }

    var wrappedValue: Value {
        get {
            defaults.object(forKey: key) as? Value ?? defaultValue
        }
        set {
            defaults.set(newValue, forKey: key)
        }
    }
}
