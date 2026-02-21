Last Updated: 2026-02-13

# Technology Stack

> **VaulType** — Privacy-first, macOS-native speech-to-text with local LLM post-processing.
> Every technology was chosen to maximize privacy, performance, and native macOS integration.

---

## Table of Contents

- [Technology Overview](#technology-overview)
- [Core Language and Frameworks](#core-language-and-frameworks)
  - [Why Swift/SwiftUI Over Electron or Cross-Platform](#why-swiftswiftui-over-electron-or-cross-platform)
- [ML Engines](#ml-engines)
  - [Why whisper.cpp Over Apple Speech Framework](#why-whispercpp-over-apple-speech-framework)
  - [Why llama.cpp vs Ollama vs MLX](#why-llamacpp-vs-ollama-vs-mlx)
- [Audio Pipeline](#audio-pipeline)
  - [Why AVAudioEngine Over AudioQueue/AVAudioRecorder](#why-avaudioengine-over-audioqueueavAudiorecorder)
- [Text Injection](#text-injection)
  - [Why CGEvent Over Accessibility API for Text Injection](#why-cgevent-over-accessibility-api-for-text-injection)
- [Data Persistence](#data-persistence)
  - [Why SwiftData Over Core Data](#why-swiftdata-over-core-data)
- [Build and Distribution](#build-and-distribution)
- [Version Compatibility Matrix](#version-compatibility-matrix)
- [Performance Considerations](#performance-considerations)
  - [Apple Silicon vs Intel Comparison](#apple-silicon-vs-intel-comparison)
- [Memory Usage Analysis](#memory-usage-analysis)
- [Technology Integration Examples](#technology-integration-examples)
- [Learning Resources](#learning-resources)
- [Related Documentation](#related-documentation)

---

## Technology Overview

| Technology | Version | Purpose | License | Category |
|---|---|---|---|---|
| **Swift** | 5.9+ | Primary language | Apache 2.0 | Language |
| **SwiftUI** | 5.0+ | UI framework (menu bar, settings) | Proprietary (Apple) | UI |
| **AppKit** | macOS 14+ | Native macOS integration | Proprietary (Apple) | UI |
| **Combine** | macOS 14+ | Reactive data streams | Proprietary (Apple) | Framework |
| **whisper.cpp** | latest (`master`) | Speech-to-text inference | MIT | ML Engine |
| **llama.cpp** | latest (`master`) | LLM post-processing inference | MIT | ML Engine |
| **AVAudioEngine** | macOS 14+ | Real-time audio capture | Proprietary (Apple) | Audio |
| **Metal** | 3.1+ | GPU-accelerated ML inference | Proprietary (Apple) | GPU |
| **CGEvent** | macOS 14+ | Keystroke simulation / text injection | Proprietary (Apple) | System |
| **SwiftData** | macOS 14+ | Local data persistence | Proprietary (Apple) | Storage |
| **UserDefaults** | macOS 14+ | Preferences storage | Proprietary (Apple) | Storage |
| **Keychain Services** | macOS 14+ | Secure credential storage | Proprietary (Apple) | Security |
| **Sparkle** | 2.x | Auto-update framework | MIT | Distribution |
| **Swift Package Manager** | 5.9+ | Dependency management | Apache 2.0 | Build |
| **CMake** | 3.21+ | C/C++ library builds (whisper.cpp, llama.cpp) | BSD 3-Clause | Build |
| **GitHub Actions** | N/A | CI/CD pipeline | N/A | CI/CD |
| **notarytool** | Xcode 15+ | Apple notarization | Proprietary (Apple) | Distribution |

---

## Core Language and Frameworks

### Why Swift/SwiftUI Over Electron or Cross-Platform

VaulType is a macOS-only application by design. This single-platform commitment allows us to use the best tools for the job without compromise.

| Criteria | Swift/SwiftUI | Electron | Tauri | Qt |
|---|---|---|---|---|
| **Binary size** | ~15 MB | ~150 MB+ | ~8 MB | ~40 MB+ |
| **RAM at idle** | ~30 MB | ~150 MB+ | ~50 MB | ~80 MB |
| **Metal GPU access** | Native, direct | Via WebGPU (limited) | Via plugins | Via plugins |
| **CGEvent access** | Direct C bridge | Node.js FFI | Rust FFI | C++ native |
| **Accessibility API** | First-class citizen | Requires native modules | Requires native modules | Partial |
| **Menu bar app** | `MenuBarExtra` built-in | Custom window hacks | Custom implementation | Custom implementation |
| **macOS look & feel** | Pixel-perfect native | Web-styled (foreign) | Web-styled | Close but not native |
| **Startup time** | < 0.5s | 2-5s | < 1s | 1-2s |
| **System integration** | Full (Spotlight, Services, Shortcuts) | Minimal | Minimal | Partial |

> ✅ **Do**: Use Swift for anything that touches macOS system APIs, Metal, or performance-critical paths.
>
> ❌ **Don't**: Introduce cross-platform abstractions that compromise native macOS behavior.

**Key advantages of Swift/SwiftUI for VaulType:**

1. **Direct Metal access** — whisper.cpp and llama.cpp use Metal Performance Shaders via Apple's GPU framework. Swift calls these APIs with zero overhead.

2. **System API access** — CGEvent (text injection), Accessibility API (permissions), AVAudioEngine (audio capture), and IOKit (hardware detection) are all first-class Swift APIs.

3. **Menu bar native support** — SwiftUI's `MenuBarExtra` provides a native menu bar experience with minimal code:

```swift
@main
struct VaulTypeApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("VaulType", systemImage: appState.isRecording ? "mic.fill" : "mic") {
            MenuBarView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
```

4. **Small binary size** — The entire app ships under 15 MB (excluding ML models), compared to Electron apps that bundle a full Chromium instance.

5. **First-class macOS citizen** — Native notifications, Spotlight integration, Services menu, Shortcuts app support, and sandboxing compatibility.

> 🍎 **macOS-specific**: SwiftUI on macOS 14+ provides `MenuBarExtra`, `Settings` scene, and native window management that would require extensive workarounds in cross-platform frameworks.

---

## ML Engines

### Why whisper.cpp Over Apple Speech Framework

This is the most critical technology decision in VaulType. The choice of whisper.cpp is driven by our core privacy guarantee: **no audio data ever leaves the device**.

| Criteria | whisper.cpp | Apple Speech (SFSpeechRecognizer) | Google Speech API | Deepgram |
|---|---|---|---|---|
| **Privacy** | 100% local | May send to Apple servers | Cloud-only | Cloud-only |
| **Network required** | No | Optional (on-device mode limited) | Yes | Yes |
| **Model flexibility** | Any Whisper model (tiny to large-v3) | Apple's model only | Google's model only | Deepgram's model only |
| **Language support** | 99 languages | ~60 languages (on-device: fewer) | 120+ languages | 36 languages |
| **Metal GPU accel** | Yes (full Metal backend) | Internal (opaque) | N/A | N/A |
| **Custom models** | Fine-tuned GGML models | No | No | No |
| **Beam search tuning** | Full control | No | No | Limited |
| **Open source** | MIT license | Proprietary | Proprietary | Proprietary |
| **Cost** | Free | Free | Pay-per-use | Pay-per-use |
| **Latency (local)** | ~0.3-1.5s depending on model | ~0.5-2s | 0.3-1s (network-dependent) | 0.2-0.8s (network-dependent) |

> 🔒 **Security**: Apple's `SFSpeechRecognizer` with on-device mode (`requiresOnDeviceRecognition = true`) is limited to a small set of languages and lacks the model flexibility VaulType requires. More critically, Apple's privacy policy for Speech APIs allows aggregated data collection, which conflicts with our zero-telemetry guarantee.

**whisper.cpp integration architecture:**

```
┌─────────────────────────────────────────────────────┐
│                    Swift Layer                       │
│  ┌───────────────────────────────────────────────┐  │
│  │         WhisperContext (Swift class)           │  │
│  │  - Manages whisper_context* lifecycle          │  │
│  │  - Configures whisper_full_params              │  │
│  │  - Handles PCM float buffer conversion         │  │
│  └──────────────────┬────────────────────────────┘  │
│                     │ C bridging header              │
├─────────────────────┼───────────────────────────────┤
│                     ▼                                │
│  ┌───────────────────────────────────────────────┐  │
│  │            whisper.cpp (C/C++)                 │  │
│  │  - GGML tensor operations                     │  │
│  │  - Encoder/Decoder transformer                │  │
│  │  - Beam search / greedy decoding              │  │
│  └──────────────────┬────────────────────────────┘  │
│                     │                                │
│  ┌──────────────────▼────────────────────────────┐  │
│  │           Metal Backend (GGML)                 │  │
│  │  - Matrix multiplication on GPU               │  │
│  │  - Flash attention kernels                    │  │
│  │  - Quantized inference (Q4_0, Q5_1, Q8_0)    │  │
│  └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

**Beam search parameter control** — Unlike Apple Speech, whisper.cpp exposes full inference parameters:

```swift
/// Configure whisper.cpp inference parameters for optimal accuracy/speed tradeoff
func createWhisperParams(for quality: TranscriptionQuality) -> whisper_full_params {
    var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)

    switch quality {
    case .fast:
        params.n_threads = 4
        params.speed_up = true
        params.no_context = true
        params.single_segment = true
        params.beam_search.beam_size = 1  // Greedy decoding
        params.entropy_thold = 2.4

    case .balanced:
        params.n_threads = 6
        params.speed_up = false
        params.no_context = false
        params.single_segment = false
        params.beam_search.beam_size = 3
        params.entropy_thold = 2.6

    case .accurate:
        params.strategy = WHISPER_SAMPLING_BEAM_SEARCH
        params.n_threads = 8
        params.speed_up = false
        params.no_context = false
        params.beam_search.beam_size = 5
        params.beam_search.patience = 1.0
        params.entropy_thold = 2.8
        params.suppress_blank = true
        params.suppress_non_speech_tokens = true
    }

    // Language detection or explicit language setting
    params.language = nil  // Auto-detect
    params.detect_language = true
    params.translate = false  // Transcribe in source language

    return params
}
```

> 💡 **Tip**: For real-time dictation, use `quality: .fast` with the `whisper-tiny` or `whisper-base` model. For editing finalized text, switch to `quality: .accurate` with `whisper-small` or `whisper-medium`.

---

### Why llama.cpp vs Ollama vs MLX

VaulType uses a local LLM for post-processing tasks: punctuation correction, formatting, grammar fixes, command interpretation, and text transformation. The choice of engine is critical for both integration simplicity and runtime performance.

| Criteria | llama.cpp (direct) | Ollama | MLX (Apple) | Core ML |
|---|---|---|---|---|
| **Integration** | C library linked directly | Separate process (HTTP API) | Python-first, Swift bindings experimental | Model conversion required |
| **Process model** | In-process | Out-of-process daemon | In-process (Python) or separate | In-process |
| **Metal support** | Full Metal backend | Via llama.cpp internally | Native Apple Silicon | Native Apple Silicon |
| **Model format** | GGUF (universal) | GGUF (via llama.cpp) | Safetensors/MLX format | Core ML `.mlpackage` |
| **Model ecosystem** | Huge (HuggingFace GGUF) | Ollama registry | Growing | Limited |
| **Memory efficiency** | Excellent (mmap, quantization) | Good (+ daemon overhead) | Good | Good |
| **Startup overhead** | ~50ms (model already loaded) | ~200ms (HTTP round-trip) | ~100ms | ~100ms |
| **Binary dependency** | None (compiled in) | Requires Ollama installed | Requires Python or Swift pkg | Xcode tools for conversion |
| **License** | MIT | MIT | MIT | Proprietary |
| **User setup** | Zero (bundled) | User must install Ollama | Complex | Complex |

**Our approach: llama.cpp as primary, Ollama as optional alternative.**

```
┌───────────────────────────────────────────────────────────────┐
│                      LLM Processing Layer                     │
│                                                               │
│   ┌─────────────────────┐     ┌────────────────────────────┐ │
│   │  llama.cpp (default) │     │  Ollama (optional)         │ │
│   │  ─────────────────── │     │  ──────────────────────    │ │
│   │  In-process C lib    │     │  HTTP API to localhost     │ │
│   │  Zero setup needed   │     │  For users who already     │ │
│   │  Minimal overhead    │     │  have Ollama installed     │ │
│   └─────────┬───────────┘     └──────────┬─────────────────┘ │
│             │                             │                   │
│             └──────────┬──────────────────┘                   │
│                        ▼                                      │
│              ┌─────────────────┐                              │
│              │  LLMProvider    │  (Protocol)                  │
│              │  protocol       │                              │
│              └─────────────────┘                              │
└───────────────────────────────────────────────────────────────┘
```

**Why not Ollama as default:**

1. **External dependency** — Users would need to install and run a separate daemon. VaulType's promise is "download and it works."
2. **Process management** — Detecting if Ollama is running, handling its lifecycle, and recovering from crashes adds significant complexity.
3. **Latency** — Each inference call goes through HTTP, adding ~50-200ms of overhead per request.
4. **Resource contention** — Ollama manages its own model loading/unloading, which can conflict with VaulType's memory management strategy.

**Why not MLX as default:**

1. **Swift bindings maturity** — MLX's Swift bindings are experimental as of 2025 and lack the stability of llama.cpp's C API.
2. **Apple Silicon only** — MLX has no Intel fallback; llama.cpp supports both architectures with graceful degradation.
3. **Model ecosystem** — GGUF models on HuggingFace vastly outnumber MLX-format models, giving users more choice.

> ℹ️ **Info**: llama.cpp is compiled directly into the VaulType binary via CMake and Swift Package Manager. No external processes, no HTTP APIs, no daemons. The LLM runs in the same address space as the app.

**LLM provider protocol for extensibility:**

```swift
/// Protocol abstracting LLM inference backends
protocol LLMProvider: Sendable {
    /// Load a model from the given file path
    func loadModel(at path: URL, parameters: LLMLoadParameters) async throws

    /// Run a completion with the given prompt and parameters
    func complete(prompt: String, parameters: LLMInferenceParameters) async throws -> String

    /// Check if a model is currently loaded and ready
    var isModelLoaded: Bool { get }

    /// Estimated memory usage of the currently loaded model in bytes
    var estimatedMemoryUsage: UInt64 { get }

    /// Unload the current model and free resources
    func unloadModel() async
}

/// Direct llama.cpp integration — default provider
final class LlamaCppProvider: LLMProvider {
    private var context: OpaquePointer?  // llama_context*
    private var model: OpaquePointer?    // llama_model*

    func loadModel(at path: URL, parameters: LLMLoadParameters) async throws {
        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = parameters.gpuLayers  // Metal offloading
        modelParams.use_mmap = true                       // Memory-mapped I/O

        model = llama_load_model_from_file(path.path, modelParams)
        guard model != nil else {
            throw LLMError.modelLoadFailed(path: path)
        }

        var contextParams = llama_context_default_params()
        contextParams.n_ctx = UInt32(parameters.contextLength)
        contextParams.n_batch = UInt32(parameters.batchSize)
        contextParams.n_threads = UInt32(parameters.threadCount)

        context = llama_new_context_with_model(model, contextParams)
        guard context != nil else {
            throw LLMError.contextCreationFailed
        }
    }
    // ... completion and lifecycle methods
}

/// Ollama HTTP API — optional alternative provider
final class OllamaProvider: LLMProvider {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = URL(string: "http://localhost:11434")!) {
        self.baseURL = baseURL
        // URLSession configured for local-only connections
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }
    // ... HTTP-based inference methods
}
```

> ⚠️ **Warning**: When using the Ollama provider, network calls are made to `localhost:11434` only. VaulType's App Transport Security (ATS) configuration explicitly allows only loopback addresses. No data is sent to external servers.

---

## Audio Pipeline

### Why AVAudioEngine Over AudioQueue/AVAudioRecorder

| Criteria | AVAudioEngine | AudioQueue (C API) | AVAudioRecorder |
|---|---|---|---|
| **API style** | Modern Swift/ObjC | C callback-based | High-level, limited |
| **Real-time processing** | Yes (tap-based) | Yes (buffer callbacks) | No |
| **Format conversion** | Built-in converter nodes | Manual conversion | Fixed format |
| **Latency** | Low (~10ms buffer) | Very low (~5ms) | High (~100ms+) |
| **VAD integration** | Easy (tap audio buffers) | Manual buffer management | Not practical |
| **Sample rate conversion** | Automatic via format nodes | Manual | Automatic but limited |
| **Complexity** | Moderate | High | Low |
| **Recommended by Apple** | Yes (current) | Legacy | Simple recording only |

> 🍎 **macOS-specific**: `AVAudioEngine` on macOS supports input device selection, aggregate devices, and system audio capture when combined with Audio Units. This is essential for VaulType's microphone selection feature.

**AVAudioEngine setup for whisper.cpp integration:**

```swift
import AVFoundation

final class AudioCaptureManager: @unchecked Sendable {
    private let audioEngine = AVAudioEngine()
    private var audioBuffer = CircularAudioBuffer(capacity: 30 * 16000) // 30 seconds at 16kHz
    private let targetSampleRate: Double = 16000.0  // whisper.cpp expects 16kHz mono

    /// Install a tap on the input node to capture microphone audio
    func startCapture() throws {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // whisper.cpp requires 16kHz mono Float32 PCM
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioError.formatCreationFailed
        }

        // Use AVAudioConverter for sample rate conversion
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioError.converterCreationFailed
        }

        // Install tap on input node — this is the real-time audio callback
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1024,  // ~64ms at 16kHz — low latency
            format: inputFormat
        ) { [weak self] (buffer, time) in
            self?.processAudioBuffer(buffer, converter: converter, targetFormat: targetFormat)
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    /// Convert captured audio to 16kHz mono Float32 for whisper.cpp
    private func processAudioBuffer(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) {
        let frameCount = AVAudioFrameCount(
            Double(buffer.frameLength) * targetSampleRate / buffer.format.sampleRate
        )

        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: frameCount
        ) else { return }

        var error: NSError?
        var allConsumed = false

        converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            if allConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            allConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        if error == nil, let channelData = convertedBuffer.floatChannelData {
            let samples = Array(
                UnsafeBufferPointer(
                    start: channelData[0],
                    count: Int(convertedBuffer.frameLength)
                )
            )
            audioBuffer.append(samples)
        }
    }

    func stopCapture() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
    }

    /// Get accumulated audio samples for whisper.cpp inference
    func getAccumulatedSamples() -> [Float] {
        return audioBuffer.drain()
    }
}
```

> 💡 **Tip**: The `bufferSize: 1024` parameter in `installTap` controls latency. Smaller values (512) reduce latency but increase CPU overhead. Larger values (4096) reduce CPU load but add latency. 1024 is a good balance for real-time dictation.

---

## Text Injection

### Why CGEvent Over Accessibility API for Text Injection

VaulType needs to type transcribed text into any application the user is focused on. There are two primary approaches on macOS:

| Criteria | CGEvent (Keystroke Simulation) | Accessibility API (AXUIElement) |
|---|---|---|
| **Universality** | Works in virtually all apps | Requires per-app compatibility |
| **Terminal support** | Full support (Terminal, iTerm2, Alacritty) | Inconsistent / broken |
| **Electron app support** | Full support (VS Code, Slack, Discord) | Varies by app |
| **Permission model** | One-time Accessibility permission | Same one-time permission |
| **Per-app trust** | Not required after initial grant | Some apps require additional setup |
| **Implementation** | Simulate keystrokes (Shift, Cmd, etc.) | Find focused element, set `AXValue` |
| **Unicode support** | Via `CGEvent(keyboardEventSource:...)` | Direct string setting |
| **Speed (short text)** | Fast (~1ms per keystroke) | Very fast (instant) |
| **Speed (long text)** | Slow for long text (keystroke-by-keystroke) | Fast (set entire string) |
| **Reliability** | Very high | App-dependent |

**VaulType's dual-mode approach:**

```
┌─────────────────────────────────────────┐
│           Text Injection Engine          │
│                                         │
│   Input: "Hello, world!"               │
│                                         │
│   ┌───────────────────────┐             │
│   │  Short text (< 50ch)  │─── CGEvent  │
│   │  Keystroke simulation │    keystrokes│
│   └───────────────────────┘             │
│                                         │
│   ┌───────────────────────┐             │
│   │  Long text (>= 50ch)  │─── Clipboard│
│   │  Clipboard + Cmd+V    │    paste     │
│   └───────────────────────┘             │
│                                         │
│   (Clipboard is restored after paste)   │
└─────────────────────────────────────────┘
```

**CGEvent keystroke simulation example:**

```swift
import CoreGraphics

final class TextInjector {
    /// Inject text at the current cursor position using CGEvent keystroke simulation
    func injectViaKeystrokes(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)

        for character in text {
            guard let unicodeScalar = character.unicodeScalars.first else { continue }
            let keyCode: CGKeyCode = 0  // Virtual key code (not used for Unicode input)

            // Key down event with Unicode character
            if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
                var utf16 = Array(character.utf16)
                keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
                keyDown.post(tap: .cghidEventTap)
            }

            // Key up event
            if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
                var utf16 = Array(character.utf16)
                keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
                keyUp.post(tap: .cghidEventTap)
            }

            // Small delay to prevent event coalescing in target apps
            usleep(1000)  // 1ms between keystrokes
        }
    }

    /// Inject long text via clipboard paste with clipboard preservation
    func injectViaClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general

        // Preserve existing clipboard contents
        let previousContents = pasteboard.string(forType: .string)

        // Set transcribed text to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate Cmd+V
        let source = CGEventSource(stateID: .hidSystemState)
        let vKeyCode: CGKeyCode = 9  // 'v' key

        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true) {
            keyDown.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
        }
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) {
            keyUp.flags = .maskCommand
            keyUp.post(tap: .cghidEventTap)
        }

        // Restore clipboard after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            pasteboard.clearContents()
            if let previous = previousContents {
                pasteboard.setString(previous, forType: .string)
            }
        }
    }
}
```

> 🔒 **Security**: CGEvent posting requires the Accessibility permission (`kAXTrustedCheckOptionPrompt`). VaulType requests this permission on first launch and guides the user through System Settings > Privacy & Security > Accessibility.

> ⚠️ **Warning**: The clipboard-paste fallback temporarily modifies the system clipboard. VaulType preserves and restores the previous clipboard contents, but there is a brief window (~150ms) where the clipboard contains the transcribed text. This is an inherent limitation of the paste approach.

---

## Data Persistence

### Why SwiftData Over Core Data

| Criteria | SwiftData | Core Data | SQLite (direct) | Realm |
|---|---|---|---|---|
| **API style** | Swift-native macros | ObjC-legacy, verbose | C API | ObjC/Swift wrapper |
| **Schema definition** | `@Model` macro on Swift class | `.xcdatamodeld` file | SQL DDL | Object subclass |
| **SwiftUI integration** | `@Query` property wrapper | `@FetchRequest` | Manual | Manual |
| **Migration** | Automatic lightweight migration | Manual migration mapping | Manual SQL | Automatic |
| **CloudKit sync** | Built-in (disabled for VaulType) | Built-in | Not available | Realm Sync (cloud) |
| **Thread safety** | `ModelActor` for background | `NSManagedObjectContext` per thread | Manual locking | Thread-confined |
| **Swift concurrency** | Full async/await support | Partial (performBlock) | Manual | Partial |
| **Minimum macOS** | 14.0 (Sonoma) | 10.4+ | Any | 10.0+ |

> ℹ️ **Info**: SwiftData's CloudKit sync capability is explicitly disabled in VaulType. We configure `ModelConfiguration` with `cloudKitDatabase: .none` to ensure zero network activity. This is a deliberate privacy decision, not a limitation.

**SwiftData model example:**

```swift
import SwiftData

@Model
final class TranscriptionRecord {
    var id: UUID
    var text: String
    var rawText: String           // Before LLM post-processing
    var language: String           // Detected language code (e.g., "en", "tr")
    var confidence: Double         // Whisper confidence score (0.0 - 1.0)
    var createdAt: Date
    var durationSeconds: Double    // Audio duration
    var modelUsed: String          // e.g., "whisper-base", "whisper-small"
    var wasPostProcessed: Bool     // Whether LLM post-processing was applied
    var targetApplication: String? // Bundle ID of the app text was injected into

    init(
        text: String,
        rawText: String,
        language: String,
        confidence: Double,
        durationSeconds: Double,
        modelUsed: String,
        wasPostProcessed: Bool = false,
        targetApplication: String? = nil
    ) {
        self.id = UUID()
        self.text = text
        self.rawText = rawText
        self.language = language
        self.confidence = confidence
        self.createdAt = Date()
        self.durationSeconds = durationSeconds
        self.modelUsed = modelUsed
        self.wasPostProcessed = wasPostProcessed
        self.targetApplication = targetApplication
    }
}
```

**Container configuration with CloudKit disabled:**

```swift
import SwiftData

extension ModelContainer {
    static func createVaulTypeContainer() throws -> ModelContainer {
        let schema = Schema([
            TranscriptionRecord.self,
            UserPromptTemplate.self,
            ModelConfiguration.self,
        ])

        let configuration = ModelConfiguration(
            "VaulTypeStore",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: .none,       // No app group sharing
            cloudKitDatabase: .none       // Explicitly disable CloudKit — privacy guarantee
        )

        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }
}
```

> 🔒 **Security**: VaulType stores transcription history in a local SwiftData database. Users can configure automatic deletion (after 24 hours, 7 days, 30 days, or never) in Settings. The database file is stored in the app's sandboxed container at `~/Library/Application Support/VaulType/`.

---

## Build and Distribution

### Build System

| Component | Tool | Purpose |
|---|---|---|
| **Swift code** | Xcode 15+ / `xcodebuild` | Compile Swift/SwiftUI app |
| **Swift dependencies** | Swift Package Manager | Manage Swift packages (Sparkle, etc.) |
| **whisper.cpp** | CMake 3.21+ | Build C/C++ library with Metal |
| **llama.cpp** | CMake 3.21+ | Build C/C++ library with Metal |
| **ML models** | Download script | Fetch GGUF models from HuggingFace |
| **Code signing** | `codesign` | Developer ID Application certificate |
| **Notarization** | `notarytool` | Apple notarization for Gatekeeper |
| **DMG creation** | `create-dmg` or `hdiutil` | macOS disk image for distribution |

**Build process overview:**

```bash
# 1. Clone with submodules (whisper.cpp, llama.cpp)
git clone --recursive https://github.com/user/vaultype.git
cd vaultype

# 2. Build C/C++ dependencies with Metal support
cmake -B build/whisper -S vendor/whisper.cpp \
    -DWHISPER_METAL=ON \
    -DWHISPER_COREML=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64"
cmake --build build/whisper --config Release

cmake -B build/llama -S vendor/llama.cpp \
    -DLLAMA_METAL=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64"
cmake --build build/llama --config Release

# 3. Build the Swift app
xcodebuild -project VaulType.xcodeproj \
    -scheme VaulType \
    -configuration Release \
    -archivePath build/VaulType.xcarchive \
    archive

# 4. Export for distribution
xcodebuild -exportArchive \
    -archivePath build/VaulType.xcarchive \
    -exportPath build/export \
    -exportOptionsPlist ExportOptions.plist
```

### Distribution Channels

| Channel | Format | Auto-Update | User Action |
|---|---|---|---|
| **GitHub Releases** | `.dmg` | Via Sparkle | Download and drag to /Applications |
| **Homebrew Cask** | Formula | Via `brew upgrade` | `brew install --cask vaultype` |
| **Sparkle** | `.zip` (appcast) | Automatic background updates | Prompted in-app |

### CI/CD Pipeline (GitHub Actions)

```bash
# Triggered on: push to main, pull requests, tags (v*)
#
# Jobs:
# 1. build-and-test    — Compile, run unit tests, run UI tests
# 2. notarize          — Code sign + notarize (on tags only)
# 3. create-release    — Build DMG, upload to GitHub Releases (on tags only)
# 4. update-homebrew   — Update Homebrew cask formula (on tags only)
```

> 💡 **Tip**: Local development does not require code signing or notarization. The app runs fine unsigned during development. Code signing is only needed for distribution builds.

---

## Version Compatibility Matrix

| macOS Version | Minimum | Metal GPU | whisper.cpp Metal | llama.cpp Metal | SwiftData | SwiftUI MenuBarExtra | Status |
|---|---|---|---|---|---|---|---|
| **macOS 15 (Sequoia)** | - | Full (Metal 3.2) | Full acceleration | Full acceleration | Full support | Full support | **Fully Supported** |
| **macOS 14 (Sonoma)** | **Target** | Full (Metal 3.1) | Full acceleration | Full acceleration | Full support | Full support | **Primary Target** |
| **macOS 13 (Ventura)** | - | Full (Metal 3.0) | Full acceleration | Full acceleration | Not available | Full support | **Not Supported** (SwiftData) |
| **macOS 12 (Monterey)** | - | Partial | Partial | Partial | Not available | Not available | **Not Supported** |
| **macOS 11 (Big Sur)** | - | Partial | CPU only | CPU only | Not available | Not available | **Not Supported** |

| Hardware | whisper.cpp Performance | llama.cpp Performance | Metal Acceleration | Status |
|---|---|---|---|---|
| **Apple Silicon M1** | Excellent | Excellent | Full (unified memory) | **Recommended** |
| **Apple Silicon M1 Pro/Max/Ultra** | Excellent | Excellent | Full (more GPU cores) | **Recommended** |
| **Apple Silicon M2/M3/M4 family** | Excellent | Excellent | Full (latest Metal) | **Recommended** |
| **Intel Mac with AMD GPU** | Good | Good | Partial (discrete GPU) | **Supported** |
| **Intel Mac (integrated graphics)** | Moderate | Moderate | Limited | **Supported (CPU fallback)** |

> 🍎 **macOS-specific**: Apple Silicon's unified memory architecture is a significant advantage for ML inference. Both whisper.cpp and llama.cpp can access GPU memory without the copy overhead present on discrete GPU systems. A Mac with 16 GB unified memory can run models that would require careful GPU memory management on Intel Macs.

---

## Performance Considerations

### Apple Silicon vs Intel Comparison

The following benchmarks were measured on representative hardware. Actual performance varies with system load, thermal conditions, and specific hardware configuration.

#### Whisper Transcription Speed (10-second audio clip)

| Model | Parameters | Apple Silicon M1 (8 GB) | Apple Silicon M2 Pro (16 GB) | Intel i7 (6-core, AMD 5500M) | Intel i5 (4-core, integrated) |
|---|---|---|---|---|---|
| `whisper-tiny` | 39M | **~0.3s** | **~0.2s** | ~0.8s | ~1.5s |
| `whisper-base` | 74M | **~0.5s** | **~0.3s** | ~1.2s | ~2.5s |
| `whisper-small` | 244M | **~1.0s** | **~0.6s** | ~3.0s | ~6.0s |
| `whisper-medium` | 769M | **~2.5s** | **~1.5s** | ~8.0s | ~15.0s |
| `whisper-large-v3` | 1550M | **~5.0s** | **~3.0s** | ~18.0s | ~35.0s |

> ℹ️ **Info**: Times marked in bold indicate real-time or faster-than-real-time processing (under 10 seconds for a 10-second clip). For real-time dictation, the model must process audio faster than it arrives.

#### LLM Post-Processing Speed (formatting a 100-word paragraph)

| Model | Parameters | Quantization | Apple Silicon M1 | Apple Silicon M2 Pro | Intel i7 (AMD GPU) |
|---|---|---|---|---|---|
| `Qwen2.5-0.5B` | 0.5B | Q4_K_M | **~0.3s** | **~0.2s** | ~0.8s |
| `Qwen2.5-1.5B` | 1.5B | Q4_K_M | **~0.8s** | **~0.5s** | ~2.0s |
| `Qwen2.5-3B` | 3B | Q4_K_M | **~1.5s** | **~0.9s** | ~4.0s |
| `Llama-3.2-1B` | 1B | Q4_K_M | **~0.5s** | **~0.3s** | ~1.2s |
| `Llama-3.2-3B` | 3B | Q4_K_M | **~1.5s** | **~0.9s** | ~4.0s |
| `Phi-3-mini-4k` | 3.8B | Q4_K_M | **~2.0s** | **~1.2s** | ~5.0s |

#### Model Loading Time (cold start)

| Model Size | Apple Silicon (NVMe) | Intel (SATA SSD) | Intel (HDD) |
|---|---|---|---|
| ~100 MB (tiny/base) | **~0.1s** | ~0.3s | ~1.5s |
| ~500 MB (small) | **~0.3s** | ~0.8s | ~3.0s |
| ~1.5 GB (medium) | **~0.5s** | ~2.0s | ~8.0s |
| ~3 GB (large-v3) | **~0.8s** | ~3.5s | ~15.0s |
| ~2 GB (LLM 3B Q4) | **~0.6s** | ~2.5s | ~10.0s |

> 💡 **Tip**: VaulType keeps models loaded in memory between transcriptions to avoid reload latency. Use `mmap` (memory-mapped I/O) for models that exceed available RAM — the OS will page sections in and out efficiently.

---

## Memory Usage Analysis

Memory requirements depend on which Whisper model and LLM model are loaded simultaneously. The following table shows approximate peak RAM usage for common combinations.

### Model Combinations and RAM Usage

| Whisper Model | LLM Model | Model Files Size | Peak RAM Usage | Recommended System RAM | Notes |
|---|---|---|---|---|---|
| `tiny` (Q8_0) | None (no LLM) | ~75 MB | **~200 MB** | 4 GB | Minimal setup, no post-processing |
| `tiny` (Q8_0) | `Qwen2.5-0.5B` (Q4_K_M) | ~450 MB | **~800 MB** | 8 GB | Lightweight with basic post-processing |
| `base` (Q8_0) | `Qwen2.5-1.5B` (Q4_K_M) | ~1.1 GB | **~1.5 GB** | 8 GB | Good balance of speed and quality |
| `small` (Q5_1) | `Qwen2.5-3B` (Q4_K_M) | ~2.2 GB | **~3.0 GB** | 8 GB | Recommended for most users |
| `small` (Q5_1) | `Llama-3.2-3B` (Q4_K_M) | ~2.4 GB | **~3.2 GB** | 8 GB | Alternative recommended config |
| `medium` (Q5_0) | `Qwen2.5-3B` (Q4_K_M) | ~3.5 GB | **~5.0 GB** | 16 GB | High accuracy transcription |
| `medium` (Q5_0) | `Llama-3.2-3B` (Q4_K_M) | ~3.7 GB | **~5.2 GB** | 16 GB | High accuracy alternative |
| `large-v3` (Q5_0) | `Qwen2.5-3B` (Q4_K_M) | ~5.5 GB | **~7.5 GB** | 16 GB | Maximum transcription quality |
| `large-v3` (Q5_0) | `Llama-3.2-3B` (Q4_K_M) | ~5.7 GB | **~7.8 GB** | 16 GB | Maximum quality alternative |
| `large-v3` (Q8_0) | `Phi-3-mini-4k` (Q4_K_M) | ~7.0 GB | **~9.5 GB** | 32 GB | Maximum quality, advanced LLM |

### Memory Breakdown

```
┌──────────────────────────────────────────────────────────┐
│                  VaulType Memory Layout                   │
│                  (small + Llama-3.2-3B)                   │
│                                                          │
│  ┌────────────────────────────────────────┐  ~500 MB     │
│  │  Whisper Model (small, Q5_1)          │  (mmap'd)    │
│  └────────────────────────────────────────┘              │
│  ┌────────────────────────────────────────┐  ~2.0 GB     │
│  │  LLM Model (Llama-3.2-3B, Q4_K_M)    │  (mmap'd)    │
│  └────────────────────────────────────────┘              │
│  ┌────────────────────────────┐  ~200 MB                 │
│  │  Whisper KV Cache          │  (allocated)             │
│  └────────────────────────────┘                          │
│  ┌────────────────────────────┐  ~300 MB                 │
│  │  LLM KV Cache              │  (allocated)             │
│  └────────────────────────────┘                          │
│  ┌──────────────┐  ~100 MB                               │
│  │  Audio Buffer │  (30s @ 16kHz)                        │
│  └──────────────┘                                        │
│  ┌──────────────┐  ~80 MB                                │
│  │  App + UI     │  (SwiftUI, SwiftData)                 │
│  └──────────────┘                                        │
│                                                          │
│  Total: ~3.2 GB peak                                     │
└──────────────────────────────────────────────────────────┘
```

> ⚠️ **Warning**: On systems with 8 GB RAM, using `whisper-large-v3` with a 3B+ LLM will cause significant memory pressure and potential swapping. VaulType displays a warning in Settings when the selected model combination exceeds 60% of system RAM.

> 💡 **Tip**: Memory-mapped I/O (`mmap`) means the OS only loads model pages that are actively needed. Reported "memory usage" in Activity Monitor may show high numbers, but actual physical RAM pressure is lower. Check "Memory Pressure" in Activity Monitor for true system impact.

---

## Technology Integration Examples

### End-to-End Flow: Audio Capture to Text Injection

The following example shows how VaulType's core technologies integrate in the main transcription pipeline:

```swift
import AVFoundation
import Combine

/// Orchestrates the full pipeline: Audio -> Whisper -> LLM -> Text Injection
final class TranscriptionPipeline: ObservableObject {
    @Published var state: PipelineState = .idle

    private let audioCaptureManager: AudioCaptureManager
    private let whisperContext: WhisperContext
    private let llmProvider: LLMProvider
    private let textInjector: TextInjector

    private var cancellables = Set<AnyCancellable>()

    init(
        audioCaptureManager: AudioCaptureManager,
        whisperContext: WhisperContext,
        llmProvider: LLMProvider,
        textInjector: TextInjector
    ) {
        self.audioCaptureManager = audioCaptureManager
        self.whisperContext = whisperContext
        self.llmProvider = llmProvider
        self.textInjector = textInjector
    }

    /// Start recording and processing audio
    func startTranscription() async throws {
        state = .recording
        try audioCaptureManager.startCapture()
    }

    /// Stop recording, transcribe, post-process, and inject text
    func stopAndProcess() async throws -> TranscriptionResult {
        // 1. Stop audio capture
        audioCaptureManager.stopCapture()
        state = .transcribing

        // 2. Get accumulated audio samples (16kHz mono Float32)
        let samples = audioCaptureManager.getAccumulatedSamples()

        // 3. Run whisper.cpp inference
        let rawText = try await whisperContext.transcribe(
            samples: samples,
            params: createWhisperParams(for: .balanced)
        )

        // 4. Post-process with LLM (punctuation, formatting, grammar)
        state = .postProcessing
        let processedText: String
        if llmProvider.isModelLoaded {
            let prompt = """
            Fix punctuation, capitalization, and grammar in the following \
            transcribed speech. Output only the corrected text, nothing else:

            \(rawText)
            """
            processedText = try await llmProvider.complete(
                prompt: prompt,
                parameters: LLMInferenceParameters(
                    maxTokens: 512,
                    temperature: 0.1,  // Low temperature for deterministic corrections
                    topP: 0.9
                )
            )
        } else {
            processedText = rawText
        }

        // 5. Inject text at cursor position
        state = .injecting
        if processedText.count < 50 {
            textInjector.injectViaKeystrokes(processedText)
        } else {
            textInjector.injectViaClipboard(processedText)
        }

        state = .idle

        return TranscriptionResult(
            rawText: rawText,
            processedText: processedText,
            language: whisperContext.detectedLanguage,
            confidence: whisperContext.averageConfidence,
            durationSeconds: Double(samples.count) / 16000.0
        )
    }
}
```

### whisper.cpp Bridging Header

To use whisper.cpp from Swift, a C bridging header exposes the necessary functions:

```c
// VaulType-Bridging-Header.h

#ifndef VaulType_Bridging_Header_h
#define VaulType_Bridging_Header_h

// whisper.cpp C API
#include "whisper.h"

// llama.cpp C API
#include "llama.h"

// Common GGML utilities
#include "ggml.h"

#endif /* VaulType_Bridging_Header_h */
```

This bridging header makes all whisper.cpp and llama.cpp C functions available directly in Swift:

```swift
/// Swift wrapper around whisper.cpp C context
final class WhisperContext {
    private var context: OpaquePointer?

    init(modelPath: String) throws {
        var params = whisper_context_default_params()
        params.use_gpu = true  // Enable Metal acceleration

        context = whisper_init_from_file_with_params(modelPath, params)
        guard context != nil else {
            throw WhisperError.modelLoadFailed(path: modelPath)
        }
    }

    /// Run inference on PCM float samples
    func transcribe(samples: [Float], params: whisper_full_params) async throws -> String {
        var mutableParams = params

        let result = samples.withUnsafeBufferPointer { bufferPointer in
            whisper_full(context, mutableParams, bufferPointer.baseAddress, Int32(samples.count))
        }

        guard result == 0 else {
            throw WhisperError.inferenceFailed(code: result)
        }

        // Collect all segments into a single string
        let segmentCount = whisper_full_n_segments(context)
        var transcription = ""
        for i in 0..<segmentCount {
            if let text = whisper_full_get_segment_text(context, i) {
                transcription += String(cString: text)
            }
        }

        return transcription.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    deinit {
        if let context {
            whisper_free(context)
        }
    }
}
```

---

## Learning Resources

### Core Technologies

| Technology | Resource | Type | URL |
|---|---|---|---|
| **Swift** | The Swift Programming Language | Official Book | [swift.org/documentation](https://swift.org/documentation/) |
| **SwiftUI** | Apple SwiftUI Tutorials | Official Tutorial | [developer.apple.com/tutorials/swiftui](https://developer.apple.com/tutorials/swiftui) |
| **SwiftData** | Meet SwiftData (WWDC23) | Video | [developer.apple.com/wwdc23/10187](https://developer.apple.com/videos/play/wwdc2023/10187/) |
| **Combine** | Using Combine | Book | [heckj.github.io/swiftui-notes](https://heckj.github.io/swiftui-notes/) |

### ML and Audio

| Technology | Resource | Type | URL |
|---|---|---|---|
| **whisper.cpp** | GitHub Repository | Source + Docs | [github.com/ggerganov/whisper.cpp](https://github.com/ggerganov/whisper.cpp) |
| **llama.cpp** | GitHub Repository | Source + Docs | [github.com/ggerganov/llama.cpp](https://github.com/ggerganov/llama.cpp) |
| **GGUF Format** | GGUF Specification | Spec | [github.com/ggerganov/ggml/blob/master/docs/gguf.md](https://github.com/ggerganov/ggml/blob/master/docs/gguf.md) |
| **Whisper Paper** | Robust Speech Recognition via Large-Scale Weak Supervision | Paper | [arxiv.org/abs/2212.04356](https://arxiv.org/abs/2212.04356) |
| **AVAudioEngine** | Apple Audio Engine Programming Guide | Guide | [developer.apple.com/audio](https://developer.apple.com/documentation/avfaudio/avaudioengine) |
| **Metal** | Metal Programming Guide | Official Guide | [developer.apple.com/metal](https://developer.apple.com/metal/) |

### macOS System APIs

| Technology | Resource | Type | URL |
|---|---|---|---|
| **CGEvent** | Quartz Event Services | Reference | [developer.apple.com/documentation/coregraphics/quartz_event_services](https://developer.apple.com/documentation/coregraphics/quartz_event_services) |
| **Accessibility** | Accessibility Programming Guide | Guide | [developer.apple.com/accessibility](https://developer.apple.com/documentation/accessibility) |
| **App Distribution** | Distributing Apps Outside the App Store | Guide | [developer.apple.com/documentation/xcode/distributing-your-app-outside-the-app-store](https://developer.apple.com/documentation/xcode/distributing-your-app-outside-the-app-store) |
| **Sparkle** | Sparkle Documentation | Docs | [sparkle-project.org](https://sparkle-project.org/) |

### Model Repositories

| Resource | Description | URL |
|---|---|---|
| **HuggingFace GGUF Models** | Pre-quantized models for whisper.cpp and llama.cpp | [huggingface.co/models?search=gguf](https://huggingface.co/models?search=gguf) |
| **Whisper Models** | Official OpenAI Whisper model weights | [huggingface.co/openai](https://huggingface.co/openai) |
| **Ollama Model Library** | Ollama-compatible model registry | [ollama.com/library](https://ollama.com/library) |

---

## Related Documentation

- [Architecture Overview](ARCHITECTURE.md) — High-level system architecture and component interactions
- [Setup Guide](../getting-started/SETUP_GUIDE.md) — Development environment setup and first build
- [Security Model](../security/SECURITY.md) — Privacy guarantees, threat model, and security architecture
- [Deployment Guide](../deployment/DEPLOYMENT.md) — Build, sign, notarize, and distribute
- [API Reference](../api/API_REFERENCE.md) — Internal module APIs and interfaces
- [Contributing Guide](../contributing/CONTRIBUTING.md) — How to contribute to VaulType
- [Testing Guide](../testing/TESTING.md) — Unit, integration, and UI testing strategy
- [Feature Documentation](../features/FEATURES.md) — Detailed feature specifications

---

*This document is part of the [VaulType Documentation](../). For questions or corrections, please open an issue on the [GitHub repository](https://github.com/user/vaultype).*
