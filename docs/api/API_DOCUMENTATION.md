Last Updated: 2026-02-13

# Internal API Documentation

> **HushType** — Privacy-first, macOS-native speech-to-text with local LLM post-processing.
> This document is the definitive internal Swift API reference for all HushType services, protocols, and extension points.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [AudioCaptureService API](#audiocaptureservice-api)
  - [Protocol Definition](#audiocaptureservice-protocol-definition)
  - [Configuration](#audiocaptureservice-configuration)
  - [Audio Level Callbacks](#audio-level-callbacks)
  - [Error Types](#audiocaptureservice-error-types)
  - [Usage Examples](#audiocaptureservice-usage-examples)
- [WhisperService API](#whisperservice-api)
  - [Protocol Definition](#whisperservice-protocol-definition)
  - [Transcription Modes](#transcription-modes)
  - [Streaming Transcription](#streaming-transcription)
  - [Model Management](#whisperservice-model-management)
  - [Error Types](#whisperservice-error-types)
  - [Usage Examples](#whisperservice-usage-examples)
- [LLMService API](#llmservice-api)
  - [Protocol Definition](#llmservice-protocol-definition)
  - [Processing Modes](#processing-modes)
  - [Template System](#template-system)
  - [Error Types](#llmservice-error-types)
  - [Usage Examples](#llmservice-usage-examples)
- [TextInjectionService API](#textinjectionservice-api)
  - [Protocol Definition](#textinjectionservice-protocol-definition)
  - [Injection Strategies](#injection-strategies)
  - [Active Field Detection](#active-field-detection)
  - [Error Types](#textinjectionservice-error-types)
  - [Usage Examples](#textinjectionservice-usage-examples)
- [CommandParser API](#commandparser-api)
  - [Protocol Definition](#commandparser-protocol-definition)
  - [Built-in Commands](#built-in-commands)
  - [Custom Command Registration](#custom-command-registration)
  - [Error Types](#commandparser-error-types)
  - [Usage Examples](#commandparser-usage-examples)
- [HotkeyManager API](#hotkeymanager-api)
  - [Protocol Definition](#hotkeymanager-protocol-definition)
  - [Key Binding Configuration](#key-binding-configuration)
  - [Mode Switching](#mode-switching)
  - [Error Types](#hotkeymanager-error-types)
  - [Usage Examples](#hotkeymanager-usage-examples)
- [ModelManager API](#modelmanager-api)
  - [Protocol Definition](#modelmanager-protocol-definition)
  - [Download and Lifecycle](#download-and-lifecycle)
  - [Model Registry](#model-registry)
  - [Error Types](#modelmanager-error-types)
  - [Usage Examples](#modelmanager-usage-examples)
- [Plugin API Specification](#plugin-api-specification)
  - [Plugin Protocol](#plugin-protocol)
  - [Plugin Lifecycle](#plugin-lifecycle)
  - [Extension Points](#extension-points)
  - [Plugin Manifest](#plugin-manifest)
  - [Security Sandboxing](#plugin-security-sandboxing)
  - [Plugin Examples](#plugin-examples)
- [Ollama REST API Integration](#ollama-rest-api-integration)
  - [Connection Management](#connection-management)
  - [Endpoint Reference](#endpoint-reference)
  - [Request and Response Types](#request-and-response-types)
  - [Error Handling](#ollama-error-handling)
  - [Usage Examples](#ollama-usage-examples)
- [Common Types and Protocols](#common-types-and-protocols)
- [Thread Safety and Concurrency](#thread-safety-and-concurrency)
- [Related Documentation](#related-documentation)

---

## Architecture Overview

All HushType services follow a protocol-oriented design with concrete implementations injected at the application layer. Every service is designed for Swift 5.9+ structured concurrency with `async/await` and `Sendable` conformance.

```
┌────────────────────────────────────────────────────────────────────┐
│                        Application Layer                           │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                    TranscriptionPipeline                      │  │
│  │    Orchestrates all services into a unified workflow          │  │
│  └────────┬──────┬──────┬──────┬──────┬──────┬──────┬──────────┘  │
│           │      │      │      │      │      │      │              │
│           ▼      ▼      ▼      ▼      ▼      ▼      ▼              │
│  ┌──────┐┌────┐┌─────┐┌─────┐┌─────┐┌─────┐┌──────┐              │
│  │Audio ││Whis││LLM  ││Text ││Cmd  ││Hot- ││Model │              │
│  │Captu-││per ││Serv-││Inje-││Pars-││key  ││Mana- │              │
│  │re    ││Serv││ice  ││ction││er   ││Mgr  ││ger   │              │
│  └──────┘└────┘└─────┘└─────┘└─────┘└─────┘└──────┘              │
│                                                                    │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                   Plugin Host (Future)                        │  │
│  └──────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────┘
```

> ℹ️ **Info**: All service protocols reside in the `HushType/Protocols/` directory. Concrete implementations live in `HushType/Services/`. This separation allows mock injection for unit testing and future alternative implementations.

---

## AudioCaptureService API

The `AudioCaptureService` manages real-time microphone audio capture via `AVAudioEngine`, converts audio to 16 kHz mono Float32 PCM (the format required by whisper.cpp), and provides audio level metering for the UI.

### AudioCaptureService Protocol Definition

```swift
import AVFoundation
import Combine

/// Configuration for audio capture sessions.
struct AudioCaptureConfiguration: Sendable {
    /// Target sample rate for output audio. Default is 16000 Hz (whisper.cpp requirement).
    var sampleRate: Double = 16000.0

    /// Number of audio channels. Default is 1 (mono, required by whisper.cpp).
    var channelCount: Int = 1

    /// Buffer size in frames per tap callback. Smaller values reduce latency.
    /// Recommended range: 512 (low latency) to 4096 (low CPU).
    var bufferSize: AVAudioFrameCount = 1024

    /// Maximum recording duration in seconds. Nil means unlimited.
    var maxDuration: TimeInterval? = nil

    /// Identifier of the input device to use. Nil selects the system default.
    var inputDeviceID: AudioDeviceID? = nil

    /// Whether to enable voice activity detection at the capture level.
    var enableVAD: Bool = true

    /// VAD energy threshold (RMS). Audio below this level is considered silence.
    var vadEnergyThreshold: Float = 0.01

    /// Seconds of silence before VAD triggers an automatic stop.
    var vadSilenceTimeout: TimeInterval = 2.0
}

/// Real-time audio level data published during capture.
struct AudioLevelInfo: Sendable {
    /// Root mean square power level, normalized 0.0 to 1.0.
    let rmsLevel: Float

    /// Peak sample value in the current buffer, normalized 0.0 to 1.0.
    let peakLevel: Float

    /// Whether the current buffer is classified as speech by VAD.
    let isSpeechDetected: Bool

    /// Accumulated recording duration in seconds.
    let elapsedTime: TimeInterval
}

/// Delegate protocol for receiving audio capture events.
protocol AudioCaptureDelegate: AnyObject, Sendable {
    /// Called on each audio buffer with level information.
    func audioCaptureService(_ service: AudioCaptureService, didUpdateLevel info: AudioLevelInfo)

    /// Called when VAD detects the transition from silence to speech.
    func audioCaptureServiceDidDetectSpeechStart(_ service: AudioCaptureService)

    /// Called when VAD detects the transition from speech to silence.
    func audioCaptureServiceDidDetectSpeechEnd(_ service: AudioCaptureService)

    /// Called when capture stops due to an error.
    func audioCaptureService(_ service: AudioCaptureService, didFailWithError error: AudioCaptureError)

    /// Called when max duration is reached and capture auto-stops.
    func audioCaptureServiceDidReachMaxDuration(_ service: AudioCaptureService)
}

/// Protocol defining the audio capture service interface.
protocol AudioCaptureService: AnyObject, Sendable {
    /// Current capture state.
    var isCapturing: Bool { get }

    /// Publisher that emits audio level info on every buffer callback.
    var audioLevelPublisher: AnyPublisher<AudioLevelInfo, Never> { get }

    /// Publisher that emits accumulated PCM samples suitable for whisper.cpp.
    var samplesPublisher: AnyPublisher<[Float], Never> { get }

    /// Delegate for event callbacks.
    var delegate: AudioCaptureDelegate? { get set }

    /// Start capturing audio with the given configuration.
    /// - Parameter configuration: Audio capture settings.
    /// - Throws: `AudioCaptureError` if microphone permission is denied or hardware is unavailable.
    func startCapture(configuration: AudioCaptureConfiguration) async throws

    /// Stop capturing and return all accumulated PCM samples.
    /// - Returns: Array of Float32 samples at the configured sample rate (default 16 kHz mono).
    func stopCapture() async -> [Float]

    /// Discard accumulated audio without returning it.
    func cancelCapture() async

    /// List available audio input devices on the system.
    /// - Returns: Array of available input devices with their identifiers and names.
    func availableInputDevices() async -> [AudioInputDevice]

    /// Set the active input device.
    /// - Parameter deviceID: The `AudioDeviceID` of the desired input device, or nil for system default.
    func setInputDevice(_ deviceID: AudioDeviceID?) async throws

    /// Get the current accumulated recording duration in seconds.
    var currentDuration: TimeInterval { get }
}
```

> 🍎 **macOS-specific**: `AudioDeviceID` is a Core Audio type (`UInt32`). On macOS, multiple input devices (built-in mic, USB mic, audio interface) can be enumerated and selected at runtime. This is not available on iOS.

### AudioCaptureService Configuration

```swift
/// Represents an available audio input device.
struct AudioInputDevice: Identifiable, Sendable {
    let id: AudioDeviceID
    let name: String
    let manufacturer: String
    let sampleRate: Double
    let channelCount: Int
    let isDefault: Bool
}
```

### Audio Level Callbacks

The service provides two mechanisms for receiving audio level data:

1. **Combine Publisher** -- use `audioLevelPublisher` for SwiftUI bindings.
2. **Delegate Callbacks** -- use `AudioCaptureDelegate` for imperative event handling.

```swift
// SwiftUI view binding example using the Combine publisher
struct AudioLevelMeter: View {
    @StateObject private var viewModel: AudioLevelViewModel

    var body: some View {
        VStack {
            ProgressView(value: viewModel.rmsLevel)
                .progressViewStyle(.linear)
            Text(viewModel.isSpeechDetected ? "Speech detected" : "Silence")
                .foregroundColor(viewModel.isSpeechDetected ? .green : .secondary)
        }
    }
}

@MainActor
final class AudioLevelViewModel: ObservableObject {
    @Published var rmsLevel: Float = 0.0
    @Published var peakLevel: Float = 0.0
    @Published var isSpeechDetected: Bool = false

    private var cancellables = Set<AnyCancellable>()

    init(audioCaptureService: AudioCaptureService) {
        audioCaptureService.audioLevelPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                self?.rmsLevel = info.rmsLevel
                self?.peakLevel = info.peakLevel
                self?.isSpeechDetected = info.isSpeechDetected
            }
            .store(in: &cancellables)
    }
}
```

### AudioCaptureService Error Types

```swift
/// Errors thrown by AudioCaptureService operations.
enum AudioCaptureError: LocalizedError, Sendable {
    /// Microphone access was denied by the user in System Settings.
    case microphonePermissionDenied

    /// The requested input device was not found or is disconnected.
    case inputDeviceNotFound(deviceID: AudioDeviceID)

    /// The input device does not support the required format.
    case formatNotSupported(sampleRate: Double, channels: Int)

    /// AVAudioEngine failed to start.
    case engineStartFailed(underlying: Error)

    /// Audio format conversion failed.
    case conversionFailed

    /// Capture is already in progress. Stop the current session first.
    case alreadyCapturing

    /// No audio data was captured (zero samples).
    case noAudioCaptured

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access denied. Enable it in System Settings > Privacy & Security > Microphone."
        case .inputDeviceNotFound(let deviceID):
            return "Audio input device \(deviceID) not found. It may have been disconnected."
        case .formatNotSupported(let rate, let channels):
            return "Audio format not supported: \(rate) Hz, \(channels) channel(s)."
        case .engineStartFailed(let underlying):
            return "Audio engine failed to start: \(underlying.localizedDescription)"
        case .conversionFailed:
            return "Audio format conversion failed."
        case .alreadyCapturing:
            return "Audio capture is already in progress."
        case .noAudioCaptured:
            return "No audio data was captured."
        }
    }
}
```

### AudioCaptureService Usage Examples

```swift
// Full lifecycle: configure, start, capture, stop
func performDictation(service: AudioCaptureService) async throws -> [Float] {
    let config = AudioCaptureConfiguration(
        sampleRate: 16000.0,
        channelCount: 1,
        bufferSize: 1024,
        maxDuration: 60.0,  // 1 minute max
        enableVAD: true,
        vadEnergyThreshold: 0.015,
        vadSilenceTimeout: 2.5
    )

    try await service.startCapture(configuration: config)

    // ... user speaks ...
    // Capture is stopped externally (hotkey release, VAD silence, or max duration)

    let samples = await service.stopCapture()

    guard !samples.isEmpty else {
        throw AudioCaptureError.noAudioCaptured
    }

    return samples
}

// Listing and selecting an input device
func selectUSBMicrophone(service: AudioCaptureService) async throws {
    let devices = await service.availableInputDevices()

    guard let usbMic = devices.first(where: { $0.name.contains("USB") }) else {
        throw AudioCaptureError.inputDeviceNotFound(deviceID: 0)
    }

    try await service.setInputDevice(usbMic.id)
}
```

> ⚠️ **Warning**: Always check microphone permissions before starting capture. On macOS 14+, the system will prompt the user automatically on first access, but subsequent calls will fail silently if permission was denied. Use `AVCaptureDevice.authorizationStatus(for: .audio)` to check.

---

## WhisperService API

The `WhisperService` wraps whisper.cpp to provide speech-to-text transcription. It supports both batch transcription (process a complete audio buffer) and streaming transcription (process audio incrementally as it arrives).

### WhisperService Protocol Definition

```swift
import Foundation

/// Parameters controlling whisper.cpp inference behavior.
struct WhisperTranscriptionParameters: Sendable {
    /// Language code for transcription (e.g., "en", "tr", "de"). Nil enables auto-detection.
    var language: String? = nil

    /// Whether to translate non-English speech to English.
    var translate: Bool = false

    /// Decoding strategy: greedy or beam search.
    var strategy: WhisperDecodingStrategy = .greedy

    /// Number of threads for CPU inference. Nil uses system optimal.
    var threadCount: Int? = nil

    /// Beam size when using beam search strategy.
    var beamSize: Int = 5

    /// Temperature for sampling. Lower values produce more deterministic output.
    var temperature: Float = 0.0

    /// Maximum segment length in characters. 0 means no limit.
    var maxSegmentLength: Int = 0

    /// Whether to suppress blank tokens.
    var suppressBlank: Bool = true

    /// Whether to suppress non-speech tokens (music, noise markers).
    var suppressNonSpeechTokens: Bool = true

    /// Entropy threshold for segment confidence filtering.
    var entropyThreshold: Float = 2.4

    /// Initial prompt to bias the decoder (e.g., domain-specific terminology).
    var initialPrompt: String? = nil

    /// Whether to use GPU (Metal) acceleration.
    var useGPU: Bool = true
}

/// Decoding strategy for whisper.cpp inference.
enum WhisperDecodingStrategy: Sendable {
    case greedy
    case beamSearch(beamSize: Int = 5, patience: Float = 1.0)
}

/// A single transcription segment with timing and confidence.
struct TranscriptionSegment: Sendable, Identifiable {
    let id: UUID
    /// Transcribed text for this segment.
    let text: String
    /// Start time offset in seconds from the beginning of the audio.
    let startTime: TimeInterval
    /// End time offset in seconds from the beginning of the audio.
    let endTime: TimeInterval
    /// Average token-level log probability. Higher (closer to 0) is more confident.
    let averageLogProb: Float
    /// Whether this segment passes the entropy confidence threshold.
    let isConfident: Bool
    /// Detected language code for this segment.
    let language: String
}

/// Full result of a transcription operation.
struct TranscriptionResult: Sendable {
    /// Complete transcribed text (all segments concatenated).
    let text: String
    /// Individual segments with timing and confidence data.
    let segments: [TranscriptionSegment]
    /// Detected language code (from the first segment or explicit setting).
    let detectedLanguage: String
    /// Average confidence across all segments (0.0 to 1.0, normalized from log probs).
    let averageConfidence: Double
    /// Total audio duration in seconds.
    let audioDuration: TimeInterval
    /// Wall-clock time spent on inference.
    let inferenceTime: TimeInterval
    /// Name of the model used for this transcription.
    let modelName: String
}

/// Protocol defining the whisper.cpp transcription service.
protocol WhisperService: AnyObject, Sendable {
    /// Whether a model is currently loaded and ready for inference.
    var isModelLoaded: Bool { get }

    /// Name of the currently loaded model, or nil if none.
    var currentModelName: String? { get }

    /// Publisher that emits partial transcription text during streaming.
    var streamingTextPublisher: AnyPublisher<String, Never> { get }

    /// Load a Whisper GGML model from disk.
    /// - Parameters:
    ///   - path: File URL to the `.bin` GGML model file.
    ///   - useGPU: Whether to enable Metal acceleration. Default is true.
    /// - Throws: `WhisperError` if the model file is invalid or cannot be loaded.
    func loadModel(at path: URL, useGPU: Bool) async throws

    /// Unload the current model and free all associated memory.
    func unloadModel() async

    /// Transcribe a complete audio buffer in one pass.
    /// - Parameters:
    ///   - samples: Array of Float32 PCM samples at 16 kHz mono.
    ///   - parameters: Transcription parameters controlling inference behavior.
    /// - Returns: A `TranscriptionResult` with full text, segments, and metadata.
    /// - Throws: `WhisperError` if no model is loaded or inference fails.
    func transcribe(
        samples: [Float],
        parameters: WhisperTranscriptionParameters
    ) async throws -> TranscriptionResult

    /// Begin streaming transcription. Audio is processed incrementally.
    /// Partial results are emitted via `streamingTextPublisher`.
    /// - Parameters:
    ///   - parameters: Transcription parameters for the streaming session.
    /// - Throws: `WhisperError` if no model is loaded or a session is already active.
    func startStreaming(parameters: WhisperTranscriptionParameters) async throws

    /// Feed audio samples into an active streaming session.
    /// - Parameter samples: Array of Float32 PCM samples at 16 kHz mono.
    /// - Throws: `WhisperError` if no streaming session is active.
    func feedSamples(_ samples: [Float]) async throws

    /// End the streaming session and return the final result.
    /// - Returns: A `TranscriptionResult` with the complete transcription.
    /// - Throws: `WhisperError` if no streaming session is active.
    func stopStreaming() async throws -> TranscriptionResult

    /// Get a list of all Whisper models available in the model directory.
    /// - Returns: Array of `WhisperModelInfo` describing each available model.
    func getAvailableModels() async -> [WhisperModelInfo]
}

/// Metadata about a Whisper model file.
struct WhisperModelInfo: Sendable, Identifiable {
    let id: String
    /// Human-readable model name (e.g., "whisper-base", "whisper-small.en").
    let name: String
    /// File URL to the model on disk.
    let path: URL
    /// File size in bytes.
    let fileSize: UInt64
    /// Number of parameters (e.g., 74_000_000 for base).
    let parameterCount: UInt64
    /// Whether this is an English-only model.
    let isEnglishOnly: Bool
    /// GGML quantization type (e.g., "f16", "q5_1", "q8_0").
    let quantization: String
}
```

### Transcription Modes

HushType supports multiple transcription quality presets that map to whisper.cpp parameter combinations:

```swift
/// Preset quality levels that configure WhisperTranscriptionParameters.
enum TranscriptionQuality: String, Sendable, CaseIterable {
    /// Fastest transcription. Best for real-time dictation with small models.
    case fast
    /// Balanced speed and accuracy. Default for most users.
    case balanced
    /// Highest accuracy. Uses beam search with larger beam width.
    case accurate

    /// Generate WhisperTranscriptionParameters for this quality preset.
    func toParameters(language: String? = nil) -> WhisperTranscriptionParameters {
        var params = WhisperTranscriptionParameters()
        params.language = language

        switch self {
        case .fast:
            params.strategy = .greedy
            params.temperature = 0.0
            params.suppressBlank = true
            params.suppressNonSpeechTokens = true
            params.entropyThreshold = 2.4
            params.threadCount = 4

        case .balanced:
            params.strategy = .beamSearch(beamSize: 3, patience: 1.0)
            params.temperature = 0.0
            params.suppressBlank = true
            params.suppressNonSpeechTokens = true
            params.entropyThreshold = 2.6
            params.threadCount = 6

        case .accurate:
            params.strategy = .beamSearch(beamSize: 5, patience: 1.0)
            params.temperature = 0.0
            params.suppressBlank = true
            params.suppressNonSpeechTokens = true
            params.entropyThreshold = 2.8
            params.threadCount = 8
        }

        return params
    }
}
```

### Streaming Transcription

Streaming transcription processes audio incrementally, emitting partial results as new audio arrives. This enables real-time display of transcribed text while the user is still speaking.

```swift
/// Example: streaming transcription with a SwiftUI view model
@MainActor
final class StreamingTranscriptionViewModel: ObservableObject {
    @Published var partialText: String = ""
    @Published var isStreaming: Bool = false

    private let whisperService: WhisperService
    private var cancellables = Set<AnyCancellable>()

    init(whisperService: WhisperService) {
        self.whisperService = whisperService

        whisperService.streamingTextPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.partialText = text
            }
            .store(in: &cancellables)
    }

    func startStreaming() async throws {
        let params = TranscriptionQuality.fast.toParameters()
        try await whisperService.startStreaming(parameters: params)
        isStreaming = true
    }

    func feedAudio(_ samples: [Float]) async throws {
        try await whisperService.feedSamples(samples)
    }

    func stopStreaming() async throws -> TranscriptionResult {
        let result = try await whisperService.stopStreaming()
        isStreaming = false
        partialText = result.text
        return result
    }
}
```

### WhisperService Model Management

```swift
// Loading a specific model
func loadWhisperModel(service: WhisperService, modelManager: ModelManager) async throws {
    let models = await service.getAvailableModels()

    guard let smallModel = models.first(where: { $0.name == "whisper-small" }) else {
        // Model not downloaded yet -- trigger download
        try await modelManager.download(modelID: "whisper-small")
        let updatedModels = await service.getAvailableModels()
        guard let downloaded = updatedModels.first(where: { $0.name == "whisper-small" }) else {
            throw WhisperError.modelNotFound(name: "whisper-small")
        }
        try await service.loadModel(at: downloaded.path, useGPU: true)
        return
    }

    try await service.loadModel(at: smallModel.path, useGPU: true)
}
```

### WhisperService Error Types

```swift
/// Errors thrown by WhisperService operations.
enum WhisperError: LocalizedError, Sendable {
    /// No model is loaded. Call loadModel() first.
    case noModelLoaded

    /// The model file at the given path could not be loaded.
    case modelLoadFailed(path: URL, reason: String)

    /// The model was not found in the models directory.
    case modelNotFound(name: String)

    /// whisper.cpp inference returned a non-zero error code.
    case inferenceFailed(code: Int32)

    /// Streaming session is already active. Stop it before starting a new one.
    case streamingAlreadyActive

    /// No streaming session is active.
    case noActiveStreamingSession

    /// Audio samples array is empty.
    case emptySamples

    /// Audio samples are not in the expected format (16 kHz mono Float32).
    case invalidSampleFormat

    var errorDescription: String? {
        switch self {
        case .noModelLoaded:
            return "No Whisper model is loaded. Please load a model before transcribing."
        case .modelLoadFailed(let path, let reason):
            return "Failed to load Whisper model at \(path.lastPathComponent): \(reason)"
        case .modelNotFound(let name):
            return "Whisper model '\(name)' was not found. Download it from the Model Manager."
        case .inferenceFailed(let code):
            return "Whisper inference failed with error code \(code)."
        case .streamingAlreadyActive:
            return "A streaming session is already active."
        case .noActiveStreamingSession:
            return "No streaming session is active."
        case .emptySamples:
            return "Cannot transcribe empty audio."
        case .invalidSampleFormat:
            return "Audio samples must be 16 kHz mono Float32 PCM."
        }
    }
}
```

### WhisperService Usage Examples

```swift
// Batch transcription: complete audio buffer
func transcribeRecording(
    whisperService: WhisperService,
    samples: [Float]
) async throws -> String {
    guard whisperService.isModelLoaded else {
        throw WhisperError.noModelLoaded
    }

    let params = TranscriptionQuality.balanced.toParameters(language: "en")
    let result = try await whisperService.transcribe(samples: samples, parameters: params)

    print("Transcribed: \(result.text)")
    print("Language: \(result.detectedLanguage)")
    print("Confidence: \(String(format: "%.1f%%", result.averageConfidence * 100))")
    print("Inference time: \(String(format: "%.2fs", result.inferenceTime))")
    print("Segments: \(result.segments.count)")

    for segment in result.segments {
        let start = String(format: "%.1f", segment.startTime)
        let end = String(format: "%.1f", segment.endTime)
        print("  [\(start)s - \(end)s] \(segment.text)")
    }

    return result.text
}
```

---

## LLMService API

The `LLMService` wraps llama.cpp (and optionally Ollama) to provide post-processing of raw transcriptions. It applies formatting, punctuation, grammar correction, structuring, and custom transformations based on the selected processing mode.

### LLMService Protocol Definition

```swift
import Foundation
import Combine

/// Parameters controlling LLM inference behavior.
struct LLMInferenceParameters: Sendable {
    /// Maximum number of tokens to generate.
    var maxTokens: Int = 512

    /// Sampling temperature. Lower values are more deterministic.
    var temperature: Float = 0.1

    /// Top-p (nucleus) sampling threshold.
    var topP: Float = 0.9

    /// Top-k sampling: number of top tokens to consider. 0 disables.
    var topK: Int = 40

    /// Repetition penalty. Values > 1.0 penalize repeated tokens.
    var repeatPenalty: Float = 1.1

    /// Number of threads for CPU inference. Nil uses system optimal.
    var threadCount: Int? = nil

    /// Whether to use GPU (Metal) for inference.
    var useGPU: Bool = true

    /// Stop sequences that terminate generation.
    var stopSequences: [String] = []

    /// Seed for reproducible output. Nil uses random seed.
    var seed: UInt32? = nil
}

/// Result of an LLM processing operation.
struct LLMProcessingResult: Sendable {
    /// The processed text output.
    let text: String
    /// Number of tokens generated.
    let tokenCount: Int
    /// Tokens per second throughput.
    let tokensPerSecond: Double
    /// Total wall-clock processing time.
    let processingTime: TimeInterval
    /// The processing mode that was applied.
    let mode: ProcessingMode
    /// The prompt template that was used.
    let templateName: String
}

/// Protocol defining the LLM post-processing service.
protocol LLMService: AnyObject, Sendable {
    /// Whether a model is currently loaded and ready.
    var isModelLoaded: Bool { get }

    /// Name of the currently loaded model, or nil.
    var currentModelName: String? { get }

    /// Estimated memory usage of the loaded model in bytes.
    var estimatedMemoryUsage: UInt64 { get }

    /// Publisher that emits token-by-token streaming output during processing.
    var streamingTokenPublisher: AnyPublisher<String, Never> { get }

    /// Load an LLM model (GGUF format) from disk.
    /// - Parameters:
    ///   - path: File URL to the `.gguf` model file.
    ///   - contextLength: Maximum context window in tokens. Default is 2048.
    ///   - gpuLayers: Number of layers to offload to GPU. Use -1 for all layers.
    /// - Throws: `LLMError` if the model cannot be loaded.
    func loadModel(at path: URL, contextLength: Int, gpuLayers: Int) async throws

    /// Unload the current model and free resources.
    func unloadModel() async

    /// Process raw transcription text using the specified mode.
    /// - Parameters:
    ///   - text: The raw transcription text from WhisperService.
    ///   - mode: The processing mode defining what transformation to apply.
    ///   - parameters: Inference parameters controlling generation behavior.
    ///   - context: Optional application context (app name, field type, etc.).
    /// - Returns: An `LLMProcessingResult` with the processed text and metadata.
    /// - Throws: `LLMError` if no model is loaded or inference fails.
    func process(
        text: String,
        mode: ProcessingMode,
        parameters: LLMInferenceParameters,
        context: ApplicationContext?
    ) async throws -> LLMProcessingResult

    /// Process text with a custom prompt template string.
    /// - Parameters:
    ///   - text: The raw text to process.
    ///   - template: A prompt template string with `{{input}}` placeholder.
    ///   - parameters: Inference parameters.
    /// - Returns: An `LLMProcessingResult`.
    /// - Throws: `LLMError` if no model is loaded or inference fails.
    func processWithTemplate(
        text: String,
        template: String,
        parameters: LLMInferenceParameters
    ) async throws -> LLMProcessingResult

    /// Set the active prompt template for a given processing mode.
    /// - Parameters:
    ///   - template: The prompt template string.
    ///   - mode: The processing mode this template applies to.
    func setTemplate(_ template: String, for mode: ProcessingMode)

    /// Get the current prompt template for a given processing mode.
    /// - Parameter mode: The processing mode to query.
    /// - Returns: The current template string.
    func getTemplate(for mode: ProcessingMode) -> String

    /// Get all available LLM models in the model directory.
    /// - Returns: Array of `LLMModelInfo` for each available model.
    func getAvailableModels() async -> [LLMModelInfo]
}

/// Metadata about an LLM model file.
struct LLMModelInfo: Sendable, Identifiable {
    let id: String
    /// Human-readable model name (e.g., "Llama-3.2-3B-Q4_K_M").
    let name: String
    /// File URL to the GGUF file on disk.
    let path: URL
    /// File size in bytes.
    let fileSize: UInt64
    /// Parameter count (e.g., 3_000_000_000 for 3B).
    let parameterCount: UInt64
    /// Quantization type (e.g., "Q4_K_M", "Q5_1", "Q8_0").
    let quantization: String
    /// Context length the model supports.
    let contextLength: Int
    /// Model architecture (e.g., "llama", "qwen2", "phi3").
    let architecture: String
}
```

### Processing Modes

HushType defines six built-in processing modes. Each mode uses a specialized prompt template to transform the raw transcription.

```swift
/// Processing modes available for LLM post-processing.
enum ProcessingMode: String, Sendable, CaseIterable, Identifiable {
    /// No LLM processing. Pass through the raw whisper.cpp output as-is.
    case raw

    /// Basic cleanup: fix punctuation, capitalization, and remove filler words.
    case clean

    /// Structure the text: add paragraphs, headers, bullet points as appropriate.
    case structure

    /// Apply a user-defined prompt to transform the text.
    case prompt

    /// Optimize the text as source code or a code-related response.
    case code

    /// Use a fully custom prompt template defined by the user.
    case custom

    var id: String { rawValue }

    /// Human-readable display name.
    var displayName: String {
        switch self {
        case .raw: return "Raw"
        case .clean: return "Clean"
        case .structure: return "Structure"
        case .prompt: return "Prompt"
        case .code: return "Code"
        case .custom: return "Custom"
        }
    }

    /// Default prompt template for this mode.
    /// The placeholder `{{input}}` is replaced with the raw transcription text.
    /// The placeholder `{{context}}` is replaced with application context (if available).
    var defaultTemplate: String {
        switch self {
        case .raw:
            return "{{input}}"
        case .clean:
            return """
            Fix the punctuation, capitalization, and grammar of the following transcribed \
            speech. Remove filler words like "um", "uh", "like", "you know". \
            Output only the corrected text with no explanation.

            {{input}}
            """
        case .structure:
            return """
            Organize the following transcribed speech into well-structured text. \
            Add paragraph breaks, headers where appropriate, and bullet points for lists. \
            Fix punctuation and grammar. Output only the structured text.

            {{input}}
            """
        case .prompt:
            return """
            {{context}}

            Based on the above context, respond to the following transcribed speech. \
            Be concise and helpful.

            {{input}}
            """
        case .code:
            return """
            The following is transcribed speech describing code or a programming task. \
            Convert it into clean, correct source code. If the language is not specified, \
            infer it from context. Output only the code with no explanation or markdown.

            {{input}}
            """
        case .custom:
            return "{{input}}"
        }
    }
}
```

### Template System

```swift
/// Application context passed to the LLM for app-aware processing.
struct ApplicationContext: Sendable {
    /// Bundle identifier of the frontmost application (e.g., "com.apple.dt.Xcode").
    let bundleIdentifier: String?
    /// Display name of the frontmost application (e.g., "Xcode").
    let applicationName: String?
    /// Type of the focused text field (e.g., "code editor", "search bar", "email body").
    let fieldType: String?
    /// The application-specific prompt template override, if configured.
    let appSpecificTemplate: String?

    /// Format this context into a string suitable for injection into a prompt template.
    func toPromptString() -> String {
        var parts: [String] = []
        if let name = applicationName {
            parts.append("Active application: \(name)")
        }
        if let field = fieldType {
            parts.append("Field type: \(field)")
        }
        return parts.joined(separator: "\n")
    }
}

/// Prompt template engine that resolves placeholders.
struct PromptTemplateEngine {
    /// Resolve a prompt template by replacing placeholders with actual values.
    /// - Parameters:
    ///   - template: The prompt template string with `{{input}}` and `{{context}}` placeholders.
    ///   - input: The raw transcription text.
    ///   - context: Optional application context.
    /// - Returns: The resolved prompt string ready for LLM inference.
    static func resolve(
        template: String,
        input: String,
        context: ApplicationContext? = nil
    ) -> String {
        var resolved = template
        resolved = resolved.replacingOccurrences(of: "{{input}}", with: input)
        resolved = resolved.replacingOccurrences(
            of: "{{context}}",
            with: context?.toPromptString() ?? ""
        )
        return resolved
    }
}
```

### LLMService Error Types

```swift
/// Errors thrown by LLMService operations.
enum LLMError: LocalizedError, Sendable {
    /// No model is loaded. Call loadModel() first.
    case noModelLoaded

    /// The model file could not be loaded.
    case modelLoadFailed(path: URL, reason: String)

    /// llama.cpp context creation failed (usually insufficient memory).
    case contextCreationFailed(contextLength: Int)

    /// Inference returned no output tokens.
    case emptyOutput

    /// Inference was cancelled (e.g., user pressed stop).
    case cancelled

    /// The prompt exceeds the model's context window.
    case promptTooLong(tokenCount: Int, maxTokens: Int)

    /// The prompt template is invalid (missing {{input}} placeholder).
    case invalidTemplate(reason: String)

    /// The requested processing mode is not available.
    case modeNotAvailable(mode: ProcessingMode)

    /// Backend-specific error from llama.cpp or Ollama.
    case backendError(String)

    var errorDescription: String? {
        switch self {
        case .noModelLoaded:
            return "No LLM model is loaded. Please load a model in Settings."
        case .modelLoadFailed(let path, let reason):
            return "Failed to load LLM model at \(path.lastPathComponent): \(reason)"
        case .contextCreationFailed(let length):
            return "Failed to create context with length \(length). The system may not have enough memory."
        case .emptyOutput:
            return "The LLM produced no output."
        case .cancelled:
            return "LLM processing was cancelled."
        case .promptTooLong(let count, let max):
            return "Prompt is \(count) tokens but the model only supports \(max)."
        case .invalidTemplate(let reason):
            return "Invalid prompt template: \(reason)"
        case .modeNotAvailable(let mode):
            return "Processing mode '\(mode.displayName)' is not available."
        case .backendError(let message):
            return "LLM backend error: \(message)"
        }
    }
}
```

### LLMService Usage Examples

```swift
// Basic post-processing with the Clean mode
func cleanTranscription(
    llmService: LLMService,
    rawText: String
) async throws -> String {
    let params = LLMInferenceParameters(
        maxTokens: 512,
        temperature: 0.1,
        topP: 0.9
    )

    let result = try await llmService.process(
        text: rawText,
        mode: .clean,
        parameters: params,
        context: nil
    )

    print("Processed in \(String(format: "%.2fs", result.processingTime))")
    print("Throughput: \(String(format: "%.1f", result.tokensPerSecond)) tokens/sec")

    return result.text
}

// App-aware processing using application context
func processForActiveApp(
    llmService: LLMService,
    rawText: String,
    activeApp: NSRunningApplication
) async throws -> String {
    let context = ApplicationContext(
        bundleIdentifier: activeApp.bundleIdentifier,
        applicationName: activeApp.localizedName,
        fieldType: nil,
        appSpecificTemplate: nil
    )

    let result = try await llmService.process(
        text: rawText,
        mode: .clean,
        parameters: LLMInferenceParameters(),
        context: context
    )

    return result.text
}

// Custom template processing
func processWithCustomTemplate(
    llmService: LLMService,
    rawText: String
) async throws -> String {
    let template = """
    Translate the following English text to formal German. \
    Output only the translation.

    {{input}}
    """

    let result = try await llmService.processWithTemplate(
        text: rawText,
        template: template,
        parameters: LLMInferenceParameters(maxTokens: 1024, temperature: 0.3)
    )

    return result.text
}

// Streaming token output for real-time display
@MainActor
final class LLMStreamingViewModel: ObservableObject {
    @Published var outputText: String = ""

    private let llmService: LLMService
    private var cancellables = Set<AnyCancellable>()

    init(llmService: LLMService) {
        self.llmService = llmService

        llmService.streamingTokenPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] token in
                self?.outputText += token
            }
            .store(in: &cancellables)
    }
}
```

> 💡 **Tip**: For the `code` processing mode, set `temperature: 0.0` for deterministic code generation. For creative writing tasks in `custom` mode, use `temperature: 0.7` or higher.

---

## TextInjectionService API

The `TextInjectionService` handles typing processed text into the user's active application. It uses a dual-strategy approach: CGEvent keystroke simulation for short text and clipboard paste for long text.

### TextInjectionService Protocol Definition

```swift
import CoreGraphics
import AppKit

/// Strategy for injecting text into the target application.
enum InjectionStrategy: Sendable {
    /// Simulate individual keystrokes via CGEvent. Best for short text.
    case keystroke
    /// Copy to clipboard and simulate Cmd+V. Best for long text.
    case clipboard
    /// Automatically select the best strategy based on text length.
    case automatic
    /// Use the macOS Accessibility API to set the value directly.
    case accessibility
}

/// Configuration for text injection behavior.
struct InjectionConfiguration: Sendable {
    /// Strategy to use. Default is automatic.
    var strategy: InjectionStrategy = .automatic

    /// Character count threshold for switching from keystroke to clipboard in automatic mode.
    var clipboardThreshold: Int = 50

    /// Delay in milliseconds between simulated keystrokes.
    var keystrokeDelay: UInt32 = 1000

    /// Delay in milliseconds after pasting before restoring the clipboard.
    var clipboardRestoreDelay: UInt64 = 150

    /// Whether to preserve and restore the clipboard contents after paste injection.
    var preserveClipboard: Bool = true

    /// Whether to add a trailing space after injected text.
    var appendTrailingSpace: Bool = false

    /// Whether to add a newline after injected text.
    var appendNewline: Bool = false
}

/// Information about the currently focused text field.
struct ActiveFieldInfo: Sendable {
    /// The accessibility role of the focused element (e.g., "AXTextField", "AXTextArea").
    let role: String?
    /// The current value/content of the focused field.
    let currentValue: String?
    /// The position of the insertion point (caret) in the field.
    let insertionPoint: Int?
    /// The bundle identifier of the application owning the field.
    let applicationBundleID: String?
    /// Whether the field appears to be editable.
    let isEditable: Bool
    /// A description of the field type inferred from accessibility attributes.
    let fieldDescription: String?
}

/// Result of a text injection operation.
struct InjectionResult: Sendable {
    /// Whether the injection completed without errors.
    let success: Bool
    /// The strategy that was actually used.
    let strategyUsed: InjectionStrategy
    /// Number of characters injected.
    let characterCount: Int
    /// Time taken for the injection in seconds.
    let injectionTime: TimeInterval
}

/// Protocol defining the text injection service.
protocol TextInjectionService: AnyObject, Sendable {
    /// Inject text at the current cursor position using the configured strategy.
    /// - Parameters:
    ///   - text: The text to inject.
    ///   - configuration: Injection behavior settings.
    /// - Returns: An `InjectionResult` describing what happened.
    /// - Throws: `TextInjectionError` if accessibility permissions are missing or injection fails.
    func injectText(
        _ text: String,
        configuration: InjectionConfiguration
    ) async throws -> InjectionResult

    /// Inject text via the clipboard (Cmd+V paste).
    /// Preserves and restores previous clipboard contents.
    /// - Parameter text: The text to inject.
    /// - Throws: `TextInjectionError` if the operation fails.
    func injectViaClipboard(_ text: String) async throws

    /// Inject text via simulated keystrokes (CGEvent).
    /// - Parameter text: The text to inject character by character.
    /// - Throws: `TextInjectionError` if accessibility permissions are missing.
    func injectViaKeystrokes(_ text: String) async throws

    /// Detect and return information about the currently focused text field.
    /// - Returns: An `ActiveFieldInfo` describing the focused element, or nil if none is focused.
    func detectActiveField() async -> ActiveFieldInfo?

    /// Check whether HushType has the required Accessibility permission.
    /// - Returns: True if accessibility access is granted.
    func hasAccessibilityPermission() -> Bool

    /// Request the Accessibility permission from the user.
    /// Opens the system prompt dialog.
    func requestAccessibilityPermission()
}
```

### Injection Strategies

```
┌───────────────────────────────────────────────────────────────┐
│                   Injection Strategy Selection                  │
│                                                                 │
│   Input text ──▶ Length check                                   │
│                    │                                            │
│                    ├── < 50 chars ──▶ CGEvent Keystrokes        │
│                    │                  • Character-by-character   │
│                    │                  • 1ms delay between keys   │
│                    │                  • Full Unicode support     │
│                    │                                            │
│                    └── >= 50 chars ─▶ Clipboard Paste           │
│                                      • Save current clipboard   │
│                                      • Set text to clipboard    │
│                                      • Simulate Cmd+V           │
│                                      • Restore clipboard (150ms)│
│                                                                 │
│   Override: InjectionStrategy.keystroke / .clipboard / .a11y    │
└───────────────────────────────────────────────────────────────┘
```

### Active Field Detection

```swift
// Detecting the active field before injection
func injectWithFieldAwareness(
    injectionService: TextInjectionService,
    text: String
) async throws {
    guard injectionService.hasAccessibilityPermission() else {
        injectionService.requestAccessibilityPermission()
        throw TextInjectionError.accessibilityPermissionDenied
    }

    if let fieldInfo = await injectionService.detectActiveField() {
        print("Target app: \(fieldInfo.applicationBundleID ?? "unknown")")
        print("Field role: \(fieldInfo.role ?? "unknown")")
        print("Is editable: \(fieldInfo.isEditable)")

        guard fieldInfo.isEditable else {
            throw TextInjectionError.fieldNotEditable
        }
    }

    let config = InjectionConfiguration(
        strategy: .automatic,
        clipboardThreshold: 50,
        preserveClipboard: true
    )

    let result = try await injectionService.injectText(text, configuration: config)
    print("Injected \(result.characterCount) chars via \(result.strategyUsed)")
}
```

### TextInjectionService Error Types

```swift
/// Errors thrown by TextInjectionService operations.
enum TextInjectionError: LocalizedError, Sendable {
    /// Accessibility permission is not granted.
    case accessibilityPermissionDenied

    /// The focused field is not editable.
    case fieldNotEditable

    /// CGEvent creation failed.
    case eventCreationFailed

    /// Clipboard operation failed.
    case clipboardFailed

    /// No focused application or text field was detected.
    case noFocusedField

    /// The text to inject is empty.
    case emptyText

    /// Keystroke injection timed out.
    case timeout(after: TimeInterval)

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionDenied:
            return "Accessibility permission is required. Enable HushType in System Settings > Privacy & Security > Accessibility."
        case .fieldNotEditable:
            return "The focused field is not editable."
        case .eventCreationFailed:
            return "Failed to create CGEvent for keystroke simulation."
        case .clipboardFailed:
            return "Clipboard operation failed."
        case .noFocusedField:
            return "No focused text field was detected."
        case .emptyText:
            return "Cannot inject empty text."
        case .timeout(let seconds):
            return "Text injection timed out after \(String(format: "%.1f", seconds)) seconds."
        }
    }
}
```

### TextInjectionService Usage Examples

```swift
// Automatic strategy selection
func injectTranscription(
    service: TextInjectionService,
    processedText: String
) async throws {
    let config = InjectionConfiguration(
        strategy: .automatic,
        clipboardThreshold: 50,
        preserveClipboard: true,
        appendTrailingSpace: true
    )

    let result = try await service.injectText(processedText, configuration: config)

    if result.success {
        print("Injected \(result.characterCount) characters via \(result.strategyUsed)")
    }
}

// Force clipboard injection for a code block
func injectCodeBlock(
    service: TextInjectionService,
    code: String
) async throws {
    let config = InjectionConfiguration(
        strategy: .clipboard,
        preserveClipboard: true,
        appendNewline: true
    )

    _ = try await service.injectText(code, configuration: config)
}
```

> 🔒 **Security**: CGEvent posting requires the Accessibility permission (`kAXTrustedCheckOptionPrompt`). HushType checks this permission at startup and guides the user through System Settings > Privacy & Security > Accessibility if it is not yet granted.

> ⚠️ **Warning**: The clipboard paste strategy temporarily overwrites the system clipboard. Although the previous contents are restored after a short delay (default 150ms), clipboard manager apps may capture the intermediate state. The `preserveClipboard` flag controls this behavior.

---

## CommandParser API

The `CommandParser` detects and executes voice commands embedded in transcribed text. Commands are prefixed with trigger phrases (e.g., "hushtype", "command", "hey type") and can control the application, switch modes, or trigger actions.

### CommandParser Protocol Definition

```swift
import Foundation

/// A recognized voice command with its arguments.
struct ParsedCommand: Sendable {
    /// The command identifier (e.g., "switch_mode", "undo", "select_all").
    let commandID: String
    /// Human-readable command name.
    let commandName: String
    /// Parsed arguments extracted from the voice input.
    let arguments: [String: String]
    /// The original text that triggered this command.
    let originalText: String
    /// Confidence score for the command match (0.0 to 1.0).
    let confidence: Double
}

/// Result of parsing text for voice commands.
enum ParseResult: Sendable {
    /// The text contains a recognized command.
    case command(ParsedCommand)
    /// The text is regular dictation content, not a command.
    case dictation(String)
    /// The text is ambiguous -- could be a command or dictation.
    case ambiguous(command: ParsedCommand, dictation: String)
}

/// Definition of a registerable voice command.
struct CommandDefinition: Sendable, Identifiable {
    let id: String
    /// Human-readable command name.
    let name: String
    /// Trigger phrases that activate this command (case-insensitive).
    let triggerPhrases: [String]
    /// Description of what the command does.
    let description: String
    /// Whether this command accepts arguments.
    let hasArguments: Bool
    /// The action category this command belongs to.
    let category: CommandCategory
}

/// Categories for organizing commands.
enum CommandCategory: String, Sendable, CaseIterable {
    case mode       // Mode switching commands
    case editing    // Text editing commands (undo, select all, etc.)
    case app        // Application control commands (pause, stop, settings)
    case navigation // Navigation commands (scroll, tab switch)
    case system     // System commands (volume, brightness)
    case custom     // User-defined commands
}

/// Handler closure type for command execution.
typealias CommandHandler = @Sendable (ParsedCommand) async throws -> Void

/// Protocol defining the voice command parser.
protocol CommandParser: AnyObject, Sendable {
    /// Parse transcribed text to determine if it contains a voice command.
    /// - Parameter text: The transcribed text to analyze.
    /// - Returns: A `ParseResult` indicating whether a command was found.
    func parse(_ text: String) -> ParseResult

    /// Register a new voice command with its handler.
    /// - Parameters:
    ///   - definition: The command definition including trigger phrases.
    ///   - handler: The async closure to execute when the command is recognized.
    func registerCommand(
        _ definition: CommandDefinition,
        handler: @escaping CommandHandler
    )

    /// Unregister a previously registered command.
    /// - Parameter commandID: The identifier of the command to remove.
    func unregisterCommand(_ commandID: String)

    /// Get all currently registered commands.
    /// - Returns: Array of `CommandDefinition` for all registered commands.
    func getAvailableCommands() -> [CommandDefinition]

    /// Get registered commands filtered by category.
    /// - Parameter category: The category to filter by.
    /// - Returns: Array of `CommandDefinition` in the given category.
    func getCommands(in category: CommandCategory) -> [CommandDefinition]

    /// Execute a parsed command by invoking its registered handler.
    /// - Parameter command: The parsed command to execute.
    /// - Throws: `CommandError` if the command has no registered handler.
    func execute(_ command: ParsedCommand) async throws

    /// Set the trigger prefix phrase that activates command mode.
    /// - Parameter prefix: The prefix phrase (e.g., "hushtype", "command").
    func setTriggerPrefix(_ prefix: String)

    /// Get the current trigger prefix.
    var triggerPrefix: String { get }

    /// Set the minimum confidence threshold for command recognition.
    /// - Parameter threshold: A value between 0.0 and 1.0.
    func setConfidenceThreshold(_ threshold: Double)
}
```

### Built-in Commands

HushType ships with the following built-in voice commands:

| Command ID | Trigger Phrases | Category | Description |
|---|---|---|---|
| `switch_mode_raw` | "switch to raw", "raw mode" | mode | Switch to Raw processing mode |
| `switch_mode_clean` | "switch to clean", "clean mode" | mode | Switch to Clean processing mode |
| `switch_mode_structure` | "switch to structure", "structure mode" | mode | Switch to Structure processing mode |
| `switch_mode_code` | "switch to code", "code mode" | mode | Switch to Code processing mode |
| `undo` | "undo", "undo that" | editing | Undo the last text injection |
| `select_all` | "select all", "select everything" | editing | Select all text in the active field |
| `new_line` | "new line", "next line" | editing | Insert a newline character |
| `new_paragraph` | "new paragraph", "next paragraph" | editing | Insert a double newline |
| `stop_dictation` | "stop dictation", "stop listening" | app | Stop the current dictation session |
| `pause_dictation` | "pause", "pause dictation" | app | Pause without stopping |
| `open_settings` | "open settings", "show settings" | app | Open the HushType settings window |

### Custom Command Registration

```swift
// Registering a custom voice command
func registerCustomCommands(parser: CommandParser) {
    // Register a command to insert the current date
    let dateCommand = CommandDefinition(
        id: "insert_date",
        name: "Insert Date",
        triggerPhrases: ["insert date", "today's date", "current date"],
        description: "Insert the current date at the cursor position",
        hasArguments: false,
        category: .custom
    )

    parser.registerCommand(dateCommand) { command in
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        let dateString = formatter.string(from: Date())
        // Inject the date string via TextInjectionService
        // (service reference would be captured in a real implementation)
        print("Inserting date: \(dateString)")
    }

    // Register a command with arguments
    let languageCommand = CommandDefinition(
        id: "set_language",
        name: "Set Language",
        triggerPhrases: ["set language to", "switch language to"],
        description: "Set the transcription language",
        hasArguments: true,
        category: .app
    )

    parser.registerCommand(languageCommand) { command in
        if let language = command.arguments["language"] {
            print("Switching language to: \(language)")
        }
    }
}
```

### CommandParser Error Types

```swift
/// Errors thrown by CommandParser operations.
enum CommandError: LocalizedError, Sendable {
    /// No handler is registered for the given command.
    case noHandler(commandID: String)

    /// The command handler threw an error during execution.
    case executionFailed(commandID: String, underlying: Error)

    /// A command with this ID is already registered.
    case duplicateCommand(commandID: String)

    /// The trigger prefix is invalid (empty or too long).
    case invalidTriggerPrefix(String)

    var errorDescription: String? {
        switch self {
        case .noHandler(let id):
            return "No handler registered for command '\(id)'."
        case .executionFailed(let id, let error):
            return "Command '\(id)' failed: \(error.localizedDescription)"
        case .duplicateCommand(let id):
            return "A command with ID '\(id)' is already registered."
        case .invalidTriggerPrefix(let prefix):
            return "Invalid trigger prefix: '\(prefix)'."
        }
    }
}
```

### CommandParser Usage Examples

```swift
// Parsing and executing voice commands in the transcription pipeline
func handleTranscription(
    parser: CommandParser,
    whisperOutput: String
) async throws -> String? {
    let parseResult = parser.parse(whisperOutput)

    switch parseResult {
    case .command(let command):
        print("Detected command: \(command.commandName) (confidence: \(command.confidence))")
        try await parser.execute(command)
        return nil  // Command handled, no text to inject

    case .dictation(let text):
        return text  // Regular text, pass to LLM processing

    case .ambiguous(let command, let dictation):
        if command.confidence > 0.8 {
            try await parser.execute(command)
            return nil
        } else {
            return dictation  // Low confidence, treat as dictation
        }
    }
}

// Listing available commands for a settings UI
func displayCommandList(parser: CommandParser) {
    for category in CommandCategory.allCases {
        let commands = parser.getCommands(in: category)
        guard !commands.isEmpty else { continue }

        print("\n--- \(category.rawValue.capitalized) Commands ---")
        for cmd in commands {
            let triggers = cmd.triggerPhrases.joined(separator: ", ")
            print("  \(cmd.name): \"\(triggers)\"")
            print("    \(cmd.description)")
        }
    }
}
```

---

## HotkeyManager API

The `HotkeyManager` handles global keyboard shortcuts for starting and stopping dictation, switching modes, and other application actions. It uses the macOS Carbon event tap API for global hotkey registration.

### HotkeyManager Protocol Definition

```swift
import Carbon
import AppKit

/// A key combination representing a global hotkey.
struct KeyBinding: Sendable, Equatable, Codable {
    /// The key code (Carbon virtual key code).
    let keyCode: UInt32
    /// Modifier flags (command, option, control, shift).
    let modifiers: NSEvent.ModifierFlags

    /// Human-readable representation (e.g., "Ctrl+Shift+Space").
    var displayString: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("Ctrl") }
        if modifiers.contains(.option) { parts.append("Option") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        if modifiers.contains(.command) { parts.append("Cmd") }
        parts.append(keyCodeToString(keyCode))
        return parts.joined(separator: "+")
    }
}

/// Actions that can be bound to hotkeys.
enum HotkeyAction: String, Sendable, CaseIterable, Codable {
    /// Toggle dictation on/off (push-to-talk or toggle).
    case toggleDictation
    /// Hold to dictate, release to stop (push-to-talk).
    case pushToTalk
    /// Cancel the current dictation without injecting text.
    case cancelDictation
    /// Cycle through processing modes (Raw -> Clean -> Structure -> ...).
    case cycleMode
    /// Switch to a specific processing mode.
    case switchToRaw
    case switchToClean
    case switchToStructure
    case switchToCode
    /// Open or focus the HushType overlay/menu.
    case openOverlay
    /// Open the settings window.
    case openSettings
}

/// How the hotkey triggers behavior.
enum HotkeyActivationMode: String, Sendable, Codable {
    /// Action triggers on key press. A second press toggles off.
    case toggle
    /// Action triggers while key is held. Releasing the key stops the action.
    case holdToActivate
    /// Action triggers once on key press. No toggle behavior.
    case singlePress
}

/// A registered hotkey binding with its configuration.
struct HotkeyRegistration: Sendable, Identifiable {
    let id: String
    let action: HotkeyAction
    let keyBinding: KeyBinding
    let activationMode: HotkeyActivationMode
    let isEnabled: Bool
}

/// Delegate for receiving hotkey events.
protocol HotkeyDelegate: AnyObject, Sendable {
    /// A registered hotkey was pressed.
    func hotkeyManager(_ manager: HotkeyManager, didTriggerAction action: HotkeyAction)

    /// A push-to-talk hotkey was released.
    func hotkeyManager(_ manager: HotkeyManager, didReleaseAction action: HotkeyAction)

    /// A hotkey registration failed due to a conflict.
    func hotkeyManager(
        _ manager: HotkeyManager,
        didEncounterConflict action: HotkeyAction,
        conflictingApp: String?
    )
}

/// Protocol defining the global hotkey manager.
protocol HotkeyManager: AnyObject, Sendable {
    /// Delegate for hotkey events.
    var delegate: HotkeyDelegate? { get set }

    /// Register a global hotkey for the specified action.
    /// - Parameters:
    ///   - action: The action to bind.
    ///   - keyBinding: The key combination to register.
    ///   - activationMode: How the hotkey triggers (toggle, hold, single press).
    /// - Throws: `HotkeyError` if the binding conflicts with another app or system shortcut.
    func register(
        action: HotkeyAction,
        keyBinding: KeyBinding,
        activationMode: HotkeyActivationMode
    ) throws

    /// Unregister the hotkey for the specified action.
    /// - Parameter action: The action whose hotkey should be removed.
    func unregister(action: HotkeyAction)

    /// Unregister all hotkeys.
    func unregisterAll()

    /// Set the activation mode for dictation hotkeys.
    /// - Parameter mode: `.toggle` for press-on/press-off, `.holdToActivate` for push-to-talk.
    func setMode(_ mode: HotkeyActivationMode, for action: HotkeyAction)

    /// Get the current key binding for an action, if registered.
    /// - Parameter action: The action to look up.
    /// - Returns: The current `HotkeyRegistration`, or nil if not registered.
    func getRegistration(for action: HotkeyAction) -> HotkeyRegistration?

    /// Get all currently registered hotkeys.
    /// - Returns: Array of all registered `HotkeyRegistration` entries.
    func getAllRegistrations() -> [HotkeyRegistration]

    /// Check whether a key binding conflicts with existing registrations or system shortcuts.
    /// - Parameter keyBinding: The key combination to check.
    /// - Returns: A description of the conflict, or nil if no conflict.
    func checkConflict(for keyBinding: KeyBinding) -> String?

    /// Temporarily disable all hotkeys (e.g., when the key binding editor is active).
    func suspendAll()

    /// Re-enable all hotkeys after a suspension.
    func resumeAll()
}
```

### Key Binding Configuration

```swift
/// Default key bindings shipped with HushType.
extension KeyBinding {
    /// Default: Ctrl+Shift+Space for dictation toggle/push-to-talk.
    static let defaultDictation = KeyBinding(
        keyCode: UInt32(kVK_Space),
        modifiers: [.control, .shift]
    )

    /// Default: Ctrl+Shift+Escape for cancelling dictation.
    static let defaultCancel = KeyBinding(
        keyCode: UInt32(kVK_Escape),
        modifiers: [.control, .shift]
    )

    /// Default: Ctrl+Shift+M for cycling processing modes.
    static let defaultCycleMode = KeyBinding(
        keyCode: UInt32(kVK_ANSI_M),
        modifiers: [.control, .shift]
    )

    /// Default: Ctrl+Shift+O for opening the overlay.
    static let defaultOverlay = KeyBinding(
        keyCode: UInt32(kVK_ANSI_O),
        modifiers: [.control, .shift]
    )
}
```

### Mode Switching

```swift
// Setting up hotkeys with mode switching
func configureHotkeys(manager: HotkeyManager) throws {
    // Primary dictation hotkey: push-to-talk
    try manager.register(
        action: .pushToTalk,
        keyBinding: .defaultDictation,
        activationMode: .holdToActivate
    )

    // Cancel hotkey
    try manager.register(
        action: .cancelDictation,
        keyBinding: .defaultCancel,
        activationMode: .singlePress
    )

    // Mode cycling
    try manager.register(
        action: .cycleMode,
        keyBinding: .defaultCycleMode,
        activationMode: .singlePress
    )

    // Switch mode between toggle and push-to-talk
    manager.setMode(.toggle, for: .toggleDictation)
}
```

### HotkeyManager Error Types

```swift
/// Errors thrown by HotkeyManager operations.
enum HotkeyError: LocalizedError, Sendable {
    /// The key binding conflicts with another registered hotkey.
    case conflict(action: HotkeyAction, existingAction: HotkeyAction)

    /// The key binding conflicts with a system keyboard shortcut.
    case systemConflict(keyBinding: KeyBinding, systemShortcut: String)

    /// Failed to register the Carbon event handler.
    case registrationFailed(reason: String)

    /// Accessibility permission is required for global hotkey monitoring.
    case accessibilityRequired

    /// The specified action does not have a registered hotkey.
    case notRegistered(action: HotkeyAction)

    var errorDescription: String? {
        switch self {
        case .conflict(let action, let existing):
            return "Key binding for '\(action)' conflicts with '\(existing)'."
        case .systemConflict(let binding, let shortcut):
            return "Key binding \(binding.displayString) conflicts with system shortcut '\(shortcut)'."
        case .registrationFailed(let reason):
            return "Hotkey registration failed: \(reason)"
        case .accessibilityRequired:
            return "Accessibility permission is required for global hotkeys."
        case .notRegistered(let action):
            return "No hotkey is registered for '\(action)'."
        }
    }
}
```

### HotkeyManager Usage Examples

```swift
// Implementing the hotkey delegate
final class DictationController: HotkeyDelegate {
    private let pipeline: TranscriptionPipeline

    func hotkeyManager(_ manager: HotkeyManager, didTriggerAction action: HotkeyAction) {
        Task {
            switch action {
            case .toggleDictation, .pushToTalk:
                if pipeline.isRecording {
                    await pipeline.stopAndProcess()
                } else {
                    try await pipeline.startTranscription()
                }

            case .cancelDictation:
                await pipeline.cancel()

            case .cycleMode:
                pipeline.cycleToNextMode()

            case .openOverlay:
                await MainActor.run { OverlayManager.shared.toggle() }

            default:
                break
            }
        }
    }

    func hotkeyManager(_ manager: HotkeyManager, didReleaseAction action: HotkeyAction) {
        if action == .pushToTalk {
            Task { await pipeline.stopAndProcess() }
        }
    }

    func hotkeyManager(
        _ manager: HotkeyManager,
        didEncounterConflict action: HotkeyAction,
        conflictingApp: String?
    ) {
        let app = conflictingApp ?? "another application"
        print("Hotkey conflict: \(action) is already used by \(app)")
    }
}

// Checking for conflicts before registering
func registerSafely(
    manager: HotkeyManager,
    action: HotkeyAction,
    binding: KeyBinding
) throws {
    if let conflict = manager.checkConflict(for: binding) {
        throw HotkeyError.systemConflict(keyBinding: binding, systemShortcut: conflict)
    }

    try manager.register(
        action: action,
        keyBinding: binding,
        activationMode: .holdToActivate
    )
}
```

> 🍎 **macOS-specific**: Global hotkey registration uses the Carbon `InstallEventHandler` API. Although Carbon is considered legacy, it remains the only supported way to intercept global key events on macOS without requiring full Accessibility API access. The `CGEvent` tap approach is an alternative but requires additional permissions.

---

## ModelManager API

The `ModelManager` handles downloading, verifying, storing, and deleting ML models (both Whisper and LLM). It manages the model lifecycle from the remote registry to the local file system.

### ModelManager Protocol Definition

```swift
import Foundation
import Combine

/// Type of ML model.
enum ModelType: String, Sendable, Codable {
    case whisper
    case llm
}

/// Current state of a model in the local store.
enum ModelState: Sendable {
    /// Model is available for download but not yet downloaded.
    case available
    /// Model is currently being downloaded.
    case downloading(progress: Double)
    /// Model is downloaded and ready to use.
    case installed
    /// Model download or verification failed.
    case failed(error: String)
    /// Model is being deleted.
    case deleting
}

/// Information about a model in the registry (remote or local).
struct ModelDescriptor: Sendable, Identifiable {
    let id: String
    /// Human-readable name (e.g., "Whisper Small", "Llama 3.2 3B Q4_K_M").
    let name: String
    /// Model type: whisper or llm.
    let type: ModelType
    /// File size in bytes.
    let fileSize: UInt64
    /// Download URL.
    let downloadURL: URL
    /// SHA256 hash for integrity verification.
    let sha256: String
    /// Short description of the model.
    let description: String
    /// Number of parameters.
    let parameterCount: UInt64
    /// Quantization type (e.g., "q5_1", "Q4_K_M").
    let quantization: String
    /// Minimum recommended system RAM in bytes.
    let minimumRAM: UInt64
    /// Whether this model is recommended for the user's hardware.
    let isRecommended: Bool
    /// Current state in the local store.
    var state: ModelState
}

/// Progress update during model download.
struct DownloadProgress: Sendable {
    /// Model identifier.
    let modelID: String
    /// Bytes downloaded so far.
    let bytesDownloaded: UInt64
    /// Total bytes to download.
    let totalBytes: UInt64
    /// Fraction complete (0.0 to 1.0).
    let fractionCompleted: Double
    /// Estimated time remaining in seconds.
    let estimatedTimeRemaining: TimeInterval?
    /// Download speed in bytes per second.
    let bytesPerSecond: Double
}

/// Protocol defining the model management service.
protocol ModelManager: AnyObject, Sendable {
    /// Publisher that emits download progress updates.
    var downloadProgressPublisher: AnyPublisher<DownloadProgress, Never> { get }

    /// Publisher that emits when the model list changes (install, delete, state update).
    var modelsChangedPublisher: AnyPublisher<Void, Never> { get }

    /// Download a model from the registry.
    /// - Parameter modelID: The identifier of the model to download.
    /// - Throws: `ModelManagerError` if the download fails or is cancelled.
    func download(modelID: String) async throws

    /// Cancel an in-progress download.
    /// - Parameter modelID: The identifier of the model to cancel.
    func cancelDownload(modelID: String)

    /// Delete a downloaded model from disk.
    /// - Parameter modelID: The identifier of the model to delete.
    /// - Throws: `ModelManagerError` if the model is currently in use.
    func delete(modelID: String) async throws

    /// Get all installed (downloaded) models.
    /// - Returns: Array of `ModelDescriptor` for installed models.
    func getInstalled() async -> [ModelDescriptor]

    /// Get all installed models of a specific type.
    /// - Parameter type: The model type to filter by.
    /// - Returns: Array of `ModelDescriptor` for installed models of the given type.
    func getInstalled(type: ModelType) async -> [ModelDescriptor]

    /// Get all available models from the registry (both installed and not installed).
    /// - Returns: Array of `ModelDescriptor` for all known models.
    func getAvailable() async -> [ModelDescriptor]

    /// Get all available models of a specific type.
    /// - Parameter type: The model type to filter by.
    /// - Returns: Array of `ModelDescriptor` for available models of the given type.
    func getAvailable(type: ModelType) async -> [ModelDescriptor]

    /// Get the local file path for an installed model.
    /// - Parameter modelID: The model identifier.
    /// - Returns: The file URL, or nil if the model is not installed.
    func localPath(for modelID: String) -> URL?

    /// Verify the integrity of a downloaded model against its SHA256 hash.
    /// - Parameter modelID: The model identifier to verify.
    /// - Returns: True if the file matches the expected hash.
    func verify(modelID: String) async throws -> Bool

    /// Get the total disk space used by all downloaded models.
    /// - Returns: Total bytes used.
    func totalDiskUsage() async -> UInt64

    /// Refresh the model registry from the bundled catalog.
    func refreshRegistry() async
}
```

### Download and Lifecycle

```
┌───────────────────────────────────────────────────────────────────┐
│                        Model Lifecycle                             │
│                                                                    │
│  ┌───────────┐    download()     ┌──────────────┐                  │
│  │ Available  │ ───────────────▶ │ Downloading   │                  │
│  └───────────┘                   │ (progress)    │                  │
│       ▲                          └──────┬────────┘                  │
│       │                                 │                           │
│       │  delete()         verify OK     │    verify failed          │
│       │                                 ▼            │              │
│  ┌────┴──────┐                   ┌──────────────┐    ▼              │
│  │ Deleting   │ ◀─────────────── │  Installed   │  ┌──────┐        │
│  └───────────┘     delete()      └──────────────┘  │Failed │        │
│                                                     └──────┘        │
│                                                        │            │
│                                         retry ─────────┘            │
└───────────────────────────────────────────────────────────────────┘
```

### Model Registry

The model registry is a bundled JSON catalog that describes all available models. It is updated via app updates (Sparkle) and can be extended by the user.

```swift
/// Structure of the bundled model registry catalog.
struct ModelRegistry: Codable, Sendable {
    let version: Int
    let lastUpdated: Date
    let whisperModels: [ModelDescriptor]
    let llmModels: [ModelDescriptor]
}

// Default model directory location
// ~/Library/Application Support/HushType/Models/
//   ├── whisper/
//   │   ├── ggml-base.bin
//   │   ├── ggml-small.bin
//   │   └── ggml-medium.bin
//   └── llm/
//       ├── llama-3.2-3b-q4_k_m.gguf
//       └── qwen2.5-1.5b-q4_k_m.gguf
```

### ModelManager Error Types

```swift
/// Errors thrown by ModelManager operations.
enum ModelManagerError: LocalizedError, Sendable {
    /// The model was not found in the registry.
    case modelNotFound(modelID: String)

    /// The download failed.
    case downloadFailed(modelID: String, reason: String)

    /// The download was cancelled by the user.
    case downloadCancelled(modelID: String)

    /// SHA256 verification failed after download.
    case verificationFailed(modelID: String, expected: String, actual: String)

    /// The model cannot be deleted because it is currently loaded.
    case modelInUse(modelID: String)

    /// Insufficient disk space for the download.
    case insufficientDiskSpace(required: UInt64, available: UInt64)

    /// The model file on disk is corrupted or missing.
    case fileCorrupted(modelID: String)

    /// Network error during download (note: only used for initial model fetch, not during normal operation).
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let id):
            return "Model '\(id)' was not found in the registry."
        case .downloadFailed(let id, let reason):
            return "Failed to download model '\(id)': \(reason)"
        case .downloadCancelled(let id):
            return "Download of model '\(id)' was cancelled."
        case .verificationFailed(let id, _, _):
            return "Model '\(id)' failed integrity verification. The download may be corrupted."
        case .modelInUse(let id):
            return "Cannot delete model '\(id)' because it is currently loaded."
        case .insufficientDiskSpace(let required, let available):
            let req = ByteCountFormatter.string(fromByteCount: Int64(required), countStyle: .file)
            let avail = ByteCountFormatter.string(fromByteCount: Int64(available), countStyle: .file)
            return "Insufficient disk space. Required: \(req), Available: \(avail)"
        case .fileCorrupted(let id):
            return "Model file '\(id)' is corrupted. Please re-download."
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}
```

> 🔒 **Security**: Model downloads are the only network operation HushType performs, and they happen only when the user explicitly requests a model download from the Model Manager UI. Downloaded files are verified against SHA256 checksums before being used. No telemetry, analytics, or usage data is ever transmitted.

### ModelManager Usage Examples

```swift
// Downloading and loading a model
func setupModels(
    modelManager: ModelManager,
    whisperService: WhisperService,
    llmService: LLMService
) async throws {
    // Check what is installed
    let installedWhisper = await modelManager.getInstalled(type: .whisper)
    let installedLLM = await modelManager.getInstalled(type: .llm)

    // Download whisper model if none installed
    if installedWhisper.isEmpty {
        print("Downloading whisper-small model...")
        try await modelManager.download(modelID: "whisper-small")
    }

    // Download LLM if none installed
    if installedLLM.isEmpty {
        print("Downloading Llama 3.2 3B model...")
        try await modelManager.download(modelID: "llama-3.2-3b-q4_k_m")
    }

    // Load models into their respective services
    if let whisperPath = modelManager.localPath(for: "whisper-small") {
        try await whisperService.loadModel(at: whisperPath, useGPU: true)
    }

    if let llmPath = modelManager.localPath(for: "llama-3.2-3b-q4_k_m") {
        try await llmService.loadModel(at: llmPath, contextLength: 2048, gpuLayers: -1)
    }
}

// Monitoring download progress
@MainActor
final class ModelDownloadViewModel: ObservableObject {
    @Published var progress: Double = 0.0
    @Published var speedText: String = ""
    @Published var isDownloading: Bool = false

    private let modelManager: ModelManager
    private var cancellables = Set<AnyCancellable>()

    init(modelManager: ModelManager) {
        self.modelManager = modelManager

        modelManager.downloadProgressPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.progress = progress.fractionCompleted
                let speed = ByteCountFormatter.string(
                    fromByteCount: Int64(progress.bytesPerSecond),
                    countStyle: .file
                )
                self?.speedText = "\(speed)/s"
            }
            .store(in: &cancellables)
    }

    func download(modelID: String) async throws {
        isDownloading = true
        defer { isDownloading = false }
        try await modelManager.download(modelID: modelID)
    }
}

// Disk usage summary
func printDiskUsage(modelManager: ModelManager) async {
    let totalUsage = await modelManager.totalDiskUsage()
    let formatted = ByteCountFormatter.string(
        fromByteCount: Int64(totalUsage),
        countStyle: .file
    )
    print("Total model disk usage: \(formatted)")

    let installed = await modelManager.getInstalled()
    for model in installed {
        let size = ByteCountFormatter.string(
            fromByteCount: Int64(model.fileSize),
            countStyle: .file
        )
        print("  \(model.name): \(size)")
    }
}
```

---

## Plugin API Specification

> ℹ️ **Info**: The Plugin API is designed for future extensibility. It is not yet implemented in the current release but the protocol contracts are defined here to guide future development and allow early adopters to prototype extensions.

The Plugin API allows third-party extensions to add new processing modes, voice commands, text transformers, and model backends to HushType.

### Plugin Protocol

```swift
import Foundation

/// Version of the Plugin API. Plugins declare which version they target.
struct PluginAPIVersion: Sendable, Comparable {
    let major: Int
    let minor: Int

    static let v1_0 = PluginAPIVersion(major: 1, minor: 0)

    static func < (lhs: PluginAPIVersion, rhs: PluginAPIVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        return lhs.minor < rhs.minor
    }
}

/// Capabilities a plugin can provide.
struct PluginCapabilities: OptionSet, Sendable {
    let rawValue: UInt

    /// Plugin provides a custom processing mode.
    static let processingMode = PluginCapabilities(rawValue: 1 << 0)
    /// Plugin provides voice commands.
    static let voiceCommands = PluginCapabilities(rawValue: 1 << 1)
    /// Plugin provides a text transformer (post-processing filter).
    static let textTransformer = PluginCapabilities(rawValue: 1 << 2)
    /// Plugin provides an alternative LLM backend.
    static let llmBackend = PluginCapabilities(rawValue: 1 << 3)
    /// Plugin provides an alternative STT backend.
    static let sttBackend = PluginCapabilities(rawValue: 1 << 4)
    /// Plugin provides UI extensions (settings panels, overlays).
    static let uiExtension = PluginCapabilities(rawValue: 1 << 5)
}

/// Core protocol that all plugins must implement.
protocol HushTypePlugin: AnyObject, Sendable {
    /// Unique identifier for this plugin (reverse-domain notation recommended).
    var identifier: String { get }

    /// Human-readable display name.
    var displayName: String { get }

    /// Plugin version string (semver).
    var version: String { get }

    /// Minimum Plugin API version required.
    var minimumAPIVersion: PluginAPIVersion { get }

    /// Description of what this plugin does.
    var pluginDescription: String { get }

    /// Author name or organization.
    var author: String { get }

    /// Capabilities this plugin provides.
    var capabilities: PluginCapabilities { get }

    /// Called when the plugin is loaded. Use this for initialization.
    /// - Parameter host: The plugin host providing access to HushType services.
    func activate(host: PluginHost) async throws

    /// Called when the plugin is being unloaded. Clean up resources.
    func deactivate() async

    /// Called when the plugin's configuration changes.
    /// - Parameter configuration: The updated configuration dictionary.
    func configure(_ configuration: [String: Any]) async
}
```

### Plugin Lifecycle

```
┌──────────────────────────────────────────────────────────────┐
│                       Plugin Lifecycle                        │
│                                                               │
│  ┌───────────┐                                                │
│  │  Bundled   │  Plugin discovered in ~/Library/Application   │
│  │  (.plugin) │  Support/HushType/Plugins/                    │
│  └─────┬─────┘                                                │
│        │ load                                                 │
│        ▼                                                      │
│  ┌───────────┐  validate manifest, check API version          │
│  │  Loaded    │  verify sandbox entitlements                   │
│  └─────┬─────┘                                                │
│        │ activate(host:)                                      │
│        ▼                                                      │
│  ┌───────────┐  plugin registers its capabilities with host   │
│  │  Active    │  plugin receives events, processes text        │
│  └─────┬─────┘                                                │
│        │ deactivate()                                         │
│        ▼                                                      │
│  ┌───────────┐  plugin cleans up resources                    │
│  │ Inactive   │  can be re-activated without reloading         │
│  └───────────┘                                                │
└──────────────────────────────────────────────────────────────┘
```

### Extension Points

```swift
/// The host interface exposed to plugins for interacting with HushType services.
protocol PluginHost: AnyObject, Sendable {
    /// Register a custom processing mode provided by this plugin.
    func registerProcessingMode(
        id: String,
        name: String,
        template: String,
        handler: @escaping @Sendable (String) async throws -> String
    )

    /// Register a voice command provided by this plugin.
    func registerVoiceCommand(_ definition: CommandDefinition, handler: @escaping CommandHandler)

    /// Register a text transformer that runs after LLM processing.
    func registerTextTransformer(
        id: String,
        name: String,
        transformer: @escaping @Sendable (String) async -> String
    )

    /// Access the current application context (frontmost app, focused field).
    func getApplicationContext() async -> ApplicationContext?

    /// Log a message to HushType's plugin log.
    func log(_ message: String, level: PluginLogLevel)

    /// Read a value from the plugin's persistent configuration store.
    func readConfig(key: String) -> Any?

    /// Write a value to the plugin's persistent configuration store.
    func writeConfig(key: String, value: Any?)

    /// Request the user's attention via a notification.
    func showNotification(title: String, body: String)
}

/// Log levels for plugin logging.
enum PluginLogLevel: String, Sendable {
    case debug
    case info
    case warning
    case error
}
```

### Plugin Manifest

Every plugin bundle must include a `manifest.json` file:

```swift
/// Structure of the plugin manifest file (manifest.json).
struct PluginManifest: Codable, Sendable {
    /// Unique plugin identifier (reverse-domain notation).
    let identifier: String
    /// Display name.
    let name: String
    /// Plugin version (semver).
    let version: String
    /// Minimum HushType Plugin API version required.
    let minimumAPIVersion: String
    /// Author name.
    let author: String
    /// Short description.
    let description: String
    /// Capabilities declared by this plugin.
    let capabilities: [String]
    /// Name of the principal class that conforms to HushTypePlugin.
    let principalClass: String
    /// Permissions the plugin requires.
    let permissions: [PluginPermission]
}

/// Permissions a plugin can request.
enum PluginPermission: String, Codable, Sendable {
    /// Access to read the transcribed text.
    case readTranscription
    /// Access to modify the transcribed text.
    case modifyTranscription
    /// Access to read the application context.
    case readContext
    /// Access to inject text via TextInjectionService.
    case injectText
    /// Access to persistent storage.
    case storage
    /// Access to send notifications.
    case notifications
}
```

Example `manifest.json`:

```swift
// manifest.json (JSON, not Swift -- shown here for reference)
// {
//     "identifier": "com.example.hushtype-markdown-formatter",
//     "name": "Markdown Formatter",
//     "version": "1.0.0",
//     "minimumAPIVersion": "1.0",
//     "author": "Example Developer",
//     "description": "Formats transcribed text as Markdown with headers, lists, and emphasis.",
//     "capabilities": ["textTransformer", "processingMode"],
//     "principalClass": "MarkdownFormatterPlugin",
//     "permissions": ["readTranscription", "modifyTranscription", "readContext"]
// }
```

### Plugin Security Sandboxing

> 🔒 **Security**: Plugins run in a restricted sandbox with limited access to HushType APIs. They cannot access the file system outside their own container, cannot make network connections, and cannot access raw audio data. This prevents malicious plugins from exfiltrating sensitive transcription data.

```swift
/// Sandbox restrictions enforced on all plugins.
struct PluginSandbox {
    /// Plugins CANNOT:
    /// - Access raw audio buffers
    /// - Make network connections
    /// - Access the file system outside their plugin container
    /// - Access the Keychain
    /// - Register global hotkeys
    /// - Modify other plugins' configuration
    /// - Access system APIs directly (CGEvent, Accessibility)

    /// Plugins CAN (with declared permissions):
    /// - Read and modify transcribed text
    /// - Register custom processing modes and voice commands
    /// - Read the application context (app name, field type)
    /// - Store configuration in their own persistent store
    /// - Show user-facing notifications
}
```

### Plugin Examples

```swift
// Example: A plugin that formats text as Markdown
final class MarkdownFormatterPlugin: HushTypePlugin {
    let identifier = "com.example.markdown-formatter"
    let displayName = "Markdown Formatter"
    let version = "1.0.0"
    let minimumAPIVersion = PluginAPIVersion.v1_0
    let pluginDescription = "Formats dictated text as clean Markdown."
    let author = "Example Developer"
    let capabilities: PluginCapabilities = [.textTransformer, .processingMode]

    private weak var host: PluginHost?

    func activate(host: PluginHost) async throws {
        self.host = host

        // Register a text transformer
        host.registerTextTransformer(
            id: "markdown-format",
            name: "Markdown Format"
        ) { text in
            // Simple Markdown formatting logic
            var lines = text.components(separatedBy: "\n")
            lines = lines.map { line in
                if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    return line  // Already a list item
                }
                return line
            }
            return lines.joined(separator: "\n")
        }

        // Register a custom processing mode
        host.registerProcessingMode(
            id: "markdown",
            name: "Markdown",
            template: """
            Convert the following transcribed speech into well-formatted Markdown. \
            Use headers (##), bullet points (-), bold (**text**), and code blocks \
            where appropriate. Output only the Markdown.

            {{input}}
            """
        ) { processedText in
            return processedText
        }

        host.log("Markdown Formatter plugin activated", level: .info)
    }

    func deactivate() async {
        host?.log("Markdown Formatter plugin deactivated", level: .info)
    }

    func configure(_ configuration: [String: Any]) async {
        // Handle configuration changes
    }
}
```

---

## Ollama REST API Integration

HushType optionally supports Ollama as an alternative LLM backend for users who already have Ollama installed. This integration communicates exclusively with `localhost:11434` and never sends data to external servers.

> ⚠️ **Warning**: The Ollama integration is optional. It requires the user to have Ollama installed and running separately. The default llama.cpp backend requires no external dependencies.

### Connection Management

```swift
import Foundation

/// Configuration for the Ollama connection.
struct OllamaConfiguration: Sendable, Codable {
    /// Base URL for the Ollama API. Default: http://localhost:11434
    var baseURL: URL = URL(string: "http://localhost:11434")!

    /// Request timeout in seconds.
    var timeout: TimeInterval = 30.0

    /// Maximum number of retry attempts for failed requests.
    var maxRetries: Int = 2

    /// Whether to keep the model loaded in Ollama's memory between requests.
    var keepAlive: String = "5m"
}

/// Ollama connection status.
enum OllamaConnectionStatus: Sendable {
    /// Ollama is running and responsive.
    case connected(version: String)
    /// Ollama is not running or not reachable.
    case disconnected
    /// Checking connection status.
    case checking
    /// Connection failed with an error.
    case error(String)
}

/// Protocol for the Ollama REST API client.
protocol OllamaClient: AnyObject, Sendable {
    /// Current connection status.
    var connectionStatus: OllamaConnectionStatus { get }

    /// Publisher that emits connection status changes.
    var statusPublisher: AnyPublisher<OllamaConnectionStatus, Never> { get }

    /// Check if Ollama is running and reachable.
    /// - Returns: The connection status.
    func checkConnection() async -> OllamaConnectionStatus

    /// Generate a completion using a loaded model.
    /// - Parameters:
    ///   - request: The generation request parameters.
    /// - Returns: An `OllamaGenerateResponse` with the generated text.
    /// - Throws: `OllamaError` if the request fails.
    func generate(_ request: OllamaGenerateRequest) async throws -> OllamaGenerateResponse

    /// Generate a completion with streaming output.
    /// - Parameter request: The generation request parameters.
    /// - Returns: An `AsyncThrowingStream` of partial response chunks.
    func generateStream(
        _ request: OllamaGenerateRequest
    ) -> AsyncThrowingStream<OllamaGenerateChunk, Error>

    /// List all models available in Ollama.
    /// - Returns: Array of `OllamaModelInfo` for each available model.
    func listModels() async throws -> [OllamaModelInfo]

    /// Pull (download) a model from the Ollama registry.
    /// - Parameter name: The model name (e.g., "llama3.2:3b").
    /// - Returns: An `AsyncThrowingStream` of pull progress updates.
    func pullModel(name: String) -> AsyncThrowingStream<OllamaPullProgress, Error>

    /// Check if a specific model is loaded in Ollama.
    /// - Parameter name: The model name.
    /// - Returns: True if the model is currently loaded.
    func isModelLoaded(name: String) async throws -> Bool
}
```

### Endpoint Reference

| Endpoint | Method | Purpose | HushType Usage |
|---|---|---|---|
| `GET /` | GET | Health check | Connection status monitoring |
| `POST /api/generate` | POST | Generate completion | LLM post-processing |
| `POST /api/generate` (stream) | POST | Streaming completion | Real-time token output |
| `GET /api/tags` | GET | List local models | Model selector UI |
| `POST /api/pull` | POST | Download a model | Model management |
| `DELETE /api/delete` | DELETE | Delete a model | Model management |
| `POST /api/show` | POST | Show model info | Model details display |

### Request and Response Types

```swift
/// Request body for the Ollama /api/generate endpoint.
struct OllamaGenerateRequest: Codable, Sendable {
    /// Name of the model to use (e.g., "llama3.2:3b").
    let model: String
    /// The prompt text to send to the model.
    let prompt: String
    /// Whether to stream the response.
    var stream: Bool = false
    /// Generation options.
    var options: OllamaOptions?
    /// System prompt.
    var system: String?
    /// Template override.
    var template: String?
    /// How long to keep the model loaded (e.g., "5m", "0" to unload immediately).
    var keepAlive: String?

    struct OllamaOptions: Codable, Sendable {
        var temperature: Float?
        var topP: Float?
        var topK: Int?
        var numPredict: Int?
        var repeatPenalty: Float?
        var seed: Int?
        var numCtx: Int?
        var numThread: Int?

        enum CodingKeys: String, CodingKey {
            case temperature
            case topP = "top_p"
            case topK = "top_k"
            case numPredict = "num_predict"
            case repeatPenalty = "repeat_penalty"
            case seed
            case numCtx = "num_ctx"
            case numThread = "num_thread"
        }
    }
}

/// Response from the Ollama /api/generate endpoint (non-streaming).
struct OllamaGenerateResponse: Codable, Sendable {
    /// The model that generated the response.
    let model: String
    /// The generated text.
    let response: String
    /// Whether the response is complete.
    let done: Bool
    /// Total duration in nanoseconds.
    let totalDuration: Int64?
    /// Model load duration in nanoseconds.
    let loadDuration: Int64?
    /// Prompt evaluation count (tokens).
    let promptEvalCount: Int?
    /// Prompt evaluation duration in nanoseconds.
    let promptEvalDuration: Int64?
    /// Response evaluation count (tokens generated).
    let evalCount: Int?
    /// Response evaluation duration in nanoseconds.
    let evalDuration: Int64?

    enum CodingKeys: String, CodingKey {
        case model, response, done
        case totalDuration = "total_duration"
        case loadDuration = "load_duration"
        case promptEvalCount = "prompt_eval_count"
        case promptEvalDuration = "prompt_eval_duration"
        case evalCount = "eval_count"
        case evalDuration = "eval_duration"
    }

    /// Computed tokens-per-second for the generation phase.
    var tokensPerSecond: Double? {
        guard let count = evalCount, let duration = evalDuration, duration > 0 else {
            return nil
        }
        return Double(count) / (Double(duration) / 1_000_000_000.0)
    }
}

/// A single chunk in a streaming generate response.
struct OllamaGenerateChunk: Codable, Sendable {
    let model: String
    let response: String
    let done: Bool
}

/// Information about a model installed in Ollama.
struct OllamaModelInfo: Codable, Sendable, Identifiable {
    var id: String { name }
    let name: String
    let size: Int64
    let digest: String
    let modifiedAt: String

    enum CodingKeys: String, CodingKey {
        case name, size, digest
        case modifiedAt = "modified_at"
    }
}

/// Progress update during model pull.
struct OllamaPullProgress: Codable, Sendable {
    let status: String
    let digest: String?
    let total: Int64?
    let completed: Int64?
}
```

### Ollama Error Handling

```swift
/// Errors specific to the Ollama integration.
enum OllamaError: LocalizedError, Sendable {
    /// Ollama is not running or not reachable at the configured URL.
    case notRunning(url: URL)

    /// The requested model is not available in Ollama.
    case modelNotAvailable(name: String)

    /// The HTTP request failed with a status code.
    case httpError(statusCode: Int, body: String?)

    /// JSON decoding of the response failed.
    case decodingFailed(underlying: String)

    /// The request timed out.
    case timeout(after: TimeInterval)

    /// The connection was refused (Ollama not installed or not running).
    case connectionRefused

    /// The streaming response was interrupted.
    case streamInterrupted

    var errorDescription: String? {
        switch self {
        case .notRunning(let url):
            return "Ollama is not running at \(url.absoluteString). Start Ollama and try again."
        case .modelNotAvailable(let name):
            return "Model '\(name)' is not available in Ollama. Run 'ollama pull \(name)' to download it."
        case .httpError(let code, let body):
            return "Ollama returned HTTP \(code): \(body ?? "no details")"
        case .decodingFailed(let reason):
            return "Failed to decode Ollama response: \(reason)"
        case .timeout(let seconds):
            return "Ollama request timed out after \(Int(seconds)) seconds."
        case .connectionRefused:
            return "Connection to Ollama was refused. Ensure Ollama is installed and running."
        case .streamInterrupted:
            return "Streaming response from Ollama was interrupted."
        }
    }
}
```

### Ollama Usage Examples

```swift
// Checking Ollama availability and generating a completion
func processWithOllama(
    client: OllamaClient,
    rawText: String
) async throws -> String {
    // Check connection
    let status = await client.checkConnection()
    guard case .connected = status else {
        throw OllamaError.connectionRefused
    }

    // Generate completion
    let request = OllamaGenerateRequest(
        model: "llama3.2:3b",
        prompt: """
        Fix punctuation and grammar in the following text. Output only the corrected text.

        \(rawText)
        """,
        stream: false,
        options: .init(
            temperature: 0.1,
            topP: 0.9,
            numPredict: 512
        ),
        keepAlive: "5m"
    )

    let response = try await client.generate(request)

    if let tps = response.tokensPerSecond {
        print("Generated at \(String(format: "%.1f", tps)) tokens/sec")
    }

    return response.response
}

// Streaming generation for real-time display
func streamFromOllama(
    client: OllamaClient,
    prompt: String
) async throws -> String {
    let request = OllamaGenerateRequest(
        model: "llama3.2:3b",
        prompt: prompt,
        stream: true,
        options: .init(temperature: 0.1, numPredict: 512)
    )

    var fullResponse = ""

    for try await chunk in client.generateStream(request) {
        fullResponse += chunk.response
        // Print each token as it arrives
        print(chunk.response, terminator: "")
    }

    print()  // Newline after streaming
    return fullResponse
}

// Listing available Ollama models
func listOllamaModels(client: OllamaClient) async throws {
    let models = try await client.listModels()

    print("Available Ollama models:")
    for model in models {
        let size = ByteCountFormatter.string(
            fromByteCount: model.size,
            countStyle: .file
        )
        print("  \(model.name) (\(size))")
    }
}

// Integrating Ollama as an LLMProvider
final class OllamaLLMProvider: LLMProvider {
    private let client: OllamaClient
    private var activeModel: String?

    init(client: OllamaClient) {
        self.client = client
    }

    var isModelLoaded: Bool {
        activeModel != nil
    }

    var estimatedMemoryUsage: UInt64 {
        0  // Managed by Ollama externally
    }

    func loadModel(at path: URL, parameters: LLMLoadParameters) async throws {
        // For Ollama, "loading" means verifying the model exists
        let modelName = path.deletingPathExtension().lastPathComponent
        let models = try await client.listModels()

        guard models.contains(where: { $0.name == modelName }) else {
            throw OllamaError.modelNotAvailable(name: modelName)
        }

        activeModel = modelName
    }

    func complete(prompt: String, parameters: LLMInferenceParameters) async throws -> String {
        guard let model = activeModel else {
            throw LLMError.noModelLoaded
        }

        let request = OllamaGenerateRequest(
            model: model,
            prompt: prompt,
            stream: false,
            options: .init(
                temperature: parameters.temperature,
                topP: parameters.topP,
                topK: parameters.topK,
                numPredict: parameters.maxTokens,
                repeatPenalty: parameters.repeatPenalty
            )
        )

        let response = try await client.generate(request)
        return response.response
    }

    func unloadModel() async {
        activeModel = nil
    }
}
```

> 🔒 **Security**: The Ollama client is configured to communicate only with loopback addresses (`localhost` / `127.0.0.1`). HushType's App Transport Security (ATS) configuration explicitly blocks any requests to non-loopback addresses from the Ollama client. No transcription data is ever sent to remote servers.

---

## Common Types and Protocols

These types are shared across multiple services and form the foundation of the HushType API.

```swift
import Foundation

/// Load parameters shared between LLM providers (llama.cpp and Ollama).
struct LLMLoadParameters: Sendable {
    /// Number of GPU layers to offload. Use -1 for maximum offloading.
    var gpuLayers: Int = -1
    /// Context window length in tokens.
    var contextLength: Int = 2048
    /// Batch size for prompt processing.
    var batchSize: Int = 512
    /// Number of CPU threads for inference.
    var threadCount: Int = 6
    /// Whether to use memory-mapped I/O for the model file.
    var useMmap: Bool = true
}

/// Protocol for any LLM inference backend (llama.cpp direct or Ollama).
protocol LLMProvider: AnyObject, Sendable {
    /// Load a model. For llama.cpp, path is the GGUF file. For Ollama, path encodes the model name.
    func loadModel(at path: URL, parameters: LLMLoadParameters) async throws

    /// Run a text completion.
    func complete(prompt: String, parameters: LLMInferenceParameters) async throws -> String

    /// Whether a model is loaded and ready.
    var isModelLoaded: Bool { get }

    /// Estimated memory usage in bytes. Returns 0 for out-of-process backends.
    var estimatedMemoryUsage: UInt64 { get }

    /// Unload the model and free resources.
    func unloadModel() async
}

/// States of the overall transcription pipeline.
enum PipelineState: String, Sendable {
    case idle
    case recording
    case transcribing
    case postProcessing
    case injecting
    case error
}

/// Result from the full transcription pipeline.
struct PipelineResult: Sendable {
    let rawText: String
    let processedText: String
    let detectedLanguage: String
    let confidence: Double
    let audioDuration: TimeInterval
    let transcriptionTime: TimeInterval
    let processingTime: TimeInterval
    let injectionTime: TimeInterval
    let mode: ProcessingMode
    let whisperModel: String
    let llmModel: String?
}
```

---

## Thread Safety and Concurrency

All HushType service protocols are designed for Swift 5.9+ structured concurrency. Key principles:

```
┌────────────────────────────────────────────────────────────────────┐
│                        Threading Model                              │
│                                                                     │
│  ┌────────────────┐                                                 │
│  │   Main Actor   │  UI updates, SwiftUI @Published properties      │
│  │   (Main Queue) │  OverlayManager, SettingsViewModel              │
│  └───────┬────────┘                                                 │
│          │                                                          │
│  ┌───────▼────────┐                                                 │
│  │  Service Layer  │  async/await on cooperative thread pool         │
│  │  (Unstructured) │  WhisperService, LLMService, AudioCapture      │
│  └───────┬────────┘                                                 │
│          │                                                          │
│  ┌───────▼────────┐                                                 │
│  │  Inference      │  Dedicated threads managed by whisper.cpp      │
│  │  (C/C++ layer)  │  and llama.cpp internally                      │
│  └───────┬────────┘                                                 │
│          │                                                          │
│  ┌───────▼────────┐                                                 │
│  │  Audio Callback │  Real-time audio thread (AVAudioEngine tap)    │
│  │  (RT Thread)    │  Must not block -- no allocations, no locks     │
│  └────────────────┘                                                 │
└────────────────────────────────────────────────────────────────────┘
```

**Key concurrency rules:**

1. All service protocols require `Sendable` conformance to ensure safe cross-actor use.
2. Service methods are `async` and execute on the cooperative thread pool.
3. The `AVAudioEngine` tap callback runs on a real-time audio thread. No allocations, locks, or blocking calls are permitted in the callback. Use a lock-free ring buffer to pass audio data.
4. UI updates (`@Published`, `@MainActor`) must be dispatched to the main actor.
5. C/C++ inference (whisper.cpp, llama.cpp) runs on threads managed by the respective libraries via their `n_threads` parameters. Do not mix these with Swift Task threads.

```swift
// Example: safely bridging from audio callback to async service
final class AudioBridge: @unchecked Sendable {
    private let ringBuffer = LockFreeRingBuffer<Float>(capacity: 16000 * 30)

    /// Called on the real-time audio thread (AVAudioEngine tap).
    /// Must not allocate, lock, or block.
    func onAudioBuffer(_ samples: UnsafeBufferPointer<Float>) {
        ringBuffer.write(samples)
    }

    /// Called from async context to drain buffered samples.
    func drainSamples() -> [Float] {
        return ringBuffer.readAll()
    }
}
```

> ⚠️ **Warning**: Never call `async` functions or acquire locks inside the `AVAudioEngine` tap callback. This runs on a real-time audio thread and any blocking will cause audio glitches. Use lock-free data structures (ring buffers, atomics) for communication between the audio thread and the rest of the application.

---

## Related Documentation

- [Architecture Overview](../architecture/ARCHITECTURE.md) -- High-level system architecture, component interactions, and data flow
- [Technology Stack](../architecture/TECH_STACK.md) -- Technology decisions, comparisons, and integration details
- [Database Schema](../architecture/DATABASE_SCHEMA.md) -- SwiftData models, UserDefaults keys, and data persistence
- [Speech Recognition](../features/SPEECH_RECOGNITION.md) -- Detailed whisper.cpp configuration and tuning guide
- [Security Model](../security/SECURITY.md) -- Privacy guarantees, threat model, and security architecture
- [Permissions](../features/PERMISSIONS.md) -- macOS permissions required by HushType
- [Accessibility](../reference/ACCESSIBILITY.md) -- Accessibility features and VoiceOver support
- [Roadmap](../reference/ROADMAP.md) -- Future plans including Plugin API implementation timeline

---

*This document is part of the [HushType Documentation](../). For questions, corrections, or API proposals, please open an issue on the [GitHub repository](https://github.com/user/hushtype).*
