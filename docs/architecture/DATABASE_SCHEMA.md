Last Updated: 2026-02-13

# Database Schema & Local Persistence

> Complete specification of VaulType's local data persistence layer — SwiftData models, UserDefaults keys, Keychain items, migration strategy, and data lifecycle management.

## Table of Contents

- [Storage Architecture Overview](#storage-architecture-overview)
- [SwiftData Model Definitions](#swiftdata-model-definitions)
  - [Enums](#enums)
  - [DictationEntry](#dictationentry)
  - [PromptTemplate](#prompttemplate)
  - [AppProfile](#appprofile)
  - [VocabularyEntry](#vocabularyentry)
  - [UserSettings](#usersettings)
  - [ModelInfo](#modelinfo)
- [Model Relationships](#model-relationships)
- [UserDefaults Keys](#userdefaults-keys)
- [Keychain Items](#keychain-items)
- [Migration Strategy](#migration-strategy)
- [Data Export/Import Format](#data-exportimport-format)
- [Data Lifecycle](#data-lifecycle)
- [Privacy Considerations](#privacy-considerations)
- [Related Documentation](#related-documentation)

---

## Storage Architecture Overview

VaulType uses a three-tier local storage architecture. Every byte of user data remains on-device — there are no network calls, no cloud sync, and no telemetry of any kind.

```
┌─────────────────────────────────────────────────────────────────────┐
│                        VaulType Application                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                    SwiftData (Primary Store)                  │  │
│  │                                                               │  │
│  │  ┌──────────────┐  ┌───────────────┐  ┌──────────────────┐   │  │
│  │  │DictationEntry│  │PromptTemplate │  │   AppProfile     │   │  │
│  │  │              │  │               │  │                  │   │  │
│  │  │ Transcription│  │ LLM prompt    │  │ Per-app config   │   │  │
│  │  │ history &    │  │ templates for │  │ & vocabulary     │   │  │
│  │  │ metadata     │  │ post-process  │  │ preferences      │   │  │
│  │  └──────────────┘  └───────────────┘  └────────┬─────────┘   │  │
│  │                                                 │             │  │
│  │  ┌──────────────┐  ┌───────────────┐  ┌────────▼─────────┐   │  │
│  │  │ UserSettings │  │   ModelInfo   │  │VocabularyEntry   │   │  │
│  │  │  (singleton) │  │              │  │                  │   │  │
│  │  │ All app-wide │  │ ML model     │  │ Custom word      │   │  │
│  │  │ preferences  │  │ registry &   │  │ replacements     │   │  │
│  │  │ & config     │  │ download state│  │ (global/per-app) │   │  │
│  │  └──────────────┘  └───────────────┘  └──────────────────┘   │  │
│  │                                                               │  │
│  │  Location: ~/Library/Application Support/VaulType/            │  │
│  │  File:     VaulType.store (SQLite)                            │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │              UserDefaults (Lightweight Settings)              │  │
│  │                                                               │  │
│  │  • Onboarding state        • Window positions                │  │
│  │  • Feature flags           • Last-used values                │  │
│  │  • UI preferences          • Cache timestamps                │  │
│  │                                                               │  │
│  │  Location: ~/Library/Preferences/                             │  │
│  │  File:     com.vaultype.app.plist                             │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                   Keychain (Sensitive Data)                   │  │
│  │                                                               │  │
│  │  • Remote Ollama API keys  • License keys (future)           │  │
│  │  • Encrypted credentials   • Auth tokens (future)            │  │
│  │                                                               │  │
│  │  Location: macOS Keychain Services (encrypted by Secure       │  │
│  │            Enclave on Apple Silicon)                           │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Storage responsibility boundaries:**

| Storage Layer | Purpose | Data Sensitivity | Persistence |
|---|---|---|---|
| **SwiftData** | Structured domain data, relationships, queryable history | Medium — transcription text, user templates | App lifecycle, survives updates |
| **UserDefaults** | Simple key-value preferences, UI state, feature flags | Low — no PII, no content | App lifecycle, survives updates |
| **Keychain** | Secrets, API keys, credentials | High — encrypted at rest | Survives app deletion, user-controlled |

> 🔒 **Security**: All three storage tiers benefit from macOS FileVault full-disk encryption when enabled. The Keychain additionally uses hardware-backed encryption via the Secure Enclave on Apple Silicon Macs.

---

## SwiftData Model Definitions

### SwiftData Container Configuration

The SwiftData model container is configured at app launch and shared throughout the application via the SwiftUI environment.

```swift
import SwiftData
import SwiftUI

@main
struct VaulTypeApp: App {
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
            "VaulType",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        do {
            modelContainer = try ModelContainer(
                for: schema,
                migrationPlan: VaulTypeMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            fatalError("Failed to initialize SwiftData container: \(error)")
        }
    }

    var body: some Scene {
        MenuBarExtra("VaulType", systemImage: "mic.fill") {
            MenuBarView()
        }
        .modelContainer(modelContainer)

        Settings {
            SettingsView()
        }
        .modelContainer(modelContainer)
    }
}
```

> 🍎 **macOS-specific**: The `ModelContainer` is attached to both the `MenuBarExtra` scene and the `Settings` scene so that all windows share the same data store. On macOS, there is no equivalent of iOS's scene-based lifecycle — the container lives for the entire app process.

---

### Enums

All enums used across models are defined as `String`-backed, `Codable` types so they serialize cleanly into SwiftData's underlying SQLite storage.

```swift
import Foundation

// MARK: - Processing Mode

/// Defines how transcribed text is post-processed before injection.
enum ProcessingMode: String, Codable, CaseIterable, Identifiable {
    /// Raw transcription output — no post-processing applied.
    case raw

    /// Clean up punctuation, capitalization, and filler words.
    case clean

    /// Structure into paragraphs, lists, or headings based on content.
    case structure

    /// Apply a user-defined LLM prompt template.
    case prompt

    /// Optimize output for code — variable names, syntax, formatting.
    case code

    /// Fully custom pipeline with user-defined pre/post processors.
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .raw: "Raw Transcription"
        case .clean: "Clean Text"
        case .structure: "Structured Output"
        case .prompt: "Prompt Template"
        case .code: "Code Mode"
        case .custom: "Custom Pipeline"
        }
    }

    var description: String {
        switch self {
        case .raw: "Unprocessed whisper output exactly as transcribed"
        case .clean: "Removes filler words, fixes punctuation and capitalization"
        case .structure: "Organizes text into paragraphs, lists, or headings"
        case .prompt: "Processes text through a custom LLM prompt template"
        case .code: "Optimized for dictating source code and technical content"
        case .custom: "User-defined processing pipeline with custom rules"
        }
    }

    /// Whether this mode requires the LLM engine to be loaded.
    var requiresLLM: Bool {
        switch self {
        case .raw: false
        case .clean, .structure, .prompt, .code, .custom: true
        }
    }
}

// MARK: - Model Type

/// Categorizes ML models used by VaulType.
enum ModelType: String, Codable, CaseIterable, Identifiable {
    /// Whisper speech-to-text model (whisper.cpp compatible).
    case whisper

    /// Large language model for post-processing (llama.cpp compatible).
    case llm

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .whisper: "Speech-to-Text (Whisper)"
        case .llm: "Language Model (LLM)"
        }
    }

    /// File extension expected for this model type.
    var expectedExtension: String {
        switch self {
        case .whisper: "bin"
        case .llm: "gguf"
        }
    }

    /// Directory name within the app's model storage.
    var storageDirectory: String {
        switch self {
        case .whisper: "whisper-models"
        case .llm: "llm-models"
        }
    }
}

// MARK: - Injection Method

/// How transcribed text is injected into the target application.
enum InjectionMethod: String, Codable, CaseIterable, Identifiable {
    /// Simulate keyboard events via CGEvent (most compatible, requires
    /// Accessibility permission).
    case cgEvent

    /// Copy to clipboard and paste via Cmd+V (fallback for apps that
    /// block synthetic keyboard events).
    case clipboard

    /// Automatically detect the best method for the target app.
    case auto

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cgEvent: "Keyboard Simulation (CGEvent)"
        case .clipboard: "Clipboard Paste"
        case .auto: "Automatic Detection"
        }
    }

    var description: String {
        switch self {
        case .cgEvent:
            "Simulates keystrokes directly — preserves clipboard contents "
            + "but requires Accessibility permission"
        case .clipboard:
            "Copies text to clipboard and pastes — works everywhere but "
            + "overwrites clipboard contents"
        case .auto:
            "Tries CGEvent first, falls back to clipboard if the target "
            + "app blocks synthetic events"
        }
    }
}
```

> ℹ️ **Info**: All enums conform to `CaseIterable` and `Identifiable` for seamless use in SwiftUI pickers and lists. The `String` raw value ensures human-readable SQLite storage and straightforward debugging.

---

### DictationEntry

Stores every transcription event with full metadata for history, analytics, and search.

```swift
import Foundation
import SwiftData

@Model
final class DictationEntry {
    // MARK: - Identity

    /// Unique identifier for this entry.
    @Attribute(.unique)
    var id: UUID

    // MARK: - Content

    /// Raw transcription text from whisper.cpp before any post-processing.
    var rawText: String

    /// Post-processed text after LLM processing, or nil if mode is .raw.
    var processedText: String?

    /// The processing mode used for this transcription.
    var mode: ProcessingMode

    /// BCP-47 language code of the detected or selected language (e.g., "en", "tr").
    var language: String

    // MARK: - Target Application Context

    /// Bundle identifier of the app that was focused when dictation occurred.
    var appBundleIdentifier: String?

    /// Display name of the focused application.
    var appName: String?

    // MARK: - Metrics

    /// Duration of the audio recording in seconds.
    var audioDuration: TimeInterval

    /// Number of words in the final output text (processedText ?? rawText).
    var wordCount: Int

    // MARK: - Metadata

    /// When this transcription was created.
    var timestamp: Date

    /// Whether the user has marked this entry as a favorite.
    var isFavorite: Bool

    // MARK: - Initializer

    init(
        id: UUID = UUID(),
        rawText: String,
        processedText: String? = nil,
        mode: ProcessingMode = .raw,
        language: String = "en",
        appBundleIdentifier: String? = nil,
        appName: String? = nil,
        audioDuration: TimeInterval = 0,
        wordCount: Int = 0,
        timestamp: Date = .now,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.rawText = rawText
        self.processedText = processedText
        self.mode = mode
        self.language = language
        self.appBundleIdentifier = appBundleIdentifier
        self.appName = appName
        self.audioDuration = audioDuration
        self.wordCount = wordCount
        self.timestamp = timestamp
        self.isFavorite = isFavorite
    }

    // MARK: - Computed Properties

    /// The text that was actually delivered to the target application.
    var outputText: String {
        processedText ?? rawText
    }

    /// Words per minute based on audio duration.
    var wordsPerMinute: Double {
        guard audioDuration > 0 else { return 0 }
        return Double(wordCount) / (audioDuration / 60.0)
    }
}
```

**Field Reference:**

| Field | Type | Required | Default | Description |
|---|---|---|---|---|
| `id` | `UUID` | Yes | `UUID()` | Unique identifier, indexed |
| `rawText` | `String` | Yes | — | Raw whisper.cpp transcription output |
| `processedText` | `String?` | No | `nil` | LLM-processed text, nil if mode is `.raw` |
| `mode` | `ProcessingMode` | Yes | `.raw` | Processing mode applied to this entry |
| `language` | `String` | Yes | `"en"` | BCP-47 language code |
| `appBundleIdentifier` | `String?` | No | `nil` | Target app bundle ID (e.g., `com.apple.dt.Xcode`) |
| `appName` | `String?` | No | `nil` | Target app display name (e.g., "Xcode") |
| `audioDuration` | `TimeInterval` | Yes | `0` | Recording duration in seconds |
| `wordCount` | `Int` | Yes | `0` | Word count of the output text |
| `timestamp` | `Date` | Yes | `.now` | Creation timestamp |
| `isFavorite` | `Bool` | Yes | `false` | User favorite flag |

> 💡 **Tip**: Use `#Predicate` with `DictationEntry` for efficient queries. SwiftData translates predicates into SQL, so filtering by `timestamp`, `appBundleIdentifier`, or `isFavorite` is performant even with thousands of entries.

```swift
// Example: Fetch today's entries for a specific app
let today = Calendar.current.startOfDay(for: .now)
let bundleId = "com.apple.dt.Xcode"

let descriptor = FetchDescriptor<DictationEntry>(
    predicate: #Predicate {
        $0.timestamp >= today && $0.appBundleIdentifier == bundleId
    },
    sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
)
let entries = try modelContext.fetch(descriptor)
```

---

### PromptTemplate

Stores reusable LLM prompt templates for post-processing transcriptions.

```swift
import Foundation
import SwiftData

@Model
final class PromptTemplate {
    // MARK: - Identity

    @Attribute(.unique)
    var id: UUID

    // MARK: - Template Definition

    /// Human-readable name for this template (e.g., "Email Draft", "Meeting Notes").
    var name: String

    /// The processing mode this template is associated with.
    var mode: ProcessingMode

    /// System prompt sent to the LLM to define its role and behavior.
    ///
    /// Example: "You are a professional editor. Clean up the following dictated
    /// text while preserving the speaker's intent and tone."
    var systemPrompt: String

    /// User prompt template with variable placeholders.
    ///
    /// Variables are enclosed in double braces: `{{variable_name}}`.
    /// The `{{transcription}}` variable is always available and contains
    /// the raw whisper output.
    ///
    /// Example: "Rewrite this as a {{tone}} email:\n\n{{transcription}}"
    var userPromptTemplate: String

    /// List of variable names used in `userPromptTemplate` (excluding
    /// the built-in `transcription` variable).
    var variables: [String]

    // MARK: - Metadata

    /// Whether this template ships with the app and cannot be deleted.
    var isBuiltIn: Bool

    /// Whether this is the default template for its associated mode.
    var isDefault: Bool

    /// When this template was created.
    var createdAt: Date

    /// When this template was last modified.
    var updatedAt: Date

    // MARK: - Initializer

    init(
        id: UUID = UUID(),
        name: String,
        mode: ProcessingMode,
        systemPrompt: String,
        userPromptTemplate: String,
        variables: [String] = [],
        isBuiltIn: Bool = false,
        isDefault: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.systemPrompt = systemPrompt
        self.userPromptTemplate = userPromptTemplate
        self.variables = variables
        self.isBuiltIn = isBuiltIn
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Template Rendering

    /// Renders the user prompt by substituting variables.
    ///
    /// - Parameters:
    ///   - transcription: The raw transcribed text from whisper.cpp.
    ///   - values: Dictionary mapping variable names to their values.
    /// - Returns: The fully rendered prompt string.
    func render(
        transcription: String,
        values: [String: String] = [:]
    ) -> String {
        var result = userPromptTemplate
        result = result.replacingOccurrences(
            of: "{{transcription}}",
            with: transcription
        )
        for (key, value) in values {
            result = result.replacingOccurrences(
                of: "{{\(key)}}",
                with: value
            )
        }
        return result
    }
}
```

**Field Reference:**

| Field | Type | Required | Default | Description |
|---|---|---|---|---|
| `id` | `UUID` | Yes | `UUID()` | Unique identifier |
| `name` | `String` | Yes | — | Human-readable template name |
| `mode` | `ProcessingMode` | Yes | — | Associated processing mode |
| `systemPrompt` | `String` | Yes | — | LLM system prompt |
| `userPromptTemplate` | `String` | Yes | — | User prompt with `{{variable}}` placeholders |
| `variables` | `[String]` | Yes | `[]` | Variable names used in the template |
| `isBuiltIn` | `Bool` | Yes | `false` | Ships with app, cannot be deleted |
| `isDefault` | `Bool` | Yes | `false` | Default template for its mode |
| `createdAt` | `Date` | Yes | `.now` | Creation timestamp |
| `updatedAt` | `Date` | Yes | `.now` | Last modification timestamp |

> ⚠️ **Warning**: Built-in templates (`isBuiltIn == true`) should never be deleted by user actions. The UI must disable the delete button for these entries. If a user "resets" a built-in template, restore the original content rather than deleting and recreating it.

**Built-in templates seeded on first launch:**

```swift
extension PromptTemplate {
    static let builtInTemplates: [PromptTemplate] = [
        PromptTemplate(
            name: "Clean Transcript",
            mode: .clean,
            systemPrompt: """
                You are a text editor. Clean up the following dictated text. \
                Fix punctuation, capitalization, and remove filler words \
                (um, uh, like, you know). Preserve the speaker's original \
                meaning and tone. Do not add or change content.
                """,
            userPromptTemplate: "{{transcription}}",
            isBuiltIn: true,
            isDefault: true
        ),
        PromptTemplate(
            name: "Structured Notes",
            mode: .structure,
            systemPrompt: """
                You are a note-taking assistant. Organize the following \
                dictated text into well-structured notes with headings, \
                bullet points, and paragraphs as appropriate. Preserve \
                all information.
                """,
            userPromptTemplate: "{{transcription}}",
            isBuiltIn: true,
            isDefault: true
        ),
        PromptTemplate(
            name: "Code Dictation",
            mode: .code,
            systemPrompt: """
                You are a code transcription assistant. Convert the \
                following spoken programming instructions into valid \
                source code. Interpret spoken syntax naturally \
                (e.g., "open paren" → "(", "new line" → line break). \
                Output only the code, no explanations.
                """,
            userPromptTemplate: """
                Language: {{language}}

                {{transcription}}
                """,
            variables: ["language"],
            isBuiltIn: true,
            isDefault: true
        ),
        PromptTemplate(
            name: "Email Draft",
            mode: .prompt,
            systemPrompt: """
                You are a professional email writer. Convert the following \
                dictated thoughts into a well-formatted email. Use a \
                {{tone}} tone. Include a subject line.
                """,
            userPromptTemplate: """
                Tone: {{tone}}
                Recipient: {{recipient}}

                {{transcription}}
                """,
            variables: ["tone", "recipient"],
            isBuiltIn: true,
            isDefault: true
        )
    ]
}
```

---

### AppProfile

Per-application configuration that allows VaulType to behave differently depending on which app is focused.

```swift
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
```

**Field Reference:**

| Field | Type | Required | Default | Description |
|---|---|---|---|---|
| `id` | `UUID` | Yes | `UUID()` | Unique identifier |
| `bundleIdentifier` | `String` | Yes | — | macOS app bundle ID (unique constraint) |
| `appName` | `String` | Yes | — | Display name |
| `defaultMode` | `ProcessingMode?` | No | `nil` | Override global processing mode |
| `customVocabulary` | `[String]` | Yes | `[]` | Technical terms for this app |
| `preferredLanguage` | `String?` | No | `nil` | Override global language |
| `injectionMethod` | `InjectionMethod` | Yes | `.auto` | Text injection strategy |
| `isEnabled` | `Bool` | Yes | `true` | Profile active flag |
| `vocabularyEntries` | `[VocabularyEntry]` | Yes | `[]` | Related vocabulary entries (cascade delete) |

> 🍎 **macOS-specific**: The `bundleIdentifier` is obtained at runtime from `NSWorkspace.shared.frontmostApplication?.bundleIdentifier`. VaulType auto-creates AppProfile records the first time a user dictates into an unrecognized application, populating `appName` from the running app's `localizedName`.

```swift
// Example: Auto-create profile for the current app
func getOrCreateProfile(
    for app: NSRunningApplication,
    in context: ModelContext
) throws -> AppProfile {
    guard let bundleId = app.bundleIdentifier else {
        throw AppProfileError.noBundleIdentifier
    }

    let descriptor = FetchDescriptor<AppProfile>(
        predicate: #Predicate { $0.bundleIdentifier == bundleId }
    )

    if let existing = try context.fetch(descriptor).first {
        return existing
    }

    let profile = AppProfile(
        bundleIdentifier: bundleId,
        appName: app.localizedName ?? bundleId
    )
    context.insert(profile)
    return profile
}
```

---

### VocabularyEntry

Custom word replacements that correct common whisper misrecognitions or expand abbreviations.

```swift
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
```

**Field Reference:**

| Field | Type | Required | Default | Description |
|---|---|---|---|---|
| `id` | `UUID` | Yes | `UUID()` | Unique identifier |
| `spokenForm` | `String` | Yes | — | Text to find (whisper's output) |
| `replacement` | `String` | Yes | — | Text to substitute |
| `language` | `String?` | No | `nil` | Limit to specific language |
| `isGlobal` | `Bool` | Yes | `true` | Applies to all apps when true |
| `caseSensitive` | `Bool` | Yes | `false` | Case-sensitive matching |
| `appProfile` | `AppProfile?` | No | `nil` | Parent app profile (inverse relationship) |

> ✅ **Do**: Create global vocabulary entries for universally misrecognized terms like product names, technical acronyms, and proper nouns.
>
> ❌ **Don't**: Create vocabulary entries for common words — these should be handled by the LLM post-processing step instead.

**Example vocabulary entries:**

```swift
// Global entries for commonly misrecognized tech terms
let globalEntries: [VocabularyEntry] = [
    VocabularyEntry(spokenForm: "ecks code", replacement: "Xcode"),
    VocabularyEntry(spokenForm: "jay son", replacement: "JSON"),
    VocabularyEntry(spokenForm: "swift you eye", replacement: "SwiftUI"),
    VocabularyEntry(spokenForm: "gee p t", replacement: "GPT"),
    VocabularyEntry(spokenForm: "git hub", replacement: "GitHub"),
    VocabularyEntry(spokenForm: "hush type", replacement: "VaulType"),
]

// App-specific entry for Xcode
let xcodeEntry = VocabularyEntry(
    spokenForm: "build and run",
    replacement: "⌘R",
    isGlobal: false,
    appProfile: xcodeProfile
)
```

---

### UserSettings

A singleton model that stores all application-wide preferences. Only one instance of this model should ever exist.

```swift
import Foundation
import SwiftData

@Model
final class UserSettings {
    // MARK: - Identity

    /// Singleton identifier — always "default".
    @Attribute(.unique)
    var id: String

    // MARK: - Model Selection

    /// File name of the currently selected whisper.cpp model.
    var selectedWhisperModel: String

    /// File name of the currently selected llama.cpp model.
    var selectedLLMModel: String?

    // MARK: - Input Configuration

    /// Global keyboard shortcut for toggling dictation (serialized).
    /// Format: modifiers+keyCode (e.g., "cmd+shift+space").
    var globalHotkey: String

    /// Whether push-to-talk mode is enabled (hold to record, release to stop).
    /// When false, toggle mode is used (press to start, press to stop).
    var pushToTalkEnabled: Bool

    /// Audio input device identifier. Nil means use system default.
    var audioInputDeviceID: String?

    // MARK: - Processing Defaults

    /// Default processing mode applied when no AppProfile override exists.
    var defaultMode: ProcessingMode

    /// Default BCP-47 language code for transcription.
    var defaultLanguage: String

    /// Whether to auto-detect the spoken language (overrides defaultLanguage).
    var autoDetectLanguage: Bool

    // MARK: - UI Preferences

    /// Launch VaulType at macOS login.
    var launchAtLogin: Bool

    /// Show the VaulType icon in the menu bar.
    var showMenuBarIcon: Bool

    /// Show a floating indicator while recording.
    var showRecordingIndicator: Bool

    /// Play audio feedback when recording starts/stops.
    var playSoundEffects: Bool

    // MARK: - History & Privacy

    /// Maximum number of DictationEntry records to retain.
    /// 0 means unlimited. Oldest entries are purged first.
    var maxHistoryEntries: Int

    /// Number of days to retain DictationEntry records.
    /// 0 means indefinite retention.
    var historyRetentionDays: Int

    /// Whether to store the raw transcription text in history.
    /// When false, only metadata (duration, word count, timestamp) is kept.
    var storeTranscriptionText: Bool

    // MARK: - Performance

    /// Number of CPU threads for whisper.cpp inference.
    /// 0 means auto-detect (use physical core count).
    var whisperThreadCount: Int

    /// Whether to use Metal GPU acceleration for whisper.cpp.
    var useGPUAcceleration: Bool

    /// Maximum context length (tokens) for LLM inference.
    var llmContextLength: Int

    // MARK: - Text Injection

    /// Default text injection method when no AppProfile override exists.
    var defaultInjectionMethod: InjectionMethod

    /// Delay in milliseconds between simulated keystrokes (CGEvent mode).
    var keystrokeDelay: Int

    // MARK: - Initializer

    init(
        id: String = "default",
        selectedWhisperModel: String = "ggml-base.en.bin",
        selectedLLMModel: String? = nil,
        globalHotkey: String = "cmd+shift+space",
        pushToTalkEnabled: Bool = false,
        audioInputDeviceID: String? = nil,
        defaultMode: ProcessingMode = .clean,
        defaultLanguage: String = "en",
        autoDetectLanguage: Bool = false,
        launchAtLogin: Bool = false,
        showMenuBarIcon: Bool = true,
        showRecordingIndicator: Bool = true,
        playSoundEffects: Bool = true,
        maxHistoryEntries: Int = 5000,
        historyRetentionDays: Int = 90,
        storeTranscriptionText: Bool = true,
        whisperThreadCount: Int = 0,
        useGPUAcceleration: Bool = true,
        llmContextLength: Int = 2048,
        defaultInjectionMethod: InjectionMethod = .auto,
        keystrokeDelay: Int = 5
    ) {
        self.id = id
        self.selectedWhisperModel = selectedWhisperModel
        self.selectedLLMModel = selectedLLMModel
        self.globalHotkey = globalHotkey
        self.pushToTalkEnabled = pushToTalkEnabled
        self.audioInputDeviceID = audioInputDeviceID
        self.defaultMode = defaultMode
        self.defaultLanguage = defaultLanguage
        self.autoDetectLanguage = autoDetectLanguage
        self.launchAtLogin = launchAtLogin
        self.showMenuBarIcon = showMenuBarIcon
        self.showRecordingIndicator = showRecordingIndicator
        self.playSoundEffects = playSoundEffects
        self.maxHistoryEntries = maxHistoryEntries
        self.historyRetentionDays = historyRetentionDays
        self.storeTranscriptionText = storeTranscriptionText
        self.whisperThreadCount = whisperThreadCount
        self.useGPUAcceleration = useGPUAcceleration
        self.llmContextLength = llmContextLength
        self.defaultInjectionMethod = defaultInjectionMethod
        self.keystrokeDelay = keystrokeDelay
    }

    // MARK: - Singleton Access

    /// Fetches the singleton UserSettings, creating a default instance if needed.
    @MainActor
    static func shared(in context: ModelContext) throws -> UserSettings {
        let descriptor = FetchDescriptor<UserSettings>(
            predicate: #Predicate { $0.id == "default" }
        )

        if let existing = try context.fetch(descriptor).first {
            return existing
        }

        let settings = UserSettings()
        context.insert(settings)
        return settings
    }
}
```

**Field Reference:**

| Field | Type | Default | Description |
|---|---|---|---|
| `id` | `String` | `"default"` | Singleton key (always "default") |
| `selectedWhisperModel` | `String` | `"ggml-base.en.bin"` | Active whisper model filename |
| `selectedLLMModel` | `String?` | `nil` | Active LLM model filename |
| `globalHotkey` | `String` | `"cmd+shift+space"` | Global keyboard shortcut |
| `pushToTalkEnabled` | `Bool` | `false` | Hold-to-record vs toggle mode |
| `audioInputDeviceID` | `String?` | `nil` | Audio input device (nil = system default) |
| `defaultMode` | `ProcessingMode` | `.clean` | Default processing mode |
| `defaultLanguage` | `String` | `"en"` | Default language code |
| `autoDetectLanguage` | `Bool` | `false` | Auto-detect spoken language |
| `launchAtLogin` | `Bool` | `false` | Start at macOS login |
| `showMenuBarIcon` | `Bool` | `true` | Menu bar icon visibility |
| `showRecordingIndicator` | `Bool` | `true` | Floating recording indicator |
| `playSoundEffects` | `Bool` | `true` | Audio feedback |
| `maxHistoryEntries` | `Int` | `5000` | Max history records (0 = unlimited) |
| `historyRetentionDays` | `Int` | `90` | Days to keep history (0 = forever) |
| `storeTranscriptionText` | `Bool` | `true` | Store text in history |
| `whisperThreadCount` | `Int` | `0` | CPU threads (0 = auto) |
| `useGPUAcceleration` | `Bool` | `true` | Metal GPU acceleration |
| `llmContextLength` | `Int` | `2048` | LLM context window size |
| `defaultInjectionMethod` | `InjectionMethod` | `.auto` | Default text injection method |
| `keystrokeDelay` | `Int` | `5` | Delay between keystrokes (ms) |

> ⚠️ **Warning**: The singleton pattern is enforced by the `@Attribute(.unique)` constraint on `id` and the `shared(in:)` factory method. Never create `UserSettings` instances directly outside of the `shared(in:)` method. Multiple instances with different `id` values will cause undefined behavior.

---

### ModelInfo

Registry of all ML models (whisper.cpp and llama.cpp) known to the application, including download state tracking.

```swift
import Foundation
import SwiftData

@Model
final class ModelInfo {
    // MARK: - Identity

    @Attribute(.unique)
    var id: UUID

    // MARK: - Model Metadata

    /// Human-readable model name (e.g., "Whisper Base English", "Llama 3.2 1B").
    var name: String

    /// Whether this is a whisper STT model or an LLM.
    var type: ModelType

    /// The filename on disk (e.g., "ggml-base.en.bin", "llama-3.2-1b.Q4_K_M.gguf").
    @Attribute(.unique)
    var fileName: String

    /// Size of the model file in bytes.
    var fileSize: Int64

    // MARK: - Download State

    /// URL to download this model from. Nil for manually imported models.
    var downloadURL: URL?

    /// Whether the model file exists on disk and is ready for inference.
    var isDownloaded: Bool

    /// Whether this is the default model for its type.
    var isDefault: Bool

    /// Current download progress (0.0 to 1.0). Nil if not downloading.
    var downloadProgress: Double?

    // MARK: - Usage Tracking

    /// When this model was last used for inference.
    var lastUsed: Date?

    // MARK: - Initializer

    init(
        id: UUID = UUID(),
        name: String,
        type: ModelType,
        fileName: String,
        fileSize: Int64,
        downloadURL: URL? = nil,
        isDownloaded: Bool = false,
        isDefault: Bool = false,
        downloadProgress: Double? = nil,
        lastUsed: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.fileName = fileName
        self.fileSize = fileSize
        self.downloadURL = downloadURL
        self.isDownloaded = isDownloaded
        self.isDefault = isDefault
        self.downloadProgress = downloadProgress
        self.lastUsed = lastUsed
    }

    // MARK: - Computed Properties

    /// Human-readable file size string (e.g., "142 MB", "4.7 GB").
    var formattedFileSize: String {
        ByteCountFormatter.string(
            fromByteCount: fileSize,
            countStyle: .file
        )
    }

    /// The full path to the model file on disk.
    var filePath: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        return appSupport
            .appendingPathComponent("VaulType", isDirectory: true)
            .appendingPathComponent(type.storageDirectory, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    /// Verifies the model file actually exists at the expected path.
    var fileExistsOnDisk: Bool {
        FileManager.default.fileExists(atPath: filePath.path)
    }
}
```

**Field Reference:**

| Field | Type | Required | Default | Description |
|---|---|---|---|---|
| `id` | `UUID` | Yes | `UUID()` | Unique identifier |
| `name` | `String` | Yes | — | Human-readable model name |
| `type` | `ModelType` | Yes | — | `.whisper` or `.llm` |
| `fileName` | `String` | Yes | — | Filename on disk (unique constraint) |
| `fileSize` | `Int64` | Yes | — | File size in bytes |
| `downloadURL` | `URL?` | No | `nil` | Source URL for downloading |
| `isDownloaded` | `Bool` | Yes | `false` | File exists and is ready |
| `isDefault` | `Bool` | Yes | `false` | Default model for its type |
| `downloadProgress` | `Double?` | No | `nil` | Download progress 0.0-1.0 |
| `lastUsed` | `Date?` | No | `nil` | Last inference timestamp |

**Pre-seeded model registry:**

```swift
extension ModelInfo {
    static let defaultModels: [ModelInfo] = [
        // Whisper models
        ModelInfo(
            name: "Whisper Tiny (English)",
            type: .whisper,
            fileName: "ggml-tiny.en.bin",
            fileSize: 77_691_713,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin"),
            isDefault: false
        ),
        ModelInfo(
            name: "Whisper Base (English)",
            type: .whisper,
            fileName: "ggml-base.en.bin",
            fileSize: 147_951_465,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"),
            isDefault: true
        ),
        ModelInfo(
            name: "Whisper Small (English)",
            type: .whisper,
            fileName: "ggml-small.en.bin",
            fileSize: 487_601_967,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin"),
            isDefault: false
        ),
        ModelInfo(
            name: "Whisper Medium (English)",
            type: .whisper,
            fileName: "ggml-medium.en.bin",
            fileSize: 1_533_774_781,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin"),
            isDefault: false
        ),
        ModelInfo(
            name: "Whisper Large v3 Turbo",
            type: .whisper,
            fileName: "ggml-large-v3-turbo.bin",
            fileSize: 1_622_089_216,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin"),
            isDefault: false
        ),
    ]
}
```

> 💡 **Tip**: Model downloads use `URLSession` background transfers. The `downloadProgress` field is updated via Combine publishers and observed by the UI in real time. If the app terminates during a download, the progress resets to `nil` and the download must be restarted.

---

## Model Relationships

```
┌─────────────────────────────────────────────────────────────────────┐
│                    SwiftData Model Relationships                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌──────────────┐                                                   │
│  │UserSettings  │  (singleton — no relationships)                   │
│  │  id="default"│                                                   │
│  └──────────────┘                                                   │
│                                                                     │
│  ┌──────────────┐                                                   │
│  │DictationEntry│  (standalone — references app by bundleId string) │
│  │              │                                                   │
│  │ appBundle ───┼─ ─ ─ ─ ─ (logical, not FK) ─ ─ ─ ─ ┐            │
│  │  Identifier  │                                      │            │
│  └──────────────┘                                      │            │
│                                                        ▼            │
│  ┌──────────────┐         1:N (cascade)        ┌──────────────┐     │
│  │  AppProfile  │─────────────────────────────▶│Vocabulary    │     │
│  │              │                               │  Entry       │     │
│  │ bundleId ◀───┼─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘              │     │
│  │              │                               │ appProfile ──┼──┐ │
│  └──────────────┘                               └──────────────┘  │ │
│        ▲                                                          │ │
│        └──────────────────────────────────────────────────────────┘ │
│                         inverse relationship                        │
│                                                                     │
│  ┌──────────────┐                                                   │
│  │PromptTemplate│  (standalone — referenced by ProcessingMode)      │
│  └──────────────┘                                                   │
│                                                                     │
│  ┌──────────────┐                                                   │
│  │  ModelInfo   │  (standalone — referenced by filename in          │
│  │              │   UserSettings.selectedWhisperModel/LLMModel)     │
│  └──────────────┘                                                   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Relationship details:**

| Parent | Child | Cardinality | Delete Rule | Inverse Property |
|---|---|---|---|---|
| `AppProfile` | `VocabularyEntry` | One-to-Many | `.cascade` | `VocabularyEntry.appProfile` |

**Logical references (not SwiftData relationships):**

| Source Model | Field | References | Target Model |
|---|---|---|---|
| `DictationEntry` | `appBundleIdentifier` | `bundleIdentifier` | `AppProfile` |
| `UserSettings` | `selectedWhisperModel` | `fileName` | `ModelInfo` |
| `UserSettings` | `selectedLLMModel` | `fileName` | `ModelInfo` |

> ℹ️ **Info**: The `DictationEntry` to `AppProfile` reference is intentionally a logical (string-based) reference rather than a SwiftData relationship. This ensures that deleting an `AppProfile` does not cascade-delete or nullify historical dictation entries. History is preserved independently of profile configuration.

---

## UserDefaults Keys

UserDefaults stores lightweight, non-sensitive state that does not require the relational capabilities of SwiftData. All keys use the `com.vaultype` prefix to avoid collisions.

```swift
import Foundation

enum UserDefaultsKey {
    // MARK: - Onboarding
    static let hasCompletedOnboarding = "com.vaultype.hasCompletedOnboarding"
    static let onboardingVersion = "com.vaultype.onboardingVersion"

    // MARK: - Feature Flags
    static let experimentalFeaturesEnabled = "com.vaultype.experimentalFeaturesEnabled"
    static let betaUpdatesEnabled = "com.vaultype.betaUpdatesEnabled"

    // MARK: - Window State
    static let settingsWindowFrame = "com.vaultype.settingsWindowFrame"
    static let historyWindowFrame = "com.vaultype.historyWindowFrame"
    static let lastActiveSettingsTab = "com.vaultype.lastActiveSettingsTab"

    // MARK: - Cache & Timestamps
    static let lastModelRegistryUpdate = "com.vaultype.lastModelRegistryUpdate"
    static let lastHistoryCleanup = "com.vaultype.lastHistoryCleanup"
    static let lastVocabularySync = "com.vaultype.lastVocabularySync"

    // MARK: - Usage State
    static let totalDictationCount = "com.vaultype.totalDictationCount"
    static let totalAudioDuration = "com.vaultype.totalAudioDuration"
    static let lastUsedLanguage = "com.vaultype.lastUsedLanguage"
    static let lastUsedMode = "com.vaultype.lastUsedMode"

    // MARK: - Permissions
    static let hasRequestedAccessibility = "com.vaultype.hasRequestedAccessibility"
    static let hasRequestedMicrophone = "com.vaultype.hasRequestedMicrophone"

    // MARK: - UI State
    static let menuBarIconStyle = "com.vaultype.menuBarIconStyle"
    static let recordingIndicatorPosition = "com.vaultype.recordingIndicatorPosition"
    static let historySearchScope = "com.vaultype.historySearchScope"
}
```

**Key Reference Table:**

| Key | Type | Default | Description |
|---|---|---|---|
| `hasCompletedOnboarding` | `Bool` | `false` | Onboarding flow completed |
| `onboardingVersion` | `Int` | `0` | Track which onboarding version was shown |
| `experimentalFeaturesEnabled` | `Bool` | `false` | Enable experimental features |
| `betaUpdatesEnabled` | `Bool` | `false` | Opt in to beta update channel |
| `settingsWindowFrame` | `String` | `""` | Serialized NSRect for window restore |
| `historyWindowFrame` | `String` | `""` | Serialized NSRect for window restore |
| `lastActiveSettingsTab` | `String` | `"general"` | Last visible settings tab identifier |
| `lastModelRegistryUpdate` | `Date` | `Date.distantPast` | When model registry was last refreshed |
| `lastHistoryCleanup` | `Date` | `Date.distantPast` | When expired history entries were purged |
| `lastVocabularySync` | `Date` | `Date.distantPast` | When vocabulary was last reloaded |
| `totalDictationCount` | `Int` | `0` | Lifetime dictation counter |
| `totalAudioDuration` | `Double` | `0.0` | Lifetime audio seconds |
| `lastUsedLanguage` | `String` | `"en"` | Most recently used language |
| `lastUsedMode` | `String` | `"clean"` | Most recently used processing mode |
| `hasRequestedAccessibility` | `Bool` | `false` | Accessibility permission dialog shown |
| `hasRequestedMicrophone` | `Bool` | `false` | Microphone permission dialog shown |
| `menuBarIconStyle` | `String` | `"default"` | Menu bar icon variant |
| `recordingIndicatorPosition` | `String` | `"topRight"` | Floating indicator screen position |
| `historySearchScope` | `String` | `"all"` | History search filter scope |

> ❌ **Don't**: Store sensitive data, transcription content, or large objects in UserDefaults. It is backed by a plist file that is not encrypted independently of FileVault and is easily readable.
>
> ✅ **Do**: Use UserDefaults exclusively for UI state, feature flags, and lightweight counters. Anything with PII or content belongs in SwiftData.

**Convenience wrapper with type safety:**

```swift
import Foundation

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

// Usage example
final class AppState {
    @AppDefault(
        UserDefaultsKey.hasCompletedOnboarding,
        defaultValue: false
    )
    var hasCompletedOnboarding: Bool

    @AppDefault(
        UserDefaultsKey.totalDictationCount,
        defaultValue: 0
    )
    var totalDictationCount: Int

    @AppDefault(
        UserDefaultsKey.lastUsedLanguage,
        defaultValue: "en"
    )
    var lastUsedLanguage: String
}
```

---

## Keychain Items

The macOS Keychain is used exclusively for data that requires hardware-backed encryption and must persist across app reinstalls. VaulType's local-first architecture means Keychain usage is minimal.

```swift
import Foundation
import Security

enum KeychainKey {
    /// API key for a remote Ollama instance (if user configures remote LLM).
    static let ollamaAPIKey = "com.vaultype.ollamaAPIKey"

    /// License key for future premium features.
    static let licenseKey = "com.vaultype.licenseKey"

    /// Encryption key for exported data files.
    static let exportEncryptionKey = "com.vaultype.exportEncryptionKey"
}
```

**Keychain Item Reference:**

| Key | Data Type | Access | Purpose |
|---|---|---|---|
| `ollamaAPIKey` | `String` (UTF-8) | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | API key for optional remote Ollama server connectivity |
| `licenseKey` | `String` (UTF-8) | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | Future: premium license validation |
| `exportEncryptionKey` | `Data` (256-bit) | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | Future: encrypt data exports with a user-defined passphrase-derived key |

> 🔒 **Security**: All Keychain items use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, which means:
> - Items are only accessible while the Mac is unlocked
> - Items are not included in unencrypted backups
> - Items are not transferred to a new device via Migration Assistant
> - On Apple Silicon, items are protected by the Secure Enclave

**Keychain helper:**

```swift
import Foundation
import Security

enum KeychainError: Error {
    case itemNotFound
    case duplicateItem
    case unexpectedStatus(OSStatus)
    case invalidData
}

struct KeychainManager {
    private static let service = "com.vaultype.app"

    /// Save a string value to the Keychain.
    static func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String:
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Delete existing item first
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Retrieve a string value from the Keychain.
    static func load(key: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }

        return string
    }

    /// Delete a value from the Keychain.
    static func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
```

> ℹ️ **Info**: In the default local-only configuration, VaulType stores nothing in the Keychain. Keychain usage is triggered only when a user explicitly configures a remote Ollama endpoint, which is an optional power-user feature.

---

## Migration Strategy

SwiftData provides a schema versioning and migration system via `SchemaMigrationPlan`. VaulType uses staged migrations to evolve the database schema safely across app updates.

### Version History

| Schema Version | App Version | Description |
|---|---|---|
| `VaulTypeSchemaV1` | 1.0.0 | Initial release schema |
| `VaulTypeSchemaV2` | 1.1.0 | Added `autoDetectLanguage` to UserSettings, added `lastUsed` to ModelInfo |
| `VaulTypeSchemaV3` | 1.2.0 | Added `VocabularyEntry.caseSensitive`, added `AppProfile.customVocabulary` |

### Migration Plan

```swift
import SwiftData

// MARK: - Schema Versions

enum VaulTypeSchemaV1: VersionedSchema {
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

enum VaulTypeSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 1, 0)
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

enum VaulTypeSchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 2, 0)
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

enum VaulTypeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            VaulTypeSchemaV1.self,
            VaulTypeSchemaV2.self,
            VaulTypeSchemaV3.self
        ]
    }

    static var stages: [MigrationStage] {
        [
            migrateV1toV2,
            migrateV2toV3
        ]
    }

    // MARK: - V1 → V2

    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: VaulTypeSchemaV1.self,
        toVersion: VaulTypeSchemaV2.self
    )

    // MARK: - V2 → V3

    static let migrateV2toV3 = MigrationStage.custom(
        fromVersion: VaulTypeSchemaV2.self,
        toVersion: VaulTypeSchemaV3.self,
        willMigrate: nil,
        didMigrate: { context in
            // Set default values for new fields on existing records.
            let vocabularyDescriptor = FetchDescriptor<VocabularyEntry>()
            let entries = try context.fetch(vocabularyDescriptor)
            for entry in entries {
                entry.caseSensitive = false
            }

            let profileDescriptor = FetchDescriptor<AppProfile>()
            let profiles = try context.fetch(profileDescriptor)
            for profile in profiles {
                profile.customVocabulary = []
            }

            try context.save()
        }
    )
}
```

### Migration Guidelines

> ✅ **Do**:
> - Use **lightweight migrations** for additive changes (new optional fields, new models) — SwiftData handles these automatically.
> - Use **custom migrations** when you need to populate default values for new non-optional fields or transform existing data.
> - Test migrations with production-scale data before release — create a test SQLite file with thousands of DictationEntry records.
> - Keep a backup of the database before destructive migrations.

> ❌ **Don't**:
> - Remove or rename model properties without a custom migration — this will cause data loss.
> - Change the type of an existing property in-place (e.g., `String` to `Int`) — always create a new property and migrate data.
> - Skip schema versions — migrations must be sequential (V1 to V2 to V3, never V1 to V3 directly).

**Pre-migration backup utility:**

```swift
import Foundation

struct DatabaseBackup {
    private static let storePath: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("VaulType", isDirectory: true)
    }()

    /// Creates a timestamped backup of the SwiftData store before migration.
    static func createPreMigrationBackup() throws -> URL {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = dateFormatter.string(from: .now)

        let backupDir = storePath
            .appendingPathComponent("backups", isDirectory: true)
        try FileManager.default.createDirectory(
            at: backupDir,
            withIntermediateDirectories: true
        )

        let storeFile = storePath.appendingPathComponent("VaulType.store")
        let backupFile = backupDir
            .appendingPathComponent("VaulType_\(timestamp).store")

        try FileManager.default.copyItem(at: storeFile, to: backupFile)
        return backupFile
    }

    /// Removes backups older than 30 days.
    static func pruneOldBackups() throws {
        let backupDir = storePath
            .appendingPathComponent("backups", isDirectory: true)
        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -30,
            to: .now
        )!

        let files = try FileManager.default.contentsOfDirectory(
            at: backupDir,
            includingPropertiesForKeys: [.creationDateKey]
        )

        for file in files {
            let values = try file.resourceValues(forKeys: [.creationDateKey])
            if let created = values.creationDate, created < cutoff {
                try FileManager.default.removeItem(at: file)
            }
        }
    }
}
```

---

## Data Export/Import Format

VaulType supports exporting and importing user data in a structured JSON format. This enables backup, migration between machines, and sharing templates with other users.

### Export Format (JSON Schema)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "VaulType Data Export",
  "type": "object",
  "required": ["version", "exportDate", "appVersion"],
  "properties": {
    "version": {
      "type": "integer",
      "description": "Export format version",
      "const": 1
    },
    "exportDate": {
      "type": "string",
      "format": "date-time",
      "description": "ISO 8601 timestamp of when the export was created"
    },
    "appVersion": {
      "type": "string",
      "description": "VaulType app version that created this export"
    },
    "dictationHistory": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["id", "rawText", "mode", "language", "audioDuration", "wordCount", "timestamp", "isFavorite"],
        "properties": {
          "id": { "type": "string", "format": "uuid" },
          "rawText": { "type": "string" },
          "processedText": { "type": ["string", "null"] },
          "mode": { "type": "string", "enum": ["raw", "clean", "structure", "prompt", "code", "custom"] },
          "language": { "type": "string" },
          "appBundleIdentifier": { "type": ["string", "null"] },
          "appName": { "type": ["string", "null"] },
          "audioDuration": { "type": "number" },
          "wordCount": { "type": "integer" },
          "timestamp": { "type": "string", "format": "date-time" },
          "isFavorite": { "type": "boolean" }
        }
      }
    },
    "promptTemplates": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["id", "name", "mode", "systemPrompt", "userPromptTemplate", "variables", "isBuiltIn", "isDefault"],
        "properties": {
          "id": { "type": "string", "format": "uuid" },
          "name": { "type": "string" },
          "mode": { "type": "string" },
          "systemPrompt": { "type": "string" },
          "userPromptTemplate": { "type": "string" },
          "variables": { "type": "array", "items": { "type": "string" } },
          "isBuiltIn": { "type": "boolean" },
          "isDefault": { "type": "boolean" },
          "createdAt": { "type": "string", "format": "date-time" },
          "updatedAt": { "type": "string", "format": "date-time" }
        }
      }
    },
    "appProfiles": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["id", "bundleIdentifier", "appName", "injectionMethod", "isEnabled"],
        "properties": {
          "id": { "type": "string", "format": "uuid" },
          "bundleIdentifier": { "type": "string" },
          "appName": { "type": "string" },
          "defaultMode": { "type": ["string", "null"] },
          "customVocabulary": { "type": "array", "items": { "type": "string" } },
          "preferredLanguage": { "type": ["string", "null"] },
          "injectionMethod": { "type": "string" },
          "isEnabled": { "type": "boolean" },
          "vocabularyEntries": {
            "type": "array",
            "items": { "$ref": "#/$defs/vocabularyEntry" }
          }
        }
      }
    },
    "globalVocabulary": {
      "type": "array",
      "items": { "$ref": "#/$defs/vocabularyEntry" }
    },
    "settings": {
      "type": "object",
      "description": "UserSettings singleton (all fields optional on import)"
    }
  },
  "$defs": {
    "vocabularyEntry": {
      "type": "object",
      "required": ["id", "spokenForm", "replacement", "isGlobal", "caseSensitive"],
      "properties": {
        "id": { "type": "string", "format": "uuid" },
        "spokenForm": { "type": "string" },
        "replacement": { "type": "string" },
        "language": { "type": ["string", "null"] },
        "isGlobal": { "type": "boolean" },
        "caseSensitive": { "type": "boolean" }
      }
    }
  }
}
```

### Export/Import Implementation

```swift
import Foundation
import SwiftData

struct VaulTypeExport: Codable {
    let version: Int
    let exportDate: Date
    let appVersion: String
    var dictationHistory: [DictationEntryDTO]?
    var promptTemplates: [PromptTemplateDTO]?
    var appProfiles: [AppProfileDTO]?
    var globalVocabulary: [VocabularyEntryDTO]?
    var settings: UserSettingsDTO?
}

// MARK: - Data Transfer Objects

struct DictationEntryDTO: Codable {
    let id: UUID
    let rawText: String
    let processedText: String?
    let mode: String
    let language: String
    let appBundleIdentifier: String?
    let appName: String?
    let audioDuration: TimeInterval
    let wordCount: Int
    let timestamp: Date
    let isFavorite: Bool
}

struct PromptTemplateDTO: Codable {
    let id: UUID
    let name: String
    let mode: String
    let systemPrompt: String
    let userPromptTemplate: String
    let variables: [String]
    let isBuiltIn: Bool
    let isDefault: Bool
    let createdAt: Date
    let updatedAt: Date
}

struct AppProfileDTO: Codable {
    let id: UUID
    let bundleIdentifier: String
    let appName: String
    let defaultMode: String?
    let customVocabulary: [String]
    let preferredLanguage: String?
    let injectionMethod: String
    let isEnabled: Bool
    let vocabularyEntries: [VocabularyEntryDTO]?
}

struct VocabularyEntryDTO: Codable {
    let id: UUID
    let spokenForm: String
    let replacement: String
    let language: String?
    let isGlobal: Bool
    let caseSensitive: Bool
}

struct UserSettingsDTO: Codable {
    let selectedWhisperModel: String?
    let selectedLLMModel: String?
    let globalHotkey: String?
    let pushToTalkEnabled: Bool?
    let defaultMode: String?
    let defaultLanguage: String?
    // ... all other settings fields as optionals
}

// MARK: - Export Service

actor DataExportService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Exports selected data categories to a JSON file.
    func exportData(
        includeHistory: Bool = true,
        includeTemplates: Bool = true,
        includeProfiles: Bool = true,
        includeVocabulary: Bool = true,
        includeSettings: Bool = true
    ) throws -> Data {
        var export = VaulTypeExport(
            version: 1,
            exportDate: .now,
            appVersion: Bundle.main.appVersion
        )

        if includeHistory {
            let entries = try modelContext.fetch(
                FetchDescriptor<DictationEntry>(
                    sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
                )
            )
            export.dictationHistory = entries.map { $0.toDTO() }
        }

        if includeTemplates {
            let templates = try modelContext.fetch(
                FetchDescriptor<PromptTemplate>()
            )
            export.promptTemplates = templates.map { $0.toDTO() }
        }

        if includeProfiles {
            let profiles = try modelContext.fetch(
                FetchDescriptor<AppProfile>()
            )
            export.appProfiles = profiles.map { $0.toDTO() }
        }

        if includeVocabulary {
            let globalEntries = try modelContext.fetch(
                FetchDescriptor<VocabularyEntry>(
                    predicate: #Predicate { $0.isGlobal }
                )
            )
            export.globalVocabulary = globalEntries.map { $0.toDTO() }
        }

        if includeSettings {
            let settings = try UserSettings.shared(in: modelContext)
            export.settings = settings.toDTO()
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(export)
    }

    /// Imports data from a JSON export, with conflict resolution.
    func importData(
        from data: Data,
        conflictResolution: ConflictResolution = .skip
    ) throws -> ImportResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let export = try decoder.decode(VaulTypeExport.self, from: data)

        var result = ImportResult()

        // Import in dependency order: settings → profiles → vocabulary → templates → history
        if let settings = export.settings {
            try importSettings(settings)
            result.settingsImported = true
        }

        if let profiles = export.appProfiles {
            result.profilesImported = try importProfiles(
                profiles,
                conflictResolution: conflictResolution
            )
        }

        if let vocabulary = export.globalVocabulary {
            result.vocabularyImported = try importVocabulary(
                vocabulary,
                conflictResolution: conflictResolution
            )
        }

        if let templates = export.promptTemplates {
            result.templatesImported = try importTemplates(
                templates,
                conflictResolution: conflictResolution
            )
        }

        if let history = export.dictationHistory {
            result.historyImported = try importHistory(
                history,
                conflictResolution: conflictResolution
            )
        }

        try modelContext.save()
        return result
    }
}

enum ConflictResolution {
    /// Skip items that already exist (match by ID).
    case skip
    /// Overwrite existing items with imported data.
    case overwrite
    /// Create duplicates with new IDs.
    case duplicate
}

struct ImportResult {
    var settingsImported: Bool = false
    var profilesImported: Int = 0
    var vocabularyImported: Int = 0
    var templatesImported: Int = 0
    var historyImported: Int = 0

    var totalImported: Int {
        profilesImported + vocabularyImported
            + templatesImported + historyImported
    }
}
```

> 💡 **Tip**: The export file is plain JSON with no encryption by default. For users who want encrypted exports, VaulType can optionally encrypt the JSON payload with a passphrase-derived key (AES-256-GCM) stored in the Keychain. The encrypted format wraps the JSON in a binary envelope with a format header.

---

## Data Lifecycle

### Auto-Deletion Policies

VaulType manages data growth through configurable retention policies in `UserSettings`.

```swift
import Foundation
import SwiftData

actor HistoryCleanupService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Runs all cleanup policies. Should be called on app launch and
    /// periodically (e.g., every 24 hours).
    func performCleanup() throws {
        let settings = try UserSettings.shared(in: modelContext)

        try enforceRetentionDays(settings.historyRetentionDays)
        try enforceMaxEntries(settings.maxHistoryEntries)
        try purgeTextIfDisabled(settings.storeTranscriptionText)

        try modelContext.save()

        // Record cleanup timestamp
        UserDefaults.standard.set(
            Date.now,
            forKey: UserDefaultsKey.lastHistoryCleanup
        )
    }

    /// Delete entries older than the retention period.
    private func enforceRetentionDays(_ days: Int) throws {
        guard days > 0 else { return } // 0 = unlimited

        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -days,
            to: .now
        )!

        let descriptor = FetchDescriptor<DictationEntry>(
            predicate: #Predicate {
                $0.timestamp < cutoff && !$0.isFavorite
            }
        )
        let expired = try modelContext.fetch(descriptor)
        for entry in expired {
            modelContext.delete(entry)
        }
    }

    /// Keep only the N most recent entries.
    private func enforceMaxEntries(_ max: Int) throws {
        guard max > 0 else { return } // 0 = unlimited

        let countDescriptor = FetchDescriptor<DictationEntry>()
        let totalCount = try modelContext.fetchCount(countDescriptor)

        guard totalCount > max else { return }

        let excessCount = totalCount - max
        let descriptor = FetchDescriptor<DictationEntry>(
            predicate: #Predicate { !$0.isFavorite },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        // Fetch only the oldest entries that exceed the limit
        var limitedDescriptor = descriptor
        limitedDescriptor.fetchLimit = excessCount

        let excess = try modelContext.fetch(limitedDescriptor)
        for entry in excess {
            modelContext.delete(entry)
        }
    }

    /// Strip transcription text from all entries if storage is disabled.
    private func purgeTextIfDisabled(_ storeText: Bool) throws {
        guard !storeText else { return }

        let descriptor = FetchDescriptor<DictationEntry>(
            predicate: #Predicate {
                $0.rawText != "" || $0.processedText != nil
            }
        )
        let entries = try modelContext.fetch(descriptor)
        for entry in entries {
            entry.rawText = ""
            entry.processedText = nil
        }
    }
}
```

### Retention Policy Summary

| Data Type | Default Retention | Configurable | Favorite Override |
|---|---|---|---|
| `DictationEntry` text content | 90 days | Yes (`historyRetentionDays`) | Yes — favorites never auto-deleted |
| `DictationEntry` metadata | 90 days | Yes (`historyRetentionDays`) | Yes — favorites never auto-deleted |
| `DictationEntry` max count | 5,000 entries | Yes (`maxHistoryEntries`) | Yes — favorites don't count toward limit |
| `PromptTemplate` | Indefinite | No | N/A |
| `AppProfile` | Indefinite | No | N/A |
| `VocabularyEntry` | Indefinite | No | N/A |
| `UserSettings` | Indefinite | No | N/A |
| `ModelInfo` | Indefinite | No | N/A |
| UserDefaults | Indefinite | No (reset via app) | N/A |
| Keychain items | Indefinite | User-controlled | N/A |

### Storage Size Estimation

| Model | Estimated Size per Record | 5,000 Records |
|---|---|---|
| `DictationEntry` (with text) | ~2 KB avg | ~10 MB |
| `DictationEntry` (metadata only) | ~200 B | ~1 MB |
| `PromptTemplate` | ~1 KB | N/A (typically < 50) |
| `AppProfile` | ~500 B | N/A (typically < 100) |
| `VocabularyEntry` | ~200 B | ~1 MB (at 5,000) |
| `UserSettings` | ~500 B | N/A (singleton) |
| `ModelInfo` | ~300 B | N/A (typically < 20) |

> ℹ️ **Info**: The SwiftData store is expected to stay under 50 MB for typical usage patterns. ML model files (stored separately on the filesystem, not in the database) are the primary storage consumers, ranging from 75 MB (Whisper Tiny) to 4+ GB (larger LLMs).

### Manual Cleanup

```swift
extension HistoryCleanupService {
    /// Deletes ALL dictation history (including favorites).
    /// Called from Settings → Privacy → "Clear All History".
    func clearAllHistory() throws {
        let descriptor = FetchDescriptor<DictationEntry>()
        let all = try modelContext.fetch(descriptor)
        for entry in all {
            modelContext.delete(entry)
        }
        try modelContext.save()
    }

    /// Resets the entire database to factory defaults.
    /// Called from Settings → Advanced → "Reset All Data".
    func factoryReset() throws {
        // Delete all user data
        try deleteAll(DictationEntry.self)
        try deleteAll(VocabularyEntry.self)
        try deleteAll(AppProfile.self)

        // Reset templates to built-in defaults
        try deleteAll(PromptTemplate.self)
        for template in PromptTemplate.builtInTemplates {
            modelContext.insert(template)
        }

        // Reset settings to defaults
        try deleteAll(UserSettings.self)
        let _ = try UserSettings.shared(in: modelContext)

        try modelContext.save()

        // Clear UserDefaults
        if let bundleId = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(
                forName: bundleId
            )
        }

        // Clear Keychain items
        try? KeychainManager.delete(key: KeychainKey.ollamaAPIKey)
        try? KeychainManager.delete(key: KeychainKey.licenseKey)
        try? KeychainManager.delete(key: KeychainKey.exportEncryptionKey)
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) throws {
        let descriptor = FetchDescriptor<T>()
        let all = try modelContext.fetch(descriptor)
        for item in all {
            modelContext.delete(item)
        }
    }
}
```

---

## Privacy Considerations

VaulType's data persistence layer is designed around a core principle: **all user data stays on the user's machine, under the user's control, at all times.**

### Data Residency

| Storage Layer | Location on Disk | Encrypted at Rest |
|---|---|---|
| SwiftData | `~/Library/Application Support/VaulType/VaulType.store` | FileVault (if enabled) |
| UserDefaults | `~/Library/Preferences/com.vaultype.app.plist` | FileVault (if enabled) |
| Keychain | macOS Keychain database | Always (Secure Enclave on Apple Silicon) |
| ML Models | `~/Library/Application Support/VaulType/{whisper,llm}-models/` | FileVault (if enabled) |
| Audio (temporary) | `/tmp/vaultype/` | No (ephemeral, auto-deleted) |

### Privacy Guarantees

- **Zero network calls**: The SwiftData store, UserDefaults, and Keychain are never synced to any cloud service. There is no CloudKit integration, no iCloud sync, no analytics SDK.
- **No telemetry**: Usage counters in UserDefaults (`totalDictationCount`, `totalAudioDuration`) are stored locally for the user's own reference in the Statistics view. They are never transmitted.
- **Audio ephemeral**: Audio recordings are held in memory during transcription and written to `/tmp/` only when the buffer exceeds memory limits. Temporary audio files are deleted immediately after whisper.cpp processes them.
- **Text injection privacy**: Text injected via CGEvent or clipboard is not logged beyond the `DictationEntry` stored in SwiftData. The user can disable text storage entirely via `storeTranscriptionText = false`.
- **Export control**: Data export produces a local JSON file. The user decides where to save it. No export is ever triggered automatically.

> 🔒 **Security**: We strongly recommend users enable **FileVault** (macOS full-disk encryption) for maximum protection. While VaulType does not store audio recordings permanently, the SwiftData store does contain transcription text which may be sensitive. FileVault ensures this data is encrypted at rest with the user's login credentials.

### Data the App Never Stores

| Data Type | Stored? | Rationale |
|---|---|---|
| Raw audio recordings | Never (ephemeral only) | Privacy — voice biometric data |
| Screenshots or screen content | Never | Not needed for functionality |
| Keystroke logs (beyond injected text) | Never | Privacy — only injected text is logged |
| Network traffic | N/A | No network calls exist |
| Device identifiers / fingerprints | Never | No analytics or tracking |
| Location data | Never | Not needed for functionality |
| Contact or calendar data | Never | Not needed for functionality |

> 🍎 **macOS-specific**: VaulType requests only two macOS permissions — **Microphone** (for audio capture) and **Accessibility** (for CGEvent text injection). Both are requested explicitly with user consent and are revocable at any time in System Settings → Privacy & Security. The app functions in degraded mode without either permission (no recording without Microphone, clipboard-only injection without Accessibility).

---

## Related Documentation

- [Architecture Overview](ARCHITECTURE.md) — High-level system architecture and component interactions
- [Tech Stack](TECH_STACK.md) — Complete technology stack including SwiftData, whisper.cpp, and llama.cpp
- [Privacy Policy](../PRIVACY.md) — User-facing privacy commitments and data handling practices
- [Audio Pipeline](AUDIO_PIPELINE.md) — How audio is captured, buffered, and passed to whisper.cpp
- [LLM Integration](LLM_INTEGRATION.md) — Post-processing pipeline and prompt template execution
- [Text Injection](TEXT_INJECTION.md) — CGEvent and clipboard injection mechanisms
- [Configuration Guide](../guides/CONFIGURATION.md) — User-facing guide to all settings and preferences
