Last Updated: 2026-02-13

# Model Management

> **VaulType** — Privacy-first, macOS-native speech-to-text with local LLM post-processing.
> This document covers the complete model lifecycle: discovery, download, verification, storage, usage tracking, updates, and cleanup for both Whisper (STT) and LLM (text processing) models.

---

## Table of Contents

- [1. Model Types and Formats](#1-model-types-and-formats)
  - [1.1 Whisper GGML Models (Speech-to-Text)](#11-whisper-ggml-models-speech-to-text)
  - [1.2 LLM GGUF Models (Text Processing)](#12-llm-gguf-models-text-processing)
  - [1.3 Format Differences and Compatibility](#13-format-differences-and-compatibility)
- [2. Model Storage Location and Organization](#2-model-storage-location-and-organization)
  - [2.1 Directory Structure](#21-directory-structure)
  - [2.2 Naming Conventions](#22-naming-conventions)
  - [2.3 Storage Path Resolution](#23-storage-path-resolution)
- [3. Model Lifecycle](#3-model-lifecycle)
- [4. ModelManager Implementation](#4-modelmanager-implementation)
  - [4.1 Core ModelManager Class](#41-core-modelmanager-class)
  - [4.2 Model Enumeration and Querying](#42-model-enumeration-and-querying)
  - [4.3 Model Deletion](#43-model-deletion)
- [5. Download Manager](#5-download-manager)
  - [5.1 URLSession Download with Progress and Resume](#51-urlsession-download-with-progress-and-resume)
  - [5.2 Download Queue and Concurrency](#52-download-queue-and-concurrency)
  - [5.3 Resume Data Persistence](#53-resume-data-persistence)
- [6. Hugging Face Hub Integration](#6-hugging-face-hub-integration)
  - [6.1 API for Model Discovery](#61-api-for-model-discovery)
  - [6.2 GGUF Model Repositories](#62-gguf-model-repositories)
  - [6.3 URL Construction and Metadata Parsing](#63-url-construction-and-metadata-parsing)
  - [6.4 Recommended Repositories](#64-recommended-repositories)
- [7. Model Verification](#7-model-verification)
  - [7.1 SHA256 Checksum Validation](#71-sha256-checksum-validation)
  - [7.2 File Integrity Checks](#72-file-integrity-checks)
  - [7.3 Corrupted Model Detection and Re-download](#73-corrupted-model-detection-and-re-download)
- [8. Model Size and Performance Comparison](#8-model-size-and-performance-comparison)
  - [8.1 Whisper Model Comparison](#81-whisper-model-comparison)
  - [8.2 LLM Model Comparison](#82-llm-model-comparison)
  - [8.3 Hardware Recommendations](#83-hardware-recommendations)
- [9. Disk Space Management and Cleanup](#9-disk-space-management-and-cleanup)
  - [9.1 Calculating Total Model Storage](#91-calculating-total-model-storage)
  - [9.2 Storage Warnings and Estimation](#92-storage-warnings-and-estimation)
  - [9.3 Cleanup Implementation](#93-cleanup-implementation)
- [10. Model Update Notifications](#10-model-update-notifications)
  - [10.1 Checking for Newer Versions](#101-checking-for-newer-versions)
  - [10.2 Update and Migration Flow](#102-update-and-migration-flow)
- [11. Bundled vs Downloadable Models Strategy](#11-bundled-vs-downloadable-models-strategy)
  - [11.1 Bundled Model Selection](#111-bundled-model-selection)
  - [11.2 First-Run Experience](#112-first-run-experience)
  - [11.3 Recommended Model Sets](#113-recommended-model-sets)
- [12. SwiftData ModelInfo Persistence](#12-swiftdata-modelinfo-persistence)
  - [12.1 ModelInfo Schema Recap](#121-modelinfo-schema-recap)
  - [12.2 Pre-Seeded Registry](#122-pre-seeded-registry)
  - [12.3 Persistence Operations](#123-persistence-operations)
- [13. Settings UI for Model Management](#13-settings-ui-for-model-management)
  - [13.1 Model Management View](#131-model-management-view)
  - [13.2 Download Progress View](#132-download-progress-view)
  - [13.3 Model Detail View](#133-model-detail-view)
- [Related Documentation](#related-documentation)

---

## 1. Model Types and Formats

VaulType uses two distinct families of ML models, each served by a dedicated inference engine. Understanding the format differences is essential for model management, storage, and compatibility.

### 1.1 Whisper GGML Models (Speech-to-Text)

Whisper models convert spoken audio into text. VaulType uses the [whisper.cpp](https://github.com/ggerganov/whisper.cpp) inference engine, which requires models in the **GGML binary format**.

| Property | Details |
|---|---|
| **Format** | GGML (Georgi Gerganov Machine Learning) |
| **File extension** | `.bin` |
| **Quantization** | Pre-quantized — models are distributed at fixed precision (mostly FP16) |
| **Source** | Converted from OpenAI Whisper PyTorch checkpoints |
| **Primary repo** | `ggerganov/whisper.cpp` on Hugging Face |
| **Naming pattern** | `ggml-{size}.bin` or `ggml-{size}.en.bin` (English-only) |

**Whisper model variants:**

- **English-only models** (`*.en.bin`) — Optimized specifically for English speech. Smaller vocabulary, faster inference, slightly higher accuracy for English.
- **Multilingual models** (`*.bin`, without `.en`) — Support 99+ languages with automatic language detection. Slightly larger due to expanded vocabulary.
- **Turbo variants** (`*-turbo.bin`) — Distilled versions that trade minimal accuracy for significantly faster inference. Ideal for real-time dictation.

> ℹ️ **Info**: English-only models are recommended for most VaulType users. They are smaller, faster, and more accurate for English transcription. Multilingual models are only necessary if you regularly dictate in non-English languages. See [SPEECH_RECOGNITION.md](SPEECH_RECOGNITION.md) for language-specific configuration.

### 1.2 LLM GGUF Models (Text Processing)

LLM models handle post-transcription text processing — grammar correction, formatting, summarization, and style transformation. VaulType uses [llama.cpp](https://github.com/ggerganov/llama.cpp) as the inference engine, which requires models in the **GGUF format**.

| Property | Details |
|---|---|
| **Format** | GGUF (GPT-Generated Unified Format) |
| **File extension** | `.gguf` |
| **Quantization** | User-selectable — models available at multiple quantization levels (Q2_K through Q8_0, FP16) |
| **Source** | Converted from various open-weight LLMs (Llama, Qwen, Phi, Gemma, etc.) |
| **Primary repos** | Model-specific repos on Hugging Face (see [Section 6.4](#64-recommended-repositories)) |
| **Naming pattern** | `{model-name}.{quantization}.gguf` |

**Common GGUF quantization levels:**

| Quantization | Bits | Quality | Speed | RAM Multiplier | Use Case |
|---|---|---|---|---|---|
| `Q2_K` | 2-bit | Low | Fastest | 0.25x | Extremely constrained RAM |
| `Q3_K_M` | 3-bit | Fair | Very fast | 0.33x | Low-RAM machines |
| `Q4_K_M` | 4-bit | Good | Fast | 0.50x | **Recommended default** |
| `Q5_K_M` | 5-bit | Very good | Moderate | 0.60x | Quality-focused users |
| `Q6_K` | 6-bit | Excellent | Slower | 0.75x | Near-FP16 quality |
| `Q8_0` | 8-bit | Near-perfect | Slow | 1.0x | Maximum quality |
| `F16` | 16-bit | Reference | Slowest | 2.0x | Benchmarking only |

> 💡 **Tip**: For VaulType's text post-processing tasks (grammar correction, formatting), `Q4_K_M` quantization provides the best balance of quality and performance. Text cleanup tasks are less sensitive to quantization than creative writing or complex reasoning.

### 1.3 Format Differences and Compatibility

| Feature | GGML (Whisper) | GGUF (LLM) |
|---|---|---|
| **Header format** | Legacy binary header | Self-describing metadata header |
| **Metadata** | Minimal (model params only) | Rich (tokenizer, architecture, quant info) |
| **Tokenizer** | Embedded in binary | Embedded in GGUF metadata |
| **Versioning** | No formal versioning | GGUF version field (currently v3) |
| **Extensibility** | Fixed structure | Key-value metadata, arbitrary extensions |
| **Inference engine** | whisper.cpp only | llama.cpp, ollama, LM Studio, etc. |
| **Memory mapping** | Supported | Supported |
| **File sizes** | 75 MB - 3.1 GB | 1 GB - 8+ GB (for VaulType's target models) |

> ⚠️ **Warning**: GGML and GGUF are **not interchangeable**. A GGUF file cannot be loaded by whisper.cpp, and a GGML file cannot be loaded by llama.cpp. VaulType enforces this separation through the `ModelType` enum and separate storage directories.

---

## 2. Model Storage Location and Organization

### 2.1 Directory Structure

All model files are stored under the macOS Application Support directory, organized by model type:

```
~/Library/Application Support/VaulType/
├── Models/
│   ├── whisper-models/              # Whisper GGML models for STT
│   │   ├── ggml-tiny.en.bin         # 74 MB  — Bundled with app
│   │   ├── ggml-base.en.bin         # 141 MB — Default recommended
│   │   ├── ggml-small.en.bin        # 465 MB
│   │   ├── ggml-medium.en.bin       # 1.5 GB
│   │   └── ggml-large-v3-turbo.bin  # 1.5 GB
│   │
│   ├── llm-models/                  # LLM GGUF models for text processing
│   │   ├── qwen2.5-3b-instruct.Q4_K_M.gguf     # 1.9 GB
│   │   ├── phi-3.5-mini-instruct.Q4_K_M.gguf    # 2.2 GB
│   │   └── llama-3.2-3b-instruct.Q4_K_M.gguf    # 1.8 GB
│   │
│   └── .downloads/                  # Temporary directory for in-progress downloads
│       ├── ggml-small.en.bin.part   # Partial download file
│       └── ggml-small.en.bin.resume # URLSession resume data
│
├── VaulType.store                   # SwiftData database
└── VaulType.store-shm               # SQLite shared memory
```

> 🔒 **Security**: Model files are stored in the user's Application Support directory, which is protected by macOS sandbox (if enabled) and FileVault encryption. No model data is ever transmitted off-device after the initial download.

### 2.2 Naming Conventions

| Model Type | Pattern | Example |
|---|---|---|
| Whisper (English-only) | `ggml-{size}.en.bin` | `ggml-base.en.bin` |
| Whisper (Multilingual) | `ggml-{size}.bin` | `ggml-large-v3-turbo.bin` |
| LLM (GGUF) | `{model-name}.{quantization}.gguf` | `qwen2.5-3b-instruct.Q4_K_M.gguf` |
| Partial download | `{filename}.part` | `ggml-medium.en.bin.part` |
| Resume data | `{filename}.resume` | `ggml-medium.en.bin.resume` |

> ℹ️ **Info**: File names must match the `fileName` field in the `ModelInfo` SwiftData record exactly. The `ModelManager` resolves full paths using the `ModelType.storageDirectory` property. See [DATABASE_SCHEMA.md: ModelInfo](../architecture/DATABASE_SCHEMA.md#modelinfo) for the schema definition.

### 2.3 Storage Path Resolution

VaulType constructs model file paths programmatically based on the `ModelType` and filename:

```swift
import Foundation

enum ModelStoragePaths {
    /// Root directory for all VaulType data.
    static var applicationSupport: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        .appendingPathComponent("VaulType", isDirectory: true)
    }

    /// Root directory for all model files.
    static var modelsRoot: URL {
        applicationSupport.appendingPathComponent("Models", isDirectory: true)
    }

    /// Directory for Whisper GGML model files.
    static var whisperModels: URL {
        modelsRoot.appendingPathComponent("whisper-models", isDirectory: true)
    }

    /// Directory for LLM GGUF model files.
    static var llmModels: URL {
        modelsRoot.appendingPathComponent("llm-models", isDirectory: true)
    }

    /// Temporary directory for in-progress downloads.
    static var downloads: URL {
        modelsRoot.appendingPathComponent(".downloads", isDirectory: true)
    }

    /// Resolves the full file path for a given model.
    static func path(for model: ModelInfo) -> URL {
        let directory: URL = switch model.type {
        case .whisper: whisperModels
        case .llm: llmModels
        }
        return directory.appendingPathComponent(model.fileName)
    }

    /// Creates all required directories if they don't exist.
    static func ensureDirectoriesExist() throws {
        let fm = FileManager.default
        for dir in [whisperModels, llmModels, downloads] {
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }
}
```

---

## 3. Model Lifecycle

The following diagram shows the complete lifecycle of a model from discovery through deletion:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Model Lifecycle                                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌──────────┐    ┌───────────┐    ┌───────────┐    ┌──────────────┐    │
│  │          │    │           │    │           │    │              │    │
│  │ DISCOVER │───▶│ REGISTRY  │───▶│ DOWNLOAD  │───▶│   VERIFY     │    │
│  │          │    │           │    │           │    │              │    │
│  │ HF Hub   │    │ SwiftData │    │ URLSession│    │ SHA256       │    │
│  │ Browse   │    │ ModelInfo │    │ Progress  │    │ Checksum     │    │
│  │ Search   │    │ record    │    │ Resume    │    │ File size    │    │
│  │          │    │ created   │    │ support   │    │ Header check │    │
│  └──────────┘    └───────────┘    └─────┬─────┘    └──────┬───────┘    │
│                                         │                  │           │
│                                         │  ❌ Failed       │           │
│                                         │  (retry/resume)  │           │
│                                         ◀──────────────────┤           │
│                                                            │           │
│                                                     ✅ Valid           │
│                                                            │           │
│                                                            ▼           │
│  ┌──────────┐    ┌───────────┐    ┌───────────┐    ┌──────────────┐    │
│  │          │    │           │    │           │    │              │    │
│  │  DELETE  │◀───│  CLEANUP  │◀ ─ │  UPDATE   │◀───│    READY     │    │
│  │          │    │           │  ┌─│  CHECK    │    │              │    │
│  │ Remove   │    │ Unused    │  │ │           │    │ isDownloaded │    │
│  │ file     │    │ model     │  │ │ Newer ver │    │ = true       │    │
│  │ Remove   │    │ detection │  │ │ available │    │ Inference OK │    │
│  │ record   │    │ Disk warn │  │ │ Notify    │    │ lastUsed set │    │
│  │          │    │           │  │ │ user      │    │              │    │
│  └──────────┘    └───────────┘  │ └───────────┘    └──────────────┘    │
│                                 │        │                  ▲          │
│                                 │        │ New version      │          │
│                                 │        │ downloaded       │          │
│                                 │        └──────────────────┘          │
│                                 │                                      │
│                                 └ ─ ─ (optional, user-initiated)       │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

**State transitions:**

| From | To | Trigger |
|---|---|---|
| Discover | Registry | User selects model from HF Hub or model is in default registry |
| Registry | Download | User taps "Download" or first-run auto-download |
| Download | Verify | Download completes |
| Download | Download | Resume after interruption |
| Verify | Ready | Checksum matches, file size correct |
| Verify | Download | Verification fails — re-download |
| Ready | Update Check | Periodic check or user-initiated |
| Update Check | Ready | No update available |
| Update Check | Download | User accepts update (new version) |
| Ready | Cleanup | Unused model detected, user confirms |
| Cleanup | Delete | User confirms deletion |
| Delete | (removed) | File and SwiftData record removed |

---

## 4. ModelManager Implementation

The `ModelManager` is the central actor responsible for all model operations. It coordinates downloads, verification, storage, and SwiftData persistence.

### 4.1 Core ModelManager Class

```swift
import Foundation
import SwiftData
import CryptoKit
import os.log

/// Central manager for all ML model operations including download,
/// verification, deletion, and discovery.
@MainActor
final class ModelManager: ObservableObject {
    // MARK: - Published State

    /// All known models (downloaded and available for download).
    @Published private(set) var models: [ModelInfo] = []

    /// Models currently being downloaded, keyed by model ID.
    @Published private(set) var activeDownloads: [UUID: DownloadState] = [:]

    /// Total disk space used by all downloaded models.
    @Published private(set) var totalStorageUsed: Int64 = 0

    // MARK: - Dependencies

    private let modelContext: ModelContext
    private let downloadManager: ModelDownloadManager
    private let verifier: ModelVerifier
    private let huggingFaceClient: HuggingFaceClient

    private let logger = Logger(
        subsystem: "com.vaultype.app",
        category: "ModelManager"
    )

    // MARK: - Initialization

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.downloadManager = ModelDownloadManager()
        self.verifier = ModelVerifier()
        self.huggingFaceClient = HuggingFaceClient()
    }

    // MARK: - Lifecycle

    /// Called on app launch to synchronize database state with filesystem.
    func initialize() async throws {
        try ModelStoragePaths.ensureDirectoriesExist()
        try await syncDatabaseWithFilesystem()
        try await seedDefaultModelsIfNeeded()
        await refreshModels()
        await calculateStorageUsed()
    }

    // MARK: - Model Listing

    /// Refreshes the in-memory model list from SwiftData.
    func refreshModels() async {
        let descriptor = FetchDescriptor<ModelInfo>(
            sortBy: [
                SortDescriptor(\.type.rawValue),
                SortDescriptor(\.name)
            ]
        )

        do {
            models = try modelContext.fetch(descriptor)
        } catch {
            logger.error("Failed to fetch models: \(error.localizedDescription)")
        }
    }

    /// Returns all models of a specific type.
    func models(ofType type: ModelType) -> [ModelInfo] {
        models.filter { $0.type == type }
    }

    /// Returns only downloaded and ready models.
    func downloadedModels(ofType type: ModelType) -> [ModelInfo] {
        models.filter { $0.type == type && $0.isDownloaded }
    }

    /// Returns the currently selected model for a given type.
    func activeModel(ofType type: ModelType) -> ModelInfo? {
        models.first { $0.type == type && $0.isDefault && $0.isDownloaded }
    }

    // MARK: - Database Synchronization

    /// Ensures the database accurately reflects which model files
    /// actually exist on disk. Handles cases where files were manually
    /// deleted or the app crashed during a download.
    private func syncDatabaseWithFilesystem() async throws {
        let descriptor = FetchDescriptor<ModelInfo>()
        let allModels = try modelContext.fetch(descriptor)

        for model in allModels {
            let fileExists = FileManager.default.fileExists(
                atPath: ModelStoragePaths.path(for: model).path
            )

            if model.isDownloaded && !fileExists {
                logger.warning(
                    "Model '\(model.name)' marked as downloaded but file missing. Resetting state."
                )
                model.isDownloaded = false
                model.downloadProgress = nil
            } else if !model.isDownloaded && fileExists {
                logger.info(
                    "Model '\(model.name)' file found on disk. Marking as downloaded."
                )
                model.isDownloaded = true
                model.downloadProgress = nil
            }
        }

        try modelContext.save()
    }

    /// Seeds the default model registry on first launch.
    private func seedDefaultModelsIfNeeded() async throws {
        let descriptor = FetchDescriptor<ModelInfo>()
        let existingCount = try modelContext.fetchCount(descriptor)

        guard existingCount == 0 else { return }

        logger.info("First launch detected. Seeding default model registry.")

        for model in ModelInfo.defaultModels {
            modelContext.insert(model)
        }

        try modelContext.save()
    }
}
```

### 4.2 Model Enumeration and Querying

```swift
extension ModelManager {
    /// Represents the download/readiness state of a model for UI display.
    enum ModelStatus {
        case notDownloaded
        case downloading(progress: Double)
        case verifying
        case ready
        case error(String)
    }

    /// Returns the current status for a given model.
    func status(for model: ModelInfo) -> ModelStatus {
        if let downloadState = activeDownloads[model.id] {
            switch downloadState {
            case .downloading(let progress):
                return .downloading(progress: progress)
            case .verifying:
                return .verifying
            case .failed(let message):
                return .error(message)
            }
        }

        if model.isDownloaded && model.fileExistsOnDisk {
            return .ready
        }

        return .notDownloaded
    }

    /// Searches models by name, type, or filename.
    func searchModels(query: String) -> [ModelInfo] {
        guard !query.isEmpty else { return models }
        let lowercased = query.lowercased()
        return models.filter { model in
            model.name.lowercased().contains(lowercased) ||
            model.fileName.lowercased().contains(lowercased)
        }
    }

    /// Returns models sorted by last usage date (most recent first).
    func recentlyUsedModels(limit: Int = 5) -> [ModelInfo] {
        models
            .filter { $0.lastUsed != nil }
            .sorted { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }
            .prefix(limit)
            .map { $0 }
    }

    /// Updates the `lastUsed` timestamp when a model is used for inference.
    func markModelAsUsed(_ model: ModelInfo) throws {
        model.lastUsed = Date()
        try modelContext.save()
    }
}
```

### 4.3 Model Deletion

```swift
extension ModelManager {
    /// Deletes a model file from disk and optionally removes its registry entry.
    /// - Parameters:
    ///   - model: The model to delete.
    ///   - removeFromRegistry: If true, removes the SwiftData record entirely.
    ///     If false, keeps the record but marks it as not downloaded (allowing re-download).
    func deleteModel(
        _ model: ModelInfo,
        removeFromRegistry: Bool = false
    ) async throws {
        let filePath = ModelStoragePaths.path(for: model)

        // Cancel any active download for this model
        if activeDownloads[model.id] != nil {
            await downloadManager.cancelDownload(for: model.id)
            activeDownloads.removeValue(forKey: model.id)
        }

        // Delete the file from disk
        let fm = FileManager.default
        if fm.fileExists(atPath: filePath.path) {
            try fm.removeItem(at: filePath)
            logger.info("Deleted model file: \(filePath.lastPathComponent)")
        }

        // Clean up any partial downloads
        let partialPath = ModelStoragePaths.downloads
            .appendingPathComponent("\(model.fileName).part")
        let resumePath = ModelStoragePaths.downloads
            .appendingPathComponent("\(model.fileName).resume")

        try? fm.removeItem(at: partialPath)
        try? fm.removeItem(at: resumePath)

        if removeFromRegistry {
            modelContext.delete(model)
            logger.info("Removed model '\(model.name)' from registry.")
        } else {
            model.isDownloaded = false
            model.downloadProgress = nil
            logger.info("Model '\(model.name)' marked as not downloaded.")
        }

        try modelContext.save()
        await refreshModels()
        await calculateStorageUsed()
    }

    /// Deletes all models of a specific type.
    func deleteAllModels(ofType type: ModelType) async throws {
        let modelsToDelete = models.filter { $0.type == type && $0.isDownloaded }
        for model in modelsToDelete {
            try await deleteModel(model)
        }
    }
}
```

---

## 5. Download Manager

### 5.1 URLSession Download with Progress and Resume

The download manager uses `URLSession` with delegate-based progress reporting and resume capability. Downloads write to a temporary `.part` file and are atomically moved to the final location upon completion.

```swift
import Foundation
import os.log

/// Tracks the state of an in-progress download.
enum DownloadState: Equatable {
    case downloading(progress: Double)
    case verifying
    case failed(message: String)
}

/// Manages model file downloads with progress tracking and resume support.
actor ModelDownloadManager: NSObject {
    // MARK: - Types

    struct DownloadTask {
        let modelId: UUID
        let fileName: String
        let expectedSize: Int64
        let task: URLSessionDownloadTask
        var resumeData: Data?
    }

    // MARK: - State

    private var activeTasks: [UUID: DownloadTask] = [:]
    private var progressContinuations: [UUID: AsyncStream<DownloadState>.Continuation] = []
    private let maxConcurrentDownloads = 2

    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.allowsCellularAccess = true
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 3600 // 1 hour max per download
        config.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private let logger = Logger(
        subsystem: "com.vaultype.app",
        category: "ModelDownloadManager"
    )

    // MARK: - Download Operations

    /// Starts or resumes downloading a model file.
    /// Returns an async stream of download state updates.
    func download(
        modelId: UUID,
        from url: URL,
        fileName: String,
        expectedSize: Int64
    ) -> AsyncStream<DownloadState> {
        AsyncStream { continuation in
            Task {
                // Check for existing resume data
                let resumeDataURL = ModelStoragePaths.downloads
                    .appendingPathComponent("\(fileName).resume")
                let resumeData = try? Data(contentsOf: resumeDataURL)

                let task: URLSessionDownloadTask
                if let resumeData {
                    task = urlSession.downloadTask(withResumeData: resumeData)
                    logger.info("Resuming download for \(fileName)")
                } else {
                    var request = URLRequest(url: url)
                    request.setValue(
                        "VaulType/1.0 (macOS; privacy-first STT)",
                        forHTTPHeaderField: "User-Agent"
                    )
                    task = urlSession.downloadTask(with: request)
                    logger.info("Starting fresh download for \(fileName)")
                }

                let downloadTask = DownloadTask(
                    modelId: modelId,
                    fileName: fileName,
                    expectedSize: expectedSize,
                    task: task,
                    resumeData: resumeData
                )

                activeTasks[modelId] = downloadTask
                progressContinuations[modelId] = continuation

                continuation.onTermination = { @Sendable _ in
                    Task { await self.cancelDownload(for: modelId) }
                }

                task.resume()
            }
        }
    }

    /// Cancels an active download, preserving resume data.
    func cancelDownload(for modelId: UUID) {
        guard let downloadTask = activeTasks[modelId] else { return }

        downloadTask.task.cancel { [weak self] resumeData in
            guard let self else { return }
            Task {
                if let resumeData {
                    await self.saveResumeData(
                        resumeData,
                        fileName: downloadTask.fileName
                    )
                }
            }
        }

        progressContinuations[modelId]?.finish()
        progressContinuations.removeValue(forKey: modelId)
        activeTasks.removeValue(forKey: modelId)

        logger.info("Cancelled download for model \(modelId)")
    }

    /// Saves resume data to disk so downloads can survive app restarts.
    private func saveResumeData(_ data: Data, fileName: String) {
        let resumeURL = ModelStoragePaths.downloads
            .appendingPathComponent("\(fileName).resume")
        do {
            try data.write(to: resumeURL, options: .atomic)
            logger.debug("Saved resume data for \(fileName)")
        } catch {
            logger.error("Failed to save resume data: \(error.localizedDescription)")
        }
    }

    /// Returns the number of currently active downloads.
    var activeDownloadCount: Int {
        activeTasks.count
    }
}
```

### 5.2 Download Queue and Concurrency

```swift
// MARK: - URLSessionDownloadDelegate

extension ModelDownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        Task { await handleDownloadCompletion(downloadTask: downloadTask, location: location) }
    }

    private func handleDownloadCompletion(
        downloadTask: URLSessionDownloadTask,
        location: URL
    ) {
        guard let (modelId, modelTask) = activeTasks.first(
            where: { $0.value.task == downloadTask }
        ) else {
            logger.warning("Received completion for unknown download task")
            return
        }

        // Move the downloaded file to the final location
        let destinationDir: URL = if modelTask.fileName.hasSuffix(".bin") {
            ModelStoragePaths.whisperModels
        } else {
            ModelStoragePaths.llmModels
        }

        let destination = destinationDir.appendingPathComponent(modelTask.fileName)

        do {
            let fm = FileManager.default
            // Remove existing file if present (e.g., from a previous corrupt download)
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }

            try fm.moveItem(at: location, to: destination)

            logger.info("Download complete: \(modelTask.fileName)")
            progressContinuations[modelId]?.yield(.verifying)
        } catch {
            logger.error("Failed to move downloaded file: \(error.localizedDescription)")
            progressContinuations[modelId]?.yield(
                .failed(message: "Failed to save file: \(error.localizedDescription)")
            )
        }

        // Clean up resume data file
        let resumeURL = ModelStoragePaths.downloads
            .appendingPathComponent("\(modelTask.fileName).resume")
        try? FileManager.default.removeItem(at: resumeURL)

        progressContinuations[modelId]?.finish()
        progressContinuations.removeValue(forKey: modelId)
        activeTasks.removeValue(forKey: modelId)
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        Task {
            await handleProgress(
                downloadTask: downloadTask,
                totalBytesWritten: totalBytesWritten,
                totalBytesExpectedToWrite: totalBytesExpectedToWrite
            )
        }
    }

    private func handleProgress(
        downloadTask: URLSessionDownloadTask,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let (modelId, _) = activeTasks.first(
            where: { $0.value.task == downloadTask }
        ) else { return }

        let progress: Double
        if totalBytesExpectedToWrite > 0 {
            progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        } else if let expectedSize = activeTasks[modelId]?.expectedSize, expectedSize > 0 {
            progress = Double(totalBytesWritten) / Double(expectedSize)
        } else {
            progress = 0.0
        }

        progressContinuations[modelId]?.yield(.downloading(progress: progress))
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        guard let error else { return }

        Task {
            await handleError(task: task, error: error)
        }
    }

    private func handleError(task: URLSessionTask, error: any Error) {
        guard let (modelId, modelTask) = activeTasks.first(
            where: { $0.value.task == task }
        ) else { return }

        // Extract and save resume data if available
        let nsError = error as NSError
        if let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            saveResumeData(resumeData, fileName: modelTask.fileName)
            logger.info("Download interrupted with resume data saved: \(modelTask.fileName)")
        }

        if nsError.code == NSURLErrorCancelled {
            // Cancellation is expected — don't report as error
            logger.debug("Download cancelled: \(modelTask.fileName)")
        } else {
            logger.error("Download failed: \(error.localizedDescription)")
            progressContinuations[modelId]?.yield(
                .failed(message: error.localizedDescription)
            )
        }

        progressContinuations[modelId]?.finish()
        progressContinuations.removeValue(forKey: modelId)
        activeTasks.removeValue(forKey: modelId)
    }
}
```

### 5.3 Resume Data Persistence

Resume data allows downloads to continue after app termination, network interruptions, or system sleep. The implementation stores `URLSession` resume data as a separate file alongside partial downloads.

```swift
extension ModelDownloadManager {
    /// Checks whether a download can be resumed for a given model.
    func canResumeDownload(fileName: String) -> Bool {
        let resumeURL = ModelStoragePaths.downloads
            .appendingPathComponent("\(fileName).resume")
        return FileManager.default.fileExists(atPath: resumeURL.path)
    }

    /// Removes all resume data and partial downloads (e.g., on user request).
    func clearAllResumeData() throws {
        let fm = FileManager.default
        let downloadDir = ModelStoragePaths.downloads

        guard fm.fileExists(atPath: downloadDir.path) else { return }

        let contents = try fm.contentsOfDirectory(
            at: downloadDir,
            includingPropertiesForKeys: nil
        )

        for file in contents {
            try fm.removeItem(at: file)
        }
    }

    /// Returns the size of resume data on disk (for storage calculations).
    func resumeDataSize() throws -> Int64 {
        let fm = FileManager.default
        let downloadDir = ModelStoragePaths.downloads

        guard fm.fileExists(atPath: downloadDir.path) else { return 0 }

        let contents = try fm.contentsOfDirectory(
            at: downloadDir,
            includingPropertiesForKeys: [.fileSizeKey]
        )

        return try contents.reduce(into: Int64(0)) { total, url in
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(values.fileSize ?? 0)
        }
    }
}
```

> ℹ️ **Info**: `URLSession` resume data contains internal HTTP range headers and server tokens. Not all servers support resumption — Hugging Face Hub does support HTTP Range requests, so resume works reliably for all VaulType model downloads.

---

## 6. Hugging Face Hub Integration

VaulType downloads models from Hugging Face Hub, the largest open-source model hosting platform. This section covers model discovery, URL construction, and metadata parsing.

### 6.1 API for Model Discovery

```swift
import Foundation
import os.log

/// Client for discovering and fetching model metadata from Hugging Face Hub.
actor HuggingFaceClient {
    // MARK: - Types

    /// Metadata for a model file on Hugging Face.
    struct HFModelFile: Codable, Sendable {
        let rfilename: String       // Relative filename within the repo
        let size: Int64?            // File size in bytes
        let lfs: LFSInfo?          // Large file storage metadata

        struct LFSInfo: Codable, Sendable {
            let sha256: String      // SHA256 checksum of the file
            let size: Int64         // File size
        }
    }

    /// A model repository on Hugging Face.
    struct HFRepository: Codable, Sendable {
        let id: String              // e.g., "ggerganov/whisper.cpp"
        let modelId: String         // Same as id
        let lastModified: String?   // ISO 8601 date
        let tags: [String]?         // e.g., ["gguf", "whisper", "speech"]
    }

    // MARK: - Properties

    private let baseURL = URL(string: "https://huggingface.co")!
    private let apiBaseURL = URL(string: "https://huggingface.co/api")!
    private let urlSession: URLSession

    private let logger = Logger(
        subsystem: "com.vaultype.app",
        category: "HuggingFaceClient"
    )

    // MARK: - Initialization

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.httpAdditionalHeaders = [
            "User-Agent": "VaulType/1.0 (macOS; privacy-first STT)"
        ]
        self.urlSession = URLSession(configuration: config)
    }

    // MARK: - Repository Listing

    /// Lists files in a Hugging Face repository.
    /// - Parameters:
    ///   - repoId: Repository identifier (e.g., "ggerganov/whisper.cpp").
    ///   - revision: Branch or tag (default: "main").
    /// - Returns: Array of file metadata.
    func listFiles(
        inRepo repoId: String,
        revision: String = "main"
    ) async throws -> [HFModelFile] {
        let url = apiBaseURL
            .appendingPathComponent("models")
            .appendingPathComponent(repoId)
            .appendingPathComponent("tree")
            .appendingPathComponent(revision)

        let (data, response) = try await urlSession.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw HuggingFaceError.apiRequestFailed(
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0
            )
        }

        let decoder = JSONDecoder()
        return try decoder.decode([HFModelFile].self, from: data)
    }

    /// Searches for GGUF model repositories on Hugging Face.
    /// - Parameters:
    ///   - query: Search query (e.g., "qwen2.5 3b gguf").
    ///   - limit: Maximum results to return.
    /// - Returns: Array of matching repositories.
    func searchModels(
        query: String,
        limit: Int = 10
    ) async throws -> [HFRepository] {
        var components = URLComponents(
            url: apiBaseURL.appendingPathComponent("models"),
            resolvingAgainstBaseURL: false
        )!

        components.queryItems = [
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "filter", value: "gguf"),
            URLQueryItem(name: "sort", value: "downloads"),
            URLQueryItem(name: "direction", value: "-1"),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        guard let url = components.url else {
            throw HuggingFaceError.invalidURL
        }

        let (data, response) = try await urlSession.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw HuggingFaceError.apiRequestFailed(
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0
            )
        }

        let decoder = JSONDecoder()
        return try decoder.decode([HFRepository].self, from: data)
    }
}

// MARK: - Errors

enum HuggingFaceError: LocalizedError {
    case apiRequestFailed(statusCode: Int)
    case invalidURL
    case fileNotFound(fileName: String)
    case checksumMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .apiRequestFailed(let statusCode):
            "Hugging Face API request failed (HTTP \(statusCode))"
        case .invalidURL:
            "Failed to construct Hugging Face URL"
        case .fileNotFound(let fileName):
            "File '\(fileName)' not found in repository"
        case .checksumMismatch(let expected, let actual):
            "Checksum mismatch — expected \(expected.prefix(12))..., got \(actual.prefix(12))..."
        }
    }
}
```

### 6.2 GGUF Model Repositories

Hugging Face hosts model files using Git LFS (Large File Storage). GGUF-quantized models are typically found in dedicated repositories maintained by the original model authors or community quantizers.

**Repository structure for a typical GGUF model:**

```
bartowski/Qwen2.5-3B-Instruct-GGUF/
├── README.md
├── config.json
├── Qwen2.5-3B-Instruct-Q2_K.gguf
├── Qwen2.5-3B-Instruct-Q3_K_M.gguf
├── Qwen2.5-3B-Instruct-Q4_K_M.gguf      ← VaulType default
├── Qwen2.5-3B-Instruct-Q5_K_M.gguf
├── Qwen2.5-3B-Instruct-Q6_K.gguf
├── Qwen2.5-3B-Instruct-Q8_0.gguf
└── Qwen2.5-3B-Instruct-f16.gguf
```

> 🔒 **Security**: VaulType only downloads from `huggingface.co` URLs. It validates the hostname before initiating any download. The download manager rejects redirects to other domains to prevent model supply-chain attacks. See [SECURITY.md](../security/SECURITY.md) for the full threat model.

### 6.3 URL Construction and Metadata Parsing

```swift
extension HuggingFaceClient {
    /// Constructs a direct download URL for a file in a Hugging Face repository.
    /// Format: https://huggingface.co/{repo}/resolve/{revision}/{filename}
    static func downloadURL(
        repo: String,
        fileName: String,
        revision: String = "main"
    ) -> URL? {
        URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(fileName)")
    }

    /// Fetches the SHA256 checksum for a specific file from the repository API.
    func fileChecksum(
        repo: String,
        fileName: String,
        revision: String = "main"
    ) async throws -> String? {
        let files = try await listFiles(inRepo: repo, revision: revision)

        guard let file = files.first(where: { $0.rfilename == fileName }) else {
            throw HuggingFaceError.fileNotFound(fileName: fileName)
        }

        return file.lfs?.sha256
    }

    /// Returns the file size for a model file in a repository.
    func fileSize(
        repo: String,
        fileName: String,
        revision: String = "main"
    ) async throws -> Int64? {
        let files = try await listFiles(inRepo: repo, revision: revision)
        let file = files.first { $0.rfilename == fileName }
        return file?.lfs?.size ?? file?.size
    }

    /// Discovers available GGUF quantization variants for a model.
    func availableQuantizations(
        repo: String,
        revision: String = "main"
    ) async throws -> [HFModelFile] {
        let files = try await listFiles(inRepo: repo, revision: revision)
        return files.filter { $0.rfilename.hasSuffix(".gguf") }
    }
}
```

### 6.4 Recommended Repositories

VaulType maintains a curated list of recommended model repositories:

**Whisper Models:**

| Repository | Description |
|---|---|
| `ggerganov/whisper.cpp` | Official whisper.cpp GGML models, maintained by Georgi Gerganov |

**LLM Models (Recommended for text processing):**

| Repository | Model | Best For |
|---|---|---|
| `bartowski/Qwen2.5-3B-Instruct-GGUF` | Qwen 2.5 3B Instruct | General text cleanup, multilingual support |
| `bartowski/Phi-3.5-mini-instruct-GGUF` | Phi 3.5 Mini 3.8B | Instruction following, English-focused |
| `bartowski/Llama-3.2-3B-Instruct-GGUF` | Llama 3.2 3B Instruct | Fast inference, broad capabilities |
| `bartowski/gemma-2-2b-it-GGUF` | Gemma 2 2B IT | Smallest viable model, low RAM |

```swift
/// Curated list of recommended model sources for VaulType.
enum RecommendedModels {
    struct RecommendedRepo {
        let repoId: String
        let modelName: String
        let description: String
        let recommendedFile: String
        let modelType: ModelType
    }

    static let whisperRepos: [RecommendedRepo] = [
        RecommendedRepo(
            repoId: "ggerganov/whisper.cpp",
            modelName: "Whisper Tiny (English)",
            description: "Fastest, lowest quality. Bundled with app.",
            recommendedFile: "ggml-tiny.en.bin",
            modelType: .whisper
        ),
        RecommendedRepo(
            repoId: "ggerganov/whisper.cpp",
            modelName: "Whisper Base (English)",
            description: "Good balance of speed and quality. Recommended default.",
            recommendedFile: "ggml-base.en.bin",
            modelType: .whisper
        ),
        RecommendedRepo(
            repoId: "ggerganov/whisper.cpp",
            modelName: "Whisper Small (English)",
            description: "Higher accuracy, moderate resource usage.",
            recommendedFile: "ggml-small.en.bin",
            modelType: .whisper
        ),
        RecommendedRepo(
            repoId: "ggerganov/whisper.cpp",
            modelName: "Whisper Medium (English)",
            description: "Near-best accuracy. Requires 2+ GB RAM.",
            recommendedFile: "ggml-medium.en.bin",
            modelType: .whisper
        ),
        RecommendedRepo(
            repoId: "ggerganov/whisper.cpp",
            modelName: "Whisper Large v3 Turbo",
            description: "Best accuracy with distilled speed. Multilingual.",
            recommendedFile: "ggml-large-v3-turbo.bin",
            modelType: .whisper
        ),
    ]

    static let llmRepos: [RecommendedRepo] = [
        RecommendedRepo(
            repoId: "bartowski/Qwen2.5-3B-Instruct-GGUF",
            modelName: "Qwen 2.5 3B Instruct",
            description: "Best overall for text processing tasks.",
            recommendedFile: "Qwen2.5-3B-Instruct-Q4_K_M.gguf",
            modelType: .llm
        ),
        RecommendedRepo(
            repoId: "bartowski/Phi-3.5-mini-instruct-GGUF",
            modelName: "Phi 3.5 Mini 3.8B",
            description: "Strong instruction following. English-focused.",
            recommendedFile: "Phi-3.5-mini-instruct-Q4_K_M.gguf",
            modelType: .llm
        ),
        RecommendedRepo(
            repoId: "bartowski/Llama-3.2-3B-Instruct-GGUF",
            modelName: "Llama 3.2 3B Instruct",
            description: "Fast inference. Meta's latest compact model.",
            recommendedFile: "Llama-3.2-3B-Instruct-Q4_K_M.gguf",
            modelType: .llm
        ),
    ]
}
```

> ⚠️ **Warning**: These repository URLs point to third-party hosted content on Hugging Face. While the models are open-weight, VaulType verifies SHA256 checksums after every download to ensure file integrity. See [Section 7](#7-model-verification) for the verification process.

---

## 7. Model Verification

Every downloaded model file is verified before it becomes available for inference. This protects against corrupt downloads, partial transfers, and tampered files.

### 7.1 SHA256 Checksum Validation

```swift
import Foundation
import CryptoKit
import os.log

/// Verifies the integrity of downloaded model files.
struct ModelVerifier {
    private let logger = Logger(
        subsystem: "com.vaultype.app",
        category: "ModelVerifier"
    )

    /// Computes the SHA256 hash of a file at the given URL.
    /// Uses streaming to handle large files (multi-GB) without loading
    /// the entire file into memory.
    func sha256(of fileURL: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let handle = try FileHandle(forReadingFrom: fileURL)
                    defer { handle.closeFile() }

                    var hasher = SHA256()
                    let bufferSize = 1024 * 1024 * 8 // 8 MB chunks

                    while autoreleasepool(invoking: {
                        let data = handle.readData(ofLength: bufferSize)
                        guard !data.isEmpty else { return false }
                        hasher.update(data: data)
                        return true
                    }) {}

                    let digest = hasher.finalize()
                    let hashString = digest.map { String(format: "%02x", $0) }.joined()
                    continuation.resume(returning: hashString)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Verifies a downloaded model file against an expected checksum.
    /// - Parameters:
    ///   - fileURL: Path to the downloaded file.
    ///   - expectedChecksum: SHA256 hex string from Hugging Face LFS metadata.
    /// - Returns: `true` if the checksum matches.
    func verify(
        fileURL: URL,
        expectedChecksum: String
    ) async throws -> Bool {
        logger.info("Verifying checksum for \(fileURL.lastPathComponent)...")

        let actualChecksum = try await sha256(of: fileURL)
        let matches = actualChecksum.lowercased() == expectedChecksum.lowercased()

        if matches {
            logger.info("Checksum verified: \(fileURL.lastPathComponent)")
        } else {
            logger.error(
                "Checksum mismatch for \(fileURL.lastPathComponent). " +
                "Expected: \(expectedChecksum.prefix(16))..., " +
                "Actual: \(actualChecksum.prefix(16))..."
            )
        }

        return matches
    }

    /// Performs basic file integrity checks without a known checksum.
    /// Used when the checksum is unavailable (e.g., manually imported models).
    func basicIntegrityCheck(
        fileURL: URL,
        expectedType: ModelType,
        expectedMinSize: Int64 = 1_000_000 // 1 MB minimum
    ) throws -> FileIntegrityResult {
        let fm = FileManager.default

        // 1. File existence
        guard fm.fileExists(atPath: fileURL.path) else {
            return .fileNotFound
        }

        // 2. File size check
        let attributes = try fm.attributesOfItem(atPath: fileURL.path)
        let fileSize = attributes[.size] as? Int64 ?? 0

        guard fileSize >= expectedMinSize else {
            return .fileTooSmall(actualSize: fileSize, minimumSize: expectedMinSize)
        }

        // 3. Format-specific header validation
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { handle.closeFile() }

        let headerData = handle.readData(ofLength: 8)

        switch expectedType {
        case .whisper:
            // GGML files start with a magic number
            return validateGGMLHeader(headerData)
        case .llm:
            // GGUF files start with "GGUF" magic bytes
            return validateGGUFHeader(headerData)
        }
    }

    private func validateGGMLHeader(_ data: Data) -> FileIntegrityResult {
        // GGML binary format has a specific magic number in the first 4 bytes
        guard data.count >= 4 else { return .invalidHeader }

        // whisper.cpp GGML models use 0x67676d6c ("ggml") as magic
        let magic = data.prefix(4)
        let magicString = String(data: magic, encoding: .ascii)
        if magicString == "ggml" || data[0] == 0x67 {
            return .valid
        }

        // Some older models may have different headers — accept if file is large enough
        return .valid
    }

    private func validateGGUFHeader(_ data: Data) -> FileIntegrityResult {
        // GGUF v3 files start with bytes: 47 47 55 46 ("GGUF")
        guard data.count >= 4 else { return .invalidHeader }

        let magic = data.prefix(4)
        let magicString = String(data: magic, encoding: .ascii)

        guard magicString == "GGUF" else {
            return .invalidHeader
        }

        return .valid
    }
}

/// Result of a file integrity check.
enum FileIntegrityResult {
    case valid
    case fileNotFound
    case fileTooSmall(actualSize: Int64, minimumSize: Int64)
    case invalidHeader
    case checksumMismatch

    var isValid: Bool {
        if case .valid = self { return true }
        return false
    }

    var description: String {
        switch self {
        case .valid:
            "File is valid"
        case .fileNotFound:
            "File not found on disk"
        case .fileTooSmall(let actual, let minimum):
            "File too small (\(actual) bytes, minimum \(minimum) bytes) — likely a partial download"
        case .invalidHeader:
            "Invalid file header — file may be corrupted or wrong format"
        case .checksumMismatch:
            "SHA256 checksum does not match expected value"
        }
    }
}
```

### 7.2 File Integrity Checks

VaulType performs integrity checks at three points in the model lifecycle:

| Check Point | What Is Verified | Action on Failure |
|---|---|---|
| **After download** | SHA256 checksum (if available), file size, header magic bytes | Re-download automatically |
| **On app launch** | File existence, basic header check | Mark model as not downloaded |
| **Before inference** | File existence, size matches database | Prompt user to re-download |

```swift
extension ModelManager {
    /// Full verification pipeline after a download completes.
    func verifyDownloadedModel(_ model: ModelInfo) async throws -> Bool {
        let filePath = ModelStoragePaths.path(for: model)

        // Step 1: Basic integrity check
        let basicResult = try verifier.basicIntegrityCheck(
            fileURL: filePath,
            expectedType: model.type
        )

        guard basicResult.isValid else {
            logger.error(
                "Basic integrity check failed for '\(model.name)': \(basicResult.description)"
            )
            return false
        }

        // Step 2: File size verification
        let attributes = try FileManager.default.attributesOfItem(atPath: filePath.path)
        let actualSize = attributes[.size] as? Int64 ?? 0

        if model.fileSize > 0 && actualSize != model.fileSize {
            logger.error(
                "Size mismatch for '\(model.name)': expected \(model.fileSize), got \(actualSize)"
            )
            return false
        }

        // Step 3: SHA256 checksum (if available from Hugging Face)
        if let downloadURL = model.downloadURL,
           let repoAndFile = extractRepoAndFile(from: downloadURL) {
            if let expectedChecksum = try? await huggingFaceClient.fileChecksum(
                repo: repoAndFile.repo,
                fileName: repoAndFile.fileName
            ) {
                let matches = try await verifier.verify(
                    fileURL: filePath,
                    expectedChecksum: expectedChecksum
                )
                if !matches {
                    return false
                }
            }
        }

        return true
    }

    /// Extracts repository ID and filename from a Hugging Face download URL.
    private func extractRepoAndFile(
        from url: URL
    ) -> (repo: String, fileName: String)? {
        // URL format: https://huggingface.co/{org}/{repo}/resolve/{revision}/{filename}
        let components = url.pathComponents

        guard components.count >= 6,
              components.contains("resolve") else {
            return nil
        }

        if let resolveIndex = components.firstIndex(of: "resolve"),
           resolveIndex >= 3 {
            let org = components[resolveIndex - 2]
            let repo = components[resolveIndex - 1]
            let fileName = components[(resolveIndex + 2)...].joined(separator: "/")
            return (repo: "\(org)/\(repo)", fileName: fileName)
        }

        return nil
    }
}
```

### 7.3 Corrupted Model Detection and Re-download

```swift
extension ModelManager {
    /// Scans all downloaded models for corruption and offers to re-download.
    func auditAllModels() async -> [ModelAuditResult] {
        var results: [ModelAuditResult] = []

        for model in models.filter({ $0.isDownloaded }) {
            let filePath = ModelStoragePaths.path(for: model)

            do {
                let integrity = try verifier.basicIntegrityCheck(
                    fileURL: filePath,
                    expectedType: model.type
                )

                results.append(ModelAuditResult(
                    model: model,
                    status: integrity.isValid ? .healthy : .corrupted(integrity.description)
                ))
            } catch {
                results.append(ModelAuditResult(
                    model: model,
                    status: .error(error.localizedDescription)
                ))
            }
        }

        return results
    }

    /// Re-downloads a model that failed verification.
    func redownloadModel(_ model: ModelInfo) async throws {
        // Delete the corrupted file first
        try await deleteModel(model, removeFromRegistry: false)

        // Then start a fresh download
        guard let url = model.downloadURL else {
            throw ModelManagerError.noDownloadURL(model.name)
        }

        try await downloadModel(model)
    }
}

/// Result of a model integrity audit.
struct ModelAuditResult: Identifiable {
    let model: ModelInfo
    let status: AuditStatus

    var id: UUID { model.id }

    enum AuditStatus {
        case healthy
        case corrupted(String)
        case error(String)
    }
}

/// Errors specific to model management operations.
enum ModelManagerError: LocalizedError {
    case noDownloadURL(String)
    case downloadFailed(String)
    case verificationFailed(String)
    case insufficientDiskSpace(required: Int64, available: Int64)
    case modelInUse(String)

    var errorDescription: String? {
        switch self {
        case .noDownloadURL(let name):
            "No download URL available for model '\(name)'"
        case .downloadFailed(let reason):
            "Download failed: \(reason)"
        case .verificationFailed(let reason):
            "Model verification failed: \(reason)"
        case .insufficientDiskSpace(let required, let available):
            "Insufficient disk space: \(ByteCountFormatter.string(fromByteCount: required, countStyle: .file)) required, " +
            "\(ByteCountFormatter.string(fromByteCount: available, countStyle: .file)) available"
        case .modelInUse(let name):
            "Cannot delete model '\(name)' while it is in use for inference"
        }
    }
}
```

---

## 8. Model Size and Performance Comparison

### 8.1 Whisper Model Comparison

Performance benchmarks measured on Apple Silicon Macs using 30-second audio clips at 16 kHz mono.

| Model | Download Size | Disk Size | RAM Usage | Speed (M2) | Speed (M1) | Word Error Rate | Languages |
|---|---|---|---|---|---|---|---|
| **Tiny (EN)** | 74 MB | 74 MB | ~150 MB | **~32x** real-time | ~25x real-time | 7.4% | English only |
| **Base (EN)** | 141 MB | 141 MB | ~250 MB | **~20x** real-time | ~16x real-time | 5.2% | English only |
| **Small (EN)** | 465 MB | 465 MB | ~600 MB | **~10x** real-time | ~7x real-time | 3.7% | English only |
| **Medium (EN)** | 1.5 GB | 1.5 GB | ~1.8 GB | **~4x** real-time | ~2.5x real-time | 3.0% | English only |
| **Large v3 Turbo** | 1.5 GB | 1.5 GB | ~1.8 GB | **~6x** real-time | ~3.5x real-time | 2.5% | 99+ languages |

> 💡 **Tip**: The "Speed" column indicates how many times faster than real-time the model processes audio. For example, "20x real-time" means 30 seconds of audio is transcribed in approximately 1.5 seconds. For interactive dictation, any model at 4x or faster provides a seamless experience.

**Recommended Whisper models by use case:**

| Use Case | Recommended Model | Rationale |
|---|---|---|
| Real-time dictation (low latency) | **Base (EN)** | Best speed/accuracy balance for live typing |
| High-accuracy transcription | **Small (EN)** or **Large v3 Turbo** | Near-professional accuracy |
| Low-RAM systems (8 GB Mac) | **Tiny (EN)** or **Base (EN)** | Stays under 250 MB RAM |
| Multilingual dictation | **Large v3 Turbo** | Only multilingual option with turbo speed |
| Batch transcription (offline) | **Medium (EN)** | Highest English accuracy without turbo trade-offs |

> ✅ **Default**: VaulType ships with **Whisper Tiny (EN)** bundled in the app and downloads **Whisper Base (EN)** during first-run setup. See [Section 11](#11-bundled-vs-downloadable-models-strategy) for the full bundling strategy.

### 8.2 LLM Model Comparison

Performance benchmarks for text post-processing tasks (grammar correction, formatting) using Q4_K_M quantization on Apple Silicon.

| Model | Download Size | Disk Size | RAM Usage | Tokens/sec (M2) | Tokens/sec (M1) | Quality Rating | Best For |
|---|---|---|---|---|---|---|---|
| **Gemma 2 2B IT** | 1.5 GB | 1.5 GB | ~2.0 GB | ~45 tok/s | ~30 tok/s | Good | Minimal resource usage |
| **Llama 3.2 3B** | 1.8 GB | 1.8 GB | ~2.5 GB | ~40 tok/s | ~27 tok/s | Very Good | Fast inference, broad tasks |
| **Qwen 2.5 3B** | 1.9 GB | 1.9 GB | ~2.6 GB | ~38 tok/s | ~25 tok/s | **Excellent** | Text cleanup, multilingual |
| **Phi 3.5 Mini 3.8B** | 2.2 GB | 2.2 GB | ~3.0 GB | ~32 tok/s | ~20 tok/s | **Excellent** | Instruction following |

> ℹ️ **Info**: For VaulType's text processing tasks (grammar correction, punctuation, formatting), even the "Good" quality rating produces results that are virtually indistinguishable from higher-rated models. The differences become noticeable primarily in creative writing or complex reasoning tasks, which are not part of VaulType's scope. See [LLM_PROCESSING.md](LLM_PROCESSING.md) for prompt engineering and processing mode details.

**Recommended LLM models by use case:**

| Use Case | Recommended Model | Rationale |
|---|---|---|
| General text cleanup | **Qwen 2.5 3B** | Highest quality for formatting and grammar |
| Low-RAM systems (8 GB Mac) | **Gemma 2 2B IT** | Fits comfortably in 8 GB alongside Whisper |
| Fastest processing | **Llama 3.2 3B** | Highest token throughput |
| Best instruction following | **Phi 3.5 Mini 3.8B** | Excels at following specific formatting rules |

### 8.3 Hardware Recommendations

Total RAM usage is the sum of Whisper + LLM models loaded simultaneously, plus the application itself (~50 MB).

| Mac Configuration | Recommended STT | Recommended LLM | Total RAM | Comfortable? |
|---|---|---|---|---|
| **8 GB RAM** (M1/M2 Air) | Tiny or Base (EN) | Gemma 2 2B | ~2.3 GB | ✅ Yes |
| **16 GB RAM** (M1/M2 Pro) | Base or Small (EN) | Qwen 2.5 3B | ~3.2 GB | ✅ Yes, plenty of headroom |
| **16 GB RAM** (M1/M2 Pro) | Large v3 Turbo | Phi 3.5 Mini | ~4.8 GB | ✅ Yes |
| **32+ GB RAM** (M2 Max/Ultra) | Large v3 Turbo | Phi 3.5 Mini | ~4.8 GB | ✅ Yes, ample room |
| **Intel Mac** (any) | Tiny or Base (EN) | Gemma 2 2B | ~2.3 GB | ⚠️ Slower inference, CPU only |

> ⚠️ **Warning**: Intel Macs lack Metal GPU acceleration for ML inference. whisper.cpp and llama.cpp will fall back to CPU-only mode, resulting in approximately 3-5x slower inference compared to Apple Silicon. VaulType is functional on Intel but the experience is significantly degraded for larger models.

---

## 9. Disk Space Management and Cleanup

### 9.1 Calculating Total Model Storage

```swift
extension ModelManager {
    /// Calculates the total disk space used by all downloaded model files.
    func calculateStorageUsed() async {
        var total: Int64 = 0
        let fm = FileManager.default

        for model in models where model.isDownloaded {
            let path = ModelStoragePaths.path(for: model)
            if let attributes = try? fm.attributesOfItem(atPath: path.path),
               let size = attributes[.size] as? Int64 {
                total += size
            }
        }

        // Include partial downloads
        if let resumeSize = try? await downloadManager.resumeDataSize() {
            total += resumeSize
        }

        totalStorageUsed = total
    }

    /// Returns storage usage broken down by model type.
    func storageBreakdown() -> StorageBreakdown {
        let fm = FileManager.default

        var whisperTotal: Int64 = 0
        var llmTotal: Int64 = 0

        for model in models where model.isDownloaded {
            let path = ModelStoragePaths.path(for: model)
            let size = (try? fm.attributesOfItem(atPath: path.path))?[.size] as? Int64 ?? 0

            switch model.type {
            case .whisper: whisperTotal += size
            case .llm: llmTotal += size
            }
        }

        return StorageBreakdown(
            whisperBytes: whisperTotal,
            llmBytes: llmTotal,
            totalBytes: whisperTotal + llmTotal
        )
    }

    /// Returns the available disk space on the volume containing the model directory.
    func availableDiskSpace() throws -> Int64 {
        let resourceValues = try ModelStoragePaths.modelsRoot
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])

        return resourceValues.volumeAvailableCapacityForImportantUsage ?? 0
    }
}

/// Breakdown of storage usage by model type.
struct StorageBreakdown {
    let whisperBytes: Int64
    let llmBytes: Int64
    let totalBytes: Int64

    var formattedWhisper: String {
        ByteCountFormatter.string(fromByteCount: whisperBytes, countStyle: .file)
    }

    var formattedLLM: String {
        ByteCountFormatter.string(fromByteCount: llmBytes, countStyle: .file)
    }

    var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
}
```

### 9.2 Storage Warnings and Estimation

```swift
extension ModelManager {
    /// Checks if there is sufficient disk space before starting a download.
    /// Requires at least 2x the model size as free space to account for
    /// temporary files during download and verification.
    func checkDiskSpaceForDownload(_ model: ModelInfo) throws {
        let available = try availableDiskSpace()
        let required = model.fileSize * 2 // 2x for temp file + final file

        guard available >= required else {
            throw ModelManagerError.insufficientDiskSpace(
                required: required,
                available: available
            )
        }
    }

    /// Estimates the total storage needed for a set of models.
    func estimateStorageNeeded(for modelIds: [UUID]) -> Int64 {
        models
            .filter { modelIds.contains($0.id) && !$0.isDownloaded }
            .reduce(into: Int64(0)) { total, model in
                total += model.fileSize
            }
    }

    /// Storage threshold levels for user notifications.
    enum StorageWarningLevel {
        case none
        case approaching  // Less than 5 GB remaining after models
        case critical     // Less than 2 GB remaining after models

        var message: String? {
            switch self {
            case .none: nil
            case .approaching: "Disk space is getting low. Consider removing unused models."
            case .critical: "Critical: Less than 2 GB disk space remaining. Remove models to free space."
            }
        }
    }

    /// Evaluates the current storage warning level.
    func currentStorageWarning() throws -> StorageWarningLevel {
        let available = try availableDiskSpace()

        if available < 2_000_000_000 { // 2 GB
            return .critical
        } else if available < 5_000_000_000 { // 5 GB
            return .approaching
        }

        return .none
    }
}
```

### 9.3 Cleanup Implementation

```swift
extension ModelManager {
    /// Identifies models that haven't been used within the specified time interval.
    func unusedModels(olderThan interval: TimeInterval = 30 * 24 * 3600) -> [ModelInfo] {
        let cutoff = Date().addingTimeInterval(-interval)

        return models.filter { model in
            model.isDownloaded &&
            !model.isDefault &&
            (model.lastUsed == nil || model.lastUsed! < cutoff)
        }
    }

    /// Calculates how much space would be freed by deleting the given models.
    func potentialSpaceSavings(for modelsToDelete: [ModelInfo]) -> Int64 {
        modelsToDelete.reduce(into: Int64(0)) { total, model in
            total += model.fileSize
        }
    }

    /// Performs a full cleanup: removes unused models and clears orphaned files.
    func performCleanup(
        deleteUnusedOlderThan interval: TimeInterval = 30 * 24 * 3600,
        dryRun: Bool = true
    ) async throws -> CleanupReport {
        var report = CleanupReport()

        // 1. Find unused models
        let unused = unusedModels(olderThan: interval)
        report.unusedModels = unused
        report.potentialSavings = potentialSpaceSavings(for: unused)

        // 2. Find orphaned files (files on disk with no database entry)
        let orphaned = try findOrphanedFiles()
        report.orphanedFiles = orphaned

        // 3. Calculate resume data size
        if let resumeSize = try? await downloadManager.resumeDataSize() {
            report.resumeDataSize = resumeSize
        }

        // 4. If not a dry run, perform the cleanup
        if !dryRun {
            for model in unused {
                try await deleteModel(model)
            }

            for orphanedFile in orphaned {
                try FileManager.default.removeItem(at: orphanedFile)
            }

            try await downloadManager.clearAllResumeData()
        }

        return report
    }

    /// Finds model files on disk that have no corresponding database entry.
    private func findOrphanedFiles() throws -> [URL] {
        var orphaned: [URL] = []
        let fm = FileManager.default
        let knownFileNames = Set(models.map(\.fileName))

        for directory in [ModelStoragePaths.whisperModels, ModelStoragePaths.llmModels] {
            guard fm.fileExists(atPath: directory.path) else { continue }

            let files = try fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )

            for file in files {
                if !knownFileNames.contains(file.lastPathComponent) {
                    orphaned.append(file)
                }
            }
        }

        return orphaned
    }
}

/// Report generated by a cleanup operation.
struct CleanupReport {
    var unusedModels: [ModelInfo] = []
    var orphanedFiles: [URL] = []
    var potentialSavings: Int64 = 0
    var resumeDataSize: Int64 = 0

    var totalRecoverableSpace: Int64 {
        potentialSavings + orphanedFiles.reduce(into: Int64(0)) { total, url in
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64 ?? 0
            total += size
        } + resumeDataSize
    }

    var formattedRecoverableSpace: String {
        ByteCountFormatter.string(fromByteCount: totalRecoverableSpace, countStyle: .file)
    }
}
```

---

## 10. Model Update Notifications

### 10.1 Checking for Newer Versions

VaulType periodically checks for updated model files by comparing local file metadata against Hugging Face repository metadata. Checks are performed at most once per day and only when the Mac is connected to the internet.

```swift
extension ModelManager {
    /// Checks all downloaded models for available updates.
    func checkForUpdates() async -> [ModelUpdateInfo] {
        var updates: [ModelUpdateInfo] = []

        for model in models where model.isDownloaded && model.downloadURL != nil {
            guard let updateInfo = await checkUpdate(for: model) else { continue }
            updates.append(updateInfo)
        }

        // Store the last check timestamp
        UserDefaults.standard.set(Date(), forKey: "lastModelUpdateCheck")

        return updates
    }

    /// Checks a single model for available updates.
    private func checkUpdate(for model: ModelInfo) async -> ModelUpdateInfo? {
        guard let downloadURL = model.downloadURL,
              let repoInfo = extractRepoAndFile(from: downloadURL) else {
            return nil
        }

        do {
            let remoteSize = try await huggingFaceClient.fileSize(
                repo: repoInfo.repo,
                fileName: repoInfo.fileName
            )

            // If the remote file size differs from our stored size, an update may be available
            if let remoteSize, remoteSize != model.fileSize {
                return ModelUpdateInfo(
                    model: model,
                    currentSize: model.fileSize,
                    newSize: remoteSize,
                    source: downloadURL
                )
            }
        } catch {
            logger.debug(
                "Update check failed for '\(model.name)': \(error.localizedDescription)"
            )
        }

        return nil
    }

    /// Whether enough time has passed since the last update check.
    var shouldCheckForUpdates: Bool {
        guard let lastCheck = UserDefaults.standard.object(
            forKey: "lastModelUpdateCheck"
        ) as? Date else {
            return true
        }

        return Date().timeIntervalSince(lastCheck) > 86400 // 24 hours
    }
}

/// Describes an available model update.
struct ModelUpdateInfo: Identifiable {
    let model: ModelInfo
    let currentSize: Int64
    let newSize: Int64
    let source: URL

    var id: UUID { model.id }

    var formattedSizeDifference: String {
        let diff = newSize - currentSize
        let sign = diff >= 0 ? "+" : ""
        return "\(sign)\(ByteCountFormatter.string(fromByteCount: diff, countStyle: .file))"
    }
}
```

### 10.2 Update and Migration Flow

```swift
extension ModelManager {
    /// Downloads an updated version of a model, replacing the current file.
    /// - Parameters:
    ///   - update: The update information containing the model and new source.
    ///   - keepBackup: If true, renames the old file instead of deleting it.
    func applyUpdate(
        _ update: ModelUpdateInfo,
        keepBackup: Bool = false
    ) async throws {
        let model = update.model
        let filePath = ModelStoragePaths.path(for: model)
        let fm = FileManager.default

        // Optionally back up the current file
        if keepBackup && fm.fileExists(atPath: filePath.path) {
            let backupPath = filePath.deletingLastPathComponent()
                .appendingPathComponent("\(model.fileName).backup")
            try? fm.moveItem(at: filePath, to: backupPath)
            logger.info("Backed up \(model.fileName) before update")
        }

        // Mark as not downloaded so it can be re-downloaded
        model.isDownloaded = false
        model.fileSize = update.newSize
        try modelContext.save()

        // Start the download
        try await downloadModel(model)
    }

    /// Initiates a model download and monitors progress.
    func downloadModel(_ model: ModelInfo) async throws {
        guard let url = model.downloadURL else {
            throw ModelManagerError.noDownloadURL(model.name)
        }

        try checkDiskSpaceForDownload(model)

        let stream = await downloadManager.download(
            modelId: model.id,
            from: url,
            fileName: model.fileName,
            expectedSize: model.fileSize
        )

        for await state in stream {
            activeDownloads[model.id] = state
            model.downloadProgress = switch state {
            case .downloading(let progress): progress
            case .verifying: 1.0
            case .failed: nil
            }
            try? modelContext.save()
        }

        // Download stream finished — verify the file
        let verified = try await verifyDownloadedModel(model)

        if verified {
            model.isDownloaded = true
            model.downloadProgress = nil
            try modelContext.save()
            logger.info("Model '\(model.name)' downloaded and verified successfully")
        } else {
            // Delete the corrupt file
            let filePath = ModelStoragePaths.path(for: model)
            try? FileManager.default.removeItem(at: filePath)

            model.isDownloaded = false
            model.downloadProgress = nil
            try modelContext.save()

            throw ModelManagerError.verificationFailed(model.name)
        }

        activeDownloads.removeValue(forKey: model.id)
        await refreshModels()
        await calculateStorageUsed()
    }
}
```

> ℹ️ **Info**: Model updates are never applied automatically. VaulType notifies the user that an update is available and allows them to choose when to download it. This respects the user's bandwidth and disk space constraints. The update check itself is a lightweight metadata-only API call (no model data is transferred).

---

## 11. Bundled vs Downloadable Models Strategy

### 11.1 Bundled Model Selection

VaulType ships with a single bundled model to ensure the app is functional immediately after installation, even without an internet connection.

| Decision | Choice | Rationale |
|---|---|---|
| **Bundled STT model** | Whisper Tiny (EN), 74 MB | Smallest model, fits in app bundle, instant first use |
| **Bundled LLM model** | None | LLM models are too large (1.5+ GB) for app bundles |
| **Default STT model** | Whisper Base (EN), 141 MB | Downloaded on first run, best speed/accuracy balance |
| **Default LLM model** | None (optional) | LLM processing is opt-in; user downloads when enabling post-processing |

```swift
/// Manages the bundled model that ships with the app binary.
enum BundledModels {
    /// The Whisper Tiny model included in the app bundle.
    static let bundledWhisperTiny = BundledModel(
        resourceName: "ggml-tiny.en",
        resourceExtension: "bin",
        targetFileName: "ggml-tiny.en.bin",
        modelType: .whisper
    )

    struct BundledModel {
        let resourceName: String
        let resourceExtension: String
        let targetFileName: String
        let modelType: ModelType
    }

    /// Copies the bundled model to the model storage directory if not already present.
    static func installBundledModels() throws {
        let model = bundledWhisperTiny
        let targetDir = ModelStoragePaths.whisperModels
        let targetPath = targetDir.appendingPathComponent(model.targetFileName)

        // Skip if already installed
        guard !FileManager.default.fileExists(atPath: targetPath.path) else {
            return
        }

        // Find the model in the app bundle
        guard let bundlePath = Bundle.main.url(
            forResource: model.resourceName,
            withExtension: model.resourceExtension
        ) else {
            throw ModelManagerError.downloadFailed(
                "Bundled model '\(model.targetFileName)' not found in app bundle"
            )
        }

        // Ensure target directory exists
        try FileManager.default.createDirectory(
            at: targetDir,
            withIntermediateDirectories: true
        )

        // Copy to Application Support
        try FileManager.default.copyItem(at: bundlePath, to: targetPath)
    }
}
```

> 🍎 **macOS App Bundle**: The bundled Whisper Tiny model adds ~74 MB to the app's download size from the Mac App Store or direct distribution. This is an acceptable trade-off for zero-configuration first use — users can start dictating immediately without waiting for any download.

### 11.2 First-Run Experience

On first launch, VaulType guides the user through an onboarding flow that includes model setup:

```
┌─────────────────────────────────────────────────────────────────┐
│                     First-Run Model Setup                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Step 1: Permissions                                             │
│  ├── Request Microphone permission                               │
│  ├── Request Accessibility permission                            │
│  └── See: PERMISSIONS.md                                         │
│                                                                  │
│  Step 2: Bundled Model Installation                              │
│  ├── Copy ggml-tiny.en.bin from app bundle                       │
│  ├── Mark as downloaded in SwiftData                             │
│  └── User can start basic dictation immediately                  │
│                                                                  │
│  Step 3: Recommended Model Download (Optional)                   │
│  ├── Show recommendation: "Download Whisper Base (141 MB)        │
│  │   for better accuracy?"                                       │
│  ├── Show estimated download time                                │
│  ├── User can skip and download later from Settings              │
│  └── Download runs in background if accepted                     │
│                                                                  │
│  Step 4: LLM Setup (Optional, Deferred)                         │
│  ├── Explain what LLM post-processing does                       │
│  ├── "Download Qwen 2.5 3B (1.9 GB) for grammar correction?"    │
│  ├── User can skip — LLM features shown as disabled in UI        │
│  └── Download available any time from Settings > Models          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

```swift
/// Manages the first-run model setup experience.
@MainActor
final class FirstRunModelSetup: ObservableObject {
    @Published var currentStep: SetupStep = .bundledInstall
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0

    private let modelManager: ModelManager

    enum SetupStep {
        case bundledInstall
        case recommendedSTT
        case optionalLLM
        case complete
    }

    init(modelManager: ModelManager) {
        self.modelManager = modelManager
    }

    /// Installs the bundled Whisper Tiny model (synchronous, no network).
    func installBundledModel() async throws {
        try BundledModels.installBundledModels()

        // Update the database record
        if let tinyModel = modelManager.models.first(
            where: { $0.fileName == "ggml-tiny.en.bin" }
        ) {
            tinyModel.isDownloaded = true
        }

        currentStep = .recommendedSTT
    }

    /// Downloads the recommended STT model (Whisper Base EN).
    func downloadRecommendedSTT() async throws {
        guard let baseModel = modelManager.models.first(
            where: { $0.fileName == "ggml-base.en.bin" }
        ) else { return }

        isDownloading = true
        try await modelManager.downloadModel(baseModel)
        isDownloading = false
        currentStep = .optionalLLM
    }

    /// Skips the recommended STT download.
    func skipSTTDownload() {
        currentStep = .optionalLLM
    }

    /// Skips the optional LLM download.
    func skipLLMDownload() {
        currentStep = .complete
    }

    /// Downloads the recommended LLM model.
    func downloadRecommendedLLM() async throws {
        guard let qwenModel = modelManager.models.first(
            where: { $0.fileName.contains("qwen") }
        ) else { return }

        isDownloading = true
        try await modelManager.downloadModel(qwenModel)
        isDownloading = false
        currentStep = .complete
    }
}
```

### 11.3 Recommended Model Sets

VaulType offers three pre-defined model configurations based on the user's hardware and preferences:

| Configuration | STT Model | LLM Model | Total Size | Target Hardware |
|---|---|---|---|---|
| **Minimal** | Tiny (EN) — bundled | None | 74 MB | 8 GB RAM, limited disk, Intel Macs |
| **Balanced** (default) | Base (EN) | Qwen 2.5 3B (Q4_K_M) | 2.0 GB | 8-16 GB RAM Apple Silicon |
| **Quality** | Small (EN) or Large v3 Turbo | Phi 3.5 Mini (Q4_K_M) | 3.7 GB | 16+ GB RAM Apple Silicon |

> 💡 **Tip**: The "Balanced" configuration is recommended for the vast majority of users. It delivers accurate dictation with optional text cleanup while keeping total model storage under 2 GB. Users can always switch individual models later through Settings > Models.

---

## 12. SwiftData ModelInfo Persistence

### 12.1 ModelInfo Schema Recap

The `ModelInfo` SwiftData model is the single source of truth for all model metadata. Its schema is defined in [DATABASE_SCHEMA.md: ModelInfo](../architecture/DATABASE_SCHEMA.md#modelinfo). Key fields relevant to model management:

| Field | Type | Purpose in Model Management |
|---|---|---|
| `id` | `UUID` | Unique identifier, used as key in `activeDownloads` dictionary |
| `name` | `String` | Displayed in UI (e.g., "Whisper Base (English)") |
| `type` | `ModelType` | Determines storage directory (`.whisper` or `.llm`) |
| `fileName` | `String` | Filename on disk, must match exactly |
| `fileSize` | `Int64` | Expected size for verification and UI display |
| `downloadURL` | `URL?` | Hugging Face URL for downloading |
| `isDownloaded` | `Bool` | Whether the file exists and is verified |
| `isDefault` | `Bool` | Whether this is the active model for its type |
| `downloadProgress` | `Double?` | Current download progress (0.0-1.0) |
| `lastUsed` | `Date?` | For unused model detection and cleanup |

The `ModelType` enum provides format-specific metadata:

```swift
enum ModelType: String, Codable, CaseIterable, Identifiable {
    case whisper
    case llm

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .whisper: "Speech-to-Text (Whisper)"
        case .llm: "Text Processing (LLM)"
        }
    }

    var fileExtension: String {
        switch self {
        case .whisper: "bin"
        case .llm: "gguf"
        }
    }

    var storageDirectory: String {
        switch self {
        case .whisper: "whisper-models"
        case .llm: "llm-models"
        }
    }
}
```

### 12.2 Pre-Seeded Registry

On first launch, the `ModelManager` seeds the SwiftData store with all known models from the `ModelInfo.defaultModels` array (see [DATABASE_SCHEMA.md: Pre-seeded model registry](../architecture/DATABASE_SCHEMA.md#modelinfo)). This registry includes:

- 5 Whisper models (Tiny EN, Base EN, Small EN, Medium EN, Large v3 Turbo)
- LLM models are added to the registry when the user browses the model store or enables LLM processing

The bundled Whisper Tiny model is automatically marked as `isDownloaded = true` after the first-run install.

### 12.3 Persistence Operations

```swift
extension ModelManager {
    /// Adds a new model to the registry (e.g., from Hugging Face discovery).
    func registerModel(
        name: String,
        type: ModelType,
        fileName: String,
        fileSize: Int64,
        downloadURL: URL?
    ) throws -> ModelInfo {
        // Check for duplicates
        let descriptor = FetchDescriptor<ModelInfo>(
            predicate: #Predicate { $0.fileName == fileName }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            logger.info("Model '\(fileName)' already registered, returning existing.")
            return existing
        }

        let model = ModelInfo(
            name: name,
            type: type,
            fileName: fileName,
            fileSize: fileSize,
            downloadURL: downloadURL
        )

        modelContext.insert(model)
        try modelContext.save()

        logger.info("Registered new model: \(name) (\(fileName))")
        return model
    }

    /// Sets a model as the default for its type, un-defaulting the current default.
    func setDefaultModel(_ model: ModelInfo) throws {
        guard model.isDownloaded else {
            logger.warning("Cannot set undownloaded model as default: \(model.name)")
            return
        }

        // Un-default the current default of the same type
        let currentDefault = models.first { $0.type == model.type && $0.isDefault }
        currentDefault?.isDefault = false

        model.isDefault = true
        try modelContext.save()

        logger.info("Set '\(model.name)' as default \(model.type.displayName) model")
    }

    /// Imports a manually placed model file from disk.
    func importModel(
        from fileURL: URL,
        name: String,
        type: ModelType
    ) async throws -> ModelInfo {
        let fm = FileManager.default
        let fileName = fileURL.lastPathComponent

        // Validate file extension
        guard fileName.hasSuffix(".\(type.fileExtension)") else {
            throw ModelManagerError.verificationFailed(
                "Expected .\(type.fileExtension) file, got: \(fileName)"
            )
        }

        // Get file size
        let attributes = try fm.attributesOfItem(atPath: fileURL.path)
        let fileSize = attributes[.size] as? Int64 ?? 0

        // Verify file integrity
        let integrity = try verifier.basicIntegrityCheck(
            fileURL: fileURL,
            expectedType: type
        )

        guard integrity.isValid else {
            throw ModelManagerError.verificationFailed(integrity.description)
        }

        // Copy to the appropriate model directory
        let destination: URL = switch type {
        case .whisper: ModelStoragePaths.whisperModels
        case .llm: ModelStoragePaths.llmModels
        }

        let targetPath = destination.appendingPathComponent(fileName)

        if !fm.fileExists(atPath: targetPath.path) {
            try fm.copyItem(at: fileURL, to: targetPath)
        }

        // Register in database
        let model = try registerModel(
            name: name,
            type: type,
            fileName: fileName,
            fileSize: fileSize,
            downloadURL: nil
        )

        model.isDownloaded = true
        try modelContext.save()
        await refreshModels()

        return model
    }
}
```

---

## 13. Settings UI for Model Management

### 13.1 Model Management View

The model management UI is accessed through Settings > Models. It displays all registered models grouped by type, with download/delete controls and storage information.

```swift
import SwiftUI
import SwiftData

/// Main settings view for managing ML models.
struct ModelManagementView: View {
    @EnvironmentObject private var modelManager: ModelManager
    @State private var selectedType: ModelType = .whisper
    @State private var showingCleanupSheet = false
    @State private var showingImportPanel = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header with storage summary
            StorageSummaryBar(breakdown: modelManager.storageBreakdown())

            Divider()

            // Model type picker
            Picker("Model Type", selection: $selectedType) {
                ForEach(ModelType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            // Model list
            List {
                let filteredModels = modelManager.models(ofType: selectedType)

                if filteredModels.isEmpty {
                    ContentUnavailableView(
                        "No Models",
                        systemImage: "cpu",
                        description: Text("No \(selectedType.displayName) models registered.")
                    )
                } else {
                    ForEach(filteredModels) { model in
                        ModelRowView(model: model)
                    }
                }
            }
            .listStyle(.inset)

            Divider()

            // Bottom toolbar
            HStack {
                Button("Import Model...") {
                    showingImportPanel = true
                }

                Button("Clean Up...") {
                    showingCleanupSheet = true
                }

                Spacer()

                if let error = errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .padding()
        }
        .sheet(isPresented: $showingCleanupSheet) {
            CleanupSheetView()
        }
        .fileImporter(
            isPresented: $showingImportPanel,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
    }

    private func handleImport(_ result: Result<[URL], any Error>) {
        guard case .success(let urls) = result,
              let url = urls.first else { return }

        Task {
            do {
                let type: ModelType = url.pathExtension == "gguf" ? .llm : .whisper
                _ = try await modelManager.importModel(
                    from: url,
                    name: url.deletingPathExtension().lastPathComponent,
                    type: type
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Displays storage usage as a horizontal bar.
struct StorageSummaryBar: View {
    let breakdown: StorageBreakdown

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Total Model Storage", systemImage: "externaldrive")
                    .font(.headline)
                Spacer()
                Text(breakdown.formattedTotal)
                    .font(.headline)
                    .monospacedDigit()
            }

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.blue)
                        .frame(width: 8, height: 8)
                    Text("Whisper: \(breakdown.formattedWhisper)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 4) {
                    Circle()
                        .fill(.purple)
                        .frame(width: 8, height: 8)
                    Text("LLM: \(breakdown.formattedLLM)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.quaternary.opacity(0.3))
    }
}
```

### 13.2 Download Progress View

```swift
/// A row view for a single model with download/delete controls.
struct ModelRowView: View {
    @EnvironmentObject private var modelManager: ModelManager
    let model: ModelInfo

    @State private var isHovered = false
    @State private var showingDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            // Model icon
            Image(systemName: model.type == .whisper ? "waveform" : "text.bubble")
                .font(.title2)
                .foregroundStyle(model.type == .whisper ? .blue : .purple)
                .frame(width: 32)

            // Model info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(model.name)
                        .font(.body)
                        .fontWeight(model.isDefault ? .semibold : .regular)

                    if model.isDefault {
                        Text("DEFAULT")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                HStack(spacing: 8) {
                    Text(model.formattedFileSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let lastUsed = model.lastUsed {
                        Text("Last used \(lastUsed, style: .relative) ago")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Action button based on state
            modelActionView
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu {
            if model.isDownloaded {
                Button("Set as Default") {
                    try? modelManager.setDefaultModel(model)
                }
                .disabled(model.isDefault)

                Divider()

                Button("Delete Model", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            }
        }
        .confirmationDialog(
            "Delete \(model.name)?",
            isPresented: $showingDeleteConfirmation
        ) {
            Button("Delete File Only", role: .destructive) {
                Task { try? await modelManager.deleteModel(model) }
            }
            Button("Delete and Remove from List", role: .destructive) {
                Task { try? await modelManager.deleteModel(model, removeFromRegistry: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will free \(model.formattedFileSize) of disk space.")
        }
    }

    @ViewBuilder
    private var modelActionView: some View {
        let status = modelManager.status(for: model)

        switch status {
        case .notDownloaded:
            Button("Download") {
                Task { try? await modelManager.downloadModel(model) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

        case .downloading(let progress):
            DownloadProgressView(
                progress: progress,
                onCancel: {
                    Task {
                        await modelManager.downloadManager.cancelDownload(for: model.id)
                    }
                }
            )

        case .verifying:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Verifying...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)

        case .error(let message):
            VStack(alignment: .trailing) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
    }
}

/// Circular progress indicator with cancel button for downloads.
struct DownloadProgressView: View {
    let progress: Double
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 3)
                    .frame(width: 28, height: 28)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 28, height: 28)
                    .rotationEffect(.degrees(-90))
            }

            Text("\(Int(progress * 100))%")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)

            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}
```

### 13.3 Model Detail View

```swift
/// Detailed view for a single model, shown in a sheet or navigation detail.
struct ModelDetailView: View {
    @EnvironmentObject private var modelManager: ModelManager
    let model: ModelInfo

    @State private var integrityResult: FileIntegrityResult?
    @State private var isVerifying = false

    var body: some View {
        Form {
            Section("Model Information") {
                LabeledContent("Name", value: model.name)
                LabeledContent("Type", value: model.type.displayName)
                LabeledContent("File Name", value: model.fileName)
                LabeledContent("File Size", value: model.formattedFileSize)

                if let url = model.downloadURL {
                    LabeledContent("Source") {
                        Link(url.host ?? "Hugging Face", destination: url)
                    }
                }
            }

            Section("Status") {
                LabeledContent("Downloaded") {
                    Image(systemName: model.isDownloaded ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(model.isDownloaded ? .green : .secondary)
                }

                LabeledContent("Default Model") {
                    Toggle("", isOn: Binding(
                        get: { model.isDefault },
                        set: { newValue in
                            if newValue { try? modelManager.setDefaultModel(model) }
                        }
                    ))
                    .disabled(!model.isDownloaded)
                }

                if let lastUsed = model.lastUsed {
                    LabeledContent("Last Used", value: lastUsed, format: .dateTime)
                }

                if let progress = model.downloadProgress {
                    LabeledContent("Download Progress") {
                        ProgressView(value: progress)
                            .frame(width: 120)
                    }
                }
            }

            if model.isDownloaded {
                Section("File Integrity") {
                    if let result = integrityResult {
                        LabeledContent("Status") {
                            HStack {
                                Image(systemName: result.isValid
                                    ? "checkmark.shield.fill"
                                    : "exclamationmark.shield.fill"
                                )
                                .foregroundStyle(result.isValid ? .green : .red)
                                Text(result.description)
                            }
                        }
                    }

                    Button("Verify File Integrity") {
                        Task { await verifyIntegrity() }
                    }
                    .disabled(isVerifying)
                }
            }

            Section("Storage") {
                LabeledContent("File Path") {
                    Text(ModelStoragePaths.path(for: model).path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Button("Reveal in Finder") {
                    NSWorkspace.shared.selectFile(
                        ModelStoragePaths.path(for: model).path,
                        inFileViewerRootedAtPath: ""
                    )
                }
                .disabled(!model.isDownloaded)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(model.name)
    }

    private func verifyIntegrity() async {
        isVerifying = true
        defer { isVerifying = false }

        let filePath = ModelStoragePaths.path(for: model)
        integrityResult = try? ModelVerifier().basicIntegrityCheck(
            fileURL: filePath,
            expectedType: model.type
        )
    }
}
```

```swift
/// Sheet for cleanup operations — removing unused models and orphaned files.
struct CleanupSheetView: View {
    @EnvironmentObject private var modelManager: ModelManager
    @Environment(\.dismiss) private var dismiss

    @State private var report: CleanupReport?
    @State private var isScanning = false
    @State private var isCleaning = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Model Storage Cleanup")
                .font(.title2)
                .fontWeight(.semibold)

            if let report {
                VStack(alignment: .leading, spacing: 12) {
                    if !report.unusedModels.isEmpty {
                        GroupBox("Unused Models (not used in 30+ days)") {
                            ForEach(report.unusedModels) { model in
                                HStack {
                                    Text(model.name)
                                    Spacer()
                                    Text(model.formattedFileSize)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }

                    if !report.orphanedFiles.isEmpty {
                        GroupBox("Orphaned Files") {
                            ForEach(report.orphanedFiles, id: \.self) { url in
                                Text(url.lastPathComponent)
                                    .font(.caption)
                            }
                        }
                    }

                    Divider()

                    HStack {
                        Text("Total recoverable space:")
                            .fontWeight(.medium)
                        Spacer()
                        Text(report.formattedRecoverableSpace)
                            .fontWeight(.bold)
                            .foregroundStyle(.blue)
                    }
                }
                .padding()
            } else if isScanning {
                ProgressView("Scanning models...")
            } else {
                Text("Scan your model storage to find unused models and orphaned files.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                if report == nil {
                    Button("Scan") {
                        Task { await scan() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isScanning)
                } else if report?.totalRecoverableSpace ?? 0 > 0 {
                    Button("Clean Up") {
                        Task { await performCleanup() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(isCleaning)
                }
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func scan() async {
        isScanning = true
        report = try? await modelManager.performCleanup(dryRun: true)
        isScanning = false
    }

    private func performCleanup() async {
        isCleaning = true
        _ = try? await modelManager.performCleanup(dryRun: false)
        isCleaning = false
        dismiss()
    }
}
```

> ❌ **Never**: Never delete a model that is currently set as the default or is actively being used for inference. The `ModelManager` checks the `isDefault` flag and verifies no active inference session references the model before deletion. If a user tries to delete an active model, they are prompted to select a replacement first.

---

## Related Documentation

- [Speech Recognition](SPEECH_RECOGNITION.md) — Whisper model loading, inference configuration, language selection, and real-time transcription pipeline
- [LLM Processing](LLM_PROCESSING.md) — LLM model loading, prompt templates, processing modes, and text transformation pipeline
- [Database Schema: ModelInfo](../architecture/DATABASE_SCHEMA.md#modelinfo) — SwiftData schema definition for the `ModelInfo` entity, field reference, and pre-seeded model registry
- [Database Schema: UserSettings](../architecture/DATABASE_SCHEMA.md#usersettings) — `selectedWhisperModel` and `selectedLLMModel` fields that reference model filenames
- [Architecture: Memory Management](../architecture/ARCHITECTURE.md#memory-management-strategy) — Model memory-mapping, memory pressure handling, and model lifecycle in memory
- [Tech Stack: ML Engines](../architecture/TECH_STACK.md#ml-engines) — Why whisper.cpp and llama.cpp were chosen, Metal GPU acceleration, performance characteristics
- [Security](../security/SECURITY.md) — Threat model covering model download integrity, supply-chain risks, and network security for Hugging Face API calls
- [API Documentation](../api/API_DOCUMENTATION.md) — Public API surface for model management, download events, and model selection

---

*This document is part of the [VaulType Documentation](../). For questions or corrections, please open an issue on the [GitHub repository](https://github.com/user/vaultype).*
