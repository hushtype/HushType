# VaulType Memory Leak Testing Protocol

## Overview

Protocol for verifying VaulType has no memory leaks using Xcode Instruments. This document
defines repeatable test scenarios tied to the actual C bridging and service lifecycle patterns
in the codebase. Execute each scenario manually and record results in the Summary table.

---

## Test Environment

- **macOS**: 14.0+
- **Xcode**: 16.2
- **Instruments templates**: Leaks, Allocations, VM Tracker
- **Build configuration**: Release (Archive build — Debug adds ARC instrumentation overhead)
- **Date tested**: _(fill in during testing)_
- **Tester**: _(fill in during testing)_

---

## Pre-Test Setup

1. Build a **Release** configuration archive:
   ```bash
   xcodebuild -scheme VaulType -configuration Release build \
     ONLY_ACTIVE_ARCH=YES
   ```
2. Open **Instruments** (Xcode > Open Developer Tool > Instruments).
3. Choose the **Leaks** template (includes both Leaks and Allocations instruments).
4. Set the target to the VaulType.app built above.
5. In the Allocations instrument, enable **"Record reference counts"** to capture retain/release
   call stacks.
6. Launch the app and wait for it to fully initialise before starting any scenario.
7. Record a **baseline memory reading** (VM Tracker > Physical Footprint) after the app has
   been idle for 10 seconds with no model loaded.

**Baseline memory**: _______ MB

---

## Test Scenarios

---

### Scenario 1: WhisperContext Init/Deinit Cycle

**Source file**: `VaulType/Services/Speech/WhisperContext.swift`

**Relevant pattern**:
```swift
// init — allocates C context via whisper_init_from_file_with_params
let params = whisper_context_default_params()
guard let ctx = whisper_init_from_file_with_params(modelPath, params) else { ... }
self.context = ctx

// deinit — synchronises on dedicated queue before calling whisper_free
queue.sync {
    if let ctx = context {
        whisper_free(ctx)
        context = nil
    }
}

// explicit unload (same teardown path as deinit)
func unload() {
    queue.sync {
        if let ctx = context {
            whisper_free(ctx)
            context = nil
        }
    }
}
```

**Risk**: If a `transcribe()` async continuation is still executing on
`com.vaultype.whisper.context` when `deinit` fires, the `queue.sync` inside `deinit`
will block until the in-flight closure completes. If this sequence is disrupted (e.g., a
crash or task cancellation), `whisper_free` may not be called.

**Steps**:
1. Navigate to Settings > Models and load a whisper model.
2. Transcribe a short phrase to confirm the model is active.
3. Navigate to Settings > Models and **unload** the model.
4. Repeat steps 1–3 ten times without restarting the app.

**Expected**:
- No `whisper_context` allocations remain after each unload.
- Memory returns to within 5 MB of baseline after each unload cycle.
- Instruments Leaks instrument shows zero leaks during the cycle.

**Monitor**:
- Leaks instrument — watch for leaked `whisper_context` heap blocks.
- Allocations instrument — filter by "whisper" to isolate C allocations.
- VM Tracker — Physical Footprint should trend flat across cycles.

**Result**: [ ] PASS  [ ] FAIL

**Notes**: _(record any Instruments findings here)_

---

### Scenario 2: LlamaContext Init/Deinit Cycle

**Source file**: `VaulType/Services/LLM/LlamaContext.swift`

**Relevant pattern**:
```swift
// init — allocates THREE C objects: model, context, sampler
llama_backend_init()                                    // global backend
self.model   = llama_model_load_from_file(...)
self.context = llama_init_from_model(loadedModel, ...)
self.sampler = llama_sampler_chain_init(...)
llama_sampler_chain_add(chain, llama_sampler_init_greedy())

// deinit — frees all three in reverse order on dedicated queue
queue.sync {
    if let smpl = sampler  { llama_sampler_free(smpl);  sampler  = nil }
    if let ctx  = context  { llama_free(ctx);            context  = nil }
    if let mdl  = model    { llama_model_free(mdl);      model    = nil }
    llama_backend_free()
}

// llama_batch is managed per-generation with defer { llama_batch_free(batch) }
var batch = llama_batch_init(...)
defer { llama_batch_free(batch) }
```

