# HushType Stability Testing Protocol

## Overview

Protocol for verifying HushType can sustain continuous operation without crashes, resource leaks,
or degraded performance. This document defines repeatable one-hour test scenarios tied to the
actual service lifecycle patterns in the codebase. Each scenario targets a specific failure mode
that arises in long-running menu bar apps, C-bridged inference engines, or real-time audio
pipelines.

Execute the scenarios in the order listed. Record results in the Results Template at the end.
The cumulative test session totals approximately **60–70 minutes** of active runtime.

---

## Environment Setup

### Required Hardware

- **Mac**: Apple Silicon (M1 or newer) — primary target; run Intel Mac as secondary if available
- **RAM**: Minimum 8 GB; 16 GB recommended when testing with large LLM models (7B+)
- **Microphone**: Built-in microphone for baseline tests; USB audio interface for disconnect scenario
- **Storage**: At least 10 GB free for model files and swap space monitoring

### Software

- **macOS**: 14.0+ (Sonoma or later)
- **Xcode**: 16.2
- **Build configuration**: Release (Archive build — Debug adds ARC instrumentation that skews CPU figures)
- **Date tested**: _(fill in during testing)_
- **Tester**: _(fill in during testing)_
- **Build version**: _(fill in during testing)_

### Activity Monitor Setup

Open **Activity Monitor** before starting any scenario:

1. Open **Activity Monitor** (Applications > Utilities > Activity Monitor).
2. Select the **Memory** tab. Locate the `HushType` process row.
3. Select the **CPU** tab in a second Activity Monitor window (Window > CPU Usage) or pin the
   CPU column alongside Memory.
4. Enable **View > All Processes** if HushType does not appear.
5. Pin both **Real Memory** and **CPU %** columns to visible positions.
6. Set the update frequency: **Activity Monitor > View > Update Frequency > Every 2 Seconds**.

### Terminal Monitoring Setup

Open a terminal and run the following `top` command pinned to the HushType process for
continuous sampling throughout the session:

```bash
# Replace <PID> with the actual HushType process ID from Activity Monitor
top -pid $(pgrep HushType) -stats pid,command,cpu,rsize,vsize,threads -d 2
```

For periodic snapshots at key scenario boundaries, use:

```bash
# Snapshot CPU and memory at any moment
ps -o pid,pcpu,rss,vsz,threads -p $(pgrep HushType)
```

For virtual memory pressure:

```bash
# Virtual memory statistics (run before and after each scenario)
vm_stat
```

For GPU and swap:

```bash
# GPU memory pressure (run after model-loading scenarios)
sudo powermetrics --samplers gpu_power -n 1
```

---

## Pre-Test Baseline

Capture the following baseline measurements **before running any scenario**, with HushType
launched and fully idle, no models loaded, settings window closed.

**Steps**:

1. Build a Release configuration:
   ```bash
   xcodebuild -scheme HushType -configuration Release build \
     ONLY_ACTIVE_ARCH=YES
   ```
