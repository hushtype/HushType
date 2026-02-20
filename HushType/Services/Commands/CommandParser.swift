import Foundation
import os

// MARK: - Parsed Command

/// Structured representation of a parsed voice command.
struct ParsedCommand: Sendable {
    let intent: CommandIntent
    let entities: [String: String]
    let rawText: String
    let displayName: String
}

// MARK: - Command Result

/// Result of executing a voice command.
struct CommandResult: Sendable {
    let success: Bool
    let message: String
    let intent: CommandIntent
}

// MARK: - Command Parser

/// Parses natural language voice commands into structured `ParsedCommand` objects.
/// Uses regex-based pattern matching to identify intent and extract entities.
final class CommandParser: Sendable {
    /// A regex-based command pattern.
    private struct Pattern: Sendable {
        let intent: CommandIntent
        let regex: NSRegularExpression
        let entityKeys: [String]
        let priority: Int
        let displayTemplate: String
    }

    private let patterns: [Pattern]

    init() {
        self.patterns = Self.buildPatterns()
    }

    /// Parse a single command from text.
    /// - Parameter input: Natural language command text (wake phrase already stripped).
    /// - Returns: Parsed command, or nil if no pattern matches.
    func parse(_ input: String) -> ParsedCommand? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var bestMatch: (command: ParsedCommand, priority: Int)?

        for pattern in patterns {
            guard let match = pattern.regex.firstMatch(
                in: trimmed,
                range: NSRange(trimmed.startIndex..., in: trimmed)
            ) else { continue }

            var entities: [String: String] = [:]
            for (index, key) in pattern.entityKeys.enumerated() {
                let groupIndex = index + 1
                guard groupIndex < match.numberOfRanges,
                      let range = Range(match.range(at: groupIndex), in: trimmed) else { continue }
                let value = String(trimmed[range]).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty {
                    entities[key] = value
                }
            }

            let displayName = buildDisplayName(template: pattern.displayTemplate, entities: entities)
            let command = ParsedCommand(
                intent: pattern.intent,
                entities: entities,
                rawText: trimmed,
                displayName: displayName
            )

            if bestMatch == nil || pattern.priority > bestMatch!.priority {
                bestMatch = (command, pattern.priority)
            }
        }

        if let result = bestMatch {
            Logger.commands.info("Parsed command: \(result.command.intent.rawValue) from \"\(trimmed)\"")
            return result.command
        }

