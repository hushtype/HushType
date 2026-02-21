Last Updated: 2026-02-13

# Development Guide

> Comprehensive guide for developing, extending, and maintaining VaulType.

## Table of Contents

- [Project Structure](#project-structure)
- [Swift Package Organization](#swift-package-organization)
- [C/C++ Bridging Conventions](#cc-bridging-conventions)
- [Naming Conventions](#naming-conventions)
- [Git Workflow](#git-workflow)
- [How to Add a New Processing Mode](#how-to-add-a-new-processing-mode)
- [How to Add a New Voice Command](#how-to-add-a-new-voice-command)
- [How to Integrate a New Model Format](#how-to-integrate-a-new-model-format)
- [Testing Strategy](#testing-strategy)
- [Performance Profiling](#performance-profiling)
- [Memory Leak Detection](#memory-leak-detection)
- [Next Steps](#next-steps)

---

## Project Structure

```
VaulType/
├── VaulType.xcodeproj           # Xcode project file
├── VaulType/                    # Main app target
│   ├── App/
│   │   ├── VaulTypeApp.swift    # @main entry point
│   │   ├── AppDelegate.swift    # NSApplicationDelegate (menu bar, lifecycle)
│   │   └── MenuBarManager.swift # Menu bar icon and dropdown management
│   ├── Views/
│   │   ├── Settings/
│   │   │   ├── SettingsView.swift        # Root settings window
│   │   │   ├── GeneralSettingsTab.swift  # Launch at login, hotkey, etc.
│   │   │   ├── AudioSettingsTab.swift    # Input device, noise gate
│   │   │   ├── ModelsSettingsTab.swift   # Model download/management
│   │   │   ├── ModesSettingsTab.swift    # Processing mode configuration
│   │   │   └── AdvancedSettingsTab.swift # Injection method, diagnostics
│   │   ├── Overlay/
│   │   │   ├── OverlayWindow.swift       # NSPanel for floating overlay
│   │   │   └── OverlayView.swift         # SwiftUI overlay content
│   │   └── Components/
│   │       ├── AudioLevelIndicator.swift # Real-time audio level meter
│   │       ├── ModelDownloadRow.swift    # Model download progress UI
│   │       └── ModeSelector.swift       # Processing mode picker
│   ├── Services/
│   │   ├── Audio/
│   │   │   ├── AudioCaptureService.swift # AVAudioEngine management
│   │   │   └── VoiceActivityDetector.swift # VAD implementation
│   │   ├── Speech/
│   │   │   ├── WhisperService.swift      # whisper.cpp Swift wrapper
│   │   │   └── WhisperContext.swift      # whisper_context lifecycle
│   │   ├── LLM/
│   │   │   ├── LLMService.swift          # llama.cpp Swift wrapper
│   │   │   ├── LlamaContext.swift        # llama_context lifecycle
│   │   │   ├── OllamaService.swift       # Ollama REST API client
│   │   │   └── PromptTemplateEngine.swift # Template variable substitution
│   │   ├── Injection/
│   │   │   ├── TextInjectionService.swift # CGEvent + clipboard injection
│   │   │   └── ClipboardManager.swift     # Clipboard save/restore
│   │   ├── Commands/
│   │   │   ├── CommandParser.swift        # Natural language → command
│   │   │   ├── CommandRegistry.swift      # Built-in command definitions
│   │   │   └── CommandExecutor.swift      # Execute parsed commands
│   │   ├── HotkeyManager.swift           # Global hotkey registration
│   │   ├── ModelManager.swift            # Model download/storage
│   │   └── AppContextService.swift       # Active app detection
│   ├── Models/
│   │   ├── DictationEntry.swift          # SwiftData: dictation history
│   │   ├── PromptTemplate.swift          # SwiftData: prompt templates
│   │   ├── AppProfile.swift              # SwiftData: per-app config
│   │   ├── VocabularyEntry.swift         # SwiftData: custom vocabulary
│   │   └── ModelInfo.swift               # SwiftData: installed models
│   ├── Utilities/
│   │   ├── Constants.swift               # App-wide constants
│   │   ├── Logger+Extensions.swift       # os_log category helpers
│   │   └── Permissions.swift             # Permission check helpers
│   └── Resources/
│       ├── Assets.xcassets               # App icon, menu bar icons
│       ├── Entitlements.plist            # Accessibility, microphone
│       ├── Info.plist                    # App configuration
│       └── PromptTemplates/             # Built-in .json prompt templates
│           ├── clean.json
│           ├── structure.json
│           ├── prompt.json
│           └── code.json
├── WhisperKit/                          # whisper.cpp bridging module
│   ├── include/
│   │   └── whisper-bridging-header.h    # C bridging header
│   ├── Sources/
│   │   └── WhisperWrapper.swift         # High-level Swift API
│   └── Package.swift
├── LlamaKit/                            # llama.cpp bridging module
│   ├── include/
│   │   └── llama-bridging-header.h      # C bridging header
│   ├── Sources/
│   │   └── LlamaWrapper.swift           # High-level Swift API
│   └── Package.swift
├── VaulTypeTests/                       # Unit tests
│   ├── Services/
│   │   ├── CommandParserTests.swift
│   │   ├── PromptTemplateEngineTests.swift
│   │   └── TextInjectionTests.swift
│   └── Models/
│       └── SwiftDataModelTests.swift
├── VaulTypeUITests/                     # UI tests
│   ├── SettingsUITests.swift
│   └── OverlayUITests.swift
├── scripts/
│   ├── build-deps.sh                   # Build whisper.cpp + llama.cpp
│   ├── download-model.sh               # CLI model downloader
│   ├── create-dmg.sh                   # DMG packaging
│   └── notarize.sh                     # Notarization script
└── docs/                               # Documentation (this folder)
```

## Swift Package Organization

VaulType uses Swift Package Manager (SPM) for dependency management alongside the Xcode project.

### Local Packages

```
Package.swift (root)
├── WhisperKit            # Local package wrapping whisper.cpp
├── LlamaKit              # Local package wrapping llama.cpp
└── VaulTypeCore          # Shared models and utilities (future)
```

### External Dependencies

Add dependencies in `Package.swift` or via Xcode's package resolution:

```swift
// Package.swift
let package = Package(
    name: "VaulType",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(
            name: "VaulType",
            dependencies: ["Sparkle", "WhisperKit", "LlamaKit"]
        ),
    ]
)
```

### Adding a New Package

1. Add the dependency to `Package.swift` or via Xcode > File > Add Package Dependencies
2. Import the module in the relevant source files
3. Document the dependency in [TECH_STACK.md](../architecture/TECH_STACK.md)
4. Verify license compatibility (see [LEGAL_COMPLIANCE.md](../security/LEGAL_COMPLIANCE.md))

---

## C/C++ Bridging Conventions

VaulType bridges to whisper.cpp and llama.cpp via C interop. Follow these conventions:

### Bridging Header Structure

```c
// WhisperKit/include/whisper-bridging-header.h

#ifndef WhisperBridgingHeader_h
#define WhisperBridgingHeader_h

// Include the whisper.cpp public API
#include "whisper.h"

// Any additional C helper functions
// Keep these minimal — prefer Swift wrappers
int whisper_helper_get_segment_count(struct whisper_context *ctx);

#endif
```

### Swift Wrapper Pattern

Always wrap raw C API calls in a Swift class that manages memory:

```swift
// WhisperKit/Sources/WhisperWrapper.swift

import Foundation

final class WhisperContext: @unchecked Sendable {
    private let context: OpaquePointer

    init(modelPath: String) throws {
        var params = whisper_context_default_params()
        params.use_gpu = true  // Metal acceleration

        guard let ctx = whisper_init_from_file_with_params(modelPath, params) else {
            throw WhisperError.modelLoadFailed(path: modelPath)
        }
        self.context = ctx
    }

    deinit {
        whisper_free(context)
    }

    func transcribe(audioData: [Float], language: String? = nil) async throws -> String {
        // Always dispatch to a background queue — never block the main thread
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
                params.n_threads = Int32(ProcessInfo.processInfo.activeProcessorCount)
                params.language = language.map { ($0 as NSString).utf8String! }

                let result = whisper_full(self.context, params, audioData, Int32(audioData.count))

                if result == 0 {
                    let text = self.collectSegments()
                    continuation.resume(returning: text)
                } else {
                    continuation.resume(throwing: WhisperError.transcriptionFailed(code: result))
                }
            }
        }
    }

    private func collectSegments() -> String {
        let segmentCount = whisper_full_n_segments(context)
        var result = ""
        for i in 0..<segmentCount {
            if let text = whisper_full_get_segment_text(context, i) {
                result += String(cString: text)
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

### Conventions

| Rule | Details |
|------|---------|
| Memory management | Always pair `_init` with `_free` in `init`/`deinit` |
| Threading | Never call C APIs on the main thread |
| Error handling | Map C error codes to Swift `Error` types |
| Naming | Swift wrappers use `Context` suffix (e.g., `WhisperContext`, `LlamaContext`) |
| Sendable | Mark as `@unchecked Sendable` if the C context is thread-safe |
| Bridging headers | One per C library, kept minimal |

---

## Naming Conventions

VaulType follows the [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/) with these project-specific rules:

### Files

| Type | Convention | Example |
|------|-----------|---------|
| SwiftUI View | `PascalCase` + `View` suffix | `SettingsView.swift` |
| Service | `PascalCase` + `Service` suffix | `AudioCaptureService.swift` |
| SwiftData Model | `PascalCase`, noun | `DictationEntry.swift` |
| Extension | `Type+Feature.swift` | `Logger+Extensions.swift` |
| Protocol | Adjective or `-able`/`-ible` | `Transcribable.swift` |
| Test | `TestedType` + `Tests` suffix | `CommandParserTests.swift` |

### Code

```swift
// Types: PascalCase
struct DictationEntry { }
enum ProcessingMode { }
protocol AudioCapturing { }

// Properties and methods: camelCase
let currentMode: ProcessingMode
func startRecording() async throws

// Constants: camelCase (not UPPER_SNAKE)
let maxAudioBufferSize = 16_000 * 30  // 30 seconds at 16kHz

// Enum cases: camelCase
enum ProcessingMode: String, Codable {
    case raw
    case clean
    case structure
    case prompt
    case code
    case custom
}

// Boolean properties: use `is`, `has`, `should` prefix
var isRecording: Bool
var hasModelLoaded: Bool
var shouldAutoInject: Bool
```

### os_log Categories

```swift
// Use subsystem + category pattern
import os

extension Logger {
    static let audio = Logger(subsystem: "com.vaultype.app", category: "audio")
    static let whisper = Logger(subsystem: "com.vaultype.app", category: "whisper")
    static let llm = Logger(subsystem: "com.vaultype.app", category: "llm")
    static let injection = Logger(subsystem: "com.vaultype.app", category: "injection")
    static let commands = Logger(subsystem: "com.vaultype.app", category: "commands")
    static let ui = Logger(subsystem: "com.vaultype.app", category: "ui")
}
```

---

## Git Workflow

VaulType uses **trunk-based development** with short-lived feature branches.

### Branch Naming

```
main                    # Always deployable
feature/add-code-mode   # New features
fix/clipboard-restore   # Bug fixes
chore/update-whisper    # Dependency updates, maintenance
docs/setup-guide        # Documentation changes
```

### Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add Structure processing mode
fix: clipboard not restored after paste injection
perf: preload Whisper model on app launch
docs: update API documentation for LLMService
chore: bump whisper.cpp to v1.7.3
test: add CommandParser unit tests
refactor: extract PromptTemplateEngine from LLMService
```

### Workflow

1. Create a feature branch from `main`
2. Make changes with focused, atomic commits
3. Run tests locally: `xcodebuild test -scheme VaulType`
4. Push and create a pull request
5. CI runs tests and linting
6. Code review and approval
7. Squash-merge to `main`
8. Delete feature branch

### Tags and Releases

```bash
# Tag a release
git tag -a v0.1.0 -m "MVP: Menu bar + whisper.cpp + text injection"
git push origin v0.1.0
# CI automatically builds, signs, notarizes, and creates a GitHub Release
```

---

## How to Add a New Processing Mode

Processing modes transform raw Whisper output through the LLM pipeline. Here's how to add one:

### Step 1: Define the Mode

Add a new case to the `ProcessingMode` enum:

```swift
// VaulType/Models/ProcessingMode.swift

enum ProcessingMode: String, Codable, CaseIterable, Identifiable {
    case raw
    case clean
    case structure
    case prompt
    case code
    case custom
    case email  // <-- New mode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        // ...existing cases...
        case .email: return "Email"
        }
    }

    var description: String {
        switch self {
        // ...existing cases...
        case .email: return "Format dictation as a professional email"
        }
    }

    var icon: String {
        switch self {
        // ...existing cases...
        case .email: return "envelope"
        }
    }
}
```

### Step 2: Create the Prompt Template

Create a JSON template file:

```json
// VaulType/Resources/PromptTemplates/email.json
{
    "name": "Email",
    "mode": "email",
    "systemPrompt": "You are a writing assistant that formats dictated speech into professional emails. Maintain the sender's intent and tone while improving clarity and structure.",
    "userPromptTemplate": "Format the following dictated text as a professional email. Add appropriate greeting and sign-off if not present. Fix grammar and punctuation.\n\nDictated text: {text}\n\nApp context: {app_name}\nLanguage: {language}",
    "isBuiltIn": true
}
```

### Step 3: Register in LLMService

```swift
// VaulType/Services/LLM/LLMService.swift

func process(text: String, mode: ProcessingMode, context: AppContext) async throws -> String {
    switch mode {
    case .raw:
        return text
    // ...existing cases...
    case .email:
        let template = try loadTemplate(for: .email)
        return try await runInference(text: text, template: template, context: context)
    }
}
```

### Step 4: Add Tests

```swift
// VaulTypeTests/Services/LLMServiceTests.swift

func testEmailModeFormatsAsEmail() async throws {
    let service = LLMService(model: mockModel)
    let result = try await service.process(
        text: "hey john wanted to follow up on yesterdays meeting about the project timeline",
        mode: .email,
        context: .default
    )
    XCTAssertTrue(result.contains("Hi") || result.contains("Dear") || result.contains("Hello"))
}
```

### Step 5: Update UI

The mode selector automatically picks up new `CaseIterable` cases. Verify it appears correctly in Settings > Modes tab.

---

## How to Add a New Voice Command

### Step 1: Define the Command

```swift
// VaulType/Services/Commands/CommandRegistry.swift

struct CommandDefinition {
    let name: String
    let patterns: [String]  // Regex patterns to match
    let handler: (CommandContext) async throws -> Void
}

extension CommandRegistry {
    static func registerBuiltinCommands() {
        // Existing commands...

        register(CommandDefinition(
            name: "screenshot",
            patterns: [
                "take a screenshot",
                "screenshot",
                "capture screen",
                "take screen capture"
            ],
            handler: { context in
                try await ScreenshotCommand.execute(context: context)
            }
        ))
    }
}
```

### Step 2: Implement the Handler

```swift
// VaulType/Services/Commands/Handlers/ScreenshotCommand.swift

enum ScreenshotCommand {
    static func execute(context: CommandContext) async throws {
        // Simulate Cmd+Shift+3 for full screenshot
        let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: 0x14,  // '3' key
            keyDown: true
        )
        event?.flags = [.maskCommand, .maskShift]
        event?.post(tap: .cghidEventTap)

        // Key up
        let eventUp = CGEvent(
            keyboardEventSource: nil,
            virtualKey: 0x14,
            keyDown: false
        )
        eventUp?.post(tap: .cghidEventTap)

        Logger.commands.info("Screenshot command executed")
    }
}
```

### Step 3: Add Tests

```swift
// VaulTypeTests/Services/CommandParserTests.swift

func testScreenshotCommandParsing() throws {
    let parser = CommandParser()
    let result = try parser.parse("take a screenshot")
    XCTAssertEqual(result?.name, "screenshot")
}

func testScreenshotVariations() throws {
    let parser = CommandParser()
    let variations = ["screenshot", "take a screenshot", "capture screen"]
    for phrase in variations {
        let result = try parser.parse(phrase)
        XCTAssertEqual(result?.name, "screenshot", "Failed to parse: \(phrase)")
    }
}
```

---

## How to Integrate a New Model Format

To support a new model format beyond GGML (Whisper) and GGUF (LLM):

### Step 1: Add a Model Type

```swift
// VaulType/Models/ModelInfo.swift

enum ModelFormat: String, Codable {
    case ggml    // Whisper models
    case gguf    // LLM models (llama.cpp)
    case coreml  // <-- New: Core ML models
}
```

### Step 2: Create an Inference Adapter

```swift
// VaulType/Services/Speech/CoreMLWhisperService.swift

protocol TranscriptionService {
    func transcribe(audioData: [Float], language: String?) async throws -> String
}

final class CoreMLWhisperService: TranscriptionService {
    private let model: MLModel

    init(modelPath: String) throws {
        let compiledURL = try MLModel.compileModel(at: URL(fileURLWithPath: modelPath))
        self.model = try MLModel(contentsOf: compiledURL)
    }

    func transcribe(audioData: [Float], language: String?) async throws -> String {
        // Core ML inference implementation
        // ...
    }
}
```

### Step 3: Update ModelManager

```swift
// VaulType/Services/ModelManager.swift

func loadModel(info: ModelInfo) throws -> Any {
    switch info.format {
    case .ggml:
        return try WhisperContext(modelPath: info.localPath)
    case .gguf:
        return try LlamaContext(modelPath: info.localPath)
    case .coreml:
        return try CoreMLWhisperService(modelPath: info.localPath)
    }
}
```

---

## Testing Strategy

### Test Pyramid

```
        ╱  UI Tests  ╲       ← Fewest: critical user flows
       ╱───────────────╲
      ╱ Integration Tests╲   ← Middle: service interactions
     ╱─────────────────────╲
    ╱     Unit Tests         ╲ ← Most: pure logic, parsers, templates
   ╱───────────────────────────╲
```

### Unit Tests

Focus on pure logic that doesn't require hardware or models:

```swift
// CommandParser, PromptTemplateEngine, text processing
func testCleanModeRemovesFillerWords() {
    let engine = TextProcessor()
    let result = engine.removeFillers("so um I think we should uh proceed")
    XCTAssertEqual(result, "I think we should proceed")
}
```

### Integration Tests

Test whisper.cpp and llama.cpp Swift wrappers with small models:

```swift
// Requires a test model in the test bundle
func testWhisperTranscribesAudio() async throws {
    let whisper = try WhisperContext(modelPath: testModelPath)
    let audio = try loadTestAudio("hello_world.wav")
    let result = try await whisper.transcribe(audioData: audio)
    XCTAssertTrue(result.lowercased().contains("hello"))
}
```

### UI Tests

Test SwiftUI settings and overlay with XCUITest:

```swift
func testSettingsWindowOpens() {
    let app = XCUIApplication()
    app.launch()
    // Click menu bar icon, then Settings
    app.menuBarItems["VaulType"].click()
    app.menuItems["Settings..."].click()
    XCTAssertTrue(app.windows["Settings"].waitForExistence(timeout: 3))
}
```

### Mock Audio Input

For testing the audio pipeline without a real microphone:

```swift
final class MockAudioCaptureService: AudioCapturing {
    var mockAudioData: [Float] = []

    func startCapture() async throws {
        // Simulate audio callback with mock data
        delegate?.audioCaptureService(self, didCaptureAudio: mockAudioData)
    }
}
```

> See [TESTING.md](../testing/TESTING.md) for the complete testing guide.

---

## Performance Profiling

### Using Instruments

1. **Product > Profile** (⌘I) in Xcode
2. Choose the relevant template:

| Template | Use For |
|----------|---------|
| Time Profiler | Finding CPU hotspots during inference |
| Allocations | Tracking memory usage for model loading |
| Leaks | Detecting memory leaks in C bridging code |
| Metal System Trace | GPU utilization for whisper.cpp/llama.cpp |
| Energy Log | Battery impact during dictation |

### Key Metrics to Monitor

```
┌────────────────────────┬───────────────┬───────────────┐
│ Metric                 │ Target        │ Alert         │
├────────────────────────┼───────────────┼───────────────┤
│ Idle memory            │ <50 MB        │ >100 MB       │
│ Whisper model loaded   │ <500 MB       │ >1 GB         │
│ Whisper + LLM loaded   │ <2 GB         │ >3 GB         │
│ Transcription latency  │ <2s (5s clip) │ >5s           │
│ LLM processing         │ <3s           │ >8s           │
│ Text injection          │ <100ms        │ >500ms        │
│ Idle CPU               │ ~0%           │ >2%           │
│ App launch time        │ <1s           │ >3s           │
└────────────────────────┴───────────────┴───────────────┘
```

### Profiling Whisper Inference

```swift
import os

let signpost = OSSignposter(subsystem: "com.vaultype.app", category: "whisper")

func transcribe(audio: [Float]) async throws -> String {
    let state = signpost.beginInterval("transcription", id: signpost.makeSignpostID())
    defer { signpost.endInterval("transcription", state) }

    return try await whisperContext.transcribe(audioData: audio)
}
```

View in Instruments > os_signpost to see exact timing per transcription.

---

## Memory Leak Detection

C bridging code is the most common source of memory leaks. Follow these practices:

### Use Instruments Leaks Template

1. Run with the Leaks template in Instruments
2. Perform several dictation cycles
3. Check for leaked `whisper_context` or `llama_context` objects

### RAII Pattern for C Resources

```swift
// Always pair init/free in a class with deinit
final class WhisperContext {
    private let ctx: OpaquePointer

    init(path: String) throws {
        guard let ctx = whisper_init_from_file(path) else {
            throw WhisperError.loadFailed
        }
        self.ctx = ctx
    }

    deinit {
        whisper_free(ctx)  // ALWAYS free in deinit
    }
}
```

### Detecting Retain Cycles

SwiftUI closures and Combine publishers can create retain cycles:

```swift
// BAD: retain cycle in Combine sink
cancellable = audioService.audioLevelPublisher
    .sink { self.updateLevel($0) }  // Strong capture of self

// GOOD: weak capture
cancellable = audioService.audioLevelPublisher
    .sink { [weak self] level in
        self?.updateLevel(level)
    }
```

### Memory Debugging Flags

Add to Xcode scheme > Run > Arguments > Environment Variables:

```
MallocStackLogging = 1
MallocScribble = 1
ASAN_OPTIONS = detect_leaks=1
```

---

## Next Steps

- [Setup Guide](SETUP_GUIDE.md) — Set up your development environment
- [Testing Guide](../testing/TESTING.md) — Detailed testing practices
- [Architecture](../architecture/ARCHITECTURE.md) — System architecture deep dive
- [Contributing](../contributing/CONTRIBUTING.md) — How to contribute to VaulType
- [API Documentation](../api/API_DOCUMENTATION.md) — Internal API reference