**Risk**: `LlamaContext` manages three independent C heap objects (`llama_model`,
`llama_context`, `llama_sampler`) plus a per-generation `llama_batch`. A partial failure
during `init` (e.g., `llama_init_from_model` returns nil) does call `llama_model_free`
before throwing, which is correct. Confirm that no double-free or missed-free occurs on
the sampler path when an early `init` error occurs.

**Steps**:
1. Navigate to Settings > Models and load an LLM model (GGUF format).
2. Dictate a phrase in **Clean** or **Structure** mode to trigger LLM processing.
3. Navigate to Settings > Models and **unload** the LLM model.
4. Repeat steps 1–3 ten times.

**Expected**:
- No `llama_model`, `llama_context`, or `llama_sampler` allocations persist after unload.
- Memory returns to within 5 MB of baseline after each unload cycle.
- `llama_backend_free` is paired with every `llama_backend_init`.

**Monitor**:
- Leaks instrument — filter by "llama".
- Allocations — filter by "llama" and "ggml" (shared tensor memory).
- VM Tracker — watch for anonymous VM regions that grow without shrinking.

**Result**: [ ] PASS  [ ] FAIL

**Notes**: _(record any Instruments findings here)_

---

### Scenario 3: AudioCaptureService Start/Stop

**Source file**: `VaulType/Services/Audio/AudioCaptureService.swift`

**Relevant pattern**:
```swift
// startCapture — installs tap and starts AVAudioEngine
inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] (buffer, time) in
    self?.handleAudioBuffer(buffer)
}
try engine.start()

// stopCapture — removes tap and stops engine
engine.stop()
engine.inputNode.removeTap(onBus: 0)

// AVAudioConverter is created only when sample-rate conversion is needed
// and stored as self.converter (an Optional — not explicitly freed)
self.converter = nil   // set to nil on next startCapture when no conversion needed
```

**Risk**: The `AVAudioConverter` is nulled out conditionally. If the hardware sample rate
changes between stop/start cycles (e.g., plugging in a USB interface), the previous
converter may not be released before a new one is allocated. The `[weak self]` in the
tap closure prevents the common retain-cycle pattern, but confirm no strong references
escape via the `AVAudioConverter` `inputBlock` closure in `convertBuffer`.

**Steps**:
1. Press and hold the dictation hotkey to start audio capture.
2. Release the hotkey to stop capture (do not transcribe — cancel quickly).
3. Repeat 20 times.

**Expected**:
- No `AVAudioEngine` node allocations survive beyond each stop cycle.
- No `AVAudioPCMBuffer` objects remain after `stopCapture` returns.
- `AudioBuffer` internal array (`os_unfair_lock`-protected) is reset on each `startCapture`.

**Monitor**:
- Allocations — filter by "AVAudio" and "AudioBuffer".
- VM Tracker — confirm audio I/O buffers (IOKit category) are released.

**Result**: [ ] PASS  [ ] FAIL

**Notes**: _(record any Instruments findings here)_

---

### Scenario 4: Repeated Full Dictation Cycles

**Source file**: `VaulType/Services/DictationController.swift`

**Relevant pipeline**:
```
hotkey down
  → audioService.startCapture()           // AVAudioEngine tap installed
hotkey up
  → audioService.stopCapture()            // tap removed, samples returned
  → vad.trimSilence(from:sensitivity:)    // in-memory Float array, released after
  → whisperService.transcribe(samples:)   // WhisperContext.queue.async closure
  → VoicePrefixDetector.detect(in:)       // stateless struct
  → VocabularyService.apply(to:...)       // stateless struct
  → CommandDetector.detect(in:...)        // stateless struct
  → processingRouter.process(...)         // LlamaContext.queue.async closure
  → injectionService.inject(...)          // CGEvent / NSPasteboard (ephemeral)
  → saveDictationEntry(...)               // SwiftData ModelContext (local scope)
  → HistoryCleanupService.runCleanup()    // created fresh, released after
```

**Steps**:
1. Ensure both whisper and LLM models are loaded.
2. Dictate a 3–5 word phrase and allow the full pipeline to complete (inject into a text field).
3. Repeat 50 times in succession, pausing 2 seconds between each cycle.

**Expected**:
- Total memory growth across 50 cycles is less than 10 MB.
- No persistent leaks reported by Instruments Leaks instrument.
- `DictationEntry` SwiftData objects saved and cleaned up within retention limits.
- `HistoryCleanupService` instances (created per-save) are deallocated immediately.
- No `ModelContext` objects linger after `saveDictationEntry` returns.

