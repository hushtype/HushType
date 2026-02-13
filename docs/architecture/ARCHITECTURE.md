Last Updated: 2026-02-13

# System Architecture

> **HushType** — Privacy-first, macOS-native speech-to-text with local LLM post-processing.
> This document is the definitive reference for HushType's internal architecture, data flows, threading model, memory management, and extensibility design.

---

## Table of Contents

- [High-Level System Architecture](#high-level-system-architecture)
  - [Layer Diagram](#layer-diagram)
  - [Component Interaction Map](#component-interaction-map)
- [Audio Pipeline](#audio-pipeline)
  - [Capture and Conversion Flow](#capture-and-conversion-flow)
  - [Ring Buffer and VAD](#ring-buffer-and-vad)
  - [Whisper Inference Integration](#whisper-inference-integration)
- [LLM Pipeline](#llm-pipeline)
  - [Mode Selection and Prompt Routing](#mode-selection-and-prompt-routing)
  - [Prompt Template Engine](#prompt-template-engine)
  - [Inference Execution](#inference-execution)
- [Text Injection Pipeline](#text-injection-pipeline)
  - [Injection Strategy Selection](#injection-strategy-selection)
  - [Clipboard Preservation](#clipboard-preservation)
- [Voice Command Pipeline](#voice-command-pipeline)
  - [Command Detection and Parsing](#command-detection-and-parsing)
  - [Action Execution](#action-execution)
- [Component Breakdown](#component-breakdown)
  - [Presentation Layer](#presentation-layer-components)
  - [Application Services Layer](#application-services-layer-components)
  - [Domain Layer](#domain-layer-components)
  - [Infrastructure Layer](#infrastructure-layer-components)
- [Thread Architecture](#thread-architecture)
  - [Thread Model Diagram](#thread-model-diagram)
  - [Synchronization Points](#synchronization-points)
  - [Swift Concurrency Integration](#swift-concurrency-integration)
- [Memory Management Strategy](#memory-management-strategy)
  - [Model Lifecycle](#model-lifecycle)
  - [Memory-Mapped I/O](#memory-mapped-io)
  - [Memory Pressure Handling](#memory-pressure-handling)
- [Plugin Architecture](#plugin-architecture)
  - [Plugin Protocol Definitions](#plugin-protocol-definitions)
  - [Discovery and Registration](#discovery-and-registration)
  - [Sandboxed Execution](#sandboxed-execution)
- [Error Handling Architecture](#error-handling-architecture)
  - [Error Domain Hierarchy](#error-domain-hierarchy)
  - [Fallback Chains](#fallback-chains)
  - [User-Facing Error Presentation](#user-facing-error-presentation)
- [Related Documentation](#related-documentation)

---

## High-Level System Architecture

HushType follows a strict layered architecture with four tiers. Dependencies flow downward only — upper layers depend on lower layers, but never the reverse. Each layer communicates through well-defined Swift protocols, enabling testability and future extensibility.

### Layer Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│                         PRESENTATION LAYER                                  │
│                                                                             │
│  ┌──────────────┐  ┌──────────────────┐  ┌──────────────┐  ┌───────────┐  │
│  │ MenuBarView  │  │  SettingsView    │  │ OverlayView  │  │ Onboarding│  │
│  │ (SwiftUI     │  │  (SwiftUI        │  │ (SwiftUI     │  │ View      │  │
│  │  MenuBar     │  │   Settings       │  │  NSPanel     │  │ (SwiftUI) │  │
│  │  Extra)      │  │   Scene)         │  │  overlay)    │  │           │  │
│  └──────┬───────┘  └────────┬─────────┘  └──────┬───────┘  └─────┬─────┘  │
│         │                   │                    │                │         │
├─────────┼───────────────────┼────────────────────┼────────────────┼─────────┤
│         │                   │                    │                │         │
│         ▼                   ▼                    ▼                ▼         │
│                      APPLICATION SERVICES                                   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                   TranscriptionCoordinator                          │    │
│  │   Orchestrates the full pipeline: record → transcribe → process →  │    │
│  │   inject. Single entry point for the entire dictation lifecycle.    │    │
│  └──────────────────────────────┬──────────────────────────────────────┘    │
│                                 │                                           │
│  ┌──────────────┐  ┌───────────┴──────┐  ┌──────────────┐  ┌───────────┐  │
│  │ HotkeyManager│  │  ModeManager     │  │PermissionMgr │  │ AppState  │  │
│  │              │  │                  │  │              │  │(Observable│  │
│  │ Global key   │  │ Tracks active   │  │ Accessibility│  │ Object)   │  │
│  │ event mon-   │  │ processing mode │  │ + Microphone │  │           │  │
│  │ itoring      │  │ and app profile │  │ permission   │  │ Central   │  │
│  │              │  │ resolution      │  │ requests     │  │ published │  │
│  │              │  │                  │  │              │  │ state     │  │
│  └──────┬───────┘  └──────┬──────────┘  └──────┬───────┘  └─────┬─────┘  │
│         │                 │                     │                │         │
├─────────┼─────────────────┼─────────────────────┼────────────────┼─────────┤
│         │                 │                     │                │         │
│         ▼                 ▼                     ▼                ▼         │
│                          DOMAIN LAYER                                       │
│                                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────┐  ┌──────────────┐  │
│  │WhisperService│  │  LLMService  │  │ CommandParser │  │AudioCapture  │  │
│  │              │  │              │  │               │  │  Service     │  │
│  │ Whisper ctx  │  │ LLM ctx      │  │ Voice cmd    │  │              │  │
│  │ management,  │  │ management,  │  │ detection +  │  │ AVAudioEngine│  │
│  │ inference    │  │ prompt exec, │  │ regex/LLM    │  │ tap, format  │  │
│  │ execution,   │  │ mode routing │  │ parsing      │  │ conversion,  │  │
│  │ language     │  │              │  │               │  │ ring buffer  │  │
│  │ detection    │  │              │  │               │  │              │  │
│  └──────┬───────┘  └──────┬───────┘  └───────┬───────┘  └──────┬───────┘  │
│         │                 │                   │                 │           │
│  ┌──────┴──────┐  ┌──────┴──────┐  ┌─────────┴─────┐  ┌───────┴────────┐  │
│  │TextInjection│  │ Vocabulary  │  │PromptTemplate │  │    VAD         │  │
│  │  Service    │  │  Service    │  │   Engine      │  │  (Voice        │  │
│  │             │  │             │  │               │  │   Activity     │  │
│  │ CGEvent +   │  │ Word        │  │ Template      │  │   Detection)   │  │
│  │ Clipboard   │  │ replacement │  │ variable      │  │                │  │
│  │ injection   │  │ pipeline    │  │ substitution  │  │ Energy-based   │  │
│  │             │  │             │  │               │  │ speech detect  │  │
│  └──────┬───────┘  └──────┬───────┘  └───────┬───────┘  └──────┬───────┘  │
│         │                 │                   │                 │           │
├─────────┼─────────────────┼───────────────────┼─────────────────┼──────────┤
│         │                 │                   │                 │           │
│         ▼                 ▼                   ▼                 ▼           │
│                      INFRASTRUCTURE LAYER                                   │
│                                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────┐  ┌──────────────┐  │
│  │ whisper.cpp  │  │ llama.cpp    │  │  AVAudio      │  │  CGEvent     │  │
│  │ Bridge       │  │ Bridge       │  │  Engine       │  │  Bridge      │  │
│  │              │  │              │  │               │  │              │  │
│  │ C bridging   │  │ C bridging   │  │ System audio  │  │ Quartz event │  │
│  │ header,      │  │ header,      │  │ capture       │  │ services,    │  │
│  │ OpaquePtr    │  │ OpaquePtr    │  │ hardware      │  │ keystroke    │  │
│  │ lifecycle    │  │ lifecycle    │  │               │  │ simulation   │  │
│  └──────────────┘  └──────────────┘  └───────────────┘  └──────────────┘  │
│                                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────┐  ┌──────────────┐  │
│  │  SwiftData   │  │  Model File  │  │  NSWorkspace  │  │  NSPaste     │  │
│  │  Store       │  │  Manager     │  │  Bridge       │  │  board       │  │
│  │              │  │              │  │               │  │  Bridge      │  │
│  │ Persistence, │  │ GGUF/bin     │  │ App detection,│  │              │  │
│  │ migration,   │  │ download,    │  │ launch,       │  │ Clipboard    │  │
│  │ queries      │  │ validation,  │  │ activation    │  │ read/write   │  │
│  │              │  │ storage      │  │               │  │ + restore    │  │
│  └──────────────┘  └──────────────┘  └───────────────┘  └──────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Component Interaction Map

The following diagram shows the primary runtime data flow when a user performs a dictation — from pressing the hotkey through to text appearing in their focused application.

```
   User presses           TranscriptionCoordinator
   global hotkey    ────▶  receives start signal
        │                        │
        │                        ▼
        │               AudioCaptureService
        │                .startCapture()
        │                        │
        │              ┌─────────┴──────────┐
        │              │  AVAudioEngine      │
        │              │  installTap(onBus:) │
        │              │  48kHz stereo ──────┼──▶ Format Converter
        │              └────────────────────┘     (48kHz→16kHz, stereo→mono)
        │                                              │
        │                                              ▼
        │                                        Ring Buffer
        │                                     (30s @ 16kHz mono)
        │                                              │
   User releases                                       │
   global hotkey    ────▶  TranscriptionCoordinator    │
        │                  receives stop signal         │
        │                        │                     │
        │                        ▼                     │
        │               AudioCaptureService            │
        │                .stopCapture()                 │
        │                        │                     │
        │                        ▼                     ▼
        │               WhisperService.transcribe(samples:)
        │                        │
        │                        ▼
        │                ┌───────────────┐
        │                │ whisper.cpp   │
        │                │ inference     │
        │                │ (Metal GPU)   │
        │                └───────┬───────┘
        │                        │
        │                   Raw Text
        │                        │
        │               ┌────────┴────────┐
        │               │                 │
        │               ▼                 ▼
        │     CommandParser         ModeManager
        │     .isCommand()?         .resolveMode()
        │          │                      │
        │          │ (if voice cmd)       │ (if regular text)
        │          ▼                      ▼
        │     ActionExecutor       LLMService.process()
        │     .execute(cmd)               │
        │          │                      ▼
        │          │              ┌───────────────┐
        │          │              │ llama.cpp     │
        │          │              │ inference     │
        │          │              │ (Metal GPU)   │
        │          │              └───────┬───────┘
        │          │                      │
        │          │               Processed Text
        │          │                      │
        │          │              VocabularyService
        │          │              .applyReplacements()
        │          │                      │
        │          ▼                      ▼
        │     System Action       TextInjectionService
        │     (NSWorkspace,       .inject(text:)
        │      AppleScript)              │
        │                         ┌──────┴───────┐
        │                         │              │
        │                         ▼              ▼
        │                    CGEvent        Clipboard
        │                   (< 50 ch)      + Cmd+V
        │                         │        (>= 50 ch)
        │                         │              │
        │                         └──────┬───────┘
        │                                │
        │                                ▼
        └────────────────────▶  Text appears in
                                focused application
```

> ℹ️ **Info**: The entire pipeline — from audio capture stop to text injection — typically completes in under 2 seconds on Apple Silicon with the recommended model configuration (whisper-small + Qwen2.5-1.5B).

---

## Audio Pipeline

The audio pipeline is responsible for capturing microphone input, converting it to the format whisper.cpp expects (16kHz mono Float32 PCM), buffering it efficiently, and detecting voice activity to optimize inference quality.

### Capture and Conversion Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        AUDIO PIPELINE                                    │
│                                                                          │
│  ┌─────────┐      ┌────────────────┐      ┌─────────────────────────┐   │
│  │  macOS   │      │ AVAudioEngine  │      │  AVAudioConverter       │   │
│  │  Micro-  │─────▶│  Input Node    │─────▶│                         │   │
│  │  phone   │      │                │      │  Source: Device native   │   │
│  │          │      │  Tap installed │      │    - 48kHz (typical)    │   │
│  │  (User-  │      │  on bus 0      │      │    - Stereo (2ch)      │   │
│  │  selected│      │                │      │    - Float32            │   │
│  │  or      │      │  Buffer: 1024  │      │                         │   │
│  │  default)│      │  frames        │      │  Target: whisper.cpp    │   │
│  └─────────┘      │  (~21ms @48kHz)│      │    - 16kHz              │   │
│                    └────────────────┘      │    - Mono (1ch)         │   │
│                                            │    - Float32            │   │
│                                            │    - Range: [-1.0, 1.0] │   │
│                                            └────────────┬────────────┘   │
│                                                          │               │
│                                                          ▼               │
│                    ┌─────────────────────────────────────────────┐       │
│                    │         CircularAudioBuffer                  │       │
│                    │                                              │       │
│                    │  Capacity: 30 seconds @ 16kHz = 480,000     │       │
│                    │  samples (1.83 MB)                           │       │
│                    │                                              │       │
│                    │  ┌─────────────────────────────────────┐    │       │
│                    │  │ Write Head ──▶ [samples...] ◀── Read│    │       │
│                    │  │              (lock-free SPSC)        │    │       │
│                    │  └─────────────────────────────────────┘    │       │
│                    │                                              │       │
│                    │  Thread safety: Single-producer (audio       │       │
│                    │  callback thread), single-consumer           │       │
│                    │  (inference thread). Lock-free via atomic    │       │
│                    │  read/write indices.                         │       │
│                    └──────────────────────┬──────────────────────┘       │
│                                           │                              │
│                                           ▼                              │
│                    ┌─────────────────────────────────────────────┐       │
│                    │         Voice Activity Detection (VAD)       │       │
│                    │                                              │       │
│                    │  Algorithm: Energy-based with adaptive       │       │
│                    │  threshold                                    │       │
│                    │                                              │       │
│                    │  1. Compute RMS energy per 30ms frame        │       │
│                    │  2. Compare against adaptive noise floor     │       │
│                    │  3. Apply hangover timer (300ms) to avoid    │       │
│                    │     cutting off trailing syllables           │       │
│                    │  4. Trim leading/trailing silence before     │       │
│                    │     sending to whisper.cpp                   │       │
│                    │                                              │       │
│                    │  Purpose: Reduces inference time by          │       │
│                    │  excluding silence. A 10s recording with     │       │
│                    │  6s of speech + 4s of silence processes      │       │
│                    │  ~40% faster with VAD trimming.              │       │
│                    └──────────────────────┬──────────────────────┘       │
│                                           │                              │
│                                           ▼                              │
│                    ┌─────────────────────────────────────────────┐       │
│                    │       whisper.cpp Inference                  │       │
│                    │                                              │       │
│                    │  Input:  [Float] — 16kHz mono PCM samples   │       │
│                    │  Params: whisper_full_params (beam size,     │       │
│                    │          language, thread count, etc.)        │       │
│                    │  Output: String — raw transcription          │       │
│                    │                                              │       │
│                    │  Execution: Dedicated inference thread       │       │
│                    │  GPU: Metal acceleration (encoder + decoder) │       │
│                    │  CPU: N threads for non-Metal operations     │       │
│                    └─────────────────────────────────────────────┘       │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Ring Buffer and VAD

The ring buffer decouples the real-time audio callback thread from the inference thread. The audio callback fires at hardware-determined intervals (typically every ~21ms at 48kHz with a 1024-frame buffer) and must return quickly to avoid audio glitches.

```swift
/// Lock-free single-producer single-consumer circular buffer for audio samples.
/// The audio callback thread writes; the inference thread reads.
final class CircularAudioBuffer: @unchecked Sendable {
    private var buffer: [Float]
    private let capacity: Int
    private var writeIndex = UnsafeAtomic<Int>.create(0)
    private var readIndex = UnsafeAtomic<Int>.create(0)

    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = [Float](repeating: 0, count: capacity)
    }

    /// Called from the audio callback thread (producer)
    func append(_ samples: [Float]) {
        let currentWrite = writeIndex.load(ordering: .relaxed)
        for (i, sample) in samples.enumerated() {
            buffer[(currentWrite + i) % capacity] = sample
        }
        writeIndex.store(
            (currentWrite + samples.count) % capacity,
            ordering: .releasing
        )
    }

    /// Called from the inference thread (consumer)
    func drain() -> [Float] {
        let currentRead = readIndex.load(ordering: .relaxed)
        let currentWrite = writeIndex.load(ordering: .acquiring)

        let count: Int
        if currentWrite >= currentRead {
            count = currentWrite - currentRead
        } else {
            count = capacity - currentRead + currentWrite
        }

        guard count > 0 else { return [] }

        var result = [Float](repeating: 0, count: count)
        for i in 0..<count {
            result[i] = buffer[(currentRead + i) % capacity]
        }
        readIndex.store(
            (currentRead + count) % capacity,
            ordering: .releasing
        )
        return result
    }
}
```

### Whisper Inference Integration

The `WhisperService` wraps the whisper.cpp C API and manages the model lifecycle:

```swift
/// Manages whisper.cpp context lifecycle and executes speech-to-text inference.
actor WhisperService {
    private var context: OpaquePointer?  // whisper_context*
    private let modelPath: URL

    var isLoaded: Bool { context != nil }
    var detectedLanguage: String = "en"
    var averageConfidence: Double = 0.0

    init(modelPath: URL) {
        self.modelPath = modelPath
    }

    func loadModel() throws {
        var params = whisper_context_default_params()
        params.use_gpu = true         // Metal acceleration
        params.flash_attn = true      // Flash attention on supported hardware

        context = whisper_init_from_file_with_params(
            modelPath.path,
            params
        )
        guard context != nil else {
            throw WhisperError.modelLoadFailed(path: modelPath)
        }
    }

    func transcribe(
        samples: [Float],
        params: whisper_full_params
    ) throws -> String {
        guard let ctx = context else {
            throw WhisperError.contextNotLoaded
        }

        var mutableParams = params
        let result = samples.withUnsafeBufferPointer { ptr in
            whisper_full(ctx, mutableParams, ptr.baseAddress, Int32(samples.count))
        }

        guard result == 0 else {
            throw WhisperError.inferenceFailed(code: result)
        }

        let segmentCount = whisper_full_n_segments(ctx)
        var transcription = ""
        var totalProb: Float = 0

        for i in 0..<segmentCount {
            if let text = whisper_full_get_segment_text(ctx, i) {
                transcription += String(cString: text)
            }
            let nTokens = whisper_full_n_tokens(ctx, i)
            for j in 0..<nTokens {
                totalProb += whisper_full_get_token_p(ctx, i, j)
            }
            let tokenCount = max(1, nTokens)
            averageConfidence = Double(totalProb / Float(tokenCount))
        }

        // Detect language from first segment
        if let langPtr = whisper_full_get_segment_text(ctx, 0) {
            let langId = whisper_full_lang_id(ctx)
            if let langStr = whisper_lang_str(langId) {
                detectedLanguage = String(cString: langStr)
            }
        }

        return transcription.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func unloadModel() {
        if let ctx = context {
            whisper_free(ctx)
            context = nil
        }
    }
}
```

> ⚠️ **Warning**: `whisper_full()` is a blocking call that can take several seconds for longer audio clips. It must never be called on the main thread. The `WhisperService` is an `actor`, and all inference calls should be `await`-ed from a non-main-actor context.

---

## LLM Pipeline

The LLM pipeline takes raw transcription text from whisper.cpp and applies contextual post-processing based on the active processing mode. Each mode maps to a different prompt template that instructs the LLM on how to transform the text.

### Mode Selection and Prompt Routing

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          LLM PIPELINE                                    │
│                                                                          │
│  Raw Text from                                                           │
│  WhisperService ──────▶  ModeManager.resolveMode()                      │
│                                   │                                      │
│                    ┌──────────────┼──────────────────────────┐           │
│                    │              │                          │           │
│                    ▼              ▼              ▼           ▼           │
│              ┌──────────┐  ┌──────────┐  ┌──────────┐ ┌──────────┐     │
│              │   Raw    │  │  Clean   │  │Structure │ │  Prompt  │     │
│              │          │  │          │  │          │ │          │     │
│              │ No LLM   │  │ Fix      │  │ Organize │ │ User-    │     │
│              │ processing│  │ punct,   │  │ into     │ │ defined  │     │
│              │ — pass    │  │ grammar, │  │ headings,│ │ template │     │
│              │ through   │  │ filler   │  │ bullets, │ │ with     │     │
│              │          │  │ words    │  │ sections │ │ variables│     │
│              └────┬─────┘  └────┬─────┘  └────┬─────┘ └────┬─────┘     │
│                   │             │              │            │           │
│              ┌──────────┐  ┌──────────┐                                │
│              │   Code   │  │  Custom  │                                │
│              │          │  │          │                                │
│              │ Convert  │  │ User-    │                                │
│              │ spoken   │  │ defined  │                                │
│              │ code to  │  │ pre/post │                                │
│              │ syntax   │  │ pipeline │                                │
│              └────┬─────┘  └────┬─────┘                                │
│                   │             │                                       │
│                   └──────┬──────┘                                       │
│                          │                                              │
│                          ▼                                              │
│               PromptTemplateEngine                                      │
│               .render(transcription:, mode:)                            │
│                          │                                              │
│                 ┌────────┴────────┐                                     │
│                 │  System Prompt  │  Role definition, behavioral       │
│                 │  (from template)│  constraints for the LLM           │
│                 ├─────────────────┤                                     │
│                 │  User Prompt    │  Raw text + mode-specific           │
│                 │  (rendered with │  instructions with {{variables}}    │
│                 │   variables)    │  substituted                        │
│                 └────────┬────────┘                                     │
│                          │                                              │
│                          ▼                                              │
│               LLMService.complete(prompt:)                              │
│                          │                                              │
│                 ┌────────┴────────┐                                     │
│                 │  llama.cpp      │                                     │
│                 │  Inference      │                                     │
│                 │                 │                                     │
│                 │  Context: 2048  │                                     │
│                 │  Temperature:   │                                     │
│                 │    0.1 (low for │                                     │
│                 │    determinism) │                                     │
│                 │  Top-P: 0.9    │                                     │
│                 │  Max tokens:   │                                     │
│                 │    512          │                                     │
│                 │                 │                                     │
│                 │  Metal GPU     │                                     │
│                 │  acceleration  │                                     │
│                 └────────┬────────┘                                     │
│                          │                                              │
│                          ▼                                              │
│                   Processed Text                                        │
│                          │                                              │
│                          ▼                                              │
│               VocabularyService                                         │
│               .applyReplacements()                                      │
│                          │                                              │
│                          ▼                                              │
│                   Final Output                                          │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Prompt Template Engine

The `PromptTemplateEngine` resolves the active prompt template for the current mode, substitutes variables, and constructs the final prompt payload for LLM inference.

```swift
/// Resolves and renders prompt templates for LLM post-processing.
struct PromptTemplateEngine {
    private let modelContext: ModelContext

    /// Render the prompt for the given mode and transcription.
    func renderPrompt(
        mode: ProcessingMode,
        transcription: String,
        variables: [String: String] = [:]
    ) throws -> RenderedPrompt {
        guard mode.requiresLLM else {
            // Raw mode bypasses LLM entirely
            return RenderedPrompt(
                systemPrompt: "",
                userPrompt: transcription,
                skipInference: true
            )
        }

        // Fetch the default template for this mode
        let descriptor = FetchDescriptor<PromptTemplate>(
            predicate: #Predicate {
                $0.mode == mode && $0.isDefault == true
            }
        )
        guard let template = try modelContext.fetch(descriptor).first else {
            throw PromptError.noTemplateForMode(mode)
        }

        let renderedUserPrompt = template.render(
            transcription: transcription,
            values: variables
        )

        return RenderedPrompt(
            systemPrompt: template.systemPrompt,
            userPrompt: renderedUserPrompt,
            skipInference: false
        )
    }
}

struct RenderedPrompt {
    let systemPrompt: String
    let userPrompt: String
    let skipInference: Bool
}
```

### Inference Execution

The `LLMService` manages the llama.cpp context and executes inference:

```swift
/// Manages llama.cpp model lifecycle and executes LLM inference.
actor LLMService {
    private var model: OpaquePointer?     // llama_model*
    private var context: OpaquePointer?   // llama_context*
    private let provider: LLMProvider

    var isModelLoaded: Bool { model != nil && context != nil }

    func process(
        rawText: String,
        mode: ProcessingMode,
        templateEngine: PromptTemplateEngine
    ) async throws -> String {
        let rendered = try templateEngine.renderPrompt(
            mode: mode,
            transcription: rawText
        )

        // Raw mode — skip LLM entirely
        if rendered.skipInference {
            return rawText
        }

        // Construct the chat-format prompt
        let fullPrompt = """
        <|system|>
        \(rendered.systemPrompt)
        <|user|>
        \(rendered.userPrompt)
        <|assistant|>
        """

        let result = try await provider.complete(
            prompt: fullPrompt,
            parameters: LLMInferenceParameters(
                maxTokens: 512,
                temperature: 0.1,
                topP: 0.9,
                repeatPenalty: 1.1
            )
        )

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

> 💡 **Tip**: The prompt format (`<|system|>`, `<|user|>`, `<|assistant|>`) varies by LLM model family. HushType maintains a prompt format registry that maps model filenames to their expected chat template format (ChatML, Llama, Phi, etc.).

---

## Text Injection Pipeline

After post-processing, the final text must be injected into whatever application the user was focused on when they triggered dictation. HushType uses a dual-strategy approach: CGEvent keystroke simulation for short text, and clipboard paste for longer text.

### Injection Strategy Selection

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     TEXT INJECTION PIPELINE                               │
│                                                                          │
│  Processed Text ──────▶  TextInjectionService                           │
│                                  │                                       │
│                                  ▼                                       │
│                     ┌────────────────────────┐                          │
│                     │  Resolve injection     │                          │
│                     │  method:               │                          │
│                     │                        │                          │
│                     │  1. Check AppProfile   │                          │
│                     │     for target app     │                          │
│                     │                        │                          │
│                     │  2. If .auto:          │                          │
│                     │     text.count < 50    │                          │
│                     │     → CGEvent          │                          │
│                     │     text.count >= 50   │                          │
│                     │     → Clipboard        │                          │
│                     │                        │                          │
│                     │  3. If explicit:       │                          │
│                     │     Use configured     │                          │
│                     │     method             │                          │
│                     └───────────┬────────────┘                          │
│                                 │                                        │
│                    ┌────────────┴────────────┐                          │
│                    │                         │                          │
│                    ▼                         ▼                          │
│    ┌───────────────────────┐  ┌─────────────────────────────────┐      │
│    │   CGEvent Strategy    │  │   Clipboard Strategy            │      │
│    │                       │  │                                  │      │
│    │  For each character:  │  │  1. Save current clipboard      │      │
│    │                       │  │     contents (NSPasteboard)     │      │
│    │  1. Create CGEvent    │  │                                  │      │
│    │     keyDown event     │  │  2. Set processed text to       │      │
│    │                       │  │     clipboard                    │      │
│    │  2. Set Unicode       │  │                                  │      │
│    │     string on event   │  │  3. Simulate Cmd+V via CGEvent  │      │
│    │                       │  │     keyDown: Cmd flag + 'v'     │      │
│    │  3. Post keyDown to   │  │     keyUp: release both         │      │
│    │     cghidEventTap     │  │                                  │      │
│    │                       │  │  4. Wait 150ms for paste to     │      │
│    │  4. Create + post     │  │     complete                     │      │
│    │     keyUp event       │  │                                  │      │
│    │                       │  │  5. Restore previous clipboard  │      │
│    │  5. Sleep 1-5ms       │  │     contents                    │      │
│    │     between chars     │  │                                  │      │
│    │     (configurable)    │  │  Time: ~200ms total             │      │
│    │                       │  │  (independent of text length)   │      │
│    │  Time: ~N ms          │  │                                  │      │
│    │  (N = char count *    │  │                                  │      │
│    │   keystroke delay)    │  │                                  │      │
│    └───────────┬───────────┘  └───────────────┬─────────────────┘      │
│                │                              │                         │
│                └──────────────┬───────────────┘                         │
│                               │                                         │
│                               ▼                                         │
│                    Text appears in                                       │
│                    focused application                                   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Clipboard Preservation

```swift
/// Preserves and restores the system clipboard around a paste operation.
final class ClipboardPreserver {
    private let pasteboard = NSPasteboard.general
    private var savedItems: [NSPasteboardItem] = []
    private var savedTypes: [NSPasteboard.PasteboardType] = []
    private var savedStringContent: String?

    /// Capture the current clipboard state.
    func save() {
        savedStringContent = pasteboard.string(forType: .string)
        // Note: Full multi-type preservation would also save
        // .rtf, .html, .tiff etc. for rich content.
    }

    /// Restore the previously captured clipboard state.
    func restore() {
        pasteboard.clearContents()
        if let content = savedStringContent {
            pasteboard.setString(content, forType: .string)
        }
        savedStringContent = nil
    }
}
```

> 🔒 **Security**: The clipboard contains the transcribed text for approximately 150ms during the paste operation. HushType immediately restores the previous clipboard contents. Applications that poll the clipboard rapidly (clipboard managers, password managers) may capture this transient content. Users who are concerned about this can configure CGEvent-only injection in their `AppProfile`, accepting slower injection for longer texts.

---

## Voice Command Pipeline

HushType supports voice commands that trigger system actions instead of injecting text. Voice commands are detected by a configurable prefix (default: "hey hush") and parsed into structured actions.

### Command Detection and Parsing

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      VOICE COMMAND PIPELINE                              │
│                                                                          │
│  Raw Text from                                                           │
│  WhisperService ──────▶  CommandParser.parse(text:)                     │
│                                   │                                      │
│                                   ▼                                      │
│                    ┌──────────────────────────┐                          │
│                    │  Prefix Detection         │                          │
│                    │                           │                          │
│                    │  Does text start with     │                          │
│                    │  command prefix?           │                          │
│                    │                           │                          │
│                    │  Default: "hey hush"      │                          │
│                    │  Configurable in settings │                          │
│                    │                           │                          │
│                    │  Case-insensitive match   │                          │
│                    │  with fuzzy tolerance     │                          │
│                    │  ("hey hush", "a hush",   │                          │
│                    │   "hey hash" → all match) │                          │
│                    └──────────┬───────────────┘                          │
│                               │                                          │
│                    ┌──────────┴───────────┐                              │
│                    │  No prefix detected  │──────▶ Return to normal      │
│                    │                      │       text pipeline           │
│                    └──────────────────────┘                              │
│                               │                                          │
│                     (Prefix detected)                                    │
│                               │                                          │
│                               ▼                                          │
│                    ┌──────────────────────────┐                          │
│                    │  Command Body Extraction  │                          │
│                    │                           │                          │
│                    │  Strip prefix, normalize  │                          │
│                    │  whitespace, lowercase    │                          │
│                    │                           │                          │
│                    │  "hey hush open Safari"   │                          │
│                    │  → "open safari"          │                          │
│                    └──────────┬───────────────┘                          │
│                               │                                          │
│                               ▼                                          │
│                    ┌──────────────────────────┐                          │
│                    │  Regex Pattern Matching   │                          │
│                    │  (first pass — fast)      │                          │
│                    │                           │                          │
│                    │  Built-in patterns:       │                          │
│                    │  • "open (.+)"            │                          │
│                    │  • "switch to (.+)"       │                          │
│                    │  • "type (.+)"            │                          │
│                    │  • "search (for )?(.+)"   │                          │
│                    │  • "mode (raw|clean|...)" │                          │
│                    │  • "undo"                 │                          │
│                    │  • "select all"           │                          │
│                    │  • "copy that"            │                          │
│                    │  • "paste"                │                          │
│                    │  • "new line"             │                          │
│                    │  • "new paragraph"        │                          │
│                    │  • "delete that"          │                          │
│                    └──────────┬───────────────┘                          │
│                               │                                          │
│                    ┌──────────┴───────────┐                              │
│                    │  No regex match      │                              │
│                    └──────────┬───────────┘                              │
│                               │                                          │
│                               ▼                                          │
│                    ┌──────────────────────────┐                          │
│                    │  LLM Command Parser      │                          │
│                    │  (second pass — smart)    │                          │
│                    │                           │                          │
│                    │  Send command body to LLM │                          │
│                    │  with structured output   │                          │
│                    │  prompt:                  │                          │
│                    │                           │                          │
│                    │  "Classify this voice     │                          │
│                    │   command into an action  │                          │
│                    │   type and parameters.    │                          │
│                    │   Output JSON."           │                          │
│                    │                           │                          │
│                    │  Handles natural language: │                          │
│                    │  "can you open my browser" │                          │
│                    │  → { action: "open_app",  │                          │
│                    │     target: "Safari" }    │                          │
│                    └──────────┬───────────────┘                          │
│                               │                                          │
│                               ▼                                          │
│                    ┌──────────────────────────┐                          │
│                    │  Action Executor          │                          │
│                    │                           │                          │
│                    │  Dispatch parsed command  │                          │
│                    │  to appropriate system API│                          │
│                    │                           │                          │
│                    │  open_app → NSWorkspace   │                          │
│                    │  keystroke → CGEvent      │                          │
│                    │  system → AppleScript     │                          │
│                    │  mode → ModeManager       │                          │
│                    │  text_edit → CGEvent seq  │                          │
│                    └──────────────────────────┘                          │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Action Execution

```swift
/// Parsed voice command with action type and parameters.
enum VoiceCommand {
    case openApp(name: String)
    case switchToApp(name: String)
    case typeText(text: String)
    case searchFor(query: String)
    case changeMode(ProcessingMode)
    case keystroke(KeystrokeAction)
    case textEdit(TextEditAction)
    case unknown(rawText: String)
}

enum KeystrokeAction {
    case undo, redo, copy, paste, cut, selectAll, newLine, newParagraph
}

enum TextEditAction {
    case deleteLastWord, deleteLastSentence, deleteLine
}

/// Executes parsed voice commands against macOS system APIs.
actor ActionExecutor {
    func execute(_ command: VoiceCommand) async throws {
        switch command {
        case .openApp(let name):
            let config = NSWorkspace.OpenConfiguration()
            if let appURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: resolveAppBundleId(name)
            ) {
                try await NSWorkspace.shared.openApplication(
                    at: appURL,
                    configuration: config
                )
            }

        case .keystroke(let action):
            let source = CGEventSource(stateID: .hidSystemState)
            switch action {
            case .undo:
                postKeystroke(key: 6, flags: .maskCommand, source: source)  // Cmd+Z
            case .copy:
                postKeystroke(key: 8, flags: .maskCommand, source: source)  // Cmd+C
            case .selectAll:
                postKeystroke(key: 0, flags: .maskCommand, source: source)  // Cmd+A
            // ... other keystroke actions
            default:
                break
            }

        case .changeMode(let mode):
            await ModeManager.shared.setActiveMode(mode)

        case .unknown(let rawText):
            throw CommandError.unrecognizedCommand(rawText)
        default:
            break
        }
    }
}
```

> ℹ️ **Info**: The two-pass command parsing strategy (regex first, LLM second) ensures that common commands execute instantly (~1ms for regex) while still supporting natural language variations through the LLM (~200-500ms). If the LLM is not loaded, unrecognized commands fall through to the text injection pipeline as regular transcription.

---

## Component Breakdown

### Presentation Layer Components

| Component | Responsibility | Dependencies | Thread Affinity |
|---|---|---|---|
| `MenuBarView` | SwiftUI menu bar interface, recording state indicator, quick mode switching | `AppState`, `TranscriptionCoordinator` | `@MainActor` |
| `SettingsView` | Multi-tab settings window (General, Models, Audio, Text, History, Advanced) | `UserSettings`, `ModelInfo`, `AppProfile` | `@MainActor` |
| `OverlayView` | Floating transparent panel showing recording/processing state indicator | `AppState` | `@MainActor` |
| `OnboardingView` | First-launch setup wizard (permissions, model download, hotkey config) | `PermissionManager`, `ModelFileManager` | `@MainActor` |
| `HistoryView` | Searchable, filterable list of past dictation entries | `DictationEntry`, `SwiftData` queries | `@MainActor` |
| `ModelManagerView` | Model download/delete interface, storage usage display | `ModelInfo`, `ModelFileManager` | `@MainActor` |

### Application Services Layer Components

| Component | Responsibility | Dependencies | Thread Affinity |
|---|---|---|---|
| `TranscriptionCoordinator` | Orchestrates complete dictation lifecycle: start recording, stop, transcribe, post-process, inject | `AudioCaptureService`, `WhisperService`, `LLMService`, `TextInjectionService`, `CommandParser` | `actor` (own executor) |
| `HotkeyManager` | Registers and monitors global keyboard shortcuts via `CGEvent` tap | `CGEvent`, `TranscriptionCoordinator` | Main thread (event tap) |
| `ModeManager` | Resolves active processing mode by checking `AppProfile` for focused app, falling back to global default | `AppProfile`, `UserSettings`, `NSWorkspace` | `@MainActor` |
| `PermissionManager` | Requests and monitors Accessibility and Microphone permissions | `AXIsProcessTrusted`, `AVCaptureDevice` | `@MainActor` |
| `AppState` | Central `@Observable` object publishing recording state, current mode, active model info to all UI | None (pure state) | `@MainActor` |

### Domain Layer Components

| Component | Responsibility | Dependencies | Thread Affinity |
|---|---|---|---|
| `WhisperService` | whisper.cpp context management, model loading/unloading, inference execution, language detection | whisper.cpp bridge | `actor` (inference thread) |
| `LLMService` | llama.cpp context management, prompt execution, token sampling | llama.cpp bridge, `PromptTemplateEngine` | `actor` (inference thread) |
| `AudioCaptureService` | AVAudioEngine lifecycle, tap installation, format conversion (48kHz->16kHz), ring buffer management | `AVAudioEngine`, `CircularAudioBuffer` | Audio thread (callback) |
| `TextInjectionService` | Dual-mode text injection (CGEvent keystrokes or clipboard paste), strategy selection | `CGEvent`, `NSPasteboard`, `ClipboardPreserver` | Background thread |
| `CommandParser` | Voice command prefix detection, regex pattern matching, LLM-based natural language parsing | `LLMService` (optional), regex patterns | `actor` |
| `VocabularyService` | Post-inference word replacement pipeline, applies global and app-specific vocabulary entries | `VocabularyEntry`, `AppProfile` | Any (stateless) |
| `PromptTemplateEngine` | Resolves prompt templates by mode, renders variable substitutions | `PromptTemplate`, `SwiftData` | Any (stateless) |
| `VADProcessor` | Voice activity detection using energy-based thresholding, silence trimming | None (pure computation) | Audio thread |
| `ActionExecutor` | Executes parsed voice commands against macOS system APIs | `NSWorkspace`, `CGEvent`, `AppleScript` bridge | `actor` |

### Infrastructure Layer Components

| Component | Responsibility | Dependencies | Thread Affinity |
|---|---|---|---|
| whisper.cpp Bridge | C bridging header exposing `whisper.h` functions to Swift, `OpaquePointer` lifecycle | whisper.cpp static library, Metal framework | N/A (C library) |
| llama.cpp Bridge | C bridging header exposing `llama.h` functions to Swift, `OpaquePointer` lifecycle | llama.cpp static library, Metal framework | N/A (C library) |
| `AVAudioEngine` (system) | macOS system audio capture, device selection, format negotiation | macOS Audio subsystem | Audio thread |
| CGEvent Bridge | Quartz Event Services for keystroke simulation, global event tapping | macOS Accessibility framework | HID event thread |
| `SwiftDataStore` | `ModelContainer` and `ModelContext` factory, migration plan, background context creation | SwiftData, SQLite | Per-context |
| `ModelFileManager` | GGUF/bin model file download (URLSession), validation (file integrity), storage path management | `URLSession`, `FileManager` | Background thread |
| `NSWorkspace` Bridge | Frontmost application detection, app launching, bundle ID resolution | AppKit | Main thread |
| `NSPasteboard` Bridge | System clipboard read/write, content type handling, preservation/restore | AppKit | Main thread |

---

## Thread Architecture

HushType uses a combination of Swift Concurrency (`actor`, `async/await`, `Task`) and explicit GCD dispatch for components that interact with C libraries or system callbacks.

### Thread Model Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        THREAD ARCHITECTURE                               │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────┐        │
│  │  MAIN THREAD (@MainActor)                                    │        │
│  │                                                               │        │
│  │  • All SwiftUI views and state updates                       │        │
│  │  • AppState (@Observable) property mutations                 │        │
│  │  • PermissionManager (AXIsProcessTrusted checks)             │        │
│  │  • ModeManager (NSWorkspace.frontmostApplication)            │        │
│  │  • HotkeyManager (CGEvent tap registration)                  │        │
│  │  • NSPasteboard read/write                                   │        │
│  │  • UserDefaults access                                       │        │
│  │                                                               │        │
│  │  Rule: No blocking operations. No inference calls.           │        │
│  │        Maximum blocking time: < 16ms (one frame @ 60fps)     │        │
│  └────────────────────────┬──────────────────────────────────────┘        │
│                           │                                              │
│               ┌───────────┼───────────────────┐                          │
│               │           │                   │                          │
│               ▼           ▼                   ▼                          │
│  ┌────────────────┐ ┌──────────────┐ ┌───────────────────────────┐      │
│  │ AUDIO THREAD   │ │ INFERENCE    │ │ BACKGROUND THREAD(S)      │      │
│  │                │ │ THREAD(S)    │ │                            │      │
│  │ AVAudioEngine  │ │              │ │ Model file downloads       │      │
│  │ installTap     │ │ WhisperSvc   │ │ (URLSession background)   │      │
│  │ callback.      │ │ .transcribe()│ │                            │      │
│  │                │ │              │ │ SwiftData background       │      │
│  │ Runs on Apple's│ │ LLMService   │ │ ModelActor operations     │      │
│  │ audio IO       │ │ .process()   │ │ (history cleanup, export) │      │
│  │ thread.        │ │              │ │                            │      │
│  │                │ │ CommandParser│ │ Model validation +         │      │
│  │ MUST return    │ │ .parse()     │ │ integrity checks           │      │
│  │ quickly        │ │              │ │                            │      │
│  │ (< 10ms).     │ │ Each is a    │ │ Vocabulary reloading       │      │
│  │                │ │ Swift actor  │ │                            │      │
│  │ Only writes to │ │ with its own │ │ Clipboard restoration      │      │
│  │ ring buffer.   │ │ serial       │ │ (delayed dispatch)         │      │
│  │                │ │ executor.    │ │                            │      │
│  │ Lock-free      │ │              │ │ CGEvent keystroke          │      │
│  │ SPSC pattern.  │ │ Can run      │ │ simulation (with delays)  │      │
│  │                │ │ concurrently │ │                            │      │
│  │                │ │ with audio   │ │                            │      │
│  │                │ │ capture.     │ │                            │      │
│  └───────┬────────┘ └──────┬───────┘ └────────────┬──────────────┘      │
│          │                 │                       │                      │
│          │    Sync Points  │                       │                      │
│          │                 │                       │                      │
│          ▼                 ▼                       ▼                      │
│  ┌─────────────────────────────────────────────────────────────┐        │
│  │                   SYNCHRONIZATION LAYER                      │        │
│  │                                                               │        │
│  │  1. Ring Buffer: Atomic read/write indices (lock-free SPSC) │        │
│  │     Audio thread → writes samples                            │        │
│  │     Inference thread → reads/drains samples                  │        │
│  │                                                               │        │
│  │  2. Actor isolation: WhisperService, LLMService, Command-   │        │
│  │     Parser all use Swift actor isolation — mutual exclusion  │        │
│  │     guaranteed by the Swift runtime                           │        │
│  │                                                               │        │
│  │  3. @MainActor: All UI state transitions dispatched via      │        │
│  │     MainActor.run {} or @MainActor-annotated methods         │        │
│  │                                                               │        │
│  │  4. SwiftData ModelContext: One context per thread/actor.     │        │
│  │     Main context for UI reads. Background ModelActor for     │        │
│  │     writes (cleanup, import).                                 │        │
│  │                                                               │        │
│  │  5. Combine: @Published properties on @MainActor ensure      │        │
│  │     UI updates are delivered on the main thread               │        │
│  └─────────────────────────────────────────────────────────────┘        │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Synchronization Points

| Sync Point | Mechanism | Producer | Consumer | Data |
|---|---|---|---|---|
| Audio samples | Lock-free ring buffer (atomic indices) | Audio callback thread | Inference thread | `[Float]` PCM samples |
| Transcription result | Swift `actor` isolation (await) | `WhisperService` actor | `TranscriptionCoordinator` actor | `String` raw text |
| LLM result | Swift `actor` isolation (await) | `LLMService` actor | `TranscriptionCoordinator` actor | `String` processed text |
| UI state updates | `@MainActor` + `@Observable` | Any actor (via `MainActor.run`) | SwiftUI views | `AppState` properties |
| SwiftData writes | `ModelActor` (background context) | Background cleanup service | Main context (auto-refresh) | `DictationEntry` inserts |
| Pipeline state | `Combine` `@Published` | `TranscriptionCoordinator` | `MenuBarView`, `OverlayView` | `PipelineState` enum |

### Swift Concurrency Integration

```swift
/// Pipeline states published to the UI via @MainActor.
enum PipelineState: String, Sendable {
    case idle
    case recording
    case transcribing
    case postProcessing
    case injecting
    case error
}

/// The TranscriptionCoordinator is the central orchestrator.
/// It is an actor to serialize pipeline operations and prevent
/// concurrent transcription attempts.
actor TranscriptionCoordinator {
    private let audioService: AudioCaptureService
    private let whisperService: WhisperService
    private let llmService: LLMService
    private let textInjector: TextInjectionService
    private let commandParser: CommandParser
    private let modeManager: ModeManager

    /// Published to UI via @MainActor bridge
    @MainActor var state: PipelineState = .idle

    func startRecording() async throws {
        await MainActor.run { state = .recording }
        try audioService.startCapture()
    }

    func stopAndProcess() async throws {
        audioService.stopCapture()
        await MainActor.run { state = .transcribing }

        let samples = audioService.getAccumulatedSamples()
        let rawText = try await whisperService.transcribe(
            samples: samples,
            params: currentWhisperParams()
        )

        // Check for voice commands first
        if let command = try await commandParser.parse(rawText) {
            try await ActionExecutor().execute(command)
            await MainActor.run { state = .idle }
            return
        }

        // Normal text pipeline
        await MainActor.run { state = .postProcessing }
        let mode = await modeManager.resolveMode()
        let processed: String

        do {
            processed = try await llmService.process(
                rawText: rawText,
                mode: mode,
                templateEngine: PromptTemplateEngine(
                    modelContext: backgroundModelContext
                )
            )
        } catch {
            // Fallback: inject raw text if LLM fails
            processed = rawText
        }

        await MainActor.run { state = .injecting }
        try await textInjector.inject(processed)
        await MainActor.run { state = .idle }
    }
}
```

> ⚠️ **Warning**: The `AudioCaptureService` is intentionally **not** an actor because its `installTap` callback runs on Apple's internal audio I/O thread. Making it an actor would cause the callback to hop to the actor's executor, introducing unacceptable latency. Instead, the audio callback writes to a lock-free ring buffer, and the service exposes `@unchecked Sendable` conformance with carefully documented thread-safety invariants.

---

## Memory Management Strategy

ML model memory management is critical for HushType. A typical configuration loads 0.5-3 GB of model weights into memory. This section describes how models are loaded, retained, unloaded, and how the app responds to system memory pressure.

### Model Lifecycle

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      MODEL LIFECYCLE                                     │
│                                                                          │
│  ┌─────────┐     ┌──────────┐     ┌──────────┐     ┌──────────────┐    │
│  │  COLD   │────▶│ LOADING  │────▶│  WARM    │────▶│  INFERENCE   │    │
│  │ (on disk │     │          │     │ (in RAM, │     │  (actively   │    │
│  │  only)   │     │ mmap +   │     │  ready   │     │   running    │    │
│  │          │     │ context  │     │  for     │     │   whisper_   │    │
│  │          │     │ creation │     │  calls)  │     │   full or    │    │
│  │          │     │          │     │          │     │   llama      │    │
│  │          │     │ Time:    │     │          │     │   _decode)   │    │
│  │          │     │ 100ms-   │     │          │     │              │    │
│  │          │     │ 800ms    │     │          │     │              │    │
│  └─────────┘     └──────────┘     └────┬─────┘     └──────┬───────┘    │
│       ▲                                │                   │            │
│       │                                │                   │            │
│       │          ┌──────────┐          │                   │            │
│       │          │ UNLOADING│◀─────────┘                   │            │
│       └──────────│          │◀──────────────────────────────┘            │
│                  │ whisper_ │                                            │
│                  │ free() / │    Triggers:                               │
│                  │ llama_   │    • User switches model in Settings       │
│                  │ free()   │    • Memory pressure notification          │
│                  │          │    • App enters background (optional)      │
│                  │ Time:    │    • App termination (cleanup)             │
│                  │ < 10ms   │                                            │
│                  └──────────┘                                            │
│                                                                          │
│  PRELOADING STRATEGY:                                                    │
│                                                                          │
│  On app launch:                                                          │
│  1. Load Whisper model immediately (required for core function)         │
│  2. Load LLM model in background after Whisper is ready                 │
│  3. If both models exceed 60% of system RAM, show warning               │
│                                                                          │
│  On model switch:                                                        │
│  1. Unload current model of that type                                   │
│  2. Load new model                                                       │
│  3. Warm up with a short test inference (optional, configurable)        │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Memory-Mapped I/O

Both whisper.cpp and llama.cpp support `mmap` (memory-mapped I/O) for loading model weight files. This is critical for memory efficiency:

```swift
/// Model loading configuration emphasizing mmap for memory efficiency.
struct ModelLoadConfiguration {
    /// Enable memory-mapped I/O for model weights.
    /// When true, the OS maps the model file directly into the process
    /// address space. Only pages that are actively needed for inference
    /// are loaded into physical RAM. The OS can evict pages under memory
    /// pressure and reload them transparently from disk.
    var useMmap: Bool = true

    /// Number of GPU layers to offload to Metal.
    /// -1 means offload all layers. 0 means CPU only.
    /// Values in between split layers between CPU and GPU.
    var gpuLayers: Int32 = -1

    /// Lock model weights in RAM (prevent paging to disk).
    /// Use only when real-time latency is critical and sufficient
    /// RAM is available. Increases memory pressure.
    var lockMemory: Bool = false
}
```

**How mmap affects memory reporting:**

```
┌───────────────────────────────────────────────────────────────┐
│  Memory Reporting for a 2 GB model with mmap enabled         │
│                                                               │
│  Activity Monitor "Memory" column:  ~2.5 GB                  │
│  (Includes mmap'd pages — misleading!)                        │
│                                                               │
│  Actual physical RAM usage:         ~800 MB - 1.5 GB          │
│  (Only actively-used pages)                                   │
│                                                               │
│  Memory Pressure gauge:             Green/Yellow              │
│  (OS can reclaim mmap pages freely)                           │
│                                                               │
│  ┌─────────────────────────────────────────┐                  │
│  │  Model file on disk (2 GB)              │                  │
│  │  ████████████████████████████████████████│                  │
│  └─────────────────────────────────────────┘                  │
│           ▲           ▲          ▲                             │
│           │           │          │   mmap: OS loads pages      │
│           │           │          │   on demand                 │
│  ┌────────┴───────────┴──────────┴─────────┐                  │
│  │  Physical RAM (pages loaded on access)   │                  │
│  │  ████████░░░░████████░░░░░░████████░░░░ │                  │
│  │  ^used^   ^not^  ^used^           ^used^ │                  │
│  │          loaded                          │                  │
│  └─────────────────────────────────────────┘                  │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

### Memory Pressure Handling

HushType responds to macOS memory pressure notifications to prevent the system from becoming unresponsive:

```swift
import Foundation

/// Monitors system memory pressure and triggers model unloading
/// when the system is under stress.
final class MemoryPressureMonitor {
    private var source: DispatchSourceMemoryPressure?
    private let whisperService: WhisperService
    private let llmService: LLMService

    func startMonitoring() {
        source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .global(qos: .utility)
        )

        source?.setEventHandler { [weak self] in
            guard let self else { return }
            let event = self.source?.data ?? []

            Task {
                if event.contains(.critical) {
                    // Critical: Unload both models immediately
                    await self.llmService.unloadModel()
                    await self.whisperService.unloadModel()
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: .modelsUnloadedDueToMemoryPressure,
                            object: nil
                        )
                    }
                } else if event.contains(.warning) {
                    // Warning: Unload LLM only (less essential)
                    // Whisper is needed for core transcription
                    await self.llmService.unloadModel()
                }
            }
        }

        source?.resume()
    }

    func stopMonitoring() {
        source?.cancel()
        source = nil
    }
}
```

**Memory management decision matrix:**

| System RAM | Recommended Whisper | Recommended LLM | mmap | GPU Layers |
|---|---|---|---|---|
| 8 GB | `tiny` or `base` | `Qwen2.5-0.5B` Q4 | Required | All (-1) |
| 8 GB | `small` | `Qwen2.5-1.5B` Q4 | Required | All (-1) |
| 16 GB | `small` or `medium` | `Qwen2.5-3B` Q4 | Recommended | All (-1) |
| 16 GB | `large-v3` | `Llama-3.2-3B` Q4 | Recommended | All (-1) |
| 32 GB | `large-v3` | `Phi-3-mini` Q4 | Optional | All (-1) |
| 32 GB+ | `large-v3` | Any 7B Q4 | Optional | All (-1) |

> 🍎 **macOS-specific**: Apple Silicon's unified memory architecture means GPU and CPU share the same physical RAM pool. Setting `gpuLayers: -1` (offload all layers to Metal) does not consume additional memory beyond what the model already uses — it simply tells the GPU to read from the same memory addresses. On Intel Macs with discrete GPUs, GPU offloading requires a separate copy of the offloaded layers in VRAM.

---

## Plugin Architecture

HushType is designed for future extensibility through a plugin system. While plugins are not yet implemented in the initial release, the architecture is designed to accommodate them without breaking changes.

### Plugin Protocol Definitions

```swift
import Foundation

/// A HushType plugin that can process text at specific points in the pipeline.
///
/// Plugins are discovered at launch, instantiated in sandboxed containers,
/// and invoked at well-defined pipeline stages.
protocol HushTypePlugin: AnyObject, Sendable {
    /// Unique reverse-DNS identifier (e.g., "com.example.myplugin").
    static var identifier: String { get }

    /// Human-readable plugin name shown in Settings.
    static var displayName: String { get }

    /// Plugin version following semver.
    static var version: String { get }

    /// Which pipeline stages this plugin hooks into.
    static var hooks: Set<PluginHook> { get }

    /// Called once when the plugin is loaded. Use for setup.
    func activate() async throws

    /// Called when the plugin is being unloaded. Use for cleanup.
    func deactivate() async

    /// Process text at the given pipeline stage.
    /// Return the (possibly modified) text to pass to the next stage.
    func process(
        text: String,
        context: PluginContext,
        hook: PluginHook
    ) async throws -> String
}

/// Points in the pipeline where plugins can intercept and modify text.
enum PluginHook: String, Sendable, CaseIterable {
    /// After whisper.cpp transcription, before command parsing.
    case postTranscription

    /// After command parsing (only for non-command text), before LLM.
    case preLLM

    /// After LLM post-processing, before vocabulary replacement.
    case postLLM

    /// After vocabulary replacement, before text injection.
    case preInjection
}

/// Read-only context provided to plugins during processing.
struct PluginContext: Sendable {
    /// The current processing mode.
    let mode: ProcessingMode

    /// Detected language of the transcription.
    let language: String

    /// Bundle ID of the focused application.
    let targetAppBundleId: String?

    /// Duration of the audio recording in seconds.
    let audioDuration: TimeInterval

    /// Whisper confidence score (0.0 - 1.0).
    let confidence: Double
}
```

### Discovery and Registration

```swift
/// Manages plugin discovery, lifecycle, and execution.
actor PluginManager {
    private var loadedPlugins: [String: any HushTypePlugin] = [:]
    private var enabledPlugins: Set<String> = []

    /// Plugin search paths (in priority order).
    private let searchPaths: [URL] = [
        // User plugins
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("HushType/Plugins"),

        // Built-in plugins
        Bundle.main.builtInPlugInsURL
    ].compactMap { $0 }

    /// Discover and load all plugins from search paths.
    func discoverPlugins() async throws {
        for path in searchPaths {
            guard FileManager.default.fileExists(atPath: path.path) else {
                continue
            }

            let contents = try FileManager.default.contentsOfDirectory(
                at: path,
                includingPropertiesForKeys: nil
            )

            for item in contents where item.pathExtension == "hushplugin" {
                try await loadPlugin(at: item)
            }
        }
    }

    /// Execute all enabled plugins for the given hook.
    func executeHook(
        _ hook: PluginHook,
        text: String,
        context: PluginContext
    ) async throws -> String {
        var result = text

        // Plugins execute in registration order
        for (id, plugin) in loadedPlugins {
            guard enabledPlugins.contains(id) else { continue }
            guard type(of: plugin).hooks.contains(hook) else { continue }

            result = try await plugin.process(
                text: result,
                context: context,
                hook: hook
            )
        }

        return result
    }
}
```

### Sandboxed Execution

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     PLUGIN SANDBOX MODEL                                 │
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────┐       │
│  │  HushType Main Process                                       │       │
│  │                                                               │       │
│  │  ┌──────────────────────────────────────────────────────┐    │       │
│  │  │  TranscriptionCoordinator                             │    │       │
│  │  │       │                                               │    │       │
│  │  │       ▼                                               │    │       │
│  │  │  PluginManager.executeHook(.postTranscription, ...)   │    │       │
│  │  └──────┬────────────────────────────────────────────────┘    │       │
│  │         │                                                     │       │
│  └─────────┼─────────────────────────────────────────────────────┘       │
│            │  XPC connection (future)                                     │
│            │  or in-process with restrictions (v1)                       │
│            ▼                                                             │
│  ┌──────────────────────────────────────────────────────────────┐       │
│  │  Plugin Sandbox                                               │       │
│  │                                                               │       │
│  │  Restrictions:                                                │       │
│  │  • No network access (URLSession blocked)                    │       │
│  │  • No file system access outside plugin's own container      │       │
│  │  • No access to system APIs (CGEvent, NSWorkspace, etc.)     │       │
│  │  • No access to SwiftData or other HushType internal state   │       │
│  │  • 5-second timeout per process() call                       │       │
│  │  • 50 MB memory limit per plugin                             │       │
│  │                                                               │       │
│  │  Allowed:                                                     │       │
│  │  • Read PluginContext (read-only metadata)                   │       │
│  │  • Receive text (String)                                     │       │
│  │  • Return modified text (String)                             │       │
│  │  • Use Foundation string processing                           │       │
│  │  • Use own bundled resources                                  │       │
│  │                                                               │       │
│  └──────────────────────────────────────────────────────────────┘       │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

> ℹ️ **Info**: The initial plugin architecture (v1) runs plugins in-process with soft restrictions enforced by API design (plugins only receive `String` and `PluginContext`, not service references). A future version (v2) will use XPC Services for true process-level isolation, enabling untrusted third-party plugins with hardware-enforced sandboxing.

> ⚠️ **Warning**: Plugin support is a planned feature for a future release. The protocols and architecture described here are subject to change. The initial release of HushType does not load or execute plugins.

---

## Error Handling Architecture

HushType uses a structured error handling strategy with typed error domains, fallback chains for graceful degradation, and consistent user-facing error presentation.

### Error Domain Hierarchy

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      ERROR DOMAIN HIERARCHY                              │
│                                                                          │
│  HushTypeError (top-level)                                               │
│  │                                                                       │
│  ├── AudioError                                                          │
│  │   ├── .microphonePermissionDenied                                    │
│  │   ├── .noInputDeviceAvailable                                        │
│  │   ├── .formatCreationFailed                                          │
│  │   ├── .converterCreationFailed                                       │
│  │   ├── .engineStartFailed(underlying: Error)                          │
│  │   └── .bufferOverflow                                                │
│  │                                                                       │
│  ├── WhisperError                                                        │
│  │   ├── .modelLoadFailed(path: URL)                                    │
│  │   ├── .contextNotLoaded                                              │
│  │   ├── .inferenceFailed(code: Int32)                                  │
│  │   ├── .emptyTranscription                                            │
│  │   └── .modelFileCorrupted(path: URL)                                 │
│  │                                                                       │
│  ├── LLMError                                                            │
│  │   ├── .modelLoadFailed(path: URL)                                    │
│  │   ├── .contextCreationFailed                                         │
│  │   ├── .inferenceFailed(underlying: Error)                            │
│  │   ├── .tokenizationFailed                                            │
│  │   ├── .outputTruncated(maxTokens: Int)                               │
│  │   └── .modelNotLoaded                                                │
│  │                                                                       │
│  ├── InjectionError                                                      │
│  │   ├── .accessibilityPermissionDenied                                 │
│  │   ├── .cgEventCreationFailed                                         │
│  │   ├── .clipboardWriteFailed                                          │
│  │   ├── .noFocusedApplication                                         │
│  │   └── .pasteTimeout                                                  │
│  │                                                                       │
│  ├── CommandError                                                        │
│  │   ├── .unrecognizedCommand(String)                                   │
│  │   ├── .appNotFound(name: String)                                     │
│  │   ├── .actionFailed(underlying: Error)                               │
│  │   └── .llmParsingFailed                                              │
│  │                                                                       │
│  ├── ModelFileError                                                      │
│  │   ├── .downloadFailed(url: URL, underlying: Error)                   │
│  │   ├── .insufficientDiskSpace(required: UInt64, available: UInt64)    │
│  │   ├── .checksumMismatch(expected: String, actual: String)            │
│  │   └── .fileNotFound(path: URL)                                       │
│  │                                                                       │
│  ├── PromptError                                                         │
│  │   ├── .noTemplateForMode(ProcessingMode)                             │
│  │   ├── .variableNotProvided(name: String)                             │
│  │   └── .templateRenderFailed                                          │
│  │                                                                       │
│  └── PluginError                                                         │
│      ├── .loadFailed(identifier: String, underlying: Error)             │
│      ├── .executionTimeout(identifier: String, hook: PluginHook)        │
│      ├── .memoryLimitExceeded(identifier: String)                       │
│      └── .invalidOutput(identifier: String)                              │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

```swift
/// Top-level error type encompassing all HushType error domains.
enum HushTypeError: Error, LocalizedError {
    case audio(AudioError)
    case whisper(WhisperError)
    case llm(LLMError)
    case injection(InjectionError)
    case command(CommandError)
    case modelFile(ModelFileError)
    case prompt(PromptError)
    case plugin(PluginError)

    var errorDescription: String? {
        switch self {
        case .audio(let e): return e.localizedDescription
        case .whisper(let e): return e.localizedDescription
        case .llm(let e): return e.localizedDescription
        case .injection(let e): return e.localizedDescription
        case .command(let e): return e.localizedDescription
        case .modelFile(let e): return e.localizedDescription
        case .prompt(let e): return e.localizedDescription
        case .plugin(let e): return e.localizedDescription
        }
    }
}

enum AudioError: Error, LocalizedError {
    case microphonePermissionDenied
    case noInputDeviceAvailable
    case formatCreationFailed
    case converterCreationFailed
    case engineStartFailed(underlying: Error)
    case bufferOverflow

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access is required. Grant permission in System Settings > Privacy & Security > Microphone."
        case .noInputDeviceAvailable:
            return "No microphone detected. Connect a microphone and try again."
        case .engineStartFailed(let err):
            return "Audio engine failed to start: \(err.localizedDescription)"
        default:
            return "An audio error occurred."
        }
    }
}
```

### Fallback Chains

HushType implements fallback chains so that partial failures degrade functionality gracefully rather than blocking the user entirely.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        FALLBACK CHAINS                                   │
│                                                                          │
│  CHAIN 1: LLM Post-Processing Failure                                   │
│  ─────────────────────────────────────                                   │
│                                                                          │
│  ┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐       │
│  │ LLM      │────▶│ Retry    │────▶│ Inject   │────▶│ Show     │       │
│  │ inference │     │ once with│     │ raw text │     │ warning  │       │
│  │ fails    │     │ shorter  │     │ (skip    │     │ to user  │       │
│  │          │     │ context  │     │ post-    │     │ "Text    │       │
│  │          │     │          │     │ process) │     │ injected │       │
│  └──────────┘     └──────────┘     └──────────┘     │ without  │       │
│                        │                             │ cleanup" │       │
│                  (if retry fails)                     └──────────┘       │
│                                                                          │
│  CHAIN 2: Text Injection Failure                                         │
│  ────────────────────────────────                                        │
│                                                                          │
│  ┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐       │
│  │ CGEvent  │────▶│ Fall back│────▶│ Copy to  │────▶│ Show     │       │
│  │ injection│     │ to       │     │ clipboard│     │ notifi-  │       │
│  │ fails    │     │ clipboard│     │ only     │     │ cation:  │       │
│  │ (no      │     │ paste    │     │ (no      │     │ "Text    │       │
│  │ a11y     │     │          │     │ paste)   │     │ copied"  │       │
│  │ perm)    │     │          │     │          │     │          │       │
│  └──────────┘     └──────────┘     └──────────┘     └──────────┘       │
│                        │                                                │
│                  (if paste also fails)                                   │
│                                                                          │
│  CHAIN 3: Whisper Inference Failure                                      │
│  ──────────────────────────────────                                      │
│                                                                          │
│  ┌──────────┐     ┌──────────┐     ┌──────────┐                        │
│  │ Whisper  │────▶│ Retry    │────▶│ Show     │                        │
│  │ inference│     │ with     │     │ error    │                        │
│  │ fails    │     │ smaller  │     │ "Trans-  │                        │
│  │          │     │ model    │     │ cription │                        │
│  │          │     │ (if      │     │ failed.  │                        │
│  │          │     │ avail-   │     │ Try      │                        │
│  │          │     │ able)    │     │ again."  │                        │
│  └──────────┘     └──────────┘     └──────────┘                        │
│                        │                                                │
│                  (if no fallback model)                                  │
│                                                                          │
│  CHAIN 4: Audio Capture Failure                                          │
│  ──────────────────────────────                                          │
│                                                                          │
│  ┌──────────┐     ┌──────────┐     ┌──────────┐                        │
│  │ Audio    │────▶│ Try      │────▶│ Show     │                        │
│  │ engine   │     │ system   │     │ error    │                        │
│  │ fails    │     │ default  │     │ with     │                        │
│  │ with     │     │ device   │     │ link to  │                        │
│  │ selected │     │          │     │ Sound    │                        │
│  │ device   │     │          │     │ settings │                        │
│  └──────────┘     └──────────┘     └──────────┘                        │
│                        │                                                │
│                  (if default also fails)                                 │
│                                                                          │
│  CHAIN 5: Model Loading Failure                                          │
│  ──────────────────────────────                                          │
│                                                                          │
│  ┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐       │
│  │ Model    │────▶│ Verify   │────▶│ Offer    │────▶│ Open     │       │
│  │ fails to │     │ file     │     │ re-      │     │ model    │       │
│  │ load     │     │ integrity│     │ download │     │ manager  │       │
│  │          │     │ (check   │     │ (delete  │     │ in       │       │
│  │          │     │ size,    │     │ corrupt  │     │ settings │       │
│  │          │     │ header)  │     │ file)    │     │          │       │
│  └──────────┘     └──────────┘     └──────────┘     └──────────┘       │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### User-Facing Error Presentation

```swift
/// Converts internal errors into user-friendly presentation.
struct ErrorPresenter {
    /// Determine the appropriate presentation style for an error.
    static func presentation(for error: HushTypeError) -> ErrorPresentation {
        switch error {
        case .audio(.microphonePermissionDenied):
            return ErrorPresentation(
                title: "Microphone Access Required",
                message: "HushType needs microphone access to transcribe your speech.",
                style: .alert,
                actions: [
                    .openSystemSettings("Privacy & Security > Microphone"),
                    .dismiss
                ],
                severity: .blocking
            )

        case .whisper(.inferenceFailed):
            return ErrorPresentation(
                title: "Transcription Failed",
                message: "The speech-to-text engine encountered an error. Please try again.",
                style: .notification,
                actions: [.retry, .dismiss],
                severity: .recoverable
            )

        case .llm(.modelNotLoaded):
            return ErrorPresentation(
                title: "Text Processing Unavailable",
                message: "The language model is not loaded. Raw transcription will be used.",
                style: .toast,
                actions: [.openModelManager, .dismiss],
                severity: .degraded
            )

        case .injection(.accessibilityPermissionDenied):
            return ErrorPresentation(
                title: "Accessibility Permission Required",
                message: "HushType needs Accessibility access to type text into applications. Text has been copied to your clipboard instead.",
                style: .alert,
                actions: [
                    .openSystemSettings("Privacy & Security > Accessibility"),
                    .dismiss
                ],
                severity: .degraded
            )

        default:
            return ErrorPresentation(
                title: "Something Went Wrong",
                message: error.localizedDescription,
                style: .notification,
                actions: [.dismiss],
                severity: .recoverable
            )
        }
    }
}

struct ErrorPresentation {
    let title: String
    let message: String
    let style: PresentationStyle
    let actions: [ErrorAction]
    let severity: ErrorSeverity

    enum PresentationStyle {
        case alert          // Modal alert dialog (blocking errors)
        case notification   // macOS notification center (transient errors)
        case toast          // In-app toast overlay (informational)
        case menuBarBadge   // Red badge on menu bar icon (persistent warnings)
    }

    enum ErrorAction {
        case dismiss
        case retry
        case openSystemSettings(String)
        case openModelManager
        case contactSupport
    }

    enum ErrorSeverity {
        case blocking     // App cannot function (no mic permission)
        case degraded     // App works with reduced functionality
        case recoverable  // Temporary failure, retry may succeed
        case informational // No action needed
    }
}
```

> ✅ **Do**: Always provide a clear, actionable error message. Tell the user what happened, why it happened, and what they can do about it. Include a direct action (button, link) to resolve the issue.
>
> ❌ **Don't**: Expose raw error codes, stack traces, or internal component names in user-facing errors. The user does not need to know that `whisper_full()` returned error code `-7`.

> 💡 **Tip**: All errors are also logged to the unified logging system (`os_log`) with the `com.hushtype` subsystem. Users can collect diagnostic logs via Console.app for bug reports. Sensitive data (transcription text) is never included in log messages.

---

## Related Documentation

- [Tech Stack](TECH_STACK.md) -- Technology choices, benchmarks, and integration details
- [Database Schema](DATABASE_SCHEMA.md) -- SwiftData models, persistence layer, migration strategy
- [Security Model](../security/SECURITY.md) -- Privacy guarantees, threat model, and security architecture
- [Setup Guide](../getting-started/SETUP_GUIDE.md) -- Development environment setup and first build
- [Deployment Guide](../deployment/DEPLOYMENT.md) -- Build, sign, notarize, and distribute
- [API Reference](../api/API_REFERENCE.md) -- Internal module APIs and interfaces
- [Contributing Guide](../contributing/CONTRIBUTING.md) -- How to contribute to HushType
- [Testing Guide](../testing/TESTING.md) -- Unit, integration, and UI testing strategy
- [Feature Documentation](../features/FEATURES.md) -- Detailed feature specifications

---

*This document is part of the [HushType Documentation](../). For questions or corrections, please open an issue on the [GitHub repository](https://github.com/user/hushtype).*
