import Foundation
import os

/// Registry of built-in and custom voice commands with per-command enable/disable support.
@Observable
final class CommandRegistry {

    // MARK: - Nested Types

    /// A single registry entry representing a voice command intent.
    struct CommandEntry: Identifiable, Sendable {
        /// The voice command action type.
        let intent: CommandIntent

        /// Whether this command is currently active.
        var isEnabled: Bool

        /// True for commands shipped with the app; false for user-created commands.
        let isBuiltIn: Bool

        /// Example phrases shown in the settings UI.
        var examplePhrases: [String]

        /// Stable identity derived from the underlying intent.
        var id: String { intent.rawValue }
    }

    // MARK: - Properties

    /// All registered command entries (built-in + any runtime additions).
    private(set) var entries: [CommandEntry]

    // MARK: - Initializer

    init() {
        entries = CommandRegistry.defaultEntries()
        Logger.commands.info("CommandRegistry initialised with \(self.entries.count) built-in entries")
    }

    // MARK: - Query

    /// Returns whether the given intent is currently enabled.
    func isEnabled(_ intent: CommandIntent) -> Bool {
        entries.first { $0.intent == intent }?.isEnabled ?? false
    }

    /// Returns all entries that belong to the given category.
    func entries(for category: CommandCategory) -> [CommandEntry] {
        entries.filter { $0.intent.category == category }
    }

    // MARK: - Mutation

    /// Enable or disable the entry for the given intent.
    func setEnabled(_ intent: CommandIntent, enabled: Bool) {
        guard let index = entries.firstIndex(where: { $0.intent == intent }) else {
            Logger.commands.warning("setEnabled called for unknown intent: \(intent.rawValue)")
            return
        }
        entries[index].isEnabled = enabled
        Logger.commands.info("Command \(intent.rawValue) \(enabled ? "enabled" : "disabled")")
    }

    /// Load persisted disabled intents from UserSettings.
    ///
    /// Resets all entries to enabled first, then disables those in the list.
    /// This prevents stale disabled state from accumulating across calls.
    func loadDisabledIntents(_ disabledRawValues: [String]) {
        let disabledSet = Set(disabledRawValues)
        for index in entries.indices {
            entries[index].isEnabled = !disabledSet.contains(entries[index].intent.rawValue)
        }
        Logger.commands.info("Loaded \(disabledRawValues.count) disabled command intents from settings")
    }

    /// Returns the raw values of all currently disabled intents (for persistence).
    func disabledIntentRawValues() -> [String] {
        entries.filter { !$0.isEnabled }.map { $0.intent.rawValue }
    }

    // MARK: - Custom Command Resolution

    /// Match transcribed text against user-defined custom commands.
    ///
    /// Comparison is case-insensitive and trims surrounding whitespace.
    /// - Parameters:
    ///   - text: The command text extracted after wake-phrase detection.
    ///   - customCommands: User-created `CustomCommand` records from SwiftData.
    /// - Returns: The action steps of the first matching, enabled custom command, or `nil`.
    func resolveCustomCommand(
        _ text: String,
        customCommands: [CustomCommand]
    ) -> [CommandActionStep]? {
        let normalised = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalised.isEmpty else { return nil }

        for command in customCommands where command.isEnabled {
            let phrase = command.triggerPhrase
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if normalised == phrase {
                Logger.commands.info("Custom command matched: \"\(command.triggerPhrase)\"")
                return command.actions
            }
        }

        return nil
    }

    // MARK: - Default Entries

    /// Constructs the full list of built-in `CommandEntry` values with example phrases.
    static func defaultEntries() -> [CommandEntry] {
        CommandIntent.allCases.map { intent in
            CommandEntry(
                intent: intent,
                isEnabled: true,
                isBuiltIn: true,
                examplePhrases: examplePhrases(for: intent)
            )
        }
    }

    // MARK: - Example Phrases

    // swiftlint:disable:next cyclomatic_complexity
    private static func examplePhrases(for intent: CommandIntent) -> [String] {
        switch intent {

        // App management
        case .openApp:
            return ["open Safari", "launch Xcode"]
        case .switchToApp:
            return ["switch to Finder", "go to Terminal"]
        case .closeApp:
            return ["close Safari"]
        case .quitApp:
            return ["quit Xcode"]
        case .hideApp:
            return ["hide Finder"]
        case .showAllWindows:
            return ["show all windows", "mission control"]

        // Window management
        case .moveWindowLeft:
            return ["move window left"]
        case .moveWindowRight:
            return ["move window right"]
        case .maximizeWindow:
            return ["maximize window", "make window full"]
        case .minimizeWindow:
            return ["minimize window"]
        case .centerWindow:
            return ["center window"]
        case .fullScreenToggle:
            return ["full screen", "toggle full screen"]
        case .moveToNextScreen:
            return ["next screen", "move to next display"]

        // System control
        case .volumeUp:
            return ["volume up", "louder"]
        case .volumeDown:
            return ["volume down", "quieter"]
        case .volumeMute:
            return ["mute", "unmute"]
        case .volumeSet:
            return ["volume 50", "set volume to 80"]
        case .brightnessUp:
            return ["brightness up", "brighter"]
        case .brightnessDown:
            return ["brightness down", "dimmer"]
        case .doNotDisturbToggle:
            return ["do not disturb on", "do not disturb off"]
        case .darkModeToggle:
            return ["dark mode", "light mode"]
        case .lockScreen:
            return ["lock screen"]
        case .takeScreenshot:
            return ["take screenshot", "screenshot"]

        // Keyboard shortcuts
        case .injectShortcut:
            return ["command shift n", "press ctrl c", "cmd r"]
        case .runShortcut:
            return ["run shortcut Morning Routine"]
        case .customAlias:
            return []
        }
    }
}
