# LLM Processing Pipeline

> **Last Updated: 2026-02-13**
> **Component**: LLM Processing Engine
> **Module**: `HushType/Sources/LLM/`
> **Maintainer**: HushType Core Team
> **License**: GPL-3.0

---

## Table of Contents

- [1. Overview](#1-overview)
- [2. llama.cpp Integration Architecture](#2-llamacpp-integration-architecture)
  - [2.1 Build and Compilation](#21-build-and-compilation)
  - [2.2 Bridging Headers and Swift-C Interop](#22-bridging-headers-and-swift-c-interop)
  - [2.3 Metal GPU Acceleration](#23-metal-gpu-acceleration)
  - [2.4 Memory-Mapped GGUF Models](#24-memory-mapped-gguf-models)
  - [2.5 LlamaContext Wrapper](#25-llamacontext-wrapper)
- [3. Ollama Integration as Alternative Backend](#3-ollama-integration-as-alternative-backend)
  - [3.1 When to Use Ollama vs llama.cpp](#31-when-to-use-ollama-vs-llamacpp)
  - [3.2 Ollama Setup Instructions](#32-ollama-setup-instructions)
  - [3.3 API Endpoints Used](#33-api-endpoints-used)
  - [3.4 OllamaClient Implementation](#34-ollamaclient-implementation)
- [4. Unified Backend Protocol](#4-unified-backend-protocol)
  - [4.1 LLMBackend Protocol](#41-llmbackend-protocol)
  - [4.2 Backend Switching](#42-backend-switching)
- [5. Model Recommendations and Benchmarks](#5-model-recommendations-and-benchmarks)
  - [5.1 Recommended Models](#51-recommended-models)
  - [5.2 Performance Benchmarks](#52-performance-benchmarks)
  - [5.3 Model Selection Guidance](#53-model-selection-guidance)
- [6. Prompt Template System Design](#6-prompt-template-system-design)
  - [6.1 Template Variables](#61-template-variables)
  - [6.2 SwiftData PromptTemplate Model](#62-swiftdata-prompttemplate-model)
  - [6.3 Built-in Templates](#63-built-in-templates)
  - [6.4 Custom Templates](#64-custom-templates)
  - [6.5 Template Import and Export](#65-template-import-and-export)
- [7. Processing Mode Implementations](#7-processing-mode-implementations)
  - [7.1 Raw Mode](#71-raw-mode)
  - [7.2 Clean Mode](#72-clean-mode)
  - [7.3 Structure Mode](#73-structure-mode)
  - [7.4 Prompt Mode](#74-prompt-mode)
  - [7.5 Code Mode](#75-code-mode)
  - [7.6 Custom Mode](#76-custom-mode)
  - [7.7 Processing Mode Selection and Execution](#77-processing-mode-selection-and-execution)
- [8. Token Management and Context Window Handling](#8-token-management-and-context-window-handling)
  - [8.1 Context Window Sizes](#81-context-window-sizes)
  - [8.2 Token Counting](#82-token-counting)
  - [8.3 Truncation Strategies](#83-truncation-strategies)
- [9. Latency Optimization Strategies](#9-latency-optimization-strategies)
  - [9.1 Model Preloading](#91-model-preloading)
  - [9.2 Speculative Decoding](#92-speculative-decoding)
  - [9.3 Batch Size Tuning](#93-batch-size-tuning)
  - [9.4 Metal GPU Layer Offloading](#94-metal-gpu-layer-offloading)
- [10. Error Handling and Fallback](#10-error-handling-and-fallback)
  - [10.1 Error Types](#101-error-types)
  - [10.2 Fallback Chain](#102-fallback-chain)
  - [10.3 Timeout Handling](#103-timeout-handling)
  - [10.4 Memory Pressure Handling](#104-memory-pressure-handling)
- [11. LLM Processing Pipeline Architecture](#11-llm-processing-pipeline-architecture)
- [12. Configuration Reference](#12-configuration-reference)
- [13. Related Documentation](#13-related-documentation)

---

## 1. Overview

HushType's LLM Processing Pipeline transforms raw speech-to-text transcriptions into polished, context-aware text output. The entire pipeline runs locally on the user's machine, maintaining HushType's zero-network architecture: no cloud calls, no telemetry, no data exfiltration.

The pipeline supports two local LLM backends:

- **llama.cpp** -- Compiled as a static library directly into HushType. This is the primary, recommended backend offering the tightest integration, lowest latency, and zero external dependencies.
- **Ollama** -- An alternative backend that communicates with a locally-running Ollama server over `localhost:11434`. Useful for users who already manage models through Ollama or want to swap models without restarting HushType.

Both backends are abstracted behind a unified `LLMBackend` protocol, allowing seamless switching without affecting the rest of the application.

```
+------------------------------------------------------------------+
|                    HushType LLM Pipeline                         |
|                                                                  |
|  Speech Audio                                                    |
|      |                                                           |
|      v                                                           |
|  +-----------------+     +-----------------+                     |
|  | whisper.cpp     |---->| Raw Transcript  |                     |
|  | (ASR Engine)    |     | "i need to fix  |                     |
|  +-----------------+     |  the login bug" |                     |
|                          +---------+-------+                     |
|                                    |                             |
|                          +---------v---------+                   |
|                          | Processing Mode   |                   |
|                          | Selection         |                   |
|                          +---------+---------+                   |
|                                    |                             |
|              +----------+----------+----------+-------+          |
|              |          |          |          |        |          |
|              v          v          v          v        v          |
|           [Raw]     [Clean]   [Structure] [Prompt]  [Code]       |
|              |          |          |          |        |          |
|              |    +-----v----------v----------v--------v---+     |
|              |    | Prompt Template Engine                  |     |
|              |    | - Variable substitution                 |     |
|              |    | - Context injection                     |     |
|              |    | - Token budget calculation               |     |
|              |    +-----+----------------------------------+     |
|              |          |                                        |
|              |    +-----v----------------------------------+     |
|              |    | LLM Backend (llama.cpp / Ollama)       |     |
|              |    | - Model loading                         |     |
|              |    | - Inference                              |     |
|              |    | - Token generation                      |     |
|              |    +-----+----------------------------------+     |
|              |          |                                        |
|              +-----+----+                                        |
|                    |                                             |
|              +-----v-----------+                                 |
|              | Post-Processing |                                 |
|              | & Injection     |                                 |
|              +-----------------+                                 |
+------------------------------------------------------------------+
```

> :lock: **Security**: All LLM inference occurs on-device. The Ollama backend communicates exclusively over `localhost`. No model data, prompts, or outputs ever leave the machine.

---

## 2. llama.cpp Integration Architecture

### 2.1 Build and Compilation

llama.cpp is compiled as a static library (`.a`) and linked directly into the HushType binary. This eliminates any runtime dependency on external executables or dynamic libraries.

**Build configuration in `Package.swift`:**

```swift
// Package.swift (excerpt)
let package = Package(
    name: "HushType",
    platforms: [.macOS(.v14)],
    targets: [
        // llama.cpp as a C/C++ static library target
        .target(
            name: "CLlama",
            path: "Sources/CLlama",
            sources: [
                "llama.cpp/src/llama.cpp",
                "llama.cpp/src/llama-vocab.cpp",
                "llama.cpp/src/llama-grammar.cpp",
                "llama.cpp/src/llama-sampling.cpp",
                "llama.cpp/src/unicode.cpp",
                "llama.cpp/ggml/src/ggml.c",
                "llama.cpp/ggml/src/ggml-alloc.c",
                "llama.cpp/ggml/src/ggml-backend.c",
                "llama.cpp/ggml/src/ggml-metal.m",
                "llama.cpp/ggml/src/ggml-quants.c"
            ],
            publicHeadersPath: "include",
            cSettings: [
                .define("GGML_USE_METAL"),
                .define("GGML_METAL_EMBED_LIBRARY"),
                .define("ACCELERATE_NEW_LAPACK"),
                .unsafeFlags(["-O3", "-fno-objc-arc"]),
                .headerSearchPath("llama.cpp/include"),
                .headerSearchPath("llama.cpp/ggml/include")
            ],
            cxxSettings: [
                .define("GGML_USE_METAL"),
                .unsafeFlags(["-O3", "-std=c++17", "-fno-objc-arc"])
            ],
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("MetalPerformanceShaders"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Foundation")
            ]
        ),

        // Swift wrapper for llama.cpp
        .target(
            name: "LlamaSwift",
            dependencies: ["CLlama"],
            path: "Sources/LlamaSwift"
        ),

        // Main HushType app target
        .target(
            name: "HushType",
            dependencies: ["LlamaSwift", /* ... */]
        )
    ]
)
```

**Build steps (automated via Xcode or SPM):**

```bash
# Clone llama.cpp into the vendor directory
git submodule add https://github.com/ggerganov/llama.cpp Sources/CLlama/llama.cpp

# Build the full project (llama.cpp compiles as part of the build)
swift build -c release

# For Xcode builds, the static library is compiled automatically
# via the SPM target dependency graph
```

> :information_source: **Info**: llama.cpp is pinned to a specific commit hash in `.gitmodules` to ensure reproducible builds. Updates to llama.cpp must be tested against all supported models before merging.

> :apple: **macOS-specific**: The `GGML_USE_METAL` flag enables Metal GPU acceleration. The `GGML_METAL_EMBED_LIBRARY` flag embeds the Metal shader library directly into the binary, eliminating the need to ship a separate `.metallib` file.

### 2.2 Bridging Headers and Swift-C Interop

Since llama.cpp is a C/C++ library, a bridging header and Swift-friendly wrapper are required.

**Public bridging header (`Sources/CLlama/include/llama_bridge.h`):**

```swift
// This is a C header file -- shown here for completeness.
// File: Sources/CLlama/include/llama_bridge.h

#ifndef LLAMA_BRIDGE_H
#define LLAMA_BRIDGE_H

#include "llama.h"
#include "ggml.h"

// Re-export the core llama.cpp API functions that HushType uses.
// Swift can call these directly through the CLlama module.

#endif /* LLAMA_BRIDGE_H */
```

**Swift module map (`Sources/CLlama/include/module.modulemap`):**

```
module CLlama {
    header "llama_bridge.h"
    export *
}
```

**Swift interop wrapper (`Sources/LlamaSwift/LlamaContext.swift`):**

```swift
import Foundation
import CLlama

/// Wraps a llama.cpp context for safe use from Swift.
/// Manages the lifecycle of the underlying C model and context pointers.
public final class LlamaContext: @unchecked Sendable {

    // MARK: - Properties

    private let model: OpaquePointer      // llama_model *
    private let context: OpaquePointer    // llama_context *
    private let sampler: OpaquePointer    // llama_sampler *
    private let queue = DispatchQueue(label: "com.hushtype.llama", qos: .userInitiated)

    public let contextSize: Int32
    public let modelPath: String

    // MARK: - Initialization

    /// Loads a GGUF model and creates an inference context.
    /// - Parameters:
    ///   - path: Absolute path to the `.gguf` model file.
    ///   - contextSize: Maximum context window size in tokens.
    ///   - gpuLayers: Number of layers to offload to Metal GPU (-1 for all).
    ///   - seed: Random seed for sampling (0 for random).
    /// - Throws: `LlamaError` if the model cannot be loaded.
    public init(
        modelPath path: String,
        contextSize: Int32 = 4096,
        gpuLayers: Int32 = -1,
        seed: UInt32 = 0
    ) throws {
        self.modelPath = path
        self.contextSize = contextSize

        // Configure model parameters
        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = gpuLayers
        modelParams.use_mmap = true   // Memory-map the model file
        modelParams.use_mlock = false  // Do not pin in RAM

        // Load model from GGUF file
        guard let loadedModel = llama_load_model_from_file(path, modelParams) else {
            throw LlamaError.modelLoadFailed(path: path)
        }
        self.model = loadedModel

        // Configure context parameters
        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = UInt32(contextSize)
        ctxParams.n_batch = 512
        ctxParams.n_threads = UInt32(ProcessInfo.processInfo.activeProcessorCount)
        ctxParams.n_threads_batch = UInt32(ProcessInfo.processInfo.activeProcessorCount)
        ctxParams.seed = seed

        // Create inference context
        guard let ctx = llama_new_context_with_model(loadedModel, ctxParams) else {
            llama_free_model(loadedModel)
            throw LlamaError.contextCreationFailed
        }
        self.context = ctx

        // Configure sampler chain
        let samplerParams = llama_sampler_chain_default_params()
        guard let samplerChain = llama_sampler_chain_init(samplerParams) else {
            llama_free(ctx)
            llama_free_model(loadedModel)
            throw LlamaError.samplerCreationFailed
        }
        // Temperature + top-p sampling
        llama_sampler_chain_add(samplerChain, llama_sampler_init_temp(0.3))
        llama_sampler_chain_add(samplerChain, llama_sampler_init_top_p(0.9, 1))
        llama_sampler_chain_add(samplerChain, llama_sampler_init_dist(seed))
        self.sampler = samplerChain
    }

    deinit {
        llama_sampler_free(sampler)
        llama_free(context)
        llama_free_model(model)
    }

    // MARK: - Tokenization

    /// Tokenizes a string into llama tokens.
    public func tokenize(_ text: String, addBos: Bool = true) -> [llama_token] {
        let utf8 = text.utf8CString
        let maxTokens = Int32(utf8.count) + (addBos ? 1 : 0)
        var tokens = [llama_token](repeating: 0, count: Int(maxTokens))
        let count = llama_tokenize(model, text, Int32(text.utf8.count),
                                   &tokens, maxTokens, addBos, false)
        guard count >= 0 else { return [] }
        return Array(tokens.prefix(Int(count)))
    }

    /// Detokenizes a token back to its string representation.
    public func detokenize(_ token: llama_token) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = llama_token_to_piece(model, token, &buffer, 256, 0, false)
        guard length > 0 else { return "" }
        return String(cString: buffer)
    }

    // MARK: - Inference

    /// Runs inference on the given prompt and returns generated text.
    /// - Parameters:
    ///   - prompt: The input prompt string.
    ///   - maxTokens: Maximum number of tokens to generate.
    ///   - stopSequences: Strings that cause generation to halt.
    /// - Returns: The generated text.
    public func generate(
        prompt: String,
        maxTokens: Int = 512,
        stopSequences: [String] = []
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    let result = try self.syncGenerate(
                        prompt: prompt,
                        maxTokens: maxTokens,
                        stopSequences: stopSequences
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func syncGenerate(
        prompt: String,
        maxTokens: Int,
        stopSequences: [String]
    ) throws -> String {
        // Clear KV cache for fresh generation
        llama_kv_cache_clear(context)

        // Tokenize prompt
        let tokens = tokenize(prompt, addBos: true)
        guard !tokens.isEmpty else {
            throw LlamaError.tokenizationFailed
        }
        guard tokens.count < contextSize else {
            throw LlamaError.contextOverflow(
                tokenCount: tokens.count,
                contextSize: Int(contextSize)
            )
        }

        // Create batch and decode prompt
        var batch = llama_batch_init(Int32(tokens.count), 0, 1)
        defer { llama_batch_free(batch) }

        for (i, token) in tokens.enumerated() {
            llama_batch_add(&batch, token, Int32(i), [0], i == tokens.count - 1)
        }

        guard llama_decode(context, batch) == 0 else {
            throw LlamaError.decodeFailed
        }

        // Generate tokens
        var output = ""
        var generatedCount = 0

        while generatedCount < maxTokens {
            let newToken = llama_sampler_sample(sampler, context, -1)

            // Check for end-of-sequence
            if llama_token_is_eog(model, newToken) {
                break
            }

            let piece = detokenize(newToken)
            output += piece
            generatedCount += 1

            // Check stop sequences
            if stopSequences.contains(where: { output.hasSuffix($0) }) {
                for stop in stopSequences where output.hasSuffix(stop) {
                    output = String(output.dropLast(stop.count))
                }
                break
            }

            // Prepare next batch (single token)
            llama_batch_clear(&batch)
            llama_batch_add(&batch, newToken,
                           Int32(tokens.count + generatedCount), [0], true)

            guard llama_decode(context, batch) == 0 else {
                throw LlamaError.decodeFailed
            }
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

> :warning: **Warning**: `LlamaContext` is marked `@unchecked Sendable` because all access to the underlying C pointers is serialized through a dedicated `DispatchQueue`. Do not access the C pointers from multiple threads without synchronization.

### 2.3 Metal GPU Acceleration

llama.cpp uses Apple's Metal framework to offload tensor operations to the GPU. On Apple Silicon, this provides a substantial performance boost -- typically 3-5x faster token generation compared to CPU-only inference.

**How GPU offloading works:**

```
+-------------------------------------------------+
|              Model Layer Distribution            |
|                                                  |
|  Layer 0  [GPU]  ========================       |
|  Layer 1  [GPU]  ========================       |
|  Layer 2  [GPU]  ========================       |
|  ...                                             |
|  Layer N-2 [GPU] ========================       |
|  Layer N-1 [GPU] ========================       |
|  Layer N   [CPU] ========================       |
|  (embedding/output layers may stay on CPU)       |
|                                                  |
|  gpuLayers = -1  --> offload ALL layers to GPU   |
|  gpuLayers = 0   --> CPU only                    |
|  gpuLayers = 20  --> first 20 layers on GPU      |
+-------------------------------------------------+
```

**Configuration for Metal acceleration:**

```swift
/// Determines optimal GPU layer count based on available memory.
func optimalGPULayers(for modelSizeBytes: UInt64) -> Int32 {
    let device = MTLCreateSystemDefaultDevice()
    let availableVRAM = device?.recommendedMaxWorkingSetSize ?? 0

    // Reserve 512 MB for KV cache and Metal overhead
    let reservedBytes: UInt64 = 512 * 1024 * 1024
    let usableVRAM = availableVRAM > reservedBytes
        ? availableVRAM - reservedBytes
        : 0

    if modelSizeBytes <= usableVRAM {
        return -1  // Offload all layers to GPU
    } else {
        // Estimate partial offload: proportional to available VRAM
        let ratio = Double(usableVRAM) / Double(modelSizeBytes)
        let estimatedLayers = Int32(ratio * 35)  // Approximate for 3B models
        return max(estimatedLayers, 0)
    }
}
```

> :apple: **macOS-specific**: Metal GPU acceleration is available on all Apple Silicon Macs and on Intel Macs with discrete AMD GPUs. Intel Macs with integrated graphics will fall back to CPU inference via the Accelerate framework.

> :bulb: **Tip**: For best performance on Apple Silicon, set `gpuLayers = -1` to offload the entire model to the GPU. A 3B parameter Q4_K_M model requires approximately 2 GB of VRAM, well within the unified memory of any M1 or later chip.

### 2.4 Memory-Mapped GGUF Models

GGUF (GGML Universal File Format) is the model file format used by llama.cpp. HushType uses memory mapping (`mmap`) to load models, which provides:

- **Fast startup** -- The OS maps the file into virtual memory without reading the entire file into RAM upfront.
- **Shared memory** -- If multiple processes load the same model file, the OS can share the physical memory pages.
- **Low resident memory** -- Only the pages actually accessed during inference are loaded into physical RAM.

```
+----------------------------------+
|       GGUF File on Disk          |
|  +----------------------------+  |
|  | Header (metadata, vocab)   |  | <-- Read into RAM immediately
|  +----------------------------+  |
|  | Tensor Data (weights)      |  | <-- Memory-mapped (mmap)
|  |  - Layer 0 weights         |  |     Pages loaded on demand
|  |  - Layer 1 weights         |  |     by the OS virtual memory
|  |  - ...                     |  |     subsystem
|  |  - Layer N weights         |  |
|  +----------------------------+  |
+----------------------------------+
```

**Memory mapping is enabled by default:**

```swift
var modelParams = llama_model_default_params()
modelParams.use_mmap = true    // Enable memory-mapped loading
modelParams.use_mlock = false  // Do not pin pages in RAM (let OS manage)
```

> :information_source: **Info**: Setting `use_mlock = true` pins all model pages in RAM, preventing the OS from swapping them out. This reduces latency jitter but increases resident memory. Only enable this if the system has ample free RAM (model size + 2 GB headroom).

### 2.5 LlamaContext Wrapper

The complete `LlamaContext` wrapper is shown in Section 2.2. Additional helper types used throughout the LLM pipeline:

```swift
// MARK: - Error Types

/// Errors that can occur during llama.cpp operations.
public enum LlamaError: LocalizedError {
    case modelLoadFailed(path: String)
    case contextCreationFailed
    case samplerCreationFailed
    case tokenizationFailed
    case contextOverflow(tokenCount: Int, contextSize: Int)
    case decodeFailed
    case generationTimeout
    case memoryPressure(available: UInt64, required: UInt64)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let path):
            return "Failed to load model from: \(path)"
        case .contextCreationFailed:
            return "Failed to create llama context"
        case .samplerCreationFailed:
            return "Failed to initialize token sampler"
        case .tokenizationFailed:
            return "Failed to tokenize input text"
        case .contextOverflow(let count, let size):
            return "Input tokens (\(count)) exceed context window (\(size))"
        case .decodeFailed:
            return "Model decode operation failed"
        case .generationTimeout:
            return "Text generation timed out"
        case .memoryPressure(let available, let required):
            return "Insufficient memory: \(available / 1_048_576) MB available, "
                 + "\(required / 1_048_576) MB required"
        case .cancelled:
            return "Generation was cancelled"
        }
    }
}

// MARK: - Generation Options

/// Configuration options for a single generation request.
public struct GenerationOptions: Sendable {
    public var maxTokens: Int = 512
    public var temperature: Float = 0.3
    public var topP: Float = 0.9
    public var topK: Int32 = 40
    public var repeatPenalty: Float = 1.1
    public var stopSequences: [String] = []
    public var timeout: TimeInterval = 30.0

    public static let `default` = GenerationOptions()

    public static let creative = GenerationOptions(
        temperature: 0.7, topP: 0.95, topK: 50
    )

    public static let deterministic = GenerationOptions(
        temperature: 0.1, topP: 0.5, topK: 10
    )

    public init(
        maxTokens: Int = 512,
        temperature: Float = 0.3,
        topP: Float = 0.9,
        topK: Int32 = 40,
        repeatPenalty: Float = 1.1,
        stopSequences: [String] = [],
        timeout: TimeInterval = 30.0
    ) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.repeatPenalty = repeatPenalty
        self.stopSequences = stopSequences
        self.timeout = timeout
    }
}
```

---

## 3. Ollama Integration as Alternative Backend

### 3.1 When to Use Ollama vs llama.cpp

| Criteria | llama.cpp (Embedded) | Ollama (Local Server) |
|---|---|---|
| **Latency** | Lower (in-process) | Slightly higher (HTTP overhead) |
| **Setup** | Zero (bundled) | Requires Ollama install |
| **Model management** | Manual GGUF files | Ollama CLI (`ollama pull`) |
| **Model switching** | Requires reload (~2-5s) | Near-instant (Ollama caches) |
| **Memory control** | Fine-grained | Ollama manages |
| **GPU layers** | Configurable per-model | Ollama auto-configures |
| **Multiple models** | One at a time | Ollama can serve multiple |
| **Offline guarantee** | Always works | Requires Ollama daemon running |
| **Recommended for** | Default / production use | Power users, model experimentation |

> :bulb: **Tip**: Use the embedded llama.cpp backend as the default. Switch to Ollama if you frequently experiment with different models or want to share a single model instance across multiple applications.

### 3.2 Ollama Setup Instructions

**Install Ollama:**

```bash
# Install via Homebrew
brew install ollama

# Or download from https://ollama.com
# The macOS app installs the CLI and daemon automatically
```

**Pull a recommended model:**

```bash
# Pull Qwen2.5-3B-Instruct (recommended for HushType)
ollama pull qwen2.5:3b-instruct-q4_K_M

# Pull Phi-3.5-mini as an alternative
ollama pull phi3.5:3.8b-mini-instruct-q4_K_M

# Pull Llama-3.2-3B-Instruct
ollama pull llama3.2:3b-instruct-q4_K_M

# Verify the model is available
ollama list
```

**Start the Ollama server (if not running as a macOS service):**

```bash
# Start the Ollama server daemon
ollama serve

# It will listen on localhost:11434 by default
# Verify it is running:
curl http://localhost:11434/api/tags
```

> :lock: **Security**: Ollama binds to `localhost` (127.0.0.1) by default. HushType only connects to `localhost:11434`. No data leaves the machine. If Ollama is configured to listen on `0.0.0.0`, HushType will still only connect to `127.0.0.1`.

### 3.3 API Endpoints Used

HushType uses two Ollama REST API endpoints:

| Endpoint | Method | Purpose |
|---|---|---|
| `/api/tags` | GET | List available models |
| `/api/generate` | POST | Run inference (non-streaming) |
| `/api/generate` (stream) | POST | Run inference (streaming) |

**Request format for `/api/generate`:**

```json
{
  "model": "qwen2.5:3b-instruct-q4_K_M",
  "prompt": "<the full prompt text>",
  "stream": false,
  "options": {
    "temperature": 0.3,
    "top_p": 0.9,
    "top_k": 40,
    "repeat_penalty": 1.1,
    "num_predict": 512,
    "stop": ["\n\n---"]
  }
}
```

**Response format:**

```json
{
  "model": "qwen2.5:3b-instruct-q4_K_M",
  "response": "The generated text output...",
  "done": true,
  "total_duration": 1234567890,
  "load_duration": 123456789,
  "prompt_eval_count": 42,
  "eval_count": 128,
  "eval_duration": 987654321
}
```

### 3.4 OllamaClient Implementation

```swift
import Foundation

/// Client for the Ollama REST API running on localhost.
public actor OllamaClient {

    // MARK: - Types

    public struct OllamaGenerateRequest: Codable, Sendable {
        let model: String
        let prompt: String
        let stream: Bool
        let options: OllamaOptions?

        struct OllamaOptions: Codable, Sendable {
            let temperature: Float?
            let top_p: Float?
            let top_k: Int?
            let repeat_penalty: Float?
            let num_predict: Int?
            let stop: [String]?
        }
    }

    public struct OllamaGenerateResponse: Codable, Sendable {
        let model: String
        let response: String
        let done: Bool
        let total_duration: UInt64?
        let load_duration: UInt64?
        let prompt_eval_count: Int?
        let eval_count: Int?
        let eval_duration: UInt64?
    }

    public struct OllamaTagsResponse: Codable, Sendable {
        let models: [OllamaModelInfo]

        struct OllamaModelInfo: Codable, Sendable {
            let name: String
            let size: UInt64
            let digest: String
        }
    }

    public enum OllamaError: LocalizedError {
        case serverNotRunning
        case modelNotFound(String)
        case requestFailed(statusCode: Int, body: String)
        case decodingFailed
        case timeout

        public var errorDescription: String? {
            switch self {
            case .serverNotRunning:
                return "Ollama server is not running on localhost:11434"
            case .modelNotFound(let model):
                return "Model '\(model)' not found. Run: ollama pull \(model)"
            case .requestFailed(let code, let body):
                return "Ollama request failed (\(code)): \(body)"
            case .decodingFailed:
                return "Failed to decode Ollama response"
            case .timeout:
                return "Ollama request timed out"
            }
        }
    }

    // MARK: - Properties

    private let baseURL: URL
    private let session: URLSession

    // MARK: - Initialization

    public init(
        host: String = "127.0.0.1",
        port: Int = 11434,
        timeout: TimeInterval = 60.0
    ) {
        self.baseURL = URL(string: "http://\(host):\(port)")!
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Lists all models available in the local Ollama instance.
    public func listModels() async throws -> [String] {
        let url = baseURL.appendingPathComponent("api/tags")
        let (data, response) = try await performRequest(url: url)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OllamaError.serverNotRunning
        }
        let tagsResponse = try JSONDecoder().decode(
            OllamaTagsResponse.self, from: data
        )
        return tagsResponse.models.map(\.name)
    }

    /// Checks whether the Ollama server is reachable.
    public func isAvailable() async -> Bool {
        do {
            _ = try await listModels()
            return true
        } catch {
            return false
        }
    }

    /// Generates text using the specified model and prompt.
    public func generate(
        model: String,
        prompt: String,
        options: GenerationOptions = .default
    ) async throws -> String {
        let url = baseURL.appendingPathComponent("api/generate")

        let requestBody = OllamaGenerateRequest(
            model: model,
            prompt: prompt,
            stream: false,
            options: .init(
                temperature: options.temperature,
                top_p: options.topP,
                top_k: Int(options.topK),
                repeat_penalty: options.repeatPenalty,
                num_predict: options.maxTokens,
                stop: options.stopSequences.isEmpty ? nil : options.stopSequences
            )
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await performRequest(request: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaError.requestFailed(statusCode: 0, body: "No HTTP response")
        }

        switch httpResponse.statusCode {
        case 200:
            let generateResponse = try JSONDecoder().decode(
                OllamaGenerateResponse.self, from: data
            )
            return generateResponse.response
                .trimmingCharacters(in: .whitespacesAndNewlines)
        case 404:
            throw OllamaError.modelNotFound(model)
        default:
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OllamaError.requestFailed(
                statusCode: httpResponse.statusCode, body: body
            )
        }
    }

    // MARK: - Private Helpers

    private func performRequest(url: URL) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(from: url)
        } catch let error as URLError where error.code == .cannotConnectToHost {
            throw OllamaError.serverNotRunning
        } catch let error as URLError where error.code == .timedOut {
            throw OllamaError.timeout
        }
    }

    private func performRequest(request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError where error.code == .cannotConnectToHost {
            throw OllamaError.serverNotRunning
        } catch let error as URLError where error.code == .timedOut {
            throw OllamaError.timeout
        }
    }
}
```

> :warning: **Warning**: The `URLSession` is configured with `ephemeral` configuration to avoid caching any prompt data or model responses to disk. This preserves the privacy-first architecture.

---

## 4. Unified Backend Protocol

### 4.1 LLMBackend Protocol

Both llama.cpp and Ollama conform to a unified protocol, enabling transparent backend switching.

```swift
import Foundation

/// Protocol that all LLM backends must conform to.
/// Enables transparent switching between llama.cpp and Ollama.
public protocol LLMBackend: Sendable {

    /// A human-readable name for this backend (e.g., "llama.cpp", "Ollama").
    var name: String { get }

    /// Whether the backend is currently ready to serve requests.
    var isReady: Bool { get async }

    /// The name or identifier of the currently loaded model.
    var currentModel: String? { get async }

    /// Loads a model, preparing the backend for inference.
    /// - Parameter modelIdentifier: Model path (llama.cpp) or model name (Ollama).
    func loadModel(_ modelIdentifier: String) async throws

    /// Unloads the current model, freeing resources.
    func unloadModel() async

    /// Generates text from the given prompt.
    /// - Parameters:
    ///   - prompt: The full prompt string.
    ///   - options: Generation configuration.
    /// - Returns: The generated text.
    func generate(
        prompt: String,
        options: GenerationOptions
    ) async throws -> String

    /// Counts the approximate number of tokens in the given text.
    /// - Parameter text: The text to tokenize.
    /// - Returns: Approximate token count.
    func countTokens(in text: String) async -> Int
}
```

**llama.cpp backend adapter:**

```swift
/// Adapts LlamaContext to the LLMBackend protocol.
public actor LlamaCppBackend: LLMBackend {

    public let name = "llama.cpp"

    private var context: LlamaContext?
    private var loadedModelPath: String?

    public var isReady: Bool {
        context != nil
    }

    public var currentModel: String? {
        loadedModelPath
    }

    public func loadModel(_ modelIdentifier: String) async throws {
        // Unload previous model if any
        await unloadModel()

        let gpuLayers = optimalGPULayers(
            for: try fileSize(at: modelIdentifier)
        )

        context = try LlamaContext(
            modelPath: modelIdentifier,
            contextSize: 4096,
            gpuLayers: gpuLayers
        )
        loadedModelPath = modelIdentifier
    }

    public func unloadModel() async {
        context = nil
        loadedModelPath = nil
    }

    public func generate(
        prompt: String,
        options: GenerationOptions
    ) async throws -> String {
        guard let context else {
            throw LlamaError.contextCreationFailed
        }
        return try await context.generate(
            prompt: prompt,
            maxTokens: options.maxTokens,
            stopSequences: options.stopSequences
        )
    }

    public func countTokens(in text: String) async -> Int {
        guard let context else { return text.count / 4 } // rough estimate
        return context.tokenize(text, addBos: false).count
    }

    private func fileSize(at path: String) throws -> UInt64 {
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        return attrs[.size] as? UInt64 ?? 0
    }
}
```

**Ollama backend adapter:**

```swift
/// Adapts OllamaClient to the LLMBackend protocol.
public actor OllamaBackend: LLMBackend {

    public let name = "Ollama"

    private let client: OllamaClient
    private var modelName: String?

    public init(client: OllamaClient = OllamaClient()) {
        self.client = client
    }

    public var isReady: Bool {
        get async {
            await client.isAvailable() && modelName != nil
        }
    }

    public var currentModel: String? {
        modelName
    }

    public func loadModel(_ modelIdentifier: String) async throws {
        // Verify model exists in Ollama
        let models = try await client.listModels()
        guard models.contains(where: { $0.hasPrefix(modelIdentifier) }) else {
            throw OllamaClient.OllamaError.modelNotFound(modelIdentifier)
        }
        modelName = modelIdentifier
    }

    public func unloadModel() async {
        modelName = nil
    }

    public func generate(
        prompt: String,
        options: GenerationOptions
    ) async throws -> String {
        guard let modelName else {
            throw OllamaClient.OllamaError.modelNotFound("No model loaded")
        }
        return try await client.generate(
            model: modelName,
            prompt: prompt,
            options: options
        )
    }

    public func countTokens(in text: String) async -> Int {
        // Approximate: Ollama does not expose tokenization directly.
        // Use a rough heuristic of ~4 characters per token for English text.
        return max(1, text.utf8.count / 4)
    }
}
```

### 4.2 Backend Switching

```swift
import SwiftUI
import Combine

/// Manages the active LLM backend and provides a unified interface for
/// the rest of the application.
@Observable
public final class LLMService {

    // MARK: - Types

    public enum BackendType: String, Codable, CaseIterable, Sendable {
        case llamaCpp = "llama.cpp"
        case ollama = "Ollama"
    }

    public enum ServiceState: Sendable {
        case idle
        case loading
        case ready
        case processing
        case error(Error)
    }

    // MARK: - Published State

    public private(set) var state: ServiceState = .idle
    public private(set) var activeBackendType: BackendType = .llamaCpp

    // MARK: - Private

    private var activeBackend: (any LLMBackend)?
    private let llamaCppBackend = LlamaCppBackend()
    private let ollamaBackend = OllamaBackend()

    // MARK: - Backend Switching

    /// Switches to the specified backend and loads the given model.
    /// - Parameters:
    ///   - backendType: The backend to switch to.
    ///   - modelIdentifier: The model path (llama.cpp) or name (Ollama).
    public func switchBackend(
        to backendType: BackendType,
        model modelIdentifier: String
    ) async throws {
        state = .loading

        // Unload current backend
        if let current = activeBackend {
            await current.unloadModel()
        }

        // Select and load new backend
        let backend: any LLMBackend = switch backendType {
        case .llamaCpp: llamaCppBackend
        case .ollama:   ollamaBackend
        }

        do {
            try await backend.loadModel(modelIdentifier)
            activeBackend = backend
            activeBackendType = backendType
            state = .ready
        } catch {
            state = .error(error)
            throw error
        }
    }

    /// Generates text using the active backend.
    public func generate(
        prompt: String,
        options: GenerationOptions = .default
    ) async throws -> String {
        guard let backend = activeBackend else {
            throw LLMServiceError.noBackendLoaded
        }
        state = .processing
        defer { state = .ready }

        return try await backend.generate(prompt: prompt, options: options)
    }

    /// Counts tokens in the given text using the active backend.
    public func countTokens(in text: String) async -> Int {
        guard let backend = activeBackend else { return text.count / 4 }
        return await backend.countTokens(in: text)
    }
}

public enum LLMServiceError: LocalizedError {
    case noBackendLoaded

    public var errorDescription: String? {
        switch self {
        case .noBackendLoaded:
            return "No LLM backend is loaded. Please select a model first."
        }
    }
}
```

**Example: Switching backends at runtime:**

```swift
// In a ViewModel or Settings handler:
let llmService = LLMService()

// Start with llama.cpp (default)
try await llmService.switchBackend(
    to: .llamaCpp,
    model: "/Users/me/Library/Application Support/HushType/Models/qwen2.5-3b-instruct-q4_K_M.gguf"
)

// Later, switch to Ollama
try await llmService.switchBackend(
    to: .ollama,
    model: "qwen2.5:3b-instruct-q4_K_M"
)

// Generate text -- same API regardless of backend
let result = try await llmService.generate(
    prompt: "Fix this text: i went to teh store",
    options: .deterministic
)
```

---

## 5. Model Recommendations and Benchmarks

### 5.1 Recommended Models

HushType is optimized for small, fast instruction-following models in the 1-4B parameter range. These models balance quality, speed, and memory usage for real-time text processing tasks.

| Model | Parameters | Quant | File Size | Context Window |
|---|---|---|---|---|
| **Qwen2.5-3B-Instruct** (recommended) | 3.09B | Q4_K_M | 2.0 GB | 32,768 |
| **Phi-3.5-mini-instruct** | 3.82B | Q4_K_M | 2.4 GB | 128,000 |
| **Llama-3.2-3B-Instruct** | 3.21B | Q4_K_M | 2.0 GB | 8,192 |
| Qwen2.5-1.5B-Instruct (lightweight) | 1.54B | Q4_K_M | 1.0 GB | 32,768 |
| Gemma-2-2B-IT (alternative) | 2.61B | Q4_K_M | 1.7 GB | 8,192 |

### 5.2 Performance Benchmarks

Benchmarks were conducted on three representative Apple Silicon configurations. All tests used Q4_K_M quantization with all layers offloaded to GPU (`gpuLayers = -1`).

**Test methodology**: Average of 50 inference runs. Input: 150 tokens. Output: 100 tokens. Temperature: 0.3.

#### Apple Silicon M1 (8 GB Unified Memory)

| Model | Prompt Eval (tok/s) | Generation (tok/s) | Total Latency | RAM Usage | VRAM Usage |
|---|---|---|---|---|---|
| Qwen2.5-3B-Instruct | 285 | 32 | 3.8s | 2.3 GB | 2.0 GB |
| Phi-3.5-mini | 240 | 27 | 4.5s | 2.8 GB | 2.4 GB |
| Llama-3.2-3B-Instruct | 275 | 30 | 4.0s | 2.3 GB | 2.0 GB |
| Qwen2.5-1.5B-Instruct | 410 | 48 | 2.6s | 1.4 GB | 1.0 GB |

#### Apple Silicon M2 Pro (16 GB Unified Memory)

| Model | Prompt Eval (tok/s) | Generation (tok/s) | Total Latency | RAM Usage | VRAM Usage |
|---|---|---|---|---|---|
| Qwen2.5-3B-Instruct | 420 | 48 | 2.6s | 2.3 GB | 2.0 GB |
| Phi-3.5-mini | 355 | 40 | 3.1s | 2.8 GB | 2.4 GB |
| Llama-3.2-3B-Instruct | 400 | 45 | 2.8s | 2.3 GB | 2.0 GB |
| Qwen2.5-1.5B-Instruct | 620 | 72 | 1.8s | 1.4 GB | 1.0 GB |

#### Apple Silicon M3 Max (36 GB Unified Memory)

| Model | Prompt Eval (tok/s) | Generation (tok/s) | Total Latency | RAM Usage | VRAM Usage |
|---|---|---|---|---|---|
| Qwen2.5-3B-Instruct | 580 | 65 | 1.9s | 2.3 GB | 2.0 GB |
| Phi-3.5-mini | 490 | 55 | 2.3s | 2.8 GB | 2.4 GB |
| Llama-3.2-3B-Instruct | 550 | 62 | 2.1s | 2.3 GB | 2.0 GB |
| Qwen2.5-1.5B-Instruct | 850 | 95 | 1.3s | 1.4 GB | 1.0 GB |

#### Intel Mac (i7-9750H + AMD Radeon Pro 5500M, 16 GB RAM)

| Model | Prompt Eval (tok/s) | Generation (tok/s) | Total Latency | RAM Usage | VRAM Usage |
|---|---|---|---|---|---|
| Qwen2.5-3B-Instruct | 95 | 12 | 10.2s | 2.3 GB | N/A* |
| Phi-3.5-mini | 80 | 10 | 12.1s | 2.8 GB | N/A* |
| Llama-3.2-3B-Instruct | 90 | 11 | 10.8s | 2.3 GB | N/A* |
| Qwen2.5-1.5B-Instruct | 140 | 18 | 7.0s | 1.4 GB | N/A* |

> *\*Intel Macs use CPU inference via the Accelerate framework. AMD GPU support through Metal is available but yields inconsistent improvements for LLM workloads on discrete AMD GPUs.*

### 5.3 Model Selection Guidance

```
Decision Tree: Which Model Should I Use?

                    +------------------+
                    | Available RAM?   |
                    +--------+---------+
                             |
              +--------------+--------------+
              |              |              |
           < 6 GB       6-12 GB        > 12 GB
              |              |              |
              v              v              v
    +------------------+  +-----------+  +-----------+
    | Qwen2.5-1.5B    |  | Qwen2.5   |  | Phi-3.5   |
    | (lightweight,    |  | -3B       |  | -mini     |
    |  fits in 4 GB   |  | (best     |  | (largest  |
    |  total RAM)     |  |  balance)  |  |  context) |
    +------------------+  +-----------+  +-----------+
```

> :information_source: **Info**: Qwen2.5-3B-Instruct is the recommended default because it offers the best combination of output quality, speed, and memory efficiency for text post-processing tasks. It consistently outperforms Llama-3.2-3B on grammar correction and formatting tasks while using the same memory footprint.

> :bulb: **Tip**: If you need to process very long transcriptions (over 4,000 words), consider Phi-3.5-mini with its 128K context window. For most real-time dictation use, Qwen2.5-3B's 32K context is more than sufficient.

---

## 6. Prompt Template System Design

### 6.1 Template Variables

HushType's prompt template system uses variable substitution with `{variable_name}` syntax. The following variables are available in all templates:

| Variable | Description | Example Value |
|---|---|---|
| `{text}` | The raw transcription from whisper.cpp | `"i need to fix the login bug before tomorrow"` |
| `{language}` | Detected or configured language code | `"en"` |
| `{app_name}` | Name of the frontmost application | `"Xcode"` |
| `{context}` | Optional user-provided context string | `"Writing a pull request description"` |
| `{timestamp}` | Current ISO 8601 timestamp | `"2026-02-13T14:30:00Z"` |
| `{word_count}` | Approximate word count of input text | `"42"` |
| `{mode}` | Current processing mode name | `"Clean"` |

**Variable resolution order:**

1. Built-in variables (`{text}`, `{language}`, `{timestamp}`, `{word_count}`, `{mode}`)
2. Application context (`{app_name}`, `{context}`)
3. User-defined variables (from Custom mode template configuration)

### 6.2 SwiftData PromptTemplate Model

```swift
import Foundation
import SwiftData

/// Represents a reusable prompt template stored in SwiftData.
@Model
public final class PromptTemplate {

    // MARK: - Stored Properties

    /// Unique identifier for the template.
    @Attribute(.unique)
    public var id: UUID

    /// Human-readable name shown in the UI.
    public var name: String

    /// The template string with {variable} placeholders.
    public var templateBody: String

    /// Description of what this template does.
    public var templateDescription: String

    /// The processing mode this template belongs to.
    public var mode: ProcessingMode

    /// Whether this is a built-in template (cannot be deleted).
    public var isBuiltIn: Bool

    /// Display order within the mode's template list.
    public var sortOrder: Int

    /// Creation timestamp.
    public var createdAt: Date

    /// Last modified timestamp.
    public var updatedAt: Date

    /// Optional system prompt prepended to the template.
    public var systemPrompt: String?

    /// Stop sequences for this template.
    public var stopSequences: [String]

    /// Recommended temperature for this template.
    public var temperature: Float

    /// Maximum tokens to generate.
    public var maxTokens: Int

    // MARK: - Initialization

    public init(
        name: String,
        templateBody: String,
        description: String = "",
        mode: ProcessingMode = .custom,
        isBuiltIn: Bool = false,
        sortOrder: Int = 0,
        systemPrompt: String? = nil,
        stopSequences: [String] = [],
        temperature: Float = 0.3,
        maxTokens: Int = 512
    ) {
        self.id = UUID()
        self.name = name
        self.templateBody = templateBody
        self.templateDescription = description
        self.mode = mode
        self.isBuiltIn = isBuiltIn
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.updatedAt = Date()
        self.systemPrompt = systemPrompt
        self.stopSequences = stopSequences
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
}

// MARK: - Processing Mode Enum

/// All available text processing modes.
public enum ProcessingMode: String, Codable, CaseIterable, Sendable {
    case raw       = "Raw"
    case clean     = "Clean"
    case structure = "Structure"
    case prompt    = "Prompt"
    case code      = "Code"
    case custom    = "Custom"

    /// Whether this mode requires LLM processing.
    public var requiresLLM: Bool {
        switch self {
        case .raw: return false
        default:   return true
        }
    }

    /// Default generation options for this mode.
    public var defaultOptions: GenerationOptions {
        switch self {
        case .raw:
            return .default
        case .clean:
            return GenerationOptions(
                maxTokens: 512, temperature: 0.1,
                topP: 0.5, topK: 10
            )
        case .structure:
            return GenerationOptions(
                maxTokens: 768, temperature: 0.2,
                topP: 0.7, topK: 20
            )
        case .prompt:
            return GenerationOptions(
                maxTokens: 1024, temperature: 0.4,
                topP: 0.9, topK: 40
            )
        case .code:
            return GenerationOptions(
                maxTokens: 512, temperature: 0.1,
                topP: 0.5, topK: 10
            )
        case .custom:
            return .default
        }
    }
}
```

### 6.3 Built-in Templates

HushType ships with one built-in template per processing mode (except Raw, which has no template). These templates are seeded into SwiftData on first launch.

```swift
/// Seeds the default built-in prompt templates into the SwiftData store.
func seedBuiltInTemplates(context: ModelContext) {
    let builtIns: [PromptTemplate] = [
        // Clean Mode
        PromptTemplate(
            name: "Standard Clean",
            templateBody: BuiltInTemplates.clean,
            description: "Fix spelling, grammar, punctuation, and capitalization.",
            mode: .clean,
            isBuiltIn: true,
            sortOrder: 0,
            temperature: 0.1,
            maxTokens: 512
        ),
        // Structure Mode
        PromptTemplate(
            name: "Auto-Structure",
            templateBody: BuiltInTemplates.structure,
            description: "Format text as bullet lists, numbered steps, or tables.",
            mode: .structure,
            isBuiltIn: true,
            sortOrder: 0,
            temperature: 0.2,
            maxTokens: 768
        ),
        // Prompt Mode
        PromptTemplate(
            name: "Prompt Formatter",
            templateBody: BuiltInTemplates.prompt,
            description: "Reformat speech into a well-structured AI prompt.",
            mode: .prompt,
            isBuiltIn: true,
            sortOrder: 0,
            temperature: 0.4,
            maxTokens: 1024
        ),
        // Code Mode
        PromptTemplate(
            name: "Code Documentation",
            templateBody: BuiltInTemplates.code,
            description: "Format as code comments, commit messages, or docs.",
            mode: .code,
            isBuiltIn: true,
            sortOrder: 0,
            temperature: 0.1,
            maxTokens: 512
        ),
    ]

    for template in builtIns {
        context.insert(template)
    }
    try? context.save()
}
```

### 6.4 Custom Templates

Users can create, edit, and manage custom templates through the Settings UI. Custom templates support all built-in variables plus user-defined ones.

```swift
/// Resolves template variables and produces a final prompt string.
public struct TemplateEngine {

    /// Resolves all {variable} placeholders in the template body.
    /// - Parameters:
    ///   - template: The prompt template to resolve.
    ///   - text: The raw transcription text.
    ///   - context: Additional contextual information.
    /// - Returns: The fully resolved prompt string.
    public static func resolve(
        template: PromptTemplate,
        text: String,
        language: String = "en",
        appName: String = "Unknown",
        context: String = "",
        customVariables: [String: String] = [:]
    ) -> String {
        var resolved = ""

        // Prepend system prompt if present
        if let systemPrompt = template.systemPrompt, !systemPrompt.isEmpty {
            resolved += systemPrompt + "\n\n"
        }

        resolved += template.templateBody

        // Built-in variables
        let builtInVars: [String: String] = [
            "text": text,
            "language": language,
            "app_name": appName,
            "context": context,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "word_count": "\(text.split(separator: " ").count)",
            "mode": template.mode.rawValue,
        ]

        // Merge built-in with custom (custom takes precedence)
        let allVars = builtInVars.merging(customVariables) { _, custom in custom }

        // Replace all {variable} placeholders
        for (key, value) in allVars {
            resolved = resolved.replacingOccurrences(
                of: "{\(key)}",
                with: value
            )
        }

        return resolved
    }
}
```

### 6.5 Template Import and Export

Templates can be exported as JSON files for sharing and backup, and imported from JSON.

```swift
/// Handles import/export of prompt templates as JSON files.
public struct TemplateExporter {

    // MARK: - Codable DTO

    public struct TemplateDTO: Codable {
        let name: String
        let templateBody: String
        let description: String
        let mode: String
        let systemPrompt: String?
        let stopSequences: [String]
        let temperature: Float
        let maxTokens: Int
        let version: Int  // Schema version for forward compatibility
    }

    public struct TemplateBundle: Codable {
        let bundleVersion: Int
        let exportedAt: String
        let templates: [TemplateDTO]
    }

    // MARK: - Export

    /// Exports templates to a JSON file.
    public static func export(
        templates: [PromptTemplate],
        to url: URL
    ) throws {
        let dtos = templates.map { template in
            TemplateDTO(
                name: template.name,
                templateBody: template.templateBody,
                description: template.templateDescription,
                mode: template.mode.rawValue,
                systemPrompt: template.systemPrompt,
                stopSequences: template.stopSequences,
                temperature: template.temperature,
                maxTokens: template.maxTokens,
                version: 1
            )
        }
        let bundle = TemplateBundle(
            bundleVersion: 1,
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            templates: dtos
        )
        let data = try JSONEncoder.prettyPrinted.encode(bundle)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Import

    /// Imports templates from a JSON file.
    /// - Returns: Array of PromptTemplate objects (not yet inserted into context).
    public static func importTemplates(
        from url: URL
    ) throws -> [PromptTemplate] {
        let data = try Data(contentsOf: url)
        let bundle = try JSONDecoder().decode(TemplateBundle.self, from: data)

        return bundle.templates.compactMap { dto in
            guard let mode = ProcessingMode(rawValue: dto.mode) else { return nil }
            return PromptTemplate(
                name: dto.name,
                templateBody: dto.templateBody,
                description: dto.description,
                mode: mode,
                isBuiltIn: false,
                systemPrompt: dto.systemPrompt,
                stopSequences: dto.stopSequences,
                temperature: dto.temperature,
                maxTokens: dto.maxTokens
            )
        }
    }
}

private extension JSONEncoder {
    static let prettyPrinted: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
```

> :information_source: **Info**: Exported template bundles include a `bundleVersion` field for forward compatibility. Future versions of HushType can migrate older template formats automatically.

---

## 7. Processing Mode Implementations

### 7.1 Raw Mode

**Purpose**: Pass-through mode. No LLM processing. The raw transcription from whisper.cpp is injected directly into the target application.

**When to use**: When you want exact, unmodified speech-to-text output, or when LLM processing is disabled or unavailable.

**Template**: None (no LLM call is made).

```swift
// Raw mode implementation -- trivially returns the input text.
func processRaw(text: String) -> String {
    return text
}
```

```
Input:  "i went to the store and bought some milk and bread and eggs"
Output: "i went to the store and bought some milk and bread and eggs"
```

> :information_source: **Info**: Raw mode is the automatic fallback if the LLM backend is not loaded or encounters an error. See [Section 10: Error Handling and Fallback](#10-error-handling-and-fallback).

### 7.2 Clean Mode

**Purpose**: Fix spelling, grammar, punctuation, and capitalization while preserving the original meaning and tone.

**Actual prompt template:**

```
You are a text editor. Fix the spelling, grammar, punctuation, and capitalization of the following transcribed speech. Preserve the original meaning, tone, and intent exactly. Do not add, remove, or rephrase content. Do not add explanations or commentary. Output only the corrected text.

Language: {language}

Input text:
{text}

Corrected text:
```

**Generation options**: Temperature 0.1, Top-P 0.5, Top-K 10, Max tokens 512.

**Example:**

```
Input:  "i went to teh store and buoght some milk and bread and egs"
Output: "I went to the store and bought some milk, bread, and eggs."
```

```
Input:  "so basically what im trying to say is that the feature isnt working right
         and we need to look into it before the release"
Output: "So basically, what I'm trying to say is that the feature isn't working right,
         and we need to look into it before the release."
```

### 7.3 Structure Mode

**Purpose**: Reorganize transcribed speech into structured formats: bullet lists, numbered steps, tables, or headings.

**Actual prompt template:**

```
You are a text formatter. Reorganize the following transcribed speech into a well-structured format. Use the most appropriate structure based on the content:
- If the text describes steps or a process, use a numbered list.
- If the text lists items or ideas, use bullet points.
- If the text contains comparisons or data, use a markdown table.
- If the text covers multiple topics, use headings with bullet points.

Preserve all information from the original text. Do not add new information or commentary. Output only the structured text.

Language: {language}

Input text:
{text}

Structured output:
```

**Generation options**: Temperature 0.2, Top-P 0.7, Top-K 20, Max tokens 768.

**Example:**

```
Input:  "so for the project we need to first set up the database then create
         the api endpoints and after that build the frontend and finally
         deploy to production also we need to write tests"

Output: "1. Set up the database
         2. Create the API endpoints
         3. Build the frontend
         4. Write tests
         5. Deploy to production"
```

```
Input:  "the pros of using swift are type safety good performance and nice
         syntax but the cons are that it only works on apple platforms and
         the compile times can be slow"

Output: "## Swift: Pros and Cons

         **Pros:**
         - Type safety
         - Good performance
         - Nice syntax

         **Cons:**
         - Only works on Apple platforms
         - Compile times can be slow"
```

### 7.4 Prompt Mode

**Purpose**: Transform spoken instructions into well-structured AI prompts suitable for use with ChatGPT, Claude, or similar tools.

**Actual prompt template:**

```
You are a prompt engineer. Transform the following transcribed speech into a well-structured, clear AI prompt. The output should be a prompt that a user can paste directly into an AI assistant (like ChatGPT or Claude).

Follow these guidelines:
- Start with a clear role or task description.
- Include specific constraints and requirements mentioned in the speech.
- Organize multi-part requests into numbered sections.
- Add formatting instructions if the speech implies a specific output format.
- Preserve all technical details and requirements from the original speech.

Do not execute the prompt. Only output the formatted prompt text. Do not add meta-commentary.

Application context: {app_name}
Additional context: {context}

Transcribed speech:
{text}

Formatted prompt:
```

**Generation options**: Temperature 0.4, Top-P 0.9, Top-K 40, Max tokens 1024.

**Example:**

```
Input:  "i need you to help me write a python function that takes a list of
         numbers and returns the top three largest ones and it should handle
         edge cases like empty lists and lists with fewer than three items
         and make sure its well documented"

Output: "Write a Python function with the following specifications:

         1. **Function**: Accept a list of numbers as input and return the
            top 3 largest values.

         2. **Edge cases to handle**:
            - Empty list (return an empty list or raise a descriptive error)
            - List with fewer than 3 items (return all items, sorted descending)

         3. **Requirements**:
            - Include a complete docstring with parameters, return type, and examples
            - Add inline comments for complex logic
            - Follow PEP 8 style conventions"
```

### 7.5 Code Mode

**Purpose**: Format transcribed speech into code-related artifacts: code comments, commit messages, documentation, or inline annotations.

**Actual prompt template:**

```
You are a developer assistant. Transform the following transcribed speech into well-formatted code documentation. Based on the content, output the most appropriate format:

- If describing a change or fix: format as a Git commit message (subject line + body).
- If describing functionality: format as a code documentation comment (using the appropriate doc-comment syntax for the language context).
- If describing a bug or issue: format as a structured bug report.
- If describing a task: format as a TODO comment or task description.

Use concise, technical language. Follow conventional formatting standards.

Application: {app_name}
Context: {context}
Language: {language}

Transcribed speech:
{text}

Formatted output:
```

**Generation options**: Temperature 0.1, Top-P 0.5, Top-K 10, Max tokens 512.

**Example (commit message):**

```
Input:  "fixed the bug where the login screen would crash if the user
         entered a really long password because we werent validating
         the input length before sending it to the api"

Output: "fix: prevent crash on login with oversized password input

         Validate password length before sending to the authentication API.
         Previously, passwords exceeding 256 characters caused a buffer
         overflow in the API serialization layer, crashing the login screen.

         - Add input length validation (max 256 chars) to LoginViewController
         - Show user-facing error message for passwords exceeding the limit
         - Add unit test for boundary password lengths"
```

**Example (code comment):**

```
Input:  "this function calculates the total price including tax and it
         takes the subtotal and tax rate as parameters and returns the
         final amount rounded to two decimal places"

Output: "/// Calculates the total price including tax.
         ///
         /// - Parameters:
         ///   - subtotal: The pre-tax subtotal amount.
         ///   - taxRate: The tax rate as a decimal (e.g., 0.08 for 8%).
         /// - Returns: The total price rounded to two decimal places."
```

### 7.6 Custom Mode

**Purpose**: User-defined templates. Users create their own prompt templates using the available variables.

**Template**: Defined by the user. Example custom template:

```
Translate the following text from {language} to formal business English.
Maintain professional tone and corporate terminology.

Context: {context}

Original text:
{text}

Translation:
```

**Custom templates can reference any built-in variable and any user-defined variables.**

### 7.7 Processing Mode Selection and Execution

The `TextProcessor` class orchestrates the full pipeline from raw transcription through mode-specific LLM processing.

```swift
import Foundation
import SwiftData

/// Orchestrates the text processing pipeline.
/// Receives raw transcription, applies the selected processing mode,
/// and returns the final processed text.
public actor TextProcessor {

    // MARK: - Dependencies

    private let llmService: LLMService
    private let templateEngine: TemplateEngine.Type
    private let modelContext: ModelContext

    // MARK: - State

    public private(set) var currentMode: ProcessingMode = .clean

    // MARK: - Initialization

    public init(
        llmService: LLMService,
        modelContext: ModelContext
    ) {
        self.llmService = llmService
        self.templateEngine = TemplateEngine.self
        self.modelContext = modelContext
    }

    // MARK: - Mode Selection

    /// Sets the active processing mode.
    public func setMode(_ mode: ProcessingMode) {
        currentMode = mode
    }

    // MARK: - Processing

    /// Processes raw transcription text through the active mode's pipeline.
    /// - Parameters:
    ///   - rawText: The raw transcription from whisper.cpp.
    ///   - language: The detected language code.
    ///   - appName: The frontmost application name.
    ///   - context: Optional user-provided context.
    /// - Returns: The processed text, or raw text if processing fails.
    public func process(
        rawText: String,
        language: String = "en",
        appName: String = "Unknown",
        context: String = ""
    ) async -> ProcessingResult {
        // Raw mode: no LLM needed
        guard currentMode.requiresLLM else {
            return ProcessingResult(
                text: rawText,
                mode: .raw,
                processingTime: 0,
                tokensUsed: 0,
                didFallback: false
            )
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            // Fetch the active template for the current mode
            let template = try fetchActiveTemplate(for: currentMode)

            // Resolve template variables
            let prompt = templateEngine.resolve(
                template: template,
                text: rawText,
                language: language,
                appName: appName,
                context: context
            )

            // Check token budget
            let tokenCount = await llmService.countTokens(in: prompt)
            guard tokenCount < 3500 else {
                // Prompt is too long; truncate input text and retry
                let truncatedText = truncateToFit(
                    text: rawText,
                    maxTokens: 2500,
                    currentTokens: tokenCount
                )
                let truncatedPrompt = templateEngine.resolve(
                    template: template,
                    text: truncatedText,
                    language: language,
                    appName: appName,
                    context: context
                )
                let result = try await llmService.generate(
                    prompt: truncatedPrompt,
                    options: currentMode.defaultOptions
                )
                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                return ProcessingResult(
                    text: result,
                    mode: currentMode,
                    processingTime: elapsed,
                    tokensUsed: tokenCount,
                    didFallback: false
                )
            }

            // Run inference
            let result = try await llmService.generate(
                prompt: prompt,
                options: currentMode.defaultOptions
            )

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            return ProcessingResult(
                text: result,
                mode: currentMode,
                processingTime: elapsed,
                tokensUsed: tokenCount,
                didFallback: false
            )

        } catch {
            // Fallback: return raw text
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            return ProcessingResult(
                text: rawText,
                mode: currentMode,
                processingTime: elapsed,
                tokensUsed: 0,
                didFallback: true,
                fallbackReason: error.localizedDescription
            )
        }
    }

    // MARK: - Private Helpers

    private func fetchActiveTemplate(
        for mode: ProcessingMode
    ) throws -> PromptTemplate {
        let descriptor = FetchDescriptor<PromptTemplate>(
            predicate: #Predicate { $0.mode == mode },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        let templates = try modelContext.fetch(descriptor)
        guard let template = templates.first else {
            throw ProcessingError.noTemplateFound(mode: mode)
        }
        return template
    }

    private func truncateToFit(
        text: String,
        maxTokens: Int,
        currentTokens: Int
    ) -> String {
        let ratio = Double(maxTokens) / Double(currentTokens)
        let targetCharCount = Int(Double(text.count) * ratio * 0.9)
        if targetCharCount < text.count {
            let index = text.index(
                text.startIndex,
                offsetBy: targetCharCount,
                limitedBy: text.endIndex
            ) ?? text.endIndex
            return String(text[..<index]) + "..."
        }
        return text
    }
}

// MARK: - Supporting Types

public struct ProcessingResult: Sendable {
    public let text: String
    public let mode: ProcessingMode
    public let processingTime: TimeInterval
    public let tokensUsed: Int
    public let didFallback: Bool
    public var fallbackReason: String?
}

public enum ProcessingError: LocalizedError {
    case noTemplateFound(mode: ProcessingMode)

    public var errorDescription: String? {
        switch self {
        case .noTemplateFound(let mode):
            return "No prompt template found for mode: \(mode.rawValue)"
        }
    }
}
```

---

## 8. Token Management and Context Window Handling

### 8.1 Context Window Sizes

Each model has a maximum context window that limits the total number of tokens (prompt + generated output) that can be processed in a single inference call.

| Model | Max Context Window | Recommended Max for HushType | Prompt Budget | Output Budget |
|---|---|---|---|---|
| Qwen2.5-3B-Instruct | 32,768 | 4,096 | 3,500 | 596 |
| Phi-3.5-mini | 128,000 | 4,096 | 3,500 | 596 |
| Llama-3.2-3B-Instruct | 8,192 | 4,096 | 3,500 | 596 |
| Qwen2.5-1.5B-Instruct | 32,768 | 2,048 | 1,700 | 348 |

> :warning: **Warning**: While models like Phi-3.5-mini support up to 128K tokens, HushType defaults to a 4,096 context window to optimize latency and memory usage. Larger context windows require proportionally more memory for the KV cache. Users can increase this in settings if needed.

**Context window allocation:**

```
+------------------------------------------------------------+
|                  Context Window (4,096 tokens)              |
|                                                             |
|  +------------------------+-----------+------------------+  |
|  | System Prompt + Template| Input Text| Generated Output |  |
|  | (~200 tokens)          | (variable) | (up to 512 tok)  |  |
|  +------------------------+-----------+------------------+  |
|                                                             |
|  <-------- Prompt Budget (3,500) -------->|<-- Output -->|  |
|                                            (596 max)        |
+------------------------------------------------------------+
```

### 8.2 Token Counting

```swift
/// Utility for managing token budgets within the context window.
public struct TokenBudget {

    /// The total context window size in tokens.
    public let contextSize: Int

    /// Tokens reserved for the system prompt and template chrome.
    public let templateOverhead: Int

    /// Maximum tokens for generated output.
    public let maxOutputTokens: Int

    /// Tokens available for the input text.
    public var inputBudget: Int {
        contextSize - templateOverhead - maxOutputTokens
    }

    public init(
        contextSize: Int = 4096,
        templateOverhead: Int = 200,
        maxOutputTokens: Int = 512
    ) {
        self.contextSize = contextSize
        self.templateOverhead = templateOverhead
        self.maxOutputTokens = maxOutputTokens
    }

    /// Checks whether the given text fits within the input budget.
    /// - Parameters:
    ///   - text: The input text.
    ///   - tokenCounter: A closure that counts tokens in a string.
    /// - Returns: Whether the text fits, and the token count.
    public func fits(
        text: String,
        tokenCounter: (String) async -> Int
    ) async -> (fits: Bool, tokenCount: Int) {
        let count = await tokenCounter(text)
        return (count <= inputBudget, count)
    }

    /// Describes the current budget allocation.
    public var description: String {
        """
        Context: \(contextSize) tokens
        Template overhead: \(templateOverhead) tokens
        Input budget: \(inputBudget) tokens
        Output budget: \(maxOutputTokens) tokens
        """
    }
}
```

### 8.3 Truncation Strategies

When input text exceeds the token budget, HushType applies one of three truncation strategies:

```swift
/// Strategies for truncating text that exceeds the token budget.
public enum TruncationStrategy: String, Codable, CaseIterable, Sendable {
    /// Keep the end of the text (most recent speech). Default for dictation.
    case keepEnd = "Keep End"

    /// Keep the beginning of the text.
    case keepBeginning = "Keep Beginning"

    /// Keep both the beginning and end, removing the middle.
    case keepEdges = "Keep Edges"
}

extension TruncationStrategy {

    /// Truncates the given text to approximately the target token count.
    /// - Parameters:
    ///   - text: The text to truncate.
    ///   - targetTokens: The target number of tokens.
    ///   - currentTokens: The current number of tokens in the text.
    /// - Returns: The truncated text with an ellipsis marker.
    public func truncate(
        text: String,
        targetTokens: Int,
        currentTokens: Int
    ) -> String {
        guard currentTokens > targetTokens else { return text }

        let ratio = Double(targetTokens) / Double(currentTokens)
        let targetChars = Int(Double(text.count) * ratio * 0.9) // 10% safety margin

        switch self {
        case .keepEnd:
            let startIndex = text.index(
                text.endIndex,
                offsetBy: -targetChars,
                limitedBy: text.startIndex
            ) ?? text.startIndex
            return "..." + text[startIndex...]

        case .keepBeginning:
            let endIndex = text.index(
                text.startIndex,
                offsetBy: targetChars,
                limitedBy: text.endIndex
            ) ?? text.endIndex
            return text[..<endIndex] + "..."

        case .keepEdges:
            let halfChars = targetChars / 2
            let frontEnd = text.index(
                text.startIndex,
                offsetBy: halfChars,
                limitedBy: text.endIndex
            ) ?? text.endIndex
            let backStart = text.index(
                text.endIndex,
                offsetBy: -halfChars,
                limitedBy: text.startIndex
            ) ?? text.startIndex
            return text[..<frontEnd] + "\n...[truncated]...\n" + text[backStart...]
        }
    }
}
```

> :bulb: **Tip**: The default truncation strategy is `keepEnd`, which preserves the most recently dictated text. This works best for real-time dictation where the latest content is most relevant. Switch to `keepBeginning` when processing complete documents.

---

## 9. Latency Optimization Strategies

Minimizing latency is critical for HushType because the user is waiting for their speech to be transformed and injected into the active application. The goal is sub-3-second total pipeline time from end-of-speech to text injection.

```
Latency Budget (Target: < 3 seconds total)
+-------+-------+-------+-------+-------+
| ASR   | Mode  | Templ | LLM   | Inject|
| 0.5s  | 0.01s | 0.01s | 2.0s  | 0.1s  |
+-------+-------+-------+-------+-------+
         <---- Optimization focus ---->
```

### 9.1 Model Preloading

Load the LLM model at application startup so it is ready for the first inference request.

```swift
/// Preloads the LLM model at application startup.
/// Called from the AppDelegate or App struct's initialization.
@MainActor
final class AppBootstrap {

    static func preloadLLM(llmService: LLMService, settings: AppSettings) {
        Task.detached(priority: .userInitiated) {
            do {
                try await llmService.switchBackend(
                    to: settings.preferredBackend,
                    model: settings.activeModelPath
                )
            } catch {
                // Log but do not crash -- LLM will be loaded on first use
                // or fallback to raw mode.
                Logger.llm.error("Failed to preload LLM: \(error.localizedDescription)")
            }
        }
    }
}
```

**Warm-up inference:**

```swift
/// Runs a minimal inference to warm up the Metal pipeline and JIT caches.
func warmUp(backend: any LLMBackend) async {
    _ = try? await backend.generate(
        prompt: "Hello",
        options: GenerationOptions(maxTokens: 1, temperature: 0)
    )
}
```

> :information_source: **Info**: The first inference after model load is typically 2-3x slower than subsequent inferences because Metal shaders must be compiled and cached. The warm-up call eliminates this cold-start penalty.

### 9.2 Speculative Decoding

Speculative decoding uses a smaller "draft" model to generate candidate tokens, which are then verified by the main model in a single batch. This can improve generation speed by 1.5-2x.

```swift
/// Configuration for speculative decoding.
/// Uses a smaller draft model to speed up token generation.
struct SpeculativeDecodingConfig {
    /// Path to the smaller draft model (e.g., Qwen2.5-0.5B).
    let draftModelPath: String

    /// Number of draft tokens to generate before verification.
    let draftTokenCount: Int  // Typically 4-8

    /// Whether speculative decoding is enabled.
    let isEnabled: Bool

    static let `default` = SpeculativeDecodingConfig(
        draftModelPath: "",
        draftTokenCount: 6,
        isEnabled: false  // Disabled by default; requires a second model
    )
}
```

> :warning: **Warning**: Speculative decoding requires loading a second (smaller) model alongside the main model, which increases memory usage by approximately 500 MB - 1 GB. Only enable this on machines with 16 GB or more of unified memory.

### 9.3 Batch Size Tuning

The batch size controls how many tokens are processed in a single forward pass during prompt evaluation. Larger batch sizes improve prompt processing speed but use more memory.

| Batch Size | Prompt Eval Speed | Memory Overhead | Recommended For |
|---|---|---|---|
| 128 | Baseline | Minimal | Machines with < 8 GB RAM |
| 256 | ~1.3x | Low | Default for 8 GB machines |
| 512 | ~1.8x | Moderate | Default for 16 GB+ machines |
| 1024 | ~2.2x | High | 32 GB+ machines, long prompts |
| 2048 | ~2.5x | Very high | 64 GB+ machines only |

```swift
/// Determines the optimal batch size based on available system memory.
func optimalBatchSize() -> Int32 {
    let totalMemory = ProcessInfo.processInfo.physicalMemory
    switch totalMemory {
    case ..<(8 * 1_073_741_824):       // < 8 GB
        return 256
    case ..<(16 * 1_073_741_824):      // < 16 GB
        return 512
    case ..<(32 * 1_073_741_824):      // < 32 GB
        return 1024
    default:                            // >= 32 GB
        return 2048
    }
}
```

### 9.4 Metal GPU Layer Offloading

As described in [Section 2.3](#23-metal-gpu-acceleration), offloading model layers to the Metal GPU is the single most impactful optimization. The key configuration points:

```swift
/// Comprehensive GPU offloading configuration.
struct MetalConfig {
    /// Number of layers to offload (-1 = all).
    var gpuLayers: Int32 = -1

    /// Whether to use Metal for matrix multiplications.
    var useMetalMatMul: Bool = true

    /// Metal buffer size for tensor allocations (bytes).
    var metalBufferSize: UInt64 = 512 * 1024 * 1024  // 512 MB

    /// Whether to use float16 for Metal operations (faster, slight quality loss).
    var useFloat16: Bool = true

    /// Auto-configure based on the system's Metal device capabilities.
    static func autoDetect() -> MetalConfig {
        var config = MetalConfig()

        guard let device = MTLCreateSystemDefaultDevice() else {
            // No Metal device available (very old Intel Mac)
            config.gpuLayers = 0
            config.useMetalMatMul = false
            return config
        }

        let vram = device.recommendedMaxWorkingSetSize

        // Apple Silicon: use all GPU layers
        if device.supportsFamily(.apple7) {  // M1 and later
            config.gpuLayers = -1
            config.useFloat16 = true
        }
        // AMD discrete GPU (Intel Macs)
        else if vram > 2 * 1_073_741_824 {  // > 2 GB VRAM
            config.gpuLayers = 20  // Partial offload
            config.useFloat16 = false  // AMD compatibility
        }
        // Integrated graphics or insufficient VRAM
        else {
            config.gpuLayers = 0
            config.useMetalMatMul = false
        }

        return config
    }
}
```

> :apple: **macOS-specific**: On Apple Silicon, the unified memory architecture means that GPU and CPU share the same physical memory. Setting `gpuLayers = -1` does not "use more memory" -- it routes computations through the GPU cores instead of the CPU cores, which is substantially faster for matrix multiplications.

---

## 10. Error Handling and Fallback

### 10.1 Error Types

The LLM pipeline defines a comprehensive error hierarchy:

```swift
/// All errors that can occur in the LLM processing pipeline.
public enum LLMPipelineError: LocalizedError {

    // Backend errors
    case backendNotLoaded
    case backendUnavailable(backend: String, reason: String)

    // Model errors
    case modelNotFound(path: String)
    case modelCorrupted(path: String)
    case modelIncompatible(model: String, reason: String)

    // Inference errors
    case generationFailed(underlying: Error)
    case generationTimeout(seconds: TimeInterval)
    case emptyOutput

    // Resource errors
    case insufficientMemory(available: UInt64, required: UInt64)
    case insufficientDiskSpace(available: UInt64, required: UInt64)

    // Template errors
    case templateNotFound(mode: ProcessingMode)
    case templateResolutionFailed(variable: String)

    public var errorDescription: String? {
        switch self {
        case .backendNotLoaded:
            return "No LLM backend is loaded"
        case .backendUnavailable(let backend, let reason):
            return "\(backend) backend unavailable: \(reason)"
        case .modelNotFound(let path):
            return "Model file not found: \(path)"
        case .modelCorrupted(let path):
            return "Model file is corrupted: \(path)"
        case .modelIncompatible(let model, let reason):
            return "Model '\(model)' is incompatible: \(reason)"
        case .generationFailed(let underlying):
            return "Text generation failed: \(underlying.localizedDescription)"
        case .generationTimeout(let seconds):
            return "Text generation timed out after \(Int(seconds))s"
        case .emptyOutput:
            return "Model produced empty output"
        case .insufficientMemory(let available, let required):
            let avail = available / 1_048_576
            let req = required / 1_048_576
            return "Insufficient memory: \(avail) MB available, \(req) MB required"
        case .insufficientDiskSpace(let available, let required):
            let avail = available / 1_048_576
            let req = required / 1_048_576
            return "Insufficient disk space: \(avail) MB available, \(req) MB required"
        case .templateNotFound(let mode):
            return "No template found for mode: \(mode.rawValue)"
        case .templateResolutionFailed(let variable):
            return "Failed to resolve template variable: {\(variable)}"
        }
    }
}
```

### 10.2 Fallback Chain

When the LLM pipeline encounters an error, HushType follows a defined fallback chain to ensure the user always gets some output:

```
Fallback Chain:

   LLM Generation
        |
        | failure
        v
   Retry with lower temperature (0.1)
        |
        | failure
        v
   Switch to alternate backend (if available)
   (e.g., llama.cpp fails -> try Ollama)
        |
        | failure
        v
   Switch to smaller model (if available)
   (e.g., 3B model fails -> try 1.5B model)
        |
        | failure
        v
   Inject raw text (Raw mode fallback)
        |
        | always succeeds
        v
   User sees unprocessed transcription
```

**Implementation:**

```swift
/// Executes the LLM processing pipeline with full fallback chain.
public actor ResilientTextProcessor {

    private let primaryBackend: any LLMBackend
    private let fallbackBackend: (any LLMBackend)?
    private let fallbackModelPath: String?
    private let maxRetries: Int = 2
    private let retryDelay: TimeInterval = 0.5

    public init(
        primaryBackend: any LLMBackend,
        fallbackBackend: (any LLMBackend)? = nil,
        fallbackModelPath: String? = nil
    ) {
        self.primaryBackend = primaryBackend
        self.fallbackBackend = fallbackBackend
        self.fallbackModelPath = fallbackModelPath
    }

    /// Processes text with full fallback chain.
    /// Guaranteed to return a result (worst case: raw text).
    public func process(
        prompt: String,
        rawText: String,
        options: GenerationOptions
    ) async -> FallbackResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Step 1: Try primary backend
        do {
            let result = try await withTimeout(options.timeout) {
                try await self.primaryBackend.generate(
                    prompt: prompt, options: options
                )
            }
            if !result.isEmpty {
                return FallbackResult(
                    text: result,
                    source: .primary,
                    elapsed: CFAbsoluteTimeGetCurrent() - startTime
                )
            }
        } catch {
            Logger.llm.warning(
                "Primary backend failed: \(error.localizedDescription)"
            )
        }

        // Step 2: Retry with conservative settings
        do {
            var conservativeOptions = options
            conservativeOptions.temperature = 0.1
            conservativeOptions.maxTokens = min(options.maxTokens, 256)

            let result = try await withTimeout(options.timeout) {
                try await self.primaryBackend.generate(
                    prompt: prompt, options: conservativeOptions
                )
            }
            if !result.isEmpty {
                return FallbackResult(
                    text: result,
                    source: .primaryRetry,
                    elapsed: CFAbsoluteTimeGetCurrent() - startTime
                )
            }
        } catch {
            Logger.llm.warning(
                "Primary retry failed: \(error.localizedDescription)"
            )
        }

        // Step 3: Try fallback backend (e.g., Ollama if llama.cpp failed)
        if let fallback = fallbackBackend, await fallback.isReady {
            do {
                let result = try await withTimeout(options.timeout) {
                    try await fallback.generate(
                        prompt: prompt, options: options
                    )
                }
                if !result.isEmpty {
                    return FallbackResult(
                        text: result,
                        source: .fallbackBackend,
                        elapsed: CFAbsoluteTimeGetCurrent() - startTime
                    )
                }
            } catch {
                Logger.llm.warning(
                    "Fallback backend failed: \(error.localizedDescription)"
                )
            }
        }

        // Step 4: Final fallback -- return raw text
        Logger.llm.error(
            "All LLM backends failed. Falling back to raw text."
        )
        return FallbackResult(
            text: rawText,
            source: .rawFallback,
            elapsed: CFAbsoluteTimeGetCurrent() - startTime
        )
    }

    // MARK: - Timeout Helper

    private func withTimeout<T: Sendable>(
        _ timeout: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw LLMPipelineError.generationTimeout(seconds: timeout)
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

// MARK: - Fallback Result

public struct FallbackResult: Sendable {

    public enum Source: String, Sendable {
        case primary         = "Primary backend"
        case primaryRetry    = "Primary backend (retry)"
        case fallbackBackend = "Fallback backend"
        case rawFallback     = "Raw text (no LLM)"
    }

    public let text: String
    public let source: Source
    public let elapsed: TimeInterval

    public var didFallback: Bool {
        source != .primary
    }
}
```

### 10.3 Timeout Handling

Each processing mode has a configurable timeout. If the LLM does not produce output within the timeout, the pipeline falls back.

| Processing Mode | Default Timeout | Max Timeout (User Configurable) |
|---|---|---|
| Clean | 15s | 60s |
| Structure | 20s | 60s |
| Prompt | 25s | 90s |
| Code | 15s | 60s |
| Custom | 30s | 120s |

> :warning: **Warning**: If inference consistently times out, this usually indicates the model is too large for the available hardware. Consider switching to a smaller model (e.g., Qwen2.5-1.5B) or enabling more GPU layers.

### 10.4 Memory Pressure Handling

HushType monitors system memory pressure and takes protective action to prevent the system from becoming unresponsive.

```swift
import Foundation
import os

/// Monitors system memory pressure and adjusts LLM behavior accordingly.
final class MemoryPressureMonitor {

    private let source: DispatchSourceMemoryPressure
    private let llmService: LLMService

    enum PressureLevel: Sendable {
        case normal
        case warning
        case critical
    }

    private(set) var currentLevel: PressureLevel = .normal

    init(llmService: LLMService) {
        self.llmService = llmService
        self.source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let event = self.source.data
            if event.contains(.critical) {
                self.handleCriticalPressure()
            } else if event.contains(.warning) {
                self.handleWarningPressure()
            }
        }
        source.activate()
    }

    deinit {
        source.cancel()
    }

    private func handleWarningPressure() {
        currentLevel = .warning
        Logger.llm.warning("Memory pressure: WARNING. Reducing LLM batch size.")
        // Notify the LLM service to reduce batch size and context window
        Task {
            // Reduce context window to conserve memory
            // This is a signal, not a direct operation, because the
            // LlamaContext would need to be recreated.
        }
    }

    private func handleCriticalPressure() {
        currentLevel = .critical
        Logger.llm.error("Memory pressure: CRITICAL. Unloading LLM model.")
        Task {
            // Unload the model to free memory immediately
            await llmService.unloadCurrentModel()
            // Future requests will fall back to raw text mode
        }
    }
}
```

> :x: **Error**: If you see "Memory pressure: CRITICAL. Unloading LLM model." in the logs, HushType has unloaded the LLM to prevent system instability. All text processing will fall back to Raw mode until the user manually reloads a model or memory pressure subsides. Consider using a smaller model or closing other memory-intensive applications.

---

## 11. LLM Processing Pipeline Architecture

This section provides the complete end-to-end view of the LLM processing pipeline.

```
+====================================================================+
||                  HushType LLM Processing Pipeline                ||
+====================================================================+

  User speaks into microphone
        |
        v
  +------------------+
  | AVAudioEngine    |     (see SPEECH_RECOGNITION.md)
  | Audio Capture    |
  +--------+---------+
           |
           v
  +------------------+
  | whisper.cpp      |     (see SPEECH_RECOGNITION.md)
  | Transcription    |
  +--------+---------+
           |
           | Raw text: "i need to fix the login bug"
           v
  +------------------+
  | TextProcessor    |
  | .process()       |
  +--------+---------+
           |
           | Check processing mode
           v
  +------------------+     +------------------+
  | Mode == .raw?    |---->| Return raw text   |---> Inject
  +--------+---------+ yes +------------------+
           | no
           v
  +------------------+
  | Fetch template   |
  | from SwiftData   |
  +--------+---------+
           |
           v
  +------------------+
  | TemplateEngine   |
  | .resolve()       |
  | - {text}         |
  | - {language}     |
  | - {app_name}     |
  | - {context}      |
  +--------+---------+
           |
           | Fully resolved prompt string
           v
  +------------------+
  | TokenBudget      |
  | .fits()?         |
  +--------+---------+
           |
     +-----+-----+
     | fits | too long
     v           v
     |    +------------------+
     |    | TruncationStrategy|
     |    | .truncate()       |
     |    +--------+---------+
     |             |
     +------+------+
            |
            v
  +------------------+
  | LLMBackend       |
  | .generate()      |
  +--------+---------+
           |
     +-----+-----+
     | ok   | error
     v           v
     |    +------------------+
     |    | FallbackChain    |
     |    | 1. Retry         |
     |    | 2. Alt backend   |
     |    | 3. Raw fallback  |
     |    +--------+---------+
     |             |
     +------+------+
            |
            v
  +------------------+
  | Post-process     |
  | - Trim whitespace|
  | - Validate output|
  +--------+---------+
           |
           v
  +------------------+
  | CGEvent Injection|     (see ../architecture/ARCHITECTURE.md)
  | into active app  |
  +------------------+
```

**Complete pipeline timing breakdown (typical, M2 Pro, Qwen2.5-3B):**

| Stage | Duration | Cumulative |
|---|---|---|
| Audio capture (last buffer) | 0ms | 0ms |
| whisper.cpp transcription | ~500ms | ~500ms |
| Mode selection | <1ms | ~500ms |
| Template resolution | <1ms | ~500ms |
| Token counting | ~5ms | ~505ms |
| LLM prompt evaluation | ~350ms | ~855ms |
| LLM token generation (100 tokens) | ~2,100ms | ~2,955ms |
| Post-processing | <1ms | ~2,956ms |
| CGEvent injection | ~50ms | ~3,006ms |
| **Total** | | **~3.0s** |

> :white_check_mark: **Success**: On Apple Silicon with a 3B model, the complete pipeline from end-of-speech to text injection is consistently under 3.5 seconds for typical dictation lengths (10-50 words).

---

## 12. Configuration Reference

All LLM-related configuration is stored in `UserDefaults` (for simple preferences) and SwiftData (for templates and model metadata).

| Setting | Key | Default | Range |
|---|---|---|---|
| Active backend | `llm.backend` | `llamaCpp` | `llamaCpp`, `ollama` |
| Model path (llama.cpp) | `llm.modelPath` | (bundled model) | Valid file path |
| Model name (Ollama) | `llm.ollamaModel` | `qwen2.5:3b-instruct-q4_K_M` | Valid Ollama model |
| Context window | `llm.contextSize` | `4096` | 512 - 131072 |
| GPU layers | `llm.gpuLayers` | `-1` (all) | -1 to model layer count |
| Batch size | `llm.batchSize` | `512` | 64 - 2048 |
| Processing mode | `llm.mode` | `clean` | See `ProcessingMode` |
| Temperature | `llm.temperature` | `0.3` | 0.0 - 2.0 |
| Top-P | `llm.topP` | `0.9` | 0.0 - 1.0 |
| Top-K | `llm.topK` | `40` | 1 - 100 |
| Max output tokens | `llm.maxTokens` | `512` | 1 - 4096 |
| Timeout (seconds) | `llm.timeout` | `30` | 5 - 120 |
| Truncation strategy | `llm.truncation` | `keepEnd` | See `TruncationStrategy` |
| Speculative decoding | `llm.speculative` | `false` | `true`, `false` |
| Memory lock (mlock) | `llm.useMlock` | `false` | `true`, `false` |
| Ollama host | `llm.ollamaHost` | `127.0.0.1` | Valid hostname/IP |
| Ollama port | `llm.ollamaPort` | `11434` | 1024 - 65535 |

---

## 13. Related Documentation

| Document | Description |
|---|---|
| [Architecture Overview](../architecture/ARCHITECTURE.md) | System architecture, module boundaries, data flow |
| [Speech Recognition](SPEECH_RECOGNITION.md) | whisper.cpp integration, audio capture, transcription pipeline |
| [Model Management](MODEL_MANAGEMENT.md) | Model download, storage, updates, GGUF file handling |
| [API Documentation](../api/API_DOCUMENTATION.md) | Internal API reference for all modules |
| [Tech Stack](../architecture/TECH_STACK.md) | Full technology stack and dependency details |
| [Security](../security/SECURITY.md) | Security model, privacy guarantees, threat analysis |
| [Permissions](PERMISSIONS.md) | macOS permissions (microphone, accessibility) |
| [Database Schema](../architecture/DATABASE_SCHEMA.md) | SwiftData models and persistence layer |

---

*This document is part of the HushType project documentation. HushType is licensed under GPL-3.0. For more information, see the [LICENSE](../../LICENSE) file in the repository root.*
