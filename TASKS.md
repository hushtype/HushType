# TASKS.md — HushType Development Phases

> Phased task list driving DevTrack `/bootstrap`. Each `- [ ]` maps to a board task.
> Nested sub-items are split into separate DevTrack tasks during bootstrap.
> Phase gating: Phase N must be 100% `[x]` before Phase N+1 begins.

---

## Phase 0: Foundation & Project Setup

### 0.1 Project Structure
- [x] Remove Xcode boilerplate — delete `Item.swift`, `ContentView.swift`, replace `HushTypeApp.swift` placeholder content
- [x] Create folder hierarchy — `App/`, `Views/Settings/`, `Views/Overlay/`, `Views/Components/`, `Services/Audio/`, `Services/Speech/`, `Services/LLM/`, `Services/Injection/`, `Services/Commands/`, `Models/`, `Utilities/`, `Resources/`
- [x] Create `AppState.swift` — `@Observable` class holding global app state (recording status, active mode, menu bar icon state)

### 0.2 Utilities & Constants
- [x] Create `Constants.swift` — app bundle ID (`com.hushtype.app`), subsystem for logging, model storage paths, default hotkey, UserDefaults key enum
- [x] Create `Logger+Extensions.swift` — `os.Logger` factory with subsystem `com.hushtype.app` and per-module categories (audio, whisper, llm, injection, ui, hotkey, models)
- [x] Create `UserDefaultsKey.swift` — typed enum for all UserDefaults keys (onboarding, feature flags, window state, cache timestamps, usage state, permissions, UI state)
- [x] Create `KeychainManager.swift` — save/load/delete Keychain items with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`

### 0.3 SwiftData Models
- [x] Create shared enums — `ProcessingMode`, `ModelType`, `InjectionMethod` as `String`-backed `Codable` enums per DATABASE_SCHEMA.md
- [x] Create `DictationEntry.swift` — SwiftData model with rawText, processedText, mode, language, app context, metrics, timestamp, isFavorite
- [x] Create `PromptTemplate.swift` — SwiftData model with name, mode, systemPrompt, userPromptTemplate, variables, isBuiltIn, render() method, and built-in seed data
- [x] Create `AppProfile.swift` — SwiftData model with bundleIdentifier, defaultMode, customVocabulary, preferredLanguage, injectionMethod, cascade relationship to VocabularyEntry
- [x] Create `VocabularyEntry.swift` — SwiftData model with spokenForm, replacement, language, isGlobal, caseSensitive, inverse relationship to AppProfile
- [x] Create `UserSettings.swift` — singleton SwiftData model with all app-wide preferences (model selection, hotkey, processing defaults, UI prefs, history/privacy, performance, injection config)
- [x] Create `ModelInfo.swift` — SwiftData model with name, type, fileName, fileSize, downloadURL, isDownloaded, downloadProgress, pre-seeded whisper model registry

### 0.4 SwiftData Container
- [x] Configure `ModelContainer` in `HushTypeApp.swift` — register all 6 models (DictationEntry, PromptTemplate, AppProfile, VocabularyEntry, UserSettings, ModelInfo), attach to MenuBarExtra and Settings scenes
- [x] Create `HushTypeMigrationPlan.swift` — initial SchemaV1, migration plan structure for future schema evolution
- [x] Seed built-in data on first launch — 4 built-in PromptTemplates (Clean, Structured Notes, Code, Email Draft) and default whisper model registry entries

### 0.5 Entitlements & Permissions
- [x] Configure `HushType.entitlements` — add microphone usage description, accessibility API usage
- [x] Create `PermissionsManager.swift` — check/request microphone permission (AVCaptureDevice), check accessibility permission (AXIsProcessTrusted), guide user to System Settings when denied

---

## Phase 1: MVP — Core Dictation (v0.1.0)

### 1.1 Menu Bar App Shell
- [x] Implement `HushTypeApp.swift` — `@main` with `MenuBarExtra` using SF Symbols for mic state (idle/recording/processing), `.menuBarExtraStyle(.window)`
- [x] Create `AppDelegate.swift` — `NSApplicationDelegate` for lifecycle management, `LSUIElement` dock icon hiding, `NSApplication.shared` configuration
- [x] Create `MenuBarView.swift` — menu bar popover showing current status, last transcription preview, quick settings toggles, mode indicator
- [x] Create `MenuBarManager.swift` — manages menu bar icon state transitions (idle → recording → processing → idle), animates icon during processing

### 1.2 Global Hotkey System
- [x] Create `HotkeyManager.swift` — global hotkey registration using CGEvent tap, default `Cmd+Shift+Space`, support push-to-talk (hold) and toggle (press) modes
- [x] Add hotkey customization — user-configurable shortcut stored in UserSettings, conflict detection warning when shortcut clashes with another app
- [x] Support multiple hotkey slots — register up to 4 hotkeys for different processing modes (Phase 2 will bind modes to hotkeys)

### 1.3 Audio Capture Pipeline
- [x] Create `AudioCaptureService.swift` — `AVAudioEngine` tap on default input device, format conversion to 16kHz mono Float32 PCM, `AudioCapturing` protocol conformance
- [x] Create `VoiceActivityDetector.swift` — energy-based VAD to trim leading/trailing silence, configurable sensitivity threshold
- [x] Create `AudioBuffer.swift` — circular ring buffer (30-second rolling window) for streaming support, thread-safe access
- [x] Add microphone device selection — enumerate available input devices, allow user to choose specific microphone, persist selection in UserSettings

### 1.4 C Bridging: whisper.cpp
- [x] Create `WhisperKit/Package.swift` — local Swift package wrapping whisper.cpp with CMake build, C bridging header
- [x] Add whisper.cpp source — vendored or submodule, configured for macOS with Metal GPU acceleration enabled
- [x] Create `WhisperKit/include/whisper-bridge.h` — C bridging header exposing whisper_init, whisper_free, whisper_full, whisper_full_params
- [x] Create `WhisperContext.swift` — Swift wrapper pairing init/deinit with whisper_init/whisper_free, `@unchecked Sendable`, all C calls on background queue

### 1.5 Speech Recognition Service
- [x] Create `WhisperService.swift` — `TranscriptionEngine` protocol conformance, loads model from ModelInfo path, transcribes Float32 audio buffer, returns text result
- [x] Add model loading — load whisper model on first use (lazy), keep in memory between transcriptions (preloaded), unload on memory pressure
- [x] Add Metal GPU acceleration — enable Metal backend in whisper_full_params for Apple Silicon and AMD GPUs
- [x] Support multiple model sizes — tiny, base, small, medium, large-v3-turbo model loading based on UserSettings.selectedWhisperModel

### 1.6 Text Injection Engine
- [x] Create `TextInjectionService.swift` — `TextInjecting` protocol conformance, injects text at cursor position in any macOS app
- [x] Implement CGEvent injection — simulate keystrokes via CGEvent for short text (<50 chars), handle Unicode including CJK, emoji, diacritics
- [x] Implement clipboard paste fallback — copy to pasteboard, simulate Cmd+V, preserve/restore original clipboard contents
- [x] Add auto-detect strategy — choose CGEvent vs clipboard based on text length, configurable per-app override via InjectionMethod enum

### 1.7 Basic Settings
- [x] Create `SettingsView.swift` — tabbed settings window using SwiftUI `TabView`, minimum 3 tabs for MVP (General, Audio, Models)
- [x] Create `GeneralSettingsTab.swift` — hotkey configuration, push-to-talk vs toggle mode, launch at login (`SMAppService`), dock icon visibility
- [x] Create `AudioSettingsTab.swift` — input device selection picker, VAD sensitivity slider, audio level meter preview
- [x] Create `ModelsSettingsTab.swift` — whisper model list with download status, download/delete buttons, disk usage per model, active model selection

### 1.8 Pipeline Integration
- [x] Wire end-to-end pipeline — hotkey triggers AudioCaptureService → audio flows to WhisperService → transcribed text passes to TextInjectionService → text appears at cursor
- [x] Create `DictationController.swift` — orchestrates the pipeline lifecycle (start recording → stop recording → transcribe → inject), manages state transitions, updates AppState
- [x] Add DictationEntry recording — save each transcription to SwiftData with metadata (rawText, mode=.raw, language, app context, duration, wordCount, timestamp)

### 1.9 MVP Tests
- [x] Create `HotkeyManagerTests.swift` — unit tests for hotkey registration, serialization/deserialization of hotkey config
- [x] Create `AudioCaptureServiceTests.swift` — unit tests for format conversion (verify 16kHz mono Float32 output), buffer management
- [x] Create `WhisperServiceTests.swift` — integration test with known audio sample, verify transcription output matches expected text
- [x] Create `TextInjectionServiceTests.swift` — unit tests for CGEvent keystroke generation, clipboard preserve/restore logic
- [x] Create `DictationEntryTests.swift` — unit tests for SwiftData model creation, computed properties (outputText, wordsPerMinute)

---

## Phase 2: LLM Post-Processing (v0.2.0)

### 2.1 C Bridging: llama.cpp
- [x] Create `LlamaKit/Package.swift` — local Swift package wrapping llama.cpp with CMake build, C bridging header
- [x] Add llama.cpp source — vendored or submodule, configured for macOS with Metal GPU acceleration, GGUF model support
- [x] Create `LlamaKit/include/llama-bridge.h` — C bridging header exposing llama_model_load, llama_free, llama_eval, context management
- [x] Create `LlamaContext.swift` — Swift wrapper pairing init/deinit with llama_init/llama_free, `@unchecked Sendable`, configurable context length (512–4096 tokens), memory management

### 2.2 LLM Service
- [x] Create `LLMService.swift` — `TextProcessing` protocol conformance, wraps LlamaContext, loads GGUF model, runs inference with system+user prompts
- [x] Create `LLMProvider.swift` — protocol abstracting LLM backends (loadModel, complete, isModelLoaded, estimatedMemoryUsage, unloadModel) for swappable backends
- [x] Implement `LlamaCppProvider.swift` — `LLMProvider` conformance using local llama.cpp, Metal offloading, graceful OOM handling
- [x] Implement `OllamaProvider.swift` — `LLMProvider` conformance using Ollama HTTP API on localhost:11434, auto-detect running instance, model listing

### 2.3 Processing Modes
- [x] Create `ProcessingModeRouter.swift` — routes transcription through the correct processing pipeline based on `ProcessingMode` enum (raw passes through, others go to LLM)
- [x] Implement Clean mode — LLM prompt that fixes punctuation, capitalization, removes filler words (um, uh, like)
- [x] Implement Structure mode — LLM prompt that organizes into paragraphs, bullet lists, headings
- [x] Implement Prompt mode — applies user-selected PromptTemplate with variable substitution
- [x] Implement Code mode — LLM prompt optimized for converting spoken instructions into source code
- [x] Implement Custom mode — user-defined pipeline with custom pre/post processors

### 2.4 Prompt Template Engine
- [x] Create `PromptTemplateEngine.swift` — variable substitution engine for `{{transcription}}`, `{{language}}`, `{{app_name}}`, `{{app_bundle_id}}`, `{{timestamp}}`, custom user variables
- [x] Add template CRUD — create, read, update, delete user templates in SwiftData, protect built-in templates from deletion
- [x] Add template validation — check for unresolved variables, warn on empty system/user prompts

### 2.5 Model Manager
- [x] Create `ModelManager.swift` — download GGUF models via URLSession background transfers, SHA-256 verification, progress tracking via ModelInfo.downloadProgress
- [x] Add model storage management — enumerate installed models, show disk usage, delete models, verify file integrity
- [x] Add custom model import — import user-supplied GGUF files from Finder via NSOpenPanel, validate file format, register in ModelInfo

### 2.6 Per-Hotkey Mode Assignment
- [x] Bind processing modes to hotkeys — each of 4 hotkey slots triggers a specific ProcessingMode, stored in UserSettings
- [x] Add mode indicator — show active mode name/icon in menu bar popover when hotkey is pressed
- [x] Add voice prefix triggers — detect mode-switching phrases in first 2 seconds ("code mode", "email mode", "clean this up", "raw mode"), strip prefix from output

### 2.7 Settings: Processing Tab
- [x] Create `ProcessingSettingsTab.swift` — processing mode selection, default mode picker, per-hotkey mode binding UI
- [x] Create `TemplateEditorView.swift` — template list, create/edit/delete templates, system prompt editor, user prompt editor with variable insertion, preview
- [x] Create `ModelManagementView.swift` — unified view for whisper + LLM models, download progress bars, disk usage breakdown, model switcher

### 2.8 Pipeline Update
- [x] Wire LLM into pipeline — Audio → Whisper → ProcessingModeRouter → LLM (if needed) → TextInjection
- [x] Update DictationEntry recording — store both rawText and processedText, record which ProcessingMode was used
- [x] Add LLM backend selection — settings toggle between llama.cpp and Ollama provider

### 2.9 Phase 2 Tests
- [x] Create `LlamaContextTests.swift` — integration test for model loading, simple inference, memory cleanup
- [x] Create `ProcessingModeRouterTests.swift` — unit tests for mode routing, raw passthrough, LLM dispatch
- [x] Create `PromptTemplateEngineTests.swift` — unit tests for variable substitution, built-in template rendering, edge cases (missing variables, empty input)
- [x] Create `ModelManagerTests.swift` — unit tests for model registry, download state tracking, file validation

---

## Phase 3: Smart Features (v0.3.0)

### 3.1 App-Aware Context
- [x] Create `AppContextService.swift` — monitor `NSWorkspace.shared.frontmostApplication` for active app changes, emit notifications on app switch
- [x] Implement per-app profile auto-creation — create default AppProfile the first time user dictates into an unrecognized app, populate from NSRunningApplication
- [x] Add smart defaults — map known bundle IDs to sensible defaults (Xcode→Code mode, Mail→Clean, Terminal→Raw, VS Code→Code, Notes→Structure)
- [x] Create `AppProfileEditorView.swift` — settings UI for managing per-app profiles (mode, language, injection method, vocabulary overrides)

### 3.2 Dictation History
- [x] Create `HistoryView.swift` — dedicated window with list of DictationEntry records, sorted by timestamp descending
- [x] Add full-text search — search across rawText and processedText using SwiftData predicates
- [x] Add filtering — filter by target app (appBundleIdentifier), date range, processing mode, favorites only
- [x] Add edit and re-inject — select a past transcription, edit text, inject at current cursor position
- [x] Add retention policies — configurable auto-deletion by age (historyRetentionDays) and count (maxHistoryEntries), favorites exempt from auto-delete
- [x] Create `HistoryCleanupService.swift` — runs retention policies on app launch and periodically, manual "Clear All History" and "Factory Reset" options

### 3.3 Floating Overlay Window
- [x] Create `OverlayWindow.swift` — floating `NSPanel` (`.nonactivatingPanel`, `.floating`, `.fullSizeContentView`), always-on-top during dictation
- [x] Add real-time transcription display — show whisper output updating in real time as audio is processed
- [x] Add edit-before-inject — user can modify transcribed text in overlay before injecting, Enter to inject, Escape to cancel
- [x] Add overlay controls — mode indicator, language indicator, latency display, cancel/inject buttons
- [x] Add position and transparency settings — configurable overlay position (near cursor, corner, center), adjustable opacity

### 3.4 Custom Vocabulary
- [x] Create `VocabularyService.swift` — apply vocabulary replacements to transcription text before LLM processing, merge global + per-app entries
- [x] Create `VocabularyEditorView.swift` — settings UI for managing spoken form / replacement pairs, global vs per-app scope, import/export as JSON

### 3.5 Multi-Language Support
- [x] Add language selection — explicit language setting in UserSettings and per-app AppProfile, auto-detect via whisper.cpp first-30-seconds analysis
- [x] Add language indicator — show detected/selected language code in menu bar popover and overlay
- [x] Pass language to LLM — include detected language in PromptTemplate `{{language}}` variable for language-aware processing
- [x] Add per-app language override — AppProfile.preferredLanguage overrides global default for specific apps

### 3.6 Settings: Advanced Tabs
- [x] Create `AppProfilesSettingsTab.swift` — list of per-app profiles with edit/delete, auto-created profile indicators
- [x] Create `VocabularySettingsTab.swift` — vocabulary editor tab with global and per-app scopes
- [x] Create `LanguageSettingsTab.swift` — global language selection, auto-detect toggle, language priority list
- [x] Create `HistorySettingsTab.swift` — retention policies configuration, storage usage display, clear history button, export/import

### 3.7 Phase 3 Tests
- [x] Create `AppContextServiceTests.swift` — unit tests for frontmost app detection, profile auto-creation, smart defaults mapping
- [x] Create `HistoryViewTests.swift` — unit tests for SwiftData queries, search, filtering, retention policy enforcement
- [x] Create `OverlayWindowTests.swift` — unit tests for overlay lifecycle (show/hide/dismiss), edit-before-inject flow
- [x] Create `VocabularyServiceTests.swift` — unit tests for replacement matching (case sensitive/insensitive), global vs per-app merge order

---

## Phase 4: Voice Commands (v0.4.0)

### 4.1 Command Engine
- [x] Create `CommandDetector.swift` — distinguish between dictation text and voice commands using configurable wake phrase prefix (e.g., "Hey Type", "Computer")
- [x] Create `CommandParser.swift` — parse natural language commands into structured `ParsedCommand` objects with action type and arguments
- [x] Create `CommandExecutor.swift` — dispatch parsed commands to registered handlers, return `CommandResult` with success/failure/feedback
- [x] Create `CommandRegistry.swift` — registry of built-in and custom commands, enable/disable per command, command lookup by pattern

### 4.2 App Management Commands
- [x] Implement "Open {app}" — launch application by name using `NSWorkspace.shared.open`
- [x] Implement "Switch to {app}" — bring application to foreground using `NSRunningApplication.activate`
- [x] Implement "Close/Quit/Hide {app}" — close frontmost window, terminate app, hide app via NSRunningApplication APIs
- [x] Implement "Show all windows" — invoke Mission Control via `CGEvent` or private API

### 4.3 Window Management Commands
- [x] Implement window tiling — "Move window left/right" tiles to half screen, "Maximize/Minimize/Center window" using Accessibility API (`AXUIElement`)
- [x] Implement full screen toggle — "Full screen" enters/exits macOS native full-screen mode
- [x] Implement multi-display — "Next screen" moves window to the next connected display

### 4.4 System Control Commands
- [x] Implement volume controls — "Volume up/down" adjusts by 10%, "Volume {number}" sets specific level, "Mute/Unmute" toggles via CoreAudio
- [x] Implement brightness controls — "Brightness up/down" adjusts display brightness
- [x] Implement system toggles — "Do not disturb on/off", "Dark mode / Light mode", "Lock screen", "Screenshot"

### 4.5 Workflow Automation
- [x] Implement command chaining — execute multiple commands in sequence from a single voice input (e.g., "Open Safari and switch to dark mode")
- [x] Add Apple Shortcuts integration — trigger Shortcuts app workflows by name via `NSUserActivity` or URL scheme
- [x] Add custom command definitions — users define named commands mapped to action sequences, stored in SwiftData

### 4.6 Settings: Commands Tab
- [x] Create `CommandSettingsTab.swift` — list of all commands (built-in + custom), enable/disable toggles, wake phrase configuration
- [x] Create `CustomCommandEditorView.swift` — create/edit custom commands with action sequence builder, test execution

### 4.7 Phase 4 Tests
- [x] Create `CommandDetectorTests.swift` — unit tests for command vs dictation classification, wake phrase detection
- [x] Create `CommandParserTests.swift` — unit tests for natural language parsing, argument extraction, edge cases
- [x] Create `CommandExecutorTests.swift` — unit tests for command dispatch, error handling, result reporting
- [x] Create `CommandRegistryTests.swift` — unit tests for command registration, lookup, enable/disable state

---

## Phase 5: Power User & Polish (v0.5.0)

### 5.1 Keyboard Shortcut Chaining
- [x] Implement shortcut dictation — say "Command Shift N" or "New folder" and inject the keystroke combination via CGEvent
- [ ] Add app-aware shortcut aliases — know that "Build and run" = Cmd+R in Xcode, "Save all" = Cmd+Option+S, store aliases in AppProfile
- [ ] Add user-defined shortcut aliases — custom name-to-keystroke mappings managed in settings

### 5.2 Audio Feedback
- [x] Add recording start/stop sounds — distinct tones using `NSSound` or `AudioServicesPlaySystemSound`
- [x] Add success/error sounds — audio confirmation for command execution results
- [x] Add sound configuration — enable/disable, independent volume control, multiple sound themes (subtle, mechanical, none)

### 5.3 Accessibility
- [x] Add VoiceOver support — full VoiceOver compatibility with meaningful accessibility labels on all interactive elements
- [x] Add state announcements — announce recording/processing/injection state changes to assistive technology via `NSAccessibility.post`
- [x] Add keyboard navigation — full keyboard navigation for all UI (settings, history, overlay, menu bar popover)
- [x] Respect system preferences — high contrast support, reduce motion, dynamic type scaling

### 5.4 Performance Optimization
- [x] Implement battery-aware mode — reduce model quality and thread count on battery power (downgrade whisper model tier, reduce GPU layers, cap threads)
- [x] Implement thermal management — throttle inference when system is thermally constrained via `ProcessInfo.thermalState`
- [x] Implement memory pressure response — unload LLM model under memory pressure (`DispatchSource.memoryPressure`), keep whisper loaded as priority
- [x] Optimize startup — target <0.5s launch to menu bar readiness, lazy model loading on first use, near-zero idle CPU (event-driven, no polling)

### 5.5 Onboarding
- [x] Create `OnboardingView.swift` — first-launch setup flow guiding through microphone permission, accessibility permission, model download selection
- [x] Add permission request flow — step-by-step permission granting with clear explanations and deep links to System Settings
- [x] Add initial model download — guided download of default whisper model (base English) during onboarding with progress

### 5.6 Plugin System
- [x] Define `HushTypePlugin` protocol — plugin interface with identifier, displayName, version, activate/deactivate lifecycle
- [x] Define `ProcessingPlugin` protocol — transform text in the pipeline with custom logic
- [x] Define `CommandPlugin` protocol — add new voice commands via plugin
- [x] Implement plugin discovery — load plugins from `~/Library/Application Support/HushType/Plugins/`, sandboxed execution with restricted system access
- [ ] Create `PluginManagerView.swift` — settings UI to install, enable/disable, and remove plugins

### 5.7 Phase 5 Tests
- [x] Create accessibility audit tests — verify VoiceOver labels, keyboard navigation paths, state announcements
- [x] Create performance benchmark tests — measure end-to-end latency, startup time, idle CPU/RAM, battery impact
- [x] Create `OnboardingViewTests.swift` — UI tests for onboarding flow, permission request sequences

---

## Phase 6: Stable Release (v1.0.0)

### 6.1 Code Signing & Notarization
- [ ] Configure Developer ID certificate — set up code signing identity for distribution outside the Mac App Store
- [ ] Add notarization — integrate `notarytool` into build pipeline, submit app for Apple notarization, staple ticket to DMG

### 6.2 Distribution
- [ ] Create DMG packaging — build `.dmg` installer with drag-to-Applications layout, background image, volume icon
- [ ] Integrate Sparkle 2.x — auto-update framework with EdDSA signatures, appcast XML, delta updates
- [ ] Submit Homebrew cask — create and submit `homebrew-cask` formula for `brew install --cask hushtype`

### 6.3 CI/CD Pipeline
- [ ] Create GitHub Actions build workflow — build on macOS runners, cache Swift/CMake dependencies, matrix for Debug/Release
- [ ] Create GitHub Actions test workflow — run unit + integration tests, upload test results, fail PR on test failure
- [ ] Create GitHub Actions release workflow — build signed app, notarize, create DMG, create GitHub Release with artifacts, update Sparkle appcast
- [ ] Add linting to CI — run SwiftLint and SwiftFormat checks on every PR

### 6.4 Final QA
- [ ] Full regression testing — verify all Phase 1–5 features work together end-to-end
- [ ] Memory leak testing — profile with Instruments Leaks, verify C bridging code cleanup (whisper_free, llama_free)
- [ ] Stability testing — 1-hour continuous use test (idle + periodic dictation), verify zero crashes and <0.1% error rate
- [ ] Privacy verification — monitor network traffic during all operations, verify zero outbound connections for core functionality
- [ ] Accessibility compliance — WCAG 2.1 AA audit for all UI, VoiceOver walkthrough of complete user flow

### 6.5 Documentation
- [ ] Update all docs — ensure docs/ files reflect final implementation, remove outdated references, add missing API documentation
- [ ] Create user guide — end-user documentation for installation, setup, daily use, troubleshooting
- [ ] Create plugin development guide — developer documentation for building HushType plugins with example code

---

## Release Criteria

### v0.1.0 (MVP)
- User can install by dragging to /Applications
- Cmd+Shift+Space starts/stops recording system-wide
- Audio captured at 16kHz mono, transcribed by whisper.cpp (base model)
- Text injected at cursor via CGEvent/clipboard in any app
- End-to-end latency <2s for a 5-word sentence on Apple Silicon
- Settings window for hotkey, audio input, model selection
- Zero network requests during core operation

### v1.0.0 (Stable)
- All Phase 1–5 features shipped and functional
- >80% code coverage
- Zero known crash bugs, <0.1% crash rate
- WCAG 2.1 AA accessibility compliance
- Notarized DMG, Sparkle auto-updates, Homebrew cask
- Complete user and developer documentation