2. Launch HushType from the build output (not from Xcode — Xcode's debugger inflates memory).
3. Wait **60 seconds** for all launch-time service initialisations to settle
   (`AppDelegate.applicationDidFinishLaunching` completes, `NotificationCenter` observers
   registered, `PowerManagementService` sampling started).
4. Record the following from Activity Monitor:

| Metric | Baseline Value |
|--------|----------------|
| Real Memory (RSS) | _______ MB |
| Virtual Memory (VSZ) | _______ MB |
| CPU % (idle, 10-second average) | _______ % |
| Thread count | _______ |
| Open files (via `lsof -p $(pgrep HushType) | wc -l`) | _______ |

5. Run `vm_stat` and record **Pages free** and **Pages wired down** as numeric baselines.

**Baseline RSS**: _______ MB
**Baseline thread count**: _______

---

## Test Scenarios

---

### Scenario 1: Idle Stability (30 minutes)

**Purpose**: Confirm the app produces no resource drift when completely inactive — no dictation,
no settings window open, no model loaded.

**Source files**: `HushType/App/AppDelegate.swift`, `HushType/Services/PowerManagementService.swift`

**Relevant behaviour**:
```
AppDelegate — battery/thermal observers registered via NotificationCenter
PowerManagementService — polls battery state and thermal pressure on a timer
HotkeyManager — global event monitor running continuously (NSEvent.addGlobalMonitorForEvents)
AppContextService — NSWorkspace.didActivateApplicationNotification observer active
```

**Steps**:

1. Launch HushType with no whisper model and no LLM model selected.
2. Close all HushType windows (settings, overlay).
3. Start a terminal `top` session pinned to HushType.
4. Record the **start RSS** from Activity Monitor.
5. Do nothing for **30 minutes**. Do not interact with the Mac in a way that switches the
   frontmost app more than once per minute (AppContextService fires on every app switch).
6. At the 30-minute mark, record **end RSS** and **CPU % average** over the last 60 seconds.

**Expected**:

- **CPU**: Average < 0.5% over any 5-minute window during the idle period.
- **RSS growth**: Total growth from start RSS to end RSS < 5 MB over 30 minutes.
- **Thread count**: Stable — no new threads created after the initial stabilisation period.
- **No crashes**: HushType process remains alive for the full 30 minutes.
- **Open file descriptors**: Count at end matches count at start (within ±5 for any transient
  system operations).

**Monitor**:

- Activity Monitor: CPU and Real Memory columns, sampled every 2 seconds.
- `top` terminal output: watch `rsize` and `cpu` columns for trends.
- Console.app: filter by `com.hushtype.app` subsystem — any `fault` or `error` level log
  during idle indicates unexpected background activity.

**Pass criteria**:

| Metric | Pass Threshold |
|--------|---------------|
| Peak CPU during idle | < 1.0% instantaneous, < 0.5% average |
| RSS growth over 30 min | < 5 MB |
| Crashes | 0 |
| Error logs (fault/error level) | 0 unexpected entries |

**Result**: [ ] PASS  [ ] FAIL

**Start RSS**: _______ MB  **End RSS**: _______ MB  **Growth**: _______ MB
**Average CPU**: _______ %  **Peak CPU**: _______ %

**Notes**: _(record any anomalies here)_

---

### Scenario 2: Periodic Dictation (30 minutes)

**Purpose**: Confirm the full dictation pipeline can execute repeatedly over 30 minutes without
cumulative memory growth or degraded transcription quality.

**Source files**: `HushType/Services/DictationController.swift`,
                 `HushType/Services/Audio/AudioCaptureService.swift`,
                 `HushType/Services/Speech/WhisperContext.swift`

**Relevant pipeline**:
```
hotkey down  → audioService.startCapture()        // AVAudioEngine tap installed
hotkey up    → audioService.stopCapture()          // tap removed, Float array returned
             → vad.trimSilence(from:sensitivity:)  // in-memory, released after call
             → whisperService.transcribe(samples:) // WhisperContext.queue.async
             → VoicePrefixDetector.detect(in:)     // stateless struct
             → VocabularyService.apply(to:...)      // stateless struct
             → processingRouter.process(...)        // LlamaContext.queue.async (if LLM mode)
             → injectionService.inject(...)         // CGEvent / NSPasteboard (ephemeral)
             → saveDictationEntry(...)              // SwiftData ModelContext (local scope)
             → HistoryCleanupService.runCleanup()   // created fresh, released after
```

**Setup**:
- Load a whisper model (e.g., `ggml-base.en.bin`).
- Set processing mode to **Raw** (no LLM) to isolate the audio/whisper cycle first.
- Open a plain text editor (TextEdit) as the injection target.

**Steps**:

1. Record **start RSS** and **start thread count**.
2. Every **2 minutes**, dictate a 10-second phrase (e.g., "The quick brown fox jumps over the
   lazy dog. Testing one two three. HushType stability test in progress.").
3. Confirm each dictation cycle:
   - DictationState transitions: `idle → recording → transcribing → injecting → idle`
   - Transcribed text appears in TextEdit within 5 seconds of hotkey release.
4. After **15 cycles** (30 minutes), record **end RSS** and **end thread count**.

**Expected**:

- **Each cycle**: Completes within 10 seconds of hotkey release (audio + whisper).
- **No cycle failures**: DictationState never stalls in `transcribing` or `processing`.
- **RSS growth**: Total growth across all 15 cycles < 10 MB.
- **Thread count**: Stable — no accumulation of orphaned `com.hushtype.whisper.context` dispatch
  queue threads.
- **Audio device**: `AVAudioEngine` reports no errors; no `kAudioHardwareUnspecifiedError` in logs.

**Monitor**:

- Activity Monitor: RSS sampled immediately after each cycle completes.
- `lsof -p $(pgrep HushType) | wc -l`: Run after every 5 cycles to confirm no file descriptor leak.
- Console.app: Watch for any `error` or `fault` level entries on `com.hushtype.app` subsystem.

**Pass criteria**:

| Metric | Pass Threshold |
|--------|---------------|
| RSS growth over 15 cycles | < 10 MB total |
| Cycle completion rate | 15/15 (100%) |
| Max single-cycle duration | < 10 s (audio) + whisper inference time |
| Crashed cycles | 0 |
| Thread count growth | 0 net threads added over 15 cycles |

**Result**: [ ] PASS  [ ] FAIL

**Start RSS**: _______ MB  **End RSS**: _______ MB  **Growth**: _______ MB
**Cycles completed**: _______ / 15  **Failed cycles**: _______

**Notes**: _(record any anomalies here)_

---

### Scenario 3: Rapid Start/Stop (10 minutes)

**Purpose**: Confirm that rapidly toggling audio capture does not leak AVAudioEngine taps,
audio buffers, or file descriptors to the audio subsystem.

**Source file**: `HushType/Services/Audio/AudioCaptureService.swift`

**Relevant pattern**:
```swift
// startCapture — installs tap and starts AVAudioEngine
inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
    self?.handleAudioBuffer(buffer)
}
try engine.start()

// stopCapture — removes tap before stopping engine
engine.stop()
engine.inputNode.removeTap(onBus: 0)
```

**Risk**: If `engine.start()` throws after `installTap`, the tap is installed but the engine is
not running. Confirm `removeTap(onBus:)` is called in the error path. With rapid cycling, each
`startCapture` creates a new tap; without the corresponding `removeTap`, multiple taps can
accumulate on the same bus, causing `kAudioUnitErr_TooManyFramesToProcess` or a crash in
`AVAudioInputNode`.

**Steps**:

1. Record **start RSS**, **start thread count**, and `lsof` count.
2. Press and immediately release the dictation hotkey (hold for < 0.5 seconds) to trigger
   audio start/stop without accumulating meaningful audio data.
3. Wait **5 seconds** between each start/stop pair.
4. Repeat for **10 minutes** (approximately 60–100 rapid cycles).
5. Record **end RSS**, **end thread count**, and `lsof` count.

**Expected**:

- **No crash**: HushType survives all rapid cycles.
- **Audio device**: No `AVAudioSessionErrorCode` or `kAudioHardwareError` logs.
- **RSS growth**: < 5 MB over the full scenario.
- **File descriptors**: `lsof` count returns to start value after each stop (within ±2).
- **Tap count**: Only one tap active at any given time (confirmed by absence of
  `kAudioUnitErr_TooManyFramesToProcess` in system log).

**Monitor**:

- Console.app: Filter by process `HushType` — watch for any `AVAudio*` error messages.
- `lsof -p $(pgrep HushType) | grep -i audio | wc -l`: Run every 2 minutes to monitor
  audio-related file descriptor count.
- Activity Monitor: Thread count — should not grow with each cycle.

**Pass criteria**:

| Metric | Pass Threshold |
|--------|---------------|
| Crashes | 0 |
| RSS growth | < 5 MB |
| Audio errors in Console | 0 |
| File descriptor growth (audio) | 0 net growth |
| Thread count growth | 0 net threads |

**Result**: [ ] PASS  [ ] FAIL

**Start RSS**: _______ MB  **End RSS**: _______ MB  **Start FD count**: _______  **End FD count**: _______

**Notes**: _(record any anomalies here)_

---

### Scenario 4: Long Dictation — 5-Minute Continuous Recording

**Purpose**: Verify the audio buffer accumulation, whisper inference on a large sample, and
the minimum-sample padding logic all work correctly for a sustained recording.

**Source files**: `HushType/Services/Audio/AudioCaptureService.swift`,
                 `HushType/Services/Speech/WhisperContext.swift`,
                 `HushType/Services/DictationController.swift`

**Relevant constraint**:
```
Audio padded to minimum 16000 samples (1 second) before whisper.
Whisper requires >= 1s of audio input — shorter recordings are padded with silence.
A 5-minute recording at 16kHz produces 4,800,000 Float32 samples = ~18.3 MB in memory.
The AudioBuffer (os_unfair_lock-protected) holds this in a [Float] array throughout recording.
```

**Steps**:

1. Load a whisper model.
2. Record **start RSS**.
3. Press and hold the dictation hotkey. Begin speaking continuously — read aloud any text
   (e.g., a news article, book passage) for exactly **5 minutes**.
4. Release the hotkey at the 5-minute mark.
5. Observe the DictationState: `transcribing` begins. Wait for it to complete and return to `idle`.
6. Record the **peak RSS** (observed during transcription) and **end RSS** (after return to idle).
7. Verify the transcribed text appears in the injection target — it should reflect approximately
   5 minutes of spoken content (may be truncated at whisper's context limit).

**Expected**:

- **No crash or timeout**: `WhisperContext.transcribe` completes within 3× the audio duration
  (15 minutes maximum for a 5-minute recording on Apple Silicon).
- **Peak RSS increase**: RSS rises by approximately 18–25 MB during transcription (audio buffer
  + whisper internal state), then falls back within 10 MB of start RSS after injection.
- **DictationState**: Transitions cleanly `recording → transcribing → injecting → idle`
  with no stall in `transcribing` for more than 15 minutes.
- **Audio buffer release**: RSS returns toward baseline after `stopCapture()` deallocates
  the internal `[Float]` array.

**Monitor**:

- Activity Monitor: Watch RSS spike during transcription, then confirm descent on completion.
- `top -pid $(pgrep HushType)`: Log the peak `rsize` value during whisper inference.
- Console.app: Any `whisper` category logs reporting segment count or transcription duration.

**Pass criteria**:

| Metric | Pass Threshold |
|--------|---------------|
| Transcription completes | Yes (within 15 min) |
| DictationState stall | None |
| Post-transcription RSS vs start | Within 10 MB |
| Crash | 0 |

**Result**: [ ] PASS  [ ] FAIL

**Start RSS**: _______ MB  **Peak RSS**: _______ MB  **End RSS**: _______ MB
**Transcription wall time**: _______ seconds

**Notes**: _(record any anomalies here)_

---

### Scenario 5: Mode Switching During Active Session (10 minutes)

**Purpose**: Verify that switching processing modes between dictation cycles does not cause
pipeline configuration errors, stale LLM state, or memory accumulation from abandoned
`ProcessingModeRouter` or `PromptTemplateEngine` instances.

**Source files**: `HushType/Services/LLM/LLMService.swift`,
                 `HushType/Services/DictationController.swift` (`processingRouter`)

**Relevant modes** (from `DictationController.processingRouter`):
```
Raw       — no LLM, direct whisper output
Clean     — LLMService with grammar cleanup prompt
Structure — LLMService with formatting prompt
Code      — LLMService with code-specific prompt
Prompt    — LLMService with user-selected PromptTemplate
Custom    — user-defined processing chain
```

**Steps**:

1. Load both a whisper model and an LLM model.
2. Record **start RSS**.
3. Execute the following sequence, dictating a 5-second phrase between each mode switch:
   - Set mode to **Raw** → dictate → confirm raw output appears.
   - Set mode to **Clean** → dictate → confirm LLM-cleaned output appears.
   - Set mode to **Code** → dictate → confirm code-formatted output appears.
   - Set mode to **Structure** → dictate → confirm structured output appears.
   - Set mode to **Raw** → dictate → confirm LLM is bypassed (fast response).
   - Set mode to **Prompt** → select any saved template → dictate → confirm template output.
   - Set mode to **Clean** → dictate → confirm LLM re-engages correctly.
4. Repeat the full 7-step sequence twice (14 dictations total).
5. Record **end RSS** and confirm LLM is still responsive.

**Expected**:

- **Mode transitions**: Each mode switch takes effect on the very next dictation cycle.
  No stale mode state carries over.
- **LLM re-engagement**: After switching from Raw back to Clean, the `LlamaContext` responds
  within normal inference time (no cold-load delay — model should remain in memory).
- **RSS growth**: < 10 MB across 14 cycles including LLM processing.
- **No errors**: `processingRouter.process()` does not throw on any cycle.

**Monitor**:

- Activity Monitor: RSS during LLM inference cycles vs Raw cycles — confirm LLM is not
  accumulating KV-cache across mode switches.
- Console.app: Filter by `com.hushtype.app` `llm` category for any `GenerationResult` errors.

**Pass criteria**:

| Metric | Pass Threshold |
|--------|---------------|
| Mode switches that take effect immediately | 14/14 |
| LLM processing errors | 0 |
| RSS growth across 14 cycles | < 10 MB |
| Crash | 0 |

**Result**: [ ] PASS  [ ] FAIL

**Start RSS**: _______ MB  **End RSS**: _______ MB  **Growth**: _______ MB
**Mode switch failures**: _______

**Notes**: _(record any anomalies here)_

---

### Scenario 6: Model Hot-Swap (5 minutes)

**Purpose**: Verify the whisper pipeline reconfigures cleanly when a different model is selected
mid-session, with no residual C-heap allocations from the previous `whisper_context`.

**Source files**: `HushType/Services/Speech/WhisperContext.swift`,
                 `HushType/Services/DictationController.swift` (`loadWhisperModel`, `unloadWhisperModel`)

**Relevant pattern**:
```swift
// WhisperContext.deinit — called when old context is replaced
queue.sync {
    if let ctx = context {
        whisper_free(ctx)    // C heap freed on dedicated queue
        context = nil
    }
}

// NotificationCenter hot-reload signal
NotificationCenter.default.post(name: .whisperModelDownloaded, object: nil)
// AppDelegate handles this and calls dictationController.loadWhisperModel(url:)
```

**Steps**:

1. Load whisper model **A** (e.g., `ggml-base.en.bin`, ~150 MB).
2. Dictate a phrase and confirm model A is active (check transcription latency — base is faster
   than small).
3. Record **RSS with model A** loaded.
4. Navigate to Settings > Models. Load whisper model **B** (e.g., `ggml-small.en.bin`, ~500 MB).
5. Wait for the `handleModelDownloaded` notification to fire and the new context to initialise.
6. Dictate a phrase and confirm model B is active.
7. Record **RSS with model B** loaded.
8. Switch back to model **A**. Record **RSS after switch back**.
9. Repeat the A → B → A switch **3 more times** (5 total switches).
10. After the final switch, record **final RSS**.

**Expected**:

- **RSS after each unload**: Drops by approximately the size of the unloaded model's memory
  footprint (model A ≈ 150–200 MB, model B ≈ 500–600 MB).
- **No residual whisper_context**: After switching away from model A, no model-A-sized
  anonymous VM regions persist (confirm with `vmmap -resident $(pgrep HushType) | grep -i ggml`).
- **Pipeline reconfiguration**: Each dictation after a switch uses the correct model with
  no `contextNotInitialized` errors.
- **RSS stability**: After 5 switches, RSS with model A loaded should be within 20 MB of
  the first model A reading.

**Monitor**:

```bash
# After each model switch, sample GGML anonymous regions
vmmap -resident $(pgrep HushType) | grep -E "MALLOC|anonymous" | sort -k3 -rn | head -20
```

**Pass criteria**:

| Metric | Pass Threshold |
|--------|---------------|
| Successful model switches | 5/5 |
| whisper_context errors | 0 |
| RSS drift after 5 switches (vs first load) | < 20 MB |
| Crash | 0 |

**Result**: [ ] PASS  [ ] FAIL

**RSS (model A first load)**: _______ MB  **RSS (model B)**: _______ MB
**RSS (after 5 switches, model A)**: _______ MB

**Notes**: _(record any anomalies here)_

---

### Scenario 7: Settings Changes Under Load (5 minutes)

**Purpose**: Verify that modifying settings while a dictation cycle is in progress does not
corrupt shared state, cause a crash, or produce incorrect output.

**Source files**: `HushType/App/AppDelegate.swift` (settings observers),
                 `HushType/Services/DictationController.swift` (configuration properties),
                 `HushType/Views/Settings/` (all tab views)

**Risk**: `AppDelegate` monitors `UserSettings` changes and reconfigures the pipeline
(e.g., changing the hotkey, thread count, or processing mode). If a settings write races
with an in-flight dictation, shared mutable state on `DictationController` may produce
undefined behaviour.

**Steps**:

1. Load a whisper model. Open the Settings window to the **Audio** tab.
2. Begin a dictation (press and hold the hotkey). While still recording:
   - Adjust the **VAD sensitivity** slider.
   - Change the **whisper thread count** spinner.
3. Release the hotkey and allow the transcription to complete. Confirm output appears.
4. While transcription is in progress (`transcribing` state):
   - Navigate to Settings > **Processing** tab.
   - Change the active processing mode.
5. Confirm the dictation completes (using the mode that was active at hotkey-release,
   not the newly selected mode — mode changes should take effect on the next cycle).
6. Open Settings > **General** tab. Change the global hotkey while idle.
7. Confirm the new hotkey triggers dictation correctly.
8. Open Settings > **Models** tab. Unload the LLM model while in **Clean** mode.
9. Trigger a dictation — the pipeline should fall back to **Raw** mode gracefully
   (or display an appropriate error, not crash).

**Expected**:

- **No crash** during any settings change — neither during recording nor transcription.
- **In-flight cycle completes**: Changing settings mid-cycle does not abort or corrupt
  the current dictation.
- **Settings take effect**: Next cycle after each settings change uses the new configuration.
- **Hotkey re-registration**: New hotkey takes effect immediately with no duplicate triggers.
- **LLM unload fallback**: Pipeline degrades gracefully when LLM is removed while a
  mode requiring LLM is selected.

**Pass criteria**:

| Metric | Pass Threshold |
|--------|---------------|
| Crash from concurrent settings write | 0 |
| In-flight cycles corrupted | 0 |
| Hotkey re-registration failures | 0 |
| LLM unload crash | 0 |

**Result**: [ ] PASS  [ ] FAIL

**Notes**: _(record any anomalies here)_

---

### Scenario 8: Recovery from Audio Device Disconnect (5 minutes)

**Purpose**: Verify that unplugging and replugging a microphone during recording does not
crash the app, leave the `AVAudioEngine` in a broken state, or permanently disable dictation.

**Source file**: `HushType/Services/Audio/AudioCaptureService.swift`

**Relevant risk**:
```swift
// AVAudioEngine will post AVAudioEngineConfigurationChange when hardware topology changes.
// If the tap-installed inputNode becomes invalid, subsequent startCapture() attempts
// on the old engine configuration will throw kAudioHardwareNotRunningError.
// AudioCaptureService must handle AVAudioEngineConfigurationChange to re-configure.
```

**Setup**: Connect a USB microphone or headset as the primary audio input device in
System Settings > Sound > Input.

**Steps**:

1. Load a whisper model. Confirm dictation works with the USB device as input.
2. Record **start RSS** and **start thread count**.
3. Begin a dictation (press and hold the hotkey). While recording:
   - **Physically unplug** the USB microphone.
4. Observe the app behaviour:
   - Does HushType crash?
   - Does it display an error, or silently continue recording on the fallback (built-in) mic?
   - Does `DictationState` resolve to `idle` or `error`?
5. Replug the USB microphone.
6. Attempt a new dictation using the rebuilt audio engine. Confirm it completes successfully.
7. Repeat the disconnect/reconnect cycle 3 times to confirm consistent recovery behaviour.

**Expected**:

- **No crash** when the audio device is removed during recording.
- **Graceful error**: `DictationState` transitions to `error("Audio device disconnected")` or
  equivalent; the overlay/menu bar reflects the error state.
- **Automatic or manual recovery**: After replug, the next dictation attempt succeeds (either
  via automatic `AVAudioEngineConfigurationChange` handling, or by the user pressing the hotkey).
- **No orphaned taps**: After recovery, only one tap is installed on the new input node
  (no duplicate tap errors on the second recording attempt).
- **RSS stable**: Disconnect/reconnect does not leak audio subsystem resources.

**Monitor**:

- Console.app: Filter by `AVAudio` for `AVAudioEngineConfigurationChange` and engine error logs.
- `lsof -p $(pgrep HushType) | grep -i audio`: Confirm audio file descriptor count is stable
  after each reconnect.

**Pass criteria**:

| Metric | Pass Threshold |
|--------|---------------|
| Crash on disconnect | 0 |
| Crash on reconnect | 0 |
| Successful dictation after reconnect | 3/3 cycles |
| Orphaned audio taps | 0 |
| RSS growth from disconnect cycles | < 5 MB |

**Result**: [ ] PASS  [ ] FAIL

**Disconnect 1 behaviour**: _(idle/error/crash)_ _______
**Disconnect 2 behaviour**: _______
**Disconnect 3 behaviour**: _______
**RSS growth**: _______ MB

**Notes**: _(record any anomalies here)_

---

## Monitoring Commands Reference

The following commands are referenced across multiple scenarios. Collect all output in a
single log file per test session:

```bash
# --- PID lookup ---
HUSHTYPE_PID=$(pgrep HushType)
echo "HushType PID: $HUSHTYPE_PID"

# --- Continuous CPU and memory via top ---
top -pid $HUSHTYPE_PID -stats pid,command,cpu,rsize,vsize,threads -d 2

# --- Point-in-time snapshot ---
ps -o pid,pcpu,rss,vsz,threads -p $HUSHTYPE_PID

# --- Open file descriptor count ---
lsof -p $HUSHTYPE_PID | wc -l

# --- Audio-related file descriptors only ---
lsof -p $HUSHTYPE_PID | grep -iE "audio|sound|core audio" | wc -l

# --- Virtual memory pressure (run before and after each scenario) ---
vm_stat

# --- GGML memory regions (run after model loads and after model switches) ---
vmmap -resident $HUSHTYPE_PID | grep -E "MALLOC|anonymous" | sort -k3 -rn | head -30

# --- Full virtual map snapshot (save to file for comparison) ---
vmmap $HUSHTYPE_PID > /tmp/hushtype_vmmap_$(date +%H%M%S).txt

# --- Diff two vmmap snapshots to detect new anonymous regions ---
diff /tmp/hushtype_vmmap_before.txt /tmp/hushtype_vmmap_after.txt

# --- Thread count over time ---
while true; do
  ps -M -p $HUSHTYPE_PID | tail -n +2 | wc -l
  sleep 5
done

# --- GPU power during model inference (requires sudo) ---
sudo powermetrics --samplers gpu_power -n 3 -i 1000

# --- Swap usage ---
sysctl vm.swapusage

# --- Thermal state ---
pmset -g thermlog | tail -5
```

---

## Pass Criteria Summary

A full session is considered **passing** when ALL of the following thresholds are met across
all eight scenarios.

| Criterion | Pass Threshold |
|-----------|---------------|
| App crashes (any scenario) | 0 |
| DictationState stalls (any scenario) | 0 |
| RSS growth — idle scenario (30 min) | < 5 MB |
| RSS growth — periodic dictation (15 cycles) | < 10 MB |
| RSS growth — rapid start/stop (~100 cycles) | < 5 MB |
| Peak RSS during long dictation (5 min audio) | Returns within 10 MB of pre-dictation baseline |
| RSS growth — mode switching (14 cycles) | < 10 MB |
| RSS drift after 5 model hot-swaps | < 20 MB vs first load |
| Audio device reconnect success rate | 3/3 |
| Settings changes causing corrupt output | 0 |
| Error logs (fault/error level, unexpected) | 0 over the full session |
| Dictation cycle completion rate | >= 95% (at most 1 failure per scenario) |

**Fail fast rule**: If any scenario produces a crash, stop testing and file a DevTrack bug
task before continuing. Crashes invalidate subsequent scenario results.

---

## Reporting a Failed Scenario

For each scenario that produces a **FAIL** result:

1. Note the exact step number and action that triggered the failure.
2. Capture a Console.app log export filtered to the `com.hushtype.app` subsystem for the
   relevant time window (File > Export).
3. Capture an Activity Monitor screenshot showing the RSS and CPU at the time of failure.
4. If the app crashed, open `~/Library/Logs/DiagnosticReports/` and locate the
   `HushType-*.crash` file. Attach the symbolicated crash log.
5. Record the following:

```
Scenario: <number and name>
Failure step: <step number>
Trigger action: <exact action that caused the failure>
DictationState at failure: <idle/recording/transcribing/processing/injecting/error>
Console error: <paste the relevant log lines>
RSS at failure: <value>
Crash log: <filename, or "no crash">
```

6. File a DevTrack bug task:
   ```bash
   curl -s -X POST "$DEVTRACK_URL/webhooks/task/create" \
     -H "Authorization: Api-Key $DEVTRACK_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{
       "project": "HUSHTYPE",
       "title": "Bug: Stability failure in <Scenario N: name>",
       "description": "Step <N> failed. Trigger: <action>. Console error: <log>. RSS: <value>.",
       "priority": "high"
     }'
   ```

---

## Results Template

Fill in this table after completing all scenarios.

| Scenario | Duration | Status | Start RSS | End RSS | Growth | Crashes | Notes |
|----------|----------|--------|-----------|---------|--------|---------|-------|
| 1. Idle Stability | 30 min | | | | | | |
| 2. Periodic Dictation (15 cycles) | 30 min | | | | | | |
| 3. Rapid Start/Stop (~100 cycles) | 10 min | | | | | | |
| 4. Long Dictation (5 min audio) | 5 min | | | | | | |
| 5. Mode Switching (14 cycles) | 10 min | | | | | | |
| 6. Model Hot-Swap (5 switches) | 5 min | | | | | | |
| 7. Settings Changes Under Load | 5 min | | | | | | |
| 8. Audio Device Disconnect (3x) | 5 min | | | | | | |

**Baseline RSS**: _______ MB
**Final RSS (session end)**: _______ MB
**Total session RSS growth**: _______ MB
**Total crashes across session**: _______

**Overall result**: [ ] ALL PASS  [ ] FAILURES — see individual scenario notes above.

**Tested by**: _______________  **Date**: _______________  **Build**: _______________
