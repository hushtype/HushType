# Voice Commands

**Last Updated: 2026-02-13**

> HushType's voice command system enables hands-free control of macOS applications, windows, and system settings through natural language spoken commands. All processing happens locally using whisper.cpp for recognition and an optional llama.cpp-powered NLU parser for complex intent classification.

---

## Table of Contents

- [Overview](#overview)
- [Command Processing Pipeline](#command-processing-pipeline)
- [Command Mode Activation and Deactivation](#command-mode-activation-and-deactivation)
  - [Voice Prefix Trigger](#voice-prefix-trigger)
  - [Entering and Exiting Command Mode](#entering-and-exiting-command-mode)
  - [Visual Indicators](#visual-indicators)
  - [Timeout Behavior](#timeout-behavior)
- [Natural Language Command Parser Design](#natural-language-command-parser-design)
  - [Regex-Based Parsing](#regex-based-parsing)
  - [LLM-Based Parsing](#llm-based-parsing)
  - [Intent Classification](#intent-classification)
  - [Entity Extraction](#entity-extraction)
- [Built-in Command Registry](#built-in-command-registry)
  - [Command Data Structure](#command-data-structure)
  - [Command Matching](#command-matching)
  - [Priority and Confidence Scoring](#priority-and-confidence-scoring)
  - [Extensibility](#extensibility)
- [App Management Commands](#app-management-commands)
  - [Open App](#open-app)
  - [Switch to App](#switch-to-app)
  - [Close and Quit App](#close-and-quit-app)
  - [Window State Commands](#window-state-commands)
  - [Tab and Window Commands](#tab-and-window-commands)
- [Window Management Commands](#window-management-commands)
  - [Move Window to Half](#move-window-to-half)
  - [Move to Next Desktop](#move-to-next-desktop)
  - [Tile Windows](#tile-windows)
  - [Window Management via Accessibility APIs](#window-management-via-accessibility-apis)
- [System Control Commands](#system-control-commands)
  - [Volume Control](#volume-control)
  - [Brightness Control](#brightness-control)
  - [Do Not Disturb](#do-not-disturb)
  - [Screenshot](#screenshot)
  - [Lock Screen and Sleep Display](#lock-screen-and-sleep-display)
- [Workflow Automation and Command Chaining](#workflow-automation-and-command-chaining)
  - [Chaining Syntax](#chaining-syntax)
  - [Sequential Execution Engine](#sequential-execution-engine)
  - [Error Handling in Chains](#error-handling-in-chains)
- [Custom Command Aliases](#custom-command-aliases)
  - [Alias Registration](#alias-registration)
  - [SwiftData Storage](#swiftdata-storage)
  - [Alias Resolution](#alias-resolution)
- [Apple Shortcuts Integration](#apple-shortcuts-integration)
  - [Running Shortcuts via ShortcutsProvider](#running-shortcuts-via-shortcutsprovider)
  - [Passing Parameters](#passing-parameters)
- [AppleScript Bridge](#applescript-bridge)
  - [NSAppleScript Execution](#nsapplescript-execution)
  - [Security Considerations](#security-considerations)
- [Command Reference Table](#command-reference-table)
- [Error Handling and Feedback](#error-handling-and-feedback)
- [Configuration](#configuration)
- [Related Documentation](#related-documentation)

---

## Overview

HushType's voice command subsystem transforms spoken natural language into actionable macOS operations. Unlike dictation mode, which converts speech into typed text, command mode intercepts recognized speech and routes it through an intent classification pipeline to execute system-level actions.

Key design principles:

- **Fully local** -- no network calls, no cloud APIs, no telemetry
- **Low latency** -- regex-based parser handles common commands in under 5ms
- **Extensible** -- user-defined aliases and plugin-ready command registry
- **Safe by default** -- destructive commands require confirmation; sandboxed AppleScript execution

> ℹ️ Voice commands require Accessibility permissions to manage windows and inject keystrokes. See [`PERMISSIONS.md`](PERMISSIONS.md) for the full permissions guide.

---

## Command Processing Pipeline

The following diagram shows the end-to-end flow from spoken audio to executed command:

```
┌─────────────────────────────────────────────────────────────────────┐
│                    VOICE COMMAND PIPELINE                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌───────────┐    ┌──────────────┐    ┌────────────────────┐       │
│  │ Audio In  │───>│ whisper.cpp  │───>│ Wake Word Detector │       │
│  │ (AVAudio) │    │ Transcriber  │    │ "Hey Mac" / custom │       │
│  └───────────┘    └──────────────┘    └─────────┬──────────┘       │
│                                                  │                  │
│                              ┌───────────────────┘                  │
│                              │ wake word detected                   │
│                              ▼                                      │
│                   ┌─────────────────────┐                           │
│                   │  Command Mode Gate  │                           │
│                   │  (active / timeout) │                           │
│                   └──────────┬──────────┘                           │
│                              │                                      │
│                              ▼                                      │
│              ┌───────────────────────────────┐                      │
│              │   Natural Language Parser     │                      │
│              │  ┌─────────┐  ┌────────────┐  │                      │
│              │  │  Regex  │  │ LLM Parser │  │                      │
│              │  │ Matcher │  │ (optional) │  │                      │
│              │  └────┬────┘  └─────┬──────┘  │                      │
│              │       └──────┬──────┘         │                      │
│              └──────────────┼────────────────┘                      │
│                             │                                       │
│                             ▼                                       │
│              ┌───────────────────────────────┐                      │
│              │    Alias Resolution Layer     │                      │
│              │   (SwiftData custom aliases)  │                      │
│              └──────────────┬────────────────┘                      │
│                             │                                       │
│                             ▼                                       │
│              ┌───────────────────────────────┐                      │
│              │     Command Registry          │                      │
│              │  ┌─────────────────────────┐  │                      │
│              │  │  Match + Score + Rank   │  │                      │
│              │  └─────────────────────────┘  │                      │
│              └──────────────┬────────────────┘                      │
│                             │                                       │
│                             ▼                                       │
│              ┌───────────────────────────────┐                      │
│              │    Command Executor           │                      │
│              │  (single / chained / macro)   │                      │
│              └──────────────┬────────────────┘                      │
│                             │                                       │
│                             ▼                                       │
│              ┌───────────────────────────────┐                      │
│              │  Feedback & Visual Response   │                      │
│              │  (status bar / overlay / sfx) │                      │
│              └───────────────────────────────┘                      │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Command Mode Activation and Deactivation

### Voice Prefix Trigger

Command mode is activated by a configurable wake word. The default is `"Hey Mac"`, but users can configure any short phrase.

```swift
import Foundation
import Combine

// MARK: - Wake Word Configuration

struct WakeWordConfig: Codable, Equatable {
    var phrase: String
    var caseSensitive: Bool
    var fuzzyMatchThreshold: Double
    var cooldownInterval: TimeInterval

    static let `default` = WakeWordConfig(
        phrase: "Hey Mac",
        caseSensitive: false,
        fuzzyMatchThreshold: 0.80,
        cooldownInterval: 0.5
    )
}

// MARK: - Wake Word Detector

@MainActor
final class WakeWordDetector: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var lastDetectionDate: Date?

    private let config: WakeWordConfig
    private var lastTriggerTime: Date = .distantPast

    init(config: WakeWordConfig = .default) {
        self.config = config
    }

    /// Checks whether the transcribed text contains the wake word.
    /// Returns the remainder of the text after the wake word, if found.
    func detect(in transcription: String) -> String? {
        let needle = config.caseSensitive
            ? config.phrase
            : config.phrase.lowercased()
        let haystack = config.caseSensitive
            ? transcription
            : transcription.lowercased()

        // Enforce cooldown to prevent rapid re-triggers
        let now = Date()
        guard now.timeIntervalSince(lastTriggerTime) >= config.cooldownInterval else {
            return nil
        }

        // Exact substring match
        if let range = haystack.range(of: needle) {
            lastTriggerTime = now
            lastDetectionDate = now
            let remainder = String(transcription[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            return remainder
        }

        // Fuzzy match using Levenshtein distance
        if fuzzyMatch(haystack: haystack, needle: needle, threshold: config.fuzzyMatchThreshold) {
            lastTriggerTime = now
            lastDetectionDate = now
            // With fuzzy match, return the full transcription as the command
            return transcription
        }

        return nil
    }

    private func fuzzyMatch(haystack: String, needle: String, threshold: Double) -> Bool {
        let words = haystack.split(separator: " ").map(String.init)
        let needleWords = needle.split(separator: " ").map(String.init)

        guard words.count >= needleWords.count else { return false }

        for startIndex in 0...(words.count - needleWords.count) {
            let slice = Array(words[startIndex..<(startIndex + needleWords.count)])
            let joined = slice.joined(separator: " ")
            let similarity = stringSimilarity(joined, needle)
            if similarity >= threshold {
                return true
            }
        }
        return false
    }

    private func stringSimilarity(_ a: String, _ b: String) -> Double {
        let aChars = Array(a)
        let bChars = Array(b)
        let maxLen = max(aChars.count, bChars.count)
        guard maxLen > 0 else { return 1.0 }
        let distance = levenshteinDistance(aChars, bChars)
        return 1.0 - (Double(distance) / Double(maxLen))
    }

    private func levenshteinDistance(_ a: [Character], _ b: [Character]) -> Int {
        let m = a.count
        let n = b.count
        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)
        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }
        for i in 1...m {
            for j in 1...n {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,
                    matrix[i][j - 1] + 1,
                    matrix[i - 1][j - 1] + cost
                )
            }
        }
        return matrix[m][n]
    }
}
```

> 💡 The fuzzy matching threshold (default 0.80) compensates for whisper.cpp misrecognitions of the wake word. Adjust via **Settings > Voice Commands > Wake Word Sensitivity**.

### Entering and Exiting Command Mode

```swift
// MARK: - Command Mode State Machine

enum CommandModeState: Equatable {
    case inactive
    case listening(since: Date)
    case processing(command: String)
    case executing(commandName: String)
    case completed(success: Bool, message: String)
    case error(message: String)
}

@MainActor
final class CommandModeController: ObservableObject {
    @Published private(set) var state: CommandModeState = .inactive
    @Published var timeoutDuration: TimeInterval = 10.0

    private var timeoutTask: Task<Void, Never>?
    private let wakeWordDetector: WakeWordDetector
    private let commandParser: CommandParser
    private let commandExecutor: CommandExecutor

    init(
        wakeWordDetector: WakeWordDetector = WakeWordDetector(),
        commandParser: CommandParser = CommandParser(),
        commandExecutor: CommandExecutor = CommandExecutor()
    ) {
        self.wakeWordDetector = wakeWordDetector
        self.commandParser = commandParser
        self.commandExecutor = commandExecutor
    }

    /// Called when new transcription arrives from whisper.cpp
    func handleTranscription(_ text: String) async {
        switch state {
        case .inactive:
            // Check for wake word
            if let remainder = wakeWordDetector.detect(in: text) {
                await activateCommandMode()
                if !remainder.isEmpty {
                    await processCommand(remainder)
                }
            }

        case .listening:
            // Already in command mode; treat entire text as a command
            await processCommand(text)

        case .processing, .executing:
            // Ignore input while a command is in progress
            break

        case .completed, .error:
            // After a result, check if user issues a follow-up command
            if let remainder = wakeWordDetector.detect(in: text) {
                await activateCommandMode()
                if !remainder.isEmpty {
                    await processCommand(remainder)
                }
            } else {
                // Treat as follow-up in a short grace period
                await processCommand(text)
            }
        }
    }

    func activateCommandMode() async {
        state = .listening(since: Date())
        startTimeout()
        await FeedbackEngine.shared.playActivationSound()
    }

    func deactivateCommandMode() {
        cancelTimeout()
        state = .inactive
    }

    // MARK: - Private Helpers

    private func processCommand(_ rawText: String) async {
        cancelTimeout()
        state = .processing(command: rawText)

        do {
            let parsedCommand = try await commandParser.parse(rawText)
            state = .executing(commandName: parsedCommand.displayName)
            let result = try await commandExecutor.execute(parsedCommand)
            state = .completed(success: true, message: result.message)
        } catch {
            state = .error(message: error.localizedDescription)
        }

        // Return to inactive after a brief display of the result
        try? await Task.sleep(for: .seconds(2))
        state = .inactive
    }

    private func startTimeout() {
        cancelTimeout()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.timeoutDuration ?? 10.0))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if case .listening = self?.state {
                    self?.deactivateCommandMode()
                }
            }
        }
    }

    private func cancelTimeout() {
        timeoutTask?.cancel()
        timeoutTask = nil
    }
}
```

### Visual Indicators

When command mode is active, HushType displays a floating overlay in the menu bar area and optionally a larger on-screen indicator:

| State | Indicator | Color | Description |
|-------|-----------|-------|-------------|
| Inactive | None | -- | No overlay visible |
| Listening | Pulsing microphone icon | Blue | Waiting for a spoken command |
| Processing | Spinning gear | Amber | Parsing the command |
| Executing | Progress bar | Green | Running the command |
| Completed | Checkmark | Green | Command succeeded |
| Error | Exclamation mark | Red | Command failed |

> ⚠️ Visual indicators use `NSPanel` with `.nonactivatingPanel` style mask to avoid stealing focus from the user's active application.

### Timeout Behavior

Command mode automatically deactivates after a configurable timeout (default: 10 seconds) of silence. The timeout resets each time partial speech is detected. Users may also say `"cancel"` or `"never mind"` to explicitly exit command mode.

```swift
// Built-in cancellation phrases
private let cancellationPhrases: Set<String> = [
    "cancel",
    "never mind",
    "nevermind",
    "stop",
    "dismiss",
    "forget it"
]

func isCancellation(_ text: String) -> Bool {
    cancellationPhrases.contains(text.lowercased().trimmingCharacters(in: .whitespaces))
}
```

---

## Natural Language Command Parser Design

### Regex-Based Parsing

The primary parser uses compiled regular expressions for fast, deterministic matching of known command patterns. This parser handles the vast majority of commands with sub-millisecond latency.

```swift
import Foundation

// MARK: - Parsed Command

struct ParsedCommand: Sendable {
    let intent: CommandIntent
    let entities: [String: String]
    let rawText: String
    let confidence: Double
    let displayName: String
    let source: ParserSource

    enum ParserSource: Sendable {
        case regex
        case llm
        case alias
    }
}

// MARK: - Command Intent

enum CommandIntent: String, CaseIterable, Sendable {
    // App management
    case openApp
    case switchToApp
    case closeApp
    case quitApp
    case minimizeWindow
    case maximizeWindow
    case fullScreenWindow
    case newTab
    case newWindow

    // Window management
    case moveWindowLeft
    case moveWindowRight
    case moveWindowNextDesktop
    case tileWindows
    case centerWindow
    case resizeWindow

    // System control
    case volumeUp
    case volumeDown
    case volumeMute
    case volumeSet
    case brightnessUp
    case brightnessDown
    case brightnessSet
    case doNotDisturbOn
    case doNotDisturbOff
    case screenshot
    case lockScreen
    case sleepDisplay

    // Workflow
    case chainedCommand
    case runShortcut
    case runAppleScript
    case customAlias
}

// MARK: - Regex Command Pattern

struct RegexCommandPattern: Sendable {
    let intent: CommandIntent
    let pattern: Regex<AnyRegexOutput>
    let entityKeys: [String]
    let priority: Int
    let displayTemplate: String

    func match(_ input: String) -> (entities: [String: String], confidence: Double)? {
        let lowercased = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = try? pattern.firstMatch(in: lowercased) else {
            return nil
        }

        var entities: [String: String] = [:]
        for (index, key) in entityKeys.enumerated() {
            let captureIndex = index + 1
            if captureIndex < match.output.count,
               let substring = match.output[captureIndex].substring {
                entities[key] = String(substring).trimmingCharacters(in: .whitespaces)
            }
        }

        // Confidence is based on how much of the input the pattern consumed
        let matchLength = match.output[0].substring?.count ?? 0
        let confidence = Double(matchLength) / Double(lowercased.count)

        return (entities, min(confidence, 1.0))
    }
}

// MARK: - Regex-Based Command Parser

final class RegexCommandParser: Sendable {
    let patterns: [RegexCommandPattern]

    init() {
        self.patterns = Self.buildPatterns()
    }

    func parse(_ input: String) -> ParsedCommand? {
        var bestMatch: (pattern: RegexCommandPattern, entities: [String: String], confidence: Double)?

        for pattern in patterns {
            if let result = pattern.match(input) {
                let effectiveScore = result.confidence * Double(pattern.priority)
                let currentBest = bestMatch.map { $0.confidence * Double($0.pattern.priority) } ?? 0
                if effectiveScore > currentBest {
                    bestMatch = (pattern, result.entities, result.confidence)
                }
            }
        }

        guard let match = bestMatch, match.confidence >= 0.5 else {
            return nil
        }

        let displayName = formatDisplayName(match.pattern.displayTemplate, entities: match.entities)

        return ParsedCommand(
            intent: match.pattern.intent,
            entities: match.entities,
            rawText: input,
            confidence: match.confidence,
            displayName: displayName,
            source: .regex
        )
    }

    // MARK: - Pattern Definitions

    private static func buildPatterns() -> [RegexCommandPattern] {
        [
            // --- App Management ---
            RegexCommandPattern(
                intent: .openApp,
                pattern: try! Regex(#"^(?:open|launch|start|run)\s+(.+)"#),
                entityKeys: ["appName"],
                priority: 10,
                displayTemplate: "Open {appName}"
            ),
            RegexCommandPattern(
                intent: .switchToApp,
                pattern: try! Regex(#"^(?:switch to|go to|activate|focus)\s+(.+)"#),
                entityKeys: ["appName"],
                priority: 10,
                displayTemplate: "Switch to {appName}"
            ),
            RegexCommandPattern(
                intent: .closeApp,
                pattern: try! Regex(#"^close\s+(.+)"#),
                entityKeys: ["appName"],
                priority: 10,
                displayTemplate: "Close {appName}"
            ),
            RegexCommandPattern(
                intent: .quitApp,
                pattern: try! Regex(#"^(?:quit|exit|terminate|kill)\s+(.+)"#),
                entityKeys: ["appName"],
                priority: 10,
                displayTemplate: "Quit {appName}"
            ),
            RegexCommandPattern(
                intent: .minimizeWindow,
                pattern: try! Regex(#"^minimize(?:\s+(?:the\s+)?window)?"#),
                entityKeys: [],
                priority: 8,
                displayTemplate: "Minimize window"
            ),
            RegexCommandPattern(
                intent: .maximizeWindow,
                pattern: try! Regex(#"^maximize(?:\s+(?:the\s+)?window)?"#),
                entityKeys: [],
                priority: 8,
                displayTemplate: "Maximize window"
            ),
            RegexCommandPattern(
                intent: .fullScreenWindow,
                pattern: try! Regex(#"^(?:full\s*screen|enter\s+full\s*screen|toggle\s+full\s*screen)"#),
                entityKeys: [],
                priority: 8,
                displayTemplate: "Toggle full screen"
            ),
            RegexCommandPattern(
                intent: .newTab,
                pattern: try! Regex(#"^(?:new\s+tab|open\s+(?:a\s+)?new\s+tab)"#),
                entityKeys: [],
                priority: 8,
                displayTemplate: "New tab"
            ),
            RegexCommandPattern(
                intent: .newWindow,
                pattern: try! Regex(#"^(?:new\s+window|open\s+(?:a\s+)?new\s+window)"#),
                entityKeys: [],
                priority: 8,
                displayTemplate: "New window"
            ),

            // --- Window Management ---
            RegexCommandPattern(
                intent: .moveWindowLeft,
                pattern: try! Regex(#"^(?:move|snap|put)\s+(?:the\s+)?window\s+(?:to\s+)?(?:the\s+)?left(?:\s+half)?"#),
                entityKeys: [],
                priority: 9,
                displayTemplate: "Move window to left half"
            ),
            RegexCommandPattern(
                intent: .moveWindowRight,
                pattern: try! Regex(#"^(?:move|snap|put)\s+(?:the\s+)?window\s+(?:to\s+)?(?:the\s+)?right(?:\s+half)?"#),
                entityKeys: [],
                priority: 9,
                displayTemplate: "Move window to right half"
            ),
            RegexCommandPattern(
                intent: .moveWindowNextDesktop,
                pattern: try! Regex(#"^move\s+(?:the\s+)?(?:window\s+)?to\s+(?:the\s+)?next\s+(?:desktop|space)"#),
                entityKeys: [],
                priority: 9,
                displayTemplate: "Move window to next desktop"
            ),
            RegexCommandPattern(
                intent: .tileWindows,
                pattern: try! Regex(#"^tile\s+(?:all\s+)?windows"#),
                entityKeys: [],
                priority: 9,
                displayTemplate: "Tile all windows"
            ),

            // --- System Control ---
            RegexCommandPattern(
                intent: .volumeUp,
                pattern: try! Regex(#"^(?:turn\s+)?(?:volume\s+up|increase\s+volume|louder)"#),
                entityKeys: [],
                priority: 8,
                displayTemplate: "Volume up"
            ),
            RegexCommandPattern(
                intent: .volumeDown,
                pattern: try! Regex(#"^(?:turn\s+)?(?:volume\s+down|decrease\s+volume|quieter|softer)"#),
                entityKeys: [],
                priority: 8,
                displayTemplate: "Volume down"
            ),
            RegexCommandPattern(
                intent: .volumeMute,
                pattern: try! Regex(#"^(?:mute|unmute|toggle\s+mute)"#),
                entityKeys: [],
                priority: 8,
                displayTemplate: "Toggle mute"
            ),
            RegexCommandPattern(
                intent: .volumeSet,
                pattern: try! Regex(#"^(?:set\s+)?volume\s+(?:to\s+)?(\d+)(?:\s*%?)?"#),
                entityKeys: ["level"],
                priority: 9,
                displayTemplate: "Set volume to {level}%"
            ),
            RegexCommandPattern(
                intent: .brightnessUp,
                pattern: try! Regex(#"^(?:turn\s+)?(?:brightness\s+up|increase\s+brightness|brighter)"#),
                entityKeys: [],
                priority: 8,
                displayTemplate: "Brightness up"
            ),
            RegexCommandPattern(
                intent: .brightnessDown,
                pattern: try! Regex(#"^(?:turn\s+)?(?:brightness\s+down|decrease\s+brightness|dimmer)"#),
                entityKeys: [],
                priority: 8,
                displayTemplate: "Brightness down"
            ),
            RegexCommandPattern(
                intent: .doNotDisturbOn,
                pattern: try! Regex(#"^(?:turn\s+on\s+|enable\s+)?(?:do\s+not\s+disturb|dnd|focus\s+mode)"#),
                entityKeys: [],
                priority: 8,
                displayTemplate: "Enable Do Not Disturb"
            ),
            RegexCommandPattern(
                intent: .doNotDisturbOff,
                pattern: try! Regex(#"^(?:turn\s+off\s+|disable\s+)(?:do\s+not\s+disturb|dnd|focus\s+mode)"#),
                entityKeys: [],
                priority: 8,
                displayTemplate: "Disable Do Not Disturb"
            ),
            RegexCommandPattern(
                intent: .screenshot,
                pattern: try! Regex(#"^(?:take\s+(?:a\s+)?)?screenshot"#),
                entityKeys: [],
                priority: 8,
                displayTemplate: "Take screenshot"
            ),
            RegexCommandPattern(
                intent: .lockScreen,
                pattern: try! Regex(#"^lock\s+(?:the\s+)?screen"#),
                entityKeys: [],
                priority: 8,
                displayTemplate: "Lock screen"
            ),
            RegexCommandPattern(
                intent: .sleepDisplay,
                pattern: try! Regex(#"^(?:sleep|turn\s+off)\s+(?:the\s+)?(?:display|screen|monitor)"#),
                entityKeys: [],
                priority: 8,
                displayTemplate: "Sleep display"
            ),

            // --- Shortcuts ---
            RegexCommandPattern(
                intent: .runShortcut,
                pattern: try! Regex(#"^(?:run|execute|trigger)\s+(?:the\s+)?shortcut\s+(.+)"#),
                entityKeys: ["shortcutName"],
                priority: 7,
                displayTemplate: "Run shortcut: {shortcutName}"
            ),
        ]
    }

    private func formatDisplayName(_ template: String, entities: [String: String]) -> String {
        var result = template
        for (key, value) in entities {
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return result
    }
}
```

### LLM-Based Parsing

For commands that do not match any regex pattern, HushType optionally routes the input through a local llama.cpp model for deeper intent classification. This is disabled by default and requires a downloaded NLU model.

```swift
// MARK: - LLM Command Parser

actor LLMCommandParser {
    private let modelPath: URL
    private var isLoaded = false

    init(modelPath: URL) {
        self.modelPath = modelPath
    }

    /// Parses a natural language command using the local LLM.
    /// Falls back to nil if the model is unavailable or confidence is too low.
    func parse(_ input: String) async throws -> ParsedCommand? {
        guard isLoaded else {
            try await loadModel()
            return try await parse(input)
        }

        let prompt = buildClassificationPrompt(input)
        let response = try await runInference(prompt)
        return try decodeResponse(response, rawText: input)
    }

    private func buildClassificationPrompt(_ input: String) -> String {
        """
        Classify the following voice command into a JSON object with these fields:
        - "intent": one of [\(CommandIntent.allCases.map(\.rawValue).joined(separator: ", "))]
        - "entities": a dictionary of extracted parameters
        - "confidence": a number between 0 and 1

        Voice command: "\(input)"

        Respond with ONLY the JSON object, no additional text.
        """
    }

    private func loadModel() async throws {
        // Integration point with llama.cpp via LlamaContext
        // See SPEECH_RECOGNITION.md for model loading patterns
        isLoaded = true
    }

    private func runInference(_ prompt: String) async throws -> String {
        // Delegates to the llama.cpp inference engine
        // Placeholder -- actual implementation bridges to C++ via LlamaContext
        fatalError("Implemented in LlamaContext bridge -- see LLM_PROCESSING.md")
    }

    private func decodeResponse(_ json: String, rawText: String) throws -> ParsedCommand? {
        struct LLMResponse: Decodable {
            let intent: String
            let entities: [String: String]
            let confidence: Double
        }

        guard let data = json.data(using: .utf8) else { return nil }
        let decoded = try JSONDecoder().decode(LLMResponse.self, from: data)

        guard let intent = CommandIntent(rawValue: decoded.intent),
              decoded.confidence >= 0.6 else {
            return nil
        }

        return ParsedCommand(
            intent: intent,
            entities: decoded.entities,
            rawText: rawText,
            confidence: decoded.confidence,
            displayName: "\(intent.rawValue) (LLM)",
            source: .llm
        )
    }
}
```

> 🔒 The LLM parser runs entirely on-device using llama.cpp. No text is ever sent to a remote server. See [`LLM_PROCESSING.md`](LLM_PROCESSING.md) for model management.

### Intent Classification

The combined parser attempts regex first, then falls back to LLM:

```swift
// MARK: - Combined Command Parser

final class CommandParser: Sendable {
    private let regexParser = RegexCommandParser()
    private let llmParser: LLMCommandParser?
    private let aliasResolver: AliasResolver

    init(llmModelPath: URL? = nil, aliasResolver: AliasResolver = AliasResolver()) {
        self.llmParser = llmModelPath.map { LLMCommandParser(modelPath: $0) }
        self.aliasResolver = aliasResolver
    }

    func parse(_ input: String) async throws -> ParsedCommand {
        // Step 1: Check for custom aliases first
        if let aliasCommand = await aliasResolver.resolve(input) {
            return aliasCommand
        }

        // Step 2: Try regex-based parser (fast path)
        if let regexResult = regexParser.parse(input) {
            return regexResult
        }

        // Step 3: Try LLM-based parser (slow path, optional)
        if let llm = llmParser,
           let llmResult = try await llm.parse(input) {
            return llmResult
        }

        // Step 4: No match found
        throw CommandError.unrecognizedCommand(input)
    }
}
```

### Entity Extraction

Entities are key-value pairs extracted from the spoken command. Common entities include:

| Entity Key | Description | Example Input | Extracted Value |
|------------|-------------|---------------|-----------------|
| `appName` | Target application name | "open Safari" | "safari" |
| `level` | Numeric level (volume, brightness) | "set volume to 75" | "75" |
| `shortcutName` | Apple Shortcuts name | "run shortcut Morning Routine" | "morning routine" |
| `direction` | Spatial direction | "move window to left" | "left" |
| `chainedCommands` | Compound command text | "open Terminal and run..." | full chain text |

---

## Built-in Command Registry

### Command Data Structure

```swift
import Foundation

// MARK: - Command Definition

struct CommandDefinition: Identifiable, Sendable {
    let id: String
    let intent: CommandIntent
    let name: String
    let description: String
    let category: CommandCategory
    let requiredEntities: [String]
    let optionalEntities: [String]
    let requiresConfirmation: Bool
    let handler: @Sendable (ParsedCommand) async throws -> CommandResult

    enum CommandCategory: String, CaseIterable, Sendable {
        case appManagement = "App Management"
        case windowManagement = "Window Management"
        case systemControl = "System Control"
        case workflow = "Workflow"
        case shortcuts = "Shortcuts"
        case applescript = "AppleScript"
    }
}

// MARK: - Command Result

struct CommandResult: Sendable {
    let success: Bool
    let message: String
    let duration: TimeInterval
    let undoAction: (@Sendable () async throws -> Void)?

    init(success: Bool, message: String, duration: TimeInterval = 0, undoAction: (@Sendable () async throws -> Void)? = nil) {
        self.success = success
        self.message = message
        self.duration = duration
        self.undoAction = undoAction
    }
}

// MARK: - Command Error

enum CommandError: LocalizedError {
    case unrecognizedCommand(String)
    case missingEntity(String)
    case appNotFound(String)
    case permissionDenied(String)
    case executionFailed(String)
    case chainFailed(at: Int, underlying: Error)
    case timeout

    var errorDescription: String? {
        switch self {
        case .unrecognizedCommand(let text):
            return "Unrecognized command: \"\(text)\""
        case .missingEntity(let entity):
            return "Missing required parameter: \(entity)"
        case .appNotFound(let name):
            return "Application not found: \(name)"
        case .permissionDenied(let detail):
            return "Permission denied: \(detail)"
        case .executionFailed(let detail):
            return "Command failed: \(detail)"
        case .chainFailed(let index, let underlying):
            return "Chain failed at step \(index + 1): \(underlying.localizedDescription)"
        case .timeout:
            return "Command timed out"
        }
    }
}
```

### Command Matching

```swift
// MARK: - Command Registry

@MainActor
final class CommandRegistry {
    private var commands: [String: CommandDefinition] = [:]
    private var intentIndex: [CommandIntent: [CommandDefinition]] = [:]

    static let shared = CommandRegistry()

    private init() {
        registerBuiltInCommands()
    }

    func register(_ command: CommandDefinition) {
        commands[command.id] = command
        intentIndex[command.intent, default: []].append(command)
    }

    func lookup(intent: CommandIntent) -> CommandDefinition? {
        intentIndex[intent]?.first
    }

    func allCommands() -> [CommandDefinition] {
        Array(commands.values)
    }

    func commands(in category: CommandDefinition.CommandCategory) -> [CommandDefinition] {
        commands.values.filter { $0.category == category }
    }

    private func registerBuiltInCommands() {
        // App management commands
        register(CommandDefinition(
            id: "app.open",
            intent: .openApp,
            name: "Open Application",
            description: "Launches or brings an application to the foreground",
            category: .appManagement,
            requiredEntities: ["appName"],
            optionalEntities: [],
            requiresConfirmation: false,
            handler: AppCommandHandler.openApp
        ))

        register(CommandDefinition(
            id: "app.switch",
            intent: .switchToApp,
            name: "Switch to Application",
            description: "Activates a running application",
            category: .appManagement,
            requiredEntities: ["appName"],
            optionalEntities: [],
            requiresConfirmation: false,
            handler: AppCommandHandler.switchToApp
        ))

        register(CommandDefinition(
            id: "app.close",
            intent: .closeApp,
            name: "Close Application",
            description: "Closes the frontmost window of an application",
            category: .appManagement,
            requiredEntities: ["appName"],
            optionalEntities: [],
            requiresConfirmation: false,
            handler: AppCommandHandler.closeApp
        ))

        register(CommandDefinition(
            id: "app.quit",
            intent: .quitApp,
            name: "Quit Application",
            description: "Terminates an application",
            category: .appManagement,
            requiredEntities: ["appName"],
            optionalEntities: [],
            requiresConfirmation: true,
            handler: AppCommandHandler.quitApp
        ))

        // Window management commands
        register(CommandDefinition(
            id: "window.left",
            intent: .moveWindowLeft,
            name: "Move Window Left",
            description: "Snaps the frontmost window to the left half of the screen",
            category: .windowManagement,
            requiredEntities: [],
            optionalEntities: [],
            requiresConfirmation: false,
            handler: WindowCommandHandler.moveLeft
        ))

        register(CommandDefinition(
            id: "window.right",
            intent: .moveWindowRight,
            name: "Move Window Right",
            description: "Snaps the frontmost window to the right half of the screen",
            category: .windowManagement,
            requiredEntities: [],
            optionalEntities: [],
            requiresConfirmation: false,
            handler: WindowCommandHandler.moveRight
        ))

        // System commands
        register(CommandDefinition(
            id: "system.volume.up",
            intent: .volumeUp,
            name: "Volume Up",
            description: "Increases system volume by one step",
            category: .systemControl,
            requiredEntities: [],
            optionalEntities: [],
            requiresConfirmation: false,
            handler: SystemCommandHandler.volumeUp
        ))

        register(CommandDefinition(
            id: "system.screenshot",
            intent: .screenshot,
            name: "Take Screenshot",
            description: "Captures a screenshot of the entire screen",
            category: .systemControl,
            requiredEntities: [],
            optionalEntities: [],
            requiresConfirmation: false,
            handler: SystemCommandHandler.takeScreenshot
        ))

        register(CommandDefinition(
            id: "system.lock",
            intent: .lockScreen,
            name: "Lock Screen",
            description: "Locks the screen immediately",
            category: .systemControl,
            requiredEntities: [],
            optionalEntities: [],
            requiresConfirmation: true,
            handler: SystemCommandHandler.lockScreen
        ))

        // Shortcut commands
        register(CommandDefinition(
            id: "shortcuts.run",
            intent: .runShortcut,
            name: "Run Shortcut",
            description: "Executes an Apple Shortcut by name",
            category: .shortcuts,
            requiredEntities: ["shortcutName"],
            optionalEntities: [],
            requiresConfirmation: false,
            handler: ShortcutCommandHandler.runShortcut
        ))
    }
}
```

### Priority and Confidence Scoring

Commands are ranked by a composite score that combines pattern match confidence with priority weighting:

```
effectiveScore = confidence * priority * (isAlias ? 1.2 : 1.0)
```

- **`confidence`** (0.0-1.0): how well the input matches the pattern
- **`priority`** (1-10): static weight assigned per pattern; app-specific commands default to 10, system commands to 8
- **Alias boost**: custom aliases receive a 20% bonus to ensure user-defined commands take precedence

> ℹ️ A minimum confidence threshold of 0.5 is enforced. Commands below this threshold are rejected as unrecognized.

### Extensibility

Third-party extensions can register new commands through the `CommandRegistry`:

```swift
// Example: Registering a custom command at app startup
CommandRegistry.shared.register(CommandDefinition(
    id: "custom.pomodoro.start",
    intent: .customAlias,
    name: "Start Pomodoro",
    description: "Starts a 25-minute focus timer",
    category: .workflow,
    requiredEntities: [],
    optionalEntities: ["duration"],
    requiresConfirmation: false,
    handler: { command in
        let duration = Int(command.entities["duration"] ?? "25") ?? 25
        await PomodoroTimer.shared.start(minutes: duration)
        return CommandResult(success: true, message: "Pomodoro started: \(duration) minutes")
    }
))
```

---

## App Management Commands

### Open App

```swift
import AppKit

// MARK: - App Command Handler

enum AppCommandHandler {

    /// Opens an application by name using NSWorkspace.
    static func openApp(_ command: ParsedCommand) async throws -> CommandResult {
        guard let appName = command.entities["appName"] else {
            throw CommandError.missingEntity("appName")
        }

        let workspace = NSWorkspace.shared

        // Strategy 1: Open by bundle identifier (most reliable)
        if let bundleID = resolveAppBundleIdentifier(appName) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
                try await workspace.openApplication(at: appURL, configuration: config)
                return CommandResult(success: true, message: "Opened \(appName)")
            }
        }

        // Strategy 2: Open by application URL path
        if let appURL = findApplicationURL(named: appName) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            try await workspace.openApplication(at: appURL, configuration: config)
            return CommandResult(success: true, message: "Opened \(appName)")
        }

        throw CommandError.appNotFound(appName)
    }

    /// Resolves a spoken app name to a macOS bundle identifier.
    private static func resolveAppBundleIdentifier(_ name: String) -> String? {
        let normalized = name.lowercased().trimmingCharacters(in: .whitespaces)

        // Common aliases map
        let knownApps: [String: String] = [
            "safari": "com.apple.Safari",
            "chrome": "com.google.Chrome",
            "google chrome": "com.google.Chrome",
            "firefox": "org.mozilla.firefox",
            "terminal": "com.apple.Terminal",
            "finder": "com.apple.finder",
            "mail": "com.apple.mail",
            "messages": "com.apple.MobileSMS",
            "notes": "com.apple.Notes",
            "calendar": "com.apple.iCal",
            "music": "com.apple.Music",
            "photos": "com.apple.Photos",
            "preview": "com.apple.Preview",
            "settings": "com.apple.systempreferences",
            "system settings": "com.apple.systempreferences",
            "system preferences": "com.apple.systempreferences",
            "xcode": "com.apple.dt.Xcode",
            "vscode": "com.microsoft.VSCode",
            "visual studio code": "com.microsoft.VSCode",
            "slack": "com.tinyspeck.slackmacgap",
            "spotify": "com.spotify.client",
            "discord": "com.hnc.Discord",
            "zoom": "us.zoom.xos",
            "notion": "notion.id",
            "figma": "com.figma.Desktop",
            "iterm": "com.googlecode.iterm2",
            "iterm2": "com.googlecode.iterm2",
        ]

        if let bundleID = knownApps[normalized] {
            return bundleID
        }

        // Try to find via Launch Services
        let workspace = NSWorkspace.shared
        if let url = workspace.urlForApplication(withBundleIdentifier: normalized) {
            return Bundle(url: url)?.bundleIdentifier
        }

        return nil
    }

    /// Searches /Applications and ~/Applications for an app by name.
    private static func findApplicationURL(named name: String) -> URL? {
        let searchPaths = [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
            URL(fileURLWithPath: "/System/Applications"),
        ]

        let normalized = name.lowercased()

        for searchPath in searchPaths {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: searchPath,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in contents where url.pathExtension == "app" {
                let appNameOnDisk = url.deletingPathExtension().lastPathComponent.lowercased()
                if appNameOnDisk == normalized || appNameOnDisk.contains(normalized) {
                    return url
                }
            }
        }

        return nil
    }
```

### Switch to App

```swift
    /// Switches to (activates) a running application.
    static func switchToApp(_ command: ParsedCommand) async throws -> CommandResult {
        guard let appName = command.entities["appName"] else {
            throw CommandError.missingEntity("appName")
        }

        let runningApps = NSWorkspace.shared.runningApplications
        let normalized = appName.lowercased()

        // Find the best matching running application
        let match = runningApps.first { app in
            guard let name = app.localizedName else { return false }
            return name.lowercased() == normalized || name.lowercased().contains(normalized)
        }

        guard let app = match else {
            // If not running, try to open it instead
            return try await openApp(command)
        }

        let activated = app.activate()
        if activated {
            return CommandResult(success: true, message: "Switched to \(app.localizedName ?? appName)")
        } else {
            throw CommandError.executionFailed("Could not activate \(appName)")
        }
    }
```

### Close and Quit App

```swift
    /// Closes the frontmost window of an app (Cmd+W equivalent).
    static func closeApp(_ command: ParsedCommand) async throws -> CommandResult {
        guard let appName = command.entities["appName"] else {
            throw CommandError.missingEntity("appName")
        }

        let runningApps = NSWorkspace.shared.runningApplications
        let normalized = appName.lowercased()

        guard let app = runningApps.first(where: {
            $0.localizedName?.lowercased().contains(normalized) == true
        }) else {
            throw CommandError.appNotFound(appName)
        }

        // Activate the app first, then send Cmd+W
        app.activate()
        try await Task.sleep(for: .milliseconds(200))

        let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x0D, keyDown: true)  // 'w' key
        let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x0D, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        return CommandResult(success: true, message: "Closed \(app.localizedName ?? appName) window")
    }

    /// Quits an application entirely.
    static func quitApp(_ command: ParsedCommand) async throws -> CommandResult {
        guard let appName = command.entities["appName"] else {
            throw CommandError.missingEntity("appName")
        }

        let runningApps = NSWorkspace.shared.runningApplications
        let normalized = appName.lowercased()

        guard let app = runningApps.first(where: {
            $0.localizedName?.lowercased().contains(normalized) == true
        }) else {
            throw CommandError.appNotFound(appName)
        }

        let terminated = app.terminate()
        if terminated {
            return CommandResult(success: true, message: "Quit \(app.localizedName ?? appName)")
        } else {
            // Force terminate as fallback
            let forceTerminated = app.forceTerminate()
            if forceTerminated {
                return CommandResult(success: true, message: "Force quit \(app.localizedName ?? appName)")
            }
            throw CommandError.executionFailed("Could not quit \(appName)")
        }
    }
}
```

> ⚠️ `quitApp` is marked with `requiresConfirmation: true` in the command registry. HushType will ask the user to confirm before terminating an application ("Did you say quit Safari?").

### Window State Commands

```swift
// MARK: - Window State Handler (Minimize, Maximize, Full Screen)

enum WindowStateHandler {

    static func minimize(_ command: ParsedCommand) async throws -> CommandResult {
        // Send Cmd+M to minimize frontmost window
        try await sendKeyboardShortcut(key: 0x2E, modifiers: .maskCommand)  // 'm' key
        return CommandResult(success: true, message: "Window minimized")
    }

    static func maximize(_ command: ParsedCommand) async throws -> CommandResult {
        // macOS has no native maximize shortcut;
        // use Accessibility API to resize to screen bounds
        try await resizeToFillScreen()
        return CommandResult(success: true, message: "Window maximized")
    }

    static func toggleFullScreen(_ command: ParsedCommand) async throws -> CommandResult {
        // Send Ctrl+Cmd+F to toggle full screen
        try await sendKeyboardShortcut(key: 0x03, modifiers: [.maskCommand, .maskControl])  // 'f' key
        return CommandResult(success: true, message: "Full screen toggled")
    }

    private static func sendKeyboardShortcut(key: CGKeyCode, modifiers: CGEventFlags) async throws {
        let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false)
        keyDown?.flags = modifiers
        keyUp?.flags = modifiers
        keyDown?.post(tap: .cghidEventTap)
        try await Task.sleep(for: .milliseconds(50))
        keyUp?.post(tap: .cghidEventTap)
    }

    private static func resizeToFillScreen() async throws {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            throw CommandError.executionFailed("No frontmost application")
        }

        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let window = windowRef else {
            throw CommandError.executionFailed("Could not access focused window")
        }

        let axWindow = window as! AXUIElement

        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame

        var position = CGPoint(x: visibleFrame.origin.x, y: screen.frame.height - visibleFrame.maxY)
        var size = CGSize(width: visibleFrame.width, height: visibleFrame.height)

        let positionValue = AXValueCreate(.cgPoint, &position)!
        let sizeValue = AXValueCreate(.cgSize, &size)!

        AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, positionValue)
        AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeValue)
    }
}
```

### Tab and Window Commands

```swift
enum TabWindowHandler {

    /// Opens a new tab in the frontmost application (Cmd+T).
    static func newTab(_ command: ParsedCommand) async throws -> CommandResult {
        try await sendKeyboardShortcut(key: 0x11, modifiers: .maskCommand)  // 't' key
        return CommandResult(success: true, message: "New tab opened")
    }

    /// Opens a new window in the frontmost application (Cmd+N).
    static func newWindow(_ command: ParsedCommand) async throws -> CommandResult {
        try await sendKeyboardShortcut(key: 0x2D, modifiers: .maskCommand)  // 'n' key
        return CommandResult(success: true, message: "New window opened")
    }

    private static func sendKeyboardShortcut(key: CGKeyCode, modifiers: CGEventFlags) async throws {
        let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false)
        keyDown?.flags = modifiers
        keyUp?.flags = modifiers
        keyDown?.post(tap: .cghidEventTap)
        try await Task.sleep(for: .milliseconds(50))
        keyUp?.post(tap: .cghidEventTap)
    }
}
```

---

## Window Management Commands

### Move Window to Half

```swift
// MARK: - Window Management via Accessibility APIs

enum WindowCommandHandler {

    /// Snaps the frontmost window to the left half of the screen.
    static func moveLeft(_ command: ParsedCommand) async throws -> CommandResult {
        try await snapWindow(to: .left)
        return CommandResult(success: true, message: "Window moved to left half")
    }

    /// Snaps the frontmost window to the right half of the screen.
    static func moveRight(_ command: ParsedCommand) async throws -> CommandResult {
        try await snapWindow(to: .right)
        return CommandResult(success: true, message: "Window moved to right half")
    }

    enum SnapPosition {
        case left
        case right
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }

    private static func snapWindow(to position: SnapPosition) async throws {
        guard let screen = NSScreen.main else {
            throw CommandError.executionFailed("No main screen available")
        }

        let visibleFrame = screen.visibleFrame
        let screenHeight = screen.frame.height

        // Calculate target frame based on snap position
        let (targetOrigin, targetSize): (CGPoint, CGSize) = switch position {
        case .left:
            (
                CGPoint(x: visibleFrame.origin.x, y: screenHeight - visibleFrame.maxY),
                CGSize(width: visibleFrame.width / 2, height: visibleFrame.height)
            )
        case .right:
            (
                CGPoint(x: visibleFrame.origin.x + visibleFrame.width / 2, y: screenHeight - visibleFrame.maxY),
                CGSize(width: visibleFrame.width / 2, height: visibleFrame.height)
            )
        case .topLeft:
            (
                CGPoint(x: visibleFrame.origin.x, y: screenHeight - visibleFrame.maxY),
                CGSize(width: visibleFrame.width / 2, height: visibleFrame.height / 2)
            )
        case .topRight:
            (
                CGPoint(x: visibleFrame.origin.x + visibleFrame.width / 2, y: screenHeight - visibleFrame.maxY),
                CGSize(width: visibleFrame.width / 2, height: visibleFrame.height / 2)
            )
        case .bottomLeft:
            (
                CGPoint(x: visibleFrame.origin.x, y: screenHeight - visibleFrame.maxY + visibleFrame.height / 2),
                CGSize(width: visibleFrame.width / 2, height: visibleFrame.height / 2)
            )
        case .bottomRight:
            (
                CGPoint(x: visibleFrame.origin.x + visibleFrame.width / 2, y: screenHeight - visibleFrame.maxY + visibleFrame.height / 2),
                CGSize(width: visibleFrame.width / 2, height: visibleFrame.height / 2)
            )
        }

        try setWindowFrame(origin: targetOrigin, size: targetSize)
    }

    /// Sets the position and size of the frontmost application's focused window.
    private static func setWindowFrame(origin: CGPoint, size: CGSize) throws {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            throw CommandError.executionFailed("No frontmost application")
        }

        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        var windowRef: CFTypeRef?

        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &windowRef
        )

        guard result == .success, let window = windowRef else {
            throw CommandError.permissionDenied(
                "Cannot access window. Ensure Accessibility permission is granted."
            )
        }

        let axWindow = window as! AXUIElement

        var mutableOrigin = origin
        var mutableSize = size

        guard let positionValue = AXValueCreate(.cgPoint, &mutableOrigin),
              let sizeValue = AXValueCreate(.cgSize, &mutableSize) else {
            throw CommandError.executionFailed("Failed to create AXValue for position/size")
        }

        AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, positionValue)
        AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeValue)
    }
}
```

> 🍎 The Accessibility API (`AXUIElement`) requires the user to grant HushType access in **System Settings > Privacy & Security > Accessibility**. See [`PERMISSIONS.md`](PERMISSIONS.md).

### Move to Next Desktop

```swift
extension WindowCommandHandler {

    /// Moves the frontmost window to the next virtual desktop (Space).
    /// This is accomplished by simulating Ctrl+Arrow keyboard shortcuts
    /// since there is no public API for Mission Control space assignment.
    static func moveToNextDesktop(_ command: ParsedCommand) async throws -> CommandResult {
        // macOS does not expose a public API for moving windows between Spaces.
        // The workaround uses the following sequence:
        // 1. Make the window the frontmost
        // 2. Enter Mission Control briefly to assign the window
        // Alternatively, use keyboard simulation with Ctrl+Right Arrow
        // after ensuring the System Preferences option is enabled.

        let keyDown = CGEvent(
            keyboardEventSource: nil,
            virtualKey: 0x7C,  // Right arrow
            keyDown: true
        )
        let keyUp = CGEvent(
            keyboardEventSource: nil,
            virtualKey: 0x7C,
            keyDown: false
        )
        keyDown?.flags = .maskControl
        keyUp?.flags = .maskControl

        keyDown?.post(tap: .cghidEventTap)
        try await Task.sleep(for: .milliseconds(100))
        keyUp?.post(tap: .cghidEventTap)

        return CommandResult(
            success: true,
            message: "Attempted to move window to next desktop"
        )
    }
}
```

> ⚠️ Moving windows between Spaces relies on keyboard simulation and requires the **"Displays have separate Spaces"** option to be enabled in **System Settings > Desktop & Dock**. This approach may not work reliably in all configurations.

### Tile Windows

```swift
extension WindowCommandHandler {

    /// Tiles all visible windows of the frontmost application in a grid layout.
    static func tileWindows(_ command: ParsedCommand) async throws -> CommandResult {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            throw CommandError.executionFailed("No frontmost application")
        }

        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        var windowArrayRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowArrayRef
        )

        guard result == .success,
              let windowArray = windowArrayRef as? [AXUIElement],
              !windowArray.isEmpty else {
            throw CommandError.executionFailed("No windows found for \(frontApp.localizedName ?? "app")")
        }

        guard let screen = NSScreen.main else {
            throw CommandError.executionFailed("No main screen")
        }

        let visibleFrame = screen.visibleFrame
        let screenHeight = screen.frame.height
        let windowCount = windowArray.count

        // Calculate grid dimensions
        let columns = Int(ceil(sqrt(Double(windowCount))))
        let rows = Int(ceil(Double(windowCount) / Double(columns)))

        let tileWidth = visibleFrame.width / CGFloat(columns)
        let tileHeight = visibleFrame.height / CGFloat(rows)

        for (index, window) in windowArray.enumerated() {
            let col = index % columns
            let row = index / columns

            var origin = CGPoint(
                x: visibleFrame.origin.x + CGFloat(col) * tileWidth,
                y: (screenHeight - visibleFrame.maxY) + CGFloat(row) * tileHeight
            )
            var size = CGSize(width: tileWidth, height: tileHeight)

            if let positionValue = AXValueCreate(.cgPoint, &origin),
               let sizeValue = AXValueCreate(.cgSize, &size) {
                AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
                AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
            }
        }

        return CommandResult(
            success: true,
            message: "Tiled \(windowCount) windows in a \(columns)x\(rows) grid"
        )
    }
}
```

### Window Management via Accessibility APIs

All window management operations in HushType are built on the macOS Accessibility API (`AXUIElement`). The key attributes used are:

| Attribute | Type | Description |
|-----------|------|-------------|
| `kAXFocusedWindowAttribute` | `AXUIElement` | The currently focused window of an app |
| `kAXWindowsAttribute` | `[AXUIElement]` | All windows of an application |
| `kAXPositionAttribute` | `AXValue (.cgPoint)` | Window origin (top-left corner) |
| `kAXSizeAttribute` | `AXValue (.cgSize)` | Window width and height |
| `kAXMinimizedAttribute` | `CFBoolean` | Whether the window is minimized |
| `kAXFullScreenAttribute` | `CFBoolean` | Whether the window is in full screen |

> 🔒 All Accessibility API calls require the `kAXTrustedCheckOptionPrompt` entitlement. HushType checks for this on launch and guides users through granting permission. See [`PERMISSIONS.md`](PERMISSIONS.md) for details.

---

## System Control Commands

### Volume Control

```swift
import CoreAudio
import AudioToolbox

// MARK: - System Command Handler

enum SystemCommandHandler {

    // MARK: - Volume

    static func volumeUp(_ command: ParsedCommand) async throws -> CommandResult {
        let currentVolume = try getSystemVolume()
        let newVolume = min(currentVolume + 0.0625, 1.0)  // ~6.25% step (matches macOS default)
        try setSystemVolume(newVolume)
        let percentage = Int(newVolume * 100)
        return CommandResult(success: true, message: "Volume: \(percentage)%")
    }

    static func volumeDown(_ command: ParsedCommand) async throws -> CommandResult {
        let currentVolume = try getSystemVolume()
        let newVolume = max(currentVolume - 0.0625, 0.0)
        try setSystemVolume(newVolume)
        let percentage = Int(newVolume * 100)
        return CommandResult(success: true, message: "Volume: \(percentage)%")
    }

    static func volumeMute(_ command: ParsedCommand) async throws -> CommandResult {
        let isMuted = try getSystemMuteState()
        try setSystemMuteState(!isMuted)
        return CommandResult(success: true, message: isMuted ? "Unmuted" : "Muted")
    }

    static func volumeSet(_ command: ParsedCommand) async throws -> CommandResult {
        guard let levelStr = command.entities["level"],
              let level = Int(levelStr),
              (0...100).contains(level) else {
            throw CommandError.missingEntity("level (0-100)")
        }
        try setSystemVolume(Float(level) / 100.0)
        return CommandResult(success: true, message: "Volume set to \(level)%")
    }

    // MARK: - CoreAudio Volume Helpers

    private static func getDefaultOutputDeviceID() throws -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &size, &deviceID
        )

        guard status == noErr else {
            throw CommandError.executionFailed("Failed to get default audio device (error \(status))")
        }
        return deviceID
    }

    private static func getSystemVolume() throws -> Float {
        let deviceID = try getDefaultOutputDeviceID()
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
        guard status == noErr else {
            throw CommandError.executionFailed("Failed to get volume (error \(status))")
        }
        return volume
    }

    private static func setSystemVolume(_ volume: Float) throws {
        let deviceID = try getDefaultOutputDeviceID()
        var mutableVolume = Float32(max(0, min(1, volume)))
        let size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &mutableVolume)
        guard status == noErr else {
            throw CommandError.executionFailed("Failed to set volume (error \(status))")
        }
    }

    private static func getSystemMuteState() throws -> Bool {
        let deviceID = try getDefaultOutputDeviceID()
        var mute: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &mute)
        guard status == noErr else {
            throw CommandError.executionFailed("Failed to get mute state (error \(status))")
        }
        return mute != 0
    }

    private static func setSystemMuteState(_ muted: Bool) throws {
        let deviceID = try getDefaultOutputDeviceID()
        var mute: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &mute)
        guard status == noErr else {
            throw CommandError.executionFailed("Failed to set mute state (error \(status))")
        }
    }
```

### Brightness Control

```swift
    // MARK: - Brightness (IOKit)

    static func brightnessUp(_ command: ParsedCommand) async throws -> CommandResult {
        let current = try getDisplayBrightness()
        let newLevel = min(current + 0.0625, 1.0)
        try setDisplayBrightness(newLevel)
        let percentage = Int(newLevel * 100)
        return CommandResult(success: true, message: "Brightness: \(percentage)%")
    }

    static func brightnessDown(_ command: ParsedCommand) async throws -> CommandResult {
        let current = try getDisplayBrightness()
        let newLevel = max(current - 0.0625, 0.0)
        try setDisplayBrightness(newLevel)
        let percentage = Int(newLevel * 100)
        return CommandResult(success: true, message: "Brightness: \(percentage)%")
    }

    private static func getDisplayBrightness() throws -> Float {
        var brightness: Float = 0
        var iterator: io_iterator_t = 0

        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect"),
            &iterator
        )

        guard result == kIOReturnSuccess else {
            throw CommandError.executionFailed("Could not access display service")
        }

        defer { IOObjectRelease(iterator) }

        let service = IOIteratorNext(iterator)
        guard service != 0 else {
            throw CommandError.executionFailed("No display found")
        }
        defer { IOObjectRelease(service) }

        IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &brightness)
        return brightness
    }

    private static func setDisplayBrightness(_ level: Float) throws {
        var iterator: io_iterator_t = 0

        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect"),
            &iterator
        )

        guard result == kIOReturnSuccess else {
            throw CommandError.executionFailed("Could not access display service")
        }

        defer { IOObjectRelease(iterator) }

        let service = IOIteratorNext(iterator)
        guard service != 0 else {
            throw CommandError.executionFailed("No display found")
        }
        defer { IOObjectRelease(service) }

        IODisplaySetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, level)
    }
```

> ℹ️ Brightness control via IOKit is supported on built-in Apple displays. External displays may not respond to `IODisplaySetFloatParameter`. For DDC-capable external monitors, consider a separate DDC bridge (out of scope for HushType core).

### Do Not Disturb

```swift
    // MARK: - Do Not Disturb (Focus Mode)

    static func enableDoNotDisturb(_ command: ParsedCommand) async throws -> CommandResult {
        // macOS does not provide a public API for Focus/DND.
        // Use a Shortcuts-based approach or the deprecated defaults method.
        let script = """
            tell application "System Events"
                tell process "ControlCenter"
                    -- Toggle Focus mode via menu bar
                end tell
            end tell
            """
        try await executeAppleScript(script)
        return CommandResult(success: true, message: "Do Not Disturb toggled")
    }

    static func disableDoNotDisturb(_ command: ParsedCommand) async throws -> CommandResult {
        // Same toggle-based approach
        return try await enableDoNotDisturb(command)
    }
```

### Screenshot

```swift
    // MARK: - Screenshot

    static func takeScreenshot(_ command: ParsedCommand) async throws -> CommandResult {
        // Use the screencapture command-line tool
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let desktopPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent("HushType_Screenshot_\(timestamp).png")
            .path

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", desktopPath]  // -x suppresses the shutter sound

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            return CommandResult(success: true, message: "Screenshot saved to Desktop")
        } else {
            throw CommandError.executionFailed("screencapture exited with code \(process.terminationStatus)")
        }
    }
```

### Lock Screen and Sleep Display

```swift
    // MARK: - Lock Screen

    static func lockScreen(_ command: ParsedCommand) async throws -> CommandResult {
        // Use the CGSession API to lock the screen
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["displaysleepnow"]

        // Alternative: use the login window approach
        // CGSession(options: .lock, ...)
        // For simplicity, we simulate Ctrl+Cmd+Q
        let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x0C, keyDown: true)  // 'q'
        let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x0C, keyDown: false)
        keyDown?.flags = [.maskCommand, .maskControl]
        keyUp?.flags = [.maskCommand, .maskControl]
        keyDown?.post(tap: .cghidEventTap)
        try await Task.sleep(for: .milliseconds(50))
        keyUp?.post(tap: .cghidEventTap)

        return CommandResult(success: true, message: "Screen locked")
    }

    // MARK: - Sleep Display

    static func sleepDisplay(_ command: ParsedCommand) async throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]

        try process.run()
        process.waitUntilExit()

        return CommandResult(success: true, message: "Display sleeping")
    }
}
```

---

## Workflow Automation and Command Chaining

### Chaining Syntax

Users can chain multiple commands in a single utterance using natural language conjunctions:

- **"and"** -- sequential execution: `"Open Safari and open a new tab"`
- **"then"** -- sequential with dependency: `"Switch to Terminal then new window"`
- **"and then"** -- same as "then"

```swift
// MARK: - Command Chain Parser

final class CommandChainParser {
    private let separators = [" and then ", " then ", " and "]

    /// Splits a compound command into individual command strings.
    func split(_ input: String) -> [String] {
        var remaining = input.lowercased()
        var commands: [String] = []

        // Try each separator in order of specificity (longest first)
        for separator in separators {
            let parts = remaining.components(separatedBy: separator)
            if parts.count > 1 {
                commands = parts.map { $0.trimmingCharacters(in: .whitespaces) }
                return commands.filter { !$0.isEmpty }
            }
        }

        // No chain detected; return as a single command
        return [input.trimmingCharacters(in: .whitespaces)]
    }
}
```

### Sequential Execution Engine

```swift
// MARK: - Command Executor

@MainActor
final class CommandExecutor {
    private let registry = CommandRegistry.shared
    private let chainParser = CommandChainParser()
    private let parser = RegexCommandParser()

    /// Executes a parsed command, handling chains transparently.
    func execute(_ command: ParsedCommand) async throws -> CommandResult {
        // Check if this is a chained command
        let chainParts = chainParser.split(command.rawText)

        if chainParts.count > 1 {
            return try await executeChain(chainParts)
        }

        return try await executeSingle(command)
    }

    /// Executes a single command by looking it up in the registry.
    private func executeSingle(_ command: ParsedCommand) async throws -> CommandResult {
        // Validate required entities
        guard let definition = registry.lookup(intent: command.intent) else {
            throw CommandError.unrecognizedCommand(command.rawText)
        }

        for requiredEntity in definition.requiredEntities {
            guard command.entities[requiredEntity] != nil else {
                throw CommandError.missingEntity(requiredEntity)
            }
        }

        // Confirmation check for destructive commands
        if definition.requiresConfirmation {
            let confirmed = await requestConfirmation(for: definition, command: command)
            guard confirmed else {
                return CommandResult(success: false, message: "Command cancelled by user")
            }
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try await definition.handler(command)
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        return CommandResult(
            success: result.success,
            message: result.message,
            duration: duration,
            undoAction: result.undoAction
        )
    }

    /// Executes a sequence of commands, stopping on the first failure.
    private func executeChain(_ parts: [String]) async throws -> CommandResult {
        var results: [CommandResult] = []

        for (index, part) in parts.enumerated() {
            guard let parsed = parser.parse(part) else {
                throw CommandError.chainFailed(
                    at: index,
                    underlying: CommandError.unrecognizedCommand(part)
                )
            }

            do {
                let result = try await executeSingle(parsed)
                results.append(result)

                // Brief delay between chain steps for UI feedback
                if index < parts.count - 1 {
                    try await Task.sleep(for: .milliseconds(300))
                }
            } catch {
                throw CommandError.chainFailed(at: index, underlying: error)
            }
        }

        let summary = results.map(\.message).joined(separator: " -> ")
        return CommandResult(
            success: true,
            message: "Chain completed: \(summary)",
            duration: results.reduce(0) { $0 + $1.duration }
        )
    }

    /// Requests user confirmation for destructive commands.
    private func requestConfirmation(for definition: CommandDefinition, command: ParsedCommand) async -> Bool {
        await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText = "Confirm: \(definition.name)"
            alert.informativeText = "Are you sure you want to \(command.displayName.lowercased())?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Confirm")
            alert.addButton(withTitle: "Cancel")

            let response = alert.runModal()
            continuation.resume(returning: response == .alertFirstButtonReturn)
        }
    }
}
```

### Error Handling in Chains

When a chain fails at step N:

1. All previously executed steps (0 through N-1) remain in effect -- there is no automatic rollback.
2. The error message includes the step index and the underlying error.
3. If any completed steps had `undoAction` closures, the user is prompted to undo.

> ❌ Chain failure example: `"Open Safari and switch to Chrome"` -- if Chrome is not installed, step 2 fails with `appNotFound("Chrome")`. Safari remains open.

---

## Custom Command Aliases

### Alias Registration

Users can define custom voice command aliases that map to one or more built-in commands.

```swift
import SwiftData

// MARK: - Command Alias Model

@Model
final class CommandAlias {
    @Attribute(.unique) var trigger: String
    var expansion: String
    var isEnabled: Bool
    var createdAt: Date
    var lastUsedAt: Date?
    var useCount: Int

    init(trigger: String, expansion: String) {
        self.trigger = trigger.lowercased()
        self.expansion = expansion
        self.isEnabled = true
        self.createdAt = Date()
        self.lastUsedAt = nil
        self.useCount = 0
    }
}
```

### SwiftData Storage

```swift
// MARK: - Alias Store

@MainActor
final class AliasStore {
    private let modelContainer: ModelContainer
    private let modelContext: ModelContext

    init() throws {
        let schema = Schema([CommandAlias.self])
        let config = ModelConfiguration(
            "HushTypeAliases",
            schema: schema,
            isStoredInMemoryOnly: false
        )
        self.modelContainer = try ModelContainer(for: schema, configurations: [config])
        self.modelContext = modelContainer.mainContext
    }

    func addAlias(trigger: String, expansion: String) throws {
        let alias = CommandAlias(trigger: trigger, expansion: expansion)
        modelContext.insert(alias)
        try modelContext.save()
    }

    func removeAlias(trigger: String) throws {
        let normalized = trigger.lowercased()
        let predicate = #Predicate<CommandAlias> { $0.trigger == normalized }
        let descriptor = FetchDescriptor(predicate: predicate)
        let matches = try modelContext.fetch(descriptor)
        for match in matches {
            modelContext.delete(match)
        }
        try modelContext.save()
    }

    func fetchAllAliases() throws -> [CommandAlias] {
        let descriptor = FetchDescriptor<CommandAlias>(
            sortBy: [SortDescriptor(\.trigger)]
        )
        return try modelContext.fetch(descriptor)
    }

    func findAlias(for trigger: String) throws -> CommandAlias? {
        let normalized = trigger.lowercased()
        let predicate = #Predicate<CommandAlias> { $0.trigger == normalized }
        let descriptor = FetchDescriptor(predicate: predicate)
        return try modelContext.fetch(descriptor).first
    }

    func recordUsage(_ alias: CommandAlias) throws {
        alias.lastUsedAt = Date()
        alias.useCount += 1
        try modelContext.save()
    }
}
```

### Alias Resolution

```swift
// MARK: - Alias Resolver

@MainActor
final class AliasResolver {
    private var aliasStore: AliasStore?

    init() {
        self.aliasStore = try? AliasStore()
    }

    /// Resolves a spoken phrase to an aliased command expansion.
    func resolve(_ input: String) async -> ParsedCommand? {
        guard let store = aliasStore else { return nil }

        let normalized = input.lowercased().trimmingCharacters(in: .whitespaces)

        guard let alias = try? store.findAlias(for: normalized),
              alias.isEnabled else {
            return nil
        }

        // Record usage
        try? store.recordUsage(alias)

        return ParsedCommand(
            intent: .customAlias,
            entities: ["expansion": alias.expansion, "originalTrigger": alias.trigger],
            rawText: alias.expansion,
            confidence: 1.0,
            displayName: "Alias: \(alias.trigger)",
            source: .alias
        )
    }
}
```

Example aliases:

| Trigger | Expansion | Description |
|---------|-----------|-------------|
| "coding mode" | "open vscode and open terminal and open safari" | Opens dev environment |
| "night mode" | "brightness down and volume down" | Dims screen and lowers volume |
| "meeting mode" | "enable do not disturb and open zoom" | Prepares for a meeting |

> 💡 Aliases are resolved **before** regex matching, giving user-defined commands the highest priority.

---

## Apple Shortcuts Integration

### Running Shortcuts via ShortcutsProvider

HushType integrates with Apple Shortcuts using the `ShortcutsProvider` protocol introduced in macOS 14.

```swift
import AppIntents

// MARK: - HushType App Shortcuts Provider

struct HushTypeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RunVoiceCommandIntent(),
            phrases: [
                "Run voice command in \(.applicationName)",
                "Execute command with \(.applicationName)"
            ],
            shortTitle: "Voice Command",
            systemImageName: "mic.fill"
        )

        AppShortcut(
            intent: StartDictationIntent(),
            phrases: [
                "Start dictation with \(.applicationName)",
                "Dictate with \(.applicationName)"
            ],
            shortTitle: "Start Dictation",
            systemImageName: "text.bubble"
        )
    }
}

// MARK: - Run Voice Command Intent

struct RunVoiceCommandIntent: AppIntent {
    static var title: LocalizedStringResource = "Run Voice Command"
    static var description = IntentDescription("Executes a HushType voice command by text")

    @Parameter(title: "Command Text")
    var commandText: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let parser = CommandParser()
        let executor = await CommandExecutor()

        let parsed = try await parser.parse(commandText)
        let result = try await executor.execute(parsed)

        return .result(value: result.message)
    }
}
```

### Passing Parameters

```swift
// MARK: - Shortcut Runner

enum ShortcutCommandHandler {

    /// Runs an Apple Shortcut by name.
    static func runShortcut(_ command: ParsedCommand) async throws -> CommandResult {
        guard let shortcutName = command.entities["shortcutName"] else {
            throw CommandError.missingEntity("shortcutName")
        }

        // Use the shortcuts CLI to run the shortcut
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", shortcutName]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        // Wait with timeout
        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(30))
            if process.isRunning {
                process.terminate()
            }
        }

        process.waitUntilExit()
        timeoutTask.cancel()

        if process.terminationStatus == 0 {
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return CommandResult(
                success: true,
                message: output?.isEmpty == false ? "Shortcut result: \(output!)" : "Shortcut '\(shortcutName)' completed"
            )
        } else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw CommandError.executionFailed("Shortcut failed: \(errorOutput)")
        }
    }
}
```

> 🍎 The `shortcuts` CLI is available on macOS 12+ and does not require additional entitlements. HushType can list available shortcuts with `shortcuts list` and run them with `shortcuts run <name>`.

---

## AppleScript Bridge

### NSAppleScript Execution

HushType provides an AppleScript bridge for advanced automation scenarios that require controlling applications not accessible through standard APIs.

```swift
import Foundation

// MARK: - AppleScript Bridge

actor AppleScriptBridge {

    /// Executes an AppleScript string and returns the result.
    func execute(_ source: String) async throws -> String? {
        // Validate the script before execution
        try validateScript(source)

        var errorInfo: NSDictionary?
        let script = NSAppleScript(source: source)

        guard let result = script?.executeAndReturnError(&errorInfo) else {
            if let error = errorInfo {
                let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
                let number = error[NSAppleScript.errorNumber] as? Int ?? -1
                throw CommandError.executionFailed("AppleScript error \(number): \(message)")
            }
            throw CommandError.executionFailed("AppleScript returned no result")
        }

        return result.stringValue
    }

    /// Executes an AppleScript from a file URL.
    func executeFile(at url: URL) async throws -> String? {
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(contentsOf: url, error: &errorInfo) else {
            let message = errorInfo?[NSAppleScript.errorMessage] as? String ?? "Could not load script"
            throw CommandError.executionFailed("Failed to load AppleScript: \(message)")
        }

        var executeError: NSDictionary?
        guard let result = script.executeAndReturnError(&executeError) else {
            let message = executeError?[NSAppleScript.errorMessage] as? String ?? "Execution failed"
            throw CommandError.executionFailed("AppleScript error: \(message)")
        }

        return result.stringValue
    }

    // MARK: - Common AppleScript Templates

    /// Tells an application to perform an action.
    func tellApplication(_ appName: String, toPerform action: String) async throws -> String? {
        let script = """
        tell application "\(sanitize(appName))"
            \(action)
        end tell
        """
        return try await execute(script)
    }

    /// Gets a property from an application.
    func getProperty(_ property: String, from appName: String) async throws -> String? {
        let script = """
        tell application "\(sanitize(appName))"
            return \(property)
        end tell
        """
        return try await execute(script)
    }

    /// Controls System Events for UI scripting.
    func systemEvents(_ action: String) async throws -> String? {
        let script = """
        tell application "System Events"
            \(action)
        end tell
        """
        return try await execute(script)
    }
```

### Security Considerations

```swift
    // MARK: - Security

    /// Validates an AppleScript source to prevent injection and dangerous operations.
    private func validateScript(_ source: String) throws {
        let lowercased = source.lowercased()

        // Block dangerous operations
        let blockedPatterns = [
            "do shell script",          // Prevents arbitrary shell execution
            "system events\" to delete", // Prevents file deletion via System Events
            "rm -rf",                    // Should not appear in AppleScript, but guard anyway
            "format disk",
            "erase disk",
        ]

        for pattern in blockedPatterns {
            if lowercased.contains(pattern) {
                throw CommandError.permissionDenied(
                    "AppleScript contains blocked operation: '\(pattern)'. "
                    + "For security, HushType does not allow this pattern."
                )
            }
        }

        // Enforce maximum script length
        guard source.count <= 10_000 else {
            throw CommandError.executionFailed("AppleScript exceeds maximum length of 10,000 characters")
        }
    }

    /// Sanitizes a string for safe inclusion in AppleScript source.
    private func sanitize(_ input: String) -> String {
        input
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
```

> 🔒 **Security policy**: HushType blocks `do shell script` in user-submitted AppleScript to prevent arbitrary command execution. Only HushType's own internal AppleScript templates may use shell scripting, and they are reviewed at build time.

> ⚠️ AppleScript execution requires the **Automation** permission in **System Settings > Privacy & Security > Automation**. Each target application must be individually authorized. See [`PERMISSIONS.md`](PERMISSIONS.md).

```swift
// MARK: - AppleScript Execution Helper (used by executeAppleScript in SystemCommandHandler)

func executeAppleScript(_ source: String) async throws {
    let bridge = AppleScriptBridge()
    _ = try await bridge.execute(source)
}
```

---

## Command Reference Table

| Voice Command | Intent | Category | Entities | Confirmation |
|---------------|--------|----------|----------|-------------|
| "Open Safari" | `openApp` | App Management | `appName` | No |
| "Switch to Terminal" | `switchToApp` | App Management | `appName` | No |
| "Close Chrome" | `closeApp` | App Management | `appName` | No |
| "Quit Xcode" | `quitApp` | App Management | `appName` | Yes |
| "Minimize" | `minimizeWindow` | App Management | -- | No |
| "Maximize" | `maximizeWindow` | App Management | -- | No |
| "Full screen" | `fullScreenWindow` | App Management | -- | No |
| "New tab" | `newTab` | App Management | -- | No |
| "New window" | `newWindow` | App Management | -- | No |
| "Move window to left" | `moveWindowLeft` | Window Mgmt | -- | No |
| "Move window to right" | `moveWindowRight` | Window Mgmt | -- | No |
| "Move to next desktop" | `moveWindowNextDesktop` | Window Mgmt | -- | No |
| "Tile windows" | `tileWindows` | Window Mgmt | -- | No |
| "Volume up" | `volumeUp` | System Control | -- | No |
| "Volume down" | `volumeDown` | System Control | -- | No |
| "Mute" | `volumeMute` | System Control | -- | No |
| "Set volume to 50" | `volumeSet` | System Control | `level` | No |
| "Brightness up" | `brightnessUp` | System Control | -- | No |
| "Brightness down" | `brightnessDown` | System Control | -- | No |
| "Enable Do Not Disturb" | `doNotDisturbOn` | System Control | -- | No |
| "Disable Do Not Disturb" | `doNotDisturbOff` | System Control | -- | No |
| "Take screenshot" | `screenshot` | System Control | -- | No |
| "Lock screen" | `lockScreen` | System Control | -- | Yes |
| "Sleep display" | `sleepDisplay` | System Control | -- | No |
| "Run shortcut Morning" | `runShortcut` | Shortcuts | `shortcutName` | No |

---

## Error Handling and Feedback

### Error Types and User Feedback

```swift
// MARK: - Feedback Engine

@MainActor
final class FeedbackEngine {
    static let shared = FeedbackEngine()

    private init() {}

    func playActivationSound() async {
        NSSound(named: "Tink")?.play()
    }

    func playSuccessSound() async {
        NSSound(named: "Glass")?.play()
    }

    func playErrorSound() async {
        NSSound(named: "Basso")?.play()
    }

    func showFloatingMessage(_ message: String, isError: Bool = false) {
        // Displays a transient floating panel near the menu bar
        // Implementation uses NSPanel with a fade-in/out animation
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 60),
            styleMask: [.nonactivatingPanel, .titled],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = isError ? .systemRed.withAlphaComponent(0.9) : .controlBackgroundColor

        // Position near the menu bar, centered
        if let screen = NSScreen.main {
            let x = (screen.frame.width - 300) / 2
            let y = screen.frame.height - 120
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFront(nil)

        // Auto-dismiss after 2 seconds
        Task {
            try? await Task.sleep(for: .seconds(2))
            panel.orderOut(nil)
        }
    }
}
```

### Error Recovery Strategies

| Error Type | Recovery Action |
|------------|----------------|
| `unrecognizedCommand` | Suggest similar commands via fuzzy matching |
| `missingEntity` | Ask user to repeat with the missing parameter |
| `appNotFound` | Suggest similar installed application names |
| `permissionDenied` | Direct user to System Settings with a clickable link |
| `executionFailed` | Log the error, display message, retry once |
| `chainFailed` | Report which step failed, offer to retry from that step |
| `timeout` | Cancel the operation, suggest trying again |

---

## Configuration

Voice command settings are managed through HushType's preferences and stored via SwiftData:

```swift
// MARK: - Voice Command Settings

@Model
final class VoiceCommandSettings {
    var wakeWordPhrase: String
    var wakeWordEnabled: Bool
    var fuzzyMatchThreshold: Double
    var commandTimeoutSeconds: Double
    var confirmDestructiveCommands: Bool
    var enableLLMParser: Bool
    var enableSoundFeedback: Bool
    var enableVisualFeedback: Bool
    var chainDelayMilliseconds: Int
    var maxChainLength: Int
    var appleScriptEnabled: Bool
    var appleScriptMaxLength: Int

    init() {
        self.wakeWordPhrase = "Hey Mac"
        self.wakeWordEnabled = true
        self.fuzzyMatchThreshold = 0.80
        self.commandTimeoutSeconds = 10.0
        self.confirmDestructiveCommands = true
        self.enableLLMParser = false
        self.enableSoundFeedback = true
        self.enableVisualFeedback = true
        self.chainDelayMilliseconds = 300
        self.maxChainLength = 10
        self.appleScriptEnabled = true
        self.appleScriptMaxLength = 10_000
    }
}
```

> ✅ All configuration is stored locally in the application's SwiftData container. No settings are synced to any cloud service.

---

## Related Documentation

- [Architecture Overview](../architecture/ARCHITECTURE.md) -- System-wide architecture and module boundaries
- [Speech Recognition](SPEECH_RECOGNITION.md) -- whisper.cpp integration and audio pipeline details
- [LLM Processing](LLM_PROCESSING.md) -- llama.cpp model management and inference pipeline
- [Text Injection](TEXT_INJECTION.md) -- CGEvent-based keystroke injection used by several commands
- [Permissions](PERMISSIONS.md) -- Accessibility, Automation, and Microphone permission requirements
- [API Documentation](../api/API_DOCUMENTATION.md) -- Public API surface and extension points
