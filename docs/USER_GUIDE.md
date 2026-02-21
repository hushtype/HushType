# VaulType User Guide

**Version 0.5.0 | macOS 14.0+ (Sonoma)**

VaulType is a privacy-first speech-to-text app that lives in your Mac's menu bar. It transcribes your voice locally using on-device AI — no internet connection required, no data ever leaves your machine.

---

## Table of Contents

1. [Getting Started](#1-getting-started)
2. [First Launch — Onboarding](#2-first-launch--onboarding)
3. [Daily Use](#3-daily-use)
4. [Settings Reference](#4-settings-reference)
   - [General](#41-general)
   - [Audio](#42-audio)
   - [Processing](#43-processing)
   - [Models](#44-models)
   - [App Profiles](#45-app-profiles)
   - [Vocabulary](#46-vocabulary)
   - [Language](#47-language)
   - [History](#48-history)
   - [Commands](#49-commands)
   - [Plugins](#410-plugins)
5. [Voice Commands](#5-voice-commands)
6. [Processing Modes](#6-processing-modes)
7. [Troubleshooting](#7-troubleshooting)
8. [Privacy](#8-privacy)

---

## 1. Getting Started

### What is VaulType?

VaulType is a macOS menu bar app that converts your speech into text and types it into any app — email clients, text editors, chat apps, code editors, and more. Unlike cloud-based dictation tools, all AI processing happens entirely on your Mac using:

- **whisper.cpp** for speech recognition
- **llama.cpp** for optional grammar cleanup and text formatting

Everything is stored locally. Nothing is sent to any server.

### System Requirements

| Requirement | Minimum | Recommended |
|---|---|---|
| macOS | 14.0 (Sonoma) | 15.0+ |
| Chip | Intel or Apple Silicon | Apple Silicon (M1 or later) |
| RAM | 4 GB | 8 GB or more |
| Storage | 500 MB free | 2 GB+ free (for additional models) |
| Microphone | Built-in or external | External microphone for best accuracy |

Apple Silicon Macs are strongly recommended. The on-device AI models run significantly faster on the Neural Engine found in M-series chips.

### Installation

**From the DMG:**
1. Download the latest `VaulType.dmg` from the releases page.
2. Open the DMG file.
3. Drag VaulType into your Applications folder.
4. Open VaulType from Applications or Spotlight.

**From Homebrew (when available):**
```
brew install --cask vaultype
```

When you first open VaulType, macOS may ask if you are sure you want to open it. Click "Open" to proceed. VaulType is not yet notarized for all distribution channels.

---

## 2. First Launch — Onboarding

The first time you open VaulType, a setup wizard walks you through four steps. Each step is important for the app to work correctly.

### Step 1: Welcome

A brief introduction to VaulType. Click **Continue** to proceed.

### Step 2: Microphone Access

VaulType needs access to your microphone to capture your voice. Click **Grant Microphone Access** to open the system permission dialog, then click **Allow**.

If you skip this step, dictation will not work. You can grant microphone access later in **System Settings > Privacy & Security > Microphone**.

### Step 3: Accessibility Permission

Accessibility permission allows VaulType to:
- Type transcribed text into other apps
- Move and resize windows using voice commands

Click **Open Accessibility Settings**. In System Settings, scroll down to find VaulType and toggle it on.

This step is technically optional — you can skip it and still use clipboard-based text injection — but it is required for the best experience and for voice commands that manage windows.

### Step 4: Download Speech Model

VaulType needs a speech recognition model before it can transcribe anything. The default model (Base English, approximately 150 MB) is downloaded automatically during this step. Wait for the progress bar to complete before continuing.

You can download additional or larger models later in **Settings > Models**.

### Step 5: You're All Set

Setup is complete. Click **Get Started**. VaulType will minimize to the menu bar. You are ready to dictate.

---

## 3. Daily Use

### The Menu Bar Icon

VaulType lives in your Mac's menu bar. Click the icon to open a quick-access menu where you can start dictation, open Settings, or quit the app.

### Push-to-Talk (Default Mode)

By default, VaulType uses push-to-talk:

1. Place your cursor in any text field (email body, document, chat message, etc.).
2. Press and hold the **fn** key (bottom-left of your keyboard on most Macs).
3. Speak normally. You will hear a soft chime when recording begins.
4. Release the **fn** key when you finish speaking.
5. VaulType processes your audio and types the result into the active field.

The default hotkey is **fn**, but you can change it to any key or modifier combination in **Settings > General**.

### Toggle Mode (Alternative)

If push-to-talk feels awkward for longer dictations, you can switch to toggle mode in **Settings > General > Push-to-Talk Mode** (turn the toggle off). In toggle mode:

1. Press the hotkey once to **start** recording.
2. Speak for as long as you need.
3. Press the hotkey again to **stop** recording and inject text.

### The Overlay Panel

After transcription completes, a floating panel appears showing the recognized text. You can:
- **Read and confirm** the text before it is injected.
- **Edit** any words that were misrecognized.
- **Press Enter** or click the confirm button to inject the text at your cursor.
- **Press Escape** or click dismiss to discard the text without injecting.

You can disable the overlay in **Settings > General > Show Overlay After Dictation** if you prefer text to be injected immediately without review.

### Sound Feedback

VaulType plays audio cues to confirm recording events:
- A chime when recording starts.
- A click when recording stops.
- A distinct sound when a voice command succeeds or fails.

Sound effects can be disabled or the theme changed in **Settings > Audio > Sound Feedback**.

### Text Injection

Once transcription is confirmed (or immediately, if the overlay is disabled), VaulType types the text at your cursor using one of two methods:

- **Automatic (default)**: VaulType picks the best method for the active app automatically.
- **Keyboard Simulation**: Types character by character using simulated keystrokes. Preserves your clipboard but requires Accessibility permission.
- **Clipboard Paste**: Copies text to your clipboard and presses Cmd+V. Works in all apps but temporarily overwrites whatever was on your clipboard.

You can choose a method in **Settings > General > Text Injection**.

---

## 4. Settings Reference

Open Settings by clicking the VaulType icon in the menu bar and selecting **Settings**, or by pressing the standard macOS shortcut **Cmd+,** when any VaulType window is focused.

### 4.1 General

**Input**

| Setting | Description |
|---|---|
| Global Hotkey | The key or shortcut that starts/stops dictation. Click the field and press any key combination to set a new hotkey. The default is `fn`. |
| Push-to-Talk Mode | When on, hold the hotkey to record and release to stop. When off, press once to start and press again to stop. |

**Startup & Appearance**

| Setting | Description |
|---|---|
| Launch at Login | Automatically starts VaulType when you log in to your Mac. Recommended for daily use. |
| Show Overlay After Dictation | Displays a floating review panel showing the transcription before it is typed. Turn off for instant injection. |
| Play Sound Effects | Plays audio feedback when recording starts and stops. |

**Updates**

Click **Check for Updates** to see if a newer version of VaulType is available.

**Text Injection**

| Setting | Description |
|---|---|
| Default Method | How VaulType types text. Options: Automatic Detection, Keyboard Simulation (CGEvent), or Clipboard Paste. |
| Keystroke Delay | Time in milliseconds between simulated keystrokes (Keyboard Simulation mode only). Increase this if text is being dropped in some apps. Default: 5 ms. |

### 4.2 Audio

**Input Device**

Select which microphone VaulType uses. The default is your system's default input device. Click **Refresh Devices** if a newly plugged-in microphone does not appear.

**Voice Activity Detection**

The VAD Sensitivity slider controls how sensitive VaulType is to detecting speech. The orange line on the level meter shows the current threshold.

- Audio levels **above** the orange line are treated as speech.
- Audio levels **below** the orange line are treated as silence or background noise.

Lower the sensitivity if VaulType is picking up too much background noise. Raise it if VaulType is cutting off the beginning of your speech. Click **Start Preview** to see your microphone level in real time while adjusting.

**Sound Feedback**

| Setting | Description |
|---|---|
| Enable Sound Effects | Turns audio feedback on or off. |
| Sound Theme | Choose between **Subtle** (quiet, unobtrusive tones) and **Mechanical** (more audible click-style sounds). |
| Volume | Adjusts the volume of the sound effects independently of your system volume. |

Click **Preview Sound** to hear how the current settings sound.

**Advanced**

| Setting | Description |
|---|---|
| GPU Acceleration | Always on (Metal). Uses your Mac's GPU for faster transcription on supported hardware. |
| Inference Threads | Number of CPU threads for speech recognition. **Auto** is recommended and uses all available cores. Reduce this if you notice the fan spinning excessively. |
| Battery-Aware Mode | When on, VaulType automatically reduces quality and thread count when running on battery power to extend battery life. |

### 4.3 Processing

**Default Processing Mode**

Choose how transcriptions are handled after speech recognition. The dropdown shows all six modes. Modes that require an LLM model show a notice if no LLM model is configured.

See [Section 6: Processing Modes](#6-processing-modes) for a full explanation of each mode.

**Active LLM Model**

Shows the LLM model currently selected for text post-processing. To change it, go to **Settings > Models** and select a different LLM.

**Templates**

When using Prompt Template mode, this section lists the available templates for the selected mode. Click **Manage Templates** to create, edit, or delete templates using the template editor.

**Advanced**

| Setting | Description |
|---|---|
| LLM Context Length | Maximum number of tokens the LLM can process at once. Default is 2048. Increase for longer texts, but be aware that higher values use more RAM. |

### 4.4 Models

VaulType uses two types of AI models:

- **Speech-to-Text (Whisper)**: Converts your voice to text.
- **Language Model (LLM)**: Optionally post-processes the text (grammar, formatting, etc.).

Use the segmented picker at the top to switch between the two model types.

**Whisper Model Comparison**

| Model | File Size | RAM | Speed | Accuracy |
|---|---|---|---|---|
| Tiny | 75 MB | ~273 MB | Fastest | Basic |
| Base | 142 MB | ~388 MB | Fast | Good |
| Small | 466 MB | ~852 MB | Moderate | Better |
| Medium | 1.5 GB | ~2.1 GB | Slow | Very Good |
| Large v3 Turbo | 1.5 GB | ~2.1 GB | Slow | Best |

**Recommendation**: Start with **Base** for everyday use. If you notice frequent errors with names, technical terms, or accented speech, upgrade to **Small**.

English-only models (labeled `.en`) are faster and more accurate if you dictate exclusively in English.

**LLM Model Comparison**

| Model | File Size | RAM | Quality |
|---|---|---|---|
| Qwen 2.5 0.5B | 463 MB | ~900 MB | Good |
| Gemma 3 1B | 806 MB | ~1.5 GB | Better |
| Llama 3.2 1B | 808 MB | ~1.5 GB | Better |
| Qwen 2.5 1.5B | 1.1 GB | ~2 GB | Great |
| Phi-4 Mini 3.8B | 2.5 GB | ~4 GB | Best |

**Recommendation**: **Qwen 2.5 0.5B** for fast grammar cleanup. **Phi-4 Mini** for the best rewriting quality.

An LLM is not required if you use Raw Transcription mode. Only download an LLM if you want Clean, Structure, Prompt, Code, or Custom processing.

**Downloading and Managing Models**

1. Select the model type (Whisper or LLM) using the picker.
2. Find the model you want in the **Available Models** list.
3. Click the download button (cloud icon) next to it.
4. Wait for the progress bar to complete.
5. In the **Active Model** section, select your newly downloaded model.

To delete a model and free up disk space, click the trash icon next to a downloaded model. You cannot delete the model that is currently active — switch to another model first.

Click **Check for Updates** to refresh the model registry and see if new models are available.

### 4.5 App Profiles

App Profiles let you configure VaulType differently for each application. For example, you might want:

- Code mode when dictating in VS Code.
- Clean mode when writing emails in Mail.
- A different language when using a Japanese text editor.

**Creating a Profile**

1. Click **Add Profile**.
2. Enter the app's bundle identifier (e.g., `com.apple.mail`) and its display name.
3. Click Save.
4. Select the profile in the list to configure its settings.

**Profile Settings**

Each profile can override:
- Default processing mode
- Default spoken language
- Custom vocabulary (spoken-word substitutions specific to this app)
- Shortcut aliases (voice phrases that trigger keyboard shortcuts in this app)

When VaulType detects that a specific app is active, its profile settings take priority over your global defaults.

### 4.6 Vocabulary

The Vocabulary tab lets you teach VaulType custom word substitutions. When a spoken form is recognized, it is automatically replaced with your defined replacement before text injection.

**Example use cases:**
- Say "my email" → type `firstname.lastname@example.com`
- Say "company name" → type `Acme Corporation`
- Say "version number" → type `v2.4.1`
- Correct a name VaulType consistently misspells, such as "Kaitlin" being misheard as "Caitlin"

**Adding a Vocabulary Entry**

1. Click the **+** button.
2. Enter the **Spoken Form** — exactly what you will say.
3. Enter the **Replacement** — the text that will be typed.
4. Optionally set a language restriction and whether it is case-sensitive.
5. Choose **Global** (applies everywhere) or **Per-App** (applies only in a specific app profile).

Entries are sorted alphabetically. You can filter the list by scope using the **All / Global / Per-App** picker.

### 4.7 Language

**Auto-Detect Language**

When this toggle is on, whisper.cpp analyzes the first 30 seconds of audio to identify the spoken language automatically. This is useful if you regularly switch between languages.

**Default Language**

When auto-detect is off, VaulType uses this language for all transcriptions. If you have an App Profile that specifies a different language, the profile's language takes priority.

Supported languages include English, Turkish, German, French, Spanish, Italian, Portuguese, Dutch, Polish, Russian, Chinese, Japanese, Korean, Arabic, and Hindi.

### 4.8 History

VaulType keeps a log of past dictations in **History**. Access it from the menu bar menu to review, copy, or re-inject earlier transcriptions.

**Retention Policies**

| Setting | Description |
|---|---|
| Max Entries | Maximum number of history items to keep. Set to 0 for unlimited. Oldest entries beyond this limit are deleted automatically. Default: 5000. |
| Retention (Days) | Entries older than this many days are deleted automatically. Set to 0 to keep entries forever. Default: 90 days. |

Entries marked as favorites are never deleted automatically regardless of these limits.

**Privacy**

Toggle **Store transcription text** off if you want VaulType to record that a dictation happened (timestamp, duration, word count) without storing the actual text. This is useful if you dictate sensitive content.

**Storage Actions**

- **Clear All History**: Permanently deletes all history entries, including favorites. This cannot be undone.
- **Factory Reset**: Deletes all data — history, profiles, vocabulary — and resets all settings to their defaults.

### 4.9 Commands

Voice commands let you control macOS by voice using the same hotkey as dictation. Instead of typing text, you give VaulType a command to execute.

**Enable Voice Commands**

Toggle **Enable Voice Commands** on to activate the system.

**Wake Phrase**

The wake phrase is what you say to distinguish a command from regular dictation. The default wake phrase is `Hey Type`.

To use a voice command, say the wake phrase followed by your command:

```
"Hey Type, open Safari"
"Hey Type, volume up"
"Hey Type, move window left"
```

You can change the wake phrase to any word or short phrase that feels natural. Make sure it is something unlikely to appear in regular dictation.

**Built-in Commands**

Each category of commands can be individually enabled or disabled. Expand each section to see example phrases and toggle commands on or off.

See [Section 5: Voice Commands](#5-voice-commands) for a full reference.

**Global Shortcut Aliases**

Shortcut aliases let you say a phrase to trigger any keyboard shortcut. For example:

- Say "undo" → presses Cmd+Z
- Say "save file" → presses Cmd+S
- Say "paste plain" → presses Cmd+Shift+V

Click **Add Alias** to create a new one. Enter:
- **Spoken Phrase**: What you will say after the wake phrase.
- **Shortcut**: The keyboard shortcut in the format `modifier+key`, for example `cmd+z` or `cmd+shift+v`.

Global aliases work in all apps. App-specific aliases (set in App Profiles) override global ones.

**Custom Commands**

Custom commands let you define your own trigger phrases that execute one or more built-in actions in sequence. Click **Manage Custom Commands** to open the editor.

### 4.10 Plugins

Plugins extend VaulType with additional processing modes or custom voice commands. They are distributed as `.bundle` files.

**Installing a Plugin**

1. Click **Open Plugins Folder** to open `~/Library/Application Support/VaulType/Plugins/` in Finder.
2. Copy your `.bundle` file into this folder.
3. Return to VaulType and click **Refresh** to discover the new plugin.

**Managing Plugins**

Each installed plugin appears in the list with a toggle to activate or deactivate it. Use the trash button to unload a plugin from the current session (the file remains in the Plugins folder and can be re-loaded by clicking Refresh).

---

## 5. Voice Commands

Voice commands let you control your Mac entirely by voice. The command system is fully local — no internet connection is required.

### How to Issue a Command

1. Press (and hold, in push-to-talk mode) the dictation hotkey.
2. Say the wake phrase (default: **Hey Type**) followed by your command.
3. Release the hotkey.

VaulType recognizes the wake phrase, strips it from the transcription, and routes the remainder through the command parser instead of injecting it as text.

**Example:**
```
"Hey Type, open Mail"
"Hey Type, volume 50"
"Hey Type, move window left and then maximize"
```

### Chaining Commands

You can issue multiple commands in a single recording using "and", "then", or "and then":

```
"Hey Type, open Safari and then volume up"
"Hey Type, maximize window then do not disturb"
```

Commands in a chain execute sequentially. If one command fails, the chain stops.

### App Management Commands

| What you say | What happens |
|---|---|
| `open [app name]` | Opens or brings an app to the front |
| `launch [app name]` | Same as open |
| `switch to [app name]` | Activates a running app |
| `go to [app name]` | Same as switch to |
| `close [app name]` | Closes the frontmost window of an app |
| `quit [app name]` | Quits an app |
| `exit [app name]` | Same as quit |
| `hide [app name]` | Hides an app |
| `show all windows` | Triggers Mission Control (Exposé) |
| `mission control` | Same as show all windows |

**Examples:**
```
"Hey Type, open Notes"
"Hey Type, quit Safari"
"Hey Type, switch to Finder"
```

### Window Management Commands

Window management commands require Accessibility permission.

| What you say | What happens |
|---|---|
| `move window left` | Tiles the active window to the left half of the screen |
| `tile left` | Same as move window left |
| `move window right` | Tiles the active window to the right half of the screen |
| `maximize` | Expands the active window to fill the screen |
| `maximize window` | Same as maximize |
| `minimize` | Minimizes the active window to the Dock |
| `center window` | Centers the active window on screen |
| `full screen` | Toggles full-screen mode |
| `next screen` | Moves the active window to the next display |
| `other screen` | Same as next screen |

**Examples:**
```
"Hey Type, move window left"
"Hey Type, full screen"
"Hey Type, maximize and then do not disturb"
```

### Volume and Brightness Commands

| What you say | What happens |
|---|---|
| `volume up` | Increases system volume |
| `louder` | Same as volume up |
| `volume down` | Decreases system volume |
| `quieter` | Same as volume down |
| `mute` | Toggles mute on/off |
| `volume [number]` | Sets volume to a specific percentage, e.g. `volume 50` |
| `brightness up` | Increases screen brightness |
| `brighter` | Same as brightness up |
| `brightness down` | Decreases screen brightness |
| `dimmer` | Same as brightness down |

**Examples:**
```
"Hey Type, volume 40"
"Hey Type, mute"
"Hey Type, brighter"
```

### System Control Commands

| What you say | What happens |
|---|---|
| `do not disturb` | Toggles Focus / Do Not Disturb mode |
| `dark mode` | Toggles between dark and light appearance |
| `lock screen` | Locks your Mac |
| `lock` | Same as lock screen |
| `take a screenshot` | Captures a screenshot |
| `screenshot` | Same as take a screenshot |

### Shortcut Injection

You can speak keyboard shortcuts directly:

```
"Hey Type, command Z"           → presses Cmd+Z (undo)
"Hey Type, command shift Z"     → presses Cmd+Shift+Z (redo)
"Hey Type, control option T"    → presses Ctrl+Option+T
```

The format is: say the modifier keys followed by the key name.
Supported modifiers: `command` / `cmd`, `control` / `ctrl`, `option` / `opt` / `alt`, `shift`.

### Running Apple Shortcuts

You can trigger any shortcut you have created in the macOS Shortcuts app:

```
"Hey Type, run shortcut Daily Report"
"Hey Type, shortcut Morning Routine"
```

### Custom Aliases

If you have set up shortcut aliases in **Settings > Commands**, say the phrase after the wake phrase to trigger the mapped shortcut:

```
"Hey Type, undo"            → presses Cmd+Z (if aliased)
"Hey Type, paste plain"     → presses Cmd+Shift+V (if aliased)
```

---

## 6. Processing Modes

Processing modes control what happens to the raw transcription text before it is typed into your app. You can set a global default mode in **Settings > Processing**, and override it per-app in **Settings > App Profiles**.

### Raw Transcription

Injects the text exactly as whisper.cpp transcribed it. No changes are made.

**Best for:** When you want maximum speed and total control. Good for note-taking apps where you will clean up the text yourself.

**Example:**
- You say: *"um so basically the meeting is uh scheduled for thursday and we need to like finalize the agenda"*
- You get: `um so basically the meeting is uh scheduled for thursday and we need to like finalize the agenda`

### Clean Text

Uses an LLM to remove filler words, fix punctuation, and correct capitalization. The meaning and tone stay the same — only the rough edges are smoothed.

**Best for:** Emails, messages, and documents where you want professional-looking output without editing.

**Example:**
- You say: *"um so basically the meeting is uh scheduled for thursday and we need to like finalize the agenda"*
- You get: `The meeting is scheduled for Thursday and we need to finalize the agenda.`

### Structured Output

Uses an LLM to organize your text into paragraphs, bullet lists, or headings based on what makes sense for the content.

**Best for:** Meeting notes, reports, or any situation where you speak in a flowing stream-of-consciousness style but want structured output.

**Example:**
- You say: *"the new feature needs a database migration a UI update and updated documentation and we should also write tests"*
- You get:
  ```
  New feature requirements:
  - Database migration
  - UI update
  - Updated documentation
  - Tests
  ```

### Prompt Template

Runs the transcription through a custom LLM prompt template you have defined. You choose exactly how the LLM should transform the input.

**Best for:** Specialized workflows — translating to another language, formatting as JSON, converting to bullet points in a specific style, or any transformation you use repeatedly.

Create and manage templates in **Settings > Processing > Manage Templates**.

### Code Mode

Optimizes transcription for dictating source code and technical content. The LLM attempts to format variable names (camelCase, snake_case), recognize language-specific syntax, and produce properly formatted code.

**Best for:** Dictating code in editors like VS Code, Xcode, or any IDE.

**Example:**
- You say: *"function calculate total price with items array that returns a number"*
- You get: `function calculateTotalPrice(items: [Item]) -> Double {`

### Custom Pipeline

Fully user-defined processing using a combination of pre-processors and post-processors configured in the template editor. This is the most flexible mode for advanced users who need transformations that go beyond a single LLM prompt.

**Note:** All modes except Raw Transcription require an LLM model to be downloaded and configured in **Settings > Models**.

---

## 7. Troubleshooting

### Microphone Not Detected

**Symptom**: VaulType shows no audio level in the settings, or nothing happens when you press the hotkey.

**Solutions:**
1. Open **System Settings > Privacy & Security > Microphone** and confirm VaulType has permission.
2. In **Settings > Audio**, click **Refresh Devices** and check if your microphone appears in the list.
3. Make sure your microphone is not muted at the hardware level (some USB microphones have a physical mute button).
4. If you recently plugged in a new microphone, click **Refresh Devices** — the device list does not update automatically.

### Text Is Not Being Typed Into the App

**Symptom**: Transcription appears in the overlay, but nothing is typed after you confirm.

**Solutions:**
1. Open **System Settings > Privacy & Security > Accessibility** and confirm VaulType is listed and enabled.
2. Without Accessibility permission, only Clipboard Paste injection works. Try setting **Settings > General > Default Method** to **Clipboard Paste**.
3. Some apps (notably web browsers running in isolated sandbox modes) may block simulated keystrokes. Try Clipboard Paste mode for those apps.
4. Confirm that the text field you want to type into was focused before you started recording.

### No Models Downloaded

**Symptom**: VaulType shows a "No model available" error, or transcription never starts.

**Solutions:**
1. Go to **Settings > Models**, switch to the **Whisper** tab, and download at least one model.
2. After downloading, check the **Active Model** section to confirm the downloaded model is selected.
3. If the download fails, check your internet connection and click the Retry button (circular arrow icon).

### Slow Transcription

**Symptom**: After releasing the hotkey, it takes several seconds before text appears.

**Solutions:**
1. Use a smaller Whisper model. Switch from **Small** or **Medium** to **Base** in **Settings > Models**.
2. Turn on **Battery-Aware Mode** if you are on battery — this reduces quality to maintain speed.
3. Set **Inference Threads** to **Auto** in **Settings > Audio > Advanced** if you changed it manually.
4. Upgrade to Apple Silicon if you are on an Intel Mac. The performance difference is substantial.
5. Disable LLM post-processing by switching to **Raw Transcription** mode in **Settings > Processing**.

### Voice Commands Not Working

**Symptom**: You say the wake phrase but commands are not executed.

**Solutions:**
1. Confirm **Enable Voice Commands** is turned on in **Settings > Commands**.
2. Check that you are saying the exact wake phrase — the default is **Hey Type**. Verify it in **Settings > Commands > Wake Phrase**.
3. Make sure you say the wake phrase clearly before the command, within the same recording.
4. For window management commands, confirm Accessibility permission is granted.
5. Check that the specific command category (App Management, Window Management, etc.) is not disabled in **Settings > Commands**.

### High CPU or Fan Noise

**Symptom**: Your Mac's fan runs loudly during transcription.

**Solutions:**
1. Switch to a smaller Whisper model (**Tiny** or **Base**).
2. Reduce **Inference Threads** in **Settings > Audio > Advanced** to 2 or 4.
3. Enable **Battery-Aware Mode** to automatically throttle performance.
4. Disable the LLM by switching to **Raw Transcription** processing mode.

### Overlay Panel Not Appearing

**Symptom**: Text is injected immediately without showing the review overlay.

**Solution**: Go to **Settings > General** and turn on **Show Overlay After Dictation**.

### App Not in Menu Bar After Restart

**Symptom**: VaulType does not start automatically when you log in.

**Solution**: Go to **Settings > General** and turn on **Launch at Login**.

---

## 8. Privacy

VaulType is built around a single principle: **your voice data never leaves your device**.

### What Runs Locally

- **Audio capture** is done by the built-in macOS audio system (AVFoundation). Audio is captured directly by VaulType and never routed to any external service.
- **Speech recognition** uses whisper.cpp, a local implementation of OpenAI's Whisper model. The model file is stored on your Mac and runs entirely in-process.
- **Text processing** uses llama.cpp, a local implementation of various LLM models. All grammar correction, formatting, and template processing runs on your hardware.
- **Text injection** is done directly through macOS system APIs (CGEvent or the clipboard). No third-party service is involved.

### What Is Stored on Your Mac

- Dictation history (text and metadata) is stored in a local SwiftData database in your app's container.
- App profiles, vocabulary entries, and settings are stored in the same local database.
- AI model files are stored in `~/Library/Application Support/VaulType/Models/`.
- Plugins are stored in `~/Library/Application Support/VaulType/Plugins/`.

None of this data is transmitted anywhere.

### Telemetry and Analytics

VaulType collects no telemetry, crash reports, or analytics. There are no tracking identifiers, no anonymous usage statistics, and no network calls to any analytics service.

### Network Usage

The only network activity VaulType performs is:
- Downloading model files when you click the download button in **Settings > Models**.
- Checking for app updates when you click **Check for Updates** in **Settings > General** (uses Sparkle, an open-source updater).

Both of these are initiated explicitly by you. VaulType does not make background network requests.

### Microphone Usage

VaulType only captures audio while you are actively holding (or have toggled on) the dictation hotkey. The microphone is not active in the background at any other time.

### Removing Your Data

- To clear all dictation history, go to **Settings > History > Clear All History**.
- To remove all data and reset VaulType to its default state, go to **Settings > History > Factory Reset**.
- To fully uninstall VaulType, quit the app, delete it from your Applications folder, and optionally delete `~/Library/Application Support/VaulType/` to remove all stored data and models.

---

*VaulType v0.5.0 — Built with whisper.cpp and llama.cpp*