**Monitor**:
- Leaks instrument — run continuously for the full 50-cycle sequence.
- Allocations — "Generation Analysis" across cycles to spot accumulation.
- VM Tracker — track total physical footprint trend line.

**Result**: [ ] PASS  [ ] FAIL

**Notes**: _(record any Instruments findings here)_

---

### Scenario 5: Settings Window Open/Close

**Relevant files**: `VaulType/Views/Settings/` (all tab views)

**Risk areas**:
- SwiftUI `@Observable` observation tracking closures — confirm no strong self-captures
  that prevent view deallocation on close.
- Settings has 10 tabs: General, Audio, Models, Processing, App Profiles, Vocabulary,
  Language, History, Commands, Plugins. Each tab may retain service references via
  `@Environment` or direct `init` parameters.
- `PluginManagerView` holds a reference to `PluginManager` — confirm it releases on close.

**Steps**:
1. Click the VaulType menu bar icon to open the menu.
2. Click **Settings** to open the settings window.
3. Click through all 10 tabs (General → Audio → Models → Processing → App Profiles →
   Vocabulary → Language → History → Commands → Plugins).
4. Close the settings window.
5. Repeat steps 2–4 ten times.

**Expected**:
- No SwiftUI view objects (SettingsView, tab views) persist in the Allocations graph
  after the window is closed.
- `@Observable` tracking closures registered within tab views are released.
- Memory returns to within 2 MB of the pre-open baseline after each close.

**Monitor**:
- Allocations — filter by "View" and "Settings" after each close.
- Leaks — watch specifically for `__NSObservationRegistrar` retain cycles.

**Result**: [ ] PASS  [ ] FAIL

**Notes**: _(record any Instruments findings here)_

---

### Scenario 6: Model Switching (Whisper)

**Source file**: `VaulType/Services/Speech/WhisperContext.swift`,
                `VaulType/Services/DictationController.swift` (`loadWhisperModel`, `unloadWhisperModel`)

**Relevant pattern**:
```swift
// WhisperService wraps WhisperContext — loading replaces the current context
func loadModel(at url: URL) async throws {
    // The existing WhisperContext (if any) must be released before the new one
    // is created. Confirm the old OpaquePointer is freed before assigning new.
}

// DictationController exposes explicit unload for power management
func unloadWhisperModel() {
    whisperService.unloadModel()
}
```

**Steps**:
1. Load whisper model **A** (e.g., `ggml-base.en.bin`) via Settings > Models.
2. Transcribe a phrase to confirm model A is active.
3. Load whisper model **B** (e.g., `ggml-small.en.bin`) — this should unload model A first.
4. Transcribe a phrase to confirm model B is active.
5. Repeat the A → B → A switch 5 times.

**Expected**:
- After each model switch, the memory footprint of the previous model (typically 150–500 MB
  depending on model size) is fully released.
- No residual `whisper_context` or GGML tensor allocations remain from the previous model.
- Memory stabilises at the footprint of the currently loaded model within 5 seconds of switch.

**Monitor**:
- VM Tracker — watch anonymous VM regions drop when the old model is freed.
- Allocations — filter by "ggml" to confirm tensor buffers are released.
- Memory gauge in Instruments toolbar for coarse-grained footprint tracking.

**Result**: [ ] PASS  [ ] FAIL

**Notes**: _(record any Instruments findings here)_

---

### Scenario 7: Model Switching (LLM)

**Source file**: `VaulType/Services/LLM/LlamaContext.swift`,
                `VaulType/Services/DictationController.swift` (`loadLLMModel`, `unloadLLMModel`)

**Relevant pattern**:
```swift
// deinit frees three objects in reverse-allocation order:
// sampler → context → model → backend
// Switching models must ensure all three are freed before the new model loads.
```

**Steps**:
1. Load LLM model **A** and process a phrase in Clean mode.
2. Navigate to Settings > Models and switch to LLM model **B**.
3. Process a phrase in Clean mode to confirm model B is active.
4. Repeat the A → B → A switch 5 times.

**Expected**:
- `llama_sampler`, `llama_context`, and `llama_model` for the old model are all freed
  before the new model's allocations appear in Instruments.
- `llama_backend_free` / `llama_backend_init` are balanced across all switches.
- LLM memory footprint (typically 1–8 GB depending on model) is fully recovered on each switch.

