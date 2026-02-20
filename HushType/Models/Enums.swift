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

    var iconName: String {
        switch self {
        case .raw: "waveform"
        case .clean: "sparkles"
        case .structure: "list.bullet"
        case .prompt: "text.bubble"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .custom: "gearshape"
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

/// Categorizes ML models used by HushType.
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

    /// Directory name within the app's model storage.
    var storageDirectory: String {
        switch self {
        case .whisper: "whisper-models"
        case .llm: "llm-models"
        }
    }
}

// MARK: - Command Intent

/// Voice command action type.
enum CommandIntent: String, Codable, CaseIterable, Identifiable, Sendable {
    // App management
    case openApp
    case switchToApp
    case closeApp
    case quitApp
    case hideApp
    case showAllWindows

    // Window management
    case moveWindowLeft
    case moveWindowRight
    case maximizeWindow
    case minimizeWindow
    case centerWindow
    case fullScreenToggle
    case moveToNextScreen

    // System control
    case volumeUp
    case volumeDown
    case volumeMute
    case volumeSet
    case brightnessUp
    case brightnessDown
    case doNotDisturbToggle
    case darkModeToggle
    case lockScreen
    case takeScreenshot

    // Keyboard shortcuts
    case injectShortcut

    // Workflow
    case runShortcut
    case customAlias

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openApp: "Open App"
        case .switchToApp: "Switch to App"
        case .closeApp: "Close App"
        case .quitApp: "Quit App"
        case .hideApp: "Hide App"
        case .showAllWindows: "Show All Windows"
        case .moveWindowLeft: "Move Window Left"
        case .moveWindowRight: "Move Window Right"
        case .maximizeWindow: "Maximize Window"
        case .minimizeWindow: "Minimize Window"
        case .centerWindow: "Center Window"
        case .fullScreenToggle: "Toggle Full Screen"
        case .moveToNextScreen: "Move to Next Screen"
        case .volumeUp: "Volume Up"
        case .volumeDown: "Volume Down"
        case .volumeMute: "Mute/Unmute"
        case .volumeSet: "Set Volume"
        case .brightnessUp: "Brightness Up"
        case .brightnessDown: "Brightness Down"
        case .doNotDisturbToggle: "Toggle Do Not Disturb"
        case .darkModeToggle: "Toggle Dark Mode"
        case .lockScreen: "Lock Screen"
        case .takeScreenshot: "Take Screenshot"
        case .injectShortcut: "Inject Shortcut"
        case .runShortcut: "Run Shortcut"
        case .customAlias: "Custom Command"
        }
    }

    var iconName: String {
        switch self {
        case .openApp: "arrow.up.forward.app"
        case .switchToApp: "arrow.right.arrow.left"
        case .closeApp: "xmark.circle"
        case .quitApp: "power"
        case .hideApp: "eye.slash"
        case .showAllWindows: "rectangle.3.group"
        case .moveWindowLeft: "rectangle.lefthalf.filled"
        case .moveWindowRight: "rectangle.righthalf.filled"
        case .maximizeWindow: "arrow.up.left.and.arrow.down.right"
        case .minimizeWindow: "arrow.down.right.and.arrow.up.left"
        case .centerWindow: "rectangle.center.inset.filled"
        case .fullScreenToggle: "arrow.up.backward.and.arrow.down.forward"
        case .moveToNextScreen: "display.2"
        case .volumeUp: "speaker.wave.3"
        case .volumeDown: "speaker.wave.1"
        case .volumeMute: "speaker.slash"
        case .volumeSet: "speaker.wave.2"
        case .brightnessUp: "sun.max"
        case .brightnessDown: "sun.min"
        case .doNotDisturbToggle: "moon"
        case .darkModeToggle: "circle.lefthalf.filled"
        case .lockScreen: "lock"
        case .takeScreenshot: "camera.viewfinder"
        case .injectShortcut: "command"
        case .runShortcut: "bolt"
        case .customAlias: "star"
        }
    }

    /// Category grouping for settings UI.
    var category: CommandCategory {
        switch self {
        case .openApp, .switchToApp, .closeApp, .quitApp, .hideApp, .showAllWindows:
            .appManagement
        case .moveWindowLeft, .moveWindowRight, .maximizeWindow, .minimizeWindow,
             .centerWindow, .fullScreenToggle, .moveToNextScreen:
            .windowManagement
        case .volumeUp, .volumeDown, .volumeMute, .volumeSet,
             .brightnessUp, .brightnessDown, .doNotDisturbToggle,
             .darkModeToggle, .lockScreen, .takeScreenshot:
            .systemControl
        case .injectShortcut:
            .systemControl
        case .runShortcut, .customAlias:
            .workflow
        }
    }
}

// MARK: - Command Category

/// Groups command intents for settings UI.
enum CommandCategory: String, CaseIterable, Identifiable {
    case appManagement = "App Management"
    case windowManagement = "Window Management"
    case systemControl = "System Control"
    case workflow = "Workflow"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .appManagement: "app.badge"
        case .windowManagement: "macwindow"
        case .systemControl: "gearshape"
        case .workflow: "bolt.circle"
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

}
