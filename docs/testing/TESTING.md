Last Updated: 2026-02-13

# Testing Guide

> Testing strategy, patterns, and tools for a macOS native app with local ML inference.

## Table of Contents

- [Overview](#overview)
- [Test Pyramid](#test-pyramid)
- [Unit Tests](#unit-tests)
- [Integration Tests](#integration-tests)
- [UI Tests](#ui-tests)
- [Audio Pipeline Testing](#audio-pipeline-testing)
- [Text Injection Testing](#text-injection-testing)
- [Performance Benchmarking](#performance-benchmarking)
- [Model Accuracy Regression](#model-accuracy-regression)
- [Accessibility Testing](#accessibility-testing)
- [CI Test Configuration](#ci-test-configuration)
- [Test Data Management](#test-data-management)
- [Next Steps](#next-steps)

---

## Overview

Testing a macOS app that integrates local ML inference (whisper.cpp, llama.cpp), audio hardware, and system-level APIs (CGEvent, Accessibility) requires a layered approach. Not everything can be tested in CI — some tests require real hardware and user permissions.

```
┌─────────────────────────────────────────────────────────────┐
│                    HushType Test Layers                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────────────────────────────────────────┐     │
│  │              Manual / Exploratory                     │     │
│  │   Permission flows, real microphone, app compat      │     │
│  └─────────────────────────────────────────────────────┘     │
│  ┌─────────────────────────────────────────────────────┐     │
│  │              UI Tests (XCUITest)                       │     │
│  │   Settings UI, overlay window, menu bar              │     │
│  └─────────────────────────────────────────────────────┘     │
│  ┌─────────────────────────────────────────────────────┐     │
│  │           Integration Tests                           │     │
│  │   Whisper wrapper, LLM wrapper, audio pipeline       │     │
│  └─────────────────────────────────────────────────────┘     │
│  ┌─────────────────────────────────────────────────────┐     │
│  │              Unit Tests                                │     │
│  │   CommandParser, PromptEngine, TextProcessor,         │     │
│  │   ModelManager, VocabularyMatcher, ClipboardManager   │     │
│  └─────────────────────────────────────────────────────┘     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Test Plans

HushType uses Xcode Test Plans to organize tests:

| Test Plan | Contains | Runs In CI |
|-----------|----------|------------|
| `UnitTests` | All unit tests | Yes |
| `IntegrationTests` | Whisper/LLM wrapper tests | Yes (with test models) |
| `UITests` | XCUITest suite | Yes |
| `PerformanceTests` | Benchmark tests | Nightly only |
| `AllTests` | Everything | Local only |

---

## Test Pyramid

```
           ╱ Manual ╲           5%  — Permission flows, hardware
          ╱───────────╲
         ╱  UI Tests    ╲       10% — Settings, overlay, menu bar
        ╱─────────────────╲
       ╱ Integration Tests  ╲   25% — ML wrappers, audio, injection
      ╱───────────────────────╲
     ╱       Unit Tests         ╲ 60% — Parsers, engines, logic
    ╱─────────────────────────────╲
```

### Guidelines

- **Unit tests** should cover all pure logic: command parsing, prompt template rendering, text processing, model metadata, vocabulary matching
- **Integration tests** verify C bridging layers work correctly with real (tiny) models
- **UI tests** cover critical user flows in the Settings window and overlay
- **Manual tests** are reserved for hardware-dependent features (real microphone, permission prompts, text injection into third-party apps)

---

## Unit Tests

### Command Parser

```swift
// HushTypeTests/Services/CommandParserTests.swift

import XCTest
@testable import HushType

final class CommandParserTests: XCTestCase {

    var parser: CommandParser!

    override func setUp() {
        parser = CommandParser()
        CommandRegistry.registerBuiltinCommands(on: parser)
    }

    // MARK: - App Launch Commands

    func testParseOpenApp() throws {
        let command = try parser.parse("open Safari")
        XCTAssertEqual(command?.name, "open_app")
        XCTAssertEqual(command?.parameters["appName"] as? String, "Safari")
    }

    func testParseOpenAppCaseInsensitive() throws {
        let command = try parser.parse("OPEN safari")
        XCTAssertEqual(command?.name, "open_app")
    }

    func testParseOpenAppWithArticle() throws {
        let command = try parser.parse("open the terminal")
        XCTAssertEqual(command?.parameters["appName"] as? String, "terminal")
    }

    // MARK: - Window Management

    func testParseSnapLeft() throws {
        let phrases = ["move window to left half", "snap left", "left half"]
        for phrase in phrases {
            let command = try parser.parse(phrase)
            XCTAssertEqual(command?.name, "snap_window", "Failed: \(phrase)")
            XCTAssertEqual(command?.parameters["direction"] as? String, "left")
        }
    }

    // MARK: - System Controls

    func testParseVolumeUp() throws {
        let command = try parser.parse("volume up")
        XCTAssertEqual(command?.name, "volume")
        XCTAssertEqual(command?.parameters["action"] as? String, "up")
    }

    // MARK: - Non-Commands

    func testNonCommandReturnsNil() throws {
        let command = try parser.parse("hello world this is a dictation")
        XCTAssertNil(command)
    }

    func testEmptyStringReturnsNil() throws {
        let command = try parser.parse("")
        XCTAssertNil(command)
    }
}
```

### Prompt Template Engine

```swift
// HushTypeTests/Services/PromptTemplateEngineTests.swift

import XCTest
@testable import HushType

final class PromptTemplateEngineTests: XCTestCase {

    var engine: PromptTemplateEngine!

    override func setUp() {
        engine = PromptTemplateEngine()
    }

    func testBasicVariableSubstitution() {
        let template = "Fix grammar: {text}"
        let result = engine.render(template, variables: ["text": "this is test"])
        XCTAssertEqual(result, "Fix grammar: this is test")
    }

    func testMultipleVariables() {
        let template = "Language: {language}. App: {app_name}. Text: {text}"
        let result = engine.render(template, variables: [
            "language": "English",
            "app_name": "Terminal",
            "text": "hello world"
        ])
        XCTAssertEqual(result, "Language: English. App: Terminal. Text: hello world")
    }

    func testMissingVariableLeftAsIs() {
        let template = "Text: {text}. Context: {context}"
        let result = engine.render(template, variables: ["text": "hello"])
        XCTAssertEqual(result, "Text: hello. Context: {context}")
    }

    func testEmptyTemplate() {
        let result = engine.render("", variables: ["text": "hello"])
        XCTAssertEqual(result, "")
    }

    func testSpecialCharactersInValues() {
        let template = "Process: {text}"
        let result = engine.render(template, variables: [
            "text": "func main() { print(\"hello\") }"
        ])
        XCTAssertTrue(result.contains("func main()"))
    }

    // MARK: - Built-in Template Loading

    func testLoadCleanModeTemplate() throws {
        let template = try engine.loadBuiltInTemplate(for: .clean)
        XCTAssertFalse(template.systemPrompt.isEmpty)
        XCTAssertTrue(template.userPromptTemplate.contains("{text}"))
    }

    func testAllBuiltInTemplatesLoadable() throws {
        for mode in ProcessingMode.allCases where mode != .raw && mode != .custom {
            let template = try engine.loadBuiltInTemplate(for: mode)
            XCTAssertFalse(template.systemPrompt.isEmpty, "Empty system prompt for \(mode)")
            XCTAssertTrue(template.userPromptTemplate.contains("{text}"),
                         "Missing {text} variable for \(mode)")
        }
    }
}
```

### Text Processor

```swift
// HushTypeTests/Services/TextProcessorTests.swift

import XCTest
@testable import HushType

final class TextProcessorTests: XCTestCase {

    func testRemoveFillerWords() {
        let processor = TextProcessor()
        let input = "so um I think we should uh proceed with the plan"
        let result = processor.removeFillers(input)
        XCTAssertEqual(result, "I think we should proceed with the plan")
    }

    func testNormalizeWhitespace() {
        let processor = TextProcessor()
        let input = "hello    world   test"
        let result = processor.normalizeWhitespace(input)
        XCTAssertEqual(result, "hello world test")
    }

    func testApplyVocabularyReplacements() {
        let processor = TextProcessor()
        let replacements = [
            VocabularyEntry(spoken: "react", replacement: "React"),
            VocabularyEntry(spoken: "typescript", replacement: "TypeScript"),
        ]
        let input = "I'm working with react and typescript"
        let result = processor.applyVocabulary(input, entries: replacements)
        XCTAssertEqual(result, "I'm working with React and TypeScript")
    }

    func testHandleUnicodeText() {
        let processor = TextProcessor()
        let input = "Türkçe metin ve emojiler 🎉"
        let result = processor.normalizeWhitespace(input)
        XCTAssertEqual(result, "Türkçe metin ve emojiler 🎉")
    }
}
```

### Vocabulary Matcher

```swift
// HushTypeTests/Models/VocabularyMatcherTests.swift

import XCTest
@testable import HushType

final class VocabularyMatcherTests: XCTestCase {

    func testExactMatch() {
        let matcher = VocabularyMatcher(entries: [
            VocabularyEntry(spoken: "x code", replacement: "Xcode")
        ])
        XCTAssertEqual(matcher.apply("open x code"), "open Xcode")
    }

    func testCaseInsensitiveMatch() {
        let matcher = VocabularyMatcher(entries: [
            VocabularyEntry(spoken: "swift ui", replacement: "SwiftUI")
        ])
        XCTAssertEqual(matcher.apply("I love Swift UI"), "I love SwiftUI")
    }

    func testNoMatchLeavesUnchanged() {
        let matcher = VocabularyMatcher(entries: [
            VocabularyEntry(spoken: "react", replacement: "React")
        ])
        XCTAssertEqual(matcher.apply("hello world"), "hello world")
    }
}
```

---

## Integration Tests

Integration tests require compiled whisper.cpp/llama.cpp libraries and test models.

### Whisper Wrapper Tests

```swift
// HushTypeTests/Integration/WhisperServiceTests.swift

import XCTest
@testable import HushType

final class WhisperServiceTests: XCTestCase {

    static let testModelPath = Bundle(for: WhisperServiceTests.self)
        .path(forResource: "ggml-tiny", ofType: "bin")!

    var whisperContext: WhisperContext!

    override func setUpWithError() throws {
        whisperContext = try WhisperContext(modelPath: Self.testModelPath)
    }

    override func tearDown() {
        whisperContext = nil  // Triggers deinit → whisper_free
    }

    func testTranscribeHelloWorld() async throws {
        let audio = try loadWavFile("hello_world_en")
        let result = try await whisperContext.transcribe(audioData: audio)
        XCTAssertTrue(
            result.lowercased().contains("hello"),
            "Expected 'hello' in: \(result)"
        )
    }

    func testTranscribeSilenceReturnsEmpty() async throws {
        let silence = [Float](repeating: 0.0, count: 16000 * 2)  // 2 seconds
        let result = try await whisperContext.transcribe(audioData: silence)
        XCTAssertTrue(result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testTranscribeWithLanguageHint() async throws {
        let audio = try loadWavFile("merhaba_tr")
        let result = try await whisperContext.transcribe(audioData: audio, language: "tr")
        XCTAssertFalse(result.isEmpty)
    }

    func testModelInfoAvailable() {
        XCTAssertFalse(whisperContext.modelType.isEmpty)
    }

    // MARK: - Helpers

    private func loadWavFile(_ name: String) throws -> [Float] {
        let bundle = Bundle(for: Self.self)
        guard let url = bundle.url(forResource: name, withExtension: "wav") else {
            throw XCTSkip("Test audio file \(name).wav not found in test bundle")
        }
        return try AudioFileLoader.loadAsFloat32(url: url, sampleRate: 16000)
    }
}
```

### LLM Wrapper Tests

```swift
// HushTypeTests/Integration/LLMServiceTests.swift

import XCTest
@testable import HushType

final class LLMServiceTests: XCTestCase {

    static let testModelPath = Bundle(for: LLMServiceTests.self)
        .path(forResource: "test-model-q4", ofType: "gguf")

    var llamaContext: LlamaContext?

    override func setUpWithError() throws {
        guard let path = Self.testModelPath else {
            throw XCTSkip("Test LLM model not available")
        }
        llamaContext = try LlamaContext(modelPath: path, contextSize: 512)
    }

    override func tearDown() {
        llamaContext = nil
    }

    func testGenerateResponse() async throws {
        guard let ctx = llamaContext else { throw XCTSkip("No model") }
        let result = try await ctx.generate(
            prompt: "Fix the grammar: 'she go to store yesterday'",
            maxTokens: 64,
            temperature: 0.1
        )
        XCTAssertFalse(result.isEmpty)
    }

    func testEmptyPromptThrows() async {
        guard let ctx = llamaContext else { return }
        do {
            _ = try await ctx.generate(prompt: "", maxTokens: 10)
            XCTFail("Expected error for empty prompt")
        } catch {
            // Expected
        }
    }

    func testTokenCounting() throws {
        guard let ctx = llamaContext else { throw XCTSkip("No model") }
        let count = ctx.tokenCount(for: "Hello, world!")
        XCTAssertGreaterThan(count, 0)
        XCTAssertLessThan(count, 20)
    }
}
```

---

## UI Tests

### Settings Window

```swift
// HushTypeUITests/SettingsUITests.swift

import XCTest

final class SettingsUITests: XCTestCase {

    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--ui-testing"]
        app.launch()
    }

    func testSettingsWindowOpens() {
        openSettings()
        XCTAssertTrue(app.windows["Settings"].waitForExistence(timeout: 3))
    }

    func testSettingsTabNavigation() {
        openSettings()
        let window = app.windows["Settings"]

        let tabs = ["General", "Audio", "Models", "Modes", "Advanced"]
        for tab in tabs {
            window.toolbars.buttons[tab].click()
            XCTAssertTrue(
                window.groups[tab].waitForExistence(timeout: 2),
                "Tab '\(tab)' content not visible"
            )
        }
    }

    func testHotkeyFieldAcceptsInput() {
        openSettings()
        let window = app.windows["Settings"]
        window.toolbars.buttons["General"].click()

        let hotkeyField = window.textFields["hotkeyField"]
        XCTAssertTrue(hotkeyField.exists)
    }

    func testAudioDeviceSelector() {
        openSettings()
        let window = app.windows["Settings"]
        window.toolbars.buttons["Audio"].click()

        let devicePicker = window.popUpButtons["audioDevicePicker"]
        XCTAssertTrue(devicePicker.exists)
        XCTAssertGreaterThan(devicePicker.menuItems.count, 0)
    }

    // MARK: - Helpers

    private func openSettings() {
        // Click menu bar item → Settings
        app.menuBarItems["HushType"].click()
        app.menuItems["Settings..."].click()
    }
}
```

### Overlay Window

```swift
// HushTypeUITests/OverlayUITests.swift

import XCTest

final class OverlayUITests: XCTestCase {

    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--ui-testing", "--show-overlay"]
        app.launch()
    }

    func testOverlayShowsText() {
        let overlay = app.windows["DictationOverlay"]
        XCTAssertTrue(overlay.waitForExistence(timeout: 5))

        let textView = overlay.textViews["overlayText"]
        XCTAssertTrue(textView.exists)
    }

    func testOverlayDismissOnCancel() {
        let overlay = app.windows["DictationOverlay"]
        guard overlay.waitForExistence(timeout: 5) else { return }

        overlay.buttons["cancelButton"].click()
        XCTAssertFalse(overlay.exists)
    }

    func testOverlayModeIndicator() {
        let overlay = app.windows["DictationOverlay"]
        guard overlay.waitForExistence(timeout: 5) else { return }

        let modeLabel = overlay.staticTexts["modeIndicator"]
        XCTAssertTrue(modeLabel.exists)
        XCTAssertFalse(modeLabel.label.isEmpty)
    }
}
```

---

## Audio Pipeline Testing

Since CI runners don't have physical microphones, use mock audio input:

### Mock Audio Service

```swift
// HushTypeTests/Mocks/MockAudioCaptureService.swift

import Foundation
@testable import HushType

final class MockAudioCaptureService: AudioCapturing {
    weak var delegate: AudioCaptureDelegate?

    var isCapturing = false
    var mockAudioFile: URL?
    var mockSilence = false

    func startCapture() async throws {
        isCapturing = true

        if mockSilence {
            let silence = [Float](repeating: 0.0, count: 16000 * 3)
            delegate?.audioCaptureService(self, didCaptureAudio: silence)
            return
        }

        if let fileURL = mockAudioFile {
            let audioData = try AudioFileLoader.loadAsFloat32(url: fileURL, sampleRate: 16000)
            delegate?.audioCaptureService(self, didCaptureAudio: audioData)
        }
    }

    func stopCapture() {
        isCapturing = false
        delegate?.audioCaptureServiceDidStopCapture(self)
    }

    func setInputDevice(_ device: AudioDevice) { }
}
```

### Audio Pipeline Integration Test

```swift
// HushTypeTests/Integration/AudioPipelineTests.swift

import XCTest
@testable import HushType

final class AudioPipelineTests: XCTestCase {

    func testFullPipelineWithMockAudio() async throws {
        let audioService = MockAudioCaptureService()
        audioService.mockAudioFile = testAudioURL("hello_world_en")

        let whisper = try WhisperContext(modelPath: testModelPath)
        let pipeline = DictationPipeline(
            audioService: audioService,
            whisperService: whisper,
            llmService: nil,  // Raw mode, no LLM
            mode: .raw
        )

        let result = try await pipeline.captureAndTranscribe()
        XCTAssertTrue(result.lowercased().contains("hello"))
    }
}
```

---

## Text Injection Testing

Text injection testing is challenging in CI because CGEvent requires Accessibility permissions. Use a layered approach:

### Unit Test — Injection Logic

```swift
// HushTypeTests/Services/TextInjectionServiceTests.swift

import XCTest
@testable import HushType

final class TextInjectionServiceTests: XCTestCase {

    func testPrefersCGEventForShortText() {
        let service = TextInjectionService()
        let method = service.selectInjectionMethod(for: "Hello world", preference: .auto)
        XCTAssertEqual(method, .cgEvent)
    }

    func testPrefersClipboardForLongText() {
        let service = TextInjectionService()
        let longText = String(repeating: "A", count: 500)
        let method = service.selectInjectionMethod(for: longText, preference: .auto)
        XCTAssertEqual(method, .clipboard)
    }

    func testClipboardPreservation() async throws {
        let manager = ClipboardManager()

        // Set known clipboard contents
        let originalContent = "original clipboard content"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(originalContent, forType: .string)

        // Simulate clipboard injection
        try await manager.preserveAndRestore {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("injected text", forType: .string)
        }

        // Verify original restored
        let restored = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(restored, originalContent)
    }

    func testUnicodeTextPreparation() {
        let service = TextInjectionService()
        let text = "Merhaba dünya! 🌍 Ñoño naïve"
        let prepared = service.prepareForInjection(text)
        XCTAssertEqual(prepared, text)  // Should not mangle Unicode
    }

    func testSpecialCharacterEscaping() {
        let service = TextInjectionService()
        let text = "func test() { print(\"hello\") }"
        let prepared = service.prepareForInjection(text)
        XCTAssertTrue(prepared.contains("\""))
    }
}
```

### Manual Test Checklist — Text Injection

| App | CGEvent | Clipboard | Notes |
|-----|---------|-----------|-------|
| TextEdit | Test short text | Test long text | Baseline app |
| Terminal.app | Test commands | Test multiline | Watch for escaping |
| iTerm2 | Test commands | Test multiline | May need different timing |
| VS Code | Test in editor | Test in terminal | Electron app |
| Safari | Test in URL bar | Test in text field | Browser input |
| Slack | Test in message | Test in thread | Electron app |
| Notes.app | Test formatting | Test paste | Native app |

---

## Performance Benchmarking

```swift
// HushTypeTests/Performance/TranscriptionBenchmarkTests.swift

import XCTest
@testable import HushType

final class TranscriptionBenchmarkTests: XCTestCase {

    func testWhisperTinyLatency() throws {
        let whisper = try WhisperContext(modelPath: tinyModelPath)
        let audio = try loadWavFile("5_second_speech")

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            let expectation = expectation(description: "transcription")
            Task {
                _ = try await whisper.transcribe(audioData: audio)
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 30)
        }
    }

    func testWhisperSmallLatency() throws {
        guard let path = smallModelPath else { throw XCTSkip("Small model not available") }
        let whisper = try WhisperContext(modelPath: path)
        let audio = try loadWavFile("5_second_speech")

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            let expectation = expectation(description: "transcription")
            Task {
                _ = try await whisper.transcribe(audioData: audio)
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 60)
        }
    }

    func testModelLoadTime() throws {
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            _ = try? WhisperContext(modelPath: tinyModelPath)
        }
    }
}
```

### Performance Baselines

Stored in `TestResults/baselines.json` and tracked across commits:

```json
{
    "whisper-tiny-5s-transcription": {
        "M1": { "avg_ms": 450, "max_ms": 700, "memory_mb": 120 },
        "M2": { "avg_ms": 380, "max_ms": 550, "memory_mb": 120 },
        "M3": { "avg_ms": 320, "max_ms": 450, "memory_mb": 120 }
    },
    "whisper-small-5s-transcription": {
        "M1": { "avg_ms": 1200, "max_ms": 1800, "memory_mb": 480 },
        "M2": { "avg_ms": 950, "max_ms": 1400, "memory_mb": 480 }
    }
}
```

---

## Model Accuracy Regression

Prevent regressions when updating whisper.cpp or llama.cpp versions.

### Accuracy Test Suite

```swift
// HushTypeTests/Accuracy/WhisperAccuracyTests.swift

import XCTest
@testable import HushType

final class WhisperAccuracyTests: XCTestCase {

    struct TestCase {
        let audioFile: String
        let expectedText: String
        let language: String
        let minSimilarity: Double  // Word Error Rate threshold
    }

    let testCases: [TestCase] = [
        TestCase(audioFile: "the_quick_brown_fox", expectedText: "The quick brown fox jumps over the lazy dog", language: "en", minSimilarity: 0.90),
        TestCase(audioFile: "hello_world_en", expectedText: "Hello world", language: "en", minSimilarity: 0.95),
        TestCase(audioFile: "numbers_1_to_10", expectedText: "one two three four five six seven eight nine ten", language: "en", minSimilarity: 0.85),
        TestCase(audioFile: "technical_terms", expectedText: "SwiftUI uses declarative syntax with property wrappers", language: "en", minSimilarity: 0.80),
    ]

    func testAccuracyRegression() async throws {
        let whisper = try WhisperContext(modelPath: smallModelPath)

        for testCase in testCases {
            let audio = try loadWavFile(testCase.audioFile)
            let result = try await whisper.transcribe(audioData: audio, language: testCase.language)

            let similarity = wordSimilarity(expected: testCase.expectedText, actual: result)
            XCTAssertGreaterThanOrEqual(
                similarity,
                testCase.minSimilarity,
                "Accuracy regression for '\(testCase.audioFile)': expected ≥\(testCase.minSimilarity), got \(similarity). Result: '\(result)'"
            )
        }
    }

    private func wordSimilarity(expected: String, actual: String) -> Double {
        let expectedWords = Set(expected.lowercased().split(separator: " "))
        let actualWords = Set(actual.lowercased().split(separator: " "))
        let intersection = expectedWords.intersection(actualWords)
        return Double(intersection.count) / Double(expectedWords.count)
    }
}
```

---

## Accessibility Testing

### Automated Accessibility Audit

```swift
// HushTypeUITests/AccessibilityTests.swift

import XCTest

final class AccessibilityTests: XCTestCase {

    let app = XCUIApplication()

    override func setUp() {
        app.launchArguments = ["--ui-testing"]
        app.launch()
    }

    func testSettingsElementsHaveAccessibilityLabels() {
        openSettings()
        let window = app.windows["Settings"]

        // All buttons should have accessibility labels
        for button in window.buttons.allElementsBoundByIndex {
            XCTAssertFalse(
                button.label.isEmpty,
                "Button missing accessibility label: \(button.debugDescription)"
            )
        }

        // All text fields should have accessibility labels
        for field in window.textFields.allElementsBoundByIndex {
            XCTAssertFalse(
                field.label.isEmpty,
                "Text field missing accessibility label: \(field.debugDescription)"
            )
        }
    }

    func testSettingsKeyboardNavigation() {
        openSettings()
        let window = app.windows["Settings"]

        // Tab through all focusable elements
        var focusedElements: [String] = []
        for _ in 0..<20 {
            XCUIElement.perform(withKeyModifiers: [], block: {
                app.typeKey(.tab, modifierFlags: [])
            })
            if let focused = app.windows.firstMatch.focusedElement {
                focusedElements.append(focused.label)
            }
        }

        XCTAssertGreaterThan(focusedElements.count, 3,
                            "Too few focusable elements — keyboard navigation may be broken")
    }

    func testVoiceOverLabels() {
        openSettings()
        let window = app.windows["Settings"]

        // Key controls must have VoiceOver descriptions
        let criticalElements = [
            "hotkeyField",
            "audioDevicePicker",
            "modelSelector",
            "modeSelector"
        ]

        for identifier in criticalElements {
            let element = window.descendants(matching: .any)[identifier]
            if element.exists {
                XCTAssertFalse(
                    element.label.isEmpty,
                    "'\(identifier)' is missing VoiceOver label"
                )
            }
        }
    }

    private func openSettings() {
        app.menuBarItems["HushType"].click()
        app.menuItems["Settings..."].click()
    }
}
```

### Manual Accessibility Checklist

- [ ] Enable VoiceOver (⌘F5) and navigate the settings window
- [ ] All controls are reachable via Tab key
- [ ] All controls announce their purpose in VoiceOver
- [ ] High contrast mode doesn't hide any UI elements
- [ ] Dynamic Type (if applicable) doesn't break layout
- [ ] Overlay window is readable with VoiceOver
- [ ] Menu bar icon is accessible to VoiceOver

---

## CI Test Configuration

### Xcode Test Plans

Create test plans in Xcode: Product > Test Plan > New Test Plan.

**UnitTests.xctestplan:**
```json
{
    "configurations": [{
        "name": "Unit Tests",
        "options": {
            "targetForVariableExpansion": { "containerPath": "HushType.xcodeproj", "identifier": "HushTypeTests" }
        }
    }],
    "defaultOptions": {
        "testTimeoutsEnabled": true,
        "defaultTestExecutionTimeAllowance": 30
    },
    "testTargets": [{
        "target": { "containerPath": "HushType.xcodeproj", "identifier": "HushTypeTests" },
        "skippedTests": ["Integration/", "Performance/", "Accuracy/"]
    }]
}
```

### Running Tests in CI

```bash
# Unit tests only (fast, no models needed)
xcodebuild test \
    -project HushType.xcodeproj \
    -scheme HushType \
    -testPlan UnitTests \
    -destination "platform=macOS,arch=arm64" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO

# Integration tests (requires test models)
xcodebuild test \
    -project HushType.xcodeproj \
    -scheme HushType \
    -testPlan IntegrationTests \
    -destination "platform=macOS,arch=arm64" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO
```

---

## Test Data Management

### Test Audio Files

Store test audio in `HushTypeTests/Resources/Audio/`:

```
HushTypeTests/Resources/Audio/
├── hello_world_en.wav       # 2s, 16kHz, mono, English
├── merhaba_tr.wav           # 2s, 16kHz, mono, Turkish
├── the_quick_brown_fox.wav  # 5s, 16kHz, mono, English
├── numbers_1_to_10.wav      # 5s, 16kHz, mono, English
├── technical_terms.wav      # 5s, 16kHz, mono, English
├── 5_second_speech.wav      # 5s, 16kHz, mono, English (benchmark)
└── silence.wav              # 3s, 16kHz, mono, silence
```

> ⚠️ **Warning:** Audio files can be large. Use Git LFS for test audio files.

```bash
# Set up Git LFS for audio
git lfs track "*.wav"
git lfs track "*.bin"  # Model files
git lfs track "*.gguf"
```

### Test Models

Store tiny models in `HushTypeTests/Resources/Models/`:
- `ggml-tiny.bin` — ~75MB Whisper tiny model
- `test-model-q4.gguf` — Small quantized LLM for tests

> 💡 **Tip:** CI downloads test models as a cached step rather than storing them in the repo.

---

## Next Steps

- [Development Guide](../getting-started/DEVELOPMENT_GUIDE.md) — How to add features and write tests
- [CI/CD](../deployment/CI_CD.md) — CI pipeline configuration
- [Performance Optimization](../reference/PERFORMANCE_OPTIMIZATION.md) — Benchmarking details
- [Contributing](../contributing/CONTRIBUTING.md) — Testing requirements for PRs
