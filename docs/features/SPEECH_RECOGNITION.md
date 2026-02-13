# Speech Recognition

**Last Updated: 2026-02-13**

HushType's speech recognition engine is built on [whisper.cpp](https://github.com/ggerganov/whisper.cpp), a high-performance C/C++ port of OpenAI's Whisper model, compiled as a static library with Metal GPU acceleration for macOS. Every byte of audio is processed locally — no network calls, no cloud APIs, no telemetry.

---

## Table of Contents

- [1. Whisper.cpp Integration Architecture](#1-whispercpp-integration-architecture)
  - [1.1 Static Library Compilation](#11-static-library-compilation)
  - [1.2 Bridging Headers and Swift-C Interop](#12-bridging-headers-and-swift-c-interop)
  - [1.3 Metal GPU Acceleration](#13-metal-gpu-acceleration)
  - [1.4 Architecture Overview Diagram](#14-architecture-overview-diagram)
- [2. Model Management](#2-model-management)
  - [2.1 Supported Models](#21-supported-models)
  - [2.2 Download Flow](#22-download-flow)
  - [2.3 Storage Layout](#23-storage-layout)
  - [2.4 Model Selection UI](#24-model-selection-ui)
  - [2.5 Model Loading and Switching](#25-model-loading-and-switching)
- [3. Audio Preprocessing Pipeline](#3-audio-preprocessing-pipeline)
  - [3.1 AVAudioEngine Setup](#31-avaudioengine-setup)
  - [3.2 Sample Rate Conversion](#32-sample-rate-conversion)
  - [3.3 Voice Activity Detection (VAD)](#33-voice-activity-detection-vad)
  - [3.4 Noise Gate](#34-noise-gate)
  - [3.5 Audio Level Monitoring](#35-audio-level-monitoring)
  - [3.6 Buffer Management](#36-buffer-management)
  - [3.7 Pipeline Diagram](#37-pipeline-diagram)
- [4. Streaming vs Batch Transcription](#4-streaming-vs-batch-transcription)
  - [4.1 Batch Transcription (Process After Recording)](#41-batch-transcription-process-after-recording)
  - [4.2 Streaming Transcription (Real-Time Partial Results)](#42-streaming-transcription-real-time-partial-results)
  - [4.3 Tradeoffs Comparison](#43-tradeoffs-comparison)
  - [4.4 Implementation Details](#44-implementation-details)
- [5. Language Detection and Selection](#5-language-detection-and-selection)
  - [5.1 Automatic Language Detection](#51-automatic-language-detection)
  - [5.2 Manual Language Selection](#52-manual-language-selection)
  - [5.3 Supported Languages](#53-supported-languages)
  - [5.4 Language-Specific Optimizations](#54-language-specific-optimizations)
- [6. Performance Tuning Parameters](#6-performance-tuning-parameters)
  - [6.1 Core Parameters](#61-core-parameters)
  - [6.2 Apple Silicon Optimization](#62-apple-silicon-optimization)
  - [6.3 Intel Mac Configuration](#63-intel-mac-configuration)
  - [6.4 Memory Management](#64-memory-management)
- [7. Custom Vocabulary Integration](#7-custom-vocabulary-integration)
  - [7.1 Vocabulary Entry Format](#71-vocabulary-entry-format)
  - [7.2 Prompt Conditioning with Custom Vocabulary](#72-prompt-conditioning-with-custom-vocabulary)
  - [7.3 Post-Processing Corrections](#73-post-processing-corrections)
- [8. Accuracy Optimization Techniques](#8-accuracy-optimization-techniques)
  - [8.1 Model Selection Strategy](#81-model-selection-strategy)
  - [8.2 Prompt Conditioning](#82-prompt-conditioning)
  - [8.3 Audio Quality Tips](#83-audio-quality-tips)
- [9. Handling Edge Cases](#9-handling-edge-cases)
  - [9.1 Background Noise](#91-background-noise)
  - [9.2 Accents and Dialects](#92-accents-and-dialects)
  - [9.3 Technical Jargon](#93-technical-jargon)
  - [9.4 Mixed-Language Speech](#94-mixed-language-speech)
  - [9.5 Long Utterances](#95-long-utterances)
- [Related Documentation](#related-documentation)

---

## 1. Whisper.cpp Integration Architecture

HushType integrates whisper.cpp as a statically linked C library, bridged into Swift through a custom C-to-Swift interop layer. This approach avoids dynamic linking pitfalls, keeps the binary self-contained, and enables fine-grained control over GPU acceleration via Metal.

### 1.1 Static Library Compilation

whisper.cpp is compiled as a static library (`libwhisper.a`) as part of HushType's build process. The library is built with Metal support enabled and optimized for the target architecture.

> 🍎 **macOS-specific**: The build process uses `xcrun` and targets the macOS SDK directly, ensuring compatibility with Apple's code signing and notarization requirements.

The build configuration in the Xcode project references a custom CMake-based build step:

```bash
# Build whisper.cpp as a static library with Metal support
cd vendor/whisper.cpp

mkdir -p build && cd build

cmake .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DWHISPER_METAL=ON \
  -DWHISPER_COREML=OFF \
  -DWHISPER_NO_AVX=OFF \
  -DWHISPER_NO_AVX2=OFF \
  -DWHISPER_NO_F16C=OFF \
  -DBUILD_SHARED_LIBS=OFF \
  -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="14.0" \
  -DCMAKE_INSTALL_PREFIX="../install"

cmake --build . --config Release --target whisper -- -j$(sysctl -n hw.ncpu)
cmake --install . --config Release
```

This produces:
- `install/lib/libwhisper.a` — the static library (universal binary)
- `install/include/whisper.h` — the public C header
- `install/share/whisper/ggml-metal.metal` — the Metal shader source

> ⚠️ **Warning**: When building a universal binary (`arm64;x86_64`), ensure both architecture slices link correctly. Use `lipo -info libwhisper.a` to verify.

The Xcode project includes the static library via:
1. **Library Search Paths**: `$(PROJECT_DIR)/vendor/whisper.cpp/install/lib`
2. **Header Search Paths**: `$(PROJECT_DIR)/vendor/whisper.cpp/install/include`
3. **Other Linker Flags**: `-lwhisper -lstdc++ -framework Metal -framework MetalKit -framework Accelerate`

### 1.2 Bridging Headers and Swift-C Interop

Swift communicates with whisper.cpp through a bridging header that exposes the C API, combined with a Swift wrapper layer that provides type-safe, idiomatic Swift interfaces.

**Bridging Header** (`HushType-Bridging-Header.h`):

```c
//
//  HushType-Bridging-Header.h
//  HushType
//
//  Bridges whisper.cpp C API into Swift
//

#ifndef HushType_Bridging_Header_h
#define HushType_Bridging_Header_h

#include "whisper.h"

// Additional helper declarations for Swift interop
// whisper.h uses opaque pointer types that Swift can consume directly

#endif /* HushType_Bridging_Header_h */
```

**Swift Wrapper** (`WhisperBridge.swift`):

```swift
import Foundation

/// Thread-safe bridge to whisper.cpp C API.
/// All whisper context operations are serialized on a dedicated dispatch queue.
final class WhisperBridge: @unchecked Sendable {

    // MARK: - Types

    struct TranscriptionResult: Sendable {
        let text: String
        let segments: [Segment]
        let language: String
        let languageProbability: Float
        let processingTimeMs: Int64
    }

    struct Segment: Sendable {
        let text: String
        let startMs: Int64
        let endMs: Int64
        let probability: Float
        let isPartial: Bool
    }

    enum WhisperError: Error, LocalizedError {
        case modelNotLoaded
        case contextInitFailed(path: String)
        case transcriptionFailed(code: Int32)
        case invalidAudioFormat
        case modelFileNotFound(path: String)
        case metalInitFailed

        var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "No whisper model is currently loaded."
            case .contextInitFailed(let path):
                return "Failed to initialize whisper context from: \(path)"
            case .transcriptionFailed(let code):
                return "Transcription failed with error code: \(code)"
            case .invalidAudioFormat:
                return "Audio data must be 16kHz mono Float32 PCM."
            case .modelFileNotFound(let path):
                return "Model file not found at: \(path)"
            case .metalInitFailed:
                return "Metal GPU acceleration initialization failed."
            }
        }
    }

    // MARK: - Properties

    private var context: OpaquePointer?
    private let queue = DispatchQueue(label: "com.hushtype.whisper", qos: .userInitiated)
    private(set) var isModelLoaded: Bool = false
    private(set) var currentModelPath: String?

    // MARK: - Lifecycle

    deinit {
        if let ctx = context {
            whisper_free(ctx)
        }
    }

    // MARK: - Model Loading

    /// Load a whisper model from disk.
    /// - Parameter path: Absolute path to the .bin model file.
    /// - Throws: `WhisperError` if the file is missing or context init fails.
    func loadModel(at path: String) async throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw WhisperError.modelFileNotFound(path: path)
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self else { return }

                // Free existing context if any
                if let existingCtx = self.context {
                    whisper_free(existingCtx)
                    self.context = nil
                    self.isModelLoaded = false
                }

                // Initialize context parameters with Metal enabled
                var params = whisper_context_default_params()
                params.use_gpu = true
                params.gpu_device = 0

                guard let ctx = whisper_init_from_file_with_params(path, params) else {
                    continuation.resume(throwing: WhisperError.contextInitFailed(path: path))
                    return
                }

                self.context = ctx
                self.isModelLoaded = true
                self.currentModelPath = path
                continuation.resume()
            }
        }
    }

    /// Unload the current model and free all associated resources.
    func unloadModel() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [weak self] in
                guard let self else { return }
                if let ctx = self.context {
                    whisper_free(ctx)
                    self.context = nil
                }
                self.isModelLoaded = false
                self.currentModelPath = nil
                continuation.resume()
            }
        }
    }
}
```

> ℹ️ **Info**: The `@unchecked Sendable` conformance is intentional — all mutable state access is serialized through the dedicated `queue`. This is safe under Swift's concurrency model as long as all access goes through the queue.

### 1.3 Metal GPU Acceleration

whisper.cpp uses Metal shaders to accelerate matrix multiplication and other compute-heavy operations on Apple GPUs. HushType bundles the Metal shader source and compiles it at runtime.

```swift
extension WhisperBridge {

    /// Verifies that Metal GPU acceleration is available and functional.
    /// - Returns: `true` if Metal is available and the GPU device was found.
    func verifyMetalAvailability() -> Bool {
        guard let device = MTLCreateSystemDefaultDevice() else {
            Logger.speech.warning("No Metal-capable GPU device found")
            return false
        }

        Logger.speech.info(
            "Metal GPU available: \(device.name), "
            + "recommended max working set: \(device.recommendedMaxWorkingSetSize / 1024 / 1024) MB"
        )
        return true
    }

    /// Returns the path to the bundled Metal shader source file.
    /// whisper.cpp compiles this at runtime when `use_gpu = true`.
    static var metalShaderPath: String? {
        Bundle.main.path(forResource: "ggml-metal", ofType: "metal")
    }
}
```

> 🍎 **macOS-specific**: Metal acceleration is available on all Apple Silicon Macs and Intel Macs with discrete or integrated GPUs that support Metal. On Apple Silicon, the unified memory architecture allows the GPU to access model weights without copying, significantly reducing latency.

The Metal shader file (`ggml-metal.metal`) must be included in the app bundle's Resources. Add it to the Xcode project's "Copy Bundle Resources" build phase.

> 💡 **Tip**: To verify Metal is being used at runtime, set the environment variable `GGML_METAL_LOG_LEVEL=2` during development. This prints detailed Metal kernel dispatch information to the console.

### 1.4 Architecture Overview Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                       HushType Application                       │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────┐    ┌──────────────────┐    ┌────────────┐  │
│  │   SwiftUI Views  │    │  WhisperBridge   │    │  Model     │  │
│  │                  │───▶│  (Swift Wrapper)  │───▶│  Manager   │  │
│  │  - RecordButton  │    │                  │    │            │  │
│  │  - Transcript    │    │  - loadModel()   │    │  - download│  │
│  │  - Settings      │    │  - transcribe()  │    │  - verify  │  │
│  └─────────────────┘    │  - streaming()   │    │  - select  │  │
│           │              └────────┬─────────┘    └────────────┘  │
│           │                       │                              │
│           ▼                       ▼                              │
│  ┌─────────────────┐    ┌──────────────────┐                    │
│  │  AudioCapture    │    │  Bridging Header │                    │
│  │  Pipeline        │    │  (C ↔ Swift)     │                    │
│  │                  │    └────────┬─────────┘                    │
│  │  - AVAudioEngine │            │                               │
│  │  - VAD           │            ▼                               │
│  │  - NoiseGate     │    ┌──────────────────┐                    │
│  │  - Resampler     │    │  libwhisper.a    │                    │
│  └────────┬─────────┘    │  (Static Library) │                   │
│           │              │                  │                    │
│           │              │  ┌────────────┐  │                    │
│           └─────────────▶│  │ C API      │  │                    │
│              PCM Float32 │  ├────────────┤  │                    │
│              16kHz mono  │  │ ggml       │  │                    │
│                          │  ├────────────┤  │                    │
│                          │  │ Metal GPU  │──┼──▶ Apple GPU       │
│                          │  └────────────┘  │                    │
│                          └──────────────────┘                    │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

---

## 2. Model Management

HushType supports multiple Whisper model sizes, allowing users to choose the optimal balance between speed, accuracy, and resource consumption.

### 2.1 Supported Models

| Model | Params | Disk Size | VRAM (approx.) | Speed (Apple Silicon) | Speed (Intel) | Relative Accuracy | Best For |
|-------|--------|-----------|-----------------|----------------------|---------------|-------------------|----------|
| `tiny` | 39M | 75 MB | ~200 MB | ~10x realtime | ~4x realtime | Baseline | Quick drafts, low-resource machines |
| `base` | 74M | 148 MB | ~350 MB | ~7x realtime | ~3x realtime | +10% vs tiny | Daily use on constrained hardware |
| `small` | 244M | 488 MB | ~850 MB | ~4x realtime | ~1.5x realtime | +25% vs tiny | **Recommended default** |
| `medium` | 769M | 1.5 GB | ~2.5 GB | ~2x realtime | ~0.5x realtime | +35% vs tiny | High-accuracy needs |
| `large-v3` | 1550M | 3.1 GB | ~4.8 GB | ~1x realtime | ~0.2x realtime | +40% vs tiny | Maximum accuracy, Apple Silicon only |

> ⚠️ **Warning**: The `large-v3` model requires substantial memory and is impractical on Intel Macs with less than 16 GB RAM. On Apple Silicon, the unified memory architecture makes it feasible on machines with 16 GB or more.

> 💡 **Tip**: For most users, the `small` model offers the best balance of speed and accuracy. Start there and adjust based on your hardware and accuracy needs.

### 2.2 Download Flow

Models are downloaded from Hugging Face's CDN on first use. The download is performed in the background with progress reporting, integrity verification via SHA-256 checksums, and automatic retry on failure.

```swift
import Foundation
import CryptoKit

/// Manages Whisper model downloads, verification, and storage.
actor ModelManager {

    // MARK: - Types

    struct ModelInfo: Sendable, Codable, Identifiable {
        let id: String           // e.g., "ggml-small"
        let displayName: String  // e.g., "Small (488 MB)"
        let fileName: String     // e.g., "ggml-small.bin"
        let sizeBytes: Int64
        let sha256: String
        let downloadURL: URL
    }

    enum DownloadState: Sendable {
        case idle
        case downloading(progress: Double)
        case verifying
        case ready
        case failed(Error)
    }

    enum ModelError: Error, LocalizedError {
        case checksumMismatch(expected: String, actual: String)
        case downloadFailed(statusCode: Int)
        case insufficientDiskSpace(required: Int64, available: Int64)
        case modelNotFound(id: String)

        var errorDescription: String? {
            switch self {
            case .checksumMismatch(let expected, let actual):
                return "Checksum mismatch. Expected: \(expected.prefix(12))..., got: \(actual.prefix(12))..."
            case .downloadFailed(let code):
                return "Download failed with HTTP status \(code)."
            case .insufficientDiskSpace(let required, let available):
                let req = ByteCountFormatter.string(fromByteCount: required, countStyle: .file)
                let avail = ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
                return "Insufficient disk space. Required: \(req), available: \(avail)."
            case .modelNotFound(let id):
                return "Model '\(id)' not found in the registry."
            }
        }
    }

    // MARK: - Properties

    static let modelsDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("HushType", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("whisper", isDirectory: true)
    }()

    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var stateCallbacks: [String: (DownloadState) -> Void] = [:]

    // MARK: - Registry

    static let availableModels: [ModelInfo] = [
        ModelInfo(
            id: "ggml-tiny",
            displayName: "Tiny (75 MB)",
            fileName: "ggml-tiny.bin",
            sizeBytes: 75_000_000,
            sha256: "bd577a113a864445d4c7f519f9b0822db",  // abbreviated
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin")!
        ),
        ModelInfo(
            id: "ggml-base",
            displayName: "Base (148 MB)",
            fileName: "ggml-base.bin",
            sizeBytes: 148_000_000,
            sha256: "465707469ff3a37a2b9b8d8f89f97f2c3",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin")!
        ),
        ModelInfo(
            id: "ggml-small",
            displayName: "Small (488 MB)",
            fileName: "ggml-small.bin",
            sizeBytes: 488_000_000,
            sha256: "55356645c2b361a969dfd0ef2c5a50d72",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin")!
        ),
        ModelInfo(
            id: "ggml-medium",
            displayName: "Medium (1.5 GB)",
            fileName: "ggml-medium.bin",
            sizeBytes: 1_500_000_000,
            sha256: "fd9727b63525adb262b8ec317dd2ad8b5",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin")!
        ),
        ModelInfo(
            id: "ggml-large-v3",
            displayName: "Large v3 (3.1 GB)",
            fileName: "ggml-large-v3.bin",
            sizeBytes: 3_100_000_000,
            sha256: "ad82bf6a9043cba5e2577e0c9c1c8a9b2",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin")!
        ),
    ]

    // MARK: - Download

    /// Download a model by ID with progress reporting.
    func downloadModel(
        id: String,
        onStateChange: @escaping @Sendable (DownloadState) -> Void
    ) async throws {
        guard let model = Self.availableModels.first(where: { $0.id == id }) else {
            throw ModelError.modelNotFound(id: id)
        }

        // Check disk space
        let availableSpace = try availableDiskSpace()
        let requiredSpace = model.sizeBytes + (model.sizeBytes / 10)  // 10% buffer
        guard availableSpace > requiredSpace else {
            throw ModelError.insufficientDiskSpace(required: requiredSpace, available: availableSpace)
        }

        // Ensure directory exists
        try FileManager.default.createDirectory(
            at: Self.modelsDirectory,
            withIntermediateDirectories: true
        )

        onStateChange(.downloading(progress: 0))

        let destinationURL = Self.modelsDirectory.appendingPathComponent(model.fileName)
        let tempURL = try await downloadFile(from: model.downloadURL) { progress in
            onStateChange(.downloading(progress: progress))
        }

        // Verify checksum
        onStateChange(.verifying)
        let actualHash = try sha256Hash(of: tempURL)
        guard actualHash == model.sha256 else {
            try? FileManager.default.removeItem(at: tempURL)
            throw ModelError.checksumMismatch(expected: model.sha256, actual: actualHash)
        }

        // Move to final location (atomic replace)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)

        onStateChange(.ready)
    }

    /// Check if a model is already downloaded and ready.
    func isModelAvailable(id: String) -> Bool {
        guard let model = Self.availableModels.first(where: { $0.id == id }) else {
            return false
        }
        let path = Self.modelsDirectory.appendingPathComponent(model.fileName)
        return FileManager.default.fileExists(atPath: path.path)
    }

    /// Get the file path for a downloaded model.
    func modelPath(for id: String) -> URL? {
        guard let model = Self.availableModels.first(where: { $0.id == id }) else {
            return nil
        }
        let path = Self.modelsDirectory.appendingPathComponent(model.fileName)
        return FileManager.default.fileExists(atPath: path.path) ? path : nil
    }

    // MARK: - Private Helpers

    private func downloadFile(
        from url: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let (tempURL, response) = try await URLSession.shared.download(from: url, delegate: nil)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ModelError.downloadFailed(statusCode: code)
        }
        return tempURL
    }

    private func sha256Hash(of fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func availableDiskSpace() throws -> Int64 {
        let values = try URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values.volumeAvailableCapacityForImportantUsage ?? 0
    }
}
```

> 🔒 **Security**: Model files are verified with SHA-256 checksums before being moved to the final storage location. If the hash does not match, the partially downloaded file is deleted. This protects against corrupted or tampered downloads.

### 2.3 Storage Layout

```
~/Library/Application Support/HushType/
└── Models/
    └── whisper/
        ├── ggml-tiny.bin          # 75 MB
        ├── ggml-base.bin          # 148 MB
        ├── ggml-small.bin         # 488 MB    (default)
        ├── ggml-medium.bin        # 1.5 GB
        └── ggml-large-v3.bin      # 3.1 GB
```

> 🍎 **macOS-specific**: The `~/Library/Application Support/` directory is the standard location for application data on macOS. It is excluded from iCloud backup by default unless explicitly configured otherwise. HushType does **not** sync models to iCloud — they must be downloaded on each machine.

### 2.4 Model Selection UI

The model selection interface displays each model's status (downloaded, downloading, not available), size, and a brief description of its accuracy and speed characteristics. Users can download, delete, or select a model as the active model.

```swift
import SwiftUI

struct ModelSelectionView: View {
    @State private var downloadStates: [String: ModelManager.DownloadState] = [:]
    @AppStorage("selectedModelId") private var selectedModelId: String = "ggml-small"

    private let modelManager = ModelManager()

    var body: some View {
        Form {
            Section("Whisper Models") {
                ForEach(ModelManager.availableModels) { model in
                    ModelRowView(
                        model: model,
                        isSelected: selectedModelId == model.id,
                        downloadState: downloadStates[model.id] ?? .idle,
                        onSelect: { selectedModelId = model.id },
                        onDownload: { downloadModel(model) },
                        onDelete: { deleteModel(model) }
                    )
                }
            }

            Section {
                Text("Selected model: **\(selectedModelId)**")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } footer: {
                Text("Larger models provide better accuracy but require more memory and are slower. The Small model is recommended for most users.")
            }
        }
        .formStyle(.grouped)
    }

    private func downloadModel(_ model: ModelManager.ModelInfo) {
        Task {
            try await modelManager.downloadModel(id: model.id) { state in
                Task { @MainActor in
                    downloadStates[model.id] = state
                }
            }
        }
    }

    private func deleteModel(_ model: ModelManager.ModelInfo) {
        let path = ModelManager.modelsDirectory.appendingPathComponent(model.fileName)
        try? FileManager.default.removeItem(at: path)
        downloadStates[model.id] = .idle
        if selectedModelId == model.id {
            selectedModelId = "ggml-small"
        }
    }
}
```

### 2.5 Model Loading and Switching

Switching between models at runtime involves unloading the current context and loading a new one. This operation is asynchronous and blocks transcription until complete.

```swift
/// Coordinates model loading and switching for the speech recognition engine.
@MainActor
final class SpeechRecognitionEngine: ObservableObject {

    @Published var currentModelId: String?
    @Published var isLoading: Bool = false
    @Published var loadError: String?

    private let whisperBridge = WhisperBridge()
    private let modelManager = ModelManager()

    /// Switch to a different Whisper model.
    /// Unloads the current model, loads the new one, and updates published state.
    func switchModel(to modelId: String) async {
        isLoading = true
        loadError = nil

        // Unload current model
        await whisperBridge.unloadModel()
        currentModelId = nil

        // Resolve path
        guard let modelPath = await modelManager.modelPath(for: modelId) else {
            loadError = "Model '\(modelId)' is not downloaded."
            isLoading = false
            return
        }

        do {
            try await whisperBridge.loadModel(at: modelPath.path)
            currentModelId = modelId
            Logger.speech.info("Switched to model: \(modelId)")
        } catch {
            loadError = error.localizedDescription
            Logger.speech.error("Failed to load model \(modelId): \(error)")
        }

        isLoading = false
    }
}
```

> ℹ️ **Info**: Model switching typically takes 200ms–2s depending on model size and whether the previous model's memory has been fully reclaimed. The `large-v3` model may take longer on Intel Macs due to memory pressure.

---

## 3. Audio Preprocessing Pipeline

The audio preprocessing pipeline captures microphone input, converts it to the format Whisper expects (16kHz mono Float32 PCM), applies voice activity detection and noise gating, and manages audio buffers for both streaming and batch transcription.

### 3.1 AVAudioEngine Setup

HushType uses `AVAudioEngine` for audio capture, which provides low-latency access to the system's audio input hardware through a tap on the input node.

```swift
import AVFoundation
import Combine

/// Captures audio from the system microphone using AVAudioEngine.
/// Produces 16kHz mono Float32 PCM samples for Whisper consumption.
final class AudioCapturePipeline: ObservableObject {

    // MARK: - Published State

    @Published var isCapturing: Bool = false
    @Published var audioLevel: Float = 0.0        // 0.0 – 1.0, for UI meters
    @Published var isVoiceDetected: Bool = false

    // MARK: - Properties

    private let engine = AVAudioEngine()
    private let targetSampleRate: Double = 16_000
    private let targetChannelCount: AVAudioChannelCount = 1
    private var converter: AVAudioConverter?

    private var audioBuffer: [Float] = []
    private let bufferLock = NSLock()

    private let vad = VoiceActivityDetector()
    private let noiseGate = NoiseGate()

    // Callback for streaming: called with new PCM samples as they arrive
    var onAudioSamples: (([Float]) -> Void)?

    // MARK: - Target Format

    private var targetFormat: AVAudioFormat {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: targetChannelCount,
            interleaved: false
        )!
    }

    // MARK: - Start / Stop

    /// Begin capturing audio from the default input device.
    /// - Throws: If the audio engine cannot start or the input node is unavailable.
    func startCapture() throws {
        guard !isCapturing else { return }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0 else {
            throw AudioCaptureError.noInputDevice
        }

        // Create the sample-rate converter
        guard let conv = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioCaptureError.converterInitFailed
        }
        self.converter = conv

        // Reset buffers
        bufferLock.lock()
        audioBuffer.removeAll(keepingCapacity: true)
        bufferLock.unlock()

        // Install tap on input node
        let bufferSize: AVAudioFrameCount = 4096
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) {
            [weak self] buffer, time in
            self?.processInputBuffer(buffer, time: time)
        }

        try engine.start()
        isCapturing = true
    }

    /// Stop capturing audio and release resources.
    func stopCapture() {
        guard isCapturing else { return }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCapturing = false
    }

    /// Returns the accumulated audio buffer and clears it.
    /// Used for batch transcription after recording stops.
    func drainBuffer() -> [Float] {
        bufferLock.lock()
        let samples = audioBuffer
        audioBuffer.removeAll(keepingCapacity: true)
        bufferLock.unlock()
        return samples
    }

    // MARK: - Private Processing

    private func processInputBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        guard let converter = self.converter else { return }

        // Convert to 16kHz mono
        guard let convertedBuffer = convertBuffer(buffer, using: converter) else { return }
        guard let channelData = convertedBuffer.floatChannelData else { return }

        let frameCount = Int(convertedBuffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))

        // Update audio level for UI (RMS)
        let rms = computeRMS(samples)
        DispatchQueue.main.async { [weak self] in
            self?.audioLevel = min(rms * 3.0, 1.0)  // Scale for visual range
        }

        // Apply noise gate
        let gatedSamples = noiseGate.process(samples)

        // Voice activity detection
        let hasVoice = vad.detect(in: gatedSamples)
        DispatchQueue.main.async { [weak self] in
            self?.isVoiceDetected = hasVoice
        }

        // Accumulate for batch mode
        bufferLock.lock()
        audioBuffer.append(contentsOf: gatedSamples)
        bufferLock.unlock()

        // Notify streaming listeners
        if hasVoice {
            onAudioSamples?(gatedSamples)
        }
    }

    private func convertBuffer(
        _ input: AVAudioPCMBuffer,
        using converter: AVAudioConverter
    ) -> AVAudioPCMBuffer? {
        let ratio = targetSampleRate / input.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 1

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputFrameCapacity
        ) else { return nil }

        var error: NSError?
        var hasData = true

        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if hasData {
                outStatus.pointee = .haveData
                hasData = false
                return input
            }
            outStatus.pointee = .noDataNow
            return nil
        }

        if let error {
            Logger.audio.error("Audio conversion error: \(error)")
            return nil
        }

        return outputBuffer
    }

    private func computeRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return sqrt(sumOfSquares / Float(samples.count))
    }
}

enum AudioCaptureError: Error, LocalizedError {
    case noInputDevice
    case converterInitFailed
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .noInputDevice:
            return "No audio input device found."
        case .converterInitFailed:
            return "Failed to create audio format converter."
        case .permissionDenied:
            return "Microphone access was denied."
        }
    }
}
```

> 🍎 **macOS-specific**: On macOS 14+, microphone access requires explicit user permission. HushType requests this via `AVCaptureDevice.requestAccess(for: .audio)` at first launch. The `NSMicrophoneUsageDescription` key must be present in `Info.plist`.

### 3.2 Sample Rate Conversion

Whisper models expect audio at 16kHz mono. Most macOS input devices operate at 44.1kHz or 48kHz stereo. The `AVAudioConverter` handles the downsampling and channel mixing automatically.

```
Input Device          AVAudioConverter           Whisper
┌──────────────┐     ┌──────────────────┐     ┌──────────────┐
│ 48kHz Stereo │────▶│ Resample + Mix   │────▶│ 16kHz Mono   │
│ Float32      │     │ to 16kHz Mono    │     │ Float32 PCM  │
└──────────────┘     └──────────────────┘     └──────────────┘
```

> ℹ️ **Info**: The `AVAudioConverter` uses Apple's high-quality sample rate conversion algorithm internally. No additional anti-aliasing filters are needed.

### 3.3 Voice Activity Detection (VAD)

VAD determines whether a given audio segment contains speech. HushType uses an energy-based VAD with zero-crossing rate analysis to distinguish speech from silence and background noise.

```swift
import Accelerate

/// Energy-based voice activity detector with zero-crossing rate analysis.
/// Distinguishes speech from silence/noise using adaptive thresholds.
final class VoiceActivityDetector {

    // MARK: - Configuration

    struct Configuration {
        var energyThreshold: Float = 0.005        // Minimum RMS energy for speech
        var zeroCrossingThreshold: Float = 0.15   // Max zero-crossing rate for speech
        var hangoverFrames: Int = 8               // Frames to hold "voice" after drop
        var adaptiveAlpha: Float = 0.02           // Noise floor adaptation rate
    }

    // MARK: - State

    private var config: Configuration
    private var noiseFloor: Float = 0.001
    private var hangoverCounter: Int = 0
    private var isCurrentlyActive: Bool = false

    init(config: Configuration = Configuration()) {
        self.config = config
    }

    // MARK: - Detection

    /// Analyze a chunk of audio samples and return whether voice activity is detected.
    /// - Parameter samples: Audio samples (16kHz mono Float32 PCM).
    /// - Returns: `true` if voice activity is detected in this chunk.
    func detect(in samples: [Float]) -> Bool {
        guard !samples.isEmpty else { return false }

        // Compute RMS energy
        let energy = computeRMS(samples)

        // Compute zero-crossing rate
        let zcr = computeZeroCrossingRate(samples)

        // Adapt noise floor (slowly track ambient noise level)
        if !isCurrentlyActive {
            noiseFloor = noiseFloor * (1 - config.adaptiveAlpha) + energy * config.adaptiveAlpha
        }

        // Dynamic threshold: noise floor + configured minimum
        let dynamicThreshold = max(config.energyThreshold, noiseFloor * 3.0)

        // Speech detection: energy above threshold AND zero-crossing below speech range
        let speechDetected = energy > dynamicThreshold && zcr < config.zeroCrossingThreshold

        // Hangover logic: keep detecting voice for a few frames after energy drops
        if speechDetected {
            hangoverCounter = config.hangoverFrames
            isCurrentlyActive = true
        } else if hangoverCounter > 0 {
            hangoverCounter -= 1
            isCurrentlyActive = true
        } else {
            isCurrentlyActive = false
        }

        return isCurrentlyActive
    }

    /// Reset the detector state (call when starting a new recording session).
    func reset() {
        noiseFloor = 0.001
        hangoverCounter = 0
        isCurrentlyActive = false
    }

    // MARK: - Private

    private func computeRMS(_ samples: [Float]) -> Float {
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        return rms
    }

    private func computeZeroCrossingRate(_ samples: [Float]) -> Float {
        guard samples.count > 1 else { return 0 }
        var crossings = 0
        for i in 1..<samples.count {
            if (samples[i] >= 0) != (samples[i - 1] >= 0) {
                crossings += 1
            }
        }
        return Float(crossings) / Float(samples.count - 1)
    }
}
```

> 💡 **Tip**: The `hangoverFrames` parameter prevents the VAD from cutting off the end of words during brief pauses in speech. Increase it if you notice clipped word endings; decrease it for tighter silence trimming.

### 3.4 Noise Gate

The noise gate suppresses audio below a configurable threshold, reducing low-level background noise that can confuse the recognition model.

```swift
/// Simple noise gate that suppresses audio below a threshold.
final class NoiseGate {

    var threshold: Float = 0.003     // Gate opens above this RMS level
    var attackTime: Float = 0.005    // Seconds to fully open
    var releaseTime: Float = 0.05    // Seconds to fully close
    var sampleRate: Float = 16_000

    private var gateLevel: Float = 0.0

    /// Process a chunk of samples, applying the noise gate.
    /// - Parameter samples: Raw audio samples.
    /// - Returns: Gated audio samples.
    func process(_ samples: [Float]) -> [Float] {
        var output = [Float](repeating: 0, count: samples.count)

        let attackCoeff = 1.0 - exp(-1.0 / (attackTime * sampleRate))
        let releaseCoeff = 1.0 - exp(-1.0 / (releaseTime * sampleRate))

        for i in 0..<samples.count {
            let absSample = abs(samples[i])

            if absSample > threshold {
                gateLevel += attackCoeff * (1.0 - gateLevel)
            } else {
                gateLevel += releaseCoeff * (0.0 - gateLevel)
            }

            output[i] = samples[i] * gateLevel
        }

        return output
    }

    func reset() {
        gateLevel = 0.0
    }
}
```

### 3.5 Audio Level Monitoring

Audio levels are published to the UI layer for real-time feedback (microphone level meter). The RMS value is computed per buffer and smoothed for display.

```swift
/// Smoothed audio level suitable for driving a UI meter.
final class AudioLevelMonitor: ObservableObject {
    @Published var level: Float = 0.0
    @Published var peakLevel: Float = 0.0

    private var smoothingFactor: Float = 0.3
    private var peakDecayRate: Float = 0.95

    func update(rms: Float) {
        // Exponential smoothing
        let smoothedLevel = level * (1 - smoothingFactor) + rms * smoothingFactor

        // Peak tracking with decay
        let newPeak = max(peakLevel * peakDecayRate, rms)

        DispatchQueue.main.async { [weak self] in
            self?.level = smoothedLevel
            self?.peakLevel = newPeak
        }
    }

    func reset() {
        level = 0.0
        peakLevel = 0.0
    }
}
```

### 3.6 Buffer Management

Audio buffers accumulate samples during recording. For batch mode, the entire buffer is sent to Whisper after recording stops. For streaming mode, overlapping windows of audio are sent at regular intervals.

| Parameter | Batch Mode | Streaming Mode |
|-----------|-----------|----------------|
| Buffer strategy | Accumulate all | Sliding window |
| Window size | Full recording | 5 seconds |
| Overlap | N/A | 1 second |
| Memory growth | Linear with duration | Fixed (~320 KB) |
| Max duration | 5 minutes (configurable) | Unlimited |

> ⚠️ **Warning**: For batch mode, audio buffers grow linearly. A 5-minute recording at 16kHz mono produces approximately 9.6 MB of Float32 data. HushType enforces a configurable maximum recording duration (default: 5 minutes) to prevent excessive memory use.

### 3.7 Pipeline Diagram

```
┌─────────────┐
│  Microphone  │
│  (Hardware)  │
└──────┬──────┘
       │  48kHz Stereo (typical)
       ▼
┌─────────────────┐
│  AVAudioEngine   │
│  Input Node      │
│  (installTap)    │
└──────┬──────────┘
       │  Raw PCM buffers
       ▼
┌─────────────────┐
│  AVAudioConverter│
│  48kHz → 16kHz   │
│  Stereo → Mono   │
└──────┬──────────┘
       │  16kHz Mono Float32
       ▼
┌─────────────────┐
│  Noise Gate      │
│  Suppress low-   │
│  level noise     │
└──────┬──────────┘
       │
       ▼
┌─────────────────┐       ┌─────────────────┐
│  VAD (Voice      │──────▶│  Audio Level    │
│  Activity        │       │  Monitor (UI)   │
│  Detection)      │       └─────────────────┘
└──────┬──────────┘
       │  Voice-gated samples
       ▼
┌─────────────────┐
│  Buffer Manager  │
│                  │
│  ┌────────────┐ │    ┌──────────────────────┐
│  │ Batch:     │─┼───▶│ Full buffer → Whisper │
│  │ Accumulate │ │    │ (after recording)     │
│  └────────────┘ │    └──────────────────────┘
│                  │
│  ┌────────────┐ │    ┌──────────────────────┐
│  │ Streaming: │─┼───▶│ Sliding window →     │
│  │ Window     │ │    │ Whisper (periodic)    │
│  └────────────┘ │    └──────────────────────┘
│                  │
└─────────────────┘
```

---

## 4. Streaming vs Batch Transcription

HushType supports two transcription modes: batch (process after recording) and streaming (real-time partial results). Each mode has distinct performance characteristics and user experience implications.

### 4.1 Batch Transcription (Process After Recording)

In batch mode, audio is recorded in its entirety, then sent to Whisper for processing. This produces the highest-quality transcription because the model has access to the full audio context.

```swift
extension WhisperBridge {

    /// Transcribe a complete audio buffer in batch mode.
    /// - Parameters:
    ///   - samples: 16kHz mono Float32 PCM audio samples.
    ///   - language: ISO 639-1 language code, or `nil` for auto-detection.
    ///   - options: Transcription configuration options.
    /// - Returns: The transcription result with segments and timing info.
    func transcribeBatch(
        samples: [Float],
        language: String? = nil,
        options: TranscriptionOptions = .default
    ) async throws -> TranscriptionResult {
        guard isModelLoaded, context != nil else {
            throw WhisperError.modelNotLoaded
        }

        guard !samples.isEmpty else {
            return TranscriptionResult(
                text: "",
                segments: [],
                language: language ?? "en",
                languageProbability: 0,
                processingTimeMs: 0
            )
        }

        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self, let ctx = self.context else {
                    continuation.resume(throwing: WhisperError.modelNotLoaded)
                    return
                }

                let startTime = DispatchTime.now()

                // Configure parameters
                var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)

                params.n_threads = Int32(options.threadCount)
                params.translate = false
                params.no_timestamps = false
                params.single_segment = false
                params.print_special = false
                params.print_progress = false
                params.print_realtime = false
                params.print_timestamps = true

                // Beam search configuration
                if options.beamSize > 1 {
                    params.strategy = WHISPER_SAMPLING_BEAM_SEARCH
                    params.beam_search.beam_size = Int32(options.beamSize)
                }

                params.temperature = options.temperature
                params.temperature_inc = options.temperatureIncrement

                // Language setting
                if let lang = language {
                    lang.withCString { cStr in
                        params.language = cStr
                    }
                } else {
                    params.detect_language = true
                }

                // Prompt conditioning
                if let prompt = options.initialPrompt {
                    prompt.withCString { cStr in
                        params.initial_prompt = cStr
                    }
                }

                // Run inference
                let result = samples.withUnsafeBufferPointer { bufferPtr in
                    whisper_full(ctx, params, bufferPtr.baseAddress, Int32(samples.count))
                }

                guard result == 0 else {
                    continuation.resume(throwing: WhisperError.transcriptionFailed(code: result))
                    return
                }

                // Extract results
                let segmentCount = whisper_full_n_segments(ctx)
                var segments: [Segment] = []
                var fullText = ""

                for i in 0..<segmentCount {
                    let text = String(cString: whisper_full_get_segment_text(ctx, i))
                    let startMs = whisper_full_get_segment_t0(ctx, i) * 10
                    let endMs = whisper_full_get_segment_t1(ctx, i) * 10

                    // Average token probability for this segment
                    let tokenCount = whisper_full_n_tokens(ctx, i)
                    var probSum: Float = 0
                    for t in 0..<tokenCount {
                        probSum += whisper_full_get_token_p(ctx, i, t)
                    }
                    let avgProb = tokenCount > 0 ? probSum / Float(tokenCount) : 0

                    segments.append(Segment(
                        text: text,
                        startMs: Int64(startMs),
                        endMs: Int64(endMs),
                        probability: avgProb,
                        isPartial: false
                    ))
                    fullText += text
                }

                // Detect language
                let detectedLang: String
                let langProb: Float
                if language == nil {
                    let langId = whisper_full_lang_id(ctx)
                    detectedLang = String(cString: whisper_lang_str(langId))
                    langProb = 0.0  // Approximate; full lang probs require separate API
                } else {
                    detectedLang = language!
                    langProb = 1.0
                }

                let elapsed = DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds
                let elapsedMs = Int64(elapsed / 1_000_000)

                continuation.resume(returning: TranscriptionResult(
                    text: fullText.trimmingCharacters(in: .whitespacesAndNewlines),
                    segments: segments,
                    language: detectedLang,
                    languageProbability: langProb,
                    processingTimeMs: elapsedMs
                ))
            }
        }
    }
}

/// Configurable transcription options.
struct TranscriptionOptions: Sendable {
    var threadCount: Int = ProcessInfo.processInfo.activeProcessorCount
    var beamSize: Int = 1                   // 1 = greedy, >1 = beam search
    var temperature: Float = 0.0            // 0.0 = deterministic
    var temperatureIncrement: Float = 0.2
    var initialPrompt: String? = nil

    static let `default` = TranscriptionOptions()

    static let highAccuracy = TranscriptionOptions(
        beamSize: 5,
        temperature: 0.0,
        temperatureIncrement: 0.1
    )
}
```

> ✅ **Success**: Batch mode produces the most accurate transcription because Whisper processes the full audio context. It is the default mode for HushType's push-to-talk workflow.

### 4.2 Streaming Transcription (Real-Time Partial Results)

Streaming mode provides partial transcription results as the user speaks. This creates a more responsive user experience but with somewhat lower accuracy, since the model processes audio in overlapping windows without full future context.

```swift
/// Streaming transcription controller that feeds audio windows to Whisper periodically.
actor StreamingTranscriber {

    // MARK: - Types

    struct StreamingOptions: Sendable {
        var windowDurationSeconds: Double = 5.0
        var overlapDurationSeconds: Double = 1.0
        var updateIntervalSeconds: Double = 0.5
        var language: String? = nil
        var transcriptionOptions: TranscriptionOptions = .default
    }

    enum StreamingEvent: Sendable {
        case partialResult(text: String, isFinal: Bool)
        case languageDetected(language: String, probability: Float)
        case error(Error)
    }

    // MARK: - Properties

    private let whisperBridge: WhisperBridge
    private var audioWindow: [Float] = []
    private var confirmedText: String = ""
    private var isRunning: Bool = false
    private var options: StreamingOptions
    private var eventHandler: ((StreamingEvent) -> Void)?

    private let windowSizeInSamples: Int
    private let overlapSizeInSamples: Int

    // MARK: - Init

    init(whisperBridge: WhisperBridge, options: StreamingOptions = StreamingOptions()) {
        self.whisperBridge = whisperBridge
        self.options = options
        self.windowSizeInSamples = Int(options.windowDurationSeconds * 16_000)
        self.overlapSizeInSamples = Int(options.overlapDurationSeconds * 16_000)
    }

    // MARK: - Control

    /// Start streaming transcription.
    /// - Parameter handler: Called on each transcription update.
    func start(handler: @escaping @Sendable (StreamingEvent) -> Void) {
        self.eventHandler = handler
        self.isRunning = true
        self.audioWindow = []
        self.confirmedText = ""
    }

    /// Feed new audio samples into the streaming window.
    /// Triggers transcription when enough audio has accumulated.
    func feedAudio(_ samples: [Float]) async {
        guard isRunning else { return }

        audioWindow.append(contentsOf: samples)

        // Trim window to max size (keep most recent audio + overlap)
        if audioWindow.count > windowSizeInSamples {
            let excess = audioWindow.count - windowSizeInSamples
            audioWindow.removeFirst(excess)
        }

        // Only transcribe when we have enough audio
        let minSamplesForTranscription = Int(0.5 * 16_000)  // 500ms minimum
        guard audioWindow.count >= minSamplesForTranscription else { return }

        await transcribeCurrentWindow()
    }

    /// Stop streaming and produce the final transcription.
    func stop() async -> String {
        isRunning = false

        // Final transcription of remaining audio
        if !audioWindow.isEmpty {
            await transcribeCurrentWindow(isFinal: true)
        }

        let finalText = confirmedText
        audioWindow = []
        confirmedText = ""
        return finalText
    }

    // MARK: - Private

    private func transcribeCurrentWindow(isFinal: Bool = false) async {
        do {
            let result = try await whisperBridge.transcribeBatch(
                samples: audioWindow,
                language: options.language,
                options: options.transcriptionOptions
            )

            if isFinal {
                confirmedText += result.text
                eventHandler?(.partialResult(text: confirmedText, isFinal: true))
            } else {
                // Partial: show confirmed + current window result
                let displayText = confirmedText + result.text
                eventHandler?(.partialResult(text: displayText, isFinal: false))
            }

            if options.language == nil && !result.language.isEmpty {
                eventHandler?(.languageDetected(
                    language: result.language,
                    probability: result.languageProbability
                ))
            }
        } catch {
            eventHandler?(.error(error))
        }
    }
}
```

### 4.3 Tradeoffs Comparison

| Aspect | Batch Mode | Streaming Mode |
|--------|-----------|----------------|
| **Latency** | Full recording duration + processing | Near real-time (~500ms delay) |
| **Accuracy** | Highest (full context) | Slightly lower (partial context) |
| **Memory** | Linear with recording length | Fixed window size |
| **CPU/GPU usage** | Spike after recording | Continuous moderate load |
| **User experience** | Wait for result | Live preview as you speak |
| **Use case** | Push-to-talk, short utterances | Long dictation, live captioning |
| **Implementation** | Simpler | More complex (overlap, merging) |

> 💡 **Tip**: HushType defaults to batch mode for its push-to-talk workflow (record → release → transcribe). Streaming mode can be enabled in Settings for users who prefer real-time feedback during longer dictations.

### 4.4 Implementation Details

**Sliding Window Strategy for Streaming**:

```
Time ─────────────────────────────────────────────────▶

Audio:  [==========|==========|==========|==========]

Window 1: [==========XXXXX]
Window 2:      [XXXXX==========XXXXX]
Window 3:           [XXXXX==========XXXXX]
Window 4:                [XXXXX==========]

         ─────── overlap ───────
```

Each window contains the most recent N seconds of audio. The overlap region ensures no speech is lost between windows. Whisper processes each window independently, and the streaming controller merges results by aligning overlapping text segments.

**Result Merging**: When two consecutive windows produce overlapping text, the streaming controller performs string suffix matching to avoid duplicating words:

```swift
extension StreamingTranscriber {

    /// Merge overlapping text from consecutive transcription windows.
    /// Finds the longest common suffix of `existing` that matches a prefix of `incoming`.
    static func mergeOverlappingText(existing: String, incoming: String) -> String {
        let existingWords = existing.split(separator: " ").map(String.init)
        let incomingWords = incoming.split(separator: " ").map(String.init)

        guard !existingWords.isEmpty, !incomingWords.isEmpty else {
            return existing + incoming
        }

        // Find longest overlap (up to min of both arrays)
        let maxOverlap = min(existingWords.count, incomingWords.count)
        var bestOverlap = 0

        for overlapLength in stride(from: maxOverlap, through: 1, by: -1) {
            let existingSuffix = existingWords.suffix(overlapLength)
            let incomingPrefix = incomingWords.prefix(overlapLength)

            if Array(existingSuffix) == Array(incomingPrefix) {
                bestOverlap = overlapLength
                break
            }
        }

        if bestOverlap > 0 {
            let newWords = incomingWords.dropFirst(bestOverlap)
            if newWords.isEmpty {
                return existing
            }
            return existing + " " + newWords.joined(separator: " ")
        }

        return existing + " " + incoming
    }
}
```

---

## 5. Language Detection and Selection

Whisper natively supports 90+ languages with automatic language identification. HushType exposes this capability through both automatic detection and manual language selection.

### 5.1 Automatic Language Detection

When no language is specified, Whisper analyzes the first 30 seconds of audio to identify the language. This works well for monolingual speech but may struggle with very short utterances or heavily accented speech.

```swift
extension WhisperBridge {

    /// Detect the language of an audio sample without performing full transcription.
    /// - Parameter samples: At least 1 second of 16kHz mono Float32 PCM audio.
    /// - Returns: A ranked list of detected languages with probabilities.
    func detectLanguage(samples: [Float]) async throws -> [(language: String, probability: Float)] {
        guard isModelLoaded, let ctx = context else {
            throw WhisperError.modelNotLoaded
        }

        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
                params.detect_language = true
                params.n_threads = 4

                let result = samples.withUnsafeBufferPointer { bufferPtr in
                    whisper_full(ctx, params, bufferPtr.baseAddress, Int32(min(samples.count, 16_000 * 30)))
                }

                guard result == 0 else {
                    continuation.resume(throwing: WhisperError.transcriptionFailed(code: result))
                    return
                }

                // Collect language probabilities
                let langCount = whisper_lang_max_id() + 1
                var languages: [(language: String, probability: Float)] = []

                for i in 0..<langCount {
                    let langStr = String(cString: whisper_lang_str(i))
                    // Note: Full language probability extraction requires
                    // whisper_full_lang_id for the top detected language.
                    // For a ranked list, use the state's lang_probs if available.
                    languages.append((language: langStr, probability: 0.0))
                }

                let detectedId = whisper_full_lang_id(ctx)
                let detectedLang = String(cString: whisper_lang_str(detectedId))

                // Return top detected language first
                let topResult = [(language: detectedLang, probability: 1.0 as Float)]
                continuation.resume(returning: topResult)
            }
        }
    }
}
```

### 5.2 Manual Language Selection

Users can manually select a language to bypass auto-detection. This improves accuracy for known languages and eliminates the detection overhead.

```swift
/// Language selection model for the settings UI.
struct LanguageOption: Identifiable, Hashable {
    let id: String          // ISO 639-1 code (e.g., "en", "tr", "de")
    let name: String        // English name (e.g., "English")
    let nativeName: String  // Native name (e.g., "Turkce")

    static let autoDetect = LanguageOption(
        id: "auto",
        name: "Auto-Detect",
        nativeName: "Auto-Detect"
    )
}

/// Commonly used language options for the UI.
extension LanguageOption {
    static let commonLanguages: [LanguageOption] = [
        .autoDetect,
        LanguageOption(id: "en", name: "English", nativeName: "English"),
        LanguageOption(id: "tr", name: "Turkish", nativeName: "Turkce"),
        LanguageOption(id: "de", name: "German", nativeName: "Deutsch"),
        LanguageOption(id: "fr", name: "French", nativeName: "Francais"),
        LanguageOption(id: "es", name: "Spanish", nativeName: "Espanol"),
        LanguageOption(id: "it", name: "Italian", nativeName: "Italiano"),
        LanguageOption(id: "pt", name: "Portuguese", nativeName: "Portugues"),
        LanguageOption(id: "nl", name: "Dutch", nativeName: "Nederlands"),
        LanguageOption(id: "pl", name: "Polish", nativeName: "Polski"),
        LanguageOption(id: "ru", name: "Russian", nativeName: "Russkiy"),
        LanguageOption(id: "zh", name: "Chinese", nativeName: "Zhongwen"),
        LanguageOption(id: "ja", name: "Japanese", nativeName: "Nihongo"),
        LanguageOption(id: "ko", name: "Korean", nativeName: "Hangugeo"),
        LanguageOption(id: "ar", name: "Arabic", nativeName: "Al-Arabiyyah"),
        LanguageOption(id: "hi", name: "Hindi", nativeName: "Hindi"),
    ]
}
```

### 5.3 Supported Languages

Whisper supports the following 99 languages. Performance and accuracy vary by language, with English having the highest accuracy and less-resourced languages showing lower performance.

| Tier | Languages | Expected WER |
|------|-----------|-------------|
| **Tier 1** (Excellent) | English, Spanish, French, German, Italian, Portuguese, Dutch, Russian, Chinese, Japanese | < 5% |
| **Tier 2** (Good) | Turkish, Korean, Polish, Czech, Swedish, Danish, Norwegian, Finnish, Greek, Romanian, Hungarian, Bulgarian, Croatian, Slovak, Slovenian, Lithuanian, Latvian, Estonian | 5–10% |
| **Tier 3** (Fair) | Arabic, Hindi, Thai, Vietnamese, Indonesian, Malay, Filipino, Ukrainian, Serbian, Catalan, Galician, Basque, Welsh, Irish, Icelandic | 10–20% |
| **Tier 4** (Experimental) | Remaining languages (Swahili, Yoruba, Hausa, Amharic, etc.) | > 20% |

> ℹ️ **Info**: Word Error Rate (WER) estimates are approximate and based on common benchmarks. Actual performance depends heavily on audio quality, accent, speaking pace, and domain-specific vocabulary.

### 5.4 Language-Specific Optimizations

For certain languages, HushType applies specific post-processing rules to improve output quality:

```swift
/// Language-specific post-processing rules applied after Whisper transcription.
struct LanguagePostProcessor {

    /// Apply language-specific corrections to transcribed text.
    static func process(_ text: String, language: String) -> String {
        var result = text

        switch language {
        case "tr":
            // Turkish: Fix common i/I dotted vs dotless confusion
            result = fixTurkishDotting(result)
        case "de":
            // German: Capitalize nouns (Whisper sometimes lowercases them)
            result = fixGermanCapitalization(result)
        case "zh":
            // Chinese: Remove extraneous spaces between characters
            result = result.replacingOccurrences(of: " ", with: "")
        case "ja":
            // Japanese: Normalize punctuation
            result = normalizeJapanesePunctuation(result)
        default:
            break
        }

        return result
    }

    private static func fixTurkishDotting(_ text: String) -> String {
        // Turkish has both dotted (i, I) and dotless (ı, I) i characters
        // Whisper sometimes confuses these; apply common corrections
        var result = text
        let turkishCorrections: [String: String] = [
            "Istambul": "Istanbul",
            "Izmir": "Izmir",
        ]
        for (wrong, correct) in turkishCorrections {
            result = result.replacingOccurrences(of: wrong, with: correct)
        }
        return result
    }

    private static func fixGermanCapitalization(_ text: String) -> String {
        // Simplified: in practice, this would use a noun dictionary
        return text
    }

    private static func normalizeJapanesePunctuation(_ text: String) -> String {
        text.replacingOccurrences(of: ".", with: "。")
            .replacingOccurrences(of: ",", with: "、")
    }
}
```

---

## 6. Performance Tuning Parameters

Whisper.cpp exposes several parameters that significantly affect transcription speed and accuracy. HushType provides sensible defaults and allows advanced users to tune these parameters.

### 6.1 Core Parameters

| Parameter | Default | Range | Effect |
|-----------|---------|-------|--------|
| `n_threads` | CPU core count | 1–16 | Number of CPU threads for inference |
| `beam_size` | 1 (greedy) | 1–10 | Beam search width; higher = more accurate but slower |
| `temperature` | 0.0 | 0.0–1.0 | Sampling temperature; 0 = deterministic |
| `temperature_inc` | 0.2 | 0.0–1.0 | Temperature increment on fallback attempts |
| `no_timestamps` | false | true/false | Skip timestamp generation (slight speedup) |
| `single_segment` | false | true/false | Force single-segment output |
| `max_tokens` | 0 (unlimited) | 0–448 | Max tokens per segment |
| `use_gpu` | true | true/false | Use Metal GPU acceleration |

```swift
/// Performance presets for different use cases.
enum PerformancePreset: String, CaseIterable, Identifiable {
    case fast = "Fast"
    case balanced = "Balanced"
    case accurate = "Accurate"

    var id: String { rawValue }

    var options: TranscriptionOptions {
        switch self {
        case .fast:
            return TranscriptionOptions(
                threadCount: ProcessInfo.processInfo.activeProcessorCount,
                beamSize: 1,
                temperature: 0.0,
                temperatureIncrement: 0.4,
                initialPrompt: nil
            )
        case .balanced:
            return TranscriptionOptions(
                threadCount: max(ProcessInfo.processInfo.activeProcessorCount - 2, 4),
                beamSize: 3,
                temperature: 0.0,
                temperatureIncrement: 0.2,
                initialPrompt: nil
            )
        case .accurate:
            return TranscriptionOptions(
                threadCount: max(ProcessInfo.processInfo.activeProcessorCount - 2, 4),
                beamSize: 5,
                temperature: 0.0,
                temperatureIncrement: 0.1,
                initialPrompt: nil
            )
        }
    }
}
```

### 6.2 Apple Silicon Optimization

Apple Silicon Macs benefit from the unified memory architecture and the Neural Engine. HushType automatically detects the chip family and adjusts parameters accordingly.

```swift
/// Determines optimal Whisper parameters for the current hardware.
struct HardwareOptimizer {

    struct HardwareProfile: Sendable {
        let chipFamily: ChipFamily
        let coreCount: Int
        let performanceCores: Int
        let efficiencyCores: Int
        let memoryGB: Int
        let gpuCores: Int
        let hasNeuralEngine: Bool
    }

    enum ChipFamily: Sendable {
        case appleSilicon(generation: String)  // "M1", "M2", "M3", "M4"
        case intel
    }

    /// Detect current hardware and return optimized transcription options.
    static func optimizedOptions(for modelSize: String) -> TranscriptionOptions {
        let profile = detectHardware()

        switch profile.chipFamily {
        case .appleSilicon:
            return appleSiliconOptions(profile: profile, modelSize: modelSize)
        case .intel:
            return intelOptions(profile: profile, modelSize: modelSize)
        }
    }

    private static func appleSiliconOptions(
        profile: HardwareProfile,
        modelSize: String
    ) -> TranscriptionOptions {
        // On Apple Silicon, use performance cores and leave efficiency cores for UI
        let threads = max(profile.performanceCores, 4)

        // Beam search is affordable on Apple Silicon
        let beamSize: Int
        switch modelSize {
        case "ggml-tiny", "ggml-base":
            beamSize = 5
        case "ggml-small":
            beamSize = 3
        case "ggml-medium":
            beamSize = 2
        case "ggml-large-v3":
            beamSize = 1  // Greedy to keep latency manageable
        default:
            beamSize = 3
        }

        return TranscriptionOptions(
            threadCount: threads,
            beamSize: beamSize,
            temperature: 0.0,
            temperatureIncrement: 0.2
        )
    }

    private static func intelOptions(
        profile: HardwareProfile,
        modelSize: String
    ) -> TranscriptionOptions {
        // On Intel, be more conservative with thread count
        let threads = max(profile.coreCount - 2, 2)

        // Greedy decoding for speed on Intel
        return TranscriptionOptions(
            threadCount: threads,
            beamSize: 1,
            temperature: 0.0,
            temperatureIncrement: 0.3
        )
    }

    private static func detectHardware() -> HardwareProfile {
        let processInfo = ProcessInfo.processInfo
        let coreCount = processInfo.activeProcessorCount
        let memoryGB = Int(processInfo.physicalMemory / (1024 * 1024 * 1024))

        // Detect Apple Silicon vs Intel
        #if arch(arm64)
        return HardwareProfile(
            chipFamily: .appleSilicon(generation: "M-series"),
            coreCount: coreCount,
            performanceCores: max(coreCount / 2, 4),
            efficiencyCores: coreCount / 2,
            memoryGB: memoryGB,
            gpuCores: 0,  // GPU core count not easily queryable
            hasNeuralEngine: true
        )
        #else
        return HardwareProfile(
            chipFamily: .intel,
            coreCount: coreCount,
            performanceCores: coreCount,
            efficiencyCores: 0,
            memoryGB: memoryGB,
            gpuCores: 0,
            hasNeuralEngine: false
        )
        #endif
    }
}
```

> 🍎 **macOS-specific**: On Apple Silicon, whisper.cpp offloads matrix multiplications to the Metal GPU via `ggml-metal`. The unified memory means no explicit data transfer between CPU and GPU is needed, resulting in lower latency than on discrete GPU systems.

### 6.3 Intel Mac Configuration

| Consideration | Recommendation |
|--------------|----------------|
| Max recommended model | `medium` (1.5 GB) |
| Thread count | Total cores minus 2 (minimum 2) |
| Beam search | Greedy (beam_size = 1) |
| GPU acceleration | Available if Metal-capable GPU present |
| Expected speed | 0.2x–3x realtime depending on model |
| Memory warning | 16 GB RAM minimum for `medium` |

> ⚠️ **Warning**: The `large-v3` model on Intel Macs will likely run slower than realtime and may cause memory pressure on systems with less than 32 GB RAM. HushType shows a warning when selecting `large-v3` on Intel hardware.

### 6.4 Memory Management

Whisper models are memory-mapped where possible, reducing the application's resident memory footprint. However, during inference, the working memory can be substantial:

```swift
extension WhisperBridge {

    /// Estimated memory requirements for a given model.
    static func estimatedMemory(forModel modelId: String) -> (modelMB: Int, workingMB: Int, totalMB: Int) {
        switch modelId {
        case "ggml-tiny":
            return (modelMB: 75, workingMB: 125, totalMB: 200)
        case "ggml-base":
            return (modelMB: 148, workingMB: 200, totalMB: 350)
        case "ggml-small":
            return (modelMB: 488, workingMB: 360, totalMB: 850)
        case "ggml-medium":
            return (modelMB: 1500, workingMB: 1000, totalMB: 2500)
        case "ggml-large-v3":
            return (modelMB: 3100, workingMB: 1700, totalMB: 4800)
        default:
            return (modelMB: 0, workingMB: 0, totalMB: 0)
        }
    }

    /// Check whether the system has enough memory for a model, accounting for current usage.
    static func canLoadModel(_ modelId: String) -> (canLoad: Bool, availableMB: Int, requiredMB: Int) {
        let (_, _, totalRequired) = estimatedMemory(forModel: modelId)

        let processInfo = ProcessInfo.processInfo
        let totalPhysical = Int(processInfo.physicalMemory / (1024 * 1024))
        // Conservative estimate: allow model to use up to 60% of total RAM
        let availableForModel = totalPhysical * 60 / 100

        return (
            canLoad: availableForModel >= totalRequired,
            availableMB: availableForModel,
            requiredMB: totalRequired
        )
    }
}
```

---

## 7. Custom Vocabulary Integration

HushType allows users to define custom vocabulary entries — domain-specific terms, proper nouns, abbreviations, and technical jargon — that improve recognition accuracy. Custom vocabulary works through two mechanisms: prompt conditioning and post-processing corrections.

### 7.1 Vocabulary Entry Format

```swift
import SwiftData

/// A user-defined custom vocabulary entry stored in SwiftData.
@Model
final class VocabularyEntry {
    /// The term as it should appear in the final text.
    var term: String

    /// Alternative spoken forms that should map to this term.
    /// Example: For term "PostgreSQL", spoken forms might be ["postgres", "post gres Q L"].
    var spokenForms: [String]

    /// Whether this entry should be included in Whisper prompt conditioning.
    var useForPromptConditioning: Bool

    /// Whether this entry should be applied as a post-processing replacement.
    var useForPostProcessing: Bool

    /// Optional category for organization (e.g., "Technical", "Names", "Medical").
    var category: String?

    /// Language code this entry applies to, or nil for all languages.
    var language: String?

    var createdAt: Date
    var updatedAt: Date

    init(
        term: String,
        spokenForms: [String] = [],
        useForPromptConditioning: Bool = true,
        useForPostProcessing: Bool = true,
        category: String? = nil,
        language: String? = nil
    ) {
        self.term = term
        self.spokenForms = spokenForms
        self.useForPromptConditioning = useForPromptConditioning
        self.useForPostProcessing = useForPostProcessing
        self.category = category
        self.language = language
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
```

### 7.2 Prompt Conditioning with Custom Vocabulary

Whisper supports an "initial prompt" parameter that biases the model toward specific vocabulary. HushType builds this prompt from the user's custom vocabulary entries.

```swift
/// Builds a Whisper prompt conditioning string from custom vocabulary.
struct VocabularyPromptBuilder {

    /// Build a prompt string from vocabulary entries.
    /// The prompt contains terms separated by commas, encouraging Whisper
    /// to recognize these terms during transcription.
    ///
    /// - Parameters:
    ///   - entries: Custom vocabulary entries.
    ///   - language: Current transcription language (for filtering).
    ///   - maxLength: Maximum prompt length in characters (Whisper limit ~224 tokens).
    /// - Returns: A prompt string suitable for `whisper_full_params.initial_prompt`.
    static func buildPrompt(
        from entries: [VocabularyEntry],
        language: String?,
        maxLength: Int = 500
    ) -> String? {
        let relevantEntries = entries.filter { entry in
            guard entry.useForPromptConditioning else { return false }
            if let entryLang = entry.language, let targetLang = language {
                return entryLang == targetLang
            }
            return true
        }

        guard !relevantEntries.isEmpty else { return nil }

        // Build prompt: "The following terms may appear: HushType, PostgreSQL, Kubernetes, ..."
        var prompt = "The following terms may appear: "
        var currentLength = prompt.count

        for (index, entry) in relevantEntries.enumerated() {
            let separator = index == 0 ? "" : ", "
            let addition = separator + entry.term

            if currentLength + addition.count > maxLength {
                break
            }

            prompt += addition
            currentLength += addition.count
        }

        return prompt + "."
    }
}
```

> ℹ️ **Info**: Prompt conditioning is a soft bias — it increases the probability of the listed terms appearing in the transcription but does not guarantee them. It works best when the terms are actually spoken in the audio. Overly long prompts may degrade overall accuracy.

### 7.3 Post-Processing Corrections

After Whisper produces a transcription, HushType applies post-processing rules based on custom vocabulary to correct common misrecognitions.

```swift
/// Applies post-processing corrections to transcribed text based on custom vocabulary.
struct VocabularyPostProcessor {

    /// Apply vocabulary-based corrections to transcribed text.
    /// - Parameters:
    ///   - text: Raw transcription from Whisper.
    ///   - entries: Custom vocabulary entries.
    ///   - language: Transcription language.
    /// - Returns: Corrected text.
    static func apply(
        to text: String,
        entries: [VocabularyEntry],
        language: String?
    ) -> String {
        var result = text

        let relevantEntries = entries.filter { entry in
            guard entry.useForPostProcessing else { return false }
            guard !entry.spokenForms.isEmpty else { return false }
            if let entryLang = entry.language, let targetLang = language {
                return entryLang == targetLang
            }
            return true
        }

        for entry in relevantEntries {
            for spokenForm in entry.spokenForms {
                // Case-insensitive whole-word replacement
                let pattern = "\\b\(NSRegularExpression.escapedPattern(for: spokenForm))\\b"
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let range = NSRange(result.startIndex..., in: result)
                    result = regex.stringByReplacingMatches(
                        in: result,
                        options: [],
                        range: range,
                        withTemplate: entry.term
                    )
                }
            }
        }

        return result
    }
}
```

Example vocabulary entries and their effect:

| Term | Spoken Forms | Before Correction | After Correction |
|------|-------------|-------------------|------------------|
| `HushType` | `hush type`, `hushtype` | "Open hush type settings" | "Open HushType settings" |
| `PostgreSQL` | `postgres`, `post gres` | "Connect to the postgres database" | "Connect to the PostgreSQL database" |
| `Kubernetes` | `kubernetes`, `k8s` | "Deploy to kubernetes" | "Deploy to Kubernetes" |
| `async/await` | `async await`, `a sync a wait` | "Use a sync a wait pattern" | "Use async/await pattern" |

---

## 8. Accuracy Optimization Techniques

### 8.1 Model Selection Strategy

Choosing the right model is the single most impactful decision for transcription accuracy. Use this decision tree:

```
                    Start Here
                        │
                        ▼
              ┌─────────────────────┐
              │  Apple Silicon Mac?  │
              └──────┬──────────────┘
                     │
              ┌──────┴──────┐
              ▼              ▼
             Yes             No (Intel)
              │              │
              ▼              ▼
     ┌────────────┐  ┌─────────────┐
     │ RAM >= 16GB│  │ Use small   │
     └──┬─────────┘  │ (488 MB)    │
        │            └─────────────┘
   ┌────┴────┐
   ▼         ▼
  Yes        No
   │         │
   ▼         ▼
┌────────┐ ┌──────────┐
│ Need    │ │ Use small│
│ max     │ │ (488 MB) │
│accuracy?│ └──────────┘
└──┬─────┘
   │
┌──┴──┐
▼     ▼
Yes   No
│     │
▼     ▼
Use   Use
large small
-v3   or
(3.1  medium
 GB)
```

**Recommended Model by Use Case**:

| Use Case | Recommended Model | Reason |
|----------|------------------|--------|
| Quick notes, drafts | `tiny` or `base` | Speed over accuracy |
| Daily use, emails | `small` | Best balance |
| Professional transcription | `medium` or `large-v3` | Accuracy critical |
| Technical dictation (code) | `medium` + custom vocab | Handles jargon better |
| Multi-language | `large-v3` | Best cross-language performance |

### 8.2 Prompt Conditioning

Beyond custom vocabulary, Whisper's initial prompt can be used to set context and improve recognition of domain-specific content:

```swift
/// Context-aware prompt conditioning based on the active processing mode.
struct ContextPromptBuilder {

    /// Build a context prompt based on the processing mode and user context.
    static func buildPrompt(
        mode: ProcessingMode,
        customVocab: [VocabularyEntry],
        language: String?,
        previousText: String? = nil
    ) -> String? {
        var parts: [String] = []

        // Mode-specific context
        switch mode {
        case .raw:
            break  // No prompt conditioning for raw mode
        case .clean:
            parts.append("Transcribe clearly with proper punctuation and grammar.")
        case .structure:
            parts.append("This is structured content with headings, lists, or paragraphs.")
        case .prompt:
            parts.append("This is a prompt or instruction being dictated.")
        case .code:
            parts.append(
                "This is programming-related content. "
                + "Terms like function, variable, class, struct, enum, protocol, "
                + "async, await, import, return may appear."
            )
        case .custom:
            break  // User defines their own context
        }

        // Add custom vocabulary terms
        if let vocabPrompt = VocabularyPromptBuilder.buildPrompt(
            from: customVocab,
            language: language,
            maxLength: 300
        ) {
            parts.append(vocabPrompt)
        }

        // Add previous text for continuity (last ~100 chars)
        if let prev = previousText, !prev.isEmpty {
            let suffix = String(prev.suffix(100))
            parts.append(suffix)
        }

        let prompt = parts.joined(separator: " ")
        return prompt.isEmpty ? nil : prompt
    }
}

/// HushType processing modes.
enum ProcessingMode: String, CaseIterable, Identifiable, Codable {
    case raw = "Raw"
    case clean = "Clean"
    case structure = "Structure"
    case prompt = "Prompt"
    case code = "Code"
    case custom = "Custom"

    var id: String { rawValue }
}
```

> 💡 **Tip**: For best results with prompt conditioning, keep the prompt concise (under 224 tokens) and relevant to the expected content. A prompt that does not match the actual speech can decrease accuracy.

### 8.3 Audio Quality Tips

Audio quality has a dramatic impact on transcription accuracy. HushType provides the following guidance to users:

| Factor | Impact | Recommendation |
|--------|--------|---------------|
| **Microphone distance** | High | Keep microphone 6–12 inches from mouth |
| **Background noise** | High | Use in a quiet environment or use a directional mic |
| **Speaking pace** | Medium | Speak naturally; avoid rushing or extreme slowness |
| **Microphone quality** | Medium | USB condenser or headset mic > built-in laptop mic |
| **Pop filter** | Low | Reduces plosive sounds (p, b, t) that cause artifacts |
| **Sample rate** | Low | HushType handles conversion; native 48kHz is fine |
| **Echo** | Medium | Avoid large, reverberant rooms |

---

## 9. Handling Edge Cases

### 9.1 Background Noise

Background noise is the most common source of transcription errors. HushType mitigates noise through the audio preprocessing pipeline (noise gate + VAD) and model-level robustness.

```swift
/// Adaptive noise profile that adjusts to the ambient environment.
final class AdaptiveNoiseProfile: ObservableObject {
    @Published var estimatedNoiseLevel: Float = 0.0
    @Published var noiseDescription: String = "Quiet"

    private var samples: [Float] = []
    private let calibrationDuration: Int = 16_000  // 1 second at 16kHz

    /// Calibrate the noise profile from a silent recording.
    /// Call this when the user is NOT speaking to establish a noise baseline.
    func calibrate(silentSamples: [Float]) {
        guard !silentSamples.isEmpty else { return }

        var rms: Float = 0
        vDSP_rmsqv(silentSamples, 1, &rms, vDSP_Length(silentSamples.count))

        estimatedNoiseLevel = rms

        // Classify noise level
        switch rms {
        case 0..<0.002:
            noiseDescription = "Quiet"
        case 0.002..<0.01:
            noiseDescription = "Low Background Noise"
        case 0.01..<0.05:
            noiseDescription = "Moderate Background Noise"
        default:
            noiseDescription = "High Background Noise"
        }
    }

    /// Suggest adjustments based on the noise profile.
    var recommendations: [String] {
        var tips: [String] = []

        if estimatedNoiseLevel > 0.05 {
            tips.append("High noise detected. Consider moving to a quieter environment.")
            tips.append("Use a directional or headset microphone to reduce ambient noise.")
            tips.append("Consider using a larger model (medium or large-v3) for better noise robustness.")
        } else if estimatedNoiseLevel > 0.01 {
            tips.append("Moderate noise detected. Results should be acceptable with the small model or larger.")
        }

        return tips
    }
}
```

**Noise mitigation strategies by severity**:

| Noise Level | VAD Threshold | Noise Gate Threshold | Recommended Model | Expected Impact |
|-------------|--------------|---------------------|-------------------|----------------|
| Quiet (< 0.002) | Default (0.005) | Default (0.003) | Any | Minimal |
| Low (0.002–0.01) | 0.008 | 0.005 | `small` or larger | Low WER increase |
| Moderate (0.01–0.05) | 0.015 | 0.01 | `medium` or larger | Moderate WER increase |
| High (> 0.05) | 0.03 | 0.02 | `large-v3` | Significant WER increase |

### 9.2 Accents and Dialects

Whisper is trained on a diverse multilingual dataset and handles most accents reasonably well. However, strong accents can still cause errors.

**Best practices for accented speech**:

1. **Use a larger model** — `medium` and `large-v3` handle accents significantly better than `tiny` or `base`.
2. **Set the language explicitly** — Auto-detection may misidentify the language for heavily accented speech.
3. **Use prompt conditioning** — Include region-specific terms in the initial prompt.
4. **Build custom vocabulary** — Add frequently misrecognized words to the vocabulary list.

### 9.3 Technical Jargon

Programming terms, acronyms, and domain-specific vocabulary are challenging for general-purpose speech recognition. HushType addresses this through the Code processing mode and custom vocabulary.

```swift
/// Built-in vocabulary for common programming terms.
/// Loaded automatically when the Code processing mode is active.
struct ProgrammingVocabulary {

    static let commonTerms: [(term: String, spokenForms: [String])] = [
        ("async/await", ["async await", "a sync a wait"]),
        ("boolean", ["boolean", "bool"]),
        ("StringBuilder", ["string builder"]),
        ("HashMap", ["hash map"]),
        ("GitHub", ["git hub", "github"]),
        ("GitLab", ["git lab", "gitlab"]),
        ("API", ["A P I", "api"]),
        ("URL", ["U R L", "url"]),
        ("JSON", ["J son", "jason"]),
        ("YAML", ["yam L", "yaml"]),
        ("HTTP", ["H T T P"]),
        ("HTTPS", ["H T T P S"]),
        ("SQL", ["S Q L", "sequel"]),
        ("NoSQL", ["no S Q L", "no sequel"]),
        ("REST", ["rest", "R E S T"]),
        ("GraphQL", ["graph Q L", "graph QL"]),
        ("OAuth", ["O auth", "oh auth"]),
        ("JWT", ["J W T", "jot"]),
        ("CRUD", ["crud", "C R U D"]),
        ("IDE", ["I D E"]),
        ("CLI", ["C L I"]),
        ("npm", ["N P M"]),
        ("pip", ["pip", "P I P"]),
        ("regex", ["regex", "reg ex", "regular expression"]),
        ("localhost", ["local host"]),
        ("sudo", ["sue doo", "pseudo"]),
        ("kubectl", ["cube control", "cube C T L", "kube control"]),
        ("Docker", ["docker"]),
        ("Kubernetes", ["kubernetes", "K 8 S"]),
        ("SwiftUI", ["swift U I", "swift you eye"]),
        ("UIKit", ["U I kit", "you eye kit"]),
        ("CoreData", ["core data"]),
        ("SwiftData", ["swift data"]),
        ("Xcode", ["X code", "ex code"]),
    ]
}
```

> 💡 **Tip**: When dictating code, speak punctuation explicitly: "open paren", "close bracket", "semicolon". HushType's Code processing mode with llama.cpp post-processing handles the conversion from spoken punctuation to symbols. See [Processing Modes](../api/API_DOCUMENTATION.md) for details.

### 9.4 Mixed-Language Speech

Mixed-language speech (code-switching) occurs frequently in multilingual environments — for example, switching between Turkish and English mid-sentence. This is one of Whisper's weaker areas.

**Mitigation strategies**:

1. **Use `large-v3`** — The largest model handles code-switching best, as it was trained on the most diverse dataset.
2. **Set language to the dominant language** — If most speech is in Turkish with occasional English terms, set language to `tr`. Whisper will still attempt to recognize the English portions.
3. **Use custom vocabulary for foreign terms** — Add commonly used English terms to the vocabulary when speaking primarily in another language.
4. **Avoid auto-detect for mixed speech** — Auto-detection locks to a single language based on the first 30 seconds, which may not represent the full recording.

```swift
/// Configuration for mixed-language scenarios.
struct MixedLanguageConfig {
    /// The primary language of the recording.
    let primaryLanguage: String

    /// Secondary language terms that may appear (for vocabulary conditioning).
    let secondaryTerms: [String]

    /// Build a prompt that hints at mixed-language content.
    func buildPrompt() -> String {
        var prompt = "The speaker primarily uses \(primaryLanguage)."
        if !secondaryTerms.isEmpty {
            let terms = secondaryTerms.prefix(20).joined(separator: ", ")
            prompt += " English terms such as \(terms) may also appear."
        }
        return prompt
    }
}
```

### 9.5 Long Utterances

Whisper processes audio in 30-second chunks internally. For recordings longer than 30 seconds, whisper.cpp automatically segments the audio. However, segment boundaries can occasionally split words or sentences awkwardly.

**HushType's handling of long recordings**:

1. **Automatic segmentation** — whisper.cpp handles chunking internally. HushType passes the full audio buffer and receives segmented results.
2. **Segment merging** — Adjacent segments are merged with attention to sentence boundaries to produce coherent text.
3. **Maximum duration** — Batch mode enforces a configurable maximum (default: 5 minutes). For longer dictations, streaming mode is recommended.
4. **Progress reporting** — For long recordings, HushType reports transcription progress based on the segment being processed.

```swift
extension WhisperBridge {

    /// Transcribe a long recording with progress reporting.
    /// - Parameters:
    ///   - samples: Audio samples (may exceed 30 seconds).
    ///   - language: Target language or nil for auto-detect.
    ///   - options: Transcription options.
    ///   - onProgress: Called with progress (0.0 to 1.0) as segments are processed.
    /// - Returns: Complete transcription result.
    func transcribeLong(
        samples: [Float],
        language: String? = nil,
        options: TranscriptionOptions = .default,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> TranscriptionResult {
        guard isModelLoaded, context != nil else {
            throw WhisperError.modelNotLoaded
        }

        let totalDuration = Double(samples.count) / 16_000.0
        Logger.speech.info("Starting long transcription: \(String(format: "%.1f", totalDuration))s of audio")

        // whisper_full handles long audio internally via its segmentation logic.
        // We use the progress callback to report status.
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self, let ctx = self.context else {
                    continuation.resume(throwing: WhisperError.modelNotLoaded)
                    return
                }

                let startTime = DispatchTime.now()

                var params = whisper_full_default_params(
                    options.beamSize > 1 ? WHISPER_SAMPLING_BEAM_SEARCH : WHISPER_SAMPLING_GREEDY
                )
                params.n_threads = Int32(options.threadCount)
                params.translate = false

                if options.beamSize > 1 {
                    params.beam_search.beam_size = Int32(options.beamSize)
                }

                params.temperature = options.temperature
                params.temperature_inc = options.temperatureIncrement

                if let lang = language {
                    lang.withCString { params.language = $0 }
                } else {
                    params.detect_language = true
                }

                if let prompt = options.initialPrompt {
                    prompt.withCString { params.initial_prompt = $0 }
                }

                // Progress callback
                let progressContext = UnsafeMutablePointer<(@Sendable (Double) -> Void)?>.allocate(capacity: 1)
                progressContext.initialize(to: onProgress)

                params.progress_callback_user_data = UnsafeMutableRawPointer(progressContext)
                params.progress_callback = { (ctx, state, progress, userData) in
                    guard let userData else { return }
                    let callback = userData.assumingMemoryBound(
                        to: ((@Sendable (Double) -> Void)?).self
                    ).pointee
                    callback?(Double(progress) / 100.0)
                }

                let result = samples.withUnsafeBufferPointer { bufferPtr in
                    whisper_full(ctx, params, bufferPtr.baseAddress, Int32(samples.count))
                }

                progressContext.deinitialize(count: 1)
                progressContext.deallocate()

                guard result == 0 else {
                    continuation.resume(throwing: WhisperError.transcriptionFailed(code: result))
                    return
                }

                // Extract all segments
                let segmentCount = whisper_full_n_segments(ctx)
                var segments: [Segment] = []
                var fullText = ""

                for i in 0..<segmentCount {
                    let text = String(cString: whisper_full_get_segment_text(ctx, i))
                    let t0 = whisper_full_get_segment_t0(ctx, i) * 10
                    let t1 = whisper_full_get_segment_t1(ctx, i) * 10

                    let tokenCount = whisper_full_n_tokens(ctx, i)
                    var probSum: Float = 0
                    for t in 0..<tokenCount {
                        probSum += whisper_full_get_token_p(ctx, i, t)
                    }
                    let avgProb = tokenCount > 0 ? probSum / Float(tokenCount) : 0

                    segments.append(Segment(
                        text: text,
                        startMs: Int64(t0),
                        endMs: Int64(t1),
                        probability: avgProb,
                        isPartial: false
                    ))
                    fullText += text
                }

                let detectedLang: String
                if language == nil {
                    let langId = whisper_full_lang_id(ctx)
                    detectedLang = String(cString: whisper_lang_str(langId))
                } else {
                    detectedLang = language!
                }

                let elapsed = DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds
                let elapsedMs = Int64(elapsed / 1_000_000)

                Logger.speech.info(
                    "Long transcription complete: \(segmentCount) segments, "
                    + "\(elapsedMs)ms processing time"
                )

                continuation.resume(returning: TranscriptionResult(
                    text: fullText.trimmingCharacters(in: .whitespacesAndNewlines),
                    segments: segments,
                    language: detectedLang,
                    languageProbability: 0,
                    processingTimeMs: elapsedMs
                ))
            }
        }
    }
}
```

**Segment boundary handling**:

| Issue | Cause | Mitigation |
|-------|-------|-----------|
| Split words | 30s chunk boundary falls mid-word | whisper.cpp uses overlap to minimize this |
| Repeated text | Overlap region causes duplicate tokens | Deduplication in post-processing |
| Lost context | Each chunk processes independently | Initial prompt carries forward from previous chunk |
| Hallucination | Silent segments may generate spurious text | VAD filtering removes silence before transcription |

> ❌ **Error**: If you see repeated phrases or "hallucinated" text in the output (text that was not spoken), this is typically caused by silent audio being sent to Whisper. Ensure VAD is enabled and the noise gate threshold is correctly calibrated. Whisper tends to hallucinate on silent or near-silent input.

---

## Related Documentation

- **[Architecture Overview](../architecture/ARCHITECTURE.md)** — System-level architecture including how the speech recognition engine fits into the overall pipeline.
- **[Model Management](MODEL_MANAGEMENT.md)** — Detailed guide on downloading, managing, and selecting both Whisper and llama.cpp models.
- **[API Documentation](../api/API_DOCUMENTATION.md)** — Public API reference for the speech recognition engine, audio pipeline, and processing modes.
