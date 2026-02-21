Last Updated: 2026-02-13

# Troubleshooting Guide

> Solutions for common issues with VaulType installation, permissions, audio, models, text injection, and performance.

## Table of Contents

- [Permission Issues](#permission-issues)
- [Audio Input Problems](#audio-input-problems)
- [Model Loading Failures](#model-loading-failures)
- [Text Injection Not Working](#text-injection-not-working)
- [Performance Issues](#performance-issues)
- [Update Failures](#update-failures)
- [Known Limitations](#known-limitations)
- [Diagnostic Export](#diagnostic-export)
- [Next Steps](#next-steps)

---

## Permission Issues

### Accessibility Permission Denied

VaulType requires Accessibility permission for text injection via CGEvent and for detecting active text fields.

**Symptoms:**
- Text is not injected after dictation
- "Accessibility permission required" alert appears
- Voice commands don't execute

**Solution:**

1. Open **System Settings > Privacy & Security > Accessibility**
2. Find VaulType in the list
3. Toggle it **ON**
4. If VaulType is not in the list, click the **+** button and add it from `/Applications/VaulType.app`

> ⚠️ If you previously denied the permission, you may need to remove and re-add VaulType from the list.

**If the toggle keeps resetting:**

```bash
# Reset Accessibility permissions (requires restart)
tccutil reset Accessibility com.vaultype.app
```

Then relaunch VaulType and grant permission when prompted.

**Enterprise / MDM environments:**

IT administrators can pre-approve Accessibility via MDM profile:

```xml
<key>com.apple.TCC.configuration-profile-policy</key>
<dict>
    <key>Accessibility</key>
    <array>
        <dict>
            <key>Identifier</key>
            <string>com.vaultype.app</string>
            <key>IdentifierType</key>
            <string>bundleID</string>
            <key>Allowed</key>
            <true/>
        </dict>
    </array>
</dict>
```

---

### Microphone Permission Denied

**Symptoms:**
- No audio captured when pressing the hotkey
- Audio level meter shows no activity
- "Microphone access denied" error in logs

**Solution:**

1. Open **System Settings > Privacy & Security > Microphone**
2. Find VaulType and toggle it **ON**

**If VaulType doesn't appear in the list:**

This usually means the app hasn't attempted to access the microphone yet. Launch VaulType and press the dictation hotkey — the permission dialog should appear.

**If the dialog never appears:**

```bash
# Reset Microphone permissions
tccutil reset Microphone com.vaultype.app
```

Relaunch VaulType and try dictating again.

---

### Automation Permission Issues

Required for voice commands that control other apps (AppleScript bridge).

**Symptoms:**
- "Open Safari" command doesn't work
- AppleScript-based commands fail silently

**Solution:**

1. Open **System Settings > Privacy & Security > Automation**
2. Find VaulType and enable permissions for the target apps

---

## Audio Input Problems

### Wrong Audio Input Device

**Symptoms:**
- Dictation captures audio from wrong microphone
- No audio despite microphone working in other apps

**Solution:**

1. Open VaulType **Settings > Audio**
2. Select the correct input device from the dropdown
3. Watch the audio level meter to verify it's receiving signal
4. Speak and confirm the level meter responds

**To check available devices from Terminal:**

```bash
# List audio devices
system_profiler SPAudioDataType
```

---

### No Audio Captured

**Symptoms:**
- Audio level meter shows zero regardless of speaking
- Transcription returns empty text

**Checklist:**

1. **Microphone permission** — Is it granted? (see [Microphone Permission Denied](#microphone-permission-denied))
2. **Correct device** — Is the right input device selected in Settings?
3. **Hardware** — Does the microphone work in other apps (Voice Memos, QuickTime)?
4. **Mute switch** — Some external microphones have physical mute buttons
5. **Sample rate** — VaulType requires 16kHz input. Some USB microphones may need driver updates

**Debug with Console.app:**

1. Open Console.app
2. Filter by process: `VaulType`
3. Filter by category: `audio`
4. Look for error messages related to `AVAudioEngine` or device initialization

---

### Background Noise Issues

**Symptoms:**
- Whisper transcribes background noise as speech
- Random words appear when not speaking

**Solutions:**

1. **Adjust noise gate** — Open Settings > Audio and increase the noise gate threshold
2. **Use a closer microphone** — Headset or desk mic captures less ambient noise
3. **Enable VAD** — Voice Activity Detection trims silence and can filter background noise
4. **Choose a quieter environment** — Whisper works best with clean audio input

---

### Audio Distortion or Clipping

**Symptoms:**
- Transcription is garbled or inaccurate
- Audio level meter hits maximum constantly

**Solutions:**

1. **Reduce input gain** — Lower the microphone input volume in System Settings > Sound
2. **Move away from the microphone** — Speak at a natural distance
3. **Check audio format** — Ensure the device supports 16-bit, 16kHz mono

---

## Model Loading Failures

### Corrupted Model Download

**Symptoms:**
- "Failed to load model" error after download
- App crashes when selecting a model
- Model file size is smaller than expected

**Solution:**

1. Open VaulType **Settings > Models**
2. Delete the corrupted model
3. Re-download it
4. If the problem persists, download manually:

```bash
# Delete corrupted model
rm -f ~/Library/Application\ Support/VaulType/Models/ggml-small.bin

# Re-download (example for Whisper small)
curl -L -o ~/Library/Application\ Support/VaulType/Models/ggml-small.bin \
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"

# Verify file size (should be ~466MB for small)
ls -lh ~/Library/Application\ Support/VaulType/Models/ggml-small.bin
```

---

### Insufficient Memory for Model

**Symptoms:**
- App crashes during model loading
- "Cannot allocate memory" in logs
- macOS shows memory pressure warning

**Model memory requirements:**

| Model | Type | RAM Required |
|-------|------|-------------|
| Whisper tiny | STT | ~120 MB |
| Whisper base | STT | ~200 MB |
| Whisper small | STT | ~480 MB |
| Whisper medium | STT | ~1.5 GB |
| Whisper large-v3 | STT | ~3.0 GB |
| Qwen2.5-3B Q4 | LLM | ~2.0 GB |
| Phi-3.5-mini Q4 | LLM | ~2.5 GB |

**Solutions:**

1. **Use a smaller model** — Switch to Whisper tiny or base if you have limited RAM
2. **Close other apps** — Free up memory before loading larger models
3. **Don't run STT + LLM simultaneously on 8GB Macs** — Use Raw mode to avoid loading the LLM
4. **Check available memory:**

```bash
# Check available memory
vm_stat | head -5
# Or use Activity Monitor > Memory tab
```

> 💡 **Tip:** On 8GB Macs, use Whisper small + Raw mode. On 16GB+, use Whisper small + Qwen2.5-3B for the best balance.

---

### Model Not Found After Update

**Symptoms:**
- Previously downloaded model shows as "Not Downloaded"
- Settings shows empty model list

**Solution:**

Models are stored in `~/Library/Application Support/VaulType/Models/`. If the app can't find them:

```bash
# Check if models exist
ls -la ~/Library/Application\ Support/VaulType/Models/

# If the directory is missing or empty, models need re-download
```

If models exist but aren't detected, the model metadata database may be corrupted:

```bash
# Reset the model database (models stay on disk)
rm ~/Library/Application\ Support/VaulType/VaulType.store
```

Relaunch VaulType — it will re-scan the Models directory.

---

## Text Injection Not Working

### General Injection Failure

**Symptoms:**
- Dictation completes but no text appears at the cursor
- Text appears in the wrong application

**Checklist:**

1. **Accessibility permission** — Is it granted? (Most common cause)
2. **Cursor position** — Is the cursor in an editable text field?
3. **App focus** — Is the target app in the foreground?
4. **Injection method** — Try switching between CGEvent and Clipboard in Settings > Advanced

---

### Specific App Compatibility Issues

#### Terminal.app / iTerm2

**Issue:** Special characters or escape sequences cause unexpected behavior.

**Solution:** Use Clipboard injection method for terminal apps. In Settings > Advanced, set the injection method to "Clipboard" or configure a per-app profile for Terminal.

#### VS Code / Electron Apps

**Issue:** Text injection may be slow or characters may be dropped.

**Solution:**
1. Use Clipboard injection method for Electron apps
2. In Settings > Advanced, increase the keystroke delay for CGEvent injection
3. Some Electron apps have built-in clipboard paste support that works better

#### Sandboxed Apps (App Store apps)

**Issue:** CGEvent injection doesn't work in heavily sandboxed apps.

**Solution:** Use Clipboard injection. VaulType automatically detects sandboxed apps and falls back to clipboard.

#### Browser Text Fields

**Issue:** Rich text editors in browsers (Google Docs, Notion) may not respond to CGEvent.

**Solution:**
1. Use Clipboard injection
2. For Google Docs, ensure the editing cursor is active (not in a menu)
3. For Notion, click into the text block first

---

### Special Characters and Unicode

**Issue:** Accented characters (ü, ö, ñ) or non-Latin scripts don't inject correctly.

**Solution:**
1. Use Clipboard injection method — it handles Unicode correctly
2. Verify your keyboard layout in System Settings > Keyboard
3. CGEvent injection depends on the active keyboard layout — switch to the correct one before dictating

---

## Performance Issues

### Slow Transcription

**Symptoms:**
- Long delay between speaking and text appearing
- Progress indicator spins for >5 seconds on short clips

**Solutions:**

| Action | Expected Impact |
|--------|----------------|
| Use a smaller Whisper model (tiny, base) | 2-5x speedup |
| Ensure Metal GPU is enabled in Settings | 3-10x speedup on Apple Silicon |
| Close GPU-intensive apps (games, video editors) | Free GPU resources |
| Reduce beam size in Settings > Advanced | Faster at slight accuracy cost |
| Use push-to-talk mode (shorter clips) | Less audio to process |

**Check if Metal acceleration is active:**

```bash
# Look for Metal usage in logs
log show --predicate 'process == "VaulType" AND category == "whisper"' --last 5m \
    | grep -i metal
```

---

### High CPU Usage

**Symptoms:**
- VaulType using >10% CPU when idle
- Fan spins up during dictation and doesn't stop

**Solutions:**

1. **Check for runaway inference** — If the LLM gets stuck in a loop, force-quit and relaunch
2. **Disable preloading** — Settings > Advanced > uncheck "Preload models on launch"
3. **Reduce concurrent operations** — Don't dictate while a previous LLM processing is still running

**Debug:**

```bash
# Check VaulType CPU usage
ps aux | grep VaulType

# Sample the process for 5 seconds
sample VaulType 5
```

---

### High Memory Usage

**Symptoms:**
- VaulType using >3 GB RAM
- System becomes sluggish during dictation
- Memory pressure warnings

**Solutions:**

1. **Use smaller models** — See [memory requirements table](#insufficient-memory-for-model)
2. **Unload unused models** — If you're not using LLM processing, the LLM model shouldn't be loaded
3. **Enable memory-efficient mode** — Settings > Advanced > "Unload model after processing"
4. **Restart VaulType** — Some memory may not be freed until restart

---

## Update Failures

### Sparkle Auto-Update Fails

**Symptoms:**
- "An error occurred while checking for updates" message
- Update downloads but fails to install

**Solutions:**

1. **Check network** — Sparkle needs to reach the appcast URL (this is the only network VaulType uses)
2. **Manual update** — Download the latest DMG from [GitHub Releases](https://github.com/vaultype/vaultype/releases)
3. **Permission issue** — Ensure VaulType.app is in `/Applications/` (not a read-only location)
4. **Clear Sparkle cache:**

```bash
rm -rf ~/Library/Caches/com.vaultype.app/
defaults delete com.vaultype.app SULastCheckTime
```

---

### Homebrew Update Fails

```bash
# Update Homebrew and retry
brew update
brew upgrade --cask vaultype

# If that fails, reinstall
brew uninstall --cask vaultype
brew install --cask vaultype
```

---

## Known Limitations

| Limitation | Description | Workaround |
|-----------|-------------|------------|
| No real-time streaming | Text appears after you finish speaking, not word-by-word | Use push-to-talk for shorter segments |
| Intel Mac performance | Whisper and LLM run on CPU only (no Metal) | Use tiny/base models on Intel |
| Sandboxed app injection | Some App Store apps block CGEvent | Use Clipboard injection method |
| macOS < 14 | Not supported | Upgrade to macOS Sonoma or later |
| Multiple displays | Overlay may appear on wrong display | Configure overlay display in Settings |
| Secure input fields | Password fields block injection | By design — security feature |
| Simultaneous STT + LLM | Memory-intensive on 8GB Macs | Use Raw mode on low-memory systems |
| Bluetooth mic latency | Bluetooth adds audio latency | Use wired microphone for best results |

---

## Diagnostic Export

When reporting a bug, export diagnostics to include with your report:

### From the App

1. Open VaulType **Settings > Advanced**
2. Click **Export Diagnostics**
3. Save the `.zip` file and attach to your bug report

### Manual Export

```bash
# Collect logs from the last hour
log show --predicate 'process == "VaulType"' --last 1h > ~/Desktop/vaultype-logs.txt

# Collect system info
system_profiler SPHardwareDataType SPSoftwareDataType > ~/Desktop/vaultype-system.txt

# Check model files
ls -la ~/Library/Application\ Support/VaulType/Models/ >> ~/Desktop/vaultype-system.txt

# Check permissions
tccutil list com.vaultype.app 2>&1 >> ~/Desktop/vaultype-system.txt

# Package
zip ~/Desktop/vaultype-diagnostics.zip \
    ~/Desktop/vaultype-logs.txt \
    ~/Desktop/vaultype-system.txt
```

### What to Include in Bug Reports

1. **VaulType version** (Settings > About or menu bar > About VaulType)
2. **macOS version** (Apple menu >  About This Mac)
3. **Mac model** (Apple Silicon or Intel, RAM amount)
4. **Whisper model** in use
5. **LLM model** in use (if applicable)
6. **Steps to reproduce** the issue
7. **Expected vs actual behavior**
8. **Diagnostic export** (see above)
9. **Screenshots** if it's a UI issue

---

## Next Steps

- [Monitoring & Logging](MONITORING_LOGGING.md) — Detailed logging and diagnostics
- [Permissions Guide](../features/PERMISSIONS.md) — macOS permissions deep dive
- [Performance Optimization](../reference/PERFORMANCE_OPTIMIZATION.md) — Tuning for speed
- [FAQ](../reference/FAQ.md) — Frequently asked questions
- [Report a Bug](https://github.com/vaultype/vaultype/issues/new?template=bug_report.md) — File an issue on GitHub
