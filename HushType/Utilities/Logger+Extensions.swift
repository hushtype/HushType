import os

extension Logger {
    // MARK: - Module Loggers

    /// Logger for audio capture and VAD.
    static let audio = Logger(subsystem: Constants.logSubsystem, category: "audio")

    /// Logger for whisper.cpp speech-to-text.
    static let whisper = Logger(subsystem: Constants.logSubsystem, category: "whisper")

    /// Logger for llama.cpp LLM processing.
    static let llm = Logger(subsystem: Constants.logSubsystem, category: "llm")

    /// Logger for text injection (CGEvent/clipboard).
    static let injection = Logger(subsystem: Constants.logSubsystem, category: "injection")

    /// Logger for UI and view lifecycle.
    static let ui = Logger(subsystem: Constants.logSubsystem, category: "ui")

    /// Logger for global hotkey management.
    static let hotkey = Logger(subsystem: Constants.logSubsystem, category: "hotkey")

    /// Logger for ML model management.
    static let models = Logger(subsystem: Constants.logSubsystem, category: "models")

    /// General-purpose logger for uncategorized events.
    static let general = Logger(subsystem: Constants.logSubsystem, category: "general")

    /// Logger for voice command detection and execution.
    static let commands = Logger(subsystem: Constants.logSubsystem, category: "commands")

    /// Logger for performance, power management, and resource monitoring.
    static let performance = Logger(subsystem: Constants.logSubsystem, category: "performance")
}
