Last Updated: 2026-02-13

# Scaling Guide

> **HushType** — Privacy-first, macOS-native speech-to-text with local LLM post-processing.
> This guide covers hardware-specific performance tuning, model selection strategies, memory and disk management, supporting new model formats, and plugin system scaling considerations.

---

## Table of Contents

- [Performance Baselines by Hardware](#performance-baselines-by-hardware)
  - [Apple Silicon Performance Matrix](#apple-silicon-performance-matrix)
  - [Intel Mac Performance Matrix](#intel-mac-performance-matrix)
  - [How Benchmarks Were Measured](#how-benchmarks-were-measured)
  - [Hardware Capability Detection](#hardware-capability-detection)
  - [Hardware Tier Classification](#hardware-tier-classification)
- [Model Size vs Speed vs Accuracy Tradeoffs](#model-size-vs-speed-vs-accuracy-tradeoffs)
  - [Whisper Model Decision Matrix](#whisper-model-decision-matrix)
  - [LLM Model Decision Matrix](#llm-model-decision-matrix)
  - [Quantization Impact](#quantization-impact)
  - [Dynamic Model Selection Based on Hardware](#dynamic-model-selection-based-on-hardware)
  - [Per-Hardware Model Recommendation Tables](#per-hardware-model-recommendation-tables)
- [Memory Optimization for Whisper + LLM](#memory-optimization-for-whisper--llm)
  - [Unified Memory Budgets per Hardware](#unified-memory-budgets-per-hardware)
  - [Model Memory Mapping Strategy](#model-memory-mapping-strategy)
  - [Sequential vs Concurrent Model Loading](#sequential-vs-concurrent-model-loading)
  - [Memory Budget Calculator](#memory-budget-calculator)
  - [Memory Pressure Response Escalation](#memory-pressure-response-escalation)
- [Disk Space Management for Multiple Models](#disk-space-management-for-multiple-models)
  - [Model File Sizes Reference](#model-file-sizes-reference)
  - [Storage Calculator](#storage-calculator)
  - [Cleanup Strategies](#cleanup-strategies)
  - [Model Download Priorities](#model-download-priorities)
  - [Storage Warning Thresholds](#storage-warning-thresholds)
  - [Disk Space Monitoring](#disk-space-monitoring)
- [Supporting New Model Formats and Architectures](#supporting-new-model-formats-and-architectures)
  - [Adding New GGUF Quantizations](#adding-new-gguf-quantizations)
  - [Supporting New Whisper Variants](#supporting-new-whisper-variants)
  - [Adapting to whisper.cpp and llama.cpp API Changes](#adapting-to-whispercpp-and-llamacpp-api-changes)
  - [Version Compatibility Matrix](#version-compatibility-matrix)
- [Plugin System Scaling Considerations](#plugin-system-scaling-considerations)
  - [Plugin Resource Limits](#plugin-resource-limits)
  - [Plugin Sandboxing](#plugin-sandboxing)
  - [API Versioning](#api-versioning)
  - [Plugin Discovery and Loading](#plugin-discovery-and-loading)
  - [Plugin Performance Budgets](#plugin-performance-budgets)
- [Related Documentation](#related-documentation)

---

## Performance Baselines by Hardware

HushType runs entirely on-device. Performance varies significantly across Mac hardware, primarily driven by three factors: GPU Neural Engine core count, memory bandwidth, and total unified (or discrete) memory. This section provides concrete baselines so users and developers can set realistic expectations.

### Apple Silicon Performance Matrix

The following measurements use default settings: mmap enabled, all GPU layers offloaded to Metal, Q4_K_M quantization for LLMs, and standard GGUF Whisper models.

| Chip | GPU Cores | Memory BW | Whisper `tiny` RTF | Whisper `base` RTF | Whisper `small` RTF | Whisper `medium` RTF | Whisper `large-v3` RTF | LLM 1B tok/s | LLM 3B tok/s | LLM 7B tok/s | Memory | Tier |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **M1** | 7-8 | 68 GB/s | 0.05 | 0.08 | 0.18 | 0.45 | 1.10 | 65 | 28 | 10 | 8-16 GB | Bronze |
| **M1 Pro** | 14-16 | 200 GB/s | 0.03 | 0.05 | 0.12 | 0.28 | 0.65 | 85 | 42 | 18 | 16-32 GB | Silver |
| **M1 Max** | 24-32 | 400 GB/s | 0.02 | 0.04 | 0.08 | 0.20 | 0.45 | 100 | 55 | 28 | 32-64 GB | Gold |
| **M1 Ultra** | 48-64 | 800 GB/s | 0.01 | 0.03 | 0.06 | 0.14 | 0.32 | 120 | 68 | 38 | 64-128 GB | Platinum |
| **M2** | 8-10 | 100 GB/s | 0.04 | 0.06 | 0.15 | 0.38 | 0.90 | 75 | 34 | 13 | 8-24 GB | Bronze |
| **M2 Pro** | 16-19 | 200 GB/s | 0.03 | 0.04 | 0.10 | 0.25 | 0.58 | 90 | 48 | 22 | 16-32 GB | Silver |
| **M2 Max** | 30-38 | 400 GB/s | 0.02 | 0.03 | 0.07 | 0.18 | 0.40 | 110 | 60 | 32 | 32-96 GB | Gold |
| **M2 Ultra** | 60-76 | 800 GB/s | 0.01 | 0.02 | 0.05 | 0.12 | 0.28 | 130 | 75 | 42 | 64-192 GB | Platinum |
| **M3** | 10 | 100 GB/s | 0.04 | 0.06 | 0.14 | 0.35 | 0.85 | 80 | 38 | 15 | 8-24 GB | Bronze |
| **M3 Pro** | 14-18 | 150 GB/s | 0.03 | 0.04 | 0.10 | 0.24 | 0.55 | 95 | 50 | 24 | 18-36 GB | Silver |
| **M3 Max** | 30-40 | 300-400 GB/s | 0.02 | 0.03 | 0.06 | 0.16 | 0.38 | 115 | 65 | 35 | 36-128 GB | Gold |
| **M4** | 10 | 120 GB/s | 0.03 | 0.05 | 0.12 | 0.30 | 0.75 | 90 | 42 | 17 | 16-32 GB | Silver |
| **M4 Pro** | 16-20 | 273 GB/s | 0.02 | 0.03 | 0.08 | 0.20 | 0.48 | 105 | 58 | 28 | 24-48 GB | Gold |
| **M4 Max** | 32-40 | 546 GB/s | 0.01 | 0.02 | 0.05 | 0.13 | 0.30 | 130 | 72 | 40 | 36-128 GB | Platinum |

> ℹ️ **RTF (Real-Time Factor)**: The ratio of processing time to audio duration. RTF 0.10 means 1 second of audio processes in 0.10 seconds. RTF < 1.0 is faster than real-time. For a responsive dictation experience, target RTF < 0.5 for the chosen Whisper model.

> 🍎 **Apple Silicon Note**: Unified memory means GPU and CPU share the same RAM pool. Setting `gpuLayers: -1` does not double memory usage — the GPU reads directly from the same physical addresses as the CPU. This is HushType's primary advantage on Apple Silicon.

### Intel Mac Performance Matrix

Intel Macs have separate CPU and GPU memory. Whisper and LLM inference runs on CPU only (Metal support for Intel iGPUs is limited and produces slower results than CPU-only inference for these workloads).

| Processor | Cores | RAM (typical) | Whisper `tiny` RTF | Whisper `base` RTF | Whisper `small` RTF | Whisper `medium` RTF | LLM 1B tok/s | LLM 3B tok/s | Memory Headroom | Tier |
|---|---|---|---|---|---|---|---|---|---|---|
| **i5 (4-core)** | 4C/8T | 8-16 GB | 0.15 | 0.30 | 0.80 | 2.20 | 20 | 8 | Low | Intel-Basic |
| **i7 (6-core)** | 6C/12T | 16-32 GB | 0.10 | 0.22 | 0.55 | 1.50 | 30 | 14 | Moderate | Intel-Standard |
| **i9 (8-core)** | 8C/16T | 32-64 GB | 0.08 | 0.16 | 0.40 | 1.10 | 40 | 20 | Adequate | Intel-Performance |

> ⚠️ **Intel Limitation**: Whisper `large-v3` is not recommended on Intel Macs. With RTF > 2.0 on most Intel hardware, the processing time exceeds audio duration for longer recordings, producing an unacceptable user experience. Intel users should use `tiny`, `base`, or `small` models.

> ❌ **No GPU Offloading on Intel**: LLM 7B models are not practical on Intel Macs. Without Metal GPU acceleration for transformer inference, token generation rates fall below 5 tok/s, which is too slow for real-time post-processing. Limit Intel LLM usage to 1B-3B parameter models.

### How Benchmarks Were Measured

All measurements were taken under the following conditions:

- **Audio input**: 30-second English speech sample, 16kHz mono, LibriSpeech test-clean subset
- **Whisper settings**: Default beam search (beam_size=5), no initial prompt, language auto-detect off (forced English)
- **LLM settings**: Q4_K_M quantization, 256-token generation, temperature 0.1, top_p 0.9
- **System state**: Fresh reboot, no other intensive applications, macOS Sonoma 14.4+
- **Measurement tool**: `mach_absolute_time()` with 10-run average, discarding first run (warm-up)

### Hardware Capability Detection

HushType detects the host machine's capabilities at launch to inform default model selection and display hardware-appropriate recommendations in the Settings UI.

```swift
import Foundation
import Metal

/// Represents the detected hardware capabilities of the current Mac.
/// Used to determine default model selections and display appropriate
/// recommendations in the Model Manager UI.
struct HardwareCapabilities: Sendable {

    /// Hardware performance tier for model recommendations.
    enum PerformanceTier: String, Sendable, Comparable, CaseIterable {
        case intelBasic       = "Intel Basic"
        case intelStandard    = "Intel Standard"
        case intelPerformance = "Intel Performance"
        case bronze           = "Bronze"       // M1, M2, M3 base
        case silver           = "Silver"       // Pro variants, M4 base
        case gold             = "Gold"         // Max variants, M4 Pro
        case platinum         = "Platinum"     // Ultra variants, M4 Max

        static func < (lhs: Self, rhs: Self) -> Bool {
            let order = Self.allCases
            return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
        }
    }

    /// Whether the machine uses Apple Silicon (arm64).
    let isAppleSilicon: Bool

    /// Chip name as reported by sysctl (e.g., "Apple M2 Pro").
    let chipName: String

    /// Number of physical CPU cores.
    let physicalCPUCores: Int

    /// Number of performance (P) cores on Apple Silicon.
    let performanceCores: Int

    /// Number of efficiency (E) cores on Apple Silicon.
    let efficiencyCores: Int

    /// Number of GPU cores available to Metal.
    let gpuCoreCount: Int

    /// Total system memory in bytes.
    let totalMemoryBytes: UInt64

    /// Total system memory in gigabytes (convenience).
    var totalMemoryGB: Double {
        Double(totalMemoryBytes) / (1024 * 1024 * 1024)
    }

    /// Estimated memory bandwidth in GB/s.
    let memoryBandwidthGBps: Double

    /// Whether Metal GPU is available for inference acceleration.
    let metalSupported: Bool

    /// Metal GPU family (determines feature set).
    let metalGPUFamily: String

    /// Classified performance tier.
    let tier: PerformanceTier

    /// Detect hardware capabilities of the current machine.
    static func detect() -> HardwareCapabilities {
        let isARM = detectIsAppleSilicon()
        let chipName = detectChipName()
        let physicalCores = ProcessInfo.processInfo.processorCount
        let (pCores, eCores) = detectCoreTopology()
        let gpuCores = detectGPUCoreCount()
        let totalMem = ProcessInfo.processInfo.physicalMemory
        let bandwidth = estimateMemoryBandwidth(chipName: chipName)
        let (metalOK, gpuFamily) = detectMetalCapabilities()

        let tier = classifyTier(
            isAppleSilicon: isARM,
            chipName: chipName,
            gpuCores: gpuCores,
            memoryGB: Double(totalMem) / (1024 * 1024 * 1024)
        )

        return HardwareCapabilities(
            isAppleSilicon: isARM,
            chipName: chipName,
            physicalCPUCores: physicalCores,
            performanceCores: pCores,
            efficiencyCores: eCores,
            gpuCoreCount: gpuCores,
            totalMemoryBytes: totalMem,
            memoryBandwidthGBps: bandwidth,
            metalSupported: metalOK,
            metalGPUFamily: gpuFamily,
            tier: tier
        )
    }

    // MARK: - Private Detection Methods

    private static func detectIsAppleSilicon() -> Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    private static func detectChipName() -> String {
        var size: size_t = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    private static func detectCoreTopology() -> (performance: Int, efficiency: Int) {
        // On Apple Silicon, query sysctl for core types.
        var pCores: Int32 = 0
        var eCores: Int32 = 0
        var size = MemoryLayout<Int32>.size

        if sysctlbyname("hw.perflevel0.physicalcpu", &pCores, &size, nil, 0) == 0,
           sysctlbyname("hw.perflevel1.physicalcpu", &eCores, &size, nil, 0) == 0 {
            return (Int(pCores), Int(eCores))
        }

        // Fallback for Intel: all cores are "performance" cores.
        return (ProcessInfo.processInfo.processorCount, 0)
    }

    private static func detectGPUCoreCount() -> Int {
        guard let device = MTLCreateSystemDefaultDevice() else { return 0 }

        // Metal does not directly expose core count.
        // We use maximum threads per threadgroup as a proxy, combined
        // with chip name parsing for accurate counts on known hardware.
        let chipName = detectChipName()

        // Known Apple Silicon GPU core counts by chip identifier.
        let knownCounts: [String: Int] = [
            "M1": 8, "M1 Pro": 16, "M1 Max": 32, "M1 Ultra": 64,
            "M2": 10, "M2 Pro": 19, "M2 Max": 38, "M2 Ultra": 76,
            "M3": 10, "M3 Pro": 18, "M3 Max": 40,
            "M4": 10, "M4 Pro": 20, "M4 Max": 40,
        ]

        for (chip, cores) in knownCounts {
            if chipName.contains(chip) {
                return cores
            }
        }

        // Fallback: estimate from max threadgroup size.
        let maxThreads = device.maxThreadsPerThreadgroup
        return maxThreads.width / 32  // rough estimate
    }

    private static func estimateMemoryBandwidth(chipName: String) -> Double {
        // Known bandwidth values for Apple Silicon chips (GB/s).
        let knownBandwidth: [(pattern: String, gbps: Double)] = [
            ("M4 Max", 546), ("M4 Pro", 273), ("M4", 120),
            ("M3 Max", 400), ("M3 Pro", 150), ("M3", 100),
            ("M2 Ultra", 800), ("M2 Max", 400), ("M2 Pro", 200), ("M2", 100),
            ("M1 Ultra", 800), ("M1 Max", 400), ("M1 Pro", 200), ("M1", 68),
        ]

        for entry in knownBandwidth {
            if chipName.contains(entry.pattern) {
                return entry.gbps
            }
        }

        // Intel fallback: DDR4 dual-channel typical bandwidth.
        return 38.4
    }

    private static func detectMetalCapabilities() -> (supported: Bool, family: String) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return (false, "None")
        }

        if device.supportsFamily(.apple9) { return (true, "Apple 9 (M3+)") }
        if device.supportsFamily(.apple8) { return (true, "Apple 8 (M2)") }
        if device.supportsFamily(.apple7) { return (true, "Apple 7 (M1)") }
        if device.supportsFamily(.mac2)   { return (true, "Mac 2 (Intel)") }

        return (true, "Unknown")
    }

    private static func classifyTier(
        isAppleSilicon: Bool,
        chipName: String,
        gpuCores: Int,
        memoryGB: Double
    ) -> PerformanceTier {
        guard isAppleSilicon else {
            // Intel classification based on core count and memory.
            if memoryGB >= 32 { return .intelPerformance }
            if memoryGB >= 16 { return .intelStandard }
            return .intelBasic
        }

        // Apple Silicon classification.
        if chipName.contains("Ultra") || chipName.contains("M4 Max") {
            return .platinum
        }
        if chipName.contains("Max") || chipName.contains("M4 Pro") {
            return .gold
        }
        if chipName.contains("Pro") || chipName.contains("M4") {
            return .silver
        }
        return .bronze
    }
}
```

### Hardware Tier Classification

The `PerformanceTier` enum maps directly to model recommendations throughout this guide:

| Tier | Typical Hardware | Max Whisper | Max LLM | Concurrent Loading | User Experience |
|---|---|---|---|---|---|
| **Intel-Basic** | i5, 8 GB | `base` | 1B Q4 | No | Basic transcription only |
| **Intel-Standard** | i7, 16 GB | `small` | 1B Q4 | Marginal | Transcription + simple formatting |
| **Intel-Performance** | i9, 32 GB | `small` | 3B Q4 | Yes | Full pipeline, slower post-processing |
| **Bronze** | M1/M2/M3, 8-16 GB | `small` | 1B-3B Q4 | 8 GB: No / 16 GB: Yes | Good for most dictation tasks |
| **Silver** | Pro chips, M4, 16-32 GB | `medium` | 3B Q4 | Yes | Excellent dictation, good post-processing |
| **Gold** | Max chips, M4 Pro, 32-64 GB | `large-v3` | 7B Q4 | Yes | Full quality, smooth experience |
| **Platinum** | Ultra chips, M4 Max, 64+ GB | `large-v3` | 7B Q8 or 13B Q4 | Yes | Maximum quality, headroom for plugins |

> 💡 **Tip**: HushType auto-detects the hardware tier at first launch and pre-selects appropriate default models during onboarding. Users can always override these defaults in Settings > Models, but the defaults are calibrated to avoid memory pressure on each tier.

---

## Model Size vs Speed vs Accuracy Tradeoffs

Choosing the right model size is the single most impactful decision for HushType's user experience. Larger models produce better results but require more memory and processing time. This section provides decision matrices for both Whisper and LLM model selection.

### Whisper Model Decision Matrix

| Model | Parameters | GGUF Size | RAM (mmap) | RAM (no mmap) | WER (English) | WER (Multilingual) | Best For |
|---|---|---|---|---|---|---|---|
| `tiny` | 39M | 75 MB | ~120 MB | ~200 MB | 7.7% | 14.2% | Intel Macs, quick-and-dirty, minimal memory |
| `tiny.en` | 39M | 75 MB | ~120 MB | ~200 MB | 6.5% | N/A | English-only, Intel i5 |
| `base` | 74M | 142 MB | ~210 MB | ~350 MB | 5.2% | 11.8% | Bronze tier default, good balance |
| `base.en` | 74M | 142 MB | ~210 MB | ~350 MB | 4.5% | N/A | English-only Bronze tier |
| `small` | 244M | 466 MB | ~600 MB | ~900 MB | 3.4% | 8.1% | Silver tier default, production quality |
| `small.en` | 244M | 466 MB | ~600 MB | ~900 MB | 3.0% | N/A | English-only Silver tier |
| `medium` | 769M | 1.5 GB | ~1.8 GB | ~2.8 GB | 2.7% | 6.5% | Gold tier, high accuracy |
| `medium.en` | 769M | 1.5 GB | ~1.8 GB | ~2.8 GB | 2.4% | N/A | English-only Gold tier |
| `large-v3` | 1550M | 3.1 GB | ~3.5 GB | ~5.5 GB | 2.0% | 4.8% | Platinum tier, maximum accuracy |
| `large-v3-turbo` | 809M | 1.6 GB | ~1.9 GB | ~3.0 GB | 2.2% | 5.2% | Gold tier alternative, near-large accuracy |

> ℹ️ **WER (Word Error Rate)**: Lower is better. Measured on LibriSpeech test-clean (English) and FLEURS (Multilingual). Real-world WER depends on microphone quality, ambient noise, accent, and speaking speed. Add 2-5% for typical real-world conditions.

**When to choose each Whisper model:**

| Scenario | Recommended Model | Rationale |
|---|---|---|
| Quick notes and reminders | `tiny` or `base` | Speed matters more than perfect accuracy |
| Professional dictation (English) | `small.en` or `medium.en` | Best accuracy-to-speed ratio for English |
| Multilingual environments | `small` or `medium` | Multilingual models handle code-switching |
| Medical / legal transcription | `large-v3` | Maximum accuracy for specialized vocabulary |
| Long-form dictation (5+ min) | `small` or `medium` | RTF must stay well below 1.0 for responsiveness |
| Low-memory systems (8 GB) | `tiny` or `base` | Leaves room for LLM and system processes |

### LLM Model Decision Matrix

| Model | Parameters | Q4_K_M Size | RAM (mmap) | tok/s (M2) | tok/s (M3 Pro) | Quality | Best For |
|---|---|---|---|---|---|---|---|
| **Qwen2.5-0.5B** | 0.5B | 400 MB | ~600 MB | 95 | 120 | Basic | Punctuation, capitalization only |
| **Qwen2.5-1.5B** | 1.5B | 1.0 GB | ~1.3 GB | 55 | 75 | Good | Formatting, simple grammar fixes |
| **Llama-3.2-1B** | 1.2B | 750 MB | ~1.0 GB | 65 | 85 | Good | General-purpose light formatting |
| **Llama-3.2-3B** | 3.2B | 2.0 GB | ~2.5 GB | 34 | 50 | Very Good | Professional formatting, tone adjustment |
| **Qwen2.5-3B** | 3.0B | 1.9 GB | ~2.4 GB | 36 | 52 | Very Good | Multilingual formatting |
| **Phi-3-mini** | 3.8B | 2.3 GB | ~2.9 GB | 28 | 42 | Very Good | Structured extraction, summarization |
| **Llama-3.1-8B** | 8.0B | 4.7 GB | ~5.5 GB | 13 | 28 | Excellent | Complex rewriting, professional emails |
| **Mistral-7B** | 7.2B | 4.4 GB | ~5.2 GB | 15 | 30 | Excellent | Creative writing, nuanced tone |
| **Qwen2.5-7B** | 7.6B | 4.6 GB | ~5.4 GB | 14 | 29 | Excellent | Multilingual, code-aware formatting |

> ⚠️ **Minimum Token Rate**: For real-time post-processing to feel responsive, target at least 20 tok/s. Below this threshold, users experience noticeable delay between speaking and seeing the processed text. If a model cannot achieve 20 tok/s on the target hardware, recommend a smaller model.

**When to choose each LLM size:**

| Processing Mode | Minimum LLM | Recommended LLM | Rationale |
|---|---|---|---|
| Raw (no processing) | None | None | LLM not loaded at all |
| Punctuation only | 0.5B | 1B | Simple task, smallest model suffices |
| Grammar correction | 1B | 3B | Moderate linguistic understanding needed |
| Professional formatting | 3B | 3B-7B | Needs paragraph structure awareness |
| Email / message rewriting | 3B | 7B | Requires tone and format understanding |
| Summarization | 3B | 7B | Needs comprehension and generation quality |
| Translation | 3B | 7B | Multilingual capability scales with size |

### Quantization Impact

Quantization reduces model size and memory usage at the cost of some quality loss. HushType supports all standard GGUF quantization formats through whisper.cpp and llama.cpp.

| Quantization | Bits/Weight | Size Ratio | Quality Loss | Speed Impact | Recommended For |
|---|---|---|---|---|---|
| **F16** | 16 | 1.0x (baseline) | None | Slowest | Research / validation only |
| **Q8_0** | 8 | 0.50x | Negligible | ~5% faster | Platinum tier, maximum quality |
| **Q6_K** | 6.6 | 0.41x | Minimal | ~10% faster | Gold tier seeking quality |
| **Q5_K_M** | 5.5 | 0.35x | Very small | ~15% faster | Good quality-speed balance |
| **Q4_K_M** | 4.5 | 0.28x | Small | ~20% faster | Default recommendation |
| **Q4_K_S** | 4.5 | 0.27x | Small | ~22% faster | Slightly smaller than Q4_K_M |
| **Q3_K_M** | 3.4 | 0.21x | Moderate | ~25% faster | Memory-constrained systems |
| **Q2_K** | 2.6 | 0.16x | Significant | ~30% faster | Last resort, Intel i5 / 8 GB |
| **IQ4_XS** | 4.3 | 0.26x | Small | ~18% faster | i-quant alternative to Q4_K_M |
| **IQ3_XXS** | 3.1 | 0.19x | Moderate | ~28% faster | i-quant for extreme compression |

> 💡 **Default**: HushType defaults to **Q4_K_M** for all LLM downloads. This quantization offers the best balance of size, speed, and quality for the widest range of hardware. Users can manually download other quantizations from the Model Manager settings panel.

### Dynamic Model Selection Based on Hardware

HushType recommends models automatically at first launch and when the user opens Model Manager. The following code implements the recommendation engine.

```swift
import Foundation

/// Recommends optimal Whisper and LLM models based on detected hardware.
struct ModelRecommendationEngine {

    /// A model recommendation with metadata for the Settings UI.
    struct Recommendation: Sendable {
        let modelId: String
        let displayName: String
        let sizeOnDisk: UInt64       // bytes
        let estimatedRAM: UInt64     // bytes
        let reason: String
        let isDefault: Bool
    }

    /// Complete recommendation set for a hardware configuration.
    struct RecommendationSet: Sendable {
        let whisperDefault: Recommendation
        let whisperAlternatives: [Recommendation]
        let llmDefault: Recommendation?
        let llmAlternatives: [Recommendation]
        let warnings: [String]
    }

    private let hardware: HardwareCapabilities

    init(hardware: HardwareCapabilities) {
        self.hardware = hardware
    }

    /// Generate model recommendations for the detected hardware.
    func recommend() -> RecommendationSet {
        let memGB = hardware.totalMemoryGB
        var warnings: [String] = []

        // Whisper recommendation based on tier.
        let whisperDefault: Recommendation
        let whisperAlts: [Recommendation]

        switch hardware.tier {
        case .intelBasic:
            whisperDefault = Recommendation(
                modelId: "whisper-tiny.en",
                displayName: "Whisper Tiny (English)",
                sizeOnDisk: 75_000_000,
                estimatedRAM: 200_000_000,
                reason: "Best performance on Intel i5 hardware",
                isDefault: true
            )
            whisperAlts = [makeWhisperRec("base.en", default: false)]
            warnings.append(
                "Intel i5 hardware detected. Larger Whisper models "
                + "may produce unacceptable latency."
            )

        case .intelStandard:
            whisperDefault = makeWhisperRec("base.en", default: true)
            whisperAlts = [
                makeWhisperRec("tiny.en", default: false),
                makeWhisperRec("small.en", default: false),
            ]

        case .intelPerformance:
            whisperDefault = makeWhisperRec("small.en", default: true)
            whisperAlts = [
                makeWhisperRec("base.en", default: false),
                makeWhisperRec("small", default: false),
            ]

        case .bronze:
            whisperDefault = makeWhisperRec("base", default: true)
            whisperAlts = [
                makeWhisperRec("tiny", default: false),
                makeWhisperRec("small", default: false),
            ]
            if memGB <= 8 {
                warnings.append(
                    "8 GB unified memory limits concurrent Whisper + LLM. "
                    + "Consider sequential loading mode."
                )
            }

        case .silver:
            whisperDefault = makeWhisperRec("small", default: true)
            whisperAlts = [
                makeWhisperRec("base", default: false),
                makeWhisperRec("medium", default: false),
            ]

        case .gold:
            whisperDefault = makeWhisperRec("medium", default: true)
            whisperAlts = [
                makeWhisperRec("small", default: false),
                makeWhisperRec("large-v3", default: false),
                makeWhisperRec("large-v3-turbo", default: false),
            ]

        case .platinum:
            whisperDefault = makeWhisperRec("large-v3", default: true)
            whisperAlts = [
                makeWhisperRec("large-v3-turbo", default: false),
                makeWhisperRec("medium", default: false),
            ]
        }

        // LLM recommendation based on tier and remaining memory.
        let whisperRAM = whisperDefault.estimatedRAM
        let availableForLLM = hardware.totalMemoryBytes
            - whisperRAM
            - 4_000_000_000  // Reserve 4 GB for macOS + apps

        let (llmDefault, llmAlts) = recommendLLM(
            availableBytes: availableForLLM,
            tier: hardware.tier
        )

        return RecommendationSet(
            whisperDefault: whisperDefault,
            whisperAlternatives: whisperAlts,
            llmDefault: llmDefault,
            llmAlternatives: llmAlts,
            warnings: warnings
        )
    }

    // MARK: - Private Helpers

    private func makeWhisperRec(
        _ variant: String,
        default isDefault: Bool
    ) -> Recommendation {
        let specs: (size: UInt64, ram: UInt64, name: String) = switch variant {
        case "tiny", "tiny.en":
            (75_000_000, 200_000_000, "Whisper Tiny")
        case "base", "base.en":
            (142_000_000, 350_000_000, "Whisper Base")
        case "small", "small.en":
            (466_000_000, 900_000_000, "Whisper Small")
        case "medium", "medium.en":
            (1_500_000_000, 2_800_000_000, "Whisper Medium")
        case "large-v3":
            (3_100_000_000, 5_500_000_000, "Whisper Large V3")
        case "large-v3-turbo":
            (1_600_000_000, 3_000_000_000, "Whisper Large V3 Turbo")
        default:
            (142_000_000, 350_000_000, "Whisper Base")
        }

        let suffix = variant.hasSuffix(".en") ? " (English)" : ""
        return Recommendation(
            modelId: "whisper-\(variant)",
            displayName: specs.name + suffix,
            sizeOnDisk: specs.size,
            estimatedRAM: specs.ram,
            reason: "Recommended for \(hardware.tier.rawValue) tier",
            isDefault: isDefault
        )
    }

    private func recommendLLM(
        availableBytes: UInt64,
        tier: HardwareCapabilities.PerformanceTier
    ) -> (default: Recommendation?, alternatives: [Recommendation]) {
        // No LLM for Intel Basic — not enough headroom.
        if tier == .intelBasic {
            return (nil, [])
        }

        let availableGB = Double(availableBytes) / (1024 * 1024 * 1024)

        if availableGB >= 5.5 && tier >= .gold {
            return (
                makeLLMRec("llama-3.1-8b-q4km", default: true),
                [
                    makeLLMRec("qwen2.5-7b-q4km", default: false),
                    makeLLMRec("llama-3.2-3b-q4km", default: false),
                ]
            )
        } else if availableGB >= 2.5 {
            return (
                makeLLMRec("llama-3.2-3b-q4km", default: true),
                [
                    makeLLMRec("qwen2.5-3b-q4km", default: false),
                    makeLLMRec("phi-3-mini-q4km", default: false),
                    makeLLMRec("qwen2.5-1.5b-q4km", default: false),
                ]
            )
        } else if availableGB >= 1.0 {
            return (
                makeLLMRec("qwen2.5-1.5b-q4km", default: true),
                [
                    makeLLMRec("llama-3.2-1b-q4km", default: false),
                    makeLLMRec("qwen2.5-0.5b-q4km", default: false),
                ]
            )
        } else {
            return (
                makeLLMRec("qwen2.5-0.5b-q4km", default: true),
                []
            )
        }
    }

    private func makeLLMRec(
        _ modelId: String,
        default isDefault: Bool
    ) -> Recommendation {
        let specs: (size: UInt64, ram: UInt64, name: String) = switch modelId {
        case "qwen2.5-0.5b-q4km":
            (400_000_000, 600_000_000, "Qwen 2.5 0.5B")
        case "qwen2.5-1.5b-q4km":
            (1_000_000_000, 1_300_000_000, "Qwen 2.5 1.5B")
        case "llama-3.2-1b-q4km":
            (750_000_000, 1_000_000_000, "Llama 3.2 1B")
        case "llama-3.2-3b-q4km":
            (2_000_000_000, 2_500_000_000, "Llama 3.2 3B")
        case "qwen2.5-3b-q4km":
            (1_900_000_000, 2_400_000_000, "Qwen 2.5 3B")
        case "phi-3-mini-q4km":
            (2_300_000_000, 2_900_000_000, "Phi-3 Mini")
        case "llama-3.1-8b-q4km":
            (4_700_000_000, 5_500_000_000, "Llama 3.1 8B")
        case "qwen2.5-7b-q4km":
            (4_600_000_000, 5_400_000_000, "Qwen 2.5 7B")
        case "mistral-7b-q4km":
            (4_400_000_000, 5_200_000_000, "Mistral 7B")
        default:
            (1_000_000_000, 1_300_000_000, "Unknown LLM")
        }

        return Recommendation(
            modelId: modelId,
            displayName: "\(specs.name) (Q4_K_M)",
            sizeOnDisk: specs.size,
            estimatedRAM: specs.ram,
            reason: "Recommended for \(hardware.tier.rawValue) tier",
            isDefault: isDefault
        )
    }
}
```

### Per-Hardware Model Recommendation Tables

The following tables consolidate hardware-specific recommendations. These correspond to the defaults applied during HushType onboarding.

**Apple Silicon 8 GB (M1, M2, M3 base)**

| Component | Default | Alternative 1 | Alternative 2 | Notes |
|---|---|---|---|---|
| Whisper | `base` | `tiny` | `small` (tight) | `small` requires sequential loading |
| LLM | Qwen2.5-1.5B Q4 | Qwen2.5-0.5B Q4 | Llama-3.2-1B Q4 | 3B models cause memory pressure |
| Loading | Sequential | — | — | Load Whisper, unload, load LLM |
| Total disk | ~1.2 GB | ~0.5 GB | ~0.9 GB | — |

**Apple Silicon 16 GB (M1/M2/M3 base or Pro)**

| Component | Default | Alternative 1 | Alternative 2 | Notes |
|---|---|---|---|---|
| Whisper | `small` | `base` | `medium` | `medium` tight on 16 GB with 3B LLM |
| LLM | Llama-3.2-3B Q4 | Qwen2.5-3B Q4 | Qwen2.5-1.5B Q4 | 7B too large for 16 GB concurrent |
| Loading | Concurrent | — | — | Both models loaded simultaneously |
| Total disk | ~2.5 GB | ~2.4 GB | ~1.5 GB | — |

**Apple Silicon 32 GB+ (Pro/Max)**

| Component | Default | Alternative 1 | Alternative 2 | Notes |
|---|---|---|---|---|
| Whisper | `medium` | `large-v3-turbo` | `large-v3` | All models fit comfortably |
| LLM | Llama-3.1-8B Q4 | Qwen2.5-7B Q4 | Mistral-7B Q4 | Plenty of headroom |
| Loading | Concurrent | — | — | Both models always resident |
| Total disk | ~6.2 GB | ~6.1 GB | ~5.9 GB | — |

**Apple Silicon 64 GB+ (Max/Ultra)**

| Component | Default | Alternative 1 | Alternative 2 | Notes |
|---|---|---|---|---|
| Whisper | `large-v3` | `large-v3-turbo` | `medium` | Top accuracy by default |
| LLM | Llama-3.1-8B Q8 | Qwen2.5-7B Q8 | Any 13B Q4 | Q8 for max quality at this tier |
| Loading | Concurrent | — | — | Memory is not a constraint |
| Total disk | ~12 GB | ~11 GB | ~10 GB | Store multiple model variants |

**Intel Macs**

| Configuration | Whisper | LLM | Loading Mode | Notes |
|---|---|---|---|---|
| i5, 8 GB | `tiny.en` | None or Qwen2.5-0.5B Q4 | Sequential | LLM optional at this level |
| i7, 16 GB | `base.en` | Qwen2.5-1.5B Q4 | Sequential | Marginal concurrent loading |
| i9, 32 GB | `small.en` | Llama-3.2-3B Q4 | Concurrent | Best Intel experience |

---

## Memory Optimization for Whisper + LLM

Running two ML models simultaneously is HushType's most resource-intensive operation. This section covers strategies for managing unified memory across Whisper and LLM workloads.

### Unified Memory Budgets per Hardware

HushType reserves memory according to the following budgets. The "HushType Budget" is the total memory available for model loading after reserving space for macOS, other apps, and HushType's non-model overhead.

| Total RAM | macOS Reserve | Other Apps Reserve | HushType App Overhead | HushType Model Budget | Budget % |
|---|---|---|---|---|---|
| 8 GB | 2.5 GB | 1.5 GB | 0.3 GB | **3.7 GB** | 46% |
| 16 GB | 3.0 GB | 2.5 GB | 0.3 GB | **10.2 GB** | 64% |
| 24 GB | 3.5 GB | 3.0 GB | 0.3 GB | **17.2 GB** | 72% |
| 32 GB | 4.0 GB | 4.0 GB | 0.3 GB | **23.7 GB** | 74% |
| 64 GB | 5.0 GB | 6.0 GB | 0.3 GB | **52.7 GB** | 82% |
| 128 GB | 6.0 GB | 10.0 GB | 0.3 GB | **111.7 GB** | 87% |

> ⚠️ **Conservative Budgets**: The "Other Apps Reserve" assumes moderate system usage (browser, text editor, communication app). Users running memory-intensive apps (Xcode, Photoshop, DAWs, VMs) should select smaller models than the defaults suggest. HushType monitors actual memory pressure at runtime and will downgrade models dynamically if needed.

### Model Memory Mapping Strategy

HushType uses three memory strategies depending on hardware tier and user preferences:

**Strategy 1: Full mmap (default for 8-16 GB systems)**

```
Whisper model:  mmap'd, pages loaded on demand
LLM model:      mmap'd, pages loaded on demand
Advantage:      OS can reclaim pages under pressure
Disadvantage:   Page faults during inference can cause micro-stutters
```

**Strategy 2: Whisper locked + LLM mmap (recommended for 16-32 GB)**

```
Whisper model:  mmap'd + mlock (pages locked in RAM)
LLM model:      mmap'd, pages loaded on demand
Advantage:      Whisper inference has no page-fault stalls
Disadvantage:   Reduces available pages for LLM and system
```

**Strategy 3: Both locked (recommended for 32 GB+)**

```
Whisper model:  mmap'd + mlock
LLM model:      mmap'd + mlock
Advantage:      Zero page-fault stalls for both models
Disadvantage:   Full model memory always resident in RAM
```

### Sequential vs Concurrent Model Loading

| Strategy | Memory Peak | Latency Impact | Best For |
|---|---|---|---|
| **Concurrent** (both always loaded) | Whisper RAM + LLM RAM | None — both ready instantly | 16 GB+ Apple Silicon |
| **Sequential** (one at a time) | max(Whisper RAM, LLM RAM) | 100-800ms to swap models | 8 GB systems |
| **Lazy LLM** (LLM loads on first use) | Whisper RAM at startup, +LLM later | First post-processing delayed | Any tier, user preference |
| **On-demand** (load only active model) | Single model at a time | 100-800ms each transcription | Extreme memory savings |

> ✅ **Recommended**: Concurrent loading is the default when the memory budget calculator determines both models fit within 60% of total RAM. If the combined memory exceeds this threshold, HushType automatically falls back to Lazy LLM mode.

### Memory Budget Calculator

The following code computes whether selected models fit within the system's memory budget and recommends the appropriate loading strategy.

```swift
import Foundation

/// Calculates whether a combination of Whisper + LLM models fits
/// within the system's memory budget and recommends a loading strategy.
struct MemoryBudgetCalculator {

    /// The result of a memory budget calculation.
    struct BudgetResult: Sendable {
        /// Whether the selected models fit within the budget.
        let fitsInBudget: Bool

        /// Recommended loading strategy.
        let loadingStrategy: LoadingStrategy

        /// Total estimated memory for both models.
        let totalModelMemoryBytes: UInt64

        /// Available memory budget for models.
        let budgetBytes: UInt64

        /// Percentage of total RAM used by models.
        let memoryUsagePercent: Double

        /// Human-readable summary for Settings UI.
        let summary: String

        /// Warnings to display to the user.
        let warnings: [String]
    }

    enum LoadingStrategy: String, Sendable {
        case concurrent    = "Both models loaded simultaneously"
        case lazyLLM       = "LLM loads on first use, then stays resident"
        case sequential    = "Models swap: unload one before loading the other"
        case onDemand      = "Each model loads only when needed, then unloads"
        case whisperOnly   = "LLM disabled — insufficient memory"
    }

    private let hardware: HardwareCapabilities

    init(hardware: HardwareCapabilities) {
        self.hardware = hardware
    }

    /// Calculate the memory budget for a given model combination.
    /// - Parameters:
    ///   - whisperRAM: Estimated RAM for the Whisper model in bytes.
    ///   - llmRAM: Estimated RAM for the LLM model in bytes (0 if no LLM).
    ///   - useMmap: Whether mmap is enabled (reduces effective RAM usage).
    /// - Returns: A `BudgetResult` describing the fit and recommended strategy.
    func calculate(
        whisperRAM: UInt64,
        llmRAM: UInt64,
        useMmap: Bool
    ) -> BudgetResult {
        let totalRAM = hardware.totalMemoryBytes
        let budget = computeBudget(totalRAM: totalRAM)

        // With mmap, effective RAM usage is typically 50-75% of model size
        // because the OS only loads actively-used pages.
        let mmapFactor: Double = useMmap ? 0.65 : 1.0
        let effectiveWhisper = UInt64(Double(whisperRAM) * mmapFactor)
        let effectiveLLM = UInt64(Double(llmRAM) * mmapFactor)
        let totalEffective = effectiveWhisper + effectiveLLM

        let usagePercent = Double(totalEffective) / Double(totalRAM) * 100.0

        var warnings: [String] = []

        // Determine loading strategy.
        let strategy: LoadingStrategy
        if llmRAM == 0 {
            strategy = .whisperOnly
        } else if totalEffective <= UInt64(Double(budget) * 0.60) {
            strategy = .concurrent
        } else if totalEffective <= UInt64(Double(budget) * 0.80) {
            strategy = .lazyLLM
            warnings.append(
                "Models will use \(String(format: "%.0f", usagePercent))% of RAM. "
                + "LLM will load on first use to reduce startup memory."
            )
        } else if max(effectiveWhisper, effectiveLLM) <= budget {
            strategy = .sequential
            warnings.append(
                "Insufficient memory for concurrent loading. "
                + "Models will swap as needed (~300-800ms delay)."
            )
        } else if effectiveWhisper <= budget {
            strategy = .whisperOnly
            warnings.append(
                "Selected LLM is too large for this hardware. "
                + "Consider a smaller LLM model."
            )
        } else {
            strategy = .whisperOnly
            warnings.append(
                "Selected Whisper model may cause memory pressure. "
                + "Consider using a smaller Whisper model."
            )
        }

        let fitsInBudget = strategy != .whisperOnly
            || llmRAM == 0

        let budgetGB = String(
            format: "%.1f", Double(budget) / (1024 * 1024 * 1024)
        )
        let usedGB = String(
            format: "%.1f", Double(totalEffective) / (1024 * 1024 * 1024)
        )

        let summary = """
            Memory budget: \(budgetGB) GB available for models. \
            Selected models: \(usedGB) GB effective. \
            Strategy: \(strategy.rawValue).
            """

        return BudgetResult(
            fitsInBudget: fitsInBudget,
            loadingStrategy: strategy,
            totalModelMemoryBytes: totalEffective,
            budgetBytes: budget,
            memoryUsagePercent: usagePercent,
            summary: summary,
            warnings: warnings
        )
    }

    /// Compute the available budget for ML models.
    private func computeBudget(totalRAM: UInt64) -> UInt64 {
        let totalGB = Double(totalRAM) / (1024 * 1024 * 1024)

        // macOS base memory usage scales roughly with total RAM.
        let macOSReserveGB: Double
        switch totalGB {
        case ..<12:  macOSReserveGB = 2.5
        case ..<20:  macOSReserveGB = 3.0
        case ..<28:  macOSReserveGB = 3.5
        case ..<48:  macOSReserveGB = 4.0
        case ..<96:  macOSReserveGB = 5.0
        default:     macOSReserveGB = 6.0
        }

        // Reserve for other running applications.
        let otherAppsReserveGB: Double
        switch totalGB {
        case ..<12:  otherAppsReserveGB = 1.5
        case ..<20:  otherAppsReserveGB = 2.5
        case ..<28:  otherAppsReserveGB = 3.0
        case ..<48:  otherAppsReserveGB = 4.0
        case ..<96:  otherAppsReserveGB = 6.0
        default:     otherAppsReserveGB = 10.0
        }

        // HushType non-model overhead (UI, audio buffers, SwiftData, etc.)
        let appOverheadGB: Double = 0.3

        let availableGB = max(
            0,
            totalGB - macOSReserveGB - otherAppsReserveGB - appOverheadGB
        )
        return UInt64(availableGB * 1024 * 1024 * 1024)
    }
}
```

### Memory Pressure Response Escalation

HushType implements a multi-stage response to macOS memory pressure events. Each stage is progressively more aggressive in reclaiming memory. See [`../architecture/ARCHITECTURE.md`](../architecture/ARCHITECTURE.md) for the `MemoryPressureMonitor` implementation.

| Level | Trigger | Action | User Impact | Recovery |
|---|---|---|---|---|
| **Level 0** (normal) | Memory pressure: normal | No action | None | N/A |
| **Level 1** (caution) | Model budget > 70% | Disable mlock on LLM | Possible micro-stutters in LLM | Automatic when memory frees |
| **Level 2** (warning) | `DispatchSource` `.warning` | Unload LLM model | No post-processing until re-loaded | Auto-reload on next dictation |
| **Level 3** (critical) | `DispatchSource` `.critical` | Unload both models | Dictation unavailable | User must restart dictation |
| **Level 4** (emergency) | Repeated `.critical` within 60s | Unload + reduce audio buffer to minimum | Degraded audio quality | Requires app restart |

> 🔒 **Safety**: Level 3 and Level 4 actions post a user-visible notification explaining that models were unloaded due to system memory pressure. The notification includes a "Reload Models" button that triggers re-evaluation of the memory budget before reloading.

---

## Disk Space Management for Multiple Models

HushType users may download multiple Whisper and LLM models to switch between quality levels or languages. This section covers storage requirements and management strategies.

### Model File Sizes Reference

All model files are stored in the application support directory:
`~/Library/Application Support/HushType/Models/`

**Whisper Models (GGUF format):**

| Model | File Size | SHA-256 Validated | Notes |
|---|---|---|---|
| `ggml-tiny.bin` | 75 MB | Yes | Smallest, fastest |
| `ggml-tiny.en.bin` | 75 MB | Yes | English-only variant |
| `ggml-base.bin` | 142 MB | Yes | Default for Bronze tier |
| `ggml-base.en.bin` | 142 MB | Yes | English-only variant |
| `ggml-small.bin` | 466 MB | Yes | Default for Silver tier |
| `ggml-small.en.bin` | 466 MB | Yes | English-only variant |
| `ggml-medium.bin` | 1.5 GB | Yes | Default for Gold tier |
| `ggml-medium.en.bin` | 1.5 GB | Yes | English-only variant |
| `ggml-large-v3.bin` | 3.1 GB | Yes | Maximum accuracy |
| `ggml-large-v3-turbo.bin` | 1.6 GB | Yes | Near-large accuracy, faster |

**LLM Models (GGUF format, Q4_K_M quantization):**

| Model | File Size | Notes |
|---|---|---|
| `qwen2.5-0.5b-q4_k_m.gguf` | 400 MB | Minimal LLM |
| `qwen2.5-1.5b-q4_k_m.gguf` | 1.0 GB | Good basic formatting |
| `llama-3.2-1b-q4_k_m.gguf` | 750 MB | Lightweight general-purpose |
| `llama-3.2-3b-q4_k_m.gguf` | 2.0 GB | Silver/Gold default |
| `qwen2.5-3b-q4_k_m.gguf` | 1.9 GB | Multilingual 3B |
| `phi-3-mini-q4_k_m.gguf` | 2.3 GB | Structured output |
| `llama-3.1-8b-q4_k_m.gguf` | 4.7 GB | Gold/Platinum LLM |
| `qwen2.5-7b-q4_k_m.gguf` | 4.6 GB | Multilingual 7B |
| `mistral-7b-q4_k_m.gguf` | 4.4 GB | Creative writing |

### Storage Calculator

The following code provides a storage calculator that HushType uses in the Model Manager UI to show users how much disk space their selected models consume and how much remains.

```swift
import Foundation

/// Tracks and reports disk space usage for HushType model files.
/// Used by the Model Manager settings panel.
actor ModelStorageCalculator {

    /// Storage status for display in Settings UI.
    struct StorageStatus: Sendable {
        /// Total disk space used by HushType models.
        let usedBytes: UInt64

        /// Total available disk space on the volume.
        let availableBytes: UInt64

        /// Total volume capacity.
        let totalVolumeBytes: UInt64

        /// Percentage of volume used by HushType models.
        let usagePercent: Double

        /// Breakdown by model category.
        let whisperBytes: UInt64
        let llmBytes: UInt64

        /// Number of model files.
        let whisperModelCount: Int
        let llmModelCount: Int

        /// Warning level based on available space.
        let warningLevel: StorageWarningLevel

        /// Human-readable summary.
        var summary: String {
            let usedGB = String(
                format: "%.1f", Double(usedBytes) / 1_073_741_824
            )
            let availGB = String(
                format: "%.1f", Double(availableBytes) / 1_073_741_824
            )
            return "\(usedGB) GB used by models, \(availGB) GB available on disk"
        }
    }

    enum StorageWarningLevel: String, Sendable {
        case normal   = "Sufficient disk space"
        case low      = "Disk space getting low"
        case critical = "Critically low disk space"
        case blocked  = "Insufficient disk space for downloads"
    }

    private let modelsDirectory: URL

    init() {
        self.modelsDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        .appendingPathComponent("HushType")
        .appendingPathComponent("Models")
    }

    /// Calculate current storage status.
    func calculateStatus() throws -> StorageStatus {
        let fm = FileManager.default

        // Ensure models directory exists.
        if !fm.fileExists(atPath: modelsDirectory.path) {
            try fm.createDirectory(
                at: modelsDirectory,
                withIntermediateDirectories: true
            )
        }

        // Calculate model sizes by category.
        var whisperBytes: UInt64 = 0
        var llmBytes: UInt64 = 0
        var whisperCount = 0
        var llmCount = 0

        let whisperDir = modelsDirectory.appendingPathComponent("whisper")
        let llmDir = modelsDirectory.appendingPathComponent("llm")

        if fm.fileExists(atPath: whisperDir.path) {
            let whisperFiles = try fm.contentsOfDirectory(
                at: whisperDir,
                includingPropertiesForKeys: [.fileSizeKey]
            )
            for file in whisperFiles {
                let attrs = try file.resourceValues(forKeys: [.fileSizeKey])
                whisperBytes += UInt64(attrs.fileSize ?? 0)
                whisperCount += 1
            }
        }

        if fm.fileExists(atPath: llmDir.path) {
            let llmFiles = try fm.contentsOfDirectory(
                at: llmDir,
                includingPropertiesForKeys: [.fileSizeKey]
            )
            for file in llmFiles {
                let attrs = try file.resourceValues(forKeys: [.fileSizeKey])
                llmBytes += UInt64(attrs.fileSize ?? 0)
                llmCount += 1
            }
        }

        let totalUsed = whisperBytes + llmBytes

        // Get volume space info.
        let volumeInfo = try URL(fileURLWithPath: "/").resourceValues(
            forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeTotalCapacityKey,
            ]
        )
        let available = UInt64(
            volumeInfo.volumeAvailableCapacityForImportantUsage ?? 0
        )
        let totalVolume = UInt64(
            volumeInfo.volumeTotalCapacity ?? 0
        )

        let usagePercent = totalVolume > 0
            ? Double(totalUsed) / Double(totalVolume) * 100.0
            : 0.0

        let warningLevel = classifyWarningLevel(
            availableBytes: available,
            pendingDownloadBytes: 0
        )

        return StorageStatus(
            usedBytes: totalUsed,
            availableBytes: available,
            totalVolumeBytes: totalVolume,
            usagePercent: usagePercent,
            whisperBytes: whisperBytes,
            llmBytes: llmBytes,
            whisperModelCount: whisperCount,
            llmModelCount: llmCount,
            warningLevel: warningLevel
        )
    }

    /// Check if a download of the given size can proceed.
    func canDownload(sizeBytes: UInt64) throws -> (allowed: Bool, reason: String) {
        let status = try calculateStatus()

        // Require at least 2 GB free after download.
        let minimumFreeAfter: UInt64 = 2_147_483_648  // 2 GB
        let freeAfterDownload = status.availableBytes >= sizeBytes
            ? status.availableBytes - sizeBytes
            : 0

        if freeAfterDownload < minimumFreeAfter {
            let neededGB = String(
                format: "%.1f",
                Double(sizeBytes + minimumFreeAfter) / 1_073_741_824
            )
            return (
                false,
                "Need \(neededGB) GB free. Delete unused models or free disk space."
            )
        }

        return (true, "Sufficient disk space available")
    }

    /// Classify warning level based on available space.
    private func classifyWarningLevel(
        availableBytes: UInt64,
        pendingDownloadBytes: UInt64
    ) -> StorageWarningLevel {
        let effectiveAvailable = availableBytes >= pendingDownloadBytes
            ? availableBytes - pendingDownloadBytes
            : 0
        let effectiveGB = Double(effectiveAvailable) / 1_073_741_824

        switch effectiveGB {
        case ..<2:   return .blocked
        case ..<5:   return .critical
        case ..<10:  return .low
        default:     return .normal
        }
    }
}
```

### Cleanup Strategies

HushType provides several model cleanup strategies accessible from Settings > Models > Storage:

| Strategy | Action | When to Use | Space Recovered |
|---|---|---|---|
| **Remove unused models** | Delete models not set as active Whisper or LLM | General cleanup | Varies |
| **Keep only active** | Delete all models except the currently-active Whisper and LLM | Low disk space | Potentially several GB |
| **Remove LLMs** | Delete all LLM models (keep Whisper) | User only needs transcription | 0.4-5+ GB per model |
| **Remove alternative quantizations** | Keep only Q4_K_M, delete other quant variants | Reduce redundancy | Varies |
| **Factory reset models** | Delete all models, re-download defaults for tier | Start fresh | All model storage |

> 💡 **Automatic Cleanup**: HushType never deletes models without user confirmation. However, it does display a persistent banner in the Model Manager UI when `StorageWarningLevel` is `.low` or worse, with a one-tap "Clean Up" action that opens the cleanup strategy picker.

### Model Download Priorities

When a user initiates onboarding or requests multiple model downloads, HushType queues them in priority order:

1. **Active Whisper model** — Required for core functionality. Downloaded first, always.
2. **Active LLM model** — Required for post-processing. Downloaded second.
3. **Alternative Whisper model** — User-requested backup. Queued after active models.
4. **Alternative LLM models** — User-requested alternatives. Lowest priority.

Downloads are resumable. If the app is quit during a download, the partial file is retained and download resumes on next launch. Partial files are stored with a `.partial` extension and are not loaded by the model loader.

### Storage Warning Thresholds

| Available Disk Space | Warning Level | UI Behavior |
|---|---|---|
| > 10 GB | Normal | No warnings |
| 5-10 GB | Low | Yellow banner in Model Manager |
| 2-5 GB | Critical | Red banner in Model Manager, new download confirmation dialog |
| < 2 GB | Blocked | Download buttons disabled, prominent warning |

### Disk Space Monitoring

HushType monitors available disk space periodically and before every download operation.

```swift
import Foundation
import Combine

/// Monitors available disk space and publishes warnings when
/// storage drops below configured thresholds.
final class DiskSpaceMonitor: ObservableObject {

    @Published var currentStatus: ModelStorageCalculator.StorageStatus?
    @Published var warningLevel: ModelStorageCalculator.StorageWarningLevel = .normal

    private let calculator: ModelStorageCalculator
    private var timer: AnyCancellable?

    /// Interval between automatic storage checks (seconds).
    private let checkInterval: TimeInterval = 300  // 5 minutes

    init(calculator: ModelStorageCalculator = ModelStorageCalculator()) {
        self.calculator = calculator
    }

    /// Start periodic disk space monitoring.
    func startMonitoring() {
        // Perform an immediate check.
        Task { await refresh() }

        // Schedule periodic checks.
        timer = Timer.publish(every: checkInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.refresh() }
            }
    }

    /// Stop periodic monitoring.
    func stopMonitoring() {
        timer?.cancel()
        timer = nil
    }

    /// Force a refresh of storage status (call before downloads).
    func refresh() async {
        do {
            let status = try await calculator.calculateStatus()
            await MainActor.run {
                self.currentStatus = status
                self.warningLevel = status.warningLevel
            }
        } catch {
            // Storage check failure is non-fatal.
            // Log but do not surface to user.
            print(
                "[DiskSpaceMonitor] Failed to calculate storage status: "
                + "\(error.localizedDescription)"
            )
        }
    }

    /// Check if a download of the given size can proceed.
    /// Returns a user-facing reason string if blocked.
    func preflightDownload(sizeBytes: UInt64) async -> (allowed: Bool, reason: String) {
        await refresh()
        do {
            return try await calculator.canDownload(sizeBytes: sizeBytes)
        } catch {
            return (false, "Unable to check disk space: \(error.localizedDescription)")
        }
    }
}
```

---

## Supporting New Model Formats and Architectures

As whisper.cpp and llama.cpp evolve, HushType must adapt to new model formats, quantization methods, and API changes. This section provides guidance for developers extending HushType's model support.

### Adding New GGUF Quantizations

When a new GGUF quantization type is added to llama.cpp (e.g., new importance-matrix quantizations), follow this process:

**Step 1: Update the quantization registry.**

```swift
/// Registry of known GGUF quantization types with their properties.
/// Update this when llama.cpp adds new quantization formats.
enum GGUFQuantization: String, CaseIterable, Sendable {
    // Standard quantizations
    case f16     = "F16"
    case q8_0    = "Q8_0"
    case q6_k    = "Q6_K"
    case q5_k_m  = "Q5_K_M"
    case q5_k_s  = "Q5_K_S"
    case q4_k_m  = "Q4_K_M"
    case q4_k_s  = "Q4_K_S"
    case q3_k_m  = "Q3_K_M"
    case q3_k_s  = "Q3_K_S"
    case q2_k    = "Q2_K"

    // Importance-matrix quantizations
    case iq4_xs  = "IQ4_XS"
    case iq3_xxs = "IQ3_XXS"
    case iq2_xxs = "IQ2_XXS"
    case iq1_s   = "IQ1_S"

    // Add new quantizations here as llama.cpp adds them.
    // case newQuant = "NEW_QUANT"

    /// Approximate bits per weight for memory estimation.
    var bitsPerWeight: Double {
        switch self {
        case .f16:     return 16.0
        case .q8_0:    return 8.0
        case .q6_k:    return 6.6
        case .q5_k_m:  return 5.5
        case .q5_k_s:  return 5.5
        case .q4_k_m:  return 4.5
        case .q4_k_s:  return 4.5
        case .q3_k_m:  return 3.4
        case .q3_k_s:  return 3.4
        case .q2_k:    return 2.6
        case .iq4_xs:  return 4.3
        case .iq3_xxs: return 3.1
        case .iq2_xxs: return 2.1
        case .iq1_s:   return 1.6
        }
    }

    /// Human-readable quality rating for Settings UI.
    var qualityRating: String {
        switch bitsPerWeight {
        case 8...:    return "Excellent"
        case 5..<8:   return "Very Good"
        case 4..<5:   return "Good (Recommended)"
        case 3..<4:   return "Acceptable"
        default:      return "Low (emergency only)"
        }
    }

    /// Estimate model RAM usage given parameter count and quantization.
    func estimateRAM(parameterCount: UInt64) -> UInt64 {
        let weightBytes = Double(parameterCount) * bitsPerWeight / 8.0
        let overhead = 1.2  // ~20% overhead for KV cache, activations, etc.
        return UInt64(weightBytes * overhead)
    }
}
```

**Step 2: Update the model download manifest.**

The model manifest is a JSON file bundled with the app and updated via Sparkle auto-updates. Add entries for models using the new quantization:

```json
{
  "models": [
    {
      "id": "llama-3.2-3b-iq4xs",
      "family": "llama",
      "parameters": "3.2B",
      "quantization": "IQ4_XS",
      "fileSize": 1800000000,
      "sha256": "abc123...",
      "downloadURL": "https://huggingface.co/...",
      "minAppVersion": "0.3.0",
      "recommendedTier": "bronze"
    }
  ]
}
```

**Step 3: Test inference quality.** Run the model through HushType's built-in quality benchmarks (Settings > Advanced > Run Benchmark) to verify the new quantization produces acceptable output for each processing mode.

### Supporting New Whisper Variants

When a new Whisper model variant is released (e.g., `large-v4`, `distil-whisper`), add support with these steps:

1. **Verify whisper.cpp compatibility**: Check that the whisper.cpp version bundled with HushType supports the new model's architecture. If not, update whisper.cpp first (see next section).

2. **Add to the Whisper model registry**:

```swift
/// Known Whisper model variants with their capabilities.
struct WhisperModelVariant: Sendable, Identifiable {
    let id: String              // e.g., "large-v3-turbo"
    let displayName: String
    let parameterCount: UInt64
    let multilingual: Bool
    let languages: [String]     // ISO 639-1 codes, empty = all
    let maxAudioLength: TimeInterval  // seconds
    let expectedWER: Double     // on LibriSpeech test-clean
    let fileSize: UInt64        // bytes on disk

    /// All known Whisper variants shipped or downloadable.
    static let allVariants: [WhisperModelVariant] = [
        WhisperModelVariant(
            id: "tiny",
            displayName: "Whisper Tiny",
            parameterCount: 39_000_000,
            multilingual: true,
            languages: [],
            maxAudioLength: 1800,
            expectedWER: 0.077,
            fileSize: 75_000_000
        ),
        // ... add all variants here ...
        // When adding a new variant:
        // WhisperModelVariant(
        //     id: "large-v4",
        //     displayName: "Whisper Large V4",
        //     parameterCount: 1_600_000_000,
        //     multilingual: true,
        //     languages: [],
        //     maxAudioLength: 1800,
        //     expectedWER: 0.018,
        //     fileSize: 3_200_000_000
        // ),
    ]
}
```

3. **Update the recommendation engine**: Add the new variant to `ModelRecommendationEngine` with appropriate tier assignments.

4. **Update performance baselines**: Benchmark the new variant on representative hardware and update the performance matrices in this document.

### Adapting to whisper.cpp and llama.cpp API Changes

HushType wraps whisper.cpp and llama.cpp behind Swift actor interfaces (`WhisperService` and `LLMService`). When upstream APIs change, the adaptation follows a layered approach:

```
┌─────────────────────────────────────────────────────┐
│  Swift Application Code                              │
│  (TranscriptionCoordinator, ModeManager, etc.)       │
│  Does NOT import whisper.h or llama.h directly.      │
├─────────────────────────────────────────────────────┤
│  Swift Service Layer (stable API)                     │
│  WhisperService, LLMService                          │
│  Exposes: transcribe(), process(), loadModel(),      │
│           unloadModel()                              │
│  This layer absorbs upstream API changes.             │
├─────────────────────────────────────────────────────┤
│  Swift Bridge Layer                                   │
│  WhisperBridge.swift, LlamaBridge.swift               │
│  Wraps C function calls in Swift-friendly types.      │
│  OpaquePointer management, error translation.         │
├─────────────────────────────────────────────────────┤
│  C Bridging Header                                    │
│  HushType-Bridging-Header.h                          │
│  #include "whisper.h"                                │
│  #include "llama.h"                                  │
├─────────────────────────────────────────────────────┤
│  C/C++ Libraries (vendored via SPM / CMake)           │
│  whisper.cpp, llama.cpp                              │
│  Updated via git submodule or SPM dependency.         │
└─────────────────────────────────────────────────────┘
```

**Update procedure:**

1. **Update the submodule/SPM dependency** to the new whisper.cpp or llama.cpp version.
2. **Check for compilation errors** in the bridging header and bridge layer.
3. **Update the bridge layer** (`WhisperBridge.swift` / `LlamaBridge.swift`) to adapt to any changed C function signatures, renamed types, or new required parameters.
4. **Run the existing test suite** — the service layer tests should catch behavioral regressions.
5. **Update this document** with any new performance baselines or capabilities.

> ⚠️ **Breaking Changes**: Major version bumps in whisper.cpp and llama.cpp occasionally rename structs or change function signatures. The bridge layer exists specifically to absorb these changes. Never call `whisper_*` or `llama_*` C functions directly from application code — always go through the bridge layer.

### Version Compatibility Matrix

| HushType Version | whisper.cpp Version | llama.cpp Version | GGUF Version | Metal Support | Notes |
|---|---|---|---|---|---|
| 0.1.x | >= 1.5.0 | N/A | v3 | Apple Silicon | MVP, no LLM |
| 0.2.x | >= 1.6.0 | >= b2500 | v3 | Apple Silicon + Intel (limited) | LLM integration |
| 0.3.x | >= 1.7.0 | >= b3000 | v3 | Apple Silicon + Intel (limited) | Smart features |
| 0.4.x | >= 1.7.0 | >= b3000 | v3+ | Apple Silicon + Intel (limited) | Voice commands |
| 0.5.x+ | Latest stable | Latest stable | v3+ | Apple Silicon + Intel (limited) | Plugin system |

> ℹ️ **Version Pinning**: HushType pins specific whisper.cpp and llama.cpp commit hashes in its `Package.swift` / CMake configuration. We do not track `HEAD` of either project in production builds. Version bumps are deliberate, tested, and documented in release notes.

---

## Plugin System Scaling Considerations

HushType's plugin architecture (see [`../architecture/ARCHITECTURE.md`](../architecture/ARCHITECTURE.md) for protocol definitions) is designed to scale from zero plugins to dozens without degrading core dictation performance. This section covers resource management, isolation, and versioning for the plugin ecosystem.

### Plugin Resource Limits

Each plugin operates under strict resource constraints enforced by the `PluginManager` actor:

| Resource | Limit | Enforcement | Violation Action |
|---|---|---|---|
| **Execution time** per invocation | 500ms | `Task` timeout | Plugin output discarded, raw text passed through |
| **Memory allocation** | 50 MB | Monitored via `task_info` | Plugin forcibly deactivated |
| **Disk I/O** | Plugin data directory only | Sandbox profile | I/O operations fail silently |
| **Network access** | None | No entitlement | Connection refused |
| **CPU usage** | QoS `.utility` | GCD scheduling | Deprioritized by OS scheduler |
| **Concurrent instances** | 1 per plugin | Actor isolation | Calls serialized |

```swift
/// Enforces resource limits on plugin execution.
struct PluginResourceGuard {

    /// Maximum time a plugin's `process()` method may take.
    static let maxExecutionTime: Duration = .milliseconds(500)

    /// Maximum memory a plugin may allocate (bytes).
    static let maxMemoryBytes: UInt64 = 50 * 1024 * 1024  // 50 MB

    /// Execute a plugin's process method with resource limits.
    static func executeWithLimits(
        plugin: any HushTypePlugin,
        text: String,
        context: PluginContext,
        hook: PluginHook
    ) async throws -> String {
        // Wrap in a task group with a timeout.
        let result = try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await plugin.process(
                    text: text,
                    context: context,
                    hook: hook
                )
            }

            group.addTask {
                try await Task.sleep(for: Self.maxExecutionTime)
                throw PluginError.timeout(
                    pluginId: type(of: plugin).identifier,
                    limit: Self.maxExecutionTime
                )
            }

            // Return whichever completes first.
            let firstResult = try await group.next()!
            group.cancelAll()
            return firstResult
        }

        return result
    }
}

/// Plugin-specific errors.
enum PluginError: Error, LocalizedError {
    case timeout(pluginId: String, limit: Duration)
    case memoryExceeded(pluginId: String, bytes: UInt64)
    case loadFailure(pluginId: String, reason: String)
    case apiVersionMismatch(
        pluginId: String, required: Int, current: Int
    )

    var errorDescription: String? {
        switch self {
        case .timeout(let id, let limit):
            return "Plugin '\(id)' exceeded \(limit) time limit"
        case .memoryExceeded(let id, let bytes):
            let mb = bytes / (1024 * 1024)
            return "Plugin '\(id)' exceeded \(mb) MB memory limit"
        case .loadFailure(let id, let reason):
            return "Failed to load plugin '\(id)': \(reason)"
        case .apiVersionMismatch(let id, let required, let current):
            return "Plugin '\(id)' requires API v\(required) "
                + "but HushType provides v\(current)"
        }
    }
}
```

### Plugin Sandboxing

Plugins run in a restricted environment that prevents them from interfering with HushType's core operation or accessing user data beyond what is explicitly provided:

| Capability | Allowed | Notes |
|---|---|---|
| Read input text | Yes | The text passed to `process()` |
| Modify output text | Yes | Return value of `process()` |
| Read `PluginContext` | Yes | Mode, language, app bundle ID, audio duration, confidence |
| File system (own data dir) | Yes | `~/Library/Application Support/HushType/Plugins/<id>/` |
| File system (other paths) | No | Blocked by sandbox |
| Network access | No | Zero-network philosophy applies to plugins |
| Access other plugins | No | No inter-plugin communication |
| Access HushType internals | No | Only the `HushTypePlugin` protocol is exposed |
| Modify user settings | No | Plugins cannot alter `UserDefaults` or SwiftData |
| Access audio data | No | Only processed text is provided, never raw audio |
| Access clipboard | No | Clipboard operations are internal to `TextInjectionService` |
| Spawn processes | No | Subprocess execution blocked |

> 🔒 **Privacy Guarantee**: Plugins receive only the transcribed text and metadata — never raw audio buffers. This preserves HushType's privacy-first architecture even when third-party code is involved. A plugin cannot exfiltrate audio because it never receives audio.

### API Versioning

The plugin API is versioned independently from HushType's app version. This allows plugins to specify which API version they require, and HushType to reject incompatible plugins gracefully.

```swift
/// Plugin API version constants.
/// Increment these when making changes to the plugin protocol.
enum PluginAPIVersion {
    /// Current API version provided by this build of HushType.
    static let current: Int = 1

    /// Minimum API version this build can load.
    /// Plugins requiring a version below this are rejected.
    static let minimumSupported: Int = 1

    /// Changelog:
    /// v1 (HushType 0.5.0): Initial plugin API
    ///   - HushTypePlugin protocol
    ///   - 4 pipeline hooks (postTranscription, preLLM, postLLM, preInjection)
    ///   - PluginContext with mode, language, app, duration, confidence
    ///
    /// Future versions (planned):
    /// v2: Add streaming text hook (character-by-character)
    /// v3: Add custom settings panel support
    /// v4: Add inter-plugin communication channel
}

/// Plugin manifest embedded in the plugin bundle's Info.plist.
struct PluginManifest: Codable, Sendable {
    /// Reverse-DNS identifier matching HushTypePlugin.identifier.
    let identifier: String

    /// Human-readable name.
    let displayName: String

    /// Plugin version (semver).
    let version: String

    /// Minimum HushType plugin API version required.
    let minimumAPIVersion: Int

    /// Maximum API version tested against (optional).
    let maximumAPIVersion: Int?

    /// Brief description shown in Settings > Plugins.
    let description: String

    /// Author name.
    let author: String

    /// Plugin homepage URL (optional, for "More Info" link).
    let homepage: String?
}
```

**Compatibility rules:**

| Plugin `minimumAPIVersion` | HushType `PluginAPIVersion.current` | Result |
|---|---|---|
| 1 | 1 | Loaded |
| 1 | 2 | Loaded (backward compatible) |
| 2 | 1 | Rejected with `apiVersionMismatch` error |
| 1 | 1 (but plugin uses unknown hook) | Runtime error, plugin deactivated |

### Plugin Discovery and Loading

Plugins are discovered at app launch from two locations:

1. **Built-in plugins**: `HushType.app/Contents/PlugIns/`
2. **User plugins**: `~/Library/Application Support/HushType/Plugins/`

Each plugin is a macOS bundle (`.hushplugin`) containing:

```
MyPlugin.hushplugin/
├── Contents/
│   ├── Info.plist          (PluginManifest as plist)
│   ├── MacOS/
│   │   └── MyPlugin        (compiled binary)
│   └── Resources/
│       └── icon.png         (optional, 64x64, for Settings UI)
```

The discovery and loading sequence:

1. **Scan** both plugin directories for `.hushplugin` bundles.
2. **Parse** each bundle's `Info.plist` into a `PluginManifest`.
3. **Validate** API version compatibility.
4. **Load** the bundle via `Bundle.init(url:)` and `bundle.load()`.
5. **Instantiate** the principal class (must conform to `HushTypePlugin`).
6. **Activate** by calling `plugin.activate()`.
7. **Register** the plugin's hooks with the `PluginManager`.

Plugins that fail any step are logged and skipped — they do not prevent HushType from launching.

### Plugin Performance Budgets

With multiple plugins active, their cumulative processing time must not exceed the user's perception threshold. HushType enforces a global plugin budget:

| Number of Active Plugins | Per-Plugin Budget | Total Plugin Budget | Impact on Pipeline |
|---|---|---|---|
| 1 | 500ms | 500ms | Negligible |
| 2-3 | 300ms | 600-900ms | Minor, acceptable |
| 4-6 | 200ms | 800-1200ms | Noticeable, warn user |
| 7-10 | 100ms | 700-1000ms | Significant, recommend disabling some |
| 10+ | 50ms | 500ms+ | Aggressive timeouts, likely plugin failures |

> ⚠️ **User Warning**: When more than 3 plugins are active, HushType displays a notice in Settings > Plugins: "Multiple active plugins may increase processing time. If dictation feels slow, try disabling plugins you don't need." The per-plugin timeout is dynamically reduced based on the number of active plugins to keep total plugin time under 1 second.

```swift
/// Calculates the per-plugin execution timeout based on
/// the number of currently active plugins.
func perPluginTimeout(activePluginCount: Int) -> Duration {
    switch activePluginCount {
    case 0...1: return .milliseconds(500)
    case 2...3: return .milliseconds(300)
    case 4...6: return .milliseconds(200)
    case 7...10: return .milliseconds(100)
    default: return .milliseconds(50)
    }
}
```

---

## Related Documentation

| Document | Relevance |
|---|---|
| [`../architecture/ARCHITECTURE.md`](../architecture/ARCHITECTURE.md) | Memory management strategy, model lifecycle, plugin protocol definitions, thread architecture |
| [`../features/MODEL_MANAGEMENT.md`](../features/MODEL_MANAGEMENT.md) | Model download UI, user-facing model switching, storage display |
| [`../reference/PERFORMANCE_OPTIMIZATION.md`](../reference/PERFORMANCE_OPTIMIZATION.md) | Audio pipeline optimization, inference tuning parameters, latency profiling |
| [`../architecture/TECH_STACK.md`](../architecture/TECH_STACK.md) | Technology choices, Apple Silicon vs Intel comparison, version compatibility |
| [`../reference/ROADMAP.md`](../reference/ROADMAP.md) | Phase 5 plugin system plans, performance optimization milestones |
| [`../security/SECURITY.md`](../security/SECURITY.md) | Plugin sandboxing threat model, model file integrity validation |
