Last Updated: 2026-02-20

# Product Roadmap

> **HushType** — Privacy-first, macOS-native speech-to-text with local LLM post-processing.
> This roadmap defines the phased development plan from MVP through stable release and beyond.

## Current Status (February 2026)

| Phase | Version | Status | Tasks |
|-------|---------|--------|-------|
| Phase 0 | Foundation | **Complete** | All tasks done |
| Phase 1 | v0.1.0 (MVP) | **Complete** | 35/35 tasks done |
| Phase 2 | v0.2.0 (LLM) | **Complete** | 33/33 tasks done |
| Phase 3 | v0.3.0 (Smart) | **Complete** | 29/29 tasks done |
| Phase 4 | v0.4.0 (Voice Commands) | **Complete** | 23/23 tasks done |
| Phase 5 | v0.5.0 (Power User & Polish) | **Complete** | 25/25 tasks done |
| Phase 6 | v1.0.0 (Stable Release) | **In Progress** | Several tasks remaining |

### Phase 6 Status (Stable Release)

Completed:
- Developer ID code signing configured
- Notarization integrated (`scripts/notarize.sh`)
- DMG packaging created (`scripts/create-dmg.sh`)
- Sparkle 2.x auto-updates integrated
- GitHub Actions: build workflow (`build.yml`), test workflow (`test.yml`), lint workflow (`lint.yml`)

Remaining:
- GitHub Actions release workflow (sign + notarize + DMG + GitHub Release in CI)
- Homebrew cask submission
- Full regression testing (Phase 1-5 end-to-end)
- Memory leak and stability testing
- Privacy verification (zero outbound network during core operations)
- Accessibility compliance audit (WCAG 2.1 AA)
- Documentation update pass

---

## Table of Contents

