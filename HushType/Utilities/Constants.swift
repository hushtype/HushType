import Foundation

enum Constants {
    /// App identity
    static let bundleID = "com.hushtype.app"
    static let appName = "HushType"

    /// Logging
    static let logSubsystem = "com.hushtype.app"

    /// Default hotkey: Fn (Globe key)
    enum Hotkey {
        static let defaultModifiers: UInt = 0x800000 // .maskFunction
        static let defaultKeyCode: UInt16 = 63 // fn/globe key
        static let defaultString = "fn"
    }

    /// Model storage paths
    enum Paths {
        static let appSupportDirectory: URL = {
            let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            return url.appendingPathComponent("HushType")
        }()

        static let modelsDirectory: URL = {
            appSupportDirectory.appendingPathComponent("Models")
        }()

        static let whisperModelsDirectory: URL = {
            modelsDirectory.appendingPathComponent("whisper-models")
        }()

        static let llmModelsDirectory: URL = {
            modelsDirectory.appendingPathComponent("llm-models")
        }()
    }

    /// Remote model registry
    enum Registry {
        static let manifestURL = URL(string: "https://raw.githubusercontent.com/hushtype/HushType/main/registry/models.json")!
        static let refreshIntervalSeconds: TimeInterval = 24 * 60 * 60 // 24 hours
    }

    /// UserDefaults keys
    enum Defaults {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let selectedWhisperModel = "selectedWhisperModel"
        static let selectedLLMModel = "selectedLLMModel"
        static let defaultProcessingMode = "defaultProcessingMode"
        static let defaultLanguage = "defaultLanguage"
        static let launchAtLogin = "launchAtLogin"
        static let showDockIcon = "showDockIcon"
        static let vadSensitivity = "vadSensitivity"
        static let selectedInputDevice = "selectedInputDevice"
    }
}
