import Foundation
import SwiftData

// MARK: - Command Action Step

/// A single step in a custom command's action sequence.
struct CommandActionStep: Codable, Sendable, Identifiable {
    var id: UUID = UUID()
    let intent: CommandIntent
    var parameters: [String: String]

    init(intent: CommandIntent, parameters: [String: String] = [:]) {
        self.intent = intent
        self.parameters = parameters
    }
}

// MARK: - Custom Command

/// User-defined voice command mapped to a sequence of actions.
@Model
final class CustomCommand {
    @Attribute(.unique)
    var id: UUID

    /// Display name for the command.
    var name: String

    /// What the user says to trigger this command (e.g., "morning setup").
    var triggerPhrase: String

    /// Ordered list of actions to execute when triggered.
    var actions: [CommandActionStep]

    /// Whether this command is active.
    var isEnabled: Bool

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        triggerPhrase: String,
        actions: [CommandActionStep] = [],
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.triggerPhrase = triggerPhrase
        self.actions = actions
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