**Monitor**:
- VM Tracker — anonymous VM regions should drop sharply after each model switch.
- Allocations — filter "llama" and "ggml" for residual blocks.
- Process memory gauge — expect a clear sawtooth pattern (up on load, down on unload).

**Result**: [ ] PASS  [ ] FAIL

**Notes**: _(record any Instruments findings here)_

---

## Known Risk Areas

The following areas represent the highest-probability sources of leaks and should receive
extra attention in Instruments if any scenario fails.

| Risk | Location | Detail |
|------|----------|--------|
| `whisper_free` not called | `WhisperContext.deinit` | If `queue.sync` deadlocks (e.g., queue already suspended), the C context leaks. |
| `llama_model_free` partial init | `LlamaContext.init` | If `llama_init_from_model` fails, `llama_model_free` IS called. Verify in practice. |
| `llama_sampler` orphan | `LlamaContext.deinit` | Sampler must be freed before context — reversed order causes UB in llama.cpp. |
| `llama_backend_free` imbalance | `LlamaContext.deinit` | Called once per `deinit`; if multiple `LlamaContext` instances exist simultaneously, `llama_backend_free` may be called too many times. |
| `AVAudioConverter` retained | `AudioCaptureService` | `self.converter` is an Optional that is nilled when conversion is not needed — confirm it is always nil'd before a new converter is assigned. |
| Tap not removed on error | `AudioCaptureService._startCapture` | If `engine.start()` throws after `installTap`, the tap is installed but the engine never starts. Confirm `removeTap` is called in the error path. |
| `os_unfair_lock` deadlock | `AudioBuffer` | If a lock is held when the object is deallocated, subsequent lock acquisition from a background thread will hang. |
| NotificationCenter observers | `AppDelegate` | `NSWorkspace` and `NotificationCenter` observers must be removed in `applicationWillTerminate` or use block-based APIs with weak self. |
| `OverlayWindow` retain cycle | `VaulType/Views/Overlay/` | `NSPanel` subclass references `appState` — confirm it does not form a reference cycle with `DictationController`. |
| `ModelContext` per-save | `DictationController.saveDictationEntry` | A new `ModelContext(container)` is created on every save; confirm it is released after the save/fetch completes and does not accumulate. |
| `HistoryCleanupService` per-save | `DictationController.saveDictationEntry` | Created fresh inside the async closure; confirm no strong capture keeps it alive after `runCleanup()` returns. |
| SwiftUI observation closures | All `@Observable` views | `withObservationTracking` blocks can hold strong references if the `onChange` closure captures `self` strongly. |

---

## Reporting Failed Scenarios

For each scenario that produces a **FAIL** result:

1. In Instruments, click the red leak indicator to open the **Leak Detail** panel.
2. Select the leaked allocation and expand the **Backtrace** column.
3. Identify the allocation site (look for VaulType frames, ignoring system frames).
4. Export a screenshot of the Leaks instrument timeline showing the leak moment.
5. File the following information:

```
Scenario: <number and name>
Leaked type: <class or C struct name>
Allocation backtrace:
  <paste Instruments backtrace here>
Proposed fix:
  <description of the missing free / retain cycle break>
```

6. Create a DevTrack bug task:
   ```bash
   curl -s -X POST "$DEVTRACK_URL/webhooks/task/create" \
     -H "Authorization: Api-Key $DEVTRACK_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{
       "project": "VAULTYPE",
       "title": "Bug: Memory leak in <component>",
       "description": "Scenario <N> failed. Leaked type: <type>. Backtrace: ...",
       "priority": "high"
     }'
   ```

---

## Summary

Fill in this table after completing all scenarios. Acceptable thresholds: Memory Growth
< 10 MB across the full scenario, Leaks = 0.

| Scenario | Status | Memory Growth | Leaks Reported | Notes |
|----------|--------|---------------|----------------|-------|
| 1. WhisperContext Init/Deinit | | | | |
| 2. LlamaContext Init/Deinit | | | | |
| 3. AudioCaptureService Start/Stop | | | | |
| 4. Full Dictation Cycles (50x) | | | | |
| 5. Settings Window Open/Close | | | | |
| 6. Whisper Model Switching | | | | |
| 7. LLM Model Switching | | | | |

**Overall result**: [ ] ALL PASS  [ ] FAILURES — see individual scenario notes above.

**Tested by**: _______________  **Date**: _______________  **Build**: _______________
