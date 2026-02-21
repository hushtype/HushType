# VaulType Plugin Development Guide

This guide explains how to build plugins that extend VaulType's dictation pipeline. Plugins are macOS bundles (`.bundle`) that are discovered and loaded at runtime. Two plugin types are supported: **ProcessingPlugin** for transforming transcribed text and **CommandPlugin** for adding custom voice commands.

**Current Plugin API Version: `0.5.0`**

---

## Table of Contents

1. [Overview](#overview)
2. [Plugin Architecture](#plugin-architecture)
3. [Getting Started](#getting-started)
4. [ProcessingPlugin](#processingplugin)
5. [CommandPlugin](#commandplugin)
6. [Plugin Manifest (Info.plist)](#plugin-manifest-infoplist)
7. [Installation](#installation)
8. [Testing](#testing)
9. [Best Practices](#best-practices)
10. [API Reference](#api-reference)

---

## Overview

VaulType plugins run inside the dictation pipeline on-device. They are loaded from `~/Library/Application Support/VaulType/Plugins/` at launch and managed through the Plugins tab in Settings.

### What plugins can do

| Plugin type | Role in the pipeline |
|---|---|
| `ProcessingPlugin` | Receives transcribed text, returns modified text. Runs after Whisper transcription and before text injection. |
| `CommandPlugin` | Registers natural-language patterns. When a user speaks a matching phrase, the plugin's handler executes. |

A single plugin class can conform to both `ProcessingPlugin` and `CommandPlugin` simultaneously.

### Pipeline position

```
AudioCaptureService
  → WhisperService (transcription)
    → VoicePrefixDetector
      → VocabularyService
        → CommandDetector / CommandPlugin matching  ← command plugins run here
          → LLMService
            → PluginManager.applyProcessingPlugins  ← processing plugins run here
              → OverlayWindow (optional edit)
                → TextInjectionService
                  → DictationHistory
```

---

## Plugin Architecture

### VaulTypePlugin — the base protocol

Every plugin must conform to `VaulTypePlugin`. This protocol provides identity, versioning, and lifecycle hooks.

```swift
protocol VaulTypePlugin: AnyObject {
    var identifier: String { get }        // reverse-DNS, e.g. "com.example.my-plugin"
    var displayName: String { get }       // shown in Settings → Plugins
    var version: String { get }           // semantic version of the plugin
    var apiVersion: String { get }        // must match VaulType API major version
    var pluginDescription: String { get } // optional description

    func activate() throws               // called when the plugin is turned on
    func deactivate() throws             // called when the plugin is turned off or app quits
}
```

Default implementations are provided for `apiVersion` (returns `kVaulTypePluginAPIVersion`) and `pluginDescription` (returns `""`). You only need to override them if you have specific requirements.

### Plugin types

```
VaulTypePlugin (base)
├── ProcessingPlugin  — transforms text in the dictation pipeline
└── CommandPlugin     — registers voice command patterns
```

### Lifecycle

```
Bundle file placed in Plugins/
  → PluginManager.discoverPlugins() — scans directory on launch
    → PluginManager.loadPlugin(at:) — loads bundle, instantiates principal class
      → (plugin appears in Settings UI as inactive)
        → User activates / PluginManager.activatePlugin(identifier:)
          → plugin.activate() — plugin sets up resources
            → plugin participates in the pipeline
              → User deactivates or app quits
                → plugin.deactivate() — plugin tears down resources
```

If `activate()` throws, the plugin is marked as failed and stays inactive. If `deactivate()` throws, the error is logged and removal continues regardless.

### Version compatibility

VaulType checks the **major version** of `apiVersion`. A plugin declaring `apiVersion = "0.5.0"` is compatible with any VaulType build whose `kVaulTypePluginAPIVersion` starts with `0`. A plugin with major version `1` will be rejected by a host at `0.x`.

---

## Getting Started

### Prerequisites

- Xcode 15 or later
- macOS 14.0+ deployment target
- Knowledge of Swift and macOS bundle structure

### Step 1 — Create a new macOS Bundle target in Xcode

In your Xcode project (or a standalone project):

1. **File → New → Target → macOS → Bundle**
2. Set the **product name** to your plugin name (e.g., `RemoveFillerWords`)
3. Set **deployment target** to `macOS 14.0`
4. Set the **bundle identifier** to your reverse-DNS identifier (e.g., `com.example.remove-filler-words`)

### Step 2 — Declare the principal class in Info.plist

The bundle loader finds your plugin class through the `NSPrincipalClass` key. Add it to your target's `Info.plist`:

```xml
<key>NSPrincipalClass</key>
<string>RemoveFillerWords</string>
```

Use the plain Swift class name. If your class is inside a module, use the fully qualified name: `MyModule.RemoveFillerWords`.

### Step 3 — Write the plugin class

The principal class must be an `NSObject` subclass and conform to `VaulTypePlugin`. Here is a minimal example:

```swift
import Foundation

@objc(RemoveFillerWords)
final class RemoveFillerWords: NSObject, ProcessingPlugin {

    // MARK: - VaulTypePlugin

    let identifier = "com.example.remove-filler-words"
    let displayName = "Remove Filler Words"
    let version = "1.0.0"
    let pluginDescription = "Strips 'um', 'uh', and 'like' from transcribed text."

    func activate() throws {
        // Nothing to set up for this simple plugin.
    }

    func deactivate() throws {
        // Nothing to tear down.
    }

    // MARK: - ProcessingPlugin

    func process(text: String, context: ProcessingContext) async throws -> String {
        let fillerWords = ["um", "uh", "like", "you know", "sort of"]
        var result = text
        for word in fillerWords {
            result = result.replacingOccurrences(
                of: "\\b\(word)\\b",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        // Collapse multiple spaces introduced by removals
        return result
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
```

> **Important:** The `@objc(ClassName)` attribute ensures the Objective-C runtime name matches the string in `NSPrincipalClass`. Without it, Swift name mangling can cause the bundle loader to fail.

### Step 4 — Build and install

Build the bundle target in Xcode. The output is a `.bundle` file. Copy it to:

```
~/Library/Application Support/VaulType/Plugins/RemoveFillerWords.bundle
```

Relaunch VaulType (or use Settings → Plugins → Reload). Your plugin appears in the list. Toggle it on to activate it.

---

## ProcessingPlugin

Processing plugins transform text after Whisper transcription. They are chained in priority order — the output of each plugin is passed as the input to the next.

### Protocol definition

```swift
protocol ProcessingPlugin: VaulTypePlugin {
    func process(text: String, context: ProcessingContext) async throws -> String
    var applicableModes: Set<ProcessingMode> { get }
    var priority: Int { get }
}
```

**Default values:**
- `applicableModes` — empty set (plugin applies to all modes)
- `priority` — `100`

### ProcessingContext

```swift
struct ProcessingContext: Sendable {
    let mode: ProcessingMode            // which processing mode is active
    let detectedLanguage: String?       // BCP-47 code, e.g. "en", "de" (from Whisper)
    let sourceBundleIdentifier: String? // bundle ID of the app that was frontmost
    let sourceAppName: String?          // display name of that app
    let recordingDuration: TimeInterval // how long the user recorded
}
```

Use `context` to tailor behavior — for example, applying a coding style only in Xcode, or skipping expensive processing for short recordings.

### ProcessingMode values

| Case | Display name | Description |
|---|---|---|
| `.raw` | Raw Transcription | No post-processing |
| `.clean` | Clean Text | Grammar, punctuation, filler word cleanup |
| `.structure` | Structured Output | Paragraphs, lists, headings |
| `.prompt` | Prompt Template | User-defined LLM prompt |
| `.code` | Code Mode | Source code dictation |
| `.custom` | Custom Pipeline | User-defined processing |

### Priority ordering

Lower `priority` values run first. Built-in VaulType processing runs at priority `0`. The default plugin priority is `100`. Use higher values to run after most other plugins, lower values to run before them.

```swift
// Run before all other processing plugins
var priority: Int { 10 }

// Run after all other processing plugins
var priority: Int { 900 }
```

### Error handling

If `process(text:context:)` throws, `PluginManager.applyProcessingPlugins` catches the error, logs it, and continues with the text as it was before your plugin ran. Users are not interrupted. Design your plugin to fail gracefully — return the original text rather than throw when possible.

```swift
func process(text: String, context: ProcessingContext) async throws -> String {
    guard let result = expensiveTransformation(text) else {
        return text // pass through unchanged rather than throw
    }
    return result
}
```

### Example: Auto-capitalize sentences

```swift
import Foundation

@objc(AutoCapitalizePlugin)
final class AutoCapitalizePlugin: NSObject, ProcessingPlugin {

    let identifier = "com.example.auto-capitalize"
    let displayName = "Auto-Capitalize Sentences"
    let version = "1.0.0"
    let pluginDescription = "Capitalizes the first letter of each sentence."

    func activate() throws {}
    func deactivate() throws {}

    var priority: Int { 50 }

    func process(text: String, context: ProcessingContext) async throws -> String {
        // Only run in clean and raw modes
        guard context.mode == .clean || context.mode == .raw else { return text }

        var result = ""
        var capitalizeNext = true
        for char in text {
            if capitalizeNext && char.isLetter {
                result.append(contentsOf: char.uppercased())
                capitalizeNext = false
            } else {
                result.append(char)
            }
            if ".!?".contains(char) {
                capitalizeNext = true
            }
        }
        return result
    }
}
```

### Example: Per-app translation stub

This example shows how to use `context.sourceBundleIdentifier` to apply different behavior per app:

```swift
import Foundation

@objc(ConditionalFormatterPlugin)
final class ConditionalFormatterPlugin: NSObject, ProcessingPlugin {

    let identifier = "com.example.conditional-formatter"
    let displayName = "Conditional Formatter"
    let version = "1.0.0"

    func activate() throws {}
    func deactivate() throws {}

    // Only apply in raw and clean modes
    var applicableModes: Set<ProcessingMode> { [.raw, .clean] }

    func process(text: String, context: ProcessingContext) async throws -> String {
        // Apply bullet formatting when dictating into Notes
        if context.sourceBundleIdentifier == "com.apple.Notes" {
            return text
                .components(separatedBy: ",")
                .map { "- " + $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n")
        }
        return text
    }
}
```

---

## CommandPlugin

Command plugins register natural-language patterns. When a user speaks a phrase that matches one of your patterns, VaulType calls your handler instead of injecting text.

### Protocol definition

```swift
protocol CommandPlugin: VaulTypePlugin {
    var commands: [PluginCommand] { get }
}
```

### PluginCommand

```swift
struct PluginCommand: Sendable {
    let name: String                        // internal identifier
    let patterns: [String]                  // spoken phrases that trigger this command
    let description: String                 // shown in Settings → Commands
    let handler: @Sendable ([String: String]) async -> PluginCommandResult
}
```

**Pattern matching:** Patterns are matched case-insensitively. The first pattern that matches the spoken text wins. Patterns are plain strings, not regular expressions. For example, the pattern `"open terminal"` matches any spoken phrase containing exactly those words.

**Entities:** The `entities` dictionary passed to the handler contains key-value pairs extracted from the spoken command. The current extraction mechanism is simple prefix/suffix stripping — complex entity extraction is left to the handler.

### PluginCommandResult

```swift
struct PluginCommandResult: Sendable {
    let success: Bool
    let message: String

    // Convenience constructors:
    static func success(_ message: String = "OK") -> PluginCommandResult
    static func failure(_ message: String) -> PluginCommandResult
}
```

A `success` result triggers the success sound feedback. A `failure` result triggers the error sound and logs the message.

### Example: App launcher plugin

```swift
import Foundation
import AppKit

@objc(AppLauncherPlugin)
final class AppLauncherPlugin: NSObject, CommandPlugin {

    let identifier = "com.example.app-launcher"
    let displayName = "Quick App Launcher"
    let version = "1.0.0"
    let pluginDescription = "Opens frequently used apps by voice."

    func activate() throws {}
    func deactivate() throws {}

    var commands: [PluginCommand] {
        [
            PluginCommand(
                name: "open-simulator",
                patterns: ["open simulator", "launch simulator", "open iOS simulator"],
                description: "Open Xcode Simulator",
                handler: { _ in
                    let url = URL(fileURLWithPath:
                        "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app"
                    )
                    let config = NSWorkspace.OpenConfiguration()
                    do {
                        try await NSWorkspace.shared.openApplication(at: url, configuration: config)
                        return .success("Simulator launched")
                    } catch {
                        return .failure("Could not open Simulator: \(error.localizedDescription)")
                    }
                }
            ),
            PluginCommand(
                name: "open-activity-monitor",
                patterns: ["open activity monitor", "show activity monitor"],
                description: "Open Activity Monitor",
                handler: { _ in
                    let url = URL(fileURLWithPath:
                        "/System/Applications/Utilities/Activity Monitor.app"
                    )
                    let config = NSWorkspace.OpenConfiguration()
                    do {
                        try await NSWorkspace.shared.openApplication(at: url, configuration: config)
                        return .success("Activity Monitor launched")
                    } catch {
                        return .failure("Could not open Activity Monitor: \(error.localizedDescription)")
                    }
                }
            )
        ]
    }
}
```

### Example: Shell command plugin

```swift
import Foundation

@objc(ShellCommandPlugin)
final class ShellCommandPlugin: NSObject, CommandPlugin {

    let identifier = "com.example.shell-runner"
    let displayName = "Shell Runner"
    let version = "1.0.0"
    let pluginDescription = "Runs predefined shell scripts by voice."

    private var scriptsDirectory: URL?

    func activate() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent("VaulTypeScripts")
        // Create directory if needed
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        scriptsDirectory = dir
    }

    func deactivate() throws {
        scriptsDirectory = nil
    }

    var commands: [PluginCommand] {
        [
            PluginCommand(
                name: "run-build-script",
                patterns: ["build project", "run build", "start build"],
                description: "Run ~/VaulTypeScripts/build.sh",
                handler: { [weak self] _ in
                    guard let dir = self?.scriptsDirectory else {
                        return .failure("Plugin not activated")
                    }
                    let script = dir.appendingPathComponent("build.sh")
                    guard FileManager.default.fileExists(atPath: script.path) else {
                        return .failure("build.sh not found in ~/VaulTypeScripts/")
                    }
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/bin/sh")
                    process.arguments = [script.path]
                    do {
                        try process.run()
                        process.waitUntilExit()
                        return process.terminationStatus == 0
                            ? .success("Build script completed")
                            : .failure("Build script exited with status \(process.terminationStatus)")
                    } catch {
                        return .failure("Failed to run script: \(error.localizedDescription)")
                    }
                }
            )
        ]
    }
}
```

---

## Plugin Manifest (Info.plist)

Every plugin bundle requires a valid `Info.plist`. The minimum required keys are:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Required: the Objective-C class name of your principal class -->
    <key>NSPrincipalClass</key>
    <string>RemoveFillerWords</string>

    <!-- Required: matches your plugin's 'identifier' property -->
    <key>CFBundleIdentifier</key>
    <string>com.example.remove-filler-words</string>

    <!-- Required: matches your plugin's 'version' property -->
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>

    <!-- Required: bundle type for a loadable bundle -->
    <key>CFBundlePackageType</key>
    <string>BNDL</string>

    <!-- Required -->
    <key>CFBundleExecutable</key>
    <string>RemoveFillerWords</string>
</dict>
</plist>
```

### Recommended additional keys

```xml
    <!-- Human-readable name (can differ from NSPrincipalClass) -->
    <key>CFBundleName</key>
    <string>Remove Filler Words</string>

    <!-- Short description shown in UI if pluginDescription is empty -->
    <key>CFBundleGetInfoString</key>
    <string>Strips filler words from dictated text.</string>

    <!-- Minimum macOS version -->
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
```

### Versioning

Use [Semantic Versioning](https://semver.org/) for both your plugin (`version` property / `CFBundleShortVersionString`) and your declared `apiVersion`. VaulType validates only the **major** component of `apiVersion`. A plugin at API `0.5.0` and a VaulType host at `0.9.0` are compatible. A plugin at API `1.0.0` is not compatible with a `0.x` host.

---

## Installation

### Plugin directory

Place your `.bundle` file in:

```
~/Library/Application Support/VaulType/Plugins/
```

VaulType creates this directory automatically on first launch. You can also create it manually:

```bash
mkdir -p "$HOME/Library/Application Support/VaulType/Plugins"
```

### Discovery rules

`PluginManager.discoverPlugins()` runs at app launch and:

1. Reads all entries in the Plugins directory.
2. Filters for files with the `.bundle` extension.
3. Loads each bundle, instantiates the principal class, and checks version compatibility.
4. Skips bundles that fail to load (logged to Console.app under subsystem `com.vaultype.app`).
5. Rejects bundles with a duplicate `identifier` (only the first one found is loaded).

### Reloading without restarting

VaulType does not support hot-reload of plugins. To pick up changes to an existing plugin:

1. Quit VaulType.
2. Replace the `.bundle` file.
3. Relaunch VaulType.

### Per-user vs. system-wide installation

Only the per-user directory (`~/Library/…`) is currently supported. System-wide installation (`/Library/Application Support/VaulType/Plugins/`) is not scanned.

### Uninstalling a plugin

1. Deactivate the plugin in Settings → Plugins.
2. Quit VaulType.
3. Delete the `.bundle` file from the Plugins directory.

---

## Testing

### Unit testing your plugin logic

Because `ProcessingPlugin.process` and `CommandPlugin` handlers are plain Swift functions, you can unit test them directly without running VaulType:

```swift
import XCTest

final class RemoveFillerWordsTests: XCTestCase {

    let plugin = RemoveFillerWords()

    func testFillerWordRemoval() async throws {
        let context = ProcessingContext(
            mode: .clean,
            detectedLanguage: "en",
            sourceBundleIdentifier: nil,
            sourceAppName: nil,
            recordingDuration: 3.0
        )
        let input = "Um, I think this is, like, a great idea."
        let output = try await plugin.process(text: input, context: context)
        XCTAssertFalse(output.contains("Um"))
        XCTAssertFalse(output.contains("like"))
        XCTAssertTrue(output.contains("great idea"))
    }

    func testActivateDeactivate() throws {
        XCTAssertNoThrow(try plugin.activate())
        XCTAssertNoThrow(try plugin.deactivate())
    }
}
```

### Integration testing with PluginManager

You can instantiate `PluginManager` in tests and use `loadPlugin(at:)` to load a pre-built bundle:

```swift
import XCTest

final class PluginIntegrationTests: XCTestCase {

    func testPluginLoadsAndActivates() throws {
        let manager = PluginManager()
        let bundleURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("RemoveFillerWords.bundle")

        // Load the bundle
        try manager.loadPlugin(at: bundleURL)
        XCTAssertEqual(manager.loadedPlugins.count, 1)

        // Activate it
        try manager.activatePlugin(identifier: "com.example.remove-filler-words")
        XCTAssertTrue(manager.isActive(identifier: "com.example.remove-filler-words"))
        XCTAssertEqual(manager.activeProcessingPlugins.count, 1)
    }
}
```

### Manual testing workflow

1. Build your plugin bundle in Xcode (Product → Build, or `xcodebuild -scheme MyPlugin`).
2. Copy the `.bundle` to `~/Library/Application Support/VaulType/Plugins/`.
3. Relaunch VaulType.
4. Open Settings → Plugins and verify your plugin appears in the list.
5. Activate the plugin.
6. Trigger a dictation and verify the output.
7. Check Console.app for any error messages from subsystem `com.vaultype.app`.

### Debugging

Plugin errors are logged to the system log. To view them:

```bash
log stream --predicate 'subsystem == "com.vaultype.app"' --level debug
```

Or open Console.app and filter by subsystem `com.vaultype.app`.

---

## Best Practices

### Performance

Processing plugins run synchronously in the dictation pipeline. The user waits for all active processing plugins before text is injected.

- Keep `process(text:context:)` fast. Target under 100 ms for typical inputs.
- Use `applicableModes` to skip modes where your plugin does not apply. An empty set runs in all modes; a specific set avoids unnecessary work.
- Avoid blocking network calls inside `process`. If you need a remote service, fetch asynchronously in the background and cache results.
- Cache expensive resources (compiled regular expressions, loaded models) in `activate()` rather than re-creating them per call.

```swift
private var fillerPattern: NSRegularExpression?

func activate() throws {
    // Compile once at activation, reuse in process()
    fillerPattern = try NSRegularExpression(
        pattern: "\\b(um|uh|like|you know)\\b",
        options: [.caseInsensitive]
    )
}

func process(text: String, context: ProcessingContext) async throws -> String {
    guard let pattern = fillerPattern else { return text }
    let range = NSRange(text.startIndex..., in: text)
    return pattern.stringByReplacingMatches(in: text, range: range, withTemplate: "")
}
```

### Error handling

- Prefer returning the original text over throwing from `process`. Throwing causes the error to be logged, but the pipeline continues with the unchanged input. Throwing is appropriate only when the input is genuinely unusable.
- In `activate()`, throw `PluginError.activationFailed` if a required resource cannot be set up (missing file, permission denied, etc.). VaulType will mark the plugin as inactive.
- In command handlers, always return a `PluginCommandResult` — do not throw. Wrap any thrown errors:

```swift
handler: { entities in
    do {
        try someRiskyOperation()
        return .success()
    } catch {
        return .failure(error.localizedDescription)
    }
}
```

### Thread safety

- `process(text:context:)` is called from a non-main background queue. Do not access `@MainActor`-isolated state directly.
- Command handlers are marked `@Sendable` and called asynchronously. Capture plugin state only through `[weak self]` or value types.
- If your plugin maintains mutable state accessed from multiple calls, protect it with a lock or serial `DispatchQueue`.

```swift
private let lock = NSLock()
private var requestCount = 0

func process(text: String, context: ProcessingContext) async throws -> String {
    lock.withLock { requestCount += 1 }
    // ...
}
```

### Privacy considerations

- VaulType is privacy-first. Plugins run on-device. Do not exfiltrate transcribed text to remote servers without explicit user consent and clear disclosure.
- If your plugin makes network requests, document this clearly in `pluginDescription` and your plugin's own documentation.
- Transcribed text may contain sensitive information. Avoid logging full transcriptions; log only diagnostic summaries.
- Do not store transcriptions on disk without user knowledge.

### Resource cleanup

Always pair resources created in `activate()` with cleanup in `deactivate()`. VaulType calls `deactivate()` when the user disables the plugin, when a new plugin version is installed, and when the app quits.

```swift
private var observation: NSObjectProtocol?

func activate() throws {
    observation = NotificationCenter.default.addObserver(
        forName: .NSWorkspaceDidActivateApplication,
        object: nil,
        queue: .main
    ) { [weak self] note in
        self?.handleAppSwitch(note)
    }
}

func deactivate() throws {
    if let obs = observation {
        NotificationCenter.default.removeObserver(obs)
        observation = nil
    }
}
```

### Identifier uniqueness

Use a reverse-DNS identifier that you control, e.g. `com.yourname.plugin-name`. Duplicate identifiers are rejected at load time — the first bundle wins. Two plugins with the same identifier cannot coexist.

---

## API Reference

### VaulTypePlugin

```swift
/// Current plugin API version. Plugins must declare a compatible version.
let kVaulTypePluginAPIVersion = "0.5.0"

protocol VaulTypePlugin: AnyObject {
    /// Reverse-DNS identifier unique to this plugin (e.g., "com.example.my-plugin").
    var identifier: String { get }

    /// Human-readable name shown in the plugin manager UI.
    var displayName: String { get }

    /// Semantic version of this plugin (e.g., "1.0.0").
    var version: String { get }

    /// Plugin API version this plugin was built against.
    /// Must match `kVaulTypePluginAPIVersion` major version to load.
    /// Default implementation returns `kVaulTypePluginAPIVersion`.
    var apiVersion: String { get }

    /// Optional description shown in the plugin manager.
    /// Default implementation returns "".
    var pluginDescription: String { get }

    /// Called when the plugin is activated. Set up resources here.
    /// - Throws: `PluginError.activationFailed` if setup fails.
    func activate() throws

    /// Called when the plugin is deactivated. Clean up resources here.
    /// - Throws: `PluginError.deactivationFailed` if teardown fails.
    func deactivate() throws
}
```

### ProcessingPlugin

```swift
protocol ProcessingPlugin: VaulTypePlugin {
    /// Transform text in the dictation pipeline.
    /// - Parameters:
    ///   - text: Input text (raw transcription or output from previous plugin).
    ///   - context: Metadata about the current dictation session.
    /// - Returns: Transformed text to pass to the next stage.
    /// - Throws: If processing fails. The pipeline will use the input text as fallback.
    func process(text: String, context: ProcessingContext) async throws -> String

    /// Processing modes this plugin applies to. Empty means all modes.
    /// Default implementation returns [].
    var applicableModes: Set<ProcessingMode> { get }

    /// Priority for ordering among multiple active processing plugins.
    /// Lower values run first. Default implementation returns 100.
    var priority: Int { get }
}
```

### ProcessingContext

```swift
struct ProcessingContext: Sendable {
    /// The processing mode selected for this dictation.
    let mode: ProcessingMode

    /// BCP-47 language code detected by Whisper (e.g., "en", "de").
    let detectedLanguage: String?

    /// Bundle identifier of the app that was active when recording started.
    let sourceBundleIdentifier: String?

    /// Name of the app that was active when recording started.
    let sourceAppName: String?

    /// Duration of the audio recording in seconds.
    let recordingDuration: TimeInterval
}
```

### ProcessingMode

```swift
enum ProcessingMode: String, Codable, CaseIterable, Identifiable {
    case raw       // Unprocessed Whisper output
    case clean     // Grammar, punctuation, filler word cleanup
    case structure // Paragraphs, lists, headings
    case prompt    // User-defined LLM prompt template
    case code      // Source code dictation
    case custom    // User-defined processing pipeline
}
```

### CommandPlugin

```swift
protocol CommandPlugin: VaulTypePlugin {
    /// The voice commands this plugin provides.
    var commands: [PluginCommand] { get }
}
```

### PluginCommand

```swift
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
    /// - Returns: Result indicating success or failure and a message.
    let handler: @Sendable ([String: String]) async -> PluginCommandResult
}
```

### PluginCommandResult

```swift
struct PluginCommandResult: Sendable {
    let success: Bool
    let message: String

    /// Convenience constructor for successful results.
    static func success(_ message: String = "OK") -> PluginCommandResult

    /// Convenience constructor for failure results.
    static func failure(_ message: String) -> PluginCommandResult
}
```

### PluginError

```swift
enum PluginError: LocalizedError {
    /// Bundle could not be loaded from disk.
    case loadFailed(path: String, reason: String)

    /// Plugin's activate() failed.
    case activationFailed(identifier: String, reason: String)

    /// Plugin's deactivate() failed.
    case deactivationFailed(identifier: String, reason: String)

    /// Plugin's apiVersion major component does not match VaulType's.
    case incompatibleVersion(identifier: String, required: String, found: String)

    /// A plugin with this identifier is already registered.
    case duplicateIdentifier(String)

    /// No loaded plugin matches the given identifier.
    case notFound(identifier: String)
}
```

### PluginManager

```swift
@Observable
final class PluginManager {
    /// All successfully loaded plugins (active and inactive).
    private(set) var loadedPlugins: [any VaulTypePlugin]

    /// Active processing plugins, sorted by priority (lower = runs first).
    private(set) var activeProcessingPlugins: [any ProcessingPlugin]

    /// Active command plugins.
    private(set) var activeCommandPlugins: [any CommandPlugin]

    /// Creates the Plugins directory if it does not exist.
    func ensurePluginsDirectory()

    /// Scans the Plugins directory and loads all .bundle files found.
    func discoverPlugins()

    /// Loads a single plugin bundle and registers it.
    /// - Throws: PluginError.loadFailed, .incompatibleVersion, .duplicateIdentifier
    func loadPlugin(at url: URL) throws

    /// Activates a loaded plugin by identifier.
    /// - Throws: PluginError.notFound, or any error from plugin.activate()
    func activatePlugin(identifier: String) throws

    /// Deactivates an active plugin by identifier.
    /// - Throws: PluginError.notFound, or any error from plugin.deactivate()
    func deactivatePlugin(identifier: String) throws

    /// Removes a plugin. Deactivates first if active.
    /// - Throws: PluginError.notFound, or any error from deactivatePlugin
    func removePlugin(identifier: String) throws

    /// Deactivates and unloads all plugins.
    func deactivateAll()

    /// Returns true if the plugin is currently in the active processing or command list.
    func isActive(identifier: String) -> Bool

    /// Applies all active processing plugins to text in priority order.
    /// Failed plugins are skipped; their input text is passed to the next plugin.
    func applyProcessingPlugins(text: String, context: ProcessingContext) async throws -> String
}
```

---

*VaulType Plugin API v0.5.0 — for VaulType v0.5.0-alpha and later.*
