Last Updated: 2026-02-13

# Quick Start Guide

> **VaulType** — Privacy-first, macOS-native speech-to-text. Your voice stays on your device. Always.
> Go from zero to working dictation in under 5 minutes.

---

## Table of Contents

- [1. TL;DR — Build and Run](#1-tldr--build-and-run)
- [2. Pre-Built Binary Installation](#2-pre-built-binary-installation)
  - [2.1 Homebrew Cask (Recommended)](#21-homebrew-cask-recommended)
  - [2.2 DMG Download](#22-dmg-download)
- [3. First-Time Setup Walkthrough](#3-first-time-setup-walkthrough)
  - [3.1 What Happens on First Launch](#31-what-happens-on-first-launch)
  - [3.2 Setup Wizard Flow](#32-setup-wizard-flow)
- [4. Granting Permissions](#4-granting-permissions)
  - [4.1 Accessibility Permission](#41-accessibility-permission)
  - [4.2 Microphone Permission](#42-microphone-permission)
  - [4.3 Verifying Permissions](#43-verifying-permissions)
- [5. Downloading Your First Whisper Model](#5-downloading-your-first-whisper-model)
  - [5.1 Using the Built-In Model Manager](#51-using-the-built-in-model-manager)
  - [5.2 Recommended Models](#52-recommended-models)
  - [5.3 Model Storage Location](#53-model-storage-location)
- [6. Testing Dictation in TextEdit](#6-testing-dictation-in-textEdit)
  - [6.1 Complete Test Flow](#61-complete-test-flow)
  - [6.2 Expected Behavior](#62-expected-behavior)
  - [6.3 Troubleshooting First Dictation](#63-troubleshooting-first-dictation)
- [7. Next Steps](#7-next-steps)
- [Related Documentation](#related-documentation)

---

## 1. TL;DR -- Build and Run

For developers who want to clone, build, and run VaulType from source in the fewest steps possible:

```bash
# 1. Clone the repository
git clone https://github.com/vaultype/vaultype.git

# 2. Navigate into the project directory
cd vaultype

# 3. Initialize and fetch submodules (whisper.cpp, llama.cpp)
git submodule update --init --recursive

# 4. Build the C/C++ dependencies
make deps

# 5. Open the Xcode project and build
open VaulType.xcodeproj

# 6. Or build from the command line and run
xcodebuild -scheme VaulType -configuration Debug build
```

**Prerequisites for building from source:**

| Requirement | Minimum Version | How to Check |
|-------------|----------------|--------------|
| macOS | 14 Sonoma | Apple menu > About This Mac |
| Xcode | 15.0+ | `xcodebuild -version` |
| CMake | 3.21+ | `cmake --version` |
| Git | 2.39+ | `git --version` |
| Disk space | ~5 GB | For build artifacts, submodules, and models |

If you do not have CMake installed, you can install it via Homebrew:

```bash
brew install cmake
```

> :bulb: **Tip:** If you just want to use VaulType without building from source, skip to [Section 2](#2-pre-built-binary-installation) for pre-built binaries — no development tools required.

> :warning: **Apple Silicon recommended.** VaulType uses Metal GPU acceleration for ML inference. It runs on Intel Macs but with significantly reduced performance. See [TECH_STACK.md](../architecture/TECH_STACK.md) for the full compatibility matrix.

For the complete development environment setup, build configuration details, and contribution workflow, see the [Development Guide](DEVELOPMENT_GUIDE.md).

---

## 2. Pre-Built Binary Installation

### 2.1 Homebrew Cask (Recommended)

The fastest way to install VaulType is via Homebrew:

```bash
brew install --cask vaultype
```

That is it. Homebrew handles downloading, verification, and placing VaulType in your `/Applications` folder.

To update later:

```bash
brew upgrade --cask vaultype
```

To uninstall:

```bash
brew uninstall --cask vaultype
```

> :information_source: **Info:** The Homebrew Cask formula is maintained alongside releases. It always points to the latest stable version distributed via GitHub Releases.

### 2.2 DMG Download

If you prefer a manual installation:

1. Go to the [VaulType GitHub Releases](https://github.com/vaultype/vaultype/releases) page.
2. Download the latest `VaulType-x.y.z.dmg` file.
3. Open the DMG and drag **VaulType.app** into your **Applications** folder.
4. Eject the DMG.

> :lock: **Security:** The DMG is code-signed with a valid Apple Developer ID certificate and notarized by Apple. If macOS shows a warning, right-click the app and select **Open** to bypass Gatekeeper on first launch.

> :warning: **Important:** Do not run VaulType directly from the DMG. Always copy it to `/Applications` first — running from a mounted disk image can cause permission issues and prevents auto-updates from working correctly.

---

## 3. First-Time Setup Walkthrough

### 3.1 What Happens on First Launch

When you open VaulType for the first time, the following occurs:

1. **Menu bar icon appears** — VaulType is a menu bar application. You will see the VaulType icon (a microphone glyph) in the macOS menu bar, near the clock.
2. **Setup wizard opens** — A guided setup window walks you through the essential configuration steps.
3. **No data leaves your Mac** — VaulType has zero network dependencies at runtime. The setup wizard runs entirely locally.

> :apple: **macOS Behavior:** Because VaulType is a menu bar app, it does not appear in the Dock by default. You interact with it through the menu bar icon and keyboard shortcuts.

### 3.2 Setup Wizard Flow

The setup wizard guides you through four steps, each clearly numbered in the UI:

| Step | Action | Required? |
|------|--------|-----------|
| **Step 1** | Grant Accessibility permission | Yes |
| **Step 2** | Grant Microphone permission | Yes |
| **Step 3** | Download a Whisper speech-to-text model | Yes |
| **Step 4** | Configure your global hotkey | Optional (default: `Option + Space`) |

Each step includes a status indicator:

- :white_check_mark: **Green checkmark** — Step completed successfully
- :warning: **Yellow warning** — Action needed, the wizard provides guidance
- :x: **Red X** — Permission denied or error, manual intervention required

You can revisit the setup wizard at any time from the menu bar:

**Menu Bar Icon** > **Settings...** > **Setup Wizard**

> :information_source: **Info:** The wizard only appears automatically on first launch. After all steps are completed, VaulType remembers your configuration across launches using local `UserDefaults` and `SwiftData` storage.

---

## 4. Granting Permissions

VaulType requires two macOS system permissions to function. Both are standard privacy permissions managed by Apple's TCC (Transparency, Consent, and Control) framework. No data is sent anywhere — these permissions enable local-only functionality.

For the complete permissions reference, including enterprise MDM pre-approval and troubleshooting, see [Permissions Guide](../features/PERMISSIONS.md).

### 4.1 Accessibility Permission

**Why it is needed:** VaulType uses the macOS Accessibility API (via `CGEvent`) to simulate keystrokes and inject transcribed text into the active application. Without this permission, VaulType cannot type text for you.

**How to grant it:**

1. When the setup wizard prompts for Accessibility, click **Open System Settings**.
   - This opens directly to the correct pane.
2. Alternatively, navigate manually:
   - **System Settings** > **Privacy & Security** > **Accessibility**
3. Click the lock icon (:lock:) at the bottom-left and authenticate with your password or Touch ID.
4. Click the **+** button.
5. Navigate to **Applications** > select **VaulType.app** > click **Open**.
6. Ensure the toggle next to VaulType is **ON**.
7. Return to VaulType — the wizard will detect the permission automatically.

<!-- Screenshot placeholder: System Settings > Privacy & Security > Accessibility with VaulType toggled on -->
> :bulb: **Screenshot:** `[accessibility-permission-granted.png]` — System Settings showing VaulType enabled under Accessibility.

> :warning: **Restart required after rebuilds:** If you build VaulType from source, the code signature changes with each build. macOS ties Accessibility permissions to the code signature, so you must **re-grant** Accessibility permission after every rebuild. This does not apply to pre-built releases. See [Permissions Guide](../features/PERMISSIONS.md) for details.

### 4.2 Microphone Permission

**Why it is needed:** VaulType captures audio from your microphone to transcribe your speech. All audio processing happens locally via whisper.cpp — no audio data is ever transmitted over the network.

**How to grant it:**

1. When the setup wizard prompts for Microphone access, click **Request Permission**.
   - macOS shows a standard system dialog: _"VaulType would like to access the microphone."_
2. Click **OK** to grant permission.
3. If you accidentally click **Don't Allow**, you must grant it manually:
   - **System Settings** > **Privacy & Security** > **Microphone**
   - Find **VaulType** in the list and toggle it **ON**.

<!-- Screenshot placeholder: macOS microphone permission dialog for VaulType -->
> :bulb: **Screenshot:** `[microphone-permission-dialog.png]` — macOS system dialog requesting microphone access for VaulType.

> :lock: **Privacy guarantee:** VaulType only activates the microphone when you press the dictation hotkey. The menu bar icon changes to indicate active recording. Audio is buffered in memory, processed by whisper.cpp, and immediately discarded — nothing is written to disk.

### 4.3 Verifying Permissions

After granting both permissions, the setup wizard shows green checkmarks for Steps 1 and 2. You can also verify at any time:

**Menu Bar Icon** > **Settings...** > **Permissions**

This panel shows the live status of each permission:

| Permission | Status | What It Means |
|------------|--------|---------------|
| Accessibility | :white_check_mark: Granted | Text injection is fully functional |
| Microphone | :white_check_mark: Granted | Audio capture is available |
| Accessibility | :x: Denied | VaulType cannot type text — click to open System Settings |
| Microphone | :x: Denied | VaulType cannot hear you — click to open System Settings |

> :information_source: **Info:** If either permission is revoked while VaulType is running, the app detects the change and displays a non-intrusive notification guiding you to re-enable it. VaulType gracefully degrades — it never crashes due to missing permissions.

---

## 5. Downloading Your First Whisper Model

VaulType does not bundle a speech-to-text model in the app download to keep the initial install small. You need to download at least one Whisper model before you can start dictating.

### 5.1 Using the Built-In Model Manager

1. After granting permissions, the setup wizard advances to **Step 3: Download Model**.
2. The Model Manager displays a list of available Whisper models with:
   - Model name and size (e.g., `whisper-base` — 142 MB)
   - Expected accuracy level (Good / Better / Best)
   - Estimated download time on your connection
   - Hardware recommendation (Apple Silicon vs Intel)
3. Select a model and click **Download**.
4. A progress bar shows download status with percentage and estimated time remaining.
5. After download completes, the model is verified via SHA256 checksum.
6. The status indicator changes to :white_check_mark: and the model is ready to use.

> :information_source: **Info:** Downloads are resumable. If your connection drops, re-open the Model Manager and click **Resume** — the download continues where it left off. See [Model Management](../features/MODEL_MANAGEMENT.md) for full details.

You can access the Model Manager at any time:

**Menu Bar Icon** > **Settings...** > **Models**

### 5.2 Recommended Models

For your first model, we recommend starting with **whisper-base**:

| Model | Size | RAM Usage | Speed (Apple Silicon) | Accuracy | Best For |
|-------|------|-----------|----------------------|----------|----------|
| `whisper-tiny` | 75 MB | ~390 MB | ~10x real-time | Fair | Quick testing, low-RAM machines |
| **`whisper-base`** | **142 MB** | **~500 MB** | **~7x real-time** | **Good** | **Recommended starting point** |
| `whisper-small` | 466 MB | ~1.0 GB | ~4x real-time | Better | Daily use with good hardware |
| `whisper-medium` | 1.5 GB | ~2.6 GB | ~2x real-time | Great | Professional use, high accuracy |
| `whisper-large-v3` | 3.1 GB | ~4.8 GB | ~1x real-time | Best | Maximum accuracy, 16 GB+ RAM |

> :bulb: **Tip: Start with `whisper-base`.** It provides a great balance of speed and accuracy for most users and downloads quickly. You can always download a larger model later from the Model Manager.

> :warning: **Intel Mac users:** Stick with `whisper-tiny` or `whisper-base`. Without Metal GPU acceleration, larger models may run slower than real-time, making dictation impractical. See [Speech Recognition](../features/SPEECH_RECOGNITION.md) for Intel-specific tuning.

### 5.3 Model Storage Location

Downloaded models are stored locally at:

```
~/Library/Application Support/VaulType/Models/whisper/
```

You can view storage usage and manage models from **Settings... > Models**. Models can be deleted individually to reclaim disk space. For advanced model management including LLM models for text post-processing, see [Model Management](../features/MODEL_MANAGEMENT.md).

---

## 6. Testing Dictation in TextEdit

You have installed VaulType, granted permissions, and downloaded a model. Time to test it.

### 6.1 Complete Test Flow

Follow these steps to verify everything is working:

1. **Open TextEdit**
   - Press `Cmd + Space` to open Spotlight, type `TextEdit`, and press Enter.
   - Make sure you have a new, empty document open and the cursor is active in the text area.

2. **Check VaulType status**
   - Look at the menu bar — the VaulType icon should be visible.
   - Click the icon to verify the status shows **Ready** (not "No model loaded" or "Permission missing").

3. **Press the dictation hotkey**
   - Press `Option + Space` (the default hotkey).
   - The menu bar icon changes to indicate **Recording** (the microphone glyph becomes active/colored).
   - You may also see a small floating indicator near the cursor.

4. **Speak clearly into your microphone**
   - Say something like: _"Hello, this is a test of VaulType dictation."_
   - Speak at a normal pace and volume, as you would in a conversation.

5. **Stop recording**
   - Press `Option + Space` again to stop recording.
   - Alternatively, pause speaking for a few seconds — VaulType's Voice Activity Detection (VAD) can automatically stop recording after silence is detected (configurable in Settings).

6. **See transcribed text appear**
   - VaulType processes the audio locally using whisper.cpp.
   - The transcribed text is injected into TextEdit at the cursor position.
   - You should see your spoken words appear as typed text.

> :white_check_mark: **Success!** If text appeared in TextEdit, VaulType is fully operational. You can now use it in any application — text editors, browsers, email clients, Slack, terminal emulators, and more.

### 6.2 Expected Behavior

During the dictation flow, here is what you should observe:

| Phase | Menu Bar Icon | Floating Indicator | What Is Happening |
|-------|--------------|--------------------|--------------------|
| **Idle** | Microphone (dim) | Hidden | Waiting for hotkey |
| **Recording** | Microphone (active) | Visible, pulsing | Capturing audio from microphone |
| **Processing** | Spinner / progress | "Processing..." | whisper.cpp transcribing audio |
| **Injecting** | Brief flash | "Done" | Text being typed into active app |
| **Idle** | Microphone (dim) | Hidden | Ready for next dictation |

The entire cycle — from pressing the hotkey, speaking a sentence, to seeing text — typically takes **1-3 seconds** with `whisper-base` on Apple Silicon hardware.

### 6.3 Troubleshooting First Dictation

If text did not appear, check these common issues:

| Problem | Likely Cause | Fix |
|---------|-------------|-----|
| Nothing happens when pressing hotkey | Hotkey conflict with another app | Go to **Settings... > Hotkey** and change the key combination |
| Menu bar shows "No Model" | No Whisper model downloaded | Open **Settings... > Models** and download `whisper-base` |
| Menu bar shows "Permission Missing" | Accessibility or Microphone denied | Open **Settings... > Permissions** and follow the prompts |
| Recording starts but no text appears | Accessibility permission not granted | Grant Accessibility per [Section 4.1](#41-accessibility-permission) |
| Text appears but is garbled or wrong | Microphone picking up noise, or model too small | Try speaking closer to the mic; consider upgrading to `whisper-small` |
| Text appears in wrong application | Focus changed during processing | Keep the target app focused until text is injected |
| Very slow processing | Intel Mac with large model | Switch to `whisper-tiny` or `whisper-base`; see [Speech Recognition](../features/SPEECH_RECOGNITION.md) |
| Error: "Model failed to load" | Corrupted download | Delete the model in **Settings... > Models** and re-download |

> :information_source: **Info:** For comprehensive troubleshooting beyond first-run issues, see the [Setup Guide](SETUP_GUIDE.md). For speech recognition tuning — language selection, custom vocabulary, and accuracy optimization — see [Speech Recognition](../features/SPEECH_RECOGNITION.md).

---

## 7. Next Steps

Congratulations — you have VaulType running with local, private dictation. Here are some things to explore next:

### Customize Your Workflow

- **Change the hotkey** — Go to **Settings... > Hotkey** to pick a key combination that fits your workflow.
- **Enable LLM post-processing** — Download an LLM model and enable text cleanup, grammar correction, or formatting. See [LLM Processing](../features/LLM_PROCESSING.md).
- **Set up custom vocabulary** — Add domain-specific terms (project names, technical jargon) to improve accuracy. See [Speech Recognition](../features/SPEECH_RECOGNITION.md).

### Try Different Models

- Start with `whisper-base`, then experiment with `whisper-small` for better accuracy or `whisper-tiny` for faster response times.
- Models can be swapped without restarting VaulType — just select a different model in **Settings... > Models**.

### Explore Text Injection Options

- VaulType supports multiple text injection strategies depending on the target application. See [Text Injection](../features/TEXT_INJECTION.md) for details on CGEvent keystroke simulation, clipboard-based injection, and per-app configuration.

### Contribute

- VaulType is open source under GPL-3.0. Contributions are welcome.
- See the [Development Guide](DEVELOPMENT_GUIDE.md) for building from source, running tests, and the contribution workflow.

---

## Related Documentation

| Document | Description |
|----------|-------------|
| [Setup Guide](SETUP_GUIDE.md) | Detailed installation, configuration, and troubleshooting |
| [Development Guide](DEVELOPMENT_GUIDE.md) | Building from source, development environment, contributing |
| [Permissions Guide](../features/PERMISSIONS.md) | Complete macOS permissions reference, TCC framework, MDM |
| [Speech Recognition](../features/SPEECH_RECOGNITION.md) | whisper.cpp integration, audio pipeline, language support |
| [Model Management](../features/MODEL_MANAGEMENT.md) | Model lifecycle, downloads, storage, verification |
| [LLM Processing](../features/LLM_PROCESSING.md) | Local LLM text post-processing and formatting |
| [Text Injection](../features/TEXT_INJECTION.md) | How VaulType types text into applications |
| [Architecture](../architecture/ARCHITECTURE.md) | System architecture, threading model, data flows |
| [Tech Stack](../architecture/TECH_STACK.md) | Technology choices, version matrix, performance notes |