        Logger.commands.info("No command pattern matched: \"\(trimmed)\"")
        return nil
    }

    /// Parse a chain of commands separated by conjunctions ("and", "then").
    /// - Parameter input: Full command text that may contain multiple commands.
    /// - Returns: Array of parsed commands. Empty if nothing matches.
    func parseChain(_ input: String) -> [ParsedCommand] {
        let segments = splitOnConjunctions(input)

        // If only one segment, try single parse
        if segments.count <= 1 {
            if let single = parse(input) {
                return [single]
            }
            return []
        }

        // Parse each segment independently
        var commands: [ParsedCommand] = []
        for segment in segments {
            if let parsed = parse(segment) {
                commands.append(parsed)
            }
        }

        if commands.count > 1 {
            Logger.commands.info("Parsed command chain: \(commands.count) commands")
        }

        return commands
    }

    // MARK: - Private Helpers

    /// Split text on conjunction boundaries, only if the text after the conjunction
    /// starts with a recognized command verb.
    private func splitOnConjunctions(_ text: String) -> [String] {
        let conjunctions = [" and then ", " and ", " then ", " also "]
        let commandVerbs = [
            "open", "launch", "switch", "go to", "close", "quit", "hide",
            "show", "move", "maximize", "minimise", "minimize", "center",
            "full screen", "toggle", "volume", "mute", "unmute",
            "brightness", "brighter", "dimmer", "dark mode", "light mode",
            "do not disturb", "lock", "take screenshot", "screenshot",
            "run shortcut"
        ]

        var segments: [String] = []
        var remaining = text

        for conjunction in conjunctions {
            var parts: [String] = []

            var searchStart = remaining.startIndex
            while let range = remaining.range(of: conjunction, options: .caseInsensitive, range: searchStart..<remaining.endIndex) {
                let afterConjunction = String(remaining[range.upperBound...]).lowercased()
                let startsWithVerb = commandVerbs.contains { afterConjunction.hasPrefix($0) }

                if startsWithVerb {
                    let beforePart = String(remaining[remaining.startIndex..<range.lowerBound])
                    parts.append(beforePart)
                    remaining = String(remaining[range.upperBound...])
                    searchStart = remaining.startIndex
                } else {
                    searchStart = range.upperBound
                }
            }

            if !parts.isEmpty {
                segments.append(contentsOf: parts)
            }
        }

        // Add the remaining text
        if !remaining.isEmpty {
            segments.append(remaining)
        }

        // If no splits occurred, return the original text
        if segments.isEmpty {
            return [text]
        }

        return segments.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func buildDisplayName(template: String, entities: [String: String]) -> String {
        var result = template
        for (key, value) in entities {
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return result
    }

    // MARK: - Pattern Definitions

    private static func buildPatterns() -> [Pattern] {
        var patterns: [Pattern] = []

        func add(
            _ intent: CommandIntent,
            _ regex: String,
            keys: [String] = [],
            priority: Int = 10,
            display: String
        ) {
            guard let compiled = try? NSRegularExpression(
                pattern: regex,
                options: [.caseInsensitive]
            ) else { return }
            patterns.append(Pattern(
                intent: intent,
                regex: compiled,
                entityKeys: keys,
                priority: priority,
                displayTemplate: display
            ))
        }

        // App Management
        add(.openApp, #"^(?:open|launch|start)\s+(.+)$"#,
            keys: ["appName"], priority: 10, display: "Open {appName}")
        add(.switchToApp, #"^(?:switch to|go to|activate)\s+(.+)$"#,
            keys: ["appName"], priority: 10, display: "Switch to {appName}")
        add(.closeApp, #"^close\s+(.+)$"#,
            keys: ["appName"], priority: 10, display: "Close {appName}")
        add(.quitApp, #"^(?:quit|exit|terminate)\s+(.+)$"#,
            keys: ["appName"], priority: 10, display: "Quit {appName}")
        add(.hideApp, #"^hide\s+(.+)$"#,
            keys: ["appName"], priority: 10, display: "Hide {appName}")
        add(.showAllWindows, #"^(?:show all windows|mission control|expose|exposé)$"#,
            priority: 15, display: "Show All Windows")

        // Window Management
        add(.moveWindowLeft, #"^(?:move window|tile|snap)\s+(?:to the\s+)?left$"#,
            priority: 12, display: "Move Window Left")
        add(.moveWindowRight, #"^(?:move window|tile|snap)\s+(?:to the\s+)?right$"#,
            priority: 12, display: "Move Window Right")
        add(.maximizeWindow, #"^(?:maximize|maximise|make window full|fill screen|expand)\s*(?:window)?$"#,
            priority: 12, display: "Maximize Window")
        add(.minimizeWindow, #"^(?:minimize|minimise)\s*(?:window)?$"#,
            priority: 12, display: "Minimize Window")
        add(.centerWindow, #"^center\s*(?:the\s+)?(?:window)?$"#,
            priority: 12, display: "Center Window")
        add(.fullScreenToggle, #"^(?:full\s*screen|toggle full\s*screen|enter full\s*screen|exit full\s*screen)$"#,
            priority: 15, display: "Toggle Full Screen")
        add(.moveToNextScreen, #"^(?:next screen|move to next (?:screen|display|monitor)|other screen)$"#,
            priority: 12, display: "Move to Next Screen")

        // Volume Controls
        add(.volumeUp, #"^(?:volume up|louder|turn (?:it )?up|increase volume)$"#,
            priority: 15, display: "Volume Up")
        add(.volumeDown, #"^(?:volume down|quieter|softer|turn (?:it )?down|decrease volume)$"#,
            priority: 15, display: "Volume Down")
        add(.volumeMute, #"^(?:mute|unmute|toggle mute)$"#,
            priority: 15, display: "Toggle Mute")
        add(.volumeSet, #"^(?:(?:set )?volume (?:to )?|volume )(\d+)(?:\s*%)?$"#,
            keys: ["level"], priority: 12, display: "Set Volume to {level}%")

        // Brightness Controls
        add(.brightnessUp, #"^(?:brightness up|brighter|increase brightness)$"#,
            priority: 15, display: "Brightness Up")
        add(.brightnessDown, #"^(?:brightness down|dimmer|decrease brightness|dim)$"#,
            priority: 15, display: "Brightness Down")

        // System Toggles
        add(.doNotDisturbToggle, #"^(?:do not disturb|dnd|focus mode)\s*(?:on|off|toggle)?$"#,
            priority: 15, display: "Toggle Do Not Disturb")
        add(.darkModeToggle, #"^(?:dark mode|light mode|toggle dark mode)$"#,
            priority: 15, display: "Toggle Dark Mode")
        add(.lockScreen, #"^(?:lock screen|lock (?:the )?computer|lock)$"#,
            priority: 15, display: "Lock Screen")
        add(.takeScreenshot, #"^(?:take (?:a )?screenshot|screenshot|screen capture|capture screen)$"#,
            priority: 15, display: "Take Screenshot")

        // Workflow
        add(.runShortcut, #"^(?:run shortcut|shortcut)\s+(.+)$"#,
            keys: ["shortcutName"], priority: 10, display: "Run Shortcut: {shortcutName}")

        return patterns
    }
}
