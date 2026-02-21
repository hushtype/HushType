import Foundation

/// A plugin that adds new voice commands to VaulType.
///
/// Command plugins can register custom voice commands that are recognized
/// by the command parser. When a user speaks a matching command, the
/// plugin's handler is called to execute it.
///
/// Example usage:
/// ```swift
/// class GitPlugin: CommandPlugin {
///     let identifier = "com.example.git-commands"
///     let displayName = "Git Commands"
///     let version = "1.0.0"
///
///     func activate() throws {}
///     func deactivate() throws {}
///
///     var commands: [PluginCommand] {
///         [PluginCommand(
///             name: "git commit",
///             patterns: ["commit changes", "git commit"],
///             description: "Run git commit on the current repo",
///             handler: { entities in
///                 // Execute git commit
///                 return .init(success: true, message: "Changes committed")
///             }
///         )]
///     }
/// }
/// ```
protocol CommandPlugin: VaulTypePlugin {
    /// The voice commands this plugin provides.
    var commands: [PluginCommand] { get }
}

// MARK: - Plugin Command

/// A voice command provided by a command plugin.
struct PluginCommand: Sendable {
    /// Internal name for this command (used as identifier).
    let name: String

    /// Natural language patterns that trigger this command.
    /// Case-insensitive matching. The first match wins.
    let patterns: [String]

    /// Human-readable description shown in the command settings UI.
    let description: String

    /// Handler called when the command is triggered.
    /// - Parameter entities: Key-value pairs extracted from the spoken command.
    /// - Returns: Result indicating success/failure and a message.
    let handler: @Sendable ([String: String]) async -> PluginCommandResult
}

// MARK: - Plugin Command Result

/// Result of executing a plugin command.
struct PluginCommandResult: Sendable {
    let success: Bool
    let message: String

    static func success(_ message: String = "OK") -> PluginCommandResult {
        PluginCommandResult(success: true, message: message)
    }

    static func failure(_ message: String) -> PluginCommandResult {
        PluginCommandResult(success: false, message: message)
    }
}
