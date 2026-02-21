Last Updated: 2026-02-13

# Monitoring & Logging

> **VaulType** — Privacy-first, macOS-native speech-to-text with local LLM post-processing.
> Complete reference for structured logging, performance metrics, crash reporting, diagnostics, and runtime monitoring — all designed with privacy as the default.

---

## Table of Contents

- [1. Logging Architecture Overview](#1-logging-architecture-overview)
  - [1.1 Design Principles](#11-design-principles)
  - [1.2 Architecture Diagram](#12-architecture-diagram)
- [2. os_log Integration for Structured Logging](#2-os_log-integration-for-structured-logging)
  - [2.1 OSLog Subsystem and Category Setup](#21-oslog-subsystem-and-category-setup)
  - [2.2 Log Levels](#22-log-levels)
  - [2.3 Privacy-Aware Logging](#23-privacy-aware-logging)
  - [2.4 Signposts for Performance](#24-signposts-for-performance)
- [3. Log Categories](#3-log-categories)
  - [3.1 Category Reference Table](#31-category-reference-table)
  - [3.2 Subsystem Naming Convention](#32-subsystem-naming-convention)
  - [3.3 Logger Singleton Setup](#33-logger-singleton-setup)
- [4. Console.app Usage for Debugging](#4-consoleapp-usage-for-debugging)
  - [4.1 Filtering VaulType Logs](#41-filtering-vaultype-logs)
  - [4.2 Useful Predicates](#42-useful-predicates)
  - [4.3 Streaming Logs During Development](#43-streaming-logs-during-development)
  - [4.4 Log Export](#44-log-export)
- [5. Crash Reporting with Sentry (Opt-In)](#5-crash-reporting-with-sentry-opt-in)
  - [5.1 Privacy-Respecting Configuration](#51-privacy-respecting-configuration)
  - [5.2 Opt-In Flow](#52-opt-in-flow)
  - [5.3 DSN Configuration](#53-dsn-configuration)
  - [5.4 Breadcrumbs](#54-breadcrumbs)
  - [5.5 What Is Never Sent](#55-what-is-never-sent)
- [6. Performance Metrics Collection (Local Only)](#6-performance-metrics-collection-local-only)
  - [6.1 Metrics Data Model](#61-metrics-data-model)
  - [6.2 Metrics Collection Service](#62-metrics-collection-service)
  - [6.3 Transcription Latency Tracking](#63-transcription-latency-tracking)
  - [6.4 LLM Inference Time Tracking](#64-llm-inference-time-tracking)
  - [6.5 Text Injection Time Tracking](#65-text-injection-time-tracking)
  - [6.6 Model Load Time Tracking](#66-model-load-time-tracking)
  - [6.7 Audio Buffer Statistics](#67-audio-buffer-statistics)
- [7. Diagnostics Export for Bug Reports](#7-diagnostics-export-for-bug-reports)
  - [7.1 Diagnostic Bundle Contents](#71-diagnostic-bundle-contents)
  - [7.2 Bundle Generation](#72-bundle-generation)
  - [7.3 Privacy Review Before Export](#73-privacy-review-before-export)
  - [7.4 Share Sheet Integration](#74-share-sheet-integration)
- [8. Memory and CPU Monitoring](#8-memory-and-cpu-monitoring)
  - [8.1 ProcessInfo-Based Monitoring](#81-processinfo-based-monitoring)
  - [8.2 Memory Pressure Notifications](#82-memory-pressure-notifications)
  - [8.3 Thermal State Monitoring](#83-thermal-state-monitoring)
  - [8.4 Instruments Integration](#84-instruments-integration)
- [9. Logging Best Practices](#9-logging-best-practices)
  - [9.1 Do's and Don'ts](#91-dos-and-donts)
  - [9.2 Log Message Style Guide](#92-log-message-style-guide)
- [Related Documentation](#related-documentation)

---

## 1. Logging Architecture Overview

### 1.1 Design Principles

VaulType's monitoring and logging system is built on four core principles:

1. **Privacy by Default** — No user content (transcriptions, audio data, injected text) is ever written to logs. All dynamic values use `%{private}` unless explicitly marked public.
2. **Local Only** — All performance metrics are stored in SwiftData on-device. Nothing is transmitted unless the user explicitly opts in to Sentry crash reporting.
3. **Structured and Queryable** — Apple's `os_log` provides structured, typed, efficient logging that integrates with Console.app and Instruments.
4. **Zero Overhead in Production** — Debug-level logs are compiled out in release builds. Signposts have negligible cost when not actively profiled.

> 🔒 **Security**: VaulType logs never contain transcription content, audio data, clipboard contents, or any text the user has dictated. See [`../security/SECURITY.md`](../security/SECURITY.md) for the full data handling policy.

### 1.2 Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          VaulType Application                               │
│                                                                             │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐  ┌────────────┐  │
│  │  Audio Layer  │  │  Whisper STT  │  │  LLM Engine   │  │  Injector  │  │
│  │   os_log      │  │   os_log      │  │   os_log      │  │   os_log   │  │
│  │   signposts   │  │   signposts   │  │   signposts   │  │  signposts │  │
│  └──────┬────────┘  └──────┬────────┘  └──────┬────────┘  └─────┬──────┘  │
│         │                  │                   │                  │         │
│         ▼                  ▼                   ▼                  ▼         │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    MetricsCollectionService                         │   │
│  │                                                                     │   │
│  │  • Collects timing data from signposts                             │   │
│  │  • Aggregates per-session and rolling statistics                   │   │
│  │  • Stores metrics in SwiftData (PerformanceMetric model)          │   │
│  └────────────────────────────────┬────────────────────────────────────┘   │
│                                   │                                        │
│         ┌─────────────────────────┼──────────────────────┐                │
│         ▼                         ▼                      ▼                │
│  ┌─────────────┐  ┌───────────────────────┐  ┌────────────────────┐      │
│  │  SwiftData  │  │  DiagnosticExporter   │  │  Sentry (Opt-In)  │      │
│  │  (local DB) │  │                       │  │                    │      │
│  │             │  │  Bundles logs, system  │  │  Crash reports &  │      │
│  │  Metrics &  │  │  info, metrics into   │  │  breadcrumbs only │      │
│  │  history    │  │  shareable .zip       │  │  No PII, no audio │      │
│  └─────────────┘  └───────────────────────┘  └────────────────────┘      │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    SystemMonitor                                    │   │
│  │                                                                     │   │
│  │  • Memory pressure via DispatchSource.makeMemoryPressureSource()   │   │
│  │  • Thermal state via ProcessInfo.thermalState                      │   │
│  │  • CPU/memory usage via Mach task_info                             │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                          macOS Unified Logging                              │
│                                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────────┐     │
│  │ Console.app  │  │  log stream  │  │       Instruments.app        │     │
│  │  (GUI)       │  │  (CLI)       │  │  (Signposts + Profiling)     │     │
│  └──────────────┘  └──────────────┘  └──────────────────────────────┘     │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. os_log Integration for Structured Logging

### 2.1 OSLog Subsystem and Category Setup

VaulType uses Apple's unified logging system (`os_log`) as the sole logging backend. The `Logger` struct (available since macOS 11) provides a type-safe, performant API with automatic privacy handling.

```swift
import OSLog

// MARK: - Subsystem Constant

/// The subsystem identifier for all VaulType log messages.
/// Follows Apple's reverse-DNS convention matching the app's bundle identifier.
enum LogSubsystem {
    static let main = "com.vaultype.app"
}

// MARK: - Log Categories

/// Centralized log category definitions for consistent usage across the codebase.
/// Each category maps to a distinct pipeline or subsystem within VaulType.
enum LogCategory {
    static let audio      = "audio"
    static let whisper    = "whisper"
    static let llm        = "llm"
    static let injection  = "injection"
    static let commands   = "commands"
    static let ui         = "ui"
    static let models     = "models"
    static let system     = "system"
    static let metrics    = "metrics"
    static let sentry     = "sentry"
}

// MARK: - Logger Instances

/// Pre-configured Logger instances for each VaulType subsystem.
/// Usage: `Log.audio.info("Microphone input started")`
enum Log {
    static let audio     = Logger(subsystem: LogSubsystem.main, category: LogCategory.audio)
    static let whisper   = Logger(subsystem: LogSubsystem.main, category: LogCategory.whisper)
    static let llm       = Logger(subsystem: LogSubsystem.main, category: LogCategory.llm)
    static let injection = Logger(subsystem: LogSubsystem.main, category: LogCategory.injection)
    static let commands  = Logger(subsystem: LogSubsystem.main, category: LogCategory.commands)
    static let ui        = Logger(subsystem: LogSubsystem.main, category: LogCategory.ui)
    static let models    = Logger(subsystem: LogSubsystem.main, category: LogCategory.models)
    static let system    = Logger(subsystem: LogSubsystem.main, category: LogCategory.system)
    static let metrics   = Logger(subsystem: LogSubsystem.main, category: LogCategory.metrics)
    static let sentry    = Logger(subsystem: LogSubsystem.main, category: LogCategory.sentry)
}
```

> ℹ️ **Info**: The `Logger` struct is preferred over the older `os_log()` function. It provides string interpolation with compile-time privacy checks, better performance through lazy evaluation, and cleaner syntax.

### 2.2 Log Levels

Apple's unified logging system defines five log levels. VaulType uses each level with specific intent:

| Level | `Logger` Method | Persistence | Purpose in VaulType |
|-------|----------------|-------------|---------------------|
| **Debug** | `.debug()` | Not persisted (development only) | Verbose data for active debugging — buffer sizes, sample rates, intermediate states |
| **Info** | `.info()` | Persisted only during `log collect` | Routine operations — pipeline stage transitions, model loading steps, config changes |
| **Notice** (Default) | `.notice()` | Persisted to disk | Significant events — session start/stop, model swap, permission granted, export completed |
| **Error** | `.error()` | Persisted to disk | Recoverable failures — model load failure, injection fallback, audio device disconnected |
| **Fault** | `.fault()` | Persisted to disk + stack trace | Unrecoverable / logic errors — nil where unexpected, corrupted state, assertion-like failures |

```swift
// MARK: - Log Level Usage Examples

func demonstrateLogLevels() {
    // Debug: Verbose, not persisted in production. Use for values
    // that are only useful during active development.
    Log.audio.debug("Audio buffer received: \(bufferSize, privacy: .public) frames at \(sampleRate, privacy: .public) Hz")

    // Info: Routine operations worth knowing about during log collection.
    Log.whisper.info("Whisper inference started for segment \(segmentIndex, privacy: .public)")

    // Notice: Significant events that mark state transitions.
    Log.system.notice("Dictation session started — mode: \(mode.rawValue, privacy: .public)")

    // Error: Something went wrong but we can recover.
    Log.models.error("Failed to load Whisper model at path: \(path, privacy: .private(mask: .hash)) — error: \(error.localizedDescription, privacy: .public)")

    // Fault: Programming error or corrupted state. Triggers stack capture.
    Log.injection.fault("Text injector received nil target application — this should never happen")
}
```

> ⚠️ **Warning**: Never use `.fault()` for expected failure conditions (network unavailable, file not found, etc.). Reserve it for states that indicate a programming error. Faults capture stack traces and are expensive.

### 2.3 Privacy-Aware Logging

Apple's unified logging system provides compile-time privacy annotations. VaulType enforces strict privacy rules:

**Privacy Rules:**

| Data Type | Privacy Level | Rationale |
|-----------|--------------|-----------|
| Transcribed text | `%{private}` (or never logged) | User speech content — never expose |
| Audio buffer contents | Never logged | Raw audio data — never expose |
| File paths | `%{private(mask: .hash)}` | May contain username — hash only |
| Model names | `%{public}` | Non-sensitive, useful for debugging |
| Numeric metrics | `%{public}` | Timing data, counts — non-sensitive |
| Error descriptions | `%{public}` | System error messages — non-sensitive |
| Bundle identifiers | `%{public}` | App identifiers — non-sensitive |
| Clipboard contents | Never logged | User data — never expose |
| User settings values | `%{private}` | May reveal preferences |

```swift
// MARK: - Privacy-Aware Logging Examples

// CORRECT: Model name is public, path is hashed
Log.models.info("Loading model \(modelName, privacy: .public) from \(filePath, privacy: .private(mask: .hash))")

// CORRECT: Numeric metrics are public
Log.whisper.info("Transcription completed in \(latencyMs, privacy: .public) ms, \(tokenCount, privacy: .public) tokens")

// CORRECT: Error descriptions are public
Log.audio.error("Audio engine failed: \(error.localizedDescription, privacy: .public)")

// WRONG: Never log transcription content
// Log.whisper.info("Transcribed: \(transcription)") // ❌ NEVER DO THIS

// WRONG: Never log clipboard data
// Log.injection.debug("Clipboard: \(pasteboardContent)") // ❌ NEVER DO THIS

// CORRECT: Log the action, not the content
Log.injection.info("Text injected via \(strategy.rawValue, privacy: .public), length: \(characterCount, privacy: .public) chars")
```

> 🔒 **Security**: In release builds, `%{private}` values are replaced with `<private>` in Console.app unless the device has a development profile installed. This is an additional layer of protection beyond our own logging discipline. See [`../security/SECURITY.md`](../security/SECURITY.md) for the complete privacy model.

### 2.4 Signposts for Performance

OSSignposter provides zero-cost (when not profiling) instrumentation that integrates directly with Instruments.app. VaulType uses signposts to bracket every significant operation in the pipeline.

```swift
import OSLog

// MARK: - Signpost Definitions

/// Centralized signpost instances for each performance-critical subsystem.
/// These integrate with Instruments.app's "Points of Interest" and
/// custom Instruments packages.
enum HushSignpost {
    private static let subsystem = LogSubsystem.main

    static let audio = OSSignposter(
        subsystem: subsystem,
        category: "AudioPipeline"
    )
    static let whisper = OSSignposter(
        subsystem: subsystem,
        category: "WhisperInference"
    )
    static let llm = OSSignposter(
        subsystem: subsystem,
        category: "LLMInference"
    )
    static let injection = OSSignposter(
        subsystem: subsystem,
        category: "TextInjection"
    )
    static let modelLoading = OSSignposter(
        subsystem: subsystem,
        category: "ModelLoading"
    )
}

// MARK: - Signpost Usage in Pipeline

/// Example: Bracketing whisper inference with a signpost interval.
func transcribeAudioSegment(_ segment: AudioSegment) async throws -> TranscriptionResult {
    let signpostID = HushSignpost.whisper.makeSignpostID()
    let state = HushSignpost.whisper.beginInterval(
        "Transcription",
        id: signpostID,
        "segment: \(segment.index, privacy: .public), duration: \(segment.durationMs, privacy: .public) ms"
    )

    do {
        let result = try await whisperContext.transcribe(segment)

        HushSignpost.whisper.endInterval(
            "Transcription",
            state,
            "tokens: \(result.tokenCount, privacy: .public), latency: \(result.latencyMs, privacy: .public) ms"
        )

        return result
    } catch {
        HushSignpost.whisper.endInterval(
            "Transcription",
            state,
            "FAILED: \(error.localizedDescription, privacy: .public)"
        )
        throw error
    }
}

/// Example: Using signpost for a quick event (not an interval).
func emitModelLoadEvent(modelName: String, sizeBytes: Int64) {
    HushSignpost.modelLoading.emitEvent(
        "ModelLoaded",
        "model: \(modelName, privacy: .public), size: \(sizeBytes, privacy: .public) bytes"
    )
}
```

> 💡 **Tip**: In Instruments.app, create a custom instrument that tracks `com.vaultype.app` signposts. This gives you a timeline view of the entire dictation pipeline: audio capture, whisper inference, LLM processing, and text injection — all in one trace.

---

## 3. Log Categories

### 3.1 Category Reference Table

| Category | Logger | Subsystem | Description | Typical Log Levels |
|----------|--------|-----------|-------------|--------------------|
| `audio` | `Log.audio` | `com.vaultype.app` | AVAudioEngine capture, sample rate conversion, VAD, ring buffer operations | debug, info, error |
| `whisper` | `Log.whisper` | `com.vaultype.app` | whisper.cpp inference lifecycle — model loading, segment processing, token generation | info, notice, error |
| `llm` | `Log.llm` | `com.vaultype.app` | llama.cpp inference — prompt construction, token generation, mode selection | info, notice, error |
| `injection` | `Log.injection` | `com.vaultype.app` | CGEvent text injection, clipboard operations, fallback strategies, target app detection | info, notice, error |
| `commands` | `Log.commands` | `com.vaultype.app` | Voice command detection, parsing, action execution, custom command registry | info, notice, error |
| `ui` | `Log.ui` | `com.vaultype.app` | SwiftUI view lifecycle, menu bar state, overlay presentation, settings changes | debug, info, error |
| `models` | `Log.models` | `com.vaultype.app` | Model file management — download, verification, deletion, storage calculations | info, notice, error |
| `system` | `Log.system` | `com.vaultype.app` | App lifecycle, permission requests, memory pressure, thermal state, global state transitions | notice, error, fault |
| `metrics` | `Log.metrics` | `com.vaultype.app` | Performance metric recording, aggregation, export events | debug, info |
| `sentry` | `Log.sentry` | `com.vaultype.app` | Sentry SDK lifecycle — initialization, opt-in state, event submission status | info, notice, error |

### 3.2 Subsystem Naming Convention

VaulType uses a single subsystem identifier for all log categories:

```
com.vaultype.app
```

This matches the application's bundle identifier and follows Apple's recommended reverse-DNS convention. A single subsystem keeps filtering simple — one predicate catches all VaulType logs regardless of category.

**Why one subsystem, many categories (not many subsystems)?**

- Console.app's subsystem filter is the coarsest filter — one subsystem = one click to see all VaulType logs
- Categories provide the fine-grained filtering within that subsystem
- Instruments signposts use separate category strings for visual separation in traces
- This matches Apple's own pattern (e.g., `com.apple.network` with categories `connection`, `path`, `resolution`)

### 3.3 Logger Singleton Setup

The `Log` enum from Section 2.1 is the single source of truth for all loggers in the project. Here is the complete implementation file:

```swift
// File: Sources/VaulType/Logging/Log.swift

import OSLog

// MARK: - Log Subsystem

/// Central subsystem identifier. Matches the app bundle ID.
enum LogSubsystem {
    static let main = "com.vaultype.app"
}

// MARK: - Log Category Constants

/// String constants for each log category.
/// Used by Logger instances and Console.app predicates.
enum LogCategory {
    static let audio      = "audio"
    static let whisper    = "whisper"
    static let llm        = "llm"
    static let injection  = "injection"
    static let commands   = "commands"
    static let ui         = "ui"
    static let models     = "models"
    static let system     = "system"
    static let metrics    = "metrics"
    static let sentry     = "sentry"
}

// MARK: - Logger Instances

/// Pre-configured loggers for every VaulType subsystem.
///
/// Usage:
/// ```swift
/// Log.audio.info("Microphone input started")
/// Log.whisper.error("Model failed to load: \(error, privacy: .public)")
/// ```
///
/// These are zero-cost in release builds for `.debug()` calls — the OS
/// discards debug messages without evaluating the interpolation.
enum Log {
    static let audio     = Logger(subsystem: LogSubsystem.main, category: LogCategory.audio)
    static let whisper   = Logger(subsystem: LogSubsystem.main, category: LogCategory.whisper)
    static let llm       = Logger(subsystem: LogSubsystem.main, category: LogCategory.llm)
    static let injection = Logger(subsystem: LogSubsystem.main, category: LogCategory.injection)
    static let commands  = Logger(subsystem: LogSubsystem.main, category: LogCategory.commands)
    static let ui        = Logger(subsystem: LogSubsystem.main, category: LogCategory.ui)
    static let models    = Logger(subsystem: LogSubsystem.main, category: LogCategory.models)
    static let system    = Logger(subsystem: LogSubsystem.main, category: LogCategory.system)
    static let metrics   = Logger(subsystem: LogSubsystem.main, category: LogCategory.metrics)
    static let sentry    = Logger(subsystem: LogSubsystem.main, category: LogCategory.sentry)
}
```

> ℹ️ **Info**: `Logger` instances are lightweight value types. Creating them is essentially free — they just capture the subsystem and category strings. There is no need for lazy initialization or dependency injection.

---

## 4. Console.app Usage for Debugging

### 4.1 Filtering VaulType Logs

Console.app is the primary tool for reading VaulType logs during development and QA. Here is how to set up effective filters:

**Quick Start:**

1. Open Console.app (`/Applications/Utilities/Console.app`)
2. Select your Mac (or an attached device) in the sidebar
3. Click the search bar and type: `subsystem:com.vaultype.app`
4. Press Enter to begin streaming
5. Optionally refine with a category: `category:whisper`

**Compound Filters:**

Console.app supports combining multiple predicates with AND/OR logic. Click the filter bar dropdown to switch between "Any" and "All" matching.

| Filter Goal | Predicate |
|-------------|-----------|
| All VaulType logs | `subsystem:com.vaultype.app` |
| Only audio pipeline | `subsystem:com.vaultype.app AND category:audio` |
| Errors and faults only | `subsystem:com.vaultype.app AND (messageType:error OR messageType:fault)` |
| Whisper + LLM inference | `subsystem:com.vaultype.app AND (category:whisper OR category:llm)` |
| Text injection issues | `subsystem:com.vaultype.app AND category:injection AND messageType:error` |
| Model management | `subsystem:com.vaultype.app AND (category:models OR category:system)` |

### 4.2 Useful Predicates

For advanced filtering, use Console.app's predicate syntax or the `log` CLI tool:

```bash
# Stream all VaulType logs at info level and above
log stream --predicate 'subsystem == "com.vaultype.app"' --level info

# Stream only whisper inference logs
log stream --predicate 'subsystem == "com.vaultype.app" AND category == "whisper"'

# Stream errors and faults across all categories
log stream --predicate 'subsystem == "com.vaultype.app" AND (messageType == 16 OR messageType == 17)'

# Search recent logs for model loading issues
log show --predicate 'subsystem == "com.vaultype.app" AND category == "models"' --last 1h

# Search for a specific error pattern
log show --predicate 'subsystem == "com.vaultype.app" AND eventMessage CONTAINS "failed"' --last 30m

# Export to a file for sharing
log show --predicate 'subsystem == "com.vaultype.app"' --last 2h > ~/Desktop/vaultype-logs.txt
```

> 💡 **Tip**: Create a saved search in Console.app for `subsystem:com.vaultype.app` — it persists across launches and provides one-click access to VaulType logs.

### 4.3 Streaming Logs During Development

During active development in Xcode, logs appear in the Xcode debug console automatically. However, Console.app provides better filtering and is the recommended tool for focused debugging:

**Xcode Console vs Console.app:**

| Feature | Xcode Console | Console.app |
|---------|--------------|-------------|
| Category filtering | No built-in filter | Full predicate support |
| Log level filtering | Shows all levels | Filter by level |
| Persistence | Session only | System log store |
| Signpost visualization | No | Limited (use Instruments) |
| Regex search | No | Yes |
| Save filters | No | Yes |
| Multiple processes | No | Yes |

**Recommended development workflow:**

1. Run VaulType from Xcode (Debug scheme)
2. Open Console.app side-by-side
3. Set the predicate to the category you are working on
4. Use Xcode breakpoints for state inspection, Console.app for log flow

```bash
# Terminal-based streaming (useful for CI or headless debugging)
log stream \
  --predicate 'subsystem == "com.vaultype.app"' \
  --level debug \
  --style compact
```

### 4.4 Log Export

For bug reports and diagnostics, logs can be exported using the CLI:

```bash
# Collect a log archive (includes all system logs — can be large)
sudo log collect --device --last 1h --output ~/Desktop/vaultype-log-archive.logarchive

# Export only VaulType logs as human-readable text
log show \
  --predicate 'subsystem == "com.vaultype.app"' \
  --last 4h \
  --style json \
  > ~/Desktop/vaultype-logs.json

# Export with timestamps and process info
log show \
  --predicate 'subsystem == "com.vaultype.app"' \
  --last 4h \
  --info \
  --debug \
  --style default \
  > ~/Desktop/vaultype-full-logs.txt
```

> ⚠️ **Warning**: Exported logs from development builds may contain `%{private}` values in cleartext. Never share development log exports publicly without reviewing them first. Production builds redact private values automatically.

---

## 5. Crash Reporting with Sentry (Opt-In)

### 5.1 Privacy-Respecting Configuration

VaulType offers optional crash reporting via Sentry. This feature is **disabled by default** and requires explicit user opt-in. The integration is configured to be maximally privacy-respecting:

```swift
// File: Sources/VaulType/Monitoring/SentryConfiguration.swift

import Foundation
import OSLog

#if canImport(Sentry)
import Sentry
#endif

// MARK: - Sentry Configuration

/// Manages the optional, opt-in Sentry crash reporting integration.
///
/// Privacy guarantees:
/// - Disabled by default — requires explicit user opt-in
/// - No PII collection (IP address, device name stripped)
/// - No audio data, transcription text, or clipboard content
/// - No user-identifiable breadcrumbs
/// - DSN stored in Keychain, not hardcoded
/// - Can be fully disabled at any time
final class SentryConfiguration {
    static let shared = SentryConfiguration()

    private let logger = Log.sentry
    private let sentryOptInKey = "com.vaultype.sentry.optIn"

    /// Whether the user has explicitly opted in to crash reporting.
    var isOptedIn: Bool {
        get { UserDefaults.standard.bool(forKey: sentryOptInKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: sentryOptInKey)
            if newValue {
                startSentry()
            } else {
                stopSentry()
            }
            logger.notice("Sentry opt-in changed to: \(newValue, privacy: .public)")
        }
    }

    // MARK: - Initialization

    /// Call this at app launch. Only initializes Sentry if the user has opted in.
    func configureIfOptedIn() {
        guard isOptedIn else {
            logger.info("Sentry is disabled — user has not opted in")
            return
        }
        startSentry()
    }

    // MARK: - Start / Stop

    private func startSentry() {
        #if canImport(Sentry)
        guard let dsn = loadDSN() else {
            logger.error("Sentry DSN not found — cannot initialize")
            return
        }

        SentrySDK.start { options in
            options.dsn = dsn

            // Privacy: Strip all PII
            options.sendDefaultPii = false

            // Privacy: Do not send device name or user info
            options.attachViewHierarchy = false

            // Privacy: Disable screenshot capture
            options.attachScreenshot = false

            // Privacy: Limit breadcrumbs to non-PII events
            options.maxBreadcrumbs = 50

            // Performance: Sample 100% of crashes, 10% of transactions
            options.sampleRate = 1.0
            options.tracesSampleRate = 0.1

            // Only send crash events, not all errors
            options.enableCaptureFailedRequests = false

            // Disable automatic session tracking
            options.enableAutoSessionTracking = false

            // Environment tag
            #if DEBUG
            options.environment = "development"
            #else
            options.environment = "production"
            #endif

            // App version
            options.releaseName = Bundle.main.appVersionString

            // Privacy: Custom beforeSend to strip any remaining PII
            options.beforeSend = { event in
                return SentryConfiguration.sanitizeEvent(event)
            }

            // Privacy: Custom breadcrumb filter
            options.beforeBreadcrumb = { breadcrumb in
                return SentryConfiguration.sanitizeBreadcrumb(breadcrumb)
            }
        }

        logger.notice("Sentry initialized successfully")
        #else
        logger.info("Sentry SDK not available in this build")
        #endif
    }

    private func stopSentry() {
        #if canImport(Sentry)
        SentrySDK.close()
        logger.notice("Sentry closed")
        #endif
    }

    // MARK: - DSN Management

    /// Loads the Sentry DSN from the Keychain.
    /// The DSN is stored in the Keychain rather than hardcoded to allow
    /// updates without app releases and to avoid leaking it in source control.
    private func loadDSN() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.vaultype.sentry",
            kSecAttrAccount as String: "dsn",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let dsn = String(data: data, encoding: .utf8) else {
            return nil
        }

        return dsn
    }

    // MARK: - PII Sanitization

    /// Strips any remaining PII from Sentry events before transmission.
    #if canImport(Sentry)
    private static func sanitizeEvent(_ event: Event) -> Event? {
        // Strip user info
        event.user = nil

        // Strip device name
        event.context?["device"]?["name"] = nil

        // Strip any file paths that might contain usernames
        if let exceptions = event.exceptions {
            for exception in exceptions {
                if let frames = exception.stacktrace?.frames {
                    for frame in frames {
                        // Hash file paths to remove username components
                        if let filename = frame.fileName, filename.contains("/Users/") {
                            frame.fileName = filename.replacingOccurrences(
                                of: #"/Users/[^/]+"#,
                                with: "/Users/<redacted>",
                                options: .regularExpression
                            )
                        }
                    }
                }
            }
        }

        return event
    }

    /// Filters breadcrumbs to remove any that might contain user content.
    private static func sanitizeBreadcrumb(_ breadcrumb: Breadcrumb) -> Breadcrumb? {
        // Allow only specific breadcrumb categories
        let allowedCategories: Set<String> = [
            "app.lifecycle",
            "device.orientation",
            "vaultype.pipeline",
            "vaultype.model",
            "vaultype.system"
        ]

        guard let category = breadcrumb.category,
              allowedCategories.contains(category) else {
            return nil
        }

        // Strip any message data that might contain user content
        breadcrumb.data?.removeAll()

        return breadcrumb
    }
    #endif
}

// MARK: - Bundle Extension

private extension Bundle {
    var appVersionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "com.vaultype.app@\(version)+\(build)"
    }
}
```

### 5.2 Opt-In Flow

The Sentry opt-in is presented in the Settings view under a dedicated "Privacy & Diagnostics" section. The user must take an explicit action to enable it:

```swift
// File: Sources/VaulType/Views/Settings/DiagnosticsSettingsView.swift

import SwiftUI

struct DiagnosticsSettingsView: View {
    @State private var isCrashReportingEnabled: Bool = SentryConfiguration.shared.isOptedIn
    @State private var showingPrivacyDetails = false

    var body: some View {
        Form {
            Section {
                Toggle("Send Crash Reports", isOn: $isCrashReportingEnabled)
                    .onChange(of: isCrashReportingEnabled) { _, newValue in
                        SentryConfiguration.shared.isOptedIn = newValue
                    }

                Text("When enabled, anonymous crash reports help us fix bugs faster. No transcription text, audio, or personal data is ever included.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("What data is sent?") {
                    showingPrivacyDetails = true
                }
                .font(.caption)

            } header: {
                Label("Crash Reporting (Optional)", systemImage: "ant.fill")
            }
        }
        .sheet(isPresented: $showingPrivacyDetails) {
            CrashReportPrivacyDetailView()
        }
    }
}
```

> 🔒 **Security**: The opt-in toggle defaults to `false`. Crash reporting is never silently enabled. The user sees exactly what categories of data are included before opting in.

### 5.3 DSN Configuration

The Sentry DSN (Data Source Name) is provisioned during the build process and stored in the Keychain at first launch:

```swift
// Called once during onboarding or first launch
func provisionSentryDSN() {
    // DSN is embedded in the app bundle via build configuration,
    // then moved to the Keychain for secure storage.
    guard let embeddedDSN = Bundle.main.object(
        forInfoDictionaryKey: "SENTRY_DSN"
    ) as? String, !embeddedDSN.isEmpty else {
        Log.sentry.info("No Sentry DSN configured in build")
        return
    }

    let addQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.vaultype.sentry",
        kSecAttrAccount as String: "dsn",
        kSecValueData as String: embeddedDSN.data(using: .utf8)!,
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
    ]

    let status = SecItemAdd(addQuery as CFDictionary, nil)
    if status == errSecDuplicateItem {
        Log.sentry.debug("Sentry DSN already in Keychain")
    } else if status == errSecSuccess {
        Log.sentry.info("Sentry DSN stored in Keychain")
    } else {
        Log.sentry.error("Failed to store Sentry DSN: \(status, privacy: .public)")
    }
}
```

### 5.4 Breadcrumbs

VaulType adds custom breadcrumbs for pipeline events that help diagnose crashes without revealing user content:

```swift
#if canImport(Sentry)
import Sentry

/// Adds a privacy-safe breadcrumb to the Sentry trail.
/// Only records pipeline stage transitions, never content.
enum SentryBreadcrumbs {
    static func pipelineStageChanged(from: String, to: String) {
        let crumb = Breadcrumb(level: .info, category: "vaultype.pipeline")
        crumb.message = "Pipeline: \(from) -> \(to)"
        SentrySDK.addBreadcrumb(crumb)
    }

    static func modelLoaded(name: String, type: String) {
        let crumb = Breadcrumb(level: .info, category: "vaultype.model")
        crumb.message = "Model loaded: \(type)/\(name)"
        SentrySDK.addBreadcrumb(crumb)
    }

    static func systemEvent(_ event: String) {
        let crumb = Breadcrumb(level: .info, category: "vaultype.system")
        crumb.message = event
        SentrySDK.addBreadcrumb(crumb)
    }
}
#endif
```

### 5.5 What Is Never Sent

For absolute clarity, Sentry is configured to **never** transmit:

| Data Category | Status | Enforcement Mechanism |
|---------------|--------|----------------------|
| Transcribed text | **Never sent** | Never added to breadcrumbs or context |
| Audio buffers | **Never sent** | Never logged or captured |
| Clipboard contents | **Never sent** | Never logged or captured |
| User file paths (full) | **Never sent** | Regex-stripped in `beforeSend` |
| IP address | **Never sent** | `sendDefaultPii = false` |
| Device name | **Never sent** | Stripped in `beforeSend` |
| Username | **Never sent** | Stripped from paths in `beforeSend` |
| Screenshots | **Never sent** | `attachScreenshot = false` |
| View hierarchy | **Never sent** | `attachViewHierarchy = false` |

> ❌ **Critical**: If any future development inadvertently adds user content to Sentry events, the `beforeSend` hook acts as a last line of defense. However, the correct approach is to never add such data in the first place.

---

## 6. Performance Metrics Collection (Local Only)

### 6.1 Metrics Data Model

Performance metrics are stored locally in SwiftData. They never leave the device unless the user explicitly exports a diagnostic bundle.

```swift
// File: Sources/VaulType/Models/PerformanceMetric.swift

import Foundation
import SwiftData

// MARK: - Metric Type

/// Enumeration of all tracked performance metric types.
enum MetricType: String, Codable, CaseIterable {
    case transcriptionLatency   = "transcription_latency"
    case llmInferenceTime       = "llm_inference_time"
    case textInjectionTime      = "text_injection_time"
    case whisperModelLoadTime   = "whisper_model_load_time"
    case llmModelLoadTime       = "llm_model_load_time"
    case audioBufferOverrun     = "audio_buffer_overrun"
    case audioBufferUnderrun    = "audio_buffer_underrun"
    case endToEndLatency        = "end_to_end_latency"
    case memoryPeakUsage        = "memory_peak_usage"
    case thermalThrottle        = "thermal_throttle"
}

// MARK: - SwiftData Model

/// A single performance metric data point.
///
/// Stored locally in SwiftData. Retained for up to 30 days, then pruned.
/// No user content (text, audio) is ever stored in metric records.
@Model
final class PerformanceMetric {
    /// Unique identifier for this metric entry.
    var id: UUID

    /// The type of metric being recorded.
    var type: MetricType

    /// The measured value in milliseconds (for time-based metrics)
    /// or bytes (for memory metrics) or count (for buffer events).
    var value: Double

    /// Optional: Which Whisper model was active during this measurement.
    var whisperModelName: String?

    /// Optional: Which LLM model was active during this measurement.
    var llmModelName: String?

    /// Timestamp when this metric was recorded.
    var timestamp: Date

    /// Optional: Additional context (e.g., audio segment duration, token count).
    /// Must NEVER contain user-generated content.
    var metadata: [String: String]?

    init(
        type: MetricType,
        value: Double,
        whisperModelName: String? = nil,
        llmModelName: String? = nil,
        metadata: [String: String]? = nil
    ) {
        self.id = UUID()
        self.type = type
        self.value = value
        self.whisperModelName = whisperModelName
        self.llmModelName = llmModelName
        self.timestamp = Date()
        self.metadata = metadata
    }
}
```

> ℹ️ **Info**: The `PerformanceMetric` model integrates with the existing SwiftData store described in [`../architecture/DATABASE_SCHEMA.md`](../architecture/DATABASE_SCHEMA.md). Metrics are stored in the same `VaulType.store` SQLite database alongside other app data.

### 6.2 Metrics Collection Service

The `MetricsCollectionService` is the central hub for recording and querying performance data:

```swift
// File: Sources/VaulType/Monitoring/MetricsCollectionService.swift

import Foundation
import SwiftData
import OSLog

// MARK: - Metrics Collection Service

/// Collects and stores performance metrics locally in SwiftData.
///
/// All data remains on-device. Metrics are used for:
/// - Displaying performance stats in Settings
/// - Populating diagnostic bundles for bug reports
/// - Detecting performance regressions during development
///
/// Thread Safety: All writes are dispatched to a dedicated ModelActor.
@Observable
final class MetricsCollectionService {
    private let logger = Log.metrics
    private let modelContainer: ModelContainer
    private let metricsActor: MetricsModelActor

    /// Rolling statistics for the current session (in-memory only).
    private(set) var currentSessionStats = SessionStats()

    /// Maximum age for stored metrics before pruning (30 days).
    private let maxMetricAge: TimeInterval = 30 * 24 * 60 * 60

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.metricsActor = MetricsModelActor(modelContainer: modelContainer)
    }

    // MARK: - Recording Metrics

    /// Records a performance metric and stores it in SwiftData.
    ///
    /// - Parameters:
    ///   - type: The metric type (e.g., `.transcriptionLatency`)
    ///   - value: The measured value (milliseconds, bytes, or count)
    ///   - whisperModel: Optional active Whisper model name
    ///   - llmModel: Optional active LLM model name
    ///   - metadata: Optional non-PII context
    func record(
        _ type: MetricType,
        value: Double,
        whisperModel: String? = nil,
        llmModel: String? = nil,
        metadata: [String: String]? = nil
    ) async {
        let metric = PerformanceMetric(
            type: type,
            value: value,
            whisperModelName: whisperModel,
            llmModelName: llmModel,
            metadata: metadata
        )

        // Update in-memory session stats
        currentSessionStats.update(type: type, value: value)

        // Persist to SwiftData
        await metricsActor.insert(metric)

        logger.debug("Recorded metric: \(type.rawValue, privacy: .public) = \(value, privacy: .public)")
    }

    // MARK: - Querying Metrics

    /// Returns aggregated statistics for a given metric type over a time range.
    func aggregateStats(
        for type: MetricType,
        since: Date = Date(timeIntervalSinceNow: -7 * 24 * 60 * 60)
    ) async -> AggregateMetricStats? {
        return await metricsActor.aggregateStats(for: type, since: since)
    }

    /// Returns the most recent N metrics of a given type.
    func recentMetrics(
        for type: MetricType,
        limit: Int = 100
    ) async -> [PerformanceMetric] {
        return await metricsActor.recentMetrics(for: type, limit: limit)
    }

    // MARK: - Pruning

    /// Removes metrics older than `maxMetricAge`. Called periodically.
    func pruneOldMetrics() async {
        let cutoff = Date(timeIntervalSinceNow: -maxMetricAge)
        let deletedCount = await metricsActor.deleteMetrics(olderThan: cutoff)
        logger.info("Pruned \(deletedCount, privacy: .public) metrics older than 30 days")
    }
}

// MARK: - Model Actor for Thread-Safe SwiftData Access

@ModelActor
actor MetricsModelActor {
    func insert(_ metric: PerformanceMetric) {
        modelContext.insert(metric)
        try? modelContext.save()
    }

    func aggregateStats(for type: MetricType, since: Date) -> AggregateMetricStats? {
        let predicate = #Predicate<PerformanceMetric> {
            $0.type == type && $0.timestamp >= since
        }
        let descriptor = FetchDescriptor<PerformanceMetric>(predicate: predicate)

        guard let metrics = try? modelContext.fetch(descriptor),
              !metrics.isEmpty else {
            return nil
        }

        let values = metrics.map(\.value)
        let sorted = values.sorted()

        return AggregateMetricStats(
            count: metrics.count,
            mean: values.reduce(0, +) / Double(values.count),
            median: sorted[sorted.count / 2],
            min: sorted.first ?? 0,
            max: sorted.last ?? 0,
            p95: sorted[Int(Double(sorted.count) * 0.95)],
            stddev: standardDeviation(values)
        )
    }

    func recentMetrics(for type: MetricType, limit: Int) -> [PerformanceMetric] {
        var descriptor = FetchDescriptor<PerformanceMetric>(
            predicate: #Predicate { $0.type == type },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func deleteMetrics(olderThan date: Date) -> Int {
        let predicate = #Predicate<PerformanceMetric> {
            $0.timestamp < date
        }
        let descriptor = FetchDescriptor<PerformanceMetric>(predicate: predicate)
        guard let metrics = try? modelContext.fetch(descriptor) else { return 0 }
        let count = metrics.count
        metrics.forEach { modelContext.delete($0) }
        try? modelContext.save()
        return count
    }

    private func standardDeviation(_ values: [Double]) -> Double {
        let count = Double(values.count)
        guard count > 1 else { return 0 }
        let mean = values.reduce(0, +) / count
        let sumOfSquaredDiffs = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        return (sumOfSquaredDiffs / (count - 1)).squareRoot()
    }
}

// MARK: - Supporting Types

/// Aggregated statistics for a metric type over a time period.
struct AggregateMetricStats: Sendable {
    let count: Int
    let mean: Double
    let median: Double
    let min: Double
    let max: Double
    let p95: Double
    let stddev: Double
}

/// In-memory per-session rolling statistics.
struct SessionStats {
    private(set) var transcriptionCount: Int = 0
    private(set) var averageTranscriptionLatency: Double = 0
    private(set) var averageLLMLatency: Double = 0
    private(set) var averageInjectionTime: Double = 0
    private(set) var peakMemoryMB: Double = 0

    mutating func update(type: MetricType, value: Double) {
        switch type {
        case .transcriptionLatency:
            let total = averageTranscriptionLatency * Double(transcriptionCount)
            transcriptionCount += 1
            averageTranscriptionLatency = (total + value) / Double(transcriptionCount)
        case .llmInferenceTime:
            averageLLMLatency = (averageLLMLatency + value) / 2.0
        case .textInjectionTime:
            averageInjectionTime = (averageInjectionTime + value) / 2.0
        case .memoryPeakUsage:
            peakMemoryMB = max(peakMemoryMB, value)
        default:
            break
        }
    }
}
```

### 6.3 Transcription Latency Tracking

```swift
/// Records the time from audio segment submission to transcription result.
func trackTranscription(
    segment: AudioSegment,
    metricsService: MetricsCollectionService,
    activeWhisperModel: String
) async throws -> TranscriptionResult {
    let signpostID = HushSignpost.whisper.makeSignpostID()
    let state = HushSignpost.whisper.beginInterval("Transcription", id: signpostID)

    let start = ContinuousClock.now

    let result = try await whisperContext.transcribe(segment)

    let elapsed = start.duration(to: .now)
    let latencyMs = Double(elapsed.components.attoseconds) / 1_000_000_000_000_000

    HushSignpost.whisper.endInterval("Transcription", state)

    await metricsService.record(
        .transcriptionLatency,
        value: latencyMs,
        whisperModel: activeWhisperModel,
        metadata: [
            "segmentDurationMs": "\(segment.durationMs)",
            "tokenCount": "\(result.tokenCount)"
        ]
    )

    Log.whisper.info(
        "Transcription: \(latencyMs, privacy: .public) ms, "
        + "\(result.tokenCount, privacy: .public) tokens, "
        + "model: \(activeWhisperModel, privacy: .public)"
    )

    return result
}
```

### 6.4 LLM Inference Time Tracking

```swift
/// Records LLM post-processing inference time.
func trackLLMInference(
    prompt: PreparedPrompt,
    metricsService: MetricsCollectionService,
    activeLLMModel: String
) async throws -> LLMResult {
    let signpostID = HushSignpost.llm.makeSignpostID()
    let state = HushSignpost.llm.beginInterval("LLMInference", id: signpostID)

    let start = ContinuousClock.now

    let result = try await llamaContext.generate(prompt)

    let elapsed = start.duration(to: .now)
    let latencyMs = Double(elapsed.components.attoseconds) / 1_000_000_000_000_000

    HushSignpost.llm.endInterval("LLMInference", state)

    await metricsService.record(
        .llmInferenceTime,
        value: latencyMs,
        llmModel: activeLLMModel,
        metadata: [
            "promptTokens": "\(prompt.tokenCount)",
            "outputTokens": "\(result.outputTokenCount)",
            "mode": prompt.mode.rawValue
        ]
    )

    Log.llm.info(
        "LLM inference: \(latencyMs, privacy: .public) ms, "
        + "\(result.outputTokenCount, privacy: .public) output tokens, "
        + "model: \(activeLLMModel, privacy: .public)"
    )

    return result
}
```

### 6.5 Text Injection Time Tracking

```swift
/// Records the time taken to inject text into the target application.
func trackTextInjection(
    strategy: InjectionStrategy,
    characterCount: Int,
    metricsService: MetricsCollectionService
) async throws {
    let signpostID = HushSignpost.injection.makeSignpostID()
    let state = HushSignpost.injection.beginInterval("TextInjection", id: signpostID)

    let start = ContinuousClock.now

    try await textInjector.inject(using: strategy)

    let elapsed = start.duration(to: .now)
    let latencyMs = Double(elapsed.components.attoseconds) / 1_000_000_000_000_000

    HushSignpost.injection.endInterval("TextInjection", state)

    await metricsService.record(
        .textInjectionTime,
        value: latencyMs,
        metadata: [
            "strategy": strategy.rawValue,
            "characterCount": "\(characterCount)"
        ]
    )

    Log.injection.info(
        "Injection: \(latencyMs, privacy: .public) ms via \(strategy.rawValue, privacy: .public), "
        + "\(characterCount, privacy: .public) chars"
    )
}
```

### 6.6 Model Load Time Tracking

```swift
/// Records model load time for both Whisper and LLM models.
func trackModelLoad(
    modelName: String,
    modelType: ModelType,
    metricsService: MetricsCollectionService,
    loadBlock: () async throws -> Void
) async throws {
    let signpostID = HushSignpost.modelLoading.makeSignpostID()
    let state = HushSignpost.modelLoading.beginInterval("ModelLoad", id: signpostID)

    let start = ContinuousClock.now

    try await loadBlock()

    let elapsed = start.duration(to: .now)
    let latencyMs = Double(elapsed.components.attoseconds) / 1_000_000_000_000_000

    HushSignpost.modelLoading.endInterval("ModelLoad", state)
    HushSignpost.modelLoading.emitEvent(
        "ModelLoaded",
        "model: \(modelName, privacy: .public), type: \(modelType.rawValue, privacy: .public)"
    )

    let metricType: MetricType = modelType == .whisper
        ? .whisperModelLoadTime
        : .llmModelLoadTime

    await metricsService.record(
        metricType,
        value: latencyMs,
        whisperModel: modelType == .whisper ? modelName : nil,
        llmModel: modelType == .llm ? modelName : nil,
        metadata: ["modelType": modelType.rawValue]
    )

    Log.models.notice(
        "Model loaded: \(modelName, privacy: .public) "
        + "(\(modelType.rawValue, privacy: .public)) in \(latencyMs, privacy: .public) ms"
    )
}

enum ModelType: String, Codable {
    case whisper = "whisper"
    case llm = "llm"
}
```

### 6.7 Audio Buffer Statistics

```swift
/// Tracks audio buffer health — overruns and underruns indicate pipeline pressure.
final class AudioBufferMonitor {
    private let metricsService: MetricsCollectionService
    private let logger = Log.audio
    private var overrunCount: Int = 0
    private var underrunCount: Int = 0

    init(metricsService: MetricsCollectionService) {
        self.metricsService = metricsService
    }

    /// Called when the ring buffer drops samples because the consumer is too slow.
    func recordOverrun(droppedFrames: Int) async {
        overrunCount += 1
        await metricsService.record(
            .audioBufferOverrun,
            value: Double(droppedFrames),
            metadata: [
                "cumulativeOverruns": "\(overrunCount)"
            ]
        )
        logger.error("Audio buffer overrun: \(droppedFrames, privacy: .public) frames dropped (total: \(self.overrunCount, privacy: .public))")
    }

    /// Called when the consumer requests audio but the buffer is empty.
    func recordUnderrun() async {
        underrunCount += 1
        await metricsService.record(
            .audioBufferUnderrun,
            value: 1,
            metadata: [
                "cumulativeUnderruns": "\(underrunCount)"
            ]
        )
        logger.error("Audio buffer underrun (total: \(self.underrunCount, privacy: .public))")
    }

    /// Resets per-session counters.
    func resetSessionCounters() {
        overrunCount = 0
        underrunCount = 0
    }
}
```

> 💡 **Tip**: View collected metrics in Settings > Advanced > Performance Statistics. The UI shows rolling averages and P95 latencies for the past 7 days, broken down by model.

---

## 7. Diagnostics Export for Bug Reports

### 7.1 Diagnostic Bundle Contents

When a user files a bug report, VaulType can generate a diagnostic bundle containing everything needed to diagnose the issue — without any user-generated content.

**Included in the bundle:**

| File | Contents | Privacy |
|------|----------|---------|
| `system_info.json` | macOS version, chip, RAM, disk space, VaulType version | Safe |
| `model_info.json` | Installed models, sizes, checksums, load times | Safe |
| `settings_sanitized.json` | Non-sensitive settings (UI prefs, model selections) — no paths, no content | Safe |
| `performance_metrics.json` | Last 7 days of aggregated metrics (no individual entries) | Safe |
| `recent_logs.txt` | Last 2 hours of VaulType os_log entries (privacy-redacted) | Reviewed |
| `audio_config.json` | Audio device info, sample rate, buffer size — no audio data | Safe |
| `thermal_memory.json` | Thermal state history, memory pressure events | Safe |
| `crash_logs/` | Any recent crash logs from `~/Library/Logs/DiagnosticReports/` | Reviewed |

**Never included:**

| Data | Reason |
|------|--------|
| Transcription history | Contains user speech content |
| Audio recordings | Contains user voice data |
| Clipboard contents | May contain sensitive data |
| Full file paths | May contain username |
| Keychain items | Encrypted credentials |
| Custom vocabulary entries | May contain sensitive terms |

### 7.2 Bundle Generation

```swift
// File: Sources/VaulType/Monitoring/DiagnosticExporter.swift

import Foundation
import OSLog
import SwiftData

// MARK: - Diagnostic Exporter

/// Generates a privacy-safe diagnostic bundle for bug reports.
///
/// The bundle is a ZIP archive containing system info, sanitized settings,
/// aggregated performance metrics, and redacted logs. No user content
/// (transcriptions, audio, clipboard) is ever included.
final class DiagnosticExporter {
    private let logger = Log.system
    private let metricsService: MetricsCollectionService
    private let fileManager = FileManager.default

    init(metricsService: MetricsCollectionService) {
        self.metricsService = metricsService
    }

    // MARK: - Bundle Generation

    /// Generates a diagnostic bundle and returns the URL to the ZIP file.
    ///
    /// - Returns: URL to the generated `.zip` file in the temporary directory.
    /// - Throws: If any step of the generation fails.
    func generateBundle() async throws -> URL {
        let bundleDir = fileManager.temporaryDirectory
            .appendingPathComponent("VaulType-Diagnostics-\(bundleTimestamp())")

        try fileManager.createDirectory(at: bundleDir, withIntermediateDirectories: true)

        logger.notice("Generating diagnostic bundle at \(bundleDir.path, privacy: .private(mask: .hash))")

        // Generate each component in parallel where possible
        async let systemInfo = generateSystemInfo(in: bundleDir)
        async let modelInfo = generateModelInfo(in: bundleDir)
        async let settings = generateSanitizedSettings(in: bundleDir)
        async let metrics = generateMetricsSummary(in: bundleDir)
        async let audioConfig = generateAudioConfig(in: bundleDir)
        async let thermalMemory = generateThermalMemoryReport(in: bundleDir)

        // Await all components
        _ = try await (systemInfo, modelInfo, settings, metrics, audioConfig, thermalMemory)

        // Collect recent logs (sequential — reads from log store)
        try await collectRecentLogs(in: bundleDir)

        // Collect crash logs if available
        try collectCrashLogs(in: bundleDir)

        // Generate the privacy manifest
        try generatePrivacyManifest(in: bundleDir)

        // ZIP the bundle
        let zipURL = try zipBundle(at: bundleDir)

        // Clean up the unzipped directory
        try? fileManager.removeItem(at: bundleDir)

        logger.notice("Diagnostic bundle generated: \(zipURL.lastPathComponent, privacy: .public)")

        return zipURL
    }

    // MARK: - System Info

    private func generateSystemInfo(in directory: URL) throws {
        let processInfo = ProcessInfo.processInfo
        let systemInfo: [String: Any] = [
            "vaultype_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "unknown",
            "vaultype_build": Bundle.main.infoDictionary?["CFBundleVersion"] ?? "unknown",
            "macos_version": processInfo.operatingSystemVersionString,
            "macos_build": macOSBuildNumber(),
            "chip": cpuArchitecture(),
            "physical_memory_gb": Double(processInfo.physicalMemory) / 1_073_741_824,
            "processor_count": processInfo.processorCount,
            "active_processor_count": processInfo.activeProcessorCount,
            "thermal_state": thermalStateString(processInfo.thermalState),
            "uptime_hours": processInfo.systemUptime / 3600,
            "is_low_power_mode": processInfo.isLowPowerModeEnabled,
            "bundle_identifier": Bundle.main.bundleIdentifier ?? "unknown",
            "generation_timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        let data = try JSONSerialization.data(
            withJSONObject: systemInfo,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: directory.appendingPathComponent("system_info.json"))
    }

    // MARK: - Model Info

    private func generateModelInfo(in directory: URL) async throws {
        // Query installed models from SwiftData
        let modelInfo: [String: Any] = [
            "installed_models": await getInstalledModelSummaries(),
            "models_directory_size_mb": modelsDirectorySizeMB(),
            "generation_timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        let data = try JSONSerialization.data(
            withJSONObject: modelInfo,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: directory.appendingPathComponent("model_info.json"))
    }

    // MARK: - Sanitized Settings

    private func generateSanitizedSettings(in directory: URL) throws {
        // Export only non-sensitive settings
        let defaults = UserDefaults.standard
        let safeKeys: [String] = [
            "com.vaultype.selectedWhisperModel",
            "com.vaultype.selectedLLMModel",
            "com.vaultype.llmMode",
            "com.vaultype.injectionStrategy",
            "com.vaultype.overlayPosition",
            "com.vaultype.overlayEnabled",
            "com.vaultype.vadSensitivity",
            "com.vaultype.hotkey",
            "com.vaultype.selectedLanguage",
            "com.vaultype.sentry.optIn"
        ]

        var settings: [String: Any] = [:]
        for key in safeKeys {
            if let value = defaults.object(forKey: key) {
                settings[key] = value
            }
        }
        settings["generation_timestamp"] = ISO8601DateFormatter().string(from: Date())

        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: directory.appendingPathComponent("settings_sanitized.json"))
    }

    // MARK: - Metrics Summary

    private func generateMetricsSummary(in directory: URL) async throws {
        var summary: [String: Any] = [:]

        for metricType in MetricType.allCases {
            if let stats = await metricsService.aggregateStats(for: metricType) {
                summary[metricType.rawValue] = [
                    "count": stats.count,
                    "mean": String(format: "%.2f", stats.mean),
                    "median": String(format: "%.2f", stats.median),
                    "min": String(format: "%.2f", stats.min),
                    "max": String(format: "%.2f", stats.max),
                    "p95": String(format: "%.2f", stats.p95)
                ]
            }
        }

        summary["period"] = "last_7_days"
        summary["generation_timestamp"] = ISO8601DateFormatter().string(from: Date())

        let data = try JSONSerialization.data(
            withJSONObject: summary,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: directory.appendingPathComponent("performance_metrics.json"))
    }

    // MARK: - Audio Config

    private func generateAudioConfig(in directory: URL) throws {
        let audioConfig: [String: Any] = [
            "input_device": currentAudioInputDeviceName(),
            "sample_rate": currentSampleRate(),
            "buffer_size": currentBufferSize(),
            "channel_count": currentChannelCount(),
            "generation_timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        let data = try JSONSerialization.data(
            withJSONObject: audioConfig,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: directory.appendingPathComponent("audio_config.json"))
    }

    // MARK: - Thermal & Memory Report

    private func generateThermalMemoryReport(in directory: URL) throws {
        let report: [String: Any] = [
            "current_memory_usage_mb": currentMemoryUsageMB(),
            "physical_memory_gb": Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824,
            "thermal_state": thermalStateString(ProcessInfo.processInfo.thermalState),
            "is_low_power_mode": ProcessInfo.processInfo.isLowPowerModeEnabled,
            "generation_timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        let data = try JSONSerialization.data(
            withJSONObject: report,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: directory.appendingPathComponent("thermal_memory.json"))
    }

    // MARK: - Recent Logs

    private func collectRecentLogs(in directory: URL) async throws {
        // Use the `log` CLI to collect recent VaulType logs
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "show",
            "--predicate", "subsystem == \"com.vaultype.app\"",
            "--last", "2h",
            "--style", "default"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let logData = pipe.fileHandleForReading.readDataToEndOfFile()
        try logData.write(to: directory.appendingPathComponent("recent_logs.txt"))

        logger.info("Collected recent logs: \(logData.count, privacy: .public) bytes")
    }

    // MARK: - Crash Logs

    private func collectCrashLogs(in directory: URL) throws {
        let crashDir = directory.appendingPathComponent("crash_logs")
        try fileManager.createDirectory(at: crashDir, withIntermediateDirectories: true)

        let diagnosticReports = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports")

        guard let contents = try? fileManager.contentsOfDirectory(
            at: diagnosticReports,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return
        }

        // Only include VaulType crash logs from the last 7 days
        let sevenDaysAgo = Date(timeIntervalSinceNow: -7 * 24 * 60 * 60)

        for file in contents where file.lastPathComponent.contains("VaulType") {
            let attributes = try? fileManager.attributesOfItem(atPath: file.path)
            if let created = attributes?[.creationDate] as? Date, created > sevenDaysAgo {
                try? fileManager.copyItem(
                    at: file,
                    to: crashDir.appendingPathComponent(file.lastPathComponent)
                )
            }
        }
    }

    // MARK: - Privacy Manifest

    private func generatePrivacyManifest(in directory: URL) throws {
        let manifest = """
        VaulType Diagnostic Bundle - Privacy Manifest
        ==============================================
        Generated: \(ISO8601DateFormatter().string(from: Date()))

        This bundle contains ONLY the following data:
        - System hardware/software information
        - Installed ML model metadata (names, sizes)
        - Non-sensitive application settings
        - Aggregated performance metrics (timing data only)
        - Audio device configuration (no audio data)
        - Thermal and memory state information
        - Recent application logs (privacy-redacted by macOS)
        - Recent crash logs (if any)

        This bundle does NOT contain:
        - Transcription text or history
        - Audio recordings or samples
        - Clipboard contents
        - Full file paths (may contain username)
        - Keychain items or credentials
        - Custom vocabulary entries
        - Any personally identifiable information (PII)

        You may review all files in this bundle before sharing.
        """

        try manifest.data(using: .utf8)?
            .write(to: directory.appendingPathComponent("PRIVACY_MANIFEST.txt"))
    }

    // MARK: - ZIP

    private func zipBundle(at directory: URL) throws -> URL {
        let zipURL = directory.deletingLastPathComponent()
            .appendingPathComponent("\(directory.lastPathComponent).zip")

        let coordinator = NSFileCoordinator()
        var error: NSError?

        coordinator.coordinate(
            readingItemAt: directory,
            options: .forUploading,
            error: &error
        ) { tempURL in
            try? FileManager.default.moveItem(at: tempURL, to: zipURL)
        }

        if let error {
            throw error
        }

        return zipURL
    }

    // MARK: - Helpers

    private func bundleTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }

    private func macOSBuildNumber() -> String {
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        var build = [CChar](repeating: 0, count: size)
        sysctlbyname("kern.osversion", &build, &size, nil, 0)
        return String(cString: build)
    }

    private func cpuArchitecture() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        return withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "unknown"
            }
        }
    }

    private func thermalStateString(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    private func currentMemoryUsageMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return -1 }
        return Double(info.resident_size) / 1_048_576
    }

    // Placeholder methods — actual implementation depends on audio engine state
    private func currentAudioInputDeviceName() -> String { "default" }
    private func currentSampleRate() -> Double { 16000.0 }
    private func currentBufferSize() -> Int { 4096 }
    private func currentChannelCount() -> Int { 1 }
    private func modelsDirectorySizeMB() -> Double { 0.0 }
    private func getInstalledModelSummaries() async -> [[String: Any]] { [] }
}
```

### 7.3 Privacy Review Before Export

Before sharing the diagnostic bundle, VaulType presents a privacy review screen that lets the user inspect every file:

```swift
// File: Sources/VaulType/Views/Diagnostics/DiagnosticReviewView.swift

import SwiftUI

/// Presents the diagnostic bundle contents for user review before sharing.
///
/// The user can inspect each file, remove individual files from the bundle,
/// and only proceeds to sharing after explicit confirmation.
struct DiagnosticReviewView: View {
    let bundleURL: URL
    @State private var files: [DiagnosticFile] = []
    @State private var isLoading = true
    @State private var selectedFile: DiagnosticFile?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "doc.zipper")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Review Diagnostic Bundle")
                    .font(.headline)
                Text("Review the contents below before sharing. No transcription text, audio, or personal data is included.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()

            Divider()

            // File list
            if isLoading {
                ProgressView("Preparing bundle...")
                    .padding()
            } else {
                List(files, selection: $selectedFile) { file in
                    HStack {
                        Image(systemName: file.icon)
                        VStack(alignment: .leading) {
                            Text(file.name)
                                .font(.body)
                            Text(file.sizeDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Divider()

            // Actions
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                ShareLink(item: bundleURL) {
                    Label("Share Bundle", systemImage: "square.and.arrow.up")
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
        .task { await loadFiles() }
    }

    private func loadFiles() async {
        // Enumerate ZIP contents for display
        isLoading = false
    }
}

struct DiagnosticFile: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let size: Int64
    let icon: String

    var sizeDescription: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
```

### 7.4 Share Sheet Integration

```swift
// Triggering the diagnostic export from the Settings view
struct DiagnosticsSection: View {
    @State private var isExporting = false
    @State private var bundleURL: URL?
    @State private var showReview = false
    @State private var exportError: String?

    let metricsService: MetricsCollectionService

    var body: some View {
        Section("Diagnostics") {
            Button {
                isExporting = true
                Task {
                    do {
                        let exporter = DiagnosticExporter(metricsService: metricsService)
                        bundleURL = try await exporter.generateBundle()
                        showReview = true
                    } catch {
                        exportError = error.localizedDescription
                    }
                    isExporting = false
                }
            } label: {
                if isExporting {
                    ProgressView()
                        .controlSize(.small)
                    Text("Generating...")
                } else {
                    Label("Export Diagnostic Bundle", systemImage: "ladybug")
                }
            }
            .disabled(isExporting)

            if let error = exportError {
                Text("Export failed: \(error)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .sheet(isPresented: $showReview) {
            if let url = bundleURL {
                DiagnosticReviewView(bundleURL: url)
            }
        }
    }
}
```

> ✅ **Best Practice**: Always present the privacy review screen before allowing the user to share. This builds trust and ensures the user knows exactly what they are sharing.

---

## 8. Memory and CPU Monitoring

### 8.1 ProcessInfo-Based Monitoring

VaulType monitors system resources to adapt its behavior under pressure — for example, unloading the LLM model when memory is critically low or reducing audio buffer sizes under thermal throttling.

```swift
// File: Sources/VaulType/Monitoring/SystemMonitor.swift

import Foundation
import OSLog
import Combine

// MARK: - System Monitor

/// Monitors memory pressure, thermal state, and resource usage.
///
/// Publishes state changes via Combine for reactive UI and pipeline updates.
/// All monitoring is local — no data is ever transmitted.
@Observable
final class SystemMonitor {
    private let logger = Log.system
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var thermalStateObserver: NSObjectProtocol?
    private var pollTimer: Timer?

    // MARK: - Published State

    /// Current memory usage of the VaulType process in MB.
    private(set) var currentMemoryUsageMB: Double = 0

    /// Current thermal state of the system.
    private(set) var thermalState: ProcessInfo.ThermalState = .nominal

    /// Current memory pressure level.
    private(set) var memoryPressureLevel: MemoryPressureLevel = .normal

    /// Whether the system is in low power mode.
    private(set) var isLowPowerMode: Bool = false

    /// Peak memory usage observed during this session.
    private(set) var peakMemoryUsageMB: Double = 0

    /// CPU usage percentage (approximate, sampled).
    private(set) var cpuUsagePercent: Double = 0

    // MARK: - Callbacks

    /// Called when memory pressure reaches a critical level.
    /// The pipeline should respond by unloading non-essential models.
    var onCriticalMemoryPressure: (() -> Void)?

    /// Called when thermal state becomes serious or critical.
    /// The pipeline should reduce processing intensity.
    var onThermalThrottle: (() -> Void)?

    // MARK: - Lifecycle

    func startMonitoring() {
        setupMemoryPressureMonitoring()
        setupThermalStateMonitoring()
        startPollingTimer()
        logger.notice("System monitoring started")
    }

    func stopMonitoring() {
        memoryPressureSource?.cancel()
        memoryPressureSource = nil

        if let observer = thermalStateObserver {
            NotificationCenter.default.removeObserver(observer)
            thermalStateObserver = nil
        }

        pollTimer?.invalidate()
        pollTimer = nil

        logger.notice("System monitoring stopped")
    }

    // MARK: - Memory Pressure

    private func setupMemoryPressureMonitoring() {
        memoryPressureSource = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )

        memoryPressureSource?.setEventHandler { [weak self] in
            guard let self else { return }

            let event = self.memoryPressureSource?.data ?? []

            if event.contains(.critical) {
                self.memoryPressureLevel = .critical
                self.logger.error("Memory pressure: CRITICAL — initiating model unload")
                self.onCriticalMemoryPressure?()
            } else if event.contains(.warning) {
                self.memoryPressureLevel = .warning
                self.logger.notice("Memory pressure: WARNING — consider reducing memory usage")
            }
        }

        memoryPressureSource?.setCancelHandler { [weak self] in
            self?.memoryPressureLevel = .normal
        }

        memoryPressureSource?.resume()
        logger.info("Memory pressure monitoring active")
    }

    // MARK: - Thermal State

    private func setupThermalStateMonitoring() {
        // Read initial state
        thermalState = ProcessInfo.processInfo.thermalState

        thermalStateObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }

            let newState = ProcessInfo.processInfo.thermalState
            let oldState = self.thermalState
            self.thermalState = newState

            self.logger.notice(
                "Thermal state changed: \(self.thermalStateString(oldState), privacy: .public) "
                + "-> \(self.thermalStateString(newState), privacy: .public)"
            )

            if newState == .serious || newState == .critical {
                self.logger.error("Thermal throttling active — reducing processing intensity")
                self.onThermalThrottle?()
            }
        }

        logger.info("Thermal state monitoring active — current: \(thermalStateString(thermalState), privacy: .public)")
    }

    // MARK: - Polling Timer

    /// Periodically samples memory and CPU usage for the metrics display.
    private func startPollingTimer() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.sampleResourceUsage()
        }

        // Take an initial sample immediately
        sampleResourceUsage()
    }

    private func sampleResourceUsage() {
        currentMemoryUsageMB = readProcessMemoryMB()
        peakMemoryUsageMB = max(peakMemoryUsageMB, currentMemoryUsageMB)
        cpuUsagePercent = readCPUUsage()
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    // MARK: - Mach Task Info

    /// Reads the current process memory usage using Mach `task_info`.
    private func readProcessMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            logger.error("Failed to read task_info: \(result, privacy: .public)")
            return -1
        }

        return Double(info.resident_size) / 1_048_576 // bytes -> MB
    }

    /// Reads approximate CPU usage for the current process.
    private func readCPUUsage() -> Double {
        var threadList: thread_act_array_t?
        var threadCount = mach_msg_type_number_t(0)

        guard task_threads(mach_task_self_, &threadList, &threadCount) == KERN_SUCCESS,
              let threads = threadList else {
            return 0
        }

        var totalUsage: Double = 0

        for i in 0..<Int(threadCount) {
            var threadInfo = thread_basic_info()
            var threadInfoCount = mach_msg_type_number_t(THREAD_BASIC_INFO_COUNT)

            let result = withUnsafeMutablePointer(to: &threadInfo) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(threadInfoCount)) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &threadInfoCount)
                }
            }

            if result == KERN_SUCCESS && threadInfo.flags & TH_FLAGS_IDLE == 0 {
                totalUsage += Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
            }
        }

        // Deallocate the thread list
        let size = vm_size_t(MemoryLayout<thread_t>.size * Int(threadCount))
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), size)

        return totalUsage
    }

    // MARK: - Helpers

    private func thermalStateString(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:  return "nominal"
        case .fair:     return "fair"
        case .serious:  return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}

// MARK: - Memory Pressure Level

enum MemoryPressureLevel: String, Sendable {
    case normal   = "normal"
    case warning  = "warning"
    case critical = "critical"
}
```

### 8.2 Memory Pressure Notifications

When the system is under memory pressure, VaulType responds by unloading the least-recently-used model. This is coordinated with the `TranscriptionCoordinator` described in [`../architecture/ARCHITECTURE.md`](../architecture/ARCHITECTURE.md):

```swift
// In TranscriptionCoordinator or AppDelegate setup:

func setupMemoryPressureHandling(monitor: SystemMonitor) {
    monitor.onCriticalMemoryPressure = { [weak self] in
        guard let self else { return }

        Log.system.error("Critical memory pressure — unloading LLM model to free memory")

        Task {
            // Unload the LLM model first (typically larger than Whisper)
            await self.llamaContext.unloadModel()

            // Record the event
            await self.metricsService.record(
                .memoryPeakUsage,
                value: monitor.peakMemoryUsageMB,
                metadata: ["event": "critical_pressure_unload"]
            )

            Log.system.notice(
                "LLM model unloaded — memory: \(monitor.currentMemoryUsageMB, privacy: .public) MB "
                + "(peak: \(monitor.peakMemoryUsageMB, privacy: .public) MB)"
            )
        }
    }
}
```

> ⚠️ **Warning**: Memory pressure responses must be fast. Do not perform synchronous I/O or model operations on the main thread. The `unloadModel()` call should release references and let ARC handle deallocation asynchronously.

### 8.3 Thermal State Monitoring

Thermal throttling on Apple Silicon can significantly impact inference performance. VaulType monitors thermal state and adjusts accordingly:

```swift
func setupThermalHandling(monitor: SystemMonitor) {
    monitor.onThermalThrottle = { [weak self] in
        guard let self else { return }

        let state = monitor.thermalState

        switch state {
        case .serious:
            Log.system.notice("Thermal: serious — increasing inference thread yield interval")
            // Reduce concurrent inference threads
            whisperContext.setThreadCount(max(1, ProcessInfo.processInfo.activeProcessorCount / 2))

        case .critical:
            Log.system.error("Thermal: critical — pausing non-essential processing")
            // Pause LLM post-processing, keep Whisper at minimum threads
            whisperContext.setThreadCount(1)
            llamaContext.pauseProcessing()

            Task {
                await metricsService.record(
                    .thermalThrottle,
                    value: 1,
                    metadata: ["state": "critical"]
                )
            }

        default:
            break
        }
    }
}
```

**Thermal State Behavior Matrix:**

| Thermal State | Whisper Threads | LLM Processing | Audio Capture | User Notification |
|---------------|----------------|----------------|---------------|-------------------|
| Nominal | All available | Full speed | Normal | None |
| Fair | All available | Full speed | Normal | None |
| Serious | 50% of cores | Active but throttled | Normal | Subtle indicator |
| Critical | 1 thread | Paused | Normal (reduced buffer) | Warning overlay |

### 8.4 Instruments Integration

VaulType is designed to work seamlessly with Apple's Instruments profiling tools. Here is how to set up effective profiling sessions:

**Recommended Instruments Templates:**

| Template | Purpose | VaulType Signpost Categories |
|----------|---------|-------------------------------|
| **Time Profiler** | CPU hotspot identification | N/A (call stacks) |
| **Allocations** | Memory leak detection, heap analysis | N/A (allocation events) |
| **Leaks** | Retain cycle detection | N/A (leak detection) |
| **System Trace** | Thread scheduling, context switches | All signpost categories |
| **os_signpost** | Custom interval visualization | `AudioPipeline`, `WhisperInference`, `LLMInference`, `TextInjection`, `ModelLoading` |
| **Metal System Trace** | GPU inference performance | N/A (Metal events) |
| **Thermal State** | Thermal throttling timeline | N/A (system events) |

**Creating a Custom VaulType Instrument:**

1. Open Instruments.app
2. Create a new custom instrument (File > New > Custom Instrument)
3. Add an "os_signpost" instrument
4. Set the subsystem filter to `com.vaultype.app`
5. Add separate lanes for each signpost category:
   - `AudioPipeline` — audio capture intervals
   - `WhisperInference` — transcription intervals
   - `LLMInference` — LLM processing intervals
   - `TextInjection` — injection timing
   - `ModelLoading` — model load events

```
Instruments Timeline View (Example):
┌─────────────────────────────────────────────────────────────────────┐
│ AudioPipeline     │████████│        │█████████│        │███████│   │
│ WhisperInference  │        │████│   │         │███│    │       │██ │
│ LLMInference      │        │    │██ │         │   │█│  │       │   │
│ TextInjection     │        │    │  ▌│         │   │ ▌│ │       │   │
│ ModelLoading      │▌       │    │   │         │   │  │ │       │   │
│                   ├────────┼────┼───┼─────────┼───┼──┼─┼───────┼───│
│ Time              0s      1s   2s  3s        4s  5s 6s 7s      8s  │
└─────────────────────────────────────────────────────────────────────┘
```

> 🍎 **Apple Silicon Note**: On Apple Silicon Macs, Metal System Trace is particularly useful for profiling whisper.cpp and llama.cpp GPU inference. Both engines use Metal for matrix operations, and you can see GPU utilization, shader compilation, and memory bandwidth in the trace.

**Profiling Tips:**

```bash
# Record a 30-second trace from the command line
xcrun xctrace record \
  --template 'Time Profiler' \
  --attach "VaulType" \
  --time-limit 30s \
  --output ~/Desktop/vaultype-profile.trace

# Record with signposts only (lightweight)
xcrun xctrace record \
  --template 'os_signpost' \
  --attach "VaulType" \
  --time-limit 60s \
  --output ~/Desktop/vaultype-signposts.trace
```

---

## 9. Logging Best Practices

### 9.1 Do's and Don'ts

> ✅ **Do:**
>
> - Use the `Log.*` singleton loggers exclusively — never create ad-hoc `Logger` instances
> - Mark all numeric/enum values as `%{public}` for debuggability
> - Mark all file paths as `%{private(mask: .hash)}` to protect usernames
> - Use signposts for any operation that takes > 10ms
> - Log pipeline stage transitions at `.notice` level
> - Log recoverable errors at `.error` level with the error description
> - Include enough context to understand the log without reading code
> - Use structured interpolation: `\(value, privacy: .public)` not string concatenation

> ❌ **Don't:**
>
> - Never log transcription text, audio data, or clipboard contents
> - Never log full file paths — always hash them
> - Never use `.fault()` for expected failures
> - Never use `print()` or `NSLog()` — they bypass the unified logging system
> - Never log at `.debug` in a tight loop (e.g., per-audio-frame) — even though debug is discarded, the interpolation may still execute
> - Never add Sentry breadcrumbs that contain user content
> - Never log Keychain values or secrets

### 9.2 Log Message Style Guide

Consistent log messages make filtering and reading logs much easier. Follow these conventions:

**Format:** `<Component/Action>: <details>`

```swift
// Good: Clear component, action, and context
Log.whisper.info("Whisper inference started — model: \(modelName, privacy: .public), language: \(lang, privacy: .public)")
Log.audio.error("Audio engine interrupted — reason: \(reason.rawValue, privacy: .public)")
Log.injection.notice("Injection strategy fallback — from: \(primary.rawValue, privacy: .public), to: \(fallback.rawValue, privacy: .public)")

// Bad: Vague, missing context
Log.whisper.info("Starting...")           // What is starting?
Log.audio.error("Error occurred")         // What error? Where?
Log.injection.notice("Changed strategy")  // Changed from what to what?
```

**Naming Patterns:**

| Event Type | Pattern | Example |
|------------|---------|---------|
| Start | `<noun> started` | `"Dictation session started"` |
| Complete | `<noun> completed` | `"Model download completed"` |
| Failure | `<noun> failed: <reason>` | `"Injection failed: accessibility denied"` |
| State change | `<noun> changed: <old> -> <new>` | `"Thermal state changed: nominal -> serious"` |
| Threshold | `<noun> exceeded <limit>` | `"Memory usage exceeded 2048 MB"` |
| Fallback | `<noun> fallback: <from> -> <to>` | `"Injection fallback: CGEvent -> clipboard"` |

---

## Related Documentation

| Document | Relevance |
|----------|-----------|
| [`../architecture/ARCHITECTURE.md`](../architecture/ARCHITECTURE.md) | System architecture, pipeline design, threading model, and memory management strategy |
| [`../security/SECURITY.md`](../security/SECURITY.md) | Privacy policy, data handling rules, network security, and threat model |
| [`../architecture/DATABASE_SCHEMA.md`](../architecture/DATABASE_SCHEMA.md) | SwiftData model definitions including `PerformanceMetric` integration |
| [`../architecture/TECH_STACK.md`](../architecture/TECH_STACK.md) | Technology choices, version requirements, and performance considerations |
| [`MAINTENANCE.md`](MAINTENANCE.md) | Operational maintenance procedures, model updates, and release processes |
