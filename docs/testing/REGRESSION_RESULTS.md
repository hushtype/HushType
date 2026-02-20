# HushType Regression Test Results

## Test Environment

- Date: 2026-02-20
- macOS Version: 26.2 (Build 25C56)
- Xcode Version: 26.2 (Build 17C52)
- Branch: main
- Architecture: arm64 (Apple Silicon)

---

## Automated Tests

Build result: **TEST BUILD SUCCEEDED**

Command used:
```
xcodebuild build-for-testing -scheme HushType -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/claude/DerivedData CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

Note: The test host (AppDelegate) calls `terminateOtherInstances()` on launch, which kills test runner processes. Automated test execution via `xcodebuild test` is unreliable in this environment. The build-for-testing succeeds; manual test execution in Xcode is required for actual run results.

| Test File | Test Count | Coverage Area | Status |
|-----------|-----------|---------------|--------|
| AccessibilityAuditTests.swift | 24 | AppState announcements, OverlayWindow transparency, system preferences | BUILD OK |
| AppContextServiceTests.swift | 26 | Frontmost app detection, per-app profile resolution, smart defaults | BUILD OK |
| AudioBufferTests.swift | 13 | Circular ring buffer, thread safety, overflow, capacity | BUILD OK |
| CommandDetectorTests.swift | 13 | Wake phrase matching, case insensitivity, separator handling | BUILD OK |
| CommandExecutorTests.swift | 4 | Disabled command rejection, unknown app handling, chain execution | BUILD OK |
| CommandParserTests.swift | 42 | ~25 intent patterns, chain parsing (and/then/also), trailing punctuation | BUILD OK |
| CommandRegistryTests.swift | 14 | Built-in command registration, enable/disable, intent coverage | BUILD OK |
| DictationEntryTests.swift | 16 | SwiftData model, computed properties (outputText, wordsPerMinute), isFavorite | BUILD OK |
| HistoryViewTests.swift | 7 | SwiftData queries, filtering, retention policy enforcement | BUILD OK |
| HotkeyManagerTests.swift | 11 | HotkeyBinding parse/serialize, keycode mapping, modifier flags | BUILD OK |
| LlamaContextTests.swift | 16 | GenerationResult, LlamaContextError descriptions, init failure paths | BUILD OK |
| ModelDownloaderTests.swift | 20 | URLSession download, SHA-256 verification, progress tracking, cancellation | BUILD OK |
| ModelManagerTests.swift | 7 | Model registry, download state, file validation | BUILD OK |
| ModelRegistryServiceTests.swift | 10 | Registry queries, installed model enumeration, disk usage | BUILD OK |
| OnboardingViewTests.swift | 16 | OnboardingStepView init, PermissionsManager API, UserDefaults onboarding flag | BUILD OK |
| OverlayWindowTests.swift | 7 | OverlayWindow show/hide, Position enum, canBecomeKey/canBecomeMain | BUILD OK |
| PerformanceBenchmarkTests.swift | 16 | CommandParser latency, CommandDetector throughput, PowerManagementService | BUILD OK |
| ProcessingModeRouterTests.swift | 12 | Raw passthrough, Clean/Structure/Code/Prompt/Custom routing, LLM dispatch | BUILD OK |
| PromptTemplateEngineTests.swift | 21 | Variable substitution, built-in templates, edge cases (missing vars, empty input) | BUILD OK |
| PromptTemplateTests.swift | 22 | PromptTemplate model, render(), variable validation, built-in protection | BUILD OK |
| TextInjectionServiceTests.swift | 13 | CGEvent creation, ClipboardInjector preserve/restore, method selection | BUILD OK |
| VocabularyServiceTests.swift | 8 | Spoken→replacement matching, global vs per-app priority, case sensitivity | BUILD OK |
| VoiceActivityDetectorTests.swift | 13 | Silence trimming, voice range detection, sensitivity boundaries | BUILD OK |

**Total automated tests: 371**

---

## Manual Test Checklist

The items below require manual execution on a physical Mac with microphone hardware, accessibility permissions, and downloaded AI models. Check each item off as it is verified.

---

### Phase 1: Core Dictation (v0.1.0)

#### 1.1 Menu Bar App Shell
- [ ] App launches with no dock icon (LSUIElement=1 is effective)
- [ ] Menu bar icon appears in the system menu bar
- [ ] Menu bar popover opens on click and shows current status
- [ ] Menu bar icon changes to indicate recording state (idle/recording/processing)
- [ ] Menu bar icon animates during processing (spinner or pulsing effect)
- [ ] App quits cleanly via the menu bar menu

#### 1.2 Global Hotkey System
- [ ] Default hotkey (fn key, push-to-talk) starts recording on press
- [ ] Default hotkey stops recording on release
- [ ] Toggle mode starts/stops recording on successive presses
- [ ] Hotkey is detected globally (works when another app is frontmost)
- [ ] Custom hotkey can be configured in Settings > General
- [ ] Conflict warning appears when a hotkey clashes with a system shortcut
- [ ] Up to 4 hotkey slots can each be assigned a different processing mode

#### 1.3 Audio Capture Pipeline
- [ ] Microphone permission dialog appears on first launch
- [ ] Audio capture produces 16 kHz mono Float32 PCM output
- [ ] Input device selection works in Settings > Audio
- [ ] Audio level meter shows live microphone input in Settings > Audio
- [ ] VAD trims leading and trailing silence from captured audio
- [ ] VAD sensitivity slider in Settings > Audio changes trimming aggressiveness

#### 1.4 C Bridging: whisper.cpp
- [ ] whisper.cpp compiles as part of the Xcode build (Run Script build phase)
- [ ] Metal GPU acceleration is active (check Console for ggml-metal.log messages)
- [ ] WhisperContext initializes without crashing on a downloaded model file
- [ ] WhisperContext deinit frees C memory (no leak reported by Instruments)

#### 1.5 Speech Recognition
- [ ] Whisper model loads from ~/Library/Application Support/HushType/Models/
- [ ] Transcription of clear speech returns sensible text
- [ ] Transcription runs on a background queue (UI remains responsive)
- [ ] Model selection in Settings > Models switches between tiny/base/small/medium/large-v3-turbo
- [ ] Model reloads automatically after selection change without restart

#### 1.6 Text Injection
- [ ] Short ASCII text (<50 chars) is injected via CGEvent keystrokes when accessibility is granted
- [ ] Long text or Unicode uses clipboard paste (Cmd+V simulation)
- [ ] Original clipboard contents are restored after clipboard injection
- [ ] Text appears at the current cursor position in the target app (TextEdit, Notes, etc.)
- [ ] Unicode text (CJK, emoji, diacritics) injects correctly via clipboard
- [ ] TextInjectionError.accessibilityNotGranted is thrown when permission is missing and CGEvent is required

#### 1.7 Basic Settings
- [ ] Settings window opens from menu bar menu
- [ ] Settings window has tabs: General, Audio, Models (minimum MVP tabs)
- [ ] General tab: hotkey configuration field works
- [ ] General tab: push-to-talk vs toggle mode switch persists across restarts
- [ ] General tab: Launch at Login toggle works (SMAppService)
- [ ] Audio tab: input device picker shows all available microphones
- [ ] Models tab: whisper model list shows all registry entries with download status
- [ ] Models tab: Download button initiates background download with progress bar
- [ ] Models tab: Delete button removes model file and updates download status

#### 1.8 Pipeline Integration (End-to-End)
- [ ] Complete flow: press hotkey -> speak -> release -> text appears at cursor
- [ ] DictationEntry is saved to SwiftData after each transcription
- [ ] DictationEntry contains: rawText, mode=.raw, language, app bundle ID, duration, word count, timestamp
- [ ] Pipeline state (recording/processing/idle) is reflected in AppState and menu bar icon

---

### Phase 2: LLM Post-Processing (v0.2.0)

#### 2.1 C Bridging: llama.cpp
- [ ] llama.cpp compiles alongside whisper.cpp without duplicate ggml symbol errors
- [ ] LlamaContext initializes with a valid GGUF model file
- [ ] LlamaContext deinit frees C memory cleanly
- [ ] Metal GPU offloading is active for llama.cpp inference

#### 2.2 LLM Service
- [ ] LLMService loads a GGUF model via LlamaCppProvider
- [ ] LLMService runs inference on a background thread
- [ ] LLMProvider protocol allows swapping between LlamaCppProvider and other backends
- [ ] OllamaProvider was removed in refactor (verify no OllamaProvider references remain in service layer)

#### 2.3 Processing Modes
- [ ] Raw mode: transcription passes through unmodified, LLM is never called
- [ ] Clean mode: filler words (um, uh, like) and grammar errors are fixed
- [ ] Structure mode: output contains headings and/or bullet lists
- [ ] Prompt mode: uses the selected PromptTemplate with variable substitution
- [ ] Code mode: spoken programming constructs are converted to source code syntax
- [ ] Custom mode: user-defined template is applied; falls back to Clean if no template selected
- [ ] ProcessingMode.requiresLLM correctly returns true for non-raw modes and false for raw

#### 2.4 Prompt Template Engine
- [ ] {{transcription}} variable is substituted with actual transcribed text
- [ ] {{language}} variable is substituted with the detected language code
- [ ] {{app_name}} variable is substituted with the active application name
- [ ] {{app_bundle_id}} variable is substituted with the active application bundle ID
- [ ] {{timestamp}} variable is substituted with current date/time
- [ ] Custom user variables specified in PromptTemplate.variables are substituted correctly
- [ ] Missing variable substitution produces a warning but does not crash
- [ ] Built-in templates cannot be deleted
- [ ] User templates can be created, edited, and deleted

#### 2.5 Model Manager
- [ ] GGUF model download starts from a valid URL, shows progress in Settings > Models
- [ ] SHA-256 checksum is verified after download; corrupted downloads are rejected
- [ ] Completed download is registered in ModelInfo.isDownloaded
- [ ] Model deletion removes the file from disk and resets ModelInfo.downloadProgress
- [ ] Custom GGUF file can be imported via NSOpenPanel (Settings > Models)
- [ ] Imported file is validated and registered in the model registry

#### 2.6 Per-Hotkey Mode Assignment
- [ ] Each of 4 hotkey slots can be assigned a different ProcessingMode in Settings
- [ ] Active mode name or icon is shown in the menu bar popover when hotkey is pressed
- [ ] Voice prefix "code mode:" at start of dictation switches to Code mode and strips prefix
- [ ] Voice prefix "clean this up:" switches to Clean mode and strips prefix
- [ ] VoicePrefixDetector strips the prefix before Vocabulary and LLM processing

#### 2.7 Settings: Processing Tab
- [ ] Processing tab renders with mode selection and per-hotkey binding UI
- [ ] Template editor lists built-in and user templates
- [ ] Template editor: system prompt and user prompt editors update template in real time
- [ ] Template editor: variable insertion helper inserts {{transcription}} at cursor
- [ ] Template editor: Preview button shows a mock render
- [ ] Model Management view shows both whisper and LLM models with disk usage

#### 2.8 Pipeline Update
- [ ] LLM processes transcription output before injection when mode != .raw
- [ ] DictationEntry stores both rawText and processedText after LLM run
- [ ] DictationEntry.mode reflects the ProcessingMode used (not always .raw)

---

### Phase 3: Smart Features (v0.3.0)

#### 3.1 App-Aware Context
- [ ] AppContextService detects the frontmost application on launch
- [ ] AppContextService updates currentAppName when the user switches apps
- [ ] First dictation into an unrecognized app creates a default AppProfile automatically
- [ ] Xcode is auto-mapped to Code mode; Mail to Clean; Terminal to Raw; Notes to Structure
- [ ] AppProfileEditorView shows the per-app profile list with edit/delete controls

#### 3.2 Dictation History
- [ ] HistoryView opens from the menu bar menu or Settings
- [ ] History list shows DictationEntry records sorted by timestamp descending
- [ ] Full-text search across rawText and processedText returns correct results
- [ ] Filtering by app, date range, processing mode, and favorites-only works
- [ ] Selecting a past entry and clicking "Re-inject" injects that text at the current cursor
- [ ] Editing a past entry text and re-injecting uses the edited version
- [ ] HistoryCleanupService deletes entries older than historyRetentionDays on launch
- [ ] HistoryCleanupService deletes entries beyond maxHistoryEntries count limit
- [ ] Entries marked as favorites are exempted from all auto-deletion policies
- [ ] "Clear All History" removes all non-favorite entries
- [ ] "Factory Reset" removes all entries including favorites

#### 3.3 Floating Overlay Window
- [ ] Overlay NSPanel appears floating above all other windows during dictation
- [ ] Overlay does not activate/steal focus from the target app
- [ ] Transcription text updates in the overlay as whisper produces output
- [ ] User can edit text in the overlay before injecting
- [ ] Pressing Enter in the overlay injects the edited text and closes the overlay
- [ ] Pressing Escape in the overlay cancels without injecting
- [ ] Overlay shows mode indicator, language indicator, and latency display
- [ ] Overlay position (near cursor / top center / bottom center / center) is configurable in Settings
- [ ] Overlay transparency/opacity is configurable in Settings

#### 3.4 Custom Vocabulary
- [ ] VocabularyService replaces spoken forms with configured replacements in transcription output
- [ ] Global vocabulary entries apply to all apps
- [ ] Per-app vocabulary entries take priority over global entries when both match
- [ ] Case-sensitive entries only match the exact case
- [ ] Case-insensitive entries match regardless of case
- [ ] VocabularyEditorView: add, edit, delete entries with spoken form and replacement fields
- [ ] VocabularyEditorView: scope selector toggles between Global and per-app
- [ ] Import/export vocabulary as JSON works

#### 3.5 Multi-Language Support
- [ ] Global language selection in Settings > Language persists across restarts
- [ ] Auto-detect language toggle passes null language to whisper for automatic detection
- [ ] Detected language code appears in the menu bar popover and overlay
- [ ] {{language}} variable in PromptTemplates receives the detected language string
- [ ] AppProfile.preferredLanguage overrides the global language setting for that app

#### 3.6 Settings: Advanced Tabs
- [ ] Settings has exactly 10 tabs: General, Audio, Models, Processing, App Profiles, Vocabulary, Language, History, Commands, Plugins
- [ ] App Profiles tab: lists all per-app profiles; edit and delete controls work
- [ ] App Profiles tab: auto-created profile indicator is shown
- [ ] Vocabulary tab: global and per-app scoped vocabulary editor is functional
- [ ] Language tab: global language picker and auto-detect toggle render correctly
- [ ] History tab: retention policy inputs persist; storage usage updates after clearing history

---

### Phase 4: Voice Commands (v0.4.0)

#### 4.1 Command Engine
- [ ] Wake phrase "Hey Type" followed by a command is detected and separated from dictation text
- [ ] Wake phrase detection is case-insensitive ("hey type", "HEY TYPE", "Hey Type" all match)
- [ ] Wake phrase followed only by a separator (comma, period) with no command returns nil
- [ ] Custom wake phrase (e.g., "Computer") can be configured in Settings > Commands
- [ ] CommandParser parses approximately 25 natural language intent patterns
- [ ] CommandParser returns nil for unrecognized text
- [ ] CommandExecutor dispatches parsed commands to the correct handlers
- [ ] CommandExecutor returns a CommandResult with success flag and feedback message
- [ ] Disabled commands return failure without executing

#### 4.2 App Management Commands
- [ ] "Open Safari" (and "launch", "start") launches the named application
- [ ] "Switch to Finder" (and "go to", "activate", "bring up") brings the app to foreground
- [ ] "Close Terminal" closes the frontmost window of that app
- [ ] "Quit Xcode" (and "exit", "terminate") terminates the application
- [ ] "Hide Finder" hides the application
- [ ] "Show all windows" triggers Mission Control

#### 4.3 Window Management Commands
- [ ] "Move window left" tiles the active window to the left half of the screen
- [ ] "Move window right" tiles the active window to the right half of the screen
- [ ] "Maximize window" (and "expand", "fill screen") zooms the active window
- [ ] "Minimize window" minimizes the active window to the Dock
- [ ] "Center window" centers the active window on the display
- [ ] "Full screen" (and "toggle full screen", "enter full screen") toggles native full-screen
- [ ] "Next screen" (and "other screen", "move to next display") moves window to next connected display

#### 4.4 System Control Commands
- [ ] "Volume up" (and "louder", "increase volume", "turn it up") increases system volume by 10%
- [ ] "Volume down" (and "softer", "decrease volume") decreases system volume by 10%
- [ ] "Volume 50" (and "set volume to 50") sets volume to the specified level (0-100)
- [ ] "Mute" (and "toggle mute", "unmute") toggles system mute
- [ ] "Brightness up" (and "brighter", "increase brightness") increases display brightness
- [ ] "Brightness down" (and "dimmer", "decrease brightness") decreases display brightness
- [ ] "Dark mode" toggles macOS dark/light appearance via AppleScript
- [ ] "Do not disturb" toggles Focus/Do Not Disturb mode
- [ ] "Lock screen" locks the macOS login session
- [ ] "Take screenshot" (and "screen capture", "capture screen") triggers a screenshot

#### 4.5 Workflow Automation
- [ ] Command chaining with "and": "volume up and dark mode" executes both in sequence
- [ ] Command chaining with "then": "mute then lock screen" executes both in sequence
- [ ] Command chaining with "also": "mute also dark mode" executes both in sequence
- [ ] Command chaining with "and then": "open Safari and then volume up" executes both
- [ ] Multi-segment chain: "open Safari and close Finder and then volume up" parses to 3 commands
- [ ] Chain stops on first failure (CommandExecutor.executeChain behavior)
- [ ] "Run shortcut Morning Routine" triggers the named Shortcuts app workflow
- [ ] Custom commands defined in SwiftData are executed when matched by name

#### 4.6 Settings: Commands Tab
- [ ] Commands tab lists all built-in commands with enable/disable toggles
- [ ] Disabling a command in Settings prevents it from executing
- [ ] Wake phrase field in Settings > Commands persists across restarts
- [ ] CustomCommandEditorView: create a custom command with a name and action sequence
- [ ] CustomCommandEditorView: test execution button runs the command immediately

---

### Phase 5: Power User & Polish (v0.5.0)

#### 5.1 Keyboard Shortcut Chaining
- [ ] Saying "Command Shift N" injects Cmd+Shift+N via CGEvent
- [ ] Saying "Command R" injects Cmd+R (useful for "Build and run" in Xcode context)
- [ ] App-specific shortcut alias "Build and run" maps to Cmd+R in Xcode AppProfile
- [ ] App-specific shortcut alias "Save all" maps to Cmd+Option+S in supported apps
- [ ] User-defined global shortcut aliases can be added in Settings > General
- [ ] Pipeline applies app-specific aliases before global aliases before regex patterns

#### 5.2 Audio Feedback
- [ ] A sound plays when recording starts
- [ ] A distinct sound plays when recording stops
- [ ] A success sound plays after a voice command executes successfully
- [ ] An error sound plays when a command fails
- [ ] A completion sound plays after text injection
- [ ] Sound feedback can be disabled entirely in Settings > General
- [ ] "Subtle" theme sounds are soft and unobtrusive
- [ ] "Mechanical" theme sounds are distinct click/clack tones
- [ ] "None" theme produces no audio output

#### 5.3 Accessibility
- [ ] All buttons and controls in Settings have meaningful VoiceOver accessibility labels
- [ ] Recording state changes are announced to VoiceOver ("Recording started", "Processing complete", etc.)
- [ ] AppState.announceRecordingStarted() / announceRecordingCompleted() / announceProcessing() / announceError() do not crash
- [ ] All Settings tabs are reachable via keyboard Tab navigation without a mouse
- [ ] History list is navigable with keyboard (arrow keys, Enter to select)
- [ ] AppState.prefersReducedMotion reflects NSWorkspace accessibility display preference
- [ ] AppState.prefersReducedTransparency reflects NSWorkspace accessibility display preference
- [ ] AppState.prefersHighContrast reflects NSWorkspace accessibility display preference
- [ ] OverlayWindow.applyTransparencyPreference() makes window opaque when Reduce Transparency is on

#### 5.4 Performance Optimization
- [ ] PowerManagementService.isOnBattery correctly reflects battery vs AC power state
- [ ] On battery power: whisper thread count is reduced (recommendedWhisperThreadCount returns lower value)
- [ ] On battery power: LLM model quality is reduced or GPU layers are capped
- [ ] PowerManagementService.thermalState reflects ProcessInfo.thermalState
- [ ] On critical thermal state: shouldSkipLLMProcessing returns true and LLM is bypassed
- [ ] On memory pressure: LLM model is unloaded; whisper model remains loaded
- [ ] App reaches menu bar readiness within 0.5 seconds of launch (lazy model loading)
- [ ] Idle CPU usage is near zero (no polling loops; event-driven architecture)

#### 5.5 Onboarding
- [ ] Onboarding wizard appears on first launch (when com.hushtype.onboardingCompleted is false)
- [ ] Onboarding does not appear on subsequent launches after completion
- [ ] Step 1 (Welcome): title and description render correctly
- [ ] Step 2 (Microphone): "Grant Access" button calls requestMicrophoneAccess() without crash
- [ ] Step 3 (Accessibility): "Open Settings" deep-links to macOS Accessibility settings
- [ ] Step 4 (Model Download): guided download of default whisper base model with progress indicator
- [ ] Step 5 (Done): "Get Started" button sets com.hushtype.onboardingCompleted = true and dismisses
- [ ] Onboarding can be re-triggered via a Settings option or developer defaults override

#### 5.6 Plugin System
- [ ] Plugin discovery scans ~/Library/Application Support/HushType/Plugins/ on launch
- [ ] A valid ProcessingPlugin found in that directory is listed in PluginManagerView
- [ ] A valid CommandPlugin found in that directory adds new voice commands
- [ ] Activating a plugin calls plugin.activate() without crash
- [ ] Deactivating a plugin calls plugin.deactivate() without crash
- [ ] Plugins tab in Settings renders PluginManagerView with install/enable/disable/remove controls
- [ ] Removing a plugin calls deactivate() and removes it from the active plugin list

---

### Integration Regression: Full Pipeline Smoke Test

The following sequence exercises the complete pipeline end-to-end. Run this after each significant code change.

- [ ] Launch app fresh (no previous instance)
- [ ] Onboarding is skipped (already completed)
- [ ] Menu bar icon is idle (no recording)
- [ ] Press fn (push-to-talk): icon switches to recording state, overlay appears
- [ ] Speak clearly for 2-3 seconds
- [ ] Release fn: icon switches to processing state
- [ ] Overlay shows transcription text
- [ ] Text is injected at cursor in the active text field
- [ ] DictationEntry appears in History (HistoryView)
- [ ] Say "Hey Type volume up" while recording: volume increases, no text is injected
- [ ] Switch to Xcode: AppContextService detects Xcode bundle ID, mode auto-selects Code
- [ ] Switch back to Notes: AppContextService detects Notes, mode auto-selects Structure
- [ ] Open Settings: all 10 tabs render without crash
- [ ] Close Settings: settings changes are persisted (reopen and verify)
- [ ] Quit app: no orphaned processes remain (no zombie HushType instances)

---

## Known Issues and Deferred Tests

| Issue | Reference | Status |
|-------|-----------|--------|
| CGEvent injection requires accessibility permission that is unreliable during development (code signature changes per build) | HUSHTYPE-60 | Backlog: remove clipboard fallback for production |
| Test runner crashes on launch due to AppDelegate.terminateOtherInstances() killing test host | Architecture note in MEMORY.md | Workaround: guard with `ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil` |
| OllamaProvider was removed in refactor; any tests referencing it should be updated | Commit 220e951 | Verify no stale OllamaProvider test references remain |
| CLI builds blocked by sandbox — requires `dangerouslyDisableSandbox: true` on xcodebuild | HUSHTYPE-59 | Done (resolved) |

---

## Test File Reference

All test files are located in `/Users/harungungorer/dev/HushType/HushTypeTests/`:

| Test File | Phase | Key Classes Under Test |
|-----------|-------|----------------------|
| AccessibilityAuditTests.swift | Phase 5 | AppState, OverlayWindow |
| AppContextServiceTests.swift | Phase 3 | AppContextService, AppProfile |
| AudioBufferTests.swift | Phase 1 | AudioBuffer |
| CommandDetectorTests.swift | Phase 4 | CommandDetector |
| CommandExecutorTests.swift | Phase 4 | CommandExecutor, CommandRegistry |
| CommandParserTests.swift | Phase 4 | CommandParser |
| CommandRegistryTests.swift | Phase 4 | CommandRegistry, CommandIntent |
| DictationEntryTests.swift | Phase 1 | DictationEntry |
| HistoryViewTests.swift | Phase 3 | DictationEntry, HistoryCleanupService |
| HotkeyManagerTests.swift | Phase 1 | HotkeyBinding, HotkeyManager |
| LlamaContextTests.swift | Phase 2 | LlamaContext, LlamaContextError, GenerationResult |
| ModelDownloaderTests.swift | Phase 2 | ModelDownloader |
| ModelManagerTests.swift | Phase 2 | ModelManager, ModelInfo |
| ModelRegistryServiceTests.swift | Phase 2 | ModelRegistryService |
| OnboardingViewTests.swift | Phase 5 | OnboardingStepView, PermissionsManager |
| OverlayWindowTests.swift | Phase 3 | OverlayWindow, AppState |
| PerformanceBenchmarkTests.swift | Phase 5 | CommandParser, CommandDetector, SoundFeedbackService, PowerManagementService |
| ProcessingModeRouterTests.swift | Phase 2 | ProcessingModeRouter, ProcessingMode, LLMService |
| PromptTemplateEngineTests.swift | Phase 2 | PromptTemplateEngine |
| PromptTemplateTests.swift | Phase 2 | PromptTemplate |
| TextInjectionServiceTests.swift | Phase 1 | TextInjectionService, CGEventInjector, ClipboardInjector |
| VocabularyServiceTests.swift | Phase 3 | VocabularyService, VocabularyEntry |
| VoiceActivityDetectorTests.swift | Phase 1 | VoiceActivityDetector |