- [Roadmap Overview](#roadmap-overview)
- [Phase 1 -- MVP (v0.1.0)](#phase-1--mvp-v010)
  - [1.1 Menu Bar App Shell](#11-menu-bar-app-shell)
  - [1.2 Global Hotkey System](#12-global-hotkey-system)
  - [1.3 Audio Capture Pipeline](#13-audio-capture-pipeline)
  - [1.4 Local Speech Recognition (whisper.cpp)](#14-local-speech-recognition-whispercpp)
  - [1.5 Text Injection Engine](#15-text-injection-engine)
  - [1.6 Settings and Preferences](#16-settings-and-preferences)
  - [1.7 MVP Success Criteria](#17-mvp-success-criteria)
- [Phase 2 -- LLM Post-Processing (v0.2.0)](#phase-2--llm-post-processing-v020)
  - [2.1 Local llama.cpp Integration](#21-local-llamacpp-integration)
  - [2.2 Optional Ollama Backend](#22-optional-ollama-backend)
  - [2.3 Model Downloader for GGUF](#23-model-downloader-for-gguf)
  - [2.4 Processing Modes](#24-processing-modes)
  - [2.5 Per-Hotkey Mode Assignment](#25-per-hotkey-mode-assignment)
  - [2.6 Voice Prefix Triggers](#26-voice-prefix-triggers)
  - [2.7 Prompt Template System](#27-prompt-template-system)
- [Phase 3 -- Smart Features (v0.3.0)](#phase-3--smart-features-v030)
  - [3.1 App-Aware Context](#31-app-aware-context)
  - [3.2 Dictation History](#32-dictation-history)
  - [3.3 Floating Overlay Window](#33-floating-overlay-window)
  - [3.4 Custom Vocabulary](#34-custom-vocabulary)
  - [3.5 Multi-Language Support](#35-multi-language-support)
- [Phase 4 -- Voice Commands (v0.4.0)](#phase-4--voice-commands-v040)
  - [4.1 System Command Engine](#41-system-command-engine)
  - [4.2 App Management Commands](#42-app-management-commands)
  - [4.3 Window Management](#43-window-management)
  - [4.4 System Controls](#44-system-controls)
  - [4.5 Workflow Automation](#45-workflow-automation)
- [Phase 5 -- Power User and Polish (v0.5.0)](#phase-5--power-user-and-polish-v050)
  - [5.1 Keyboard Shortcut Chaining via Voice](#51-keyboard-shortcut-chaining-via-voice)
  - [5.2 Audio Feedback](#52-audio-feedback)
  - [5.3 Accessibility Features](#53-accessibility-features)
  - [5.4 Performance Optimization](#54-performance-optimization)
  - [5.5 Plugin and Extension System](#55-plugin-and-extension-system)
- [v1.0 -- Stable Release](#v10--stable-release)
- [Future Considerations (v1.0+)](#future-considerations-v10)
  - [Speaker Diarization](#speaker-diarization)
  - [Real-Time Translation](#real-time-translation)
  - [Voice-Controlled Text Editing](#voice-controlled-text-editing)
  - [Meeting Transcription Mode](#meeting-transcription-mode)
  - [Third-Party Integrations](#third-party-integrations)
  - [iOS Companion App](#ios-companion-app)
  - [Enterprise Features](#enterprise-features)
  - [Open-Core Model](#open-core-model)
- [MVP Definition and Success Criteria](#mvp-definition-and-success-criteria)
  - [Acceptance Criteria](#acceptance-criteria)
  - [Non-Functional Requirements](#non-functional-requirements)
  - [Out of Scope for MVP](#out-of-scope-for-mvp)
- [Community-Requested Features Backlog](#community-requested-features-backlog)
- [Release Timeline Summary](#release-timeline-summary)
- [Related Documentation](#related-documentation)

---

## Roadmap Overview

HushType follows a phased release strategy. Each phase builds incrementally on the previous one, delivering usable value at every milestone. All phases share one non-negotiable constraint: **every feature operates 100% locally on the user's device**.

```
 v0.1.0 (MVP)          v0.2.0 (LLM)         v0.3.0 (Smart)
 ┌──────────────┐       ┌──────────────┐       ┌──────────────┐
 │ Menu bar app │       │ llama.cpp    │       │ App-aware    │
 │ Global hotkey│       │ 6 processing │       │ Dictation    │
 │ Audio capture│──────▶│ modes        │──────▶│ history      │
 │ whisper.cpp  │       │ Prompt       │       │ Overlay      │
 │ Text inject  │       │ templates    │       │ Vocabulary   │
 │ Settings     │       │ Model DL     │       │ Multi-lang   │
 └──────────────┘       └──────────────┘       └──────────────┘
                                                      │
 v1.0 (Stable)         v0.5.0 (Polish)        v0.4.0 (Voice)
 ┌──────────────┐       ┌──────────────┐       ┌──────────────┐
 │ Feature-     │       │ Shortcuts    │       │ System cmds  │
 │ complete     │       │ Audio feed-  │       │ App mgmt     │
 │ All phases   │◀──────│ back         │◀──────│ Window mgmt  │
 │ delivered    │       │ Accessibility│       │ Sys controls │
 │ Stable API   │       │ Performance  │       │ Workflow     │
 │              │       │ Plugin sys   │       │ automation   │
 └──────────────┘       └──────────────┘       └──────────────┘
```

| Phase | Version | Theme | Status | Key Deliverables |
|-------|---------|-------|--------|-----------------|
| **Phase 1** | v0.1.0 | MVP -- Core Dictation | Complete | Menu bar app, hotkey, whisper.cpp, text injection |
| **Phase 2** | v0.2.0 | LLM Post-Processing | Complete | llama.cpp, 6 modes, prompt templates, model downloader |
| **Phase 3** | v0.3.0 | Smart Features | Complete | App-aware context, history, overlay, vocabulary, multi-lang |
| **Phase 4** | v0.4.0 | Voice Commands | Complete | System commands, app/window management, automation |
| **Phase 5** | v0.5.0 | Power User & Polish | Complete | Voice-chained shortcuts, feedback, performance, plugins |
| **Phase 6** | v1.0.0 | Stable Release | In Progress | Code signing, notarization, DMG, CI/CD, testing, docs |

> **Note**: Versions beyond v1.0 are exploratory and subject to community input and technical feasibility assessment.

---

## Phase 1 -- MVP (v0.1.0)

**Goal**: Deliver a functional, privacy-first dictation app that allows a user to speak into any macOS application with under 2 seconds of end-to-end latency. No network required. No LLM required.

### 1.1 Menu Bar App Shell

A persistent, lightweight menu bar application built with SwiftUI `MenuBarExtra`.

| Deliverable | Description | Priority |
|---|---|---|
| Menu bar icon | Displays mic state (idle, recording, processing) via SF Symbols | P0 |
| Menu bar popover | Shows current status, last transcription preview, quick settings | P0 |
| Settings window | `Settings` scene with tabbed preference panes | P0 |
| Launch at login | `SMAppService.mainApp.register()` integration | P1 |
| Dock icon toggle | Option to hide/show dock icon (`LSUIElement`) | P2 |

```swift
// Target architecture
@main
struct HushTypeApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("HushType", systemImage: appState.menuBarIcon) {
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

### 1.2 Global Hotkey System

System-wide keyboard shortcut that works regardless of which application is focused.

| Deliverable | Description | Priority |
|---|---|---|
| Default hotkey | `Cmd+Shift+Space` for push-to-talk (hold) and toggle (press) | P0 |
| Hotkey customization | User-configurable shortcut via Settings | P0 |
| Conflict detection | Warn when the chosen shortcut conflicts with another app | P1 |
| Multiple hotkeys | Register up to 4 hotkeys (for different modes in Phase 2) | P2 |

> **Note**: The global hotkey system uses `CGEvent` tap or the `KeyboardShortcuts` library. The chosen approach must work without the App Sandbox. See [Tech Stack](../architecture/TECH_STACK.md) for rationale.

### 1.3 Audio Capture Pipeline

Real-time audio capture from the user's microphone, converted to 16kHz mono Float32 PCM for whisper.cpp.

| Deliverable | Description | Priority |
|---|---|---|
| AVAudioEngine tap | Capture audio from the default input device | P0 |
| Format conversion | Resample any input to 16kHz mono Float32 | P0 |
| Device selection | Allow the user to choose a specific microphone | P1 |
| Voice Activity Detection (VAD) | Basic energy-based VAD to trim silence | P1 |
| Circular buffer | Rolling 30-second buffer for streaming support | P1 |

```
Microphone  -->  AVAudioEngine  -->  Format Converter  -->  Circular Buffer
  (any Hz)         (tap)           (16kHz mono F32)        (30s rolling)
                                                                 |
                                                                 v
                                                          whisper.cpp
```

### 1.4 Local Speech Recognition (whisper.cpp)

On-device speech-to-text using whisper.cpp with Metal GPU acceleration.

| Deliverable | Description | Priority |
|---|---|---|
| whisper.cpp integration | Compile and link whisper.cpp via CMake + bridging header | P0 |
| Metal GPU acceleration | Enable Metal backend for Apple Silicon and AMD GPUs | P0 |
| Multiple model sizes | Support tiny, base, small, medium, large-v3 | P0 |
| Model selection UI | Settings pane to choose the active whisper model | P0 |
| Streaming transcription | Process audio in chunks for near-real-time output | P1 |
| Language selection | Explicit language or auto-detect | P1 |

**Supported model matrix:**

| Model | Parameters | Disk Size | RAM (approx) | Speed (M1, 10s audio) | Quality |
|---|---|---|---|---|---|
| `whisper-tiny` | 39M | ~75 MB | ~200 MB | ~0.3s | Basic |
| `whisper-base` | 74M | ~142 MB | ~350 MB | ~0.5s | Good |
| `whisper-small` | 244M | ~466 MB | ~750 MB | ~1.0s | Very Good |
| `whisper-medium` | 769M | ~1.5 GB | ~2.0 GB | ~2.5s | Excellent |
| `whisper-large-v3` | 1550M | ~3.1 GB | ~4.0 GB | ~5.0s | Best |

> **Note**: The default model for MVP is `whisper-base` -- a good balance of speed and accuracy that loads quickly and runs well even on 8 GB Macs.

### 1.5 Text Injection Engine

Deliver transcribed text to the cursor position in any macOS application.

| Deliverable | Description | Priority |
|---|---|---|
| CGEvent injection | Simulate keystrokes for short text (<50 chars) | P0 |
| Clipboard paste fallback | `Cmd+V` paste with clipboard preserve/restore for long text | P0 |
| Auto-detect strategy | Choose CGEvent vs. clipboard based on text length | P0 |
| Unicode support | Full Unicode including CJK, emoji, diacritics | P1 |
| Accessibility permission check | Guide user through granting Accessibility permission | P0 |

> **Important**: Text injection requires the Accessibility permission. HushType must detect when permission is missing and present clear instructions. See [Security](../security/SECURITY.md) for the permission model.

### 1.6 Settings and Preferences

Persistent user preferences stored via SwiftData and UserDefaults.

| Deliverable | Description | Priority |
|---|---|---|
| General tab | Hotkey, launch at login, dock icon | P0 |
| Audio tab | Input device selection, VAD sensitivity | P0 |
| Models tab | Whisper model selection, download management | P0 |
| About tab | Version, open source attribution, links | P1 |
| Data storage | SwiftData for structured data, UserDefaults for lightweight state | P0 |

> **Note**: See [Database Schema](../architecture/DATABASE_SCHEMA.md) for the complete data model specification.

### 1.7 MVP Success Criteria

The MVP is complete when a user can:

1. Install HushType by dragging to `/Applications`
2. Grant Microphone and Accessibility permissions on first launch
3. Press `Cmd+Shift+Space`, speak naturally, and release
4. See the transcribed text appear at the cursor in any app
5. Complete the full cycle (press, speak, release, text appears) in under 2 seconds for a short sentence

---

## Phase 2 -- LLM Post-Processing (v0.2.0)

**Goal**: Add local LLM-powered text transformation. Raw whisper output becomes polished, formatted text -- punctuated, structured, or completely rewritten according to user-defined modes and templates.

### 2.1 Local llama.cpp Integration

Direct in-process LLM inference via llama.cpp compiled into the app binary.

| Deliverable | Description | Priority |
|---|---|---|
| llama.cpp integration | Compile and link llama.cpp via CMake + bridging header | P0 |
| Metal GPU acceleration | Full Metal offloading for Apple Silicon | P0 |
| GGUF model loading | Load and manage GGUF-format models | P0 |
| Context management | Configurable context length (512-4096 tokens) | P1 |
| Memory management | Graceful handling when model exceeds available RAM | P0 |
| LLMProvider protocol | Abstract interface for swappable backends | P0 |

```swift
/// Protocol abstracting LLM backends for extensibility
protocol LLMProvider: Sendable {
    func loadModel(at path: URL, parameters: LLMLoadParameters) async throws
    func complete(prompt: String, parameters: LLMInferenceParameters) async throws -> String
    var isModelLoaded: Bool { get }
    var estimatedMemoryUsage: UInt64 { get }
    func unloadModel() async
}
```

### 2.2 Optional Ollama Backend

For users who already have Ollama installed and prefer using their existing models.

| Deliverable | Description | Priority |
|---|---|---|
| Ollama detection | Auto-detect running Ollama instance on `localhost:11434` | P1 |
| OllamaProvider | `LLMProvider` implementation using Ollama HTTP API | P1 |
| Model listing | Fetch available models from the Ollama API | P1 |
| Settings toggle | Allow switching between llama.cpp and Ollama in preferences | P1 |

> **Note**: Ollama is strictly optional. HushType must function fully without it. Network calls are made only to `localhost`. See [Security](../security/SECURITY.md) for network policy.

### 2.3 Model Downloader for GGUF

Built-in model management with download, verification, and storage.

| Deliverable | Description | Priority |
|---|---|---|
| Model registry | Pre-configured list of recommended GGUF models with metadata | P0 |
| Download manager | Background downloads with progress tracking via URLSession | P0 |
| SHA-256 verification | Verify integrity of downloaded model files | P0 |
| Storage management | Show disk usage per model, allow deletion | P0 |
| Custom model import | Import user-supplied GGUF files from Finder | P1 |

**Recommended LLM models for post-processing:**

| Model | Parameters | Quantization | Disk Size | RAM (approx) | Use Case |
|---|---|---|---|---|---|
| `Qwen2.5-0.5B` | 0.5B | Q4_K_M | ~350 MB | ~600 MB | Lightweight cleanup, 8 GB systems |
| `Qwen2.5-1.5B` | 1.5B | Q4_K_M | ~900 MB | ~1.2 GB | Balanced cleanup and formatting |
| `Qwen2.5-3B` | 3B | Q4_K_M | ~1.8 GB | ~2.5 GB | High-quality formatting, 16 GB systems |
| `Llama-3.2-1B` | 1B | Q4_K_M | ~700 MB | ~1.0 GB | Fast general-purpose processing |
| `Llama-3.2-3B` | 3B | Q4_K_M | ~1.9 GB | ~2.6 GB | High-quality general-purpose |
| `Phi-3-mini-4k` | 3.8B | Q4_K_M | ~2.2 GB | ~3.0 GB | Best instruction following |

### 2.4 Processing Modes

Six distinct processing modes that define how whisper.cpp output is transformed by the LLM.

| Mode | Enum Value | LLM Required | Description |
|---|---|---|---|
| **Raw** | `.raw` | No | Unprocessed whisper output -- exactly what was transcribed |
| **Clean** | `.clean` | Yes | Fix punctuation, capitalization, remove filler words ("um", "uh", "like") |
| **Structure** | `.structure` | Yes | Organize into paragraphs, bullet lists, or headings based on content |
| **Prompt** | `.prompt` | Yes | Apply a user-defined LLM prompt template (e.g., "rewrite as email") |
| **Code** | `.code` | Yes | Convert spoken programming instructions into valid source code |
| **Custom** | `.custom` | Yes | Fully user-defined pipeline with custom pre/post processors |

```
whisper.cpp output ──► Mode Router ──┬── Raw ──────────► direct output
                                     ├── Clean ────────► LLM (cleanup prompt)
                                     ├── Structure ────► LLM (structure prompt)
                                     ├── Prompt ───────► LLM (user template)
                                     ├── Code ─────────► LLM (code prompt)
                                     └── Custom ───────► LLM (custom pipeline)
```

### 2.5 Per-Hotkey Mode Assignment

Each registered hotkey can trigger a different processing mode.

| Deliverable | Description | Priority |
|---|---|---|
| Hotkey-mode binding | Associate each of 4 hotkeys with a specific mode | P0 |
| Mode indicator | Show the active mode in the menu bar popover | P0 |
| Quick switch | Cycle through modes via a secondary shortcut | P1 |
| Default mode | Configurable default when no hotkey-specific mode is set | P0 |

**Example configuration:**

| Hotkey | Mode | Use Case |
|---|---|---|
| `Cmd+Shift+Space` | Clean | General dictation -- punctuated, capitalized |
| `Cmd+Shift+C` | Code | Dictating source code in an IDE |
| `Cmd+Shift+E` | Prompt (Email) | Drafting emails from spoken thoughts |
| `Cmd+Shift+R` | Raw | Verbatim capture for meeting notes |

### 2.6 Voice Prefix Triggers

Change the processing mode by speaking a trigger phrase at the start of dictation.

| Deliverable | Description | Priority |
|---|---|---|
| Prefix detection | Detect mode-switching phrases in the first 2 seconds of audio | P1 |
| Built-in prefixes | "Code mode", "Email mode", "Clean this up", "Raw mode" | P1 |
| Custom prefixes | User-defined trigger phrases mapped to modes | P2 |
| Prefix stripping | Remove the trigger phrase from the final output | P1 |

**Example workflow:**

```
User says:  "Code mode... function hello world that returns a string"
Detected:    prefix = "Code mode" --> switch to .code
Processed:  "Code mode" stripped, remaining text processed as code
Output:     func helloWorld() -> String {
```

### 2.7 Prompt Template System

A templating engine for LLM prompts with variable substitution.

| Deliverable | Description | Priority |
|---|---|---|
| Template data model | `PromptTemplate` SwiftData model with system/user prompts | P0 |
| Variable substitution | `{{transcription}}`, `{{language}}`, `{{tone}}`, custom vars | P0 |
| Built-in templates | 4 shipped templates: Clean, Structured Notes, Code, Email | P0 |
| Template editor | Settings UI for creating and editing templates | P0 |
| Template import/export | Share templates as JSON files | P2 |

**Built-in template variables:**

| Variable | Type | Description |
|---|---|---|
| `{{transcription}}` | Built-in | Raw whisper.cpp output text (always available) |
| `{{language}}` | Built-in | Detected or selected language code (e.g., "en", "tr") |
| `{{app_name}}` | Built-in | Name of the currently focused application |
| `{{app_bundle_id}}` | Built-in | Bundle identifier of the focused application |
| `{{timestamp}}` | Built-in | Current date/time in ISO 8601 format |
| `{{tone}}` | User-defined | Custom variable (e.g., "professional", "casual") |
| `{{recipient}}` | User-defined | Custom variable for email templates |

> **Note**: See [Database Schema](../architecture/DATABASE_SCHEMA.md) for the `PromptTemplate` model definition and built-in template seed data.

---

## Phase 3 -- Smart Features (v0.3.0)

**Goal**: Make HushType context-aware and history-capable. The app adapts its behavior based on the active application, remembers past dictations, and provides a visual overlay for editing before injection.

### 3.1 App-Aware Context

Automatically select the optimal processing mode and vocabulary based on which application is focused.

| Deliverable | Description | Priority |
|---|---|---|
| Frontmost app detection | Monitor `NSWorkspace` for active app changes | P0 |
| App profiles | Per-app configuration (mode, language, injection method, vocabulary) | P0 |
| Auto-profile creation | Create a default profile the first time the user dictates into an app | P1 |
| Smart defaults | Sensible defaults (e.g., Code mode for Xcode, Clean for Mail) | P1 |
| Profile editor | Settings UI for managing per-app profiles | P0 |

**Example auto-detection rules:**

| Application | Bundle ID | Default Mode | Default Language | Injection Method |
|---|---|---|---|---|
| Xcode | `com.apple.dt.Xcode` | Code | en | CGEvent |
| Mail | `com.apple.mail` | Clean | Auto-detect | CGEvent |
| Slack | `com.tinyspeck.slackmacgap` | Clean | Auto-detect | Clipboard |
| Terminal | `com.apple.Terminal` | Raw | en | CGEvent |
| VS Code | `com.microsoft.VSCode` | Code | en | Clipboard |
| Notes | `com.apple.Notes` | Structure | Auto-detect | CGEvent |

### 3.2 Dictation History

Searchable, editable log of all past transcriptions.

| Deliverable | Description | Priority |
|---|---|---|
| History storage | `DictationEntry` records in SwiftData | P0 |
| History window | Dedicated window with search, filter, and sort | P0 |
| Full-text search | Search across raw and processed text | P0 |
| Filter by app | Filter history by target application | P1 |
| Filter by date | Date range picker for history filtering | P1 |
| Edit and re-inject | Edit a past transcription and inject it at the current cursor | P1 |
| Favorites | Mark entries as favorites (excluded from auto-deletion) | P1 |
| Retention policies | Configurable auto-deletion by age and count | P0 |
| Export | Export history as JSON or plain text | P2 |

> **Note**: Dictation history stores text only -- never audio. Audio is processed in memory and discarded immediately. See [Security](../security/SECURITY.md) for audio data lifecycle details.

### 3.3 Floating Overlay Window

A small, always-on-top overlay that shows real-time transcription and allows editing before injection.

| Deliverable | Description | Priority |
|---|---|---|
| Overlay window | Floating `NSPanel` with real-time transcription text | P1 |
| Edit before inject | User can modify transcribed text before it is injected | P1 |
| Dismiss and inject | Press Enter or click "Inject" to send text to cursor | P1 |
| Cancel | Press Escape to discard without injecting | P1 |
| Position control | Configurable overlay position (near cursor, corner, center) | P2 |
| Transparency | Adjustable opacity so the overlay does not obscure work | P2 |

```
┌─────────────────────────────────────────────┐
│  HushType                          [x]  [-] │
├─────────────────────────────────────────────┤
│                                             │
│  The quick brown fox jumps over the lazy    │
│  dog.                                       │
│  _                                          │
│                                             │
├─────────────────────────────────────────────┤
│  Mode: Clean  |  Lang: en  |  0.8s         │
│                        [Cancel]  [Inject]   │
└─────────────────────────────────────────────┘
```

### 3.4 Custom Vocabulary

User dictionary for correcting common whisper misrecognitions and domain-specific terms.

| Deliverable | Description | Priority |
|---|---|---|
| Global vocabulary | Replacement rules that apply in all applications | P0 |
| Per-app vocabulary | Replacements scoped to specific app profiles | P1 |
| Case sensitivity | Option for case-sensitive or case-insensitive matching | P1 |
| Vocabulary editor | Settings UI for managing spoken form / replacement pairs | P0 |
| Auto-correction | Apply vocabulary replacements before LLM processing | P0 |
| Import/export | Share vocabulary files as JSON | P2 |

**Example entries:**

| Spoken Form | Replacement | Scope | Notes |
|---|---|---|---|
| "ecks code" | "Xcode" | Global | Common whisper misrecognition |
| "jay son" | "JSON" | Global | Acronym normalization |
| "swift you eye" | "SwiftUI" | Global | Framework name |
| "build and run" | "Cmd+R" | Xcode only | App-specific shortcut |
| "hush type" | "HushType" | Global | Product name |

### 3.5 Multi-Language Support

Support for multiple transcription languages with quick switching and auto-detection.

| Deliverable | Description | Priority |
|---|---|---|
| Language selection | Explicit language setting in preferences and per-app profiles | P0 |
| Auto-detect | whisper.cpp automatic language detection (first 30 seconds) | P0 |
| Quick switch | Keyboard shortcut or voice command to change language mid-session | P1 |
| Language indicator | Show detected/selected language in the menu bar and overlay | P1 |
| Per-app language | Override global language for specific applications | P1 |
| LLM language awareness | Pass detected language to LLM prompt templates | P1 |

> **Note**: whisper.cpp supports 99 languages. Initial focus is on the top 10 languages by user demand. Language auto-detection adds ~0.5s of latency as whisper.cpp analyzes the first 30 seconds of audio.

---

## Phase 4 -- Voice Commands (v0.4.0)

**Goal**: Extend beyond dictation into voice-driven system control. Users can launch apps, manage windows, adjust system settings, and chain commands -- all by speaking.

### 4.1 System Command Engine

An interpreter that distinguishes between dictation and commands.

| Deliverable | Description | Priority |
|---|---|---|
| Command detection | Identify voice input as a command vs. dictation text | P0 |
| Command prefix | Configurable wake phrase (e.g., "Hey Type" or "Computer") | P0 |
| Command parser | Parse natural language into structured command actions | P0 |
| Confirmation mode | Optional confirmation before executing destructive commands | P1 |
| Command feedback | Audio or visual confirmation of executed commands | P0 |
| Error handling | Graceful failure with helpful error messages | P0 |

```
Voice Input ──► Command Detector ──┬── Dictation ──► Normal pipeline
                                   │
                                   └── Command ──► Command Parser ──► Executor
                                                        │
                                                   ┌────┴─────┐
                                                   │ Validated │
                                                   │ Command   │
                                                   │ Object    │
                                                   └────┬──────┘
                                                        │
                                              ┌─────────┼──────────┐
                                              ▼         ▼          ▼
                                          App Mgmt  Window Mgmt  System
```

### 4.2 App Management Commands

Voice commands for launching, switching, and closing applications.

| Command Pattern | Action | Example |
|---|---|---|
| "Open {app}" | Launch application by name | "Open Safari" |
| "Switch to {app}" | Bring application to foreground | "Switch to Xcode" |
| "Close {app}" | Close the frontmost window of an application | "Close Finder" |
| "Quit {app}" | Terminate an application | "Quit Preview" |
| "Hide {app}" | Hide an application | "Hide Messages" |
| "Show all windows" | Invoke Mission Control | "Show all windows" |

> **Note**: App management commands use `NSWorkspace` and `NSRunningApplication` APIs. Destructive commands (quit, close) require confirmation mode to be disabled or the user to confirm.

### 4.3 Window Management

Voice commands for positioning and resizing windows.

| Command Pattern | Action | Example |
|---|---|---|
| "Move window left" | Tile current window to the left half | "Move window left" |
| "Move window right" | Tile current window to the right half | "Move window right" |
| "Maximize window" | Fill the screen | "Maximize window" |
| "Minimize window" | Minimize to Dock | "Minimize window" |
| "Full screen" | Enter macOS full-screen mode | "Full screen" |
| "Center window" | Center the window on screen | "Center window" |
| "Next screen" | Move window to the next display | "Next screen" |

### 4.4 System Controls

Voice commands for adjusting system settings.

| Command Pattern | Action | Example |
|---|---|---|
| "Volume up/down" | Adjust system volume by 10% steps | "Volume up" |
| "Volume {number}" | Set volume to a specific level | "Volume fifty percent" |
| "Mute / Unmute" | Toggle system mute | "Mute" |
| "Brightness up/down" | Adjust display brightness | "Brightness down" |
| "Do not disturb on/off" | Toggle Focus mode | "Do not disturb on" |
| "Dark mode / Light mode" | Switch appearance | "Dark mode" |
| "Lock screen" | Lock the Mac | "Lock screen" |
| "Screenshot" | Capture screen | "Screenshot" |

### 4.5 Workflow Automation

Chain multiple commands and integrate with macOS automation frameworks.

| Deliverable | Description | Priority |
|---|---|---|
| Command chaining | Execute multiple commands in sequence via voice | P1 |
| Apple Shortcuts | Trigger Shortcuts app workflows by name | P1 |
| AppleScript execution | Run AppleScript snippets via voice (with safeguards) | P2 |
| Custom command definitions | Users define named commands mapped to action sequences | P2 |
| Command history | Log of recently executed commands for repeat | P2 |

**Example command chain:**

```
"Open Safari, go to GitHub, and switch to dark mode"

  ──► [1] Open Safari
  ──► [2] Wait for Safari to activate
  ──► [3] Navigate to github.com (inject URL + Enter)
  ──► [4] Switch system to dark mode
```

> **Important**: AppleScript execution requires the Automation permission and presents significant security considerations. Users must explicitly grant per-app Automation permissions, and HushType must sanitize all input to prevent injection attacks. See [Security](../security/SECURITY.md) for details.

---

## Phase 5 -- Power User and Polish (v0.5.0)

**Goal**: Refine the experience for daily-driver use. Optimize performance, add audio feedback, ensure accessibility, and introduce a plugin system for community extensibility.

### 5.1 Keyboard Shortcut Chaining via Voice

Dictate keyboard shortcuts by name or description.

| Deliverable | Description | Priority |
|---|---|---|
| Shortcut dictation | Say "Command+Shift+N" or "New folder" and inject the keystroke | P1 |
| App-aware shortcuts | Know that "Build and run" means `Cmd+R` in Xcode | P1 |
| Shortcut aliases | User-defined aliases (e.g., "Save all" = `Cmd+Option+S`) | P2 |
| Combo execution | Inject modifier key combinations via CGEvent | P1 |

### 5.2 Audio Feedback

Audible cues for state transitions and command execution.

| Deliverable | Description | Priority |
|---|---|---|
| Recording start/stop sounds | Distinct tones for begin and end of recording | P0 |
| Success/error sounds | Audio confirmation for commands | P1 |
| Sound pack system | Multiple sound themes (subtle, mechanical, none) | P2 |
| Volume control | Independent volume for feedback sounds | P1 |
| System sound integration | Use `NSSound` or `AudioServicesPlaySystemSound` | P0 |

### 5.3 Accessibility Features

Ensure HushType is fully usable by people with disabilities.

| Deliverable | Description | Priority |
|---|---|---|
| VoiceOver support | Full VoiceOver compatibility for all UI elements | P0 |
| Accessibility labels | Meaningful labels on all interactive elements | P0 |
| State announcements | Announce recording/processing state changes to assistive tech | P0 |
| High contrast support | Respect macOS "Increase Contrast" setting | P1 |
| Reduced motion | Respect macOS "Reduce Motion" preference | P1 |
| Dynamic Type | Scale text with system font size preferences | P1 |
| Keyboard navigation | Full keyboard navigation for all UI | P0 |

> **Note**: Accessibility compliance goals are documented in detail in [Legal Compliance](../security/LEGAL_COMPLIANCE.md).

### 5.4 Performance Optimization

Ensure HushType is a responsible background citizen -- low resource usage, battery awareness, and thermal management.

| Deliverable | Description | Priority |
|---|---|---|
| Model preloading | Keep active models in memory between transcriptions | P0 |
| Lazy model loading | Load models on first use, not at app launch | P0 |
| Battery-aware mode | Reduce model quality/threads when on battery power | P1 |
| Thermal management | Throttle inference when the system is thermally constrained | P1 |
| Memory pressure response | Unload LLM model under memory pressure, keep whisper loaded | P1 |
| Idle memory reduction | Release unused memory after configurable idle period | P2 |
| Startup optimization | Target <0.5s launch to menu bar readiness | P0 |
| Background CPU usage | Near-zero CPU when idle (no polling, event-driven only) | P0 |

**Battery-aware strategy:**

| Power State | Whisper Model | LLM Model | GPU Layers | Threads |
|---|---|---|---|---|
| **Plugged in** | User's choice | User's choice | Maximum | Auto (all cores) |
| **Battery > 50%** | User's choice | User's choice | Maximum | Auto (P-cores only) |
| **Battery 20-50%** | Downgrade 1 tier | Downgrade 1 tier | Reduced by 50% | 4 threads max |
| **Battery < 20%** | Tiny or Base only | Disabled | Minimum | 2 threads max |
| **Low Power Mode** | Tiny only | Disabled | Minimum | 2 threads max |

### 5.5 Plugin and Extension System

A mechanism for the community to extend HushType with custom processing, commands, and integrations.

| Deliverable | Description | Priority |
|---|---|---|
| Plugin API | Swift protocol-based plugin interface | P2 |
| Plugin types | Processing plugins, command plugins, integration plugins | P2 |
| Plugin discovery | Load plugins from `~/Library/Application Support/HushType/Plugins/` | P2 |
| Sandboxed execution | Plugins run in restricted context with limited system access | P2 |
| Plugin manager UI | Install, enable/disable, and remove plugins from Settings | P2 |
| Documentation | Plugin development guide with example plugins | P2 |

```swift
/// Plugin protocol for community extensions
protocol HushTypePlugin: Sendable {
    /// Unique identifier for this plugin
    var identifier: String { get }

    /// Human-readable name
    var displayName: String { get }

    /// Plugin version
    var version: String { get }

    /// Called when the plugin is loaded
    func activate() async throws

    /// Called when the plugin is unloaded
    func deactivate() async
}

/// Processing plugin -- transforms text in the pipeline
protocol ProcessingPlugin: HushTypePlugin {
    func process(text: String, context: ProcessingContext) async throws -> String
}

/// Command plugin -- adds new voice commands
protocol CommandPlugin: HushTypePlugin {
    var supportedCommands: [CommandDefinition] { get }
    func execute(command: ParsedCommand) async throws -> CommandResult
}
```

> **Important**: The plugin system is a Phase 5 deliverable and will be designed after the core product stabilizes. The API surface will be kept deliberately narrow to ensure stability and security. Plugins must not access the microphone, network, or filesystem outside their designated sandbox.

---

## v1.0 -- Stable Release

**Goal**: All five phases delivered, tested, documented, and polished to production quality. v1.0 represents HushType's public commitment to API and feature stability.

### v1.0 Checklist

| Category | Requirement | Status |
|---|---|---|
| **Features** | All Phase 1-5 features shipped and functional | Done (Phase 5 complete) |
| **Stability** | Zero known crash bugs; <0.1% crash rate in beta testing | Pending (regression testing) |
| **Performance** | End-to-end latency <2s (whisper-base); <4s with LLM post-processing | Done (PowerManagementService, VAD, pipeline optimized) |
| **Privacy** | Zero network calls for core functionality | Pending (formal verification) |
| **Security** | Code signing (Developer ID), notarization | Done |
| **Accessibility** | WCAG 2.1 AA compliance; VoiceOver supported | Pending (audit) |
| **Documentation** | User guide, developer docs, plugin guide | In Progress |
| **Distribution** | Notarized DMG, Sparkle auto-updates | Done; Homebrew cask pending |
| **CI/CD** | Build, test, lint workflows | Done; release workflow pending |
| **Testing** | Unit tests for all services and commands | Done (Phase 4-5 tests complete) |

### v1.0 Versioning Policy

After v1.0, HushType follows Semantic Versioning:

| Version Component | Meaning | Example |
|---|---|---|
| **Major** (X.0.0) | Breaking changes to plugin API or data format | 2.0.0 |
| **Minor** (1.X.0) | New features, backward-compatible | 1.1.0, 1.2.0 |
| **Patch** (1.0.X) | Bug fixes, security patches | 1.0.1, 1.0.2 |

---

## Future Considerations (v1.0+)

The following features are under consideration for post-1.0 releases. They are not committed to any timeline and will be prioritized based on community feedback, technical feasibility, and alignment with HushType's privacy-first principles.

### Speaker Diarization

Distinguish between multiple speakers in the audio stream.

| Aspect | Details |
|---|---|
| **Use Case** | Meeting transcription, interview recording, podcast notes |
| **Technical Approach** | Speaker embedding models (e.g., pyannote-style) running locally |
| **Challenges** | Significant additional compute; requires speaker enrollment or clustering |
| **Privacy** | Speaker embeddings are biometric data -- must be handled with extra care |
| **Dependency** | Requires whisper.cpp or a companion library to support diarization |

### Real-Time Translation

Translate transcribed speech from one language to another before injection.

| Aspect | Details |
|---|---|
| **Use Case** | Bilingual workflows, cross-language communication |
| **Technical Approach** | Local translation model (e.g., NLLB, Opus-MT) via llama.cpp or dedicated engine |
| **Challenges** | Translation quality; additional model download; increased latency |
| **Privacy** | Must remain fully local -- no cloud translation APIs |
| **Dependency** | Requires suitable GGUF-format translation models |

### Voice-Controlled Text Editing

Edit already-injected text using voice commands.

| Aspect | Details |
|---|---|
| **Use Case** | "Select the last sentence", "Replace 'foo' with 'bar'", "Delete the previous word" |
| **Technical Approach** | Track injected text positions; use Accessibility API for cursor manipulation |
| **Challenges** | Requires reliable text position tracking across diverse applications |
| **Privacy** | May need to read text from the active app via Accessibility API |
| **Dependency** | Deep integration with the Accessibility API beyond current CGEvent usage |

### Meeting Transcription Mode

Long-form transcription optimized for meetings, lectures, and interviews.

| Aspect | Details |
|---|---|
| **Use Case** | Continuous recording for 30-60+ minutes with structured output |
| **Technical Approach** | Streaming whisper inference with periodic LLM summarization |
| **Challenges** | Memory management for long audio; maintaining context over hours |
| **Privacy** | Long-running transcription increases the sensitivity of stored data |
| **Dependency** | Phase 3 (history) and potentially speaker diarization |

### Third-Party Integrations

Connect HushType to popular productivity tools.

| Integration | Description | Feasibility |
|---|---|---|
| **Raycast** | HushType as a Raycast extension for quick dictation | High -- Raycast has a Swift extension API |
| **Alfred** | Alfred workflow for triggering HushType modes | Medium -- requires Alfred Powerpack |
| **Obsidian** | Direct dictation into Obsidian notes with metadata | Medium -- via URI scheme or plugin |
| **Notion** | Dictation to Notion pages | Low -- requires Notion API (cloud) |

> **Note**: Integrations that require cloud APIs (e.g., Notion) conflict with HushType's privacy-first design. Such integrations would be offered as opt-in plugins with clear privacy disclosures.

### iOS Companion App

A paired iPhone/iPad app for mobile dictation.

| Aspect | Details |
|---|---|
| **Use Case** | Dictate on iPhone, text appears on Mac; mobile note capture |
| **Technical Approach** | Local network pairing via Bonjour; whisper.cpp on iOS (CoreML backend) |
| **Challenges** | iOS performance constraints; cross-device sync without cloud |
| **Privacy** | Data transfer over local network only (no iCloud, no internet) |
| **Dependency** | Requires significant R&D; CoreML Whisper models for iOS |

### Enterprise Features

Features for organizational deployment.

| Feature | Description |
|---|---|
| **MDM configuration** | Managed preferences via macOS MDM profiles |
| **Centralized model distribution** | Organization-hosted model repository (internal HTTP server) |
| **Usage analytics** | Optional, locally-aggregated usage statistics for IT teams |
| **Approved model list** | Restrict which models users can download |
| **Group vocabulary** | Shared vocabulary dictionaries distributed via configuration profiles |

### Open-Core Model

A potential sustainability model for long-term development.

| Tier | License | Features |
|---|---|---|
| **Community** | GPL-3.0 | All core features (Phases 1-5), all processing modes, plugin system |
| **Professional** | Commercial | Priority support, pre-built model bundles, enterprise MDM profiles |
| **Enterprise** | Commercial | Centralized management, custom model training pipeline, SLA |

> **Important**: The open-core model is under consideration only. The core product -- everything described in Phases 1-5 -- will always remain open source under GPL-3.0. See [Legal Compliance](../security/LEGAL_COMPLIANCE.md) for license details.

---

## MVP Definition and Success Criteria

This section provides the formal acceptance criteria for the v0.1.0 MVP release.

### Acceptance Criteria

Each criterion must be verified before the MVP can be tagged and released.

| ID | Criterion | Verification Method |
|---|---|---|
| **AC-01** | User can install by dragging HushType.app to `/Applications` | Manual test on clean macOS 14 installation |
| **AC-02** | App appears in the menu bar on launch with correct icon | Visual inspection |
| **AC-03** | App prompts for Microphone permission on first recording attempt | Manual test on clean install |
| **AC-04** | App prompts for Accessibility permission on first text injection | Manual test on clean install |
| **AC-05** | Default hotkey (`Cmd+Shift+Space`) starts/stops recording system-wide | Test in 5+ different apps (Safari, Terminal, Xcode, Notes, Slack) |
| **AC-06** | Audio is captured from the default microphone at 16kHz mono | Unit test verifying sample rate and channel count |
| **AC-07** | whisper.cpp transcribes audio with the base model | Integration test with known audio sample |
| **AC-08** | Transcribed text is injected at the cursor position via CGEvent | Test in 5+ different apps |
| **AC-09** | Long text (>50 chars) falls back to clipboard paste with restore | Automated test verifying clipboard preservation |
| **AC-10** | End-to-end latency is under 2 seconds for a 5-word sentence | Timed test on Apple Silicon Mac (M1 or later) |
| **AC-11** | Settings window opens from menu bar and persists preferences | Manual test: change setting, restart app, verify persistence |
| **AC-12** | User can change the whisper model in Settings | Download a different model, verify it loads and transcribes |
| **AC-13** | User can change the global hotkey in Settings | Reassign hotkey, verify it works system-wide |
| **AC-14** | App does not crash during 1 hour of continuous use (idle + periodic dictation) | Stability test |
| **AC-15** | Zero network requests during core operation (record, transcribe, inject) | Network monitor verification (see [Security](../security/SECURITY.md)) |

### Non-Functional Requirements

| Requirement | Target | Measurement |
|---|---|---|
| **Startup time** | <0.5s from launch to menu bar icon visible | Timed measurement |
| **Idle CPU** | <1% CPU when not recording | Activity Monitor observation over 10 minutes |
| **Idle RAM** | <100 MB with no model loaded; <500 MB with whisper-base loaded | Activity Monitor |
| **Binary size** | <20 MB (excluding ML models) | `du -sh HushType.app` |
| **Disk usage** | <200 MB total with whisper-base model | Measured after fresh install + model download |
| **Crash rate** | <0.5% of sessions | Tracked during beta testing |
| **Battery impact** | No measurable battery drain when idle | Battery health comparison over 8 hours |

### Out of Scope for MVP

The following features are explicitly deferred to later phases:

| Feature | Deferred To | Rationale |
|---|---|---|
| LLM post-processing | Phase 2 | MVP must work without an LLM download |
| Multiple processing modes | Phase 2 | Depends on LLM integration |
| App-aware context | Phase 3 | Requires per-app profile infrastructure |
| Dictation history | Phase 3 | Requires SwiftData history model |
| Floating overlay | Phase 3 | MVP injects directly without preview |
| Voice commands | Phase 4 | Distinct feature set from dictation |
| Plugin system | Phase 5 | Requires stable core API |
| Multi-language UI | Post-v1.0 | English-only UI for MVP |

---

## Community-Requested Features Backlog

This section serves as a template for tracking feature requests from the community. Items are added here after discussion in GitHub Issues or Discussions and are prioritized based on demand, feasibility, and alignment with HushType's values.

### Backlog Template

| # | Feature Request | Source | Votes | Phase | Feasibility | Privacy Impact | Status |
|---|---|---|---|---|---|---|---|
| CF-001 | _Example: Dictation to multiple apps simultaneously_ | _GitHub Issue #42_ | _12_ | _TBD_ | _Medium_ | _None_ | _Under Review_ |
| CF-002 | | | | | | | |
| CF-003 | | | | | | | |

### Prioritization Criteria

Requested features are evaluated against the following criteria before being added to a phase:

| Criterion | Weight | Description |
|---|---|---|
| **Privacy alignment** | Critical | Must operate 100% locally; any cloud dependency is a non-starter |
| **User demand** | High | Number of unique requestors and upvotes on the issue |
| **Technical feasibility** | High | Can be implemented with reasonable effort using existing architecture |
| **Maintenance burden** | Medium | Long-term cost of maintaining the feature |
| **Scope creep risk** | Medium | Does this pull HushType away from its core mission? |
| **Platform constraints** | Medium | Does macOS provide the necessary APIs? |

### How to Request a Feature

1. Check the [existing issues](https://github.com/hushtype/hushtype/issues) to avoid duplicates
2. Open a new issue using the "Feature Request" template
3. Describe the use case, not just the solution
4. Indicate whether you are willing to contribute implementation effort
5. The maintainers will triage and assign a backlog ID (CF-XXX)

---

## Release Timeline Summary

```
2026
  Q1  ████████████  Phase 1 (MVP v0.1.0) -- Core dictation          [DONE]
  Q1  ████████████  Phase 2 (v0.2.0) -- LLM post-processing         [DONE]
  Q1  ████████████  Phase 3 (v0.3.0) -- Smart features              [DONE]
  Q1  ████████████  Phase 4 (v0.4.0) -- Voice commands              [DONE]
  Q1  ████████████  Phase 5 (v0.5.0) -- Power user & polish         [DONE]
  Q1  ████████░░░░  Phase 6 (v1.0.0) -- Stable release              [IN PROGRESS]
```

| Milestone | Status | Notes |
|-----------|--------|-------|
| **v0.1.0 (MVP)** | Done | 35/35 tasks complete |
| **v0.2.0 (LLM)** | Done | 33/33 tasks complete |
| **v0.3.0 (Smart)** | Done | 29/29 tasks complete |
| **v0.4.0 (Voice)** | Done | 23/23 tasks complete |
| **v0.5.0 (Polish)** | Done | 25/25 tasks complete |
| **v1.0.0 (Stable)** | In Progress | Testing, docs, release workflow remaining |

---

## Related Documentation

- [Technology Stack](../architecture/TECH_STACK.md) -- Complete technology decisions, benchmarks, and integration architecture
- [Database Schema](../architecture/DATABASE_SCHEMA.md) -- SwiftData models, UserDefaults keys, migration strategy, and data lifecycle
- [Security Model](../security/SECURITY.md) -- Privacy guarantees, threat model, permissions, and security architecture
- [Legal Compliance](../security/LEGAL_COMPLIANCE.md) -- GPL-3.0 license, third-party licenses, AI model licensing, and privacy policy

---

*This document is part of the [HushType Documentation](../). For questions, corrections, or feature requests, please open an issue on the [GitHub repository](https://github.com/hushtype/hushtype).*

*HushType is free software licensed under the [GNU General Public License v3.0](../../LICENSE).*
