Last Updated: 2026-02-13

# Performance Optimization

VaulType runs two ML models simultaneously — whisper.cpp for speech recognition and llama.cpp for text refinement — entirely on-device with zero network dependency. This document defines every optimization strategy, tuning parameter, and monitoring technique required to deliver real-time performance across all supported Apple hardware.

---

## Table of Contents

- [Performance Philosophy](#performance-philosophy)
- [Apple Silicon Metal Acceleration](#apple-silicon-metal-acceleration)
  - [Metal Performance Shaders Overview](#metal-performance-shaders-overview)
  - [GPU Layer Allocation](#gpu-layer-allocation)
  - [Optimal GPU/CPU Split](#optimal-gpucpu-split)
  - [Chip Generation Differences](#chip-generation-differences)
  - [Unified Memory Advantages](#unified-memory-advantages)
  - [Metal Configuration in Code](#metal-configuration-in-code)
- [Model Quantization](#model-quantization)
  - [LLM Quantization Formats](#llm-quantization-formats)
  - [Whisper Model Sizes](#whisper-model-sizes)
  - [Quality vs Speed vs Memory Tradeoffs](#quality-vs-speed-vs-memory-tradeoffs)
  - [Quantization Selection Strategy](#quantization-selection-strategy)
- [Memory Management for Dual-Model Operation](#memory-management-for-dual-model-operation)
  - [Memory Layout Architecture](#memory-layout-architecture)
  - [Peak Memory Calculations](#peak-memory-calculations)
  - [Memory Mapping Strategies](#memory-mapping-strategies)
  - [Model Swapping](#model-swapping)
  - [When to Unload Models](#when-to-unload-models)
  - [Memory Pressure Monitoring](#memory-pressure-monitoring)
- [Audio Buffer Optimization](#audio-buffer-optimization)
  - [Buffer Size Selection](#buffer-size-selection)
  - [Sample Rate Conversion](#sample-rate-conversion)
  - [Ring Buffer Implementation](#ring-buffer-implementation)
  - [Latency vs Reliability Tradeoffs](#latency-vs-reliability-tradeoffs)
- [Lazy Model Loading Strategies](#lazy-model-loading-strategies)
  - [Load on First Use](#load-on-first-use)
  - [Background Preloading](#background-preloading)
  - [Warm-Up Inference](#warm-up-inference)
  - [Model Priority Queue](#model-priority-queue)
  - [Model Preloading Service](#model-preloading-service)
- [Battery-Aware Performance Throttling](#battery-aware-performance-throttling)
  - [Power Source Detection](#power-source-detection)
  - [Battery-Aware Model Selection](#battery-aware-model-selection)
  - [Preloading on Battery](#preloading-on-battery)
  - [Power Profile Configuration](#power-profile-configuration)
- [Thermal Management](#thermal-management)
  - [Thermal State Monitoring](#thermal-state-monitoring)
  - [Adaptive Throttling](#adaptive-throttling)
  - [Reducing GPU Layers Under Thermal Pressure](#reducing-gpu-layers-under-thermal-pressure)
  - [Thermal Throttling in Code](#thermal-throttling-in-code)
- [Benchmarking Methodology and Tools](#benchmarking-methodology-and-tools)
  - [Instruments Profiling](#instruments-profiling)
  - [Custom Benchmarking Harness](#custom-benchmarking-harness)
  - [Key Metrics to Track](#key-metrics-to-track)
  - [Regression Detection](#regression-detection)
  - [Performance Benchmark Tables](#performance-benchmark-tables)
- [Pipeline Optimization](#pipeline-optimization)
  - [End-to-End Pipeline](#end-to-end-pipeline)
  - [Concurrent Execution Strategy](#concurrent-execution-strategy)
- [Related Documentation](#related-documentation)

---

## Performance Philosophy

VaulType's performance strategy rests on three pillars:

| Pillar | Meaning |
|---|---|
| **Latency** | The user must perceive transcription and refinement as near-instantaneous — under 500 ms total for typical utterances |
| **Efficiency** | Dual-model inference must coexist with normal system operation; VaulType should never make the Mac feel sluggish |
| **Adaptability** | Performance tuning reacts to hardware capability, power source, thermal state, and memory pressure in real time |

> 💡 **Design Principle**: VaulType always degrades gracefully. When resources are constrained, it reduces quality (smaller models, fewer GPU layers) rather than increasing latency or dropping audio.

---

## Apple Silicon Metal Acceleration

Apple Silicon's unified memory architecture is the foundation of VaulType's performance story. Both whisper.cpp and llama.cpp support Metal acceleration, which offloads matrix multiplications and attention computations to the GPU cores.

### Metal Performance Shaders Overview

Metal Performance Shaders (MPS) provide optimized GPU kernels for common ML operations. Both whisper.cpp and llama.cpp use Metal compute shaders for:

- **Matrix multiplication** (GEMM/GEMV) — the dominant operation in transformer inference
- **Softmax** — attention score normalization
- **Layer normalization** — pre/post-attention normalization
- **Element-wise operations** — GELU, SiLU activations

On Apple Silicon, these operations run on the GPU cores while the CPU handles orchestration, memory management, and non-parallelizable work.

```
┌──────────────────────────────────────────────────────────────────┐
│                    Apple Silicon SoC                              │
│                                                                  │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────┐   │
│  │  CPU Cores   │    │  GPU Cores   │    │  Neural Engine   │   │
│  │  (E + P)     │    │  (Metal)     │    │  (ANE)           │   │
│  │              │    │              │    │  [Not used by     │   │
│  │  Orchestrate │    │  GEMM/GEMV   │    │   whisper.cpp/   │   │
│  │  Audio I/O   │    │  Attention   │    │   llama.cpp]     │   │
│  │  Token decode│    │  LayerNorm   │    │                  │   │
│  └──────┬───────┘    └──────┬───────┘    └──────────────────┘   │
│         │                   │                                    │
│         └─────────┬─────────┘                                    │
│                   ▼                                              │
│  ┌──────────────────────────────────┐                            │
│  │      Unified Memory (LPDDR)      │                            │
│  │                                  │                            │
│  │  Model weights, KV cache,        │                            │
│  │  audio buffers, compute buffers  │                            │
│  │  — all shared, zero-copy         │                            │
│  └──────────────────────────────────┘                            │
└──────────────────────────────────────────────────────────────────┘
```

> 🍎 **Apple Silicon Advantage**: Unlike discrete GPU systems, there is no PCIe bus transfer between CPU and GPU memory. Model weights loaded once are accessible to both CPU and GPU compute — zero-copy.

### GPU Layer Allocation

Both whisper.cpp and llama.cpp allow specifying how many transformer layers run on the GPU versus the CPU. More GPU layers mean faster inference but higher GPU memory pressure.

**whisper.cpp GPU layers:**

| Whisper Model | Total Layers | Recommended GPU Layers | Notes |
|---|---|---|---|
| tiny | 4 | 4 (all) | Fits entirely on GPU for all hardware |
| base | 6 | 6 (all) | Fits entirely on GPU for all hardware |
| small | 12 | 12 (all) | Fits entirely on GPU for 16 GB+ |
| medium | 24 | 24 (all) | Fits entirely on GPU for 16 GB+ |
| large-v3 | 32 | 32 (all) | Requires 16 GB+; consider 24 on 8 GB |

**llama.cpp GPU layers (for ~7B parameter LLM):**

| Quantization | Total Layers | 8 GB RAM | 16 GB RAM | 24 GB+ RAM |
|---|---|---|---|---|
| Q4_0 | 32 | 20-24 | 32 (all) | 32 (all) |
| Q4_K_M | 32 | 18-22 | 32 (all) | 32 (all) |
| Q5_K_M | 32 | 14-18 | 32 (all) | 32 (all) |
| Q8_0 | 32 | 8-12 | 28-32 | 32 (all) |
| F16 | 32 | N/A | 16-20 | 32 (all) |

> ⚠️ **Warning**: These layer counts assume dual-model operation (Whisper + LLM loaded simultaneously). If only one model is active, more GPU layers can be allocated.

### Optimal GPU/CPU Split

The optimal split depends on available memory after accounting for system overhead and the other model. The general rule:

```
Available GPU Memory = Total RAM - System Overhead - Other Model - KV Cache Reserve

System Overhead:
  macOS base              ~3-4 GB
  VaulType app overhead   ~200 MB
  Audio pipeline          ~50 MB

Example (16 GB M2 MacBook Air):
  16 GB - 4 GB (system) - 1.5 GB (Whisper medium) - 0.2 GB (app) = ~10.3 GB for LLM
  A Q4_K_M 7B model needs ~4.1 GB → all 32 layers fit on GPU
```

> 💡 **Tip**: Always leave at least 2 GB of headroom beyond calculated needs. macOS memory compression helps, but sustained pressure causes jank in the entire system.

### Chip Generation Differences

| Feature | M1 | M2 | M3 | M4 |
|---|---|---|---|---|
| GPU Cores (base) | 7-8 | 8-10 | 8-10 | 10 |
| GPU Cores (Pro) | 14-16 | 16-19 | 14-18 | 16-20 |
| GPU Cores (Max) | 24-32 | 30-38 | 30-40 | 32-40 |
| Memory Bandwidth | 68.25 GB/s | 100 GB/s | 100 GB/s | 120 GB/s |
| Memory Bandwidth (Pro) | 200 GB/s | 200 GB/s | 150-200 GB/s | 273 GB/s |
| Max Unified Memory | 16 GB | 24 GB | 128 GB | 64 GB |
| Max Unified Memory (Max/Ultra) | 64/128 GB | 96/192 GB | 128/192 GB | 128/256 GB |
| Metal Feature Set | Metal 3 | Metal 3 | Metal 3+ | Metal 3+ |
| Dynamic Caching | No | No | Yes | Yes |
| Mesh Shading | No | No | Yes | Yes |
| Hardware Ray Tracing | No | No | Yes | Yes |
| Relative Perf (base, 7B Q4) | 1.0x | 1.3x | 1.4x | 1.6x |

**Key observations for VaulType:**

- **M3/M4 Dynamic Caching** reduces GPU memory waste from shader register allocation, leaving more memory for model weights
- **Memory bandwidth** is the primary bottleneck for LLM inference (memory-bound workload). M4 Pro's 273 GB/s provides the biggest leap
- **M1 base (8 GB)** is the minimum viable target — use Whisper small + Q4_0 3B LLM

> ℹ️ **Intel Support**: VaulType supports Intel Macs but without Metal acceleration. CPU-only inference uses Accelerate.framework (BLAS). Expect 3-5x slower inference compared to equivalent-era Apple Silicon.

### Unified Memory Advantages

```
┌─────────────────────────────────────────────────────────┐
│              Traditional Discrete GPU                    │
│                                                         │
│  ┌──────────┐   PCIe Bus    ┌──────────┐               │
│  │ CPU RAM  │ ────────────► │ GPU VRAM │               │
│  │          │   (slow copy) │          │               │
│  │ Model    │               │ Model    │               │
│  │ (copy 1) │               │ (copy 2) │               │
│  └──────────┘               └──────────┘               │
│                                                         │
│  Total memory used: 2x model size                       │
│  Transfer latency: milliseconds per layer               │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│              Apple Silicon Unified Memory                 │
│                                                         │
│  ┌──────────────────────────────────────┐               │
│  │         Unified Memory Pool          │               │
│  │                                      │               │
│  │  ┌──────────┐                        │               │
│  │  │ Model    │◄──── CPU reads here    │               │
│  │  │ (1 copy) │◄──── GPU reads here    │               │
│  │  └──────────┘                        │               │
│  │                                      │               │
│  │  Zero-copy, zero-latency switching   │               │
│  └──────────────────────────────────────┘               │
│                                                         │
│  Total memory used: 1x model size                       │
│  Transfer latency: zero                                 │
└─────────────────────────────────────────────────────────┘
```

This is why Apple Silicon can run larger models than discrete GPUs with the same nominal memory: no duplication, no transfer overhead.

### Metal Configuration in Code

The following shows how VaulType configures GPU layer counts for both inference engines:

```swift
import Foundation

// MARK: - Metal GPU Configuration

/// Configuration for Metal GPU layer allocation across both ML models.
/// Determines how many transformer layers run on GPU vs CPU.
struct MetalGPUConfiguration {
    let whisperGPULayers: Int32
    let llmGPULayers: Int32
    let useMetalAcceleration: Bool

    /// Total system RAM in bytes
    static var totalSystemMemory: UInt64 {
        ProcessInfo.processInfo.physicalMemory
    }

    /// Total system RAM in gigabytes
    static var totalSystemMemoryGB: Double {
        Double(totalSystemMemory) / (1024 * 1024 * 1024)
    }

    /// Estimated available memory after system overhead (in GB)
    static var estimatedAvailableMemoryGB: Double {
        let systemOverhead: Double = 4.0  // macOS + background apps
        let appOverhead: Double = 0.25     // VaulType base footprint
        return max(totalSystemMemoryGB - systemOverhead - appOverhead, 1.0)
    }

    /// Determines if Metal acceleration is available on this system
    static var isMetalAvailable: Bool {
        #if arch(arm64)
        return true
        #else
        // Intel Macs: check for Metal-capable GPU
        guard let device = MTLCreateSystemDefaultDevice() else { return false }
        return device.supportsFamily(.apple1)
        #endif
    }

    /// Creates an optimal configuration for the current hardware
    /// - Parameters:
    ///   - whisperModelSize: Size category of the Whisper model
    ///   - llmQuantization: Quantization format of the LLM
    ///   - llmParameterCount: Approximate parameter count in billions
    /// - Returns: Optimal Metal GPU configuration
    static func optimal(
        whisperModelSize: WhisperModelSize,
        llmQuantization: LLMQuantization,
        llmParameterCount: Double
    ) -> MetalGPUConfiguration {
        guard isMetalAvailable else {
            return MetalGPUConfiguration(
                whisperGPULayers: 0,
                llmGPULayers: 0,
                useMetalAcceleration: false
            )
        }

        let availableGB = estimatedAvailableMemoryGB
        let whisperMemoryGB = whisperModelSize.estimatedMemoryGB
        let remainingForLLM = availableGB - whisperMemoryGB - 2.0  // 2 GB headroom

        // Whisper: always put all layers on GPU if memory allows
        let whisperLayers: Int32 = if availableGB >= whisperMemoryGB + 1.0 {
            whisperModelSize.totalLayers
        } else {
            Int32(Double(whisperModelSize.totalLayers) * 0.5)
        }

        // LLM: calculate how many layers fit in remaining memory
        let llmTotalLayers: Int32 = 32  // typical for 7B models
        let memoryPerLayer = llmQuantization.estimatedMemoryPerLayerGB(
            parameterCount: llmParameterCount
        )
        let maxLLMLayers = Int32(remainingForLLM / memoryPerLayer)
        let llmLayers = min(max(maxLLMLayers, 0), llmTotalLayers)

        return MetalGPUConfiguration(
            whisperGPULayers: whisperLayers,
            llmGPULayers: llmLayers,
            useMetalAcceleration: true
        )
    }
}

// MARK: - Supporting Types

enum WhisperModelSize: String, CaseIterable {
    case tiny, base, small, medium, large

    var totalLayers: Int32 {
        switch self {
        case .tiny:   return 4
        case .base:   return 6
        case .small:  return 12
        case .medium: return 24
        case .large:  return 32
        }
    }

    var estimatedMemoryGB: Double {
        switch self {
        case .tiny:   return 0.08
        case .base:   return 0.15
        case .small:  return 0.50
        case .medium: return 1.50
        case .large:  return 3.00
        }
    }
}

enum LLMQuantization: String, CaseIterable {
    case q4_0 = "Q4_0"
    case q4_k_m = "Q4_K_M"
    case q5_k_m = "Q5_K_M"
    case q8_0 = "Q8_0"
    case f16 = "F16"

    /// Bits per parameter for this quantization format
    var bitsPerParameter: Double {
        switch self {
        case .q4_0:   return 4.5   // 4-bit with some overhead
        case .q4_k_m: return 4.8   // k-quant mixed precision
        case .q5_k_m: return 5.5   // k-quant mixed precision
        case .q8_0:   return 8.5   // 8-bit with scale factors
        case .f16:    return 16.0  // half precision
        }
    }

    /// Estimated memory per transformer layer in GB for a given parameter count
    func estimatedMemoryPerLayerGB(parameterCount: Double) -> Double {
        let totalBits = parameterCount * 1_000_000_000 * bitsPerParameter
        let totalBytes = totalBits / 8.0
        let totalGB = totalBytes / (1024 * 1024 * 1024)
        return totalGB / 32.0  // assume 32 layers
    }
}
```

> ✅ **Best Practice**: Always call `MetalGPUConfiguration.optimal(...)` at launch and again whenever power source or thermal state changes. Store the configuration in `PerformanceManager` and propagate to both inference engines.

---

## Model Quantization

Quantization reduces model size and inference time by representing weights with fewer bits. The tradeoff is always quality vs speed vs memory.

### LLM Quantization Formats

| Format | Bits/Weight | Description | Quality Impact |
|---|---|---|---|
| **F16** | 16 | Half-precision float. Baseline quality. | None (reference) |
| **Q8_0** | 8.5 | 8-bit with block scaling. Near-lossless. | Negligible (<1% perplexity increase) |
| **Q5_K_M** | 5.5 | 5-bit k-quant, mixed precision attention layers. | Minor (1-2% perplexity increase) |
| **Q4_K_M** | 4.8 | 4-bit k-quant, mixed precision. Best quality/size ratio. | Moderate (2-4% perplexity increase) |
| **Q4_0** | 4.5 | Basic 4-bit. Fast but lower quality. | Notable (4-6% perplexity increase) |

> 💡 **VaulType Default**: Q4_K_M is the default for LLM text refinement. For VaulType's use case (grammar correction, punctuation, formatting), the quality difference between Q4_K_M and F16 is imperceptible in practice.

### Whisper Model Sizes

| Model | Parameters | Disk Size | Memory (loaded) | English WER | Multilingual WER |
|---|---|---|---|---|---|
| tiny | 39 M | 75 MB | ~80 MB | 7.7% | 12.0% |
| base | 74 M | 142 MB | ~150 MB | 5.8% | 9.8% |
| small | 244 M | 466 MB | ~500 MB | 4.2% | 7.6% |
| medium | 769 M | 1.5 GB | ~1.5 GB | 3.5% | 6.5% |
| large-v3 | 1550 M | 3.1 GB | ~3.0 GB | 2.9% | 5.2% |

> ℹ️ **WER = Word Error Rate**: Lower is better. These are approximate values on LibriSpeech/Common Voice benchmarks. Real-world performance varies with accent, background noise, and microphone quality.

### Quality vs Speed vs Memory Tradeoffs

**7B LLM — Text Refinement Speed (tokens/sec on Apple Silicon base chips):**

| Quantization | M1 (8 GB) | M2 (8 GB) | M3 (8 GB) | M4 (16 GB) | Memory |
|---|---|---|---|---|---|
| Q4_0 | 18 t/s | 24 t/s | 26 t/s | 32 t/s | 3.8 GB |
| Q4_K_M | 16 t/s | 22 t/s | 24 t/s | 30 t/s | 4.1 GB |
| Q5_K_M | 13 t/s | 18 t/s | 20 t/s | 26 t/s | 4.8 GB |
| Q8_0 | 8 t/s | 12 t/s | 14 t/s | 20 t/s | 7.2 GB |
| F16 | N/A | N/A | N/A | 12 t/s | 13.5 GB |

**Whisper — Real-Time Factor (RTF, lower is faster):**

| Model | M1 | M2 | M3 | M4 | Memory |
|---|---|---|---|---|---|
| tiny | 0.05 | 0.04 | 0.03 | 0.02 | 80 MB |
| base | 0.08 | 0.06 | 0.05 | 0.04 | 150 MB |
| small | 0.15 | 0.11 | 0.09 | 0.07 | 500 MB |
| medium | 0.35 | 0.25 | 0.20 | 0.15 | 1.5 GB |
| large-v3 | 0.70 | 0.50 | 0.40 | 0.30 | 3.0 GB |

> ℹ️ **Real-Time Factor (RTF)**: An RTF of 0.25 means 1 second of audio is processed in 0.25 seconds. Values below 1.0 are faster than real time.

### Quantization Selection Strategy

```swift
/// Selects the best quantization level based on available memory and power state
struct QuantizationSelector {
    static func recommendedLLMQuantization(
        availableMemoryGB: Double,
        isOnBattery: Bool,
        thermalState: ProcessInfo.ThermalState
    ) -> LLMQuantization {
        // Under thermal pressure or battery: prefer smaller models
        if thermalState == .critical || thermalState == .serious {
            return .q4_0
        }

        if isOnBattery {
            // On battery, favor speed over quality
            if availableMemoryGB >= 5.0 {
                return .q4_k_m
            } else {
                return .q4_0
            }
        }

        // On power: use highest quality that fits
        switch availableMemoryGB {
        case 14.0...:  return .f16
        case 8.0...:   return .q8_0
        case 5.5...:   return .q5_k_m
        case 4.5...:   return .q4_k_m
        default:        return .q4_0
        }
    }

    static func recommendedWhisperModel(
        availableMemoryGB: Double,
        isOnBattery: Bool,
        thermalState: ProcessInfo.ThermalState
    ) -> WhisperModelSize {
        if thermalState == .critical {
            return .tiny
        }
        if thermalState == .serious {
            return .base
        }

        if isOnBattery {
            if availableMemoryGB >= 2.0 {
                return .small
            } else {
                return .base
            }
        }

        // On power
        switch availableMemoryGB {
        case 5.0...:  return .large
        case 3.0...:  return .medium
        case 1.0...:  return .small
        case 0.5...:  return .base
        default:       return .tiny
        }
    }
}
```

---

## Memory Management for Dual-Model Operation

Running Whisper and an LLM simultaneously is VaulType's most demanding resource requirement. This section covers how to manage memory for both models.

### Memory Layout Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                  System Unified Memory (16 GB example)        │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐    │
│  │  macOS + System Services              ~3.5 GB        │    │
│  ├──────────────────────────────────────────────────────┤    │
│  │  VaulType App                                        │    │
│  │  ┌─────────────────────────────────────────────┐     │    │
│  │  │  App Binary + Runtime          ~50 MB       │     │    │
│  │  ├─────────────────────────────────────────────┤     │    │
│  │  │  SwiftUI View Hierarchy        ~30 MB       │     │    │
│  │  ├─────────────────────────────────────────────┤     │    │
│  │  │  Audio Pipeline (buffers)      ~20 MB       │     │    │
│  │  ├─────────────────────────────────────────────┤     │    │
│  │  │  Whisper Model (medium)        ~1.5 GB      │     │    │
│  │  │  ├── Encoder weights                        │     │    │
│  │  │  ├── Decoder weights                        │     │    │
│  │  │  └── Mel filterbank + vocab                 │     │    │
│  │  ├─────────────────────────────────────────────┤     │    │
│  │  │  Whisper Compute Buffers       ~200 MB      │     │    │
│  │  │  ├── Mel spectrogram                        │     │    │
│  │  │  ├── Encoder output                         │     │    │
│  │  │  └── Decoder KV cache                       │     │    │
│  │  ├─────────────────────────────────────────────┤     │    │
│  │  │  LLM Model (Q4_K_M 7B)        ~4.1 GB      │     │    │
│  │  │  ├── Embedding layer                        │     │    │
│  │  │  ├── 32 transformer layers                  │     │    │
│  │  │  └── Output head                            │     │    │
│  │  ├─────────────────────────────────────────────┤     │    │
│  │  │  LLM KV Cache                 ~500 MB       │     │    │
│  │  │  (context-dependent)                        │     │    │
│  │  ├─────────────────────────────────────────────┤     │    │
│  │  │  Metal Compute Buffers         ~200 MB      │     │    │
│  │  └─────────────────────────────────────────────┘     │    │
│  │  Total VaulType:                  ~6.6 GB            │    │
│  ├──────────────────────────────────────────────────────┤    │
│  │  Free / Available                 ~5.9 GB            │    │
│  └──────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────┘
```

### Peak Memory Calculations

Calculate peak memory for any hardware/model combination:

```swift
/// Calculates peak memory usage for a given model configuration
struct MemoryCalculator {
    struct MemoryBudget {
        let whisperModelMB: Double
        let whisperComputeMB: Double
        let llmModelMB: Double
        let llmKVCacheMB: Double
        let metalBuffersMB: Double
        let appOverheadMB: Double

        var totalMB: Double {
            whisperModelMB + whisperComputeMB +
            llmModelMB + llmKVCacheMB +
            metalBuffersMB + appOverheadMB
        }

        var totalGB: Double { totalMB / 1024.0 }

        /// Whether this configuration fits in the given memory with headroom
        func fits(inGB availableGB: Double, headroomGB: Double = 2.0) -> Bool {
            totalGB + headroomGB <= availableGB
        }
    }

    static func calculateBudget(
        whisperModel: WhisperModelSize,
        llmQuantization: LLMQuantization,
        llmParameterBillions: Double,
        contextLength: Int = 2048
    ) -> MemoryBudget {
        let whisperModelMB = whisperModel.estimatedMemoryGB * 1024

        // Whisper compute buffers: mel spectrogram + encoder output + KV cache
        let whisperComputeMB: Double = switch whisperModel {
        case .tiny:   50.0
        case .base:   80.0
        case .small:  120.0
        case .medium: 200.0
        case .large:  350.0
        }

        // LLM model size
        let llmBits = llmParameterBillions * 1e9 * llmQuantization.bitsPerParameter
        let llmModelMB = llmBits / 8.0 / (1024 * 1024)

        // LLM KV cache: 2 (K+V) * layers * heads * head_dim * context * 2 bytes(fp16)
        // Simplified: roughly 1 MB per 100 context tokens per billion parameters at fp16
        let llmKVCacheMB = llmParameterBillions * Double(contextLength) / 100.0

        // Metal compute buffers (scratch space for GPU operations)
        let metalBuffersMB: Double = 200.0

        let appOverheadMB: Double = 100.0

        return MemoryBudget(
            whisperModelMB: whisperModelMB,
            whisperComputeMB: whisperComputeMB,
            llmModelMB: llmModelMB,
            llmKVCacheMB: llmKVCacheMB,
            metalBuffersMB: metalBuffersMB,
            appOverheadMB: appOverheadMB
        )
    }
}
```

**Reference budgets for common configurations:**

| Configuration | Whisper | LLM | Peak Memory | Min RAM |
|---|---|---|---|---|
| Minimal | tiny (80 MB) | Q4_0 3B (1.7 GB) | ~2.3 GB | 8 GB |
| Balanced | small (500 MB) | Q4_K_M 7B (4.1 GB) | ~5.2 GB | 8 GB |
| Quality | medium (1.5 GB) | Q4_K_M 7B (4.1 GB) | ~6.6 GB | 16 GB |
| Maximum | large-v3 (3.0 GB) | Q5_K_M 7B (4.8 GB) | ~8.8 GB | 16 GB |
| Ultra | large-v3 (3.0 GB) | Q8_0 13B (13.5 GB) | ~17.5 GB | 32 GB |

### Memory Mapping Strategies

Both whisper.cpp and llama.cpp support `mmap` for loading model files. This is critical for VaulType:

```swift
/// Memory mapping strategy for model loading
enum ModelMappingStrategy {
    /// mmap the model file. Pages are loaded on demand by the kernel.
    /// Pro: Fast initial load, memory is shared with page cache
    /// Con: First inference may stall as pages fault in
    case memoryMapped

    /// Read entire model into allocated memory.
    /// Pro: Predictable performance after load completes
    /// Con: Slower initial load, higher peak memory
    case fullyLoaded

    /// mmap + mlock to prevent paging
    /// Pro: Fast load + guaranteed in-memory after first pass
    /// Con: Requires elevated memory; system may refuse mlock
    case memoryMappedLocked

    var llmLoadFlag: Bool {
        switch self {
        case .memoryMapped:       return true   // use_mmap = true
        case .fullyLoaded:        return false  // use_mmap = false
        case .memoryMappedLocked: return true   // use_mmap = true, use_mlock = true
        }
    }

    /// Recommended strategy for current conditions
    static func recommended(
        availableMemoryGB: Double,
        modelSizeGB: Double,
        isFirstLaunch: Bool
    ) -> ModelMappingStrategy {
        // If plenty of memory, use mmap + mlock for best performance
        if availableMemoryGB > modelSizeGB * 2.5 {
            return .memoryMappedLocked
        }

        // If memory is adequate, plain mmap is fine
        if availableMemoryGB > modelSizeGB * 1.5 {
            return .memoryMapped
        }

        // Tight on memory: fully loaded gives more predictable behavior
        // (system can reclaim mmap pages under pressure, causing stalls)
        return .fullyLoaded
    }
}
```

> ⚠️ **mmap Pitfall**: Under memory pressure, macOS can evict mmap'd pages. The next access then triggers a page fault and disk read, causing inference stalls. For real-time transcription, prefer `fullyLoaded` or `memoryMappedLocked` when memory allows.

### Model Swapping

When memory is insufficient for both models simultaneously, VaulType can swap models:

```swift
/// Manages loading and unloading of models to fit within memory constraints
actor ModelSwapManager {
    enum ActiveModel {
        case whisperOnly
        case llmOnly
        case both
        case none
    }

    private(set) var activeState: ActiveModel = .none
    private var whisperContext: OpaquePointer?  // whisper_context*
    private var llamaModel: OpaquePointer?      // llama_model*

    /// Transition to a new active model state, unloading as needed
    func transition(to target: ActiveModel) async throws {
        guard target != activeState else { return }

        switch (activeState, target) {
        case (_, .none):
            unloadWhisper()
            unloadLLM()

        case (.none, .whisperOnly), (.llmOnly, .whisperOnly):
            unloadLLM()
            try await loadWhisper()

        case (.none, .llmOnly), (.whisperOnly, .llmOnly):
            unloadWhisper()
            try await loadLLM()

        case (_, .both):
            if whisperContext == nil { try await loadWhisper() }
            if llamaModel == nil { try await loadLLM() }

        default:
            break
        }

        activeState = target
    }

    private func loadWhisper() async throws {
        // Implementation calls whisper_init_from_file_with_params()
        // with Metal-enabled parameters
    }

    private func loadLLM() async throws {
        // Implementation calls llama_load_model_from_file()
        // with Metal GPU layer configuration
    }

    private func unloadWhisper() {
        guard let ctx = whisperContext else { return }
        // whisper_free(ctx)
        whisperContext = nil
    }

    private func unloadLLM() {
        guard let model = llamaModel else { return }
        // llama_free_model(model)
        llamaModel = nil
    }
}
```

### When to Unload Models

| Condition | Action | Rationale |
|---|---|---|
| Memory pressure warning (`.warning`) | Unload LLM if idle > 30s | LLM is larger and less immediately needed |
| Memory pressure critical (`.critical`) | Unload both models | System stability takes priority |
| App enters background | Unload LLM after 60s | Background apps should minimize footprint |
| No transcription for 5 min | Unload Whisper | Can reload in ~1-2 seconds when needed |
| No LLM use for 5 min | Unload LLM | Can reload in ~2-4 seconds when needed |
| Thermal state `.critical` | Unload LLM | Reduce thermal generation |
| Battery below 10% | Unload LLM, use Whisper only | Preserve remaining battery |

### Memory Pressure Monitoring

```swift
import Foundation

/// Monitors system memory pressure and triggers adaptive responses
final class MemoryPressureMonitor: @unchecked Sendable {
    static let shared = MemoryPressureMonitor()

    enum PressureLevel: Int, Comparable {
        case nominal = 0
        case warning = 1
        case critical = 2

        static func < (lhs: PressureLevel, rhs: PressureLevel) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    private let source: DispatchSourceMemoryPressure
    private var currentLevel: PressureLevel = .nominal
    private var observers: [(PressureLevel) -> Void] = []

    private init() {
        source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical, .normal],
            queue: .global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let event = self.source.data

            let newLevel: PressureLevel
            if event.contains(.critical) {
                newLevel = .critical
            } else if event.contains(.warning) {
                newLevel = .warning
            } else {
                newLevel = .nominal
            }

            if newLevel != self.currentLevel {
                self.currentLevel = newLevel
                self.notifyObservers(newLevel)
            }
        }

        source.resume()
    }

    deinit {
        source.cancel()
    }

    /// Register a callback for memory pressure changes
    func observe(_ handler: @escaping (PressureLevel) -> Void) {
        observers.append(handler)
    }

    /// Current memory usage of this process in bytes
    static var currentProcessMemory: UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(
                to: integer_t.self,
                capacity: Int(count)
            ) { rawPtr in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    rawPtr,
                    &count
                )
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
    }

    /// Current process memory in megabytes
    static var currentProcessMemoryMB: Double {
        Double(currentProcessMemory) / (1024 * 1024)
    }

    /// Available system memory in bytes (approximate)
    static var availableSystemMemory: UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) { statsPtr in
            statsPtr.withMemoryRebound(
                to: integer_t.self,
                capacity: Int(count)
            ) { rawPtr in
                host_statistics64(
                    mach_host_self(),
                    HOST_VM_INFO64,
                    rawPtr,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else { return 0 }

        let pageSize = UInt64(vm_kernel_page_size)
        let free = UInt64(stats.free_count) * pageSize
        let inactive = UInt64(stats.inactive_count) * pageSize
        // macOS "available" ≈ free + inactive (purgeable/compressor pages can be reclaimed)
        return free + inactive
    }

    private func notifyObservers(_ level: PressureLevel) {
        for observer in observers {
            observer(level)
        }
    }
}
```

> ✅ **Integration**: The `PerformanceManager` subscribes to `MemoryPressureMonitor` and calls `ModelSwapManager.transition(to:)` when pressure levels change. See [Architecture](../architecture/ARCHITECTURE.md) for the full dependency graph.

---

## Audio Buffer Optimization

The audio pipeline is the first stage of VaulType's transcription flow. Buffer management here directly affects both latency and reliability.

### Buffer Size Selection

| Buffer Size (frames) | Duration @ 16 kHz | Latency | CPU Overhead | Use Case |
|---|---|---|---|---|
| 256 | 16 ms | Very low | Very high | Not recommended |
| 512 | 32 ms | Low | High | Real-time monitoring |
| 1024 | 64 ms | Medium | Medium | **Default for VaulType** |
| 2048 | 128 ms | Higher | Low | Battery-saving mode |
| 4096 | 256 ms | High | Very low | Background processing |

VaulType uses 1024 frames as the default buffer size. This provides 64 ms latency at 16 kHz — fast enough that users perceive no delay between speaking and seeing the waveform indicator, while keeping CPU wake-ups reasonable.

```swift
/// Audio buffer size configuration
enum AudioBufferConfig {
    case lowLatency     // 512 frames
    case balanced       // 1024 frames (default)
    case batterySaving  // 2048 frames

    var frameCount: AVAudioFrameCount {
        switch self {
        case .lowLatency:    return 512
        case .balanced:      return 1024
        case .batterySaving: return 2048
        }
    }

    /// Recommended config based on current power and thermal state
    static func recommended(
        isOnBattery: Bool,
        thermalState: ProcessInfo.ThermalState
    ) -> AudioBufferConfig {
        if thermalState >= .serious || isOnBattery {
            return .batterySaving
        }
        return .balanced
    }
}
```

### Sample Rate Conversion

VaulType captures audio at the system's native sample rate (typically 48 kHz) and converts to 16 kHz for Whisper. The conversion pipeline:

```
┌───────────────┐     ┌──────────────────┐     ┌─────────────────┐
│ AVAudioEngine │     │ Format Converter  │     │ Ring Buffer     │
│ Input Node    │────►│ 48 kHz → 16 kHz  │────►│ (16 kHz mono)   │
│ (48 kHz)      │     │ Stereo → Mono    │     │                 │
│               │     │ Float32           │     │ Whisper reads   │
└───────────────┘     └──────────────────┘     │ from here       │
                                               └─────────────────┘
```

```swift
import AVFoundation

/// Configures the audio format conversion pipeline
struct AudioFormatConverter {
    /// Target format for Whisper: 16 kHz, mono, Float32
    static let whisperFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000.0,
        channels: 1,
        interleaved: false
    )!

    /// Creates an AVAudioConverter for the given input format
    static func makeConverter(
        from inputFormat: AVAudioFormat
    ) -> AVAudioConverter? {
        guard let converter = AVAudioConverter(
            from: inputFormat,
            to: whisperFormat
        ) else {
            return nil
        }

        // Use highest quality SRC for accuracy
        // SampleRateConverterComplexity:
        //   .linear     — fastest, lowest quality
        //   .normal     — balanced (VaulType default on battery)
        //   .mastering  — highest quality (VaulType default on power)
        converter.sampleRateConverterQuality = .max

        return converter
    }
}
```

> 💡 **Performance Note**: Sample rate conversion quality has minimal impact on transcription accuracy for speech. `.normal` quality is sufficient and uses significantly less CPU than `.max`. Reserve `.max` for when connected to power.

### Ring Buffer Implementation

A lock-free ring buffer connects the audio capture thread (real-time priority) to the Whisper inference thread. This avoids priority inversion from locks.

```swift
import Atomics

/// Lock-free single-producer, single-consumer ring buffer for audio samples
final class AudioRingBuffer: @unchecked Sendable {
    private let buffer: UnsafeMutableBufferPointer<Float>
    private let capacity: Int
    private let writeIndex = ManagedAtomic<Int>(0)
    private let readIndex = ManagedAtomic<Int>(0)

    /// Creates a ring buffer with the given capacity in samples
    /// - Parameter capacity: Number of Float samples. Should be power of 2.
    init(capacity: Int) {
        precondition(capacity > 0 && capacity & (capacity - 1) == 0,
                     "Capacity must be a power of 2")
        self.capacity = capacity
        let ptr = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        ptr.initialize(repeating: 0.0, count: capacity)
        self.buffer = UnsafeMutableBufferPointer(start: ptr, count: capacity)
    }

    deinit {
        buffer.baseAddress?.deinitialize(count: capacity)
        buffer.baseAddress?.deallocate()
    }

    /// Number of samples available to read
    var availableSamples: Int {
        let write = writeIndex.load(ordering: .acquiring)
        let read = readIndex.load(ordering: .acquiring)
        return (write - read + capacity) & (capacity - 1)
    }

    /// Number of free slots available for writing
    var freeSlots: Int {
        capacity - 1 - availableSamples
    }

    /// Write samples from the audio capture callback (real-time safe)
    /// - Returns: Number of samples actually written
    @discardableResult
    func write(_ samples: UnsafeBufferPointer<Float>) -> Int {
        let count = min(samples.count, freeSlots)
        guard count > 0 else { return 0 }

        let writePos = writeIndex.load(ordering: .relaxed)

        for i in 0..<count {
            buffer[(writePos + i) & (capacity - 1)] = samples[i]
        }

        writeIndex.store(
            (writePos + count) & (capacity - 1),
            ordering: .releasing
        )
        return count
    }

    /// Read samples for Whisper processing (non-real-time thread)
    /// - Parameter into: Destination buffer
    /// - Returns: Number of samples actually read
    @discardableResult
    func read(into destination: UnsafeMutableBufferPointer<Float>) -> Int {
        let count = min(destination.count, availableSamples)
        guard count > 0 else { return 0 }

        let readPos = readIndex.load(ordering: .relaxed)

        for i in 0..<count {
            destination[i] = buffer[(readPos + i) & (capacity - 1)]
        }

        readIndex.store(
            (readPos + count) & (capacity - 1),
            ordering: .releasing
        )
        return count
    }

    /// Peek at samples without advancing the read pointer
    func peek(count: Int) -> [Float] {
        let available = min(count, availableSamples)
        guard available > 0 else { return [] }

        let readPos = readIndex.load(ordering: .acquiring)
        var result = [Float](repeating: 0, count: available)

        for i in 0..<available {
            result[i] = buffer[(readPos + i) & (capacity - 1)]
        }
        return result
    }

    /// Discard all buffered samples
    func reset() {
        readIndex.store(
            writeIndex.load(ordering: .acquiring),
            ordering: .releasing
        )
    }
}
```

> ⚠️ **Real-Time Safety**: The `write` method is called from the audio render callback, which runs on a real-time thread. It must never allocate memory, acquire locks, or call Objective-C methods. The implementation above uses only atomic operations and direct pointer access.

### Latency vs Reliability Tradeoffs

```
              Low Latency ◄────────────────────────► High Reliability
              ┌─────┬─────┬──────┬──────┬──────┐
Buffer Size:  │ 256 │ 512 │ 1024 │ 2048 │ 4096 │
              └──┬──┴──┬──┴──┬───┴──┬───┴──┬───┘
                 │     │     │      │      │
 Latency (ms):  16    32    64    128    256
 Drop risk:     High  Med   Low   V.Low  None
 CPU wakeups:   62/s  31/s  16/s  8/s    4/s
 Battery:       Poor  Fair  Good  Great  Best
```

VaulType's default of 1024 frames provides the best balance. The ring buffer's capacity should be at least 8x the buffer size (8192 samples = 0.5 seconds) to absorb processing jitter.

---

## Lazy Model Loading Strategies

Loading ML models is expensive. A 4 GB LLM takes 2-4 seconds to load from SSD. VaulType uses lazy loading to keep launch time under 1 second.

### Load on First Use

The simplest strategy: do not load models at launch. Wait until the user triggers their first transcription.

```swift
/// Lazy-loading wrapper for ML model contexts
actor LazyModelLoader<Context> {
    enum State {
        case unloaded
        case loading(Task<Context, Error>)
        case loaded(Context)
        case failed(Error)
    }

    private var state: State = .unloaded
    private let loadFunction: () async throws -> Context
    private let unloadFunction: (Context) -> Void

    init(
        load: @escaping () async throws -> Context,
        unload: @escaping (Context) -> Void
    ) {
        self.loadFunction = load
        self.unloadFunction = unload
    }

    /// Get the model context, loading if necessary
    func get() async throws -> Context {
        switch state {
        case .loaded(let context):
            return context

        case .loading(let task):
            return try await task.value

        case .unloaded, .failed:
            let task = Task {
                try await loadFunction()
            }
            state = .loading(task)
            do {
                let context = try await task.value
                state = .loaded(context)
                return context
            } catch {
                state = .failed(error)
                throw error
            }
        }
    }

    /// Unload the model to free memory
    func unload() {
        if case .loaded(let context) = state {
            unloadFunction(context)
        }
        state = .unloaded
    }

    /// Whether the model is currently loaded and ready
    var isLoaded: Bool {
        if case .loaded = state { return true }
        return false
    }
}
```

### Background Preloading

After launch, preload models in the background if conditions allow (on power, not thermal throttled, sufficient memory):

```swift
/// Preloads models in the background when conditions are favorable
final class BackgroundPreloader {
    private var preloadTask: Task<Void, Never>?

    func startPreloadingIfAppropriate(
        whisperLoader: LazyModelLoader<OpaquePointer>,
        llmLoader: LazyModelLoader<OpaquePointer>,
        performanceState: PerformanceState
    ) {
        // Don't preload if conditions are unfavorable
        guard !performanceState.isOnBattery,
              performanceState.thermalState <= .fair,
              performanceState.memoryPressure == .nominal else {
            return
        }

        preloadTask = Task(priority: .background) {
            // Small delay so launch UI is fully responsive first
            try? await Task.sleep(for: .seconds(2))

            guard !Task.isCancelled else { return }

            // Load Whisper first (smaller, more immediately needed)
            _ = try? await whisperLoader.get()

            guard !Task.isCancelled else { return }

            // Then LLM
            _ = try? await llmLoader.get()
        }
    }

    func cancelPreloading() {
        preloadTask?.cancel()
        preloadTask = nil
    }
}
```

### Warm-Up Inference

After loading, run a single dummy inference to warm up GPU shaders and fill caches:

```swift
/// Runs warm-up inference passes to prime GPU shader caches
struct ModelWarmup {
    /// Warm up Whisper with a short silence buffer
    static func warmUpWhisper(context: OpaquePointer) async {
        // Create 1 second of silence at 16 kHz
        let silenceBuffer = [Float](repeating: 0.0, count: 16000)

        await Task.detached(priority: .background) {
            // whisper_full() with the silence buffer
            // This compiles Metal shaders on first run and caches them
            silenceBuffer.withUnsafeBufferPointer { ptr in
                // whisper_full(context, params, ptr.baseAddress, Int32(ptr.count))
                _ = ptr // Placeholder: actual whisper_full call
            }
        }.value
    }

    /// Warm up LLM with a minimal prompt
    static func warmUpLLM(model: OpaquePointer) async {
        await Task.detached(priority: .background) {
            // Run a single-token generation with a minimal prompt
            // This warms up:
            //   1. Metal compute pipeline state objects
            //   2. GPU shader compilation cache
            //   3. Memory allocation pools
            // Actual llama_decode call with a single "hello" token
        }.value
    }
}
```

> ℹ️ **Shader Compilation**: Metal shaders are compiled just-in-time on first use. The first inference pass is typically 2-5x slower than subsequent passes. Warm-up inference ensures the user never sees this penalty.

### Model Priority Queue

When multiple models need loading, prioritize based on likely user action:

```swift
/// Priority queue for model loading requests
actor ModelPriorityQueue {
    struct LoadRequest: Comparable {
        let modelId: String
        let priority: Priority
        let loadAction: () async throws -> Void

        enum Priority: Int, Comparable {
            case critical = 0   // User is waiting right now
            case high = 1       // User likely to need soon
            case background = 2 // Speculative preload

            static func < (lhs: Priority, rhs: Priority) -> Bool {
                lhs.rawValue < rhs.rawValue
            }
        }

        static func < (lhs: LoadRequest, rhs: LoadRequest) -> Bool {
            lhs.priority < rhs.priority
        }
    }

    private var queue: [LoadRequest] = []
    private var isProcessing = false

    func enqueue(_ request: LoadRequest) {
        queue.append(request)
        queue.sort()
        processNext()
    }

    private func processNext() {
        guard !isProcessing, let request = queue.first else { return }
        queue.removeFirst()
        isProcessing = true

        Task {
            do {
                try await request.loadAction()
            } catch {
                // Log error, model will be loaded on next attempt
            }
            isProcessing = false
            processNext()
        }
    }
}
```

### Model Preloading Service

The complete preloading service that ties all loading strategies together:

```swift
import Combine
import Foundation

/// Orchestrates model lifecycle: lazy loading, preloading, warm-up, and unloading
@MainActor
final class ModelPreloadingService: ObservableObject {
    // MARK: - Published State

    @Published private(set) var whisperState: ModelState = .unloaded
    @Published private(set) var llmState: ModelState = .unloaded

    enum ModelState: Equatable {
        case unloaded
        case loading(progress: Double)
        case loaded
        case warmingUp
        case ready
        case error(String)

        static func == (lhs: ModelState, rhs: ModelState) -> Bool {
            switch (lhs, rhs) {
            case (.unloaded, .unloaded), (.loaded, .loaded),
                 (.warmingUp, .warmingUp), (.ready, .ready):
                return true
            case (.loading(let a), .loading(let b)):
                return a == b
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    // MARK: - Dependencies

    private let memoryMonitor = MemoryPressureMonitor.shared
    private let priorityQueue = ModelPriorityQueue()
    private var cancellables = Set<AnyCancellable>()
    private var idleTimers: [String: Task<Void, Never>] = [:]

    // Configuration
    private let whisperIdleTimeout: Duration = .seconds(300)  // 5 minutes
    private let llmIdleTimeout: Duration = .seconds(300)      // 5 minutes

    // MARK: - Initialization

    init() {
        setupMemoryPressureHandling()
        setupThermalStateHandling()
    }

    // MARK: - Public API

    /// Ensure Whisper is loaded and ready for transcription
    func ensureWhisperReady() async throws {
        resetIdleTimer(for: "whisper")

        guard whisperState != .ready else { return }

        whisperState = .loading(progress: 0.0)

        // Load model from disk
        // In actual implementation: whisper_init_from_file_with_params()
        whisperState = .loading(progress: 0.5)

        // Simulated progress for Metal shader compilation
        whisperState = .loaded

        // Warm up
        whisperState = .warmingUp
        // await ModelWarmup.warmUpWhisper(context: whisperContext)

        whisperState = .ready
        startIdleTimer(for: "whisper", timeout: whisperIdleTimeout)
    }

    /// Ensure LLM is loaded and ready for text refinement
    func ensureLLMReady() async throws {
        resetIdleTimer(for: "llm")

        guard llmState != .ready else { return }

        llmState = .loading(progress: 0.0)

        // Load model
        llmState = .loading(progress: 0.5)
        llmState = .loaded

        // Warm up
        llmState = .warmingUp
        // await ModelWarmup.warmUpLLM(model: llamaModel)

        llmState = .ready
        startIdleTimer(for: "llm", timeout: llmIdleTimeout)
    }

    /// Preload both models in the background if conditions are favorable
    func preloadIfFavorable(
        isOnBattery: Bool,
        thermalState: ProcessInfo.ThermalState
    ) {
        guard !isOnBattery,
              thermalState <= .fair else {
            return
        }

        Task(priority: .background) {
            try? await Task.sleep(for: .seconds(2))
            try? await ensureWhisperReady()
            try? await Task.sleep(for: .seconds(1))
            try? await ensureLLMReady()
        }
    }

    /// Unload a specific model
    func unload(_ model: String) {
        switch model {
        case "whisper":
            // whisper_free(context)
            whisperState = .unloaded
        case "llm":
            // llama_free_model(model)
            llmState = .unloaded
        default:
            break
        }
        idleTimers[model]?.cancel()
        idleTimers[model] = nil
    }

    /// Unload all models
    func unloadAll() {
        unload("whisper")
        unload("llm")
    }

    // MARK: - Private

    private func setupMemoryPressureHandling() {
        memoryMonitor.observe { [weak self] level in
            Task { @MainActor in
                guard let self else { return }
                switch level {
                case .warning:
                    // Unload LLM if it's idle (Whisper is more critical)
                    if self.llmState == .ready {
                        self.unload("llm")
                    }
                case .critical:
                    self.unloadAll()
                case .nominal:
                    break
                }
            }
        }
    }

    private func setupThermalStateHandling() {
        NotificationCenter.default
            .publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let state = ProcessInfo.processInfo.thermalState
                if state == .critical {
                    self.unloadAll()
                } else if state == .serious {
                    self.unload("llm")
                }
            }
            .store(in: &cancellables)
    }

    private func startIdleTimer(for model: String, timeout: Duration) {
        idleTimers[model]?.cancel()
        idleTimers[model] = Task {
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.unload(model)
            }
        }
    }

    private func resetIdleTimer(for model: String) {
        idleTimers[model]?.cancel()
        idleTimers[model] = nil
    }
}
```

> ✅ **Architecture Note**: `ModelPreloadingService` is owned by the `PerformanceManager` and exposed to SwiftUI views via `@EnvironmentObject`. See [Architecture](../architecture/ARCHITECTURE.md) for the full object graph.

---

## Battery-Aware Performance Throttling

VaulType adapts its performance profile based on whether the Mac is connected to power or running on battery.

### Power Source Detection

```swift
import IOKit.ps

/// Monitors power source changes and provides current battery state
final class PowerSourceMonitor: @unchecked Sendable {
    static let shared = PowerSourceMonitor()

    struct PowerState: Equatable {
        let isOnBattery: Bool
        let batteryLevel: Double?       // 0.0 - 1.0, nil if no battery
        let isCharging: Bool
        let timeRemaining: TimeInterval? // seconds, nil if unknown

        /// Whether we should use battery-saving mode
        var shouldThrottle: Bool {
            isOnBattery && (batteryLevel ?? 1.0) < 0.5
        }

        /// Whether we should use minimal mode (critical battery)
        var isCritical: Bool {
            isOnBattery && (batteryLevel ?? 1.0) < 0.1
        }
    }

    private var observers: [(PowerState) -> Void] = []
    private var runLoopSource: CFRunLoopSource?

    private(set) var currentState: PowerState

    private init() {
        self.currentState = PowerSourceMonitor.readCurrentState()
        setupMonitoring()
    }

    /// Read current power source info from IOKit
    private static func readCurrentState() -> PowerState {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue()
                as? [CFTypeRef] else {
            // Desktop Mac with no battery
            return PowerState(
                isOnBattery: false,
                batteryLevel: nil,
                isCharging: false,
                timeRemaining: nil
            )
        }

        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any] else {
                continue
            }

            let powerSource = info[kIOPSPowerSourceStateKey as String] as? String
            let isOnBattery = powerSource == kIOPSBatteryPowerValue
            let currentCapacity = info[kIOPSCurrentCapacityKey as String] as? Int ?? 0
            let maxCapacity = info[kIOPSMaxCapacityKey as String] as? Int ?? 100
            let isCharging = info[kIOPSIsChargingKey as String] as? Bool ?? false
            let timeRemaining = info[kIOPSTimeToEmptyKey as String] as? Int

            return PowerState(
                isOnBattery: isOnBattery,
                batteryLevel: Double(currentCapacity) / Double(maxCapacity),
                isCharging: isCharging,
                timeRemaining: timeRemaining.map { TimeInterval($0 * 60) }
            )
        }

        return PowerState(
            isOnBattery: false,
            batteryLevel: nil,
            isCharging: false,
            timeRemaining: nil
        )
    }

    private func setupMonitoring() {
        let context = UnsafeMutableRawPointer(
            Unmanaged.passUnretained(self).toOpaque()
        )

        runLoopSource = IOPSNotificationCreateRunLoopSource(
            { context in
                guard let context else { return }
                let monitor = Unmanaged<PowerSourceMonitor>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                let newState = PowerSourceMonitor.readCurrentState()
                if newState != monitor.currentState {
                    monitor.currentState = newState
                    for observer in monitor.observers {
                        observer(newState)
                    }
                }
            },
            context
        )?.takeRetainedValue()

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    func observe(_ handler: @escaping (PowerState) -> Void) {
        observers.append(handler)
    }
}
```

### Battery-Aware Model Selection

```swift
/// Selects optimal model configuration based on power state
struct BatteryAwareModelSelector {

    struct ModelSelection {
        let whisperModel: WhisperModelSize
        let llmQuantization: LLMQuantization
        let llmParameterBillions: Double
        let gpuLayerReduction: Int32  // reduce GPU layers by this amount
        let preloadingEnabled: Bool
        let audioBufferConfig: AudioBufferConfig
    }

    /// Select the best model configuration for current conditions
    static func select(
        powerState: PowerSourceMonitor.PowerState,
        thermalState: ProcessInfo.ThermalState,
        availableMemoryGB: Double,
        preferredWhisperModel: WhisperModelSize,
        preferredLLMQuantization: LLMQuantization,
        preferredLLMParamBillions: Double
    ) -> ModelSelection {

        // On power, no thermal issues: use preferred configuration
        if !powerState.isOnBattery && thermalState <= .fair {
            return ModelSelection(
                whisperModel: preferredWhisperModel,
                llmQuantization: preferredLLMQuantization,
                llmParameterBillions: preferredLLMParamBillions,
                gpuLayerReduction: 0,
                preloadingEnabled: true,
                audioBufferConfig: .balanced
            )
        }

        // Critical battery: minimal configuration
        if powerState.isCritical {
            return ModelSelection(
                whisperModel: .tiny,
                llmQuantization: .q4_0,
                llmParameterBillions: min(preferredLLMParamBillions, 3.0),
                gpuLayerReduction: 16,
                preloadingEnabled: false,
                audioBufferConfig: .batterySaving
            )
        }

        // On battery with < 50%: reduced configuration
        if powerState.shouldThrottle {
            let whisper: WhisperModelSize = switch preferredWhisperModel {
            case .large:  .medium
            case .medium: .small
            default:      preferredWhisperModel
            }

            return ModelSelection(
                whisperModel: whisper,
                llmQuantization: .q4_0,
                llmParameterBillions: preferredLLMParamBillions,
                gpuLayerReduction: 8,
                preloadingEnabled: false,
                audioBufferConfig: .batterySaving
            )
        }

        // On battery, > 50%: slightly reduced configuration
        return ModelSelection(
            whisperModel: preferredWhisperModel,
            llmQuantization: min(preferredLLMQuantization, .q4_k_m),
            llmParameterBillions: preferredLLMParamBillions,
            gpuLayerReduction: 4,
            preloadingEnabled: false,
            audioBufferConfig: .balanced
        )
    }
}

// Make LLMQuantization Comparable for min() usage
extension LLMQuantization: Comparable {
    static func < (lhs: LLMQuantization, rhs: LLMQuantization) -> Bool {
        lhs.bitsPerParameter < rhs.bitsPerParameter
    }
}
```

### Preloading on Battery

| Battery Level | Preloading Policy |
|---|---|
| 100% - 80% (charging or just unplugged) | Allow preloading, use balanced models |
| 80% - 50% | No preloading; load on first use only |
| 50% - 20% | No preloading; reduce to smaller models |
| 20% - 10% | No preloading; reduce GPU layers; unload idle models after 60s |
| Below 10% | Unload LLM entirely; Whisper tiny only; minimal GPU |

### Power Profile Configuration

```swift
/// Power profiles that bundle all performance settings
enum PowerProfile: String, CaseIterable {
    case maximum     // Maximum quality, all features
    case balanced    // Good quality, reasonable power use
    case efficiency  // Reduced quality, extended battery
    case minimal     // Minimum viable, emergency battery

    struct Settings {
        let whisperModel: WhisperModelSize
        let llmQuantization: LLMQuantization
        let maxGPULayers: Int32
        let preloadingEnabled: Bool
        let warmupEnabled: Bool
        let audioBufferConfig: AudioBufferConfig
        let idleUnloadTimeout: Duration
    }

    var settings: Settings {
        switch self {
        case .maximum:
            return Settings(
                whisperModel: .large,
                llmQuantization: .q8_0,
                maxGPULayers: 32,
                preloadingEnabled: true,
                warmupEnabled: true,
                audioBufferConfig: .lowLatency,
                idleUnloadTimeout: .seconds(600)
            )
        case .balanced:
            return Settings(
                whisperModel: .medium,
                llmQuantization: .q4_k_m,
                maxGPULayers: 32,
                preloadingEnabled: true,
                warmupEnabled: true,
                audioBufferConfig: .balanced,
                idleUnloadTimeout: .seconds(300)
            )
        case .efficiency:
            return Settings(
                whisperModel: .small,
                llmQuantization: .q4_0,
                maxGPULayers: 20,
                preloadingEnabled: false,
                warmupEnabled: false,
                audioBufferConfig: .batterySaving,
                idleUnloadTimeout: .seconds(120)
            )
        case .minimal:
            return Settings(
                whisperModel: .tiny,
                llmQuantization: .q4_0,
                maxGPULayers: 8,
                preloadingEnabled: false,
                warmupEnabled: false,
                audioBufferConfig: .batterySaving,
                idleUnloadTimeout: .seconds(30)
            )
        }
    }

    /// Automatically select profile based on current conditions
    static func automatic(
        powerState: PowerSourceMonitor.PowerState,
        thermalState: ProcessInfo.ThermalState
    ) -> PowerProfile {
        if thermalState >= .critical { return .minimal }
        if thermalState >= .serious  { return .efficiency }

        if powerState.isCritical     { return .minimal }
        if powerState.shouldThrottle { return .efficiency }
        if powerState.isOnBattery    { return .balanced }

        return .maximum
    }
}
```

> 🔒 **Privacy Note**: Power state detection uses IOKit APIs and does not require any special permissions. No power data leaves the device.

---

## Thermal Management

Apple Silicon throttles CPU and GPU frequency under thermal pressure. VaulType proactively adapts before the system forces throttling.

### Thermal State Monitoring

macOS provides four thermal states:

| State | Meaning | VaulType Response |
|---|---|---|
| `.nominal` | Normal operating temperature | Full performance |
| `.fair` | Slightly elevated temperature | Reduce preloading |
| `.serious` | High temperature, system may throttle | Reduce GPU layers, smaller models |
| `.critical` | System is actively throttling | Minimal mode, unload LLM |

```
Temperature ──────────────────────────────────────────────►

    ┌───────────┬───────────┬───────────┬───────────┐
    │  nominal  │   fair    │  serious  │ critical  │
    │           │           │           │           │
    │ Full GPU  │ No        │ -8 GPU    │ Unload    │
    │ Preload   │ preload   │ layers    │ LLM       │
    │ All       │ Reduce    │ Smaller   │ Whisper   │
    │ features  │ warm-up   │ models    │ tiny only │
    └───────────┴───────────┴───────────┴───────────┘
```

### Adaptive Throttling

```swift
import Combine

/// Monitors thermal state and adapts performance parameters
@MainActor
final class ThermalThrottleManager: ObservableObject {
    @Published private(set) var currentThermalState: ProcessInfo.ThermalState = .nominal
    @Published private(set) var gpuLayerReduction: Int32 = 0
    @Published private(set) var shouldReduceModelSize: Bool = false
    @Published private(set) var shouldDisablePreloading: Bool = false

    private var cancellable: AnyCancellable?

    init() {
        currentThermalState = ProcessInfo.processInfo.thermalState
        updateThrottling(for: currentThermalState)

        cancellable = NotificationCenter.default
            .publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let newState = ProcessInfo.processInfo.thermalState
                self.currentThermalState = newState
                self.updateThrottling(for: newState)
            }
    }

    private func updateThrottling(for state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal:
            gpuLayerReduction = 0
            shouldReduceModelSize = false
            shouldDisablePreloading = false

        case .fair:
            gpuLayerReduction = 0
            shouldReduceModelSize = false
            shouldDisablePreloading = true  // Stop speculative loads

        case .serious:
            gpuLayerReduction = 8       // Move 8 layers from GPU to CPU
            shouldReduceModelSize = true // Step down model sizes
            shouldDisablePreloading = true

        case .critical:
            gpuLayerReduction = 16
            shouldReduceModelSize = true
            shouldDisablePreloading = true

        @unknown default:
            gpuLayerReduction = 0
            shouldReduceModelSize = false
            shouldDisablePreloading = false
        }
    }
}
```

### Reducing GPU Layers Under Thermal Pressure

When thermal state escalates, reducing GPU layers shifts computation from GPU to CPU. This reduces heat generation because:

1. CPU cores can individually clock down more granularly
2. CPU work can be spread across efficiency cores (P/E core scheduling)
3. GPU power draw is typically higher per FLOP than CPU for these workloads at reduced clocks

```swift
/// Calculates effective GPU layer count under thermal constraints
struct ThermalAwareGPULayers {
    /// Calculate effective GPU layers for Whisper
    static func whisperGPULayers(
        baseConfig: MetalGPUConfiguration,
        thermalReduction: Int32
    ) -> Int32 {
        max(baseConfig.whisperGPULayers - thermalReduction, 0)
    }

    /// Calculate effective GPU layers for LLM
    static func llmGPULayers(
        baseConfig: MetalGPUConfiguration,
        thermalReduction: Int32
    ) -> Int32 {
        max(baseConfig.llmGPULayers - thermalReduction, 0)
    }

    /// Estimated performance impact of thermal reduction
    static func estimatedSlowdown(
        totalLayers: Int32,
        gpuLayers: Int32,
        thermalReduction: Int32
    ) -> Double {
        let originalGPU = Double(gpuLayers)
        let reducedGPU = Double(max(gpuLayers - thermalReduction, 0))
        let cpuLayers = Double(totalLayers) - reducedGPU
        let originalCPULayers = Double(totalLayers) - originalGPU

        // Very rough: GPU layers are ~3x faster than CPU layers
        let originalTime = originalCPULayers * 3.0 + originalGPU * 1.0
        let reducedTime = cpuLayers * 3.0 + reducedGPU * 1.0

        return reducedTime / originalTime
    }
}
```

### Thermal Throttling in Code

Complete thermal adaptation that integrates with the model pipeline:

```swift
import Combine
import Foundation

/// Coordinates thermal management across all VaulType subsystems
@MainActor
final class ThermalCoordinator: ObservableObject {
    @Published private(set) var effectiveProfile: PowerProfile = .balanced

    private let thermalManager = ThermalThrottleManager()
    private let powerMonitor = PowerSourceMonitor.shared
    private let preloadingService: ModelPreloadingService

    private var cancellables = Set<AnyCancellable>()

    init(preloadingService: ModelPreloadingService) {
        self.preloadingService = preloadingService
        setupBindings()
    }

    private func setupBindings() {
        // React to thermal state changes
        thermalManager.$currentThermalState
            .combineLatest(
                thermalManager.$gpuLayerReduction,
                thermalManager.$shouldReduceModelSize
            )
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] thermalState, _, _ in
                guard let self else { return }
                self.recalculateProfile()
                self.applyThermalMitigation(thermalState)
            }
            .store(in: &cancellables)
    }

    private func recalculateProfile() {
        let powerState = powerMonitor.currentState
        let thermalState = ProcessInfo.processInfo.thermalState
        effectiveProfile = PowerProfile.automatic(
            powerState: powerState,
            thermalState: thermalState
        )
    }

    private func applyThermalMitigation(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal:
            // Restore full performance if memory allows
            break

        case .fair:
            // Cancel any pending preloads
            preloadingService.unload("llm")  // Keep Whisper only if both loaded

        case .serious:
            // Unload LLM, keep Whisper with reduced GPU layers
            preloadingService.unload("llm")
            // Reconfigure Whisper with reduced GPU layers on next inference

        case .critical:
            // Unload everything
            preloadingService.unloadAll()
            // Next transcription will use .minimal profile

        @unknown default:
            break
        }
    }

    /// Log thermal event for diagnostics
    private func logThermalEvent(_ state: ProcessInfo.ThermalState) {
        let stateNames: [ProcessInfo.ThermalState: String] = [
            .nominal: "nominal",
            .fair: "fair",
            .serious: "serious",
            .critical: "critical"
        ]
        let name = stateNames[state] ?? "unknown"
        // Logger.performance.info("Thermal state changed to: \(name)")
        _ = name
    }
}
```

> ⚠️ **Hysteresis**: Thermal state transitions can oscillate. The `debounce(for: .seconds(1))` prevents rapid reconfiguration. When transitioning from `.serious` back to `.nominal`, wait at least 30 seconds before restoring full GPU layers to avoid thermal cycling.

---

## Benchmarking Methodology and Tools

Systematic benchmarking ensures VaulType's performance improves (or at least does not regress) with every release.

### Instruments Profiling

Use these Instruments templates for VaulType performance analysis:

| Template | What to Look For |
|---|---|
| **Time Profiler** | Hot functions in whisper.cpp/llama.cpp wrappers, main thread stalls, Swift overhead |
| **Allocations** | Memory growth during transcription, leaked model buffers, KV cache growth |
| **Metal System Trace** | GPU utilization, shader compilation stalls, GPU/CPU sync points |
| **System Trace** | Thread scheduling, priority inversions, real-time thread preemption |
| **Energy Log** | CPU/GPU/ANE energy impact, background activity, wake-ups |
| **Thermal State** | Thermal ramp during sustained transcription, throttle points |

**Key areas to profile:**

1. **Model loading** — Time from `load()` call to first inference readiness
2. **First inference** — Time including shader compilation
3. **Steady-state inference** — Time for subsequent inferences (cached shaders)
4. **Audio pipeline latency** — Time from microphone capture to ring buffer availability
5. **End-to-end latency** — Time from end of speech to text appearing in target app
6. **Memory high-water mark** — Peak memory during dual-model operation

### Custom Benchmarking Harness

```swift
import Foundation
import os.signpost

/// Benchmarking harness for VaulType performance measurements
final class PerformanceBenchmark {
    // MARK: - Signpost Integration

    private static let log = OSLog(
        subsystem: "com.vaultype.benchmark",
        category: .pointsOfInterest
    )

    private static let signpostLog = OSLog(
        subsystem: "com.vaultype.benchmark",
        category: "Performance"
    )

    // MARK: - Measurement Types

    struct Measurement {
        let name: String
        let duration: Duration
        let metadata: [String: String]
        let timestamp: Date

        var durationMilliseconds: Double {
            let components = duration.components
            return Double(components.seconds) * 1000.0 +
                   Double(components.attoseconds) / 1_000_000_000_000_000.0
        }
    }

    struct BenchmarkResult {
        let name: String
        let measurements: [Measurement]

        var count: Int { measurements.count }

        var meanDuration: Double {
            guard !measurements.isEmpty else { return 0 }
            let total = measurements.reduce(0.0) { $0 + $1.durationMilliseconds }
            return total / Double(measurements.count)
        }

        var medianDuration: Double {
            guard !measurements.isEmpty else { return 0 }
            let sorted = measurements.map(\.durationMilliseconds).sorted()
            let mid = sorted.count / 2
            if sorted.count.isMultiple(of: 2) {
                return (sorted[mid - 1] + sorted[mid]) / 2.0
            }
            return sorted[mid]
        }

        var p95Duration: Double {
            guard !measurements.isEmpty else { return 0 }
            let sorted = measurements.map(\.durationMilliseconds).sorted()
            let index = Int(Double(sorted.count) * 0.95)
            return sorted[min(index, sorted.count - 1)]
        }

        var p99Duration: Double {
            guard !measurements.isEmpty else { return 0 }
            let sorted = measurements.map(\.durationMilliseconds).sorted()
            let index = Int(Double(sorted.count) * 0.99)
            return sorted[min(index, sorted.count - 1)]
        }

        var standardDeviation: Double {
            guard measurements.count > 1 else { return 0 }
            let mean = meanDuration
            let variance = measurements.reduce(0.0) { sum, m in
                let diff = m.durationMilliseconds - mean
                return sum + diff * diff
            } / Double(measurements.count - 1)
            return variance.squareRoot()
        }

        var summary: String {
            """
            Benchmark: \(name)
            Iterations: \(count)
            Mean:   \(String(format: "%.2f", meanDuration)) ms
            Median: \(String(format: "%.2f", medianDuration)) ms
            P95:    \(String(format: "%.2f", p95Duration)) ms
            P99:    \(String(format: "%.2f", p99Duration)) ms
            StdDev: \(String(format: "%.2f", standardDeviation)) ms
            """
        }
    }

    // MARK: - Benchmark Execution

    private var results: [String: [Measurement]] = [:]

    /// Run a benchmark with the given name and iteration count
    func benchmark(
        name: String,
        iterations: Int = 100,
        warmupIterations: Int = 5,
        metadata: [String: String] = [:],
        operation: () async throws -> Void
    ) async throws -> BenchmarkResult {
        // Warm-up phase (results discarded)
        for _ in 0..<warmupIterations {
            try await operation()
        }

        // Measurement phase
        var measurements: [Measurement] = []
        measurements.reserveCapacity(iterations)

        for _ in 0..<iterations {
            let signpostID = OSSignpostID(log: Self.signpostLog)
            os_signpost(
                .begin,
                log: Self.signpostLog,
                name: "Benchmark",
                signpostID: signpostID,
                "%{public}s",
                name
            )

            let clock = ContinuousClock()
            let duration = try await clock.measure {
                try await operation()
            }

            os_signpost(
                .end,
                log: Self.signpostLog,
                name: "Benchmark",
                signpostID: signpostID
            )

            measurements.append(Measurement(
                name: name,
                duration: duration,
                metadata: metadata,
                timestamp: Date()
            ))
        }

        results[name] = measurements
        return BenchmarkResult(name: name, measurements: measurements)
    }

    /// Run a synchronous benchmark
    func benchmarkSync(
        name: String,
        iterations: Int = 100,
        warmupIterations: Int = 5,
        metadata: [String: String] = [:],
        operation: () throws -> Void
    ) throws -> BenchmarkResult {
        // Warm-up
        for _ in 0..<warmupIterations {
            try operation()
        }

        var measurements: [Measurement] = []
        measurements.reserveCapacity(iterations)

        let clock = ContinuousClock()

        for _ in 0..<iterations {
            let duration = try clock.measure {
                try operation()
            }

            measurements.append(Measurement(
                name: name,
                duration: duration,
                metadata: metadata,
                timestamp: Date()
            ))
        }

        results[name] = measurements
        return BenchmarkResult(name: name, measurements: measurements)
    }

    /// Export all results as JSON for trend analysis
    func exportJSON() throws -> Data {
        struct ExportEntry: Codable {
            let name: String
            let durationMs: Double
            let metadata: [String: String]
            let timestamp: String
        }

        let formatter = ISO8601DateFormatter()
        let entries = results.flatMap { (name, measurements) in
            measurements.map { m in
                ExportEntry(
                    name: name,
                    durationMs: m.durationMilliseconds,
                    metadata: m.metadata,
                    timestamp: formatter.string(from: m.timestamp)
                )
            }
        }

        return try JSONEncoder().encode(entries)
    }

    /// Print a formatted summary of all results
    func printSummary() {
        for (name, measurements) in results.sorted(by: { $0.key < $1.key }) {
            let result = BenchmarkResult(name: name, measurements: measurements)
            print(result.summary)
            print("---")
        }
    }
}
```

**Example usage:**

```swift
// Run benchmarks for all key operations
func runPerformanceSuite() async throws {
    let bench = PerformanceBenchmark()

    // Benchmark Whisper inference
    let whisperResult = try await bench.benchmark(
        name: "whisper_inference_5s_audio",
        iterations: 50,
        warmupIterations: 3,
        metadata: [
            "model": "medium",
            "audio_duration": "5.0",
            "hardware": ProcessInfo.processInfo.machineHardwareName
        ]
    ) {
        // Run whisper_full() on a 5-second test audio buffer
        try await transcribeTestAudio()
    }

    // Benchmark LLM inference
    let llmResult = try await bench.benchmark(
        name: "llm_refinement_50_tokens",
        iterations: 50,
        warmupIterations: 3,
        metadata: [
            "quantization": "Q4_K_M",
            "input_tokens": "50",
            "hardware": ProcessInfo.processInfo.machineHardwareName
        ]
    ) {
        // Run llama_decode() on a test prompt
        try await refineTestText()
    }

    // Benchmark end-to-end pipeline
    let e2eResult = try await bench.benchmark(
        name: "end_to_end_pipeline",
        iterations: 20,
        warmupIterations: 2,
        metadata: [
            "whisper_model": "medium",
            "llm_quantization": "Q4_K_M"
        ]
    ) {
        try await runFullPipeline()
    }

    bench.printSummary()

    // Export for CI comparison
    let jsonData = try bench.exportJSON()
    try jsonData.write(to: URL(fileURLWithPath: "/tmp/vaultype_benchmarks.json"))
}

// Helper to get hardware name
extension ProcessInfo {
    var machineHardwareName: String {
        var sysinfo = utsname()
        uname(&sysinfo)
        return withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "unknown"
            }
        }
    }
}
```

### Key Metrics to Track

| Metric | Target | Alert Threshold | Measurement Method |
|---|---|---|---|
| **Model load time** (Whisper medium) | < 1.5 s | > 3.0 s | `ContinuousClock` around init |
| **Model load time** (LLM Q4_K_M 7B) | < 3.0 s | > 6.0 s | `ContinuousClock` around init |
| **First inference** (Whisper) | < 500 ms | > 1000 ms | Includes shader compilation |
| **Steady inference** (Whisper, 5s audio) | < 300 ms | > 600 ms | After warm-up |
| **LLM tokens/sec** (Q4_K_M, M2) | > 20 t/s | < 10 t/s | Token generation loop |
| **End-to-end latency** | < 500 ms | > 1000 ms | Speech end → text output |
| **Peak memory** (dual model) | < 7 GB | > 10 GB | `mach_task_basic_info` |
| **Audio dropout rate** | < 0.1% | > 1% | Ring buffer overflow counter |
| **Battery drain** (1 hr active) | < 15% | > 25% | IOPowerSources sampling |

### Regression Detection

Integrate benchmarks into CI to catch regressions:

```swift
/// Compares benchmark results against stored baselines
struct RegressionDetector {
    struct Baseline: Codable {
        let name: String
        let meanDurationMs: Double
        let p95DurationMs: Double
        let hardware: String
        let date: String
    }

    /// Load baselines from disk
    static func loadBaselines(
        from url: URL
    ) throws -> [String: Baseline] {
        let data = try Data(contentsOf: url)
        let baselines = try JSONDecoder().decode([Baseline].self, from: data)
        return Dictionary(uniqueKeysWithValues: baselines.map { ($0.name, $0) })
    }

    /// Check for regressions against baselines
    static func checkForRegressions(
        results: [PerformanceBenchmark.BenchmarkResult],
        baselines: [String: Baseline],
        regressionThreshold: Double = 0.10  // 10% slower = regression
    ) -> [RegressionReport] {
        var reports: [RegressionReport] = []

        for result in results {
            guard let baseline = baselines[result.name] else {
                reports.append(RegressionReport(
                    name: result.name,
                    status: .noBaseline,
                    currentMean: result.meanDuration,
                    baselineMean: nil,
                    changePercent: nil
                ))
                continue
            }

            let changePercent = (result.meanDuration - baseline.meanDurationMs)
                / baseline.meanDurationMs

            let status: RegressionStatus
            if changePercent > regressionThreshold {
                status = .regression
            } else if changePercent < -regressionThreshold {
                status = .improvement
            } else {
                status = .stable
            }

            reports.append(RegressionReport(
                name: result.name,
                status: status,
                currentMean: result.meanDuration,
                baselineMean: baseline.meanDurationMs,
                changePercent: changePercent
            ))
        }

        return reports
    }

    enum RegressionStatus: String {
        case regression
        case stable
        case improvement
        case noBaseline
    }

    struct RegressionReport {
        let name: String
        let status: RegressionStatus
        let currentMean: Double
        let baselineMean: Double?
        let changePercent: Double?

        var description: String {
            let changeStr: String
            if let change = changePercent {
                let sign = change >= 0 ? "+" : ""
                changeStr = "\(sign)\(String(format: "%.1f", change * 100))%"
            } else {
                changeStr = "N/A"
            }

            let icon: String = switch status {
            case .regression:  "FAIL"
            case .stable:      "PASS"
            case .improvement: "IMPROVED"
            case .noBaseline:  "NEW"
            }

            return "[\(icon)] \(name): \(String(format: "%.2f", currentMean)) ms (\(changeStr))"
        }
    }
}
```

### Performance Benchmark Tables

**End-to-End Latency (5-second utterance, speech-end to text-output):**

| Configuration | M1 (8 GB) | M2 (8 GB) | M3 (16 GB) | M4 Pro (24 GB) |
|---|---|---|---|---|
| tiny + Q4_0 3B | 320 ms | 250 ms | 210 ms | 150 ms |
| small + Q4_K_M 7B | 480 ms | 380 ms | 310 ms | 220 ms |
| medium + Q4_K_M 7B | 650 ms | 500 ms | 400 ms | 280 ms |
| large-v3 + Q4_K_M 7B | 1100 ms | 850 ms | 680 ms | 450 ms |
| large-v3 + Q8_0 7B | N/A | N/A | 900 ms | 550 ms |

> ℹ️ **Reading the table**: These represent total latency from the moment the user stops speaking to the moment refined text is ready for insertion. The pipeline runs Whisper and LLM sequentially (Whisper output feeds LLM input).

**Model Loading Time (cold start, from SSD):**

| Model | Size | M1 | M2 | M3 | M4 |
|---|---|---|---|---|---|
| Whisper tiny | 75 MB | 0.1 s | 0.08 s | 0.07 s | 0.05 s |
| Whisper medium | 1.5 GB | 0.8 s | 0.6 s | 0.5 s | 0.4 s |
| Whisper large-v3 | 3.1 GB | 1.5 s | 1.2 s | 1.0 s | 0.8 s |
| LLM Q4_K_M 7B | 4.1 GB | 2.5 s | 2.0 s | 1.7 s | 1.3 s |
| LLM Q8_0 7B | 7.2 GB | 4.0 s | 3.2 s | 2.8 s | 2.1 s |

**Peak Memory During Dual-Model Operation:**

| Configuration | Model Memory | Compute Overhead | Total Peak |
|---|---|---|---|
| tiny + Q4_0 3B | 1.8 GB | 0.5 GB | 2.3 GB |
| base + Q4_K_M 7B | 4.3 GB | 0.7 GB | 5.0 GB |
| small + Q4_K_M 7B | 4.6 GB | 0.7 GB | 5.3 GB |
| medium + Q4_K_M 7B | 5.6 GB | 0.9 GB | 6.5 GB |
| large-v3 + Q4_K_M 7B | 7.1 GB | 1.1 GB | 8.2 GB |
| large-v3 + Q8_0 7B | 10.2 GB | 1.3 GB | 11.5 GB |
| large-v3 + Q8_0 13B | 16.5 GB | 1.8 GB | 18.3 GB |

---

## Pipeline Optimization

### End-to-End Pipeline

The full VaulType pipeline from microphone to text insertion:

```
┌─────────────────────────────────────────────────────────────────────┐
│                    VaulType Processing Pipeline                      │
│                                                                     │
│  ┌─────────┐   ┌──────────┐   ┌──────────┐   ┌──────────────────┐ │
│  │ Audio   │   │ Format   │   │ Ring     │   │ Voice Activity   │ │
│  │ Capture │──►│ Convert  │──►│ Buffer   │──►│ Detection (VAD)  │ │
│  │ 48 kHz  │   │ → 16 kHz │   │ 0.5 s   │   │                  │ │
│  └─────────┘   └──────────┘   └──────────┘   └────────┬─────────┘ │
│                                                        │           │
│                                          Speech ended? │           │
│                                                        ▼           │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    Whisper Inference                         │   │
│  │                                                             │   │
│  │  Audio Chunk ──► Mel Spectrogram ──► Encoder ──► Decoder    │   │
│  │                                                   │         │   │
│  │                                          Raw transcript     │   │
│  └─────────────────────────────────────────────┬───────────────┘   │
│                                                │                   │
│                                                ▼                   │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    LLM Refinement                           │   │
│  │                                                             │   │
│  │  System Prompt + Raw Transcript ──► Token Generation        │   │
│  │                                          │                  │   │
│  │                                   Refined text              │   │
│  └─────────────────────────────────────────────┬───────────────┘   │
│                                                │                   │
│                                                ▼                   │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    Text Insertion                            │   │
│  │                                                             │   │
│  │  Refined Text ──► CGEvent / Accessibility API ──► Target App│   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘

Timeline (medium + Q4_K_M 7B on M2):
├─ Audio capture ──────────────────────── continuous ─────────────────┤
├─ VAD detection ────────────────────────── ~50 ms ──┤
├─ Whisper inference ─────────────────────────────── ~250 ms ────────┤
├─ LLM refinement ─────────────────────────────────── ~130 ms ──────┤
├─ Text insertion ──────────────────────────────────────── ~5 ms ───┤
│                                                                    │
│   Total end-to-end: ~435 ms                                        │
```

### Concurrent Execution Strategy

While Whisper and LLM run sequentially per utterance (LLM needs Whisper's output), multiple optimizations enable concurrency:

1. **Streaming Whisper output**: Begin LLM processing as soon as the first sentence is decoded, while Whisper continues on remaining audio
2. **Pipeline overlap**: While LLM refines utterance N, Whisper can begin processing utterance N+1
3. **Parallel model prep**: Load/warm-up both models concurrently during preloading

```swift
/// Orchestrates overlapped pipeline execution
actor PipelineOrchestrator {
    private let whisperEngine: WhisperEngine
    private let llmEngine: LLMEngine

    init(whisperEngine: WhisperEngine, llmEngine: LLMEngine) {
        self.whisperEngine = whisperEngine
        self.llmEngine = llmEngine
    }

    /// Process audio with pipeline overlap
    func processAudio(_ audioBuffer: [Float]) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                // Start Whisper transcription
                let rawSegments = await whisperEngine.transcribeStreaming(audioBuffer)

                // Process each segment through LLM as it becomes available
                for await segment in rawSegments {
                    let refined = try? await llmEngine.refine(segment)
                    continuation.yield(refined ?? segment)
                }

                continuation.finish()
            }
        }
    }
}

// Protocol stubs for the example
protocol WhisperEngine {
    func transcribeStreaming(_ audio: [Float]) async -> AsyncStream<String>
}

protocol LLMEngine {
    func refine(_ text: String) async throws -> String
}
```

> 💡 **Streaming Optimization**: For short utterances (under 5 seconds), the overhead of streaming is not worth it — just run Whisper to completion then LLM. For longer dictation sessions (30+ seconds), streaming reduces perceived latency significantly because the user sees refined text appearing while still speaking.

---

## Related Documentation

| Document | Relevance |
|---|---|
| [Architecture Overview](../architecture/ARCHITECTURE.md) | System component graph, dependency injection, manager lifecycle |
| [Speech Recognition](../features/SPEECH_RECOGNITION.md) | Whisper integration details, audio pipeline, VAD configuration |
| [LLM Processing](../features/LLM_PROCESSING.md) | llama.cpp integration, prompt engineering, token generation |
| [Model Management](../features/MODEL_MANAGEMENT.md) | Model download, storage, versioning, user-facing model picker |
| [Tech Stack](../architecture/TECH_STACK.md) | Full dependency list, version requirements, build configuration |

---

*This document should be updated whenever new Apple Silicon generations are released, when whisper.cpp or llama.cpp make significant performance changes, or when new quantization formats become available.*
