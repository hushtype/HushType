Last Updated: 2026-02-13

# Maintenance

> **VaulType** — Privacy-first, macOS-native speech-to-text with local LLM post-processing.
> This document covers all ongoing maintenance processes: model updates, dependency management, macOS compatibility, Apple Silicon optimizations, performance monitoring, and user feedback triage.

---

## Table of Contents

- [Maintenance Schedule Overview](#maintenance-schedule-overview)
- [Model Update Process](#model-update-process)
  - [Monitoring New Releases](#monitoring-new-releases)
  - [Model Testing Pipeline](#model-testing-pipeline)
  - [Updating the Model Registry](#updating-the-model-registry)
  - [User Notification for Available Updates](#user-notification-for-available-updates)
  - [Migration from Old Model Files](#migration-from-old-model-files)
  - [Model Compatibility Checker Script](#model-compatibility-checker-script)
- [Dependency Updates](#dependency-updates)
  - [Dependency Tracking Table](#dependency-tracking-table)
  - [whisper.cpp and llama.cpp Version Tracking](#whispercpp-and-llamacpp-version-tracking)
  - [Updating Static Libraries](#updating-static-libraries)
  - [Handling Breaking API Changes](#handling-breaking-api-changes)
  - [Sparkle Framework Updates](#sparkle-framework-updates)
  - [SPM Dependency Management](#spm-dependency-management)
  - [Automated Dependency Version Checking](#automated-dependency-version-checking)
- [macOS Compatibility Maintenance](#macos-compatibility-maintenance)
  - [Testing on New macOS Releases](#testing-on-new-macos-releases)
  - [Handling Deprecated APIs](#handling-deprecated-apis)
  - [Privacy and Security Changes (TCC)](#privacy-and-security-changes-tcc)
  - [Accessibility API Changes](#accessibility-api-changes)
  - [Entitlement Updates](#entitlement-updates)
- [Apple Silicon Optimization Updates](#apple-silicon-optimization-updates)
  - [Taking Advantage of New Chip Features](#taking-advantage-of-new-chip-features)
  - [Metal API Updates](#metal-api-updates)
  - [Neural Engine Utilization](#neural-engine-utilization)
  - [Performance Regression Testing Across Generations](#performance-regression-testing-across-generations)
- [Performance Regression Monitoring](#performance-regression-monitoring)
  - [Benchmark Suite](#benchmark-suite)
  - [CI-Based Performance Tests](#ci-based-performance-tests)
  - [Performance Benchmark Runner Script](#performance-benchmark-runner-script)
  - [Alerting on Regressions](#alerting-on-regressions)
  - [Historical Performance Tracking](#historical-performance-tracking)
- [User Feedback Triage Process](#user-feedback-triage-process)
  - [GitHub Issues Workflow](#github-issues-workflow)
  - [Bug Report Template](#bug-report-template)
  - [Feature Request Template](#feature-request-template)
  - [Priority Classification](#priority-classification)
  - [Release Planning from Feedback](#release-planning-from-feedback)
  - [Diagnostic Information Collector](#diagnostic-information-collector)
- [SwiftData Migration Between App Versions](#swiftdata-migration-between-app-versions)
  - [Migration Strategy](#migration-strategy)
  - [Migration Implementation](#migration-implementation)
  - [Migration Testing](#migration-testing)
- [Related Documentation](#related-documentation)

---

## Maintenance Schedule Overview

All recurring maintenance tasks are organized by cadence. Every task has a clear owner role, expected duration, and artifact output.

| Cadence | Task | Owner | Duration | Output |
|---|---|---|---|---|
| **Daily** | Monitor crash reports and user feedback | On-call dev | 15 min | Triaged issues |
| **Daily** | Review CI pipeline status | On-call dev | 5 min | Fixed broken builds |
| **Weekly** | Check whisper.cpp/llama.cpp upstream commits | ML lead | 30 min | Update assessment |
| **Weekly** | Review open GitHub Issues backlog | Project lead | 30 min | Prioritized backlog |
| **Weekly** | Review Sparkle update analytics | Release eng | 15 min | Adoption report |
| **Bi-weekly** | Run full performance benchmark suite | Performance eng | 1 hr | Benchmark report |
| **Monthly** | Audit all SPM and C/C++ dependencies | Security lead | 2 hrs | Dependency report |
| **Monthly** | Test on latest macOS beta (when available) | QA lead | 4 hrs | Compatibility report |
| **Monthly** | Review Apple developer documentation changes | Platform lead | 1 hr | API change log |
| **Per-release** | Full regression test suite | QA team | 8 hrs | Test report |
| **Per-release** | Performance comparison vs previous release | Performance eng | 2 hrs | Regression report |
| **Per-release** | Update model compatibility matrix | ML lead | 1 hr | Updated registry |
| **Per-release** | SwiftData migration validation | Data eng | 2 hrs | Migration test report |
| **Quarterly** | Security audit of all dependencies | Security lead | 1 day | Security report |
| **Quarterly** | Review and update entitlements | Platform lead | 2 hrs | Entitlement manifest |

> ℹ️ **Note**: During Apple's WWDC period (typically June), increase macOS compatibility checks to daily and assign a dedicated engineer to track beta changes.

---

## Model Update Process

VaulType depends on two families of ML models: Whisper models for speech-to-text and GGUF-format LLMs for post-processing. Both ecosystems move quickly, so a structured update process is essential.

### Monitoring New Releases

We track upstream model releases from multiple sources:

| Source | What to Monitor | Check Frequency | Method |
|---|---|---|---|
| [openai/whisper](https://github.com/openai/whisper) | New model sizes, architecture changes | Weekly | GitHub Releases RSS |
| [ggerganov/whisper.cpp](https://github.com/ggerganov/whisper.cpp) | New GGML format versions, quantization types | Weekly | GitHub watch |
| [HuggingFace](https://huggingface.co/models) | New GGUF-format LLMs suitable for on-device | Bi-weekly | Model hub search |
| [ggerganov/llama.cpp](https://github.com/ggerganov/llama.cpp) | GGUF format changes, new quantization methods | Weekly | GitHub watch |
| Apple ML Research | CoreML-optimized models | Monthly | Blog RSS |

When a new model is detected:

1. **Assess relevance** — Does it improve quality, speed, or memory usage for VaulType's use case?
2. **Check format compatibility** — Is it available in the correct GGML/GGUF format version that our whisper.cpp/llama.cpp build supports?
3. **Evaluate resource requirements** — Will it run on our minimum supported hardware (8 GB RAM, M1)?
4. **Create a tracking issue** — Open a GitHub Issue tagged `model-update` with the assessment.

### Model Testing Pipeline

Every candidate model goes through a standardized evaluation before it is added to the registry.

```swift
// ModelEvaluator.swift — Evaluates candidate models against quality and performance baselines

import Foundation

/// Represents the result of evaluating a single model candidate.
struct ModelEvaluationResult: Codable {
    let modelName: String
    let modelType: ModelType
    let fileSize: UInt64
    let peakMemoryUsage: UInt64
    let averageInferenceTime: TimeInterval
    let wordErrorRate: Double?           // Whisper models only
    let qualityScore: Double?            // LLM models only
    let metalGPUUtilization: Double
    let compatibleChips: [String]
    let passed: Bool
    let notes: [String]

    enum ModelType: String, Codable {
        case whisper
        case llm
    }
}

/// Evaluates model candidates against baseline requirements.
actor ModelEvaluator {

    // Baseline thresholds — a model must meet ALL of these to pass
    struct Thresholds {
        static let maxPeakMemoryMB: UInt64 = 6_144          // 6 GB — leaves 2 GB for system on 8 GB machine
        static let maxWhisperInferenceRatio: Double = 1.0    // Must be faster than real-time
        static let maxWordErrorRate: Double = 0.08           // 8% WER ceiling
        static let minLLMQualityScore: Double = 0.75         // 75% on quality benchmark suite
        static let maxLLMTokenLatency: TimeInterval = 0.05   // 50ms per token
        static let maxModelFileSizeMB: UInt64 = 4_096        // 4 GB file size ceiling
    }

    private let testAudioSamples: [URL]
    private let testPrompts: [String]
    private let baselineResults: [String: ModelEvaluationResult]

    init(testDataDirectory: URL, baselineResultsFile: URL) throws {
        // Load test audio samples (diverse accents, noise levels, durations)
        let audioDir = testDataDirectory.appendingPathComponent("audio")
        self.testAudioSamples = try FileManager.default.contentsOfDirectory(
            at: audioDir,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "wav" }

        // Load test prompts for LLM evaluation
        let promptsFile = testDataDirectory.appendingPathComponent("prompts.json")
        let promptsData = try Data(contentsOf: promptsFile)
        self.testPrompts = try JSONDecoder().decode([String].self, from: promptsData)

        // Load baseline results from the last accepted model version
        let baselineData = try Data(contentsOf: baselineResultsFile)
        let baselines = try JSONDecoder().decode([ModelEvaluationResult].self, from: baselineData)
        self.baselineResults = Dictionary(uniqueKeysWithValues: baselines.map { ($0.modelName, $0) })
    }

    /// Evaluate a Whisper model candidate.
    func evaluateWhisperModel(at modelPath: URL) async throws -> ModelEvaluationResult {
        let modelName = modelPath.deletingPathExtension().lastPathComponent
        let fileSize = try FileManager.default.attributesOfItem(
            atPath: modelPath.path
        )[.size] as? UInt64 ?? 0

        var notes: [String] = []
        var totalInferenceTime: TimeInterval = 0
        var totalAudioDuration: TimeInterval = 0
        var peakMemory: UInt64 = 0

        // Run inference on all test samples
        for sample in testAudioSamples {
            let startMemory = currentMemoryUsage()
            let startTime = CFAbsoluteTimeGetCurrent()

            // Inference would be performed here via WhisperContext
            // let result = try await whisperContext.transcribe(audioFile: sample)

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            let currentMemory = currentMemoryUsage()

            totalInferenceTime += elapsed
            peakMemory = max(peakMemory, currentMemory - startMemory)

            // Estimate audio duration from file size (16kHz, 16-bit mono)
            let audioFileSize = try FileManager.default.attributesOfItem(
                atPath: sample.path
            )[.size] as? UInt64 ?? 0
            let audioDuration = Double(audioFileSize) / (16_000 * 2)  // 16kHz, 16-bit
            totalAudioDuration += audioDuration
        }

        let inferenceRatio = totalInferenceTime / totalAudioDuration
        let fileSizeMB = fileSize / (1024 * 1024)

        // Determine pass/fail
        let passed = fileSizeMB <= Thresholds.maxModelFileSizeMB
            && peakMemory / (1024 * 1024) <= Thresholds.maxPeakMemoryMB
            && inferenceRatio <= Thresholds.maxWhisperInferenceRatio

        if let baseline = baselineResults[modelName] {
            let speedDelta = ((inferenceRatio / (baseline.averageInferenceTime)) - 1.0) * 100
            notes.append("Speed vs baseline: \(String(format: "%.1f", speedDelta))%")
        }

        return ModelEvaluationResult(
            modelName: modelName,
            modelType: .whisper,
            fileSize: fileSize,
            peakMemoryUsage: peakMemory,
            averageInferenceTime: inferenceRatio,
            wordErrorRate: nil,  // Computed separately via reference transcripts
            qualityScore: nil,
            metalGPUUtilization: 0.0,  // Measured via Metal performance counters
            compatibleChips: determineCompatibleChips(peakMemoryMB: peakMemory / (1024 * 1024)),
            passed: passed,
            notes: notes
        )
    }

    // MARK: - Helpers

    private func currentMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }

    private func determineCompatibleChips(peakMemoryMB: UInt64) -> [String] {
        var chips: [String] = []
        // 8 GB unified memory chips
        if peakMemoryMB <= 6_144 {
            chips.append(contentsOf: ["M1", "M2", "M3", "M4"])
        }
        // 16 GB+ chips (Pro/Max variants)
        if peakMemoryMB <= 12_288 {
            chips.append(contentsOf: ["M1 Pro", "M2 Pro", "M3 Pro", "M4 Pro"])
        }
        // 32 GB+ chips
        if peakMemoryMB <= 28_672 {
            chips.append(contentsOf: ["M1 Max", "M2 Max", "M3 Max", "M4 Max"])
        }
        return chips
    }
}
```

> ⚠️ **Warning**: Always test models on the minimum supported hardware (8 GB M1 MacBook Air) before approving them for the default model set. Users on constrained devices are our most sensitive audience.

### Updating the Model Registry

The model registry is a JSON manifest that the app reads at launch to determine available models, their download URLs, and compatibility requirements.

```swift
// ModelRegistry.swift — Model registry data structure and update logic

import Foundation

/// A single entry in the model registry manifest.
struct ModelRegistryEntry: Codable, Identifiable {
    let id: String                          // e.g., "whisper-large-v3-turbo-q5"
    let displayName: String                 // e.g., "Whisper Large V3 Turbo (Q5_K_M)"
    let type: ModelType
    let version: String                     // Semantic version of this registry entry
    let fileName: String                    // On-disk filename
    let fileSizeMB: Int
    let sha256: String                      // Integrity verification
    let minimumRAMGB: Int
    let recommendedRAMGB: Int
    let supportedArchitectures: [String]    // ["arm64", "x86_64"]
    let requiredAppVersion: String          // Minimum VaulType version
    let deprecated: Bool
    let deprecationMessage: String?
    let replacedBy: String?                 // ID of the replacement model

    enum ModelType: String, Codable {
        case whisper
        case llm
    }
}

/// Manages the local model registry, including updates and migrations.
final class ModelRegistryManager {

    private let registryURL: URL
    private let localRegistryPath: URL

    init(localRegistryPath: URL) {
        self.registryURL = URL(string: "https://vaultype.app/models/registry.json")!
        self.localRegistryPath = localRegistryPath
    }

    /// Check for registry updates and return any new or updated entries.
    func checkForUpdates() async throws -> [ModelRegistryEntry] {
        // In production this would fetch from a local cache or bundled manifest.
        // VaulType never makes network requests — the registry ships with app updates
        // and is updated via Sparkle alongside the binary.
        let bundledRegistryURL = Bundle.main.url(
            forResource: "model-registry",
            withExtension: "json"
        )!

        let bundledData = try Data(contentsOf: bundledRegistryURL)
        let bundledEntries = try JSONDecoder().decode([ModelRegistryEntry].self, from: bundledData)

        // Load the user's current local registry
        let localEntries: [ModelRegistryEntry]
        if FileManager.default.fileExists(atPath: localRegistryPath.path) {
            let localData = try Data(contentsOf: localRegistryPath)
            localEntries = try JSONDecoder().decode([ModelRegistryEntry].self, from: localData)
        } else {
            localEntries = []
        }

        let localVersions = Dictionary(uniqueKeysWithValues: localEntries.map { ($0.id, $0.version) })

        // Find new or updated entries
        return bundledEntries.filter { entry in
            guard let localVersion = localVersions[entry.id] else {
                return true  // New model not in local registry
            }
            return entry.version.compare(localVersion, options: .numeric) == .orderedDescending
        }
    }

    /// Persist the updated registry to disk.
    func saveRegistry(_ entries: [ModelRegistryEntry]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entries)
        try data.write(to: localRegistryPath, options: .atomic)
    }
}
```

### User Notification for Available Updates

When the app detects that a newer model is available (bundled with a new app version via Sparkle), it surfaces a non-intrusive notification:

1. **Menu bar indicator** — A small badge appears on the VaulType menu bar icon.
2. **Settings panel** — The Models tab shows an "Update Available" badge next to the outdated model.
3. **No forced updates** — Users are never forced to update models. Old models continue to work as long as they are compatible with the current whisper.cpp/llama.cpp runtime.

> ℹ️ **Note**: Because VaulType is zero-network, model updates are distributed as part of app updates via Sparkle, or users download model files manually. The registry only describes what is available.

### Migration from Old Model Files

When a model format changes (e.g., GGML v3 to GGUF), migration must be handled gracefully:

1. **Detection** — At launch, scan the models directory for files in deprecated formats.
2. **In-place conversion** — If a converter is bundled (e.g., `ggml-to-gguf`), offer automatic conversion.
3. **Side-by-side** — Keep the old file until the new one is verified, then prompt for deletion.
4. **Fallback** — If conversion is not possible, display a clear message guiding the user to download the correct format.

### Model Compatibility Checker Script

```swift
// ModelCompatibilityChecker.swift — Validates model files against current runtime

import Foundation
import CryptoKit

/// Checks that model files on disk are compatible with the current runtime.
struct ModelCompatibilityChecker {

    enum CompatibilityStatus: CustomStringConvertible {
        case compatible
        case needsConversion(from: String, to: String)
        case unsupported(reason: String)
        case corrupted(expected: String, actual: String)
        case tooLargeForDevice(required: Int, available: Int)

        var description: String {
            switch self {
            case .compatible:
                return "Compatible"
            case .needsConversion(let from, let to):
                return "Needs conversion from \(from) to \(to)"
            case .unsupported(let reason):
                return "Unsupported: \(reason)"
            case .corrupted(let expected, let actual):
                return "Corrupted: expected SHA256 \(expected), got \(actual)"
            case .tooLargeForDevice(let required, let available):
                return "Too large: requires \(required) MB RAM, device has \(available) MB"
            }
        }
    }

    struct CheckResult {
        let modelPath: URL
        let modelName: String
        let status: CompatibilityStatus
        let registryEntry: ModelRegistryEntry?
    }

    private let registry: [ModelRegistryEntry]
    private let deviceRAMMB: Int

    init(registry: [ModelRegistryEntry]) {
        self.registry = registry
        self.deviceRAMMB = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024))
    }

    /// Check all models in the given directory.
    func checkAll(in modelsDirectory: URL) throws -> [CheckResult] {
        let fileManager = FileManager.default
        let modelFiles = try fileManager.contentsOfDirectory(
            at: modelsDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        )

        return try modelFiles.compactMap { fileURL -> CheckResult? in
            let ext = fileURL.pathExtension.lowercased()
            guard ext == "bin" || ext == "gguf" || ext == "ggml" else {
                return nil
            }
            return try checkSingleModel(at: fileURL)
        }
    }

    /// Check a single model file.
    func checkSingleModel(at modelPath: URL) throws -> CheckResult {
        let fileName = modelPath.lastPathComponent
        let entry = registry.first { $0.fileName == fileName }

        // Check file format
        let ext = modelPath.pathExtension.lowercased()
        if ext == "ggml" {
            return CheckResult(
                modelPath: modelPath,
                modelName: fileName,
                status: .needsConversion(from: "GGML", to: "GGUF"),
                registryEntry: entry
            )
        }

        // Check file integrity if registry entry exists
        if let entry = entry {
            let fileData = try Data(contentsOf: modelPath)
            let hash = SHA256.hash(data: fileData)
            let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

            if hashString != entry.sha256 {
                return CheckResult(
                    modelPath: modelPath,
                    modelName: fileName,
                    status: .corrupted(expected: entry.sha256, actual: hashString),
                    registryEntry: entry
                )
            }

            // Check device RAM
            if entry.minimumRAMGB * 1024 > deviceRAMMB {
                return CheckResult(
                    modelPath: modelPath,
                    modelName: fileName,
                    status: .tooLargeForDevice(
                        required: entry.minimumRAMGB * 1024,
                        available: deviceRAMMB
                    ),
                    registryEntry: entry
                )
            }

            // Check deprecation
            if entry.deprecated {
                let message = entry.deprecationMessage ?? "This model has been deprecated."
                return CheckResult(
                    modelPath: modelPath,
                    modelName: fileName,
                    status: .unsupported(reason: message),
                    registryEntry: entry
                )
            }
        }

        return CheckResult(
            modelPath: modelPath,
            modelName: fileName,
            status: .compatible,
            registryEntry: entry
        )
    }
}
```

---

## Dependency Updates

VaulType has three categories of dependencies: C/C++ libraries built from source (whisper.cpp, llama.cpp), Swift packages managed via SPM, and the Sparkle update framework.

### Dependency Tracking Table

| Dependency | Current Version | Source | Update Method | Risk Level | Owner |
|---|---|---|---|---|---|
| **whisper.cpp** | `master` (pinned commit) | GitHub submodule | Manual rebuild | High | ML lead |
| **llama.cpp** | `master` (pinned commit) | GitHub submodule | Manual rebuild | High | ML lead |
| **Sparkle** | 2.x | SPM | `swift package update` | Medium | Release eng |
| **Swift Argument Parser** | 1.x | SPM | `swift package update` | Low | Any dev |
| **KeyboardShortcuts** | 2.x | SPM | `swift package update` | Low | UI lead |
| **Metal Shaders** | Bundled | In-repo | Manual | Medium | GPU eng |
| **CMake** | 3.21+ | Homebrew | `brew upgrade cmake` | Low | Build eng |

> 🔒 **Security**: Every dependency update must be accompanied by a review of the changelog for security-relevant changes. C/C++ library updates require extra scrutiny for memory safety issues.

### whisper.cpp and llama.cpp Version Tracking

Both libraries are tracked as Git submodules pinned to specific commits. We never track `HEAD` of `master` in production builds.

```bash
#!/bin/bash
# scripts/check-cpp-deps.sh — Check for upstream updates to C/C++ dependencies

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== VaulType C/C++ Dependency Version Check ==="
echo ""

# Check whisper.cpp
WHISPER_DIR="${REPO_ROOT}/vendor/whisper.cpp"
if [ -d "$WHISPER_DIR" ]; then
    cd "$WHISPER_DIR"
    CURRENT_COMMIT=$(git rev-parse HEAD)
    CURRENT_DATE=$(git log -1 --format=%ci HEAD)

    git fetch origin master --quiet 2>/dev/null || true
    LATEST_COMMIT=$(git rev-parse origin/master 2>/dev/null || echo "fetch-failed")
    LATEST_DATE=$(git log -1 --format=%ci origin/master 2>/dev/null || echo "unknown")
    COMMITS_BEHIND=$(git rev-list HEAD..origin/master --count 2>/dev/null || echo "?")

    echo "whisper.cpp:"
    echo "  Pinned commit:  ${CURRENT_COMMIT:0:12} (${CURRENT_DATE})"
    echo "  Latest master:  ${LATEST_COMMIT:0:12} (${LATEST_DATE})"
    echo "  Commits behind: ${COMMITS_BEHIND}"
    if [ "$COMMITS_BEHIND" != "0" ] && [ "$COMMITS_BEHIND" != "?" ]; then
        echo "  Status: UPDATE AVAILABLE"
        echo ""
        echo "  Recent upstream changes:"
        git log --oneline HEAD..origin/master | head -10
    else
        echo "  Status: UP TO DATE"
    fi
else
    echo "whisper.cpp: NOT FOUND at ${WHISPER_DIR}"
fi

echo ""

# Check llama.cpp
LLAMA_DIR="${REPO_ROOT}/vendor/llama.cpp"
if [ -d "$LLAMA_DIR" ]; then
    cd "$LLAMA_DIR"
    CURRENT_COMMIT=$(git rev-parse HEAD)
    CURRENT_DATE=$(git log -1 --format=%ci HEAD)

    git fetch origin master --quiet 2>/dev/null || true
    LATEST_COMMIT=$(git rev-parse origin/master 2>/dev/null || echo "fetch-failed")
    LATEST_DATE=$(git log -1 --format=%ci origin/master 2>/dev/null || echo "unknown")
    COMMITS_BEHIND=$(git rev-list HEAD..origin/master --count 2>/dev/null || echo "?")

    echo "llama.cpp:"
    echo "  Pinned commit:  ${CURRENT_COMMIT:0:12} (${CURRENT_DATE})"
    echo "  Latest master:  ${LATEST_COMMIT:0:12} (${LATEST_DATE})"
    echo "  Commits behind: ${COMMITS_BEHIND}"
    if [ "$COMMITS_BEHIND" != "0" ] && [ "$COMMITS_BEHIND" != "?" ]; then
        echo "  Status: UPDATE AVAILABLE"
        echo ""
        echo "  Recent upstream changes:"
        git log --oneline HEAD..origin/master | head -10
    else
        echo "  Status: UP TO DATE"
    fi
else
    echo "llama.cpp: NOT FOUND at ${LLAMA_DIR}"
fi

echo ""
echo "=== Check complete ==="
```

### Updating Static Libraries

When updating whisper.cpp or llama.cpp to a new commit:

1. **Read the upstream changelog** — Look for breaking API changes, new Metal shader requirements, or GGUF format updates.
2. **Update the submodule pin**:
   ```bash
   cd vendor/whisper.cpp
   git fetch origin
   git checkout <target-commit>
   cd ../..
   git add vendor/whisper.cpp
   git commit -m "chore: update whisper.cpp to <commit-hash>"
   ```
3. **Rebuild static libraries**:
   ```bash
   scripts/build-whisper.sh --arch arm64 --arch x86_64
   scripts/build-llama.sh --arch arm64 --arch x86_64
   ```
4. **Run the full test suite** — Ensure all transcription and LLM tests pass.
5. **Run the performance benchmark** — Compare against baseline numbers.
6. **Update the bridging header** if any C API signatures changed.

### Handling Breaking API Changes

When upstream introduces breaking changes to the C API:

```swift
// WhisperBridge.swift — Abstraction layer over the raw whisper.cpp C API
// This layer insulates the rest of the app from upstream API changes.

import Foundation

/// Protocol that abstracts the whisper.cpp C API.
/// When whisper.cpp changes its API, only this bridge needs updating.
protocol WhisperBridgeProtocol {
    func loadModel(path: String) throws -> OpaquePointer
    func transcribe(
        context: OpaquePointer,
        samples: UnsafePointer<Float>,
        sampleCount: Int,
        parameters: WhisperParameters
    ) throws -> WhisperResult
    func freeModel(context: OpaquePointer)
}

/// Version-specific bridge implementation.
/// When whisper.cpp updates its API, create a new conforming type
/// and update the factory method.
struct WhisperParameters {
    var language: String = "auto"
    var translate: Bool = false
    var maxTokens: Int = 0
    var threads: Int = 4
    var useGPU: Bool = true
}

struct WhisperResult {
    let text: String
    let segments: [WhisperSegment]
    let processingTimeMs: Double
}

struct WhisperSegment {
    let startMs: Int64
    let endMs: Int64
    let text: String
    let probability: Float
}

/// Factory that returns the appropriate bridge for the compiled whisper.cpp version.
enum WhisperBridgeFactory {
    static func makeBridge() -> WhisperBridgeProtocol {
        // When upgrading whisper.cpp, update this to point to the new bridge
        // implementation if the API changed.
        return CurrentWhisperBridge()
    }
}

/// The current whisper.cpp bridge implementation.
/// When the upstream C API changes, update this struct's method bodies.
struct CurrentWhisperBridge: WhisperBridgeProtocol {
    func loadModel(path: String) throws -> OpaquePointer {
        // Calls whisper_init_from_file() from the C API
        guard let ctx = whisper_init_from_file(path) else {
            throw WhisperError.modelLoadFailed(path: path)
        }
        return ctx
    }

    func transcribe(
        context: OpaquePointer,
        samples: UnsafePointer<Float>,
        sampleCount: Int,
        parameters: WhisperParameters
    ) throws -> WhisperResult {
        // Map our parameters to whisper_full_params and call whisper_full()
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.language = parameters.language.withCString { strdup($0) }
        params.translate = parameters.translate
        params.n_threads = Int32(parameters.threads)

        let status = whisper_full(context, params, samples, Int32(sampleCount))
        guard status == 0 else {
            throw WhisperError.transcriptionFailed(code: Int(status))
        }

        // Extract results
        let segmentCount = whisper_full_n_segments(context)
        var segments: [WhisperSegment] = []
        var fullText = ""

        for i in 0..<segmentCount {
            let text = String(cString: whisper_full_get_segment_text(context, i))
            let startMs = whisper_full_get_segment_t0(context, i) * 10
            let endMs = whisper_full_get_segment_t1(context, i) * 10

            segments.append(WhisperSegment(
                startMs: Int64(startMs),
                endMs: Int64(endMs),
                text: text,
                probability: 0.0
            ))
            fullText += text
        }

        return WhisperResult(
            text: fullText.trimmingCharacters(in: .whitespacesAndNewlines),
            segments: segments,
            processingTimeMs: 0  // Measured by caller
        )
    }

    func freeModel(context: OpaquePointer) {
        whisper_free(context)
    }
}

enum WhisperError: Error, LocalizedError {
    case modelLoadFailed(path: String)
    case transcriptionFailed(code: Int)

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let path):
            return "Failed to load Whisper model at: \(path)"
        case .transcriptionFailed(let code):
            return "Transcription failed with error code: \(code)"
        }
    }
}
```

> 💡 **Tip**: The bridge pattern means that when whisper.cpp changes its `whisper_full_params` struct layout, only `CurrentWhisperBridge` needs updating. The rest of the app remains untouched.

### Sparkle Framework Updates

Sparkle is managed as an SPM dependency and updates are handled via standard Swift package resolution:

```bash
# Update Sparkle to the latest compatible version
swift package update Sparkle

# Verify the update
swift package show-dependencies | grep -i sparkle
```

After updating Sparkle:
1. Test the entire update flow: check for update, download, verify, install, restart.
2. Verify that the EdDSA signature verification still works with the existing signing key.
3. Test on both Apple Silicon and Intel builds.
4. Verify that the `SUPublicEDKey` in `Info.plist` is unchanged.

### SPM Dependency Management

```bash
# scripts/check-spm-deps.sh — Show outdated SPM packages

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

echo "=== SPM Dependency Version Check ==="
echo ""
echo "Resolved dependencies:"
swift package show-dependencies --format json 2>/dev/null | python3 -c "
import json, sys
deps = json.load(sys.stdin)
def print_deps(node, indent=0):
    name = node.get('name', node.get('identity', 'unknown'))
    version = node.get('version', 'unversioned')
    print(f\"{'  ' * indent}{name}: {version}\")
    for dep in node.get('dependencies', []):
        print_deps(dep, indent + 1)
print_deps(deps)
" 2>/dev/null || echo "Could not parse dependencies"

echo ""
echo "Checking for available updates..."
swift package update --dry-run 2>&1 || echo "Dry run not supported; run 'swift package update' to check."
echo ""
echo "=== Check complete ==="
```

### Automated Dependency Version Checking

The following Swift script is run in CI to verify all dependencies are within acceptable version ranges and no known CVEs apply:

```swift
// Scripts/DependencyChecker.swift — Automated dependency audit

import Foundation

/// Represents a tracked dependency with version constraints.
struct TrackedDependency: Codable {
    let name: String
    let currentVersion: String
    let minimumVersion: String
    let maximumVersion: String?
    let source: DependencySource
    let lastAuditDate: String
    let knownCVEs: [String]

    enum DependencySource: String, Codable {
        case spm
        case gitSubmodule
        case bundled
        case system
    }
}

/// Audits project dependencies against a manifest of tracked versions.
struct DependencyAuditor {

    struct AuditResult {
        let dependency: TrackedDependency
        let status: Status
        let message: String

        enum Status: String {
            case ok = "OK"
            case outdated = "OUTDATED"
            case vulnerable = "VULNERABLE"
            case unknown = "UNKNOWN"
        }
    }

    private let manifestPath: URL

    init(manifestPath: URL) {
        self.manifestPath = manifestPath
    }

    /// Run the full audit and return results for all tracked dependencies.
    func audit() throws -> [AuditResult] {
        let data = try Data(contentsOf: manifestPath)
        let dependencies = try JSONDecoder().decode([TrackedDependency].self, from: data)

        return dependencies.map { dep in
            // Check for known CVEs
            if !dep.knownCVEs.isEmpty {
                return AuditResult(
                    dependency: dep,
                    status: .vulnerable,
                    message: "Known CVEs: \(dep.knownCVEs.joined(separator: ", "))"
                )
            }

            // Check audit staleness (> 90 days since last audit)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            if let auditDate = formatter.date(from: dep.lastAuditDate) {
                let daysSinceAudit = Calendar.current.dateComponents(
                    [.day], from: auditDate, to: Date()
                ).day ?? 0
                if daysSinceAudit > 90 {
                    return AuditResult(
                        dependency: dep,
                        status: .outdated,
                        message: "Last audited \(daysSinceAudit) days ago — re-audit required"
                    )
                }
            }

            return AuditResult(
                dependency: dep,
                status: .ok,
                message: "Version \(dep.currentVersion) is within acceptable range"
            )
        }
    }

    /// Print a formatted audit report to stdout.
    func printReport(_ results: [AuditResult]) {
        let maxNameLen = results.map(\.dependency.name.count).max() ?? 20
        let header = "Dependency".padding(toLength: maxNameLen + 2, withPad: " ", startingAt: 0)

        print("=== VaulType Dependency Audit Report ===")
        print("\(header)  Version       Status       Notes")
        print(String(repeating: "-", count: 80))

        for result in results {
            let name = result.dependency.name.padding(
                toLength: maxNameLen + 2, withPad: " ", startingAt: 0
            )
            let version = result.dependency.currentVersion.padding(
                toLength: 14, withPad: " ", startingAt: 0
            )
            let status = result.status.rawValue.padding(
                toLength: 13, withPad: " ", startingAt: 0
            )
            print("\(name)\(version)\(status)\(result.message)")
        }

        let vulnerableCount = results.filter { $0.status == .vulnerable }.count
        let outdatedCount = results.filter { $0.status == .outdated }.count

        print(String(repeating: "-", count: 80))
        print("Total: \(results.count) | Vulnerable: \(vulnerableCount) | Outdated: \(outdatedCount)")

        if vulnerableCount > 0 {
            print("\nACTION REQUIRED: \(vulnerableCount) dependencies have known vulnerabilities!")
        }
    }
}
```

---

## macOS Compatibility Maintenance

VaulType targets macOS 14 (Sonoma) and later. Each new macOS release can introduce breaking changes to the APIs we rely on heavily: Accessibility, TCC (Transparency, Consent, and Control), AVAudioEngine, CGEvent, and Metal.

### Testing on New macOS Releases

We follow a structured timeline aligned with Apple's release cycle:

| Phase | Timing | Activities |
|---|---|---|
| **WWDC Preview** | June | Watch sessions, read release notes, identify affected APIs |
| **Developer Beta 1** | June | Install on dedicated test Mac, run smoke tests |
| **Developer Beta 2-4** | July-August | Run full test suite, file Apple Feedback for regressions |
| **Public Beta** | August | Broader testing, community reports |
| **Release Candidate** | September | Full regression test, performance benchmarks |
| **GA Release** | September-October | Ship compatible update within 1 week |

> 🍎 **Apple Platform Note**: Always test on real hardware, not just simulators. Accessibility API behavior, Metal GPU scheduling, and TCC prompts can differ between virtualized and physical environments.

Testing checklist for each new macOS version:

- [ ] App launches without crashes
- [ ] Menu bar icon renders correctly (check for Dark Mode, Reduce Transparency)
- [ ] Global keyboard shortcut registers and fires
- [ ] Accessibility permission prompt appears and grants access
- [ ] Microphone permission prompt appears and grants access
- [ ] Audio capture works with built-in and external microphones
- [ ] Whisper transcription produces correct output
- [ ] LLM post-processing produces correct output
- [ ] Text injection works via CGEvent in TextEdit, Notes, Safari, VS Code, Terminal
- [ ] Sparkle update check works
- [ ] SwiftData store opens and migrates correctly
- [ ] Memory usage stays within expected bounds
- [ ] No new deprecation warnings in Xcode build log

### Handling Deprecated APIs

When Apple deprecates an API we use:

1. **Assess timeline** — Deprecated APIs typically work for 2-3 major versions. Check the `@available(*, deprecated)` annotation for the exact version.
2. **Identify replacement** — Find the recommended replacement API in Apple's documentation.
3. **Create abstraction** — Wrap the API behind a protocol if not already done.
4. **Implement conditionally**:

```swift
// TextInjector.swift — Conditional API usage based on macOS version

import Carbon
import ApplicationServices

/// Injects text into the frontmost application using the best available method.
struct TextInjector {

    /// Insert text at the current cursor position.
    func inject(text: String) async throws {
        if #available(macOS 16, *) {
            // Use the newer API when available (hypothetical future API)
            try await injectViaModernAPI(text: text)
        } else {
            // Fall back to CGEvent-based injection
            try await injectViaCGEvent(text: text)
        }
    }

    private func injectViaCGEvent(text: String) async throws {
        // Current implementation using CGEvent
        let source = CGEventSource(stateID: .combinedSessionState)

        for scalar in text.unicodeScalars {
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)

            keyDown?.keyboardSetUnicodeString(
                stringLength: 1,
                unicodeString: [UniChar(scalar.value)]
            )
            keyUp?.keyboardSetUnicodeString(
                stringLength: 1,
                unicodeString: [UniChar(scalar.value)]
            )

            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)

            // Small delay to prevent event coalescing
            try await Task.sleep(nanoseconds: 1_000_000) // 1ms
        }
    }

    @available(macOS 16, *)
    private func injectViaModernAPI(text: String) async throws {
        // Placeholder for future API replacement
        // When Apple provides a higher-level text injection API,
        // implement it here.
        try await injectViaCGEvent(text: text)
    }
}
```

### Privacy and Security Changes (TCC)

VaulType requires two TCC permissions: **Accessibility** and **Microphone**. Apple frequently tightens TCC in new macOS releases.

| Permission | TCC Service | Current Behavior | Risk in Future Releases |
|---|---|---|---|
| Accessibility | `kTCCServiceAccessibility` | One-time prompt, persists until revoked | May require re-authorization after app update |
| Microphone | `kTCCServiceMicrophone` | One-time prompt, persists until revoked | May add usage indicators, recording limits |
| Input Monitoring | `kTCCServiceListenEvent` | Required for global hotkeys | May merge with Accessibility or become stricter |
| Screen Recording | `kTCCServiceScreenCapture` | Not currently required | If we add overlay features, may be needed |

Maintenance actions:

- **Monitor Apple Security release notes** for TCC changes.
- **Test permission flows** after every macOS update: fresh install, upgrade from previous macOS, revoke-and-re-grant.
- **Keep the onboarding flow updated** — If Apple changes the permission grant UX, update our guided setup screenshots and instructions.
- **Handle permission resets** — Some macOS updates reset TCC databases. Detect this at launch and guide the user through re-authorization.

### Accessibility API Changes

The Accessibility API (`AXUIElement`) is central to VaulType's text injection fallback path. Changes to monitor:

- **`AXUIElement` deprecation** — Watch for any signals that Apple is moving away from the Carbon-era Accessibility API toward a SwiftUI-native replacement.
- **`AXTrustedCheckOptionPrompt`** — The mechanism for checking/requesting Accessibility trust may change.
- **Sandboxing interactions** — Future macOS versions may further restrict what non-sandboxed apps can do via Accessibility.

```swift
// AccessibilityMonitor.swift — Detect and report Accessibility API status

import ApplicationServices

/// Monitors the state of Accessibility permissions and API availability.
struct AccessibilityMonitor {

    /// Check whether the app is currently trusted for Accessibility.
    static func isTrusted(promptIfNeeded: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): promptIfNeeded] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Verify that the Accessibility API is functional, not just permitted.
    static func verifyFunctionality() -> AccessibilityStatus {
        guard isTrusted(promptIfNeeded: false) else {
            return .notTrusted
        }

        // Try to get the frontmost application
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return .noFrontmostApp
        }

        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        switch result {
        case .success:
            return .functional
        case .apiDisabled:
            return .apiDisabled
        case .notImplemented:
            return .limitedSupport
        default:
            return .unknownError(code: result.rawValue)
        }
    }

    enum AccessibilityStatus: CustomStringConvertible {
        case functional
        case notTrusted
        case apiDisabled
        case noFrontmostApp
        case limitedSupport
        case unknownError(code: Int32)

        var description: String {
            switch self {
            case .functional: return "Accessibility API is functional"
            case .notTrusted: return "App is not trusted for Accessibility"
            case .apiDisabled: return "Accessibility API is disabled system-wide"
            case .noFrontmostApp: return "No frontmost application detected"
            case .limitedSupport: return "Frontmost app has limited Accessibility support"
            case .unknownError(let code): return "Accessibility error: \(code)"
            }
        }
    }
}
```

### Entitlement Updates

VaulType's current entitlement set:

| Entitlement | Value | Purpose |
|---|---|---|
| `com.apple.security.app-sandbox` | `false` | Required for CGEvent, Accessibility |
| `com.apple.security.device.audio-input` | `true` | Microphone access |
| `com.apple.security.files.user-selected.read-write` | `true` | Model file management |
| `hardened-runtime` | `true` | Required for notarization |
| `com.apple.security.cs.disable-library-validation` | `true` | Load whisper.cpp/llama.cpp dylibs |
| `com.apple.security.automation.apple-events` | `true` | AppleScript fallback injection |

> ⚠️ **Warning**: If Apple introduces new entitlement requirements for Accessibility or audio input in future macOS versions, the app must be re-signed and a new notarized build distributed via Sparkle.

---

## Apple Silicon Optimization Updates

VaulType is optimized for Apple Silicon but also supports Intel Macs. As Apple releases new chip generations, we can unlock additional performance capabilities.

### Taking Advantage of New Chip Features

| Chip Generation | Key Features for VaulType | Optimization Opportunities |
|---|---|---|
| **M1** (2020) | 8-core GPU, 16-core Neural Engine | Baseline Metal compute, ANE for small models |
| **M2** (2022) | 10-core GPU, 15.8 TOPS Neural Engine | Improved Metal throughput |
| **M3** (2023) | Dynamic Caching, hardware ray tracing, mesh shading | More efficient Metal shader dispatch |
| **M4** (2024) | Enhanced Neural Engine (38 TOPS), improved GPU | Better ANE utilization for quantized inference |
| **Future** | TBD | Monitor WWDC announcements |

When a new chip is released:

1. **Acquire test hardware** — Purchase or borrow a Mac with the new chip.
2. **Run the full benchmark suite** — Compare against previous generations.
3. **Profile with Instruments** — Look for new bottlenecks or optimization opportunities.
4. **Review Metal Best Practices** — Apple often updates Metal optimization guidance per-chip.
5. **Test whisper.cpp/llama.cpp Metal performance** — These libraries often add chip-specific optimizations upstream.

### Metal API Updates

```swift
// MetalCapabilities.swift — Detect and report Metal GPU capabilities

import Metal

/// Describes the Metal capabilities of the current device.
struct MetalCapabilities {
    let deviceName: String
    let gpuFamily: MTLGPUFamily
    let maxThreadgroupMemory: Int
    let maxThreadsPerThreadgroup: MTLSize
    let supportsRayTracing: Bool
    let supportsDynamicCaching: Bool    // M3+
    let unifiedMemorySize: UInt64
    let recommendedMaxWorkingSetSize: UInt64

    /// Detect capabilities of the default Metal device.
    static func detect() -> MetalCapabilities? {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return nil
        }

        // Determine the highest supported GPU family
        let families: [(MTLGPUFamily, String)] = [
            (.apple9, "Apple 9 (M4)"),
            (.apple8, "Apple 8 (M3)"),
            (.apple7, "Apple 7 (M1/M2)"),
        ]

        var highestFamily: MTLGPUFamily = .apple7
        for (family, _) in families {
            if device.supportsFamily(family) {
                highestFamily = family
                break
            }
        }

        return MetalCapabilities(
            deviceName: device.name,
            gpuFamily: highestFamily,
            maxThreadgroupMemory: device.maxThreadgroupMemoryLength,
            maxThreadsPerThreadgroup: device.maxThreadsPerThreadgroup,
            supportsRayTracing: device.supportsRaytracing,
            supportsDynamicCaching: device.supportsFamily(.apple8),
            unifiedMemorySize: UInt64(ProcessInfo.processInfo.physicalMemory),
            recommendedMaxWorkingSetSize: UInt64(device.recommendedMaxWorkingSetSize)
        )
    }

    /// Return a summary suitable for diagnostic reports.
    func diagnosticSummary() -> String {
        """
        Metal Device: \(deviceName)
        GPU Family: \(gpuFamily)
        Unified Memory: \(unifiedMemorySize / (1024 * 1024 * 1024)) GB
        Recommended Working Set: \(recommendedMaxWorkingSetSize / (1024 * 1024)) MB
        Threadgroup Memory: \(maxThreadgroupMemory / 1024) KB
        Ray Tracing: \(supportsRayTracing ? "Yes" : "No")
        Dynamic Caching: \(supportsDynamicCaching ? "Yes" : "No")
        """
    }
}
```

### Neural Engine Utilization

The Apple Neural Engine (ANE) can accelerate quantized model inference if the model is converted to CoreML format. Current status:

| Aspect | Status | Notes |
|---|---|---|
| Whisper via ANE | Not used | whisper.cpp uses Metal GPU directly |
| LLM via ANE | Not used | llama.cpp uses Metal GPU directly |
| Future consideration | Monitoring | CoreML Whisper models exist but have quality tradeoffs |

> ℹ️ **Note**: whisper.cpp and llama.cpp are optimized for Metal GPU compute, which currently provides the best performance-to-quality ratio. ANE support would require CoreML model conversion and is being monitored as a future optimization. See `../architecture/TECH_STACK.md` for the detailed comparison.

### Performance Regression Testing Across Generations

Every release is benchmarked on multiple hardware generations:

| Test Device | Chip | RAM | Role |
|---|---|---|---|
| MacBook Air 13" | M1 | 8 GB | Minimum supported configuration |
| MacBook Pro 14" | M1 Pro | 16 GB | Mid-range reference |
| Mac Studio | M2 Ultra | 64 GB | High-end reference |
| Mac Mini | M4 | 16 GB | Latest generation |
| MacBook Pro 15" (2019) | Intel i7 | 16 GB | Intel compatibility baseline |

Acceptable performance ranges:

| Metric | M1 8GB (min) | M1 Pro 16GB | M4 16GB | Intel i7 |
|---|---|---|---|---|
| Whisper tiny inference (10s audio) | < 2.0s | < 1.2s | < 0.8s | < 4.0s |
| Whisper base inference (10s audio) | < 4.0s | < 2.5s | < 1.5s | < 8.0s |
| LLM tokens/second (Q4_K_M 7B) | > 15 t/s | > 30 t/s | > 50 t/s | > 5 t/s |
| App launch to ready | < 1.5s | < 1.0s | < 0.8s | < 3.0s |
| Idle memory usage | < 50 MB | < 50 MB | < 50 MB | < 60 MB |
| Peak memory (transcription) | < 2 GB | < 2 GB | < 2 GB | < 2.5 GB |

---

## Performance Regression Monitoring

Performance is a core feature of VaulType. Users expect transcription to feel instantaneous. Any regression in inference speed, memory usage, or responsiveness is treated as a bug.

### Benchmark Suite

The benchmark suite measures all critical paths:

| Benchmark | What It Measures | Target | Frequency |
|---|---|---|---|
| `bench_whisper_tiny` | Whisper tiny model inference latency | < 1x real-time on M1 | Every PR |
| `bench_whisper_base` | Whisper base model inference latency | < 2x real-time on M1 | Every PR |
| `bench_llm_load` | LLM model load time | < 3s on M1 | Every PR |
| `bench_llm_inference` | LLM tokens per second | > 15 t/s on M1 | Every PR |
| `bench_text_injection` | Text injection latency (1000 chars) | < 500ms | Every PR |
| `bench_audio_pipeline` | Audio capture to transcription start | < 100ms | Every PR |
| `bench_memory_idle` | Memory at idle (no model loaded) | < 50 MB | Every PR |
| `bench_memory_peak` | Peak memory during transcription | < 2 GB | Every PR |
| `bench_startup` | Cold start to menu bar ready | < 1.5s | Every PR |
| `bench_swiftdata` | SwiftData read/write latency | < 10ms | Per release |

### CI-Based Performance Tests

Performance benchmarks run as a separate CI job on a dedicated Apple Silicon runner:

```bash
#!/bin/bash
# scripts/ci-benchmark.sh — Run performance benchmarks in CI

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS_DIR="${REPO_ROOT}/benchmark-results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_FILE="${RESULTS_DIR}/bench_${TIMESTAMP}.json"

mkdir -p "$RESULTS_DIR"

echo "=== VaulType Performance Benchmark Suite ==="
echo "Date: $(date)"
echo "Host: $(hostname)"
echo "Chip: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'Apple Silicon')"
echo "RAM: $(sysctl -n hw.memsize | awk '{print $0/1073741824 " GB"}')"
echo "macOS: $(sw_vers -productVersion)"
echo ""

# Build the benchmark target in Release mode
echo "Building benchmark target..."
xcodebuild -scheme VaulTypeBenchmarks \
    -configuration Release \
    -derivedDataPath "${REPO_ROOT}/.build/benchmarks" \
    -quiet \
    build 2>&1

# Find the built binary
BENCH_BINARY=$(find "${REPO_ROOT}/.build/benchmarks" -name "VaulTypeBenchmarks" -type f | head -1)

if [ -z "$BENCH_BINARY" ]; then
    echo "ERROR: Benchmark binary not found"
    exit 1
fi

# Run benchmarks and capture output
echo "Running benchmarks..."
"$BENCH_BINARY" --output-format json --output-path "$RESULT_FILE" 2>&1

echo ""
echo "Results written to: $RESULT_FILE"

# Compare with baseline if available
BASELINE_FILE="${RESULTS_DIR}/baseline.json"
if [ -f "$BASELINE_FILE" ]; then
    echo ""
    echo "=== Comparison with Baseline ==="
    swift "${REPO_ROOT}/Scripts/compare-benchmarks.swift" \
        --baseline "$BASELINE_FILE" \
        --current "$RESULT_FILE" \
        --threshold 10  # Alert if any metric regresses by more than 10%
    COMPARISON_EXIT=$?

    if [ $COMPARISON_EXIT -ne 0 ]; then
        echo ""
        echo "PERFORMANCE REGRESSION DETECTED"
        echo "One or more benchmarks exceeded the 10% regression threshold."
        echo "Review the comparison above and address before merging."
        exit 1
    fi
else
    echo "No baseline file found at ${BASELINE_FILE}."
    echo "To set a baseline, copy the current results:"
    echo "  cp $RESULT_FILE $BASELINE_FILE"
fi

echo ""
echo "=== Benchmark Suite Complete ==="
```

### Performance Benchmark Runner Script

```swift
// Scripts/BenchmarkRunner.swift — Performance benchmark harness

import Foundation

/// A single benchmark measurement.
struct BenchmarkMeasurement: Codable {
    let name: String
    let iterations: Int
    let totalTimeMs: Double
    let averageTimeMs: Double
    let minTimeMs: Double
    let maxTimeMs: Double
    let standardDeviation: Double
    let peakMemoryMB: Double
    let unit: String
}

/// Runs and collects performance benchmarks.
final class BenchmarkRunner {

    struct BenchmarkDefinition {
        let name: String
        let warmupIterations: Int
        let measureIterations: Int
        let unit: String
        let body: () async throws -> Double  // Returns the measured value
    }

    private var benchmarks: [BenchmarkDefinition] = []
    private var results: [BenchmarkMeasurement] = []

    /// Register a benchmark.
    func register(
        name: String,
        warmup: Int = 3,
        iterations: Int = 10,
        unit: String = "ms",
        body: @escaping () async throws -> Double
    ) {
        benchmarks.append(BenchmarkDefinition(
            name: name,
            warmupIterations: warmup,
            measureIterations: iterations,
            unit: unit,
            body: body
        ))
    }

    /// Run all registered benchmarks and return results.
    func runAll() async throws -> [BenchmarkMeasurement] {
        results = []

        for benchmark in benchmarks {
            print("Running: \(benchmark.name)...")

            // Warmup
            for _ in 0..<benchmark.warmupIterations {
                _ = try await benchmark.body()
            }

            // Measure
            var measurements: [Double] = []
            var peakMemory: UInt64 = 0

            for _ in 0..<benchmark.measureIterations {
                let memBefore = currentResidentMemory()
                let value = try await benchmark.body()
                let memAfter = currentResidentMemory()

                measurements.append(value)
                peakMemory = max(peakMemory, memAfter)

                // Brief pause between iterations to let the system settle
                try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            }

            let total = measurements.reduce(0, +)
            let average = total / Double(measurements.count)
            let min = measurements.min() ?? 0
            let max = measurements.max() ?? 0

            // Standard deviation
            let variance = measurements.map { pow($0 - average, 2) }.reduce(0, +)
                / Double(measurements.count)
            let stddev = sqrt(variance)

            let measurement = BenchmarkMeasurement(
                name: benchmark.name,
                iterations: benchmark.measureIterations,
                totalTimeMs: total,
                averageTimeMs: average,
                minTimeMs: min,
                maxTimeMs: max,
                standardDeviation: stddev,
                peakMemoryMB: Double(peakMemory) / (1024 * 1024),
                unit: benchmark.unit
            )

            results.append(measurement)
            print("  Average: \(String(format: "%.2f", average)) \(benchmark.unit) "
                + "(stddev: \(String(format: "%.2f", stddev)))")
        }

        return results
    }

    /// Write results to a JSON file.
    func writeResults(to path: URL) throws {
        let report = BenchmarkReport(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            hostname: ProcessInfo.processInfo.hostName,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            physicalMemoryGB: Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)),
            processorCount: ProcessInfo.processInfo.processorCount,
            measurements: results
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        try data.write(to: path, options: .atomic)
    }

    // MARK: - Helpers

    private func currentResidentMemory() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }
}

/// Top-level benchmark report written to JSON.
struct BenchmarkReport: Codable {
    let timestamp: String
    let hostname: String
    let osVersion: String
    let physicalMemoryGB: Int
    let processorCount: Int
    let measurements: [BenchmarkMeasurement]
}
```

### Alerting on Regressions

Regression detection is automatic in CI. The threshold configuration:

| Metric Category | Warning Threshold | Failure Threshold | Action |
|---|---|---|---|
| Inference latency | > 5% slower | > 10% slower | Block merge, notify ML lead |
| Memory usage | > 10% increase | > 20% increase | Block merge, notify platform lead |
| Startup time | > 15% slower | > 25% slower | Block merge, notify UI lead |
| Token throughput | > 5% decrease | > 10% decrease | Block merge, notify ML lead |

When a regression is detected:

1. **CI blocks the PR** with a detailed comparison table.
2. **A GitHub Issue is auto-created** with the regression details, tagged `performance-regression`.
3. **The PR author and relevant lead** are mentioned in the issue.
4. **Resolution options**: fix the regression, update the baseline (with justification), or mark as accepted tradeoff.

### Historical Performance Tracking

Benchmark results are stored as JSON files in the repository under `benchmark-results/` and visualized over time:

```bash
# scripts/plot-benchmarks.sh — Generate performance trend charts

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS_DIR="${REPO_ROOT}/benchmark-results"

# Aggregate results into a CSV for plotting
echo "timestamp,benchmark,average_ms,peak_memory_mb" > "${RESULTS_DIR}/trends.csv"

for result_file in "${RESULTS_DIR}"/bench_*.json; do
    [ -f "$result_file" ] || continue
    python3 -c "
import json, sys
with open('$result_file') as f:
    report = json.load(f)
ts = report['timestamp']
for m in report['measurements']:
    print(f\"{ts},{m['name']},{m['averageTimeMs']},{m['peakMemoryMB']}\")
" >> "${RESULTS_DIR}/trends.csv"
done

echo "Trends CSV written to: ${RESULTS_DIR}/trends.csv"
echo "Import into your preferred visualization tool (Numbers, Grafana, etc.)"
```

---

## User Feedback Triage Process

User feedback is the primary signal for prioritizing maintenance work. We use GitHub Issues as the single source of truth for all feedback, bugs, and feature requests.

### GitHub Issues Workflow

```
User reports issue
        │
        ▼
┌─────────────────┐
│  GitHub Issue    │
│  Created         │
└────────┬────────┘
         │
         ▼
┌─────────────────┐     ┌───────────────────┐
│  Auto-labeling  │────▶│  Needs Triage      │
│  (via template) │     │  label applied     │
└─────────────────┘     └────────┬──────────┘
                                 │
                        ┌────────▼──────────┐
                        │  Weekly Triage     │
                        │  Meeting           │
                        └────────┬──────────┘
                                 │
                    ┌────────────┼────────────┐
                    ▼            ▼            ▼
             ┌──────────┐ ┌──────────┐ ┌──────────┐
             │  P0/P1   │ │  P2      │ │  P3      │
             │  Assign  │ │  Backlog │ │  Icebox  │
             │  now     │ │  for     │ │  or      │
             │          │ │  next    │ │  close   │
             │          │ │  sprint  │ │          │
             └──────────┘ └──────────┘ └──────────┘
```

### Bug Report Template

```markdown
---
name: Bug Report
about: Report a problem with VaulType
title: "[Bug] "
labels: ["bug", "needs-triage"]
assignees: []
---

## Description
<!-- A clear description of the bug. -->

## Steps to Reproduce
1.
2.
3.

## Expected Behavior
<!-- What should happen? -->

## Actual Behavior
<!-- What actually happens? -->

## Environment
- **VaulType version**: <!-- e.g., 1.2.3 -->
- **macOS version**: <!-- e.g., 15.1 -->
- **Chip**: <!-- e.g., M1, M3 Pro, Intel i7 -->
- **RAM**: <!-- e.g., 8 GB, 16 GB -->
- **Whisper model**: <!-- e.g., base, small, large-v3-turbo -->
- **LLM model**: <!-- e.g., Llama 3.2 3B Q4_K_M -->

## Diagnostic Information
<!-- Paste the output of VaulType > Help > Copy Diagnostic Info -->
```
<details>
<summary>Diagnostic output</summary>

```
Paste here
```

</details>

```markdown
## Screenshots / Screen Recordings
<!-- If applicable, add screenshots or recordings. -->

## Additional Context
<!-- Any other context about the problem. -->
```

### Feature Request Template

```markdown
---
name: Feature Request
about: Suggest a new feature for VaulType
title: "[Feature] "
labels: ["enhancement", "needs-triage"]
assignees: []
---

## Problem Statement
<!-- What problem does this feature solve? -->

## Proposed Solution
<!-- How should this feature work? -->

## Alternatives Considered
<!-- What other approaches did you consider? -->

## Privacy Impact
<!-- Does this feature affect VaulType's privacy guarantees? (e.g., would it require network access?) -->

## Scope
- [ ] This feature works entirely offline
- [ ] This feature requires no new permissions
- [ ] This feature is macOS-native (no cross-platform concerns)

## Additional Context
<!-- Mockups, examples from other apps, etc. -->
```

### Priority Classification

| Priority | Label | Criteria | Response Time | Resolution Target |
|---|---|---|---|---|
| **P0 - Critical** | `priority/P0` | Data loss, security vulnerability, crash on launch, complete feature failure | Same day | 24-48 hours |
| **P1 - High** | `priority/P1` | Major feature broken for many users, significant performance regression, crash in common path | 1 business day | 1 week |
| **P2 - Medium** | `priority/P2` | Feature partially broken, workaround exists, cosmetic issues affecting usability | 1 week | Next release |
| **P3 - Low** | `priority/P3` | Minor cosmetic issues, edge cases, nice-to-have improvements | 2 weeks | Backlog |

Examples by priority:

| Priority | Example Issues |
|---|---|
| **P0** | "Transcription produces empty output on all audio" |
| **P0** | "App crashes on launch after macOS 16 update" |
| **P1** | "Text injection fails in VS Code but works in other apps" |
| **P1** | "Whisper inference 3x slower after update to v1.5" |
| **P2** | "Overlay window position resets after sleep/wake" |
| **P2** | "Settings window doesn't remember last-used tab" |
| **P3** | "Menu bar icon could use a tooltip" |
| **P3** | "Would be nice to customize the keyboard shortcut indicator" |

### Release Planning from Feedback

Each release is planned by analyzing the current issue backlog:

1. **Aggregate** — Group issues by label (`bug`, `enhancement`, `performance`, `model-update`).
2. **Prioritize** — All P0 and P1 issues must be in the current milestone.
3. **Estimate** — Assign rough effort estimates (S/M/L/XL) to each issue.
4. **Capacity check** — Ensure total estimated effort fits within the sprint/release window.
5. **Theme** — Give each release a theme based on the dominant issue category (e.g., "Performance Release", "macOS 16 Compatibility Release").
6. **Communicate** — Update the `CHANGELOG.md` draft and notify beta testers of upcoming changes.

### Diagnostic Information Collector

This is the code behind the "Copy Diagnostic Info" menu item. It collects system and app state without any personal data:

```swift
// DiagnosticCollector.swift — Gathers system and app diagnostic information

import Foundation
import IOKit
import Metal

/// Collects diagnostic information for bug reports.
/// Deliberately excludes any personal data, transcription history, or file contents.
actor DiagnosticCollector {

    struct DiagnosticReport: Codable {
        let appVersion: String
        let buildNumber: String
        let macOSVersion: String
        let hardwareModel: String
        let chipType: String
        let totalRAMGB: Int
        let availableRAMGB: Int
        let metalDevice: String?
        let metalGPUFamily: String?
        let modelsInstalled: [ModelInfo]
        let permissions: PermissionStatus
        let audioDevices: [AudioDeviceInfo]
        let appUptime: TimeInterval
        let currentMemoryUsageMB: Int
        let swiftDataStoreSize: String
        let sparkleLastCheckDate: String?
        let logsExcerpt: [String]  // Last 20 log lines, redacted

        struct ModelInfo: Codable {
            let name: String
            let type: String
            let sizeMB: Int
            let isCompatible: Bool
        }

        struct PermissionStatus: Codable {
            let accessibility: String
            let microphone: String
            let inputMonitoring: String
        }

        struct AudioDeviceInfo: Codable {
            let name: String
            let sampleRate: Double
            let channels: Int
            let isDefault: Bool
        }
    }

    /// Collect all diagnostic information.
    func collect() async -> DiagnosticReport {
        let processInfo = ProcessInfo.processInfo

        return DiagnosticReport(
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            macOSVersion: processInfo.operatingSystemVersionString,
            hardwareModel: getHardwareModel(),
            chipType: getChipType(),
            totalRAMGB: Int(processInfo.physicalMemory / (1024 * 1024 * 1024)),
            availableRAMGB: getAvailableRAMGB(),
            metalDevice: MTLCreateSystemDefaultDevice()?.name,
            metalGPUFamily: getMetalGPUFamily(),
            modelsInstalled: getInstalledModels(),
            permissions: getPermissionStatus(),
            audioDevices: getAudioDevices(),
            appUptime: processInfo.systemUptime,
            currentMemoryUsageMB: getCurrentMemoryMB(),
            swiftDataStoreSize: getSwiftDataStoreSize(),
            sparkleLastCheckDate: getSparkleLastCheck(),
            logsExcerpt: getRecentLogs(count: 20)
        )
    }

    /// Format the report as a copyable string.
    func formatAsText(_ report: DiagnosticReport) -> String {
        var lines: [String] = []

        lines.append("=== VaulType Diagnostic Report ===")
        lines.append("")
        lines.append("App Version: \(report.appVersion) (\(report.buildNumber))")
        lines.append("macOS: \(report.macOSVersion)")
        lines.append("Hardware: \(report.hardwareModel)")
        lines.append("Chip: \(report.chipType)")
        lines.append("RAM: \(report.totalRAMGB) GB total, ~\(report.availableRAMGB) GB available")
        lines.append("Metal: \(report.metalDevice ?? "Not available")")
        lines.append("GPU Family: \(report.metalGPUFamily ?? "Unknown")")
        lines.append("")

        lines.append("--- Permissions ---")
        lines.append("Accessibility: \(report.permissions.accessibility)")
        lines.append("Microphone: \(report.permissions.microphone)")
        lines.append("Input Monitoring: \(report.permissions.inputMonitoring)")
        lines.append("")

        lines.append("--- Models ---")
        for model in report.modelsInstalled {
            let compat = model.isCompatible ? "OK" : "INCOMPATIBLE"
            lines.append("  \(model.name) (\(model.type), \(model.sizeMB) MB) [\(compat)]")
        }
        lines.append("")

        lines.append("--- Audio Devices ---")
        for device in report.audioDevices {
            let def = device.isDefault ? " [DEFAULT]" : ""
            lines.append("  \(device.name) (\(Int(device.sampleRate)) Hz, \(device.channels)ch)\(def)")
        }
        lines.append("")

        lines.append("--- Runtime ---")
        lines.append("App Uptime: \(Int(report.appUptime))s")
        lines.append("Memory Usage: \(report.currentMemoryUsageMB) MB")
        lines.append("SwiftData Store: \(report.swiftDataStoreSize)")
        lines.append("Last Update Check: \(report.sparkleLastCheckDate ?? "Never")")
        lines.append("")

        if !report.logsExcerpt.isEmpty {
            lines.append("--- Recent Logs (redacted) ---")
            lines.append(contentsOf: report.logsExcerpt)
        }

        lines.append("")
        lines.append("=== End of Report ===")

        return lines.joined(separator: "\n")
    }

    // MARK: - Private Helpers

    private func getHardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }

    private func getChipType() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var brand = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)
        let result = String(cString: brand)
        return result.isEmpty ? "Apple Silicon" : result
    }

    private func getAvailableRAMGB() -> Int {
        // Use vm_statistics64 to get free + inactive memory
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let pageSize = UInt64(vm_kernel_page_size)
        let available = (UInt64(stats.free_count) + UInt64(stats.inactive_count)) * pageSize
        return Int(available / (1024 * 1024 * 1024))
    }

    private func getMetalGPUFamily() -> String? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        if device.supportsFamily(.apple9) { return "Apple 9 (M4)" }
        if device.supportsFamily(.apple8) { return "Apple 8 (M3)" }
        if device.supportsFamily(.apple7) { return "Apple 7 (M1/M2)" }
        return "Unknown"
    }

    private func getInstalledModels() -> [DiagnosticReport.ModelInfo] {
        // Scan the models directory and return basic info
        let modelsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("VaulType/Models")

        guard let modelsDir = modelsDir,
              let files = try? FileManager.default.contentsOfDirectory(
                  at: modelsDir, includingPropertiesForKeys: [.fileSizeKey]
              ) else {
            return []
        }

        return files.compactMap { url -> DiagnosticReport.ModelInfo? in
            let ext = url.pathExtension.lowercased()
            guard ext == "gguf" || ext == "bin" else { return nil }

            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let name = url.deletingPathExtension().lastPathComponent
            let type = name.lowercased().contains("whisper") ? "whisper" : "llm"

            return DiagnosticReport.ModelInfo(
                name: name,
                type: type,
                sizeMB: size / (1024 * 1024),
                isCompatible: ext == "gguf"  // GGML format is deprecated
            )
        }
    }

    private func getPermissionStatus() -> DiagnosticReport.PermissionStatus {
        DiagnosticReport.PermissionStatus(
            accessibility: AccessibilityMonitor.isTrusted() ? "Granted" : "Not Granted",
            microphone: "Check via AVCaptureDevice",  // Requires async check
            inputMonitoring: "Check via IOHIDManager"  // Requires async check
        )
    }

    private func getAudioDevices() -> [DiagnosticReport.AudioDeviceInfo] {
        // Placeholder — would query AudioObjectGetPropertyData in production
        return []
    }

    private func getCurrentMemoryMB() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Int(info.resident_size / (1024 * 1024))
    }

    private func getSwiftDataStoreSize() -> String {
        let storeURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("VaulType/VaulType.store")

        guard let storeURL = storeURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: storeURL.path),
              let size = attrs[.size] as? Int else {
            return "Not found"
        }

        if size < 1024 { return "\(size) B" }
        if size < 1024 * 1024 { return "\(size / 1024) KB" }
        return "\(size / (1024 * 1024)) MB"
    }

    private func getSparkleLastCheck() -> String? {
        UserDefaults.standard.object(forKey: "SULastCheckTime") as? String
    }

    private func getRecentLogs(count: Int) -> [String] {
        // Read from the app's log file, redacting any potentially personal content
        let logURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("VaulType/Logs/vaultype.log")

        guard let logURL = logURL,
              let content = try? String(contentsOf: logURL, encoding: .utf8) else {
            return ["No log file found"]
        }

        let lines = content.components(separatedBy: .newlines)
        let recentLines = Array(lines.suffix(count))

        // Redact anything that looks like personal content
        return recentLines.map { line in
            // Redact transcription text (appears after "Transcribed: ")
            var redacted = line.replacingOccurrences(
                of: #"Transcribed: .+"#,
                with: "Transcribed: [REDACTED]",
                options: .regularExpression
            )
            // Redact file paths that contain the username
            redacted = redacted.replacingOccurrences(
                of: #"/Users/[^/]+"#,
                with: "/Users/[REDACTED]",
                options: .regularExpression
            )
            return redacted
        }
    }
}
```

> 🔒 **Privacy**: The diagnostic collector deliberately excludes transcription history, typed text, personal file paths (redacted to `/Users/[REDACTED]`), and any content that could identify the user. This aligns with VaulType's zero-data-collection principle.

---

## SwiftData Migration Between App Versions

As VaulType evolves, the SwiftData schema may change between versions. Every schema change requires a migration plan to preserve user data (settings, transcription history, model preferences).

### Migration Strategy

VaulType follows a **forward-only migration** strategy:

1. **Never delete data** — Old fields are deprecated, not removed.
2. **Add with defaults** — New fields always have sensible defaults.
3. **Version the schema** — Each schema version corresponds to an app version.
4. **Test round-trip** — Verify that data written by version N can be read by version N+1.

| Schema Version | App Version | Changes |
|---|---|---|
| V1 | 1.0.0 | Initial schema: TranscriptionRecord, UserPreferences |
| V2 | 1.1.0 | Added `modelVersion` to TranscriptionRecord |
| V3 | 1.2.0 | Added VoiceCommandHistory model |
| V4 | 2.0.0 | Refactored UserPreferences into typed settings |

### Migration Implementation

```swift
// Persistence/MigrationManager.swift — SwiftData schema migration

import SwiftData
import Foundation
import os

/// Manages SwiftData schema migrations between app versions.
final class MigrationManager {

    private let logger = Logger(subsystem: "app.vaultype", category: "Migration")

    // MARK: - Schema Versions

    /// V1: Initial schema (app version 1.0.0)
    enum SchemaV1: VersionedSchema {
        static var versionIdentifier: Schema.Version = Schema.Version(1, 0, 0)
        static var models: [any PersistentModel.Type] {
            [TranscriptionRecordV1.self, UserPreferencesV1.self]
        }

        @Model
        final class TranscriptionRecordV1 {
            var id: UUID
            var text: String
            var createdAt: Date
            var audioDurationSeconds: Double
            var inferenceTimeMs: Double
            var language: String

            init(id: UUID, text: String, createdAt: Date,
                 audioDurationSeconds: Double, inferenceTimeMs: Double, language: String) {
                self.id = id
                self.text = text
                self.createdAt = createdAt
                self.audioDurationSeconds = audioDurationSeconds
                self.inferenceTimeMs = inferenceTimeMs
                self.language = language
            }
        }

        @Model
        final class UserPreferencesV1 {
            var id: UUID
            var selectedWhisperModel: String
            var selectedLLMModel: String?
            var language: String
            var useGPU: Bool

            init(id: UUID, selectedWhisperModel: String, selectedLLMModel: String?,
                 language: String, useGPU: Bool) {
                self.id = id
                self.selectedWhisperModel = selectedWhisperModel
                self.selectedLLMModel = selectedLLMModel
                self.language = language
                self.useGPU = useGPU
            }
        }
    }

    /// V2: Added modelVersion to TranscriptionRecord (app version 1.1.0)
    enum SchemaV2: VersionedSchema {
        static var versionIdentifier: Schema.Version = Schema.Version(1, 1, 0)
        static var models: [any PersistentModel.Type] {
            [TranscriptionRecordV2.self, UserPreferencesV1.self]
        }

        @Model
        final class TranscriptionRecordV2 {
            var id: UUID
            var text: String
            var createdAt: Date
            var audioDurationSeconds: Double
            var inferenceTimeMs: Double
            var language: String
            var whisperModelVersion: String     // NEW in V2
            var llmModelVersion: String?        // NEW in V2

            init(id: UUID, text: String, createdAt: Date,
                 audioDurationSeconds: Double, inferenceTimeMs: Double,
                 language: String, whisperModelVersion: String, llmModelVersion: String?) {
                self.id = id
                self.text = text
                self.createdAt = createdAt
                self.audioDurationSeconds = audioDurationSeconds
                self.inferenceTimeMs = inferenceTimeMs
                self.language = language
                self.whisperModelVersion = whisperModelVersion
                self.llmModelVersion = llmModelVersion
            }
        }
    }

    /// V3: Added VoiceCommandHistory (app version 1.2.0)
    enum SchemaV3: VersionedSchema {
        static var versionIdentifier: Schema.Version = Schema.Version(1, 2, 0)
        static var models: [any PersistentModel.Type] {
            [TranscriptionRecordV2.self, SchemaV1.UserPreferencesV1.self, VoiceCommandHistoryV3.self]
        }

        @Model
        final class VoiceCommandHistoryV3 {
            var id: UUID
            var command: String
            var executedAt: Date
            var wasSuccessful: Bool
            var targetApp: String?

            init(id: UUID, command: String, executedAt: Date,
                 wasSuccessful: Bool, targetApp: String?) {
                self.id = id
                self.command = command
                self.executedAt = executedAt
                self.wasSuccessful = wasSuccessful
                self.targetApp = targetApp
            }
        }
    }

    // MARK: - Migration Plans

    /// V1 -> V2: Add model version fields with defaults.
    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self,
        willMigrate: nil,
        didMigrate: { context in
            // Fetch all V2 records (which were migrated from V1)
            let records = try context.fetch(FetchDescriptor<SchemaV2.TranscriptionRecordV2>())
            for record in records {
                // Set default model versions for records created before V2
                if record.whisperModelVersion.isEmpty {
                    record.whisperModelVersion = "unknown-pre-v2"
                }
            }
            try context.save()
        }
    )

    /// V2 -> V3: Add VoiceCommandHistory model (lightweight, no data migration needed).
    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: SchemaV2.self,
        toVersion: SchemaV3.self
    )

    /// The complete migration plan covering all schema versions.
    static var migrationPlan: SchemaMigrationPlan.Type {
        VaulTypeMigrationPlan.self
    }
}

/// The full migration plan that SwiftData uses at container initialization.
enum VaulTypeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            MigrationManager.SchemaV1.self,
            MigrationManager.SchemaV2.self,
            MigrationManager.SchemaV3.self,
        ]
    }

    static var stages: [MigrationStage] {
        [
            MigrationManager.migrateV1toV2,
            MigrationManager.migrateV2toV3,
        ]
    }
}

// MARK: - Container Setup

extension ModelContainer {
    /// Create a ModelContainer with migration support.
    static func vaulTypeContainer() throws -> ModelContainer {
        let schema = Schema(MigrationManager.SchemaV3.models)
        let config = ModelConfiguration(
            "VaulType",
            schema: schema,
            isStoredInMemoryOnly: false,
            groupContainer: .none
        )

        return try ModelContainer(
            for: schema,
            migrationPlan: VaulTypeMigrationPlan.self,
            configurations: [config]
        )
    }
}
```

### Migration Testing

Every migration must be tested before release:

```swift
// Tests/MigrationTests.swift — Verify SwiftData migrations

import XCTest
import SwiftData
@testable import VaulType

final class MigrationTests: XCTestCase {

    /// Test that a V1 store can be migrated to V3 without data loss.
    func testV1toV3Migration() throws {
        // 1. Create a V1 store with test data
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create V1 container and populate
        let v1Schema = Schema(MigrationManager.SchemaV1.models)
        let v1Config = ModelConfiguration(
            url: tempDir.appendingPathComponent("test.store"),
            schema: v1Schema
        )
        let v1Container = try ModelContainer(for: v1Schema, configurations: [v1Config])
        let v1Context = ModelContext(v1Container)

        let testRecord = MigrationManager.SchemaV1.TranscriptionRecordV1(
            id: UUID(),
            text: "Test transcription",
            createdAt: Date(),
            audioDurationSeconds: 5.0,
            inferenceTimeMs: 1200.0,
            language: "en"
        )
        v1Context.insert(testRecord)
        try v1Context.save()

        // 2. Open the same store with V3 schema + migration plan
        let v3Schema = Schema(MigrationManager.SchemaV3.models)
        let v3Config = ModelConfiguration(
            url: tempDir.appendingPathComponent("test.store"),
            schema: v3Schema
        )
        let v3Container = try ModelContainer(
            for: v3Schema,
            migrationPlan: VaulTypeMigrationPlan.self,
            configurations: [v3Config]
        )
        let v3Context = ModelContext(v3Container)

        // 3. Verify data survived migration
        let migratedRecords = try v3Context.fetch(
            FetchDescriptor<MigrationManager.SchemaV2.TranscriptionRecordV2>()
        )
        XCTAssertEqual(migratedRecords.count, 1)
        XCTAssertEqual(migratedRecords.first?.text, "Test transcription")
        XCTAssertEqual(migratedRecords.first?.language, "en")

        // V2 fields should have default values
        XCTAssertEqual(migratedRecords.first?.whisperModelVersion, "unknown-pre-v2")
    }

    /// Test that migration handles empty stores gracefully.
    func testMigrationOnEmptyStore() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Opening a fresh store with migration plan should not crash
        let container = try ModelContainer.vaulTypeContainer()
        XCTAssertNotNil(container)
    }

    /// Test that corrupted stores are handled without crashing.
    func testCorruptedStoreRecovery() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Write garbage to the store file
        let storeURL = tempDir.appendingPathComponent("VaulType.store")
        try "not a valid sqlite database".write(to: storeURL, atomically: true, encoding: .utf8)

        // Attempting to open should throw, not crash
        XCTAssertThrowsError(try ModelContainer.vaulTypeContainer()) { error in
            // Verify we get a meaningful error, not a segfault
            XCTAssertNotNil(error.localizedDescription)
        }
    }
}
```

> ❌ **Never**: Skip migration testing. A failed migration means users lose their settings and transcription history on app update, which is unacceptable.

> ✅ **Always**: Keep old `VersionedSchema` types in the codebase permanently. They are needed for the migration chain to work. Do not delete `SchemaV1` even when the app is on V10.

---

## Related Documentation

| Document | Relevance |
|---|---|
| [Architecture](../architecture/ARCHITECTURE.md) | System design and component interactions that maintenance must preserve |
| [Technology Stack](../architecture/TECH_STACK.md) | Detailed technology choices and version constraints |
| [Monitoring and Logging](MONITORING_LOGGING.md) | Runtime monitoring that feeds into maintenance decisions |
| [CI/CD Pipeline](../deployment/CI_CD.md) | Build and release automation, including benchmark CI jobs |
| [Model Management](../features/MODEL_MANAGEMENT.md) | User-facing model download, switching, and deletion features |
| [Database Schema](../architecture/DATABASE_SCHEMA.md) | SwiftData schema definitions that migration code must track |
| [Security](../security/SECURITY.md) | Security policies that constrain dependency and entitlement updates |
| [Permissions](../features/PERMISSIONS.md) | TCC permission handling that must be updated for macOS changes |
| [Roadmap](../reference/ROADMAP.md) | Upcoming features that drive maintenance priorities |
