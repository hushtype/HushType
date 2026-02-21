# Text Injection

Last Updated: 2026-02-13

> VaulType's text injection system delivers transcribed speech directly into any active text field
> on macOS. This document provides a deep dive into CGEvent keystroke simulation, clipboard-based
> injection, accessibility API integration, Unicode handling, and per-app compatibility strategies.

---

## Table of Contents

- [Overview](#overview)
- [Injection Pipeline Architecture](#injection-pipeline-architecture)
- [CGEvent Keystroke Simulation Deep Dive](#cgevent-keystroke-simulation-deep-dive)
  - [How CGEvent Works](#how-cgevent-works)
  - [Creating Key Events](#creating-key-events)
  - [Posting to System Event Tap](#posting-to-system-event-tap)
  - [Character-by-Character Injection](#character-by-character-injection)
  - [Speed Considerations](#speed-considerations)
  - [Key Code Mapping](#key-code-mapping)
- [Clipboard-Paste Method Implementation](#clipboard-paste-method-implementation)
  - [NSPasteboard Usage](#nspasteboard-usage)
  - [Simulating Command-V](#simulating-command-v)
  - [When to Use Clipboard vs CGEvent](#when-to-use-clipboard-vs-cgevent)
  - [Implementation Details](#implementation-details)
- [Clipboard Preservation Strategy](#clipboard-preservation-strategy)
  - [Saving Current Clipboard Contents](#saving-current-clipboard-contents)
  - [Restoring After Injection](#restoring-after-injection)
  - [Handling Different Pasteboard Types](#handling-different-pasteboard-types)
  - [Edge Cases](#edge-cases)
- [Active App and Text Field Detection](#active-app-and-text-field-detection)
  - [AXUIElement API](#axuielement-api)
  - [Detecting the Focused Element](#detecting-the-focused-element)
  - [Checking If Element Accepts Text Input](#checking-if-element-accepts-text-input)
  - [Getting Cursor Position](#getting-cursor-position)
  - [Frontmost App Detection](#frontmost-app-detection)
- [Handling Special Characters and Unicode](#handling-special-characters-and-unicode)
  - [Emoji Injection](#emoji-injection)
  - [CJK Characters](#cjk-characters)
  - [Diacritics and Combining Characters](#diacritics-and-combining-characters)
  - [Special Symbols](#special-symbols)
  - [Newlines and Tabs](#newlines-and-tabs)
- [Per-App Injection Quirks and Workarounds](#per-app-injection-quirks-and-workarounds)
  - [App Compatibility Table](#app-compatibility-table)
  - [Known Issues and Solutions](#known-issues-and-solutions)
- [Terminal Compatibility](#terminal-compatibility)
  - [Terminal.app](#terminalapp)
  - [iTerm2](#iterm2)
  - [Warp](#warp)
  - [Alacritty](#alacritty)
  - [Terminal Injection Strategy](#terminal-injection-strategy)
- [Electron App Compatibility](#electron-app-compatibility)
  - [VS Code](#vs-code)
  - [Slack](#slack)
  - [Discord](#discord)
  - [Electron Input Handling Quirks](#electron-input-handling-quirks)
- [Browser Text Field Handling](#browser-text-field-handling)
  - [Safari](#safari)
  - [Chrome](#chrome)
  - [Firefox](#firefox)
  - [ContentEditable Fields](#contenteditable-fields)
  - [Textarea and Input Fields](#textarea-and-input-fields)
- [Per-App Injection Method Selection](#per-app-injection-method-selection)
- [Error Handling and Recovery](#error-handling-and-recovery)
- [Performance Optimization](#performance-optimization)
- [Related Documentation](#related-documentation)

---

## Overview

Text injection is the final stage of VaulType's speech-to-text pipeline. After audio is captured,
transcribed by whisper.cpp, and optionally refined by llama.cpp, the resulting text must be
delivered into whatever application and text field the user is currently focused on. This is a
deceptively complex problem on macOS, involving low-level Core Graphics events, the system
pasteboard, accessibility APIs, and per-application workarounds.

> 🍎 **macOS-specific**: Text injection on macOS requires Accessibility permissions. The user
> must grant VaulType access in System Settings > Privacy & Security > Accessibility. See
> [PERMISSIONS.md](PERMISSIONS.md) for the full permissions guide.

VaulType supports two primary injection methods:

| Method | Mechanism | Best For | Latency |
|--------|-----------|----------|---------|
| **CGEvent Keystroke** | Simulates individual key presses | Short text, precise control | ~2-5ms per char |
| **Clipboard Paste** | Writes to pasteboard, simulates Cmd+V | Long text, Unicode-heavy content | ~10-30ms total |

The injection system automatically selects the optimal method based on text length, character
composition, target application, and user preferences.

---

## Injection Pipeline Architecture

The following diagram illustrates the complete injection pipeline from transcribed text to
final delivery:

```
+------------------+     +-------------------+     +--------------------+
| Transcription    |---->| Text Processor    |---->| Injection Router   |
| Engine Output    |     | (formatting,      |     | (method selection) |
|                  |     |  punctuation)     |     |                    |
+------------------+     +-------------------+     +--------+-----------+
                                                            |
                                    +-----------------------+-----------------------+
                                    |                                               |
                          +---------v----------+                         +----------v---------+
                          | CGEvent Keystroke  |                         | Clipboard Paste    |
                          | Injector           |                         | Injector           |
                          |                    |                         |                    |
                          | 1. Map chars to    |                         | 1. Save clipboard  |
                          |    key codes       |                         | 2. Write text to   |
                          | 2. Create CGEvent  |                         |    pasteboard      |
                          | 3. Post key down   |                         | 3. Simulate Cmd+V  |
                          | 4. Post key up     |                         | 4. Restore clipbd  |
                          | 5. Inter-key delay |                         |                    |
                          +---------+----------+                         +----------+---------+
                                    |                                               |
                                    +-----------------------+-----------------------+
                                                            |
                                                  +---------v----------+
                                                  | Target App         |
                                                  | Text Field         |
                                                  | (via Accessibility)|
                                                  +--------------------+
```

```
Injection Router Decision Flow:
================================

  Text arrives
       |
       v
  [Text length > threshold?]---YES--->[Contains only ASCII?]---YES--->[Clipboard Paste]
       |                                      |
       NO                                     NO
       |                                      |
       v                                      v
  [Contains only ASCII?]              [Clipboard Paste]
       |           |
      YES          NO
       |           |
       v           v
  [CGEvent]   [Clipboard Paste]


  Default threshold: 64 characters
  Configurable per-app overrides available
```

> ℹ️ **Info**: The threshold between CGEvent and clipboard injection is configurable. The
> default of 64 characters balances latency and reliability. Some applications work better
> with one method over the other regardless of text length.

---

## CGEvent Keystroke Simulation Deep Dive

### How CGEvent Works

CGEvent is part of the Core Graphics framework (`CoreGraphics.framework`) and provides
low-level access to the macOS event system. It allows applications to create synthetic
keyboard, mouse, and other input events that are indistinguishable from real hardware
input at the system level.

The event flow for CGEvent keystroke injection:

```
+------------+     +----------------+     +------------------+     +---------------+
| VaulType   |---->| CGEvent API    |---->| macOS Event      |---->| Target App    |
| creates    |     | (CoreGraphics) |     | System (WindowServer) | | receives      |
| CGEvent    |     |                |     |                  |     | key event     |
+------------+     +----------------+     +------------------+     +---------------+
```

Key concepts:

- **CGEvent** objects represent low-level input events
- **CGEventSource** defines the origin state of events (keyboard state, mouse position)
- **CGEventTapLocation** determines where events are injected into the event stream
- Events posted via `CGEvent.post()` pass through the same path as real hardware events

> 🔒 **Security**: CGEvent posting requires the Accessibility permission. Without it,
> `CGEvent.post()` silently drops events. VaulType checks permission status before
> attempting injection. See [PERMISSIONS.md](PERMISSIONS.md).

### Creating Key Events

VaulType wraps CGEvent creation in a type-safe Swift layer:

```swift
import CoreGraphics
import Carbon.HIToolbox

/// Represents a single keystroke with optional modifiers.
struct Keystroke {
    let keyCode: CGKeyCode
    let modifiers: CGEventFlags
    let character: Character?

    init(keyCode: CGKeyCode, modifiers: CGEventFlags = [], character: Character? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.character = character
    }
}

/// Creates and posts CGEvent keystrokes to the system event stream.
final class CGEventKeystrokeInjector: @unchecked Sendable {

    private let eventSource: CGEventSource?
    private let tapLocation: CGEventTapLocation

    init(tapLocation: CGEventTapLocation = .cghidEventTap) {
        self.eventSource = CGEventSource(stateID: .combinedSessionState)
        self.tapLocation = tapLocation
    }

    /// Posts a single key down + key up pair for the given keystroke.
    func postKeystroke(_ keystroke: Keystroke) throws {
        guard let keyDown = CGEvent(
            keyboardEventSource: eventSource,
            virtualKey: keystroke.keyCode,
            keyDown: true
        ) else {
            throw InjectionError.eventCreationFailed
        }

        guard let keyUp = CGEvent(
            keyboardEventSource: eventSource,
            virtualKey: keystroke.keyCode,
            keyDown: false
        ) else {
            throw InjectionError.eventCreationFailed
        }

        // Apply modifier flags if any
        if !keystroke.modifiers.isEmpty {
            keyDown.flags = keystroke.modifiers
            keyUp.flags = keystroke.modifiers
        }

        // If we have a specific character, set the Unicode string on the event.
        // This is critical for non-ASCII characters that don't map to simple key codes.
        if let character = keystroke.character {
            let utf16 = Array(String(character).utf16)
            keyDown.keyboardSetUnicodeString(
                stringLength: utf16.count,
                unicodeString: utf16
            )
        }

        keyDown.post(tap: tapLocation)
        keyUp.post(tap: tapLocation)
    }
}
```

> ⚠️ **Warning**: The `CGEventSource` state ID matters. Using `.combinedSessionState`
> reflects the real keyboard state which is usually correct. Using `.privateState` creates
> an isolated state that ignores physical key presses, which can be useful if users type
> while injection is in progress but may confuse modifier-aware applications.

### Posting to System Event Tap

CGEvents can be posted at three different tap locations, each with different behavior:

| Tap Location | Constant | Description |
|---|---|---|
| HID Event Tap | `.cghidEventTap` | Earliest point; events appear as hardware input |
| Session Event Tap | `.cgSessionEventTap` | After HID processing; session-level injection |
| Annotated Session | `.cgAnnotatedSessionEventTap` | Events are marked as synthetic |

VaulType defaults to `.cghidEventTap` for maximum compatibility. Some applications
(notably certain Electron apps) behave differently with annotated events.

```swift
/// Event tap location strategy per application.
enum EventTapStrategy {
    case hidEventTap          // Default, maximum compatibility
    case sessionEventTap      // For apps that filter HID events
    case annotatedSession     // When synthetic marking is acceptable

    var tapLocation: CGEventTapLocation {
        switch self {
        case .hidEventTap:
            return .cghidEventTap
        case .sessionEventTap:
            return .cgSessionEventTap
        case .annotatedSession:
            return .cgAnnotatedSessionEventTap
        }
    }
}
```

### Character-by-Character Injection

For reliable text injection, VaulType iterates through each character in the text and
posts individual keystroke events:

```swift
extension CGEventKeystrokeInjector {

    /// Injects a full string character by character with configurable inter-key delay.
    /// - Parameters:
    ///   - text: The string to inject.
    ///   - interKeyDelay: Delay in nanoseconds between each keystroke. Default is 1ms.
    func injectText(_ text: String, interKeyDelay: UInt64 = 1_000_000) async throws {
        for character in text {
            let keystroke = KeyCodeMapper.keystroke(for: character)
            try postKeystroke(keystroke)

            // Inter-key delay prevents event coalescing and dropped characters
            if interKeyDelay > 0 {
                try await Task.sleep(nanoseconds: interKeyDelay)
            }
        }
    }

    /// Injects text with adaptive delay based on target application responsiveness.
    /// Starts with a minimal delay and increases if character drops are detected.
    func injectTextAdaptive(
        _ text: String,
        baseDelay: UInt64 = 500_000,
        maxDelay: UInt64 = 5_000_000
    ) async throws {
        var currentDelay = baseDelay

        for character in text {
            let keystroke = KeyCodeMapper.keystroke(for: character)
            try postKeystroke(keystroke)

            try await Task.sleep(nanoseconds: currentDelay)

            // Adaptive delay: increase if the system event queue is backed up
            if CGEventSource.secondsSinceLastEventType(
                .combinedSessionState,
                eventType: .keyDown
            ) < Double(currentDelay) / 1_000_000_000.0 {
                currentDelay = min(currentDelay * 2, maxDelay)
            }
        }
    }
}
```

> 💡 **Tip**: The inter-key delay is the single most important tuning parameter for
> CGEvent injection reliability. Too fast and characters get dropped; too slow and the
> user experiences noticeable latency. The adaptive approach works well for unknown
> applications.

### Speed Considerations

CGEvent keystroke injection speed is bounded by several factors:

```
Injection Speed Factors:
========================

  Factor                    Impact          Typical Range
  ----------------------------------------------------------------
  Inter-key delay           Primary         0.5ms - 5ms per char
  CGEvent creation          Minimal         ~0.01ms per event
  Event posting             Low             ~0.05ms per event
  Target app processing     Variable        0ms - 10ms per char
  Window Server routing     Low             ~0.1ms per event
  ----------------------------------------------------------------

  Effective throughput:
    Best case:  ~2000 chars/sec  (0.5ms delay, fast app)
    Typical:    ~500 chars/sec   (2ms delay, normal app)
    Worst case: ~100 chars/sec   (10ms delay, slow app)

  For reference:
    Average sentence: ~80 characters
    Typical injection time: 40ms - 800ms depending on method
```

> ℹ️ **Info**: For text longer than ~64 characters, the clipboard-paste method is almost
> always faster. A 500-character paragraph takes ~1 second via CGEvent but only ~30ms via
> clipboard paste.

### Key Code Mapping

macOS key codes are hardware-level virtual key codes defined in `Carbon.HIToolbox`.
VaulType maintains a mapping table for ASCII characters:

```swift
import Carbon.HIToolbox

/// Maps characters to macOS virtual key codes and required modifiers.
enum KeyCodeMapper {

    /// Returns the keystroke (key code + modifiers) for a given character.
    /// Falls back to Unicode injection for characters without direct key code mappings.
    static func keystroke(for character: Character) -> Keystroke {
        // Check ASCII mapping first
        if let ascii = character.asciiValue,
           let mapping = asciiKeyCodeMap[ascii] {
            return Keystroke(
                keyCode: mapping.keyCode,
                modifiers: mapping.modifiers,
                character: character
            )
        }

        // For non-ASCII characters, use a generic key code with Unicode string override.
        // Key code 0 (kVK_ANSI_A) is used as a carrier; the Unicode string on the
        // CGEvent determines what character is actually produced.
        return Keystroke(
            keyCode: CGKeyCode(kVK_ANSI_A),
            modifiers: [],
            character: character
        )
    }

    private struct KeyMapping {
        let keyCode: CGKeyCode
        let modifiers: CGEventFlags
    }

    /// ASCII key code map for US keyboard layout.
    /// Key codes are hardware-level and layout-independent.
    private static let asciiKeyCodeMap: [UInt8: KeyMapping] = {
        var map = [UInt8: KeyMapping]()

        // Letters (lowercase)
        let letterCodes: [(Character, Int)] = [
            ("a", kVK_ANSI_A), ("b", kVK_ANSI_B), ("c", kVK_ANSI_C),
            ("d", kVK_ANSI_D), ("e", kVK_ANSI_E), ("f", kVK_ANSI_F),
            ("g", kVK_ANSI_G), ("h", kVK_ANSI_H), ("i", kVK_ANSI_I),
            ("j", kVK_ANSI_J), ("k", kVK_ANSI_K), ("l", kVK_ANSI_L),
            ("m", kVK_ANSI_M), ("n", kVK_ANSI_N), ("o", kVK_ANSI_O),
            ("p", kVK_ANSI_P), ("q", kVK_ANSI_Q), ("r", kVK_ANSI_R),
            ("s", kVK_ANSI_S), ("t", kVK_ANSI_T), ("u", kVK_ANSI_U),
            ("v", kVK_ANSI_V), ("w", kVK_ANSI_W), ("x", kVK_ANSI_X),
            ("y", kVK_ANSI_Y), ("z", kVK_ANSI_Z),
        ]

        for (char, code) in letterCodes {
            // Lowercase
            map[char.asciiValue!] = KeyMapping(
                keyCode: CGKeyCode(code),
                modifiers: []
            )
            // Uppercase (shift modifier)
            let upper = Character(char.uppercased())
            map[upper.asciiValue!] = KeyMapping(
                keyCode: CGKeyCode(code),
                modifiers: .maskShift
            )
        }

        // Numbers
        let numberCodes: [(Character, Int)] = [
            ("0", kVK_ANSI_0), ("1", kVK_ANSI_1), ("2", kVK_ANSI_2),
            ("3", kVK_ANSI_3), ("4", kVK_ANSI_4), ("5", kVK_ANSI_5),
            ("6", kVK_ANSI_6), ("7", kVK_ANSI_7), ("8", kVK_ANSI_8),
            ("9", kVK_ANSI_9),
        ]

        for (char, code) in numberCodes {
            map[char.asciiValue!] = KeyMapping(
                keyCode: CGKeyCode(code),
                modifiers: []
            )
        }

        // Common punctuation
        map[Character(" ").asciiValue!] = KeyMapping(
            keyCode: CGKeyCode(kVK_Space), modifiers: []
        )
        map[Character("\n").asciiValue!] = KeyMapping(
            keyCode: CGKeyCode(kVK_Return), modifiers: []
        )
        map[Character("\t").asciiValue!] = KeyMapping(
            keyCode: CGKeyCode(kVK_Tab), modifiers: []
        )
        map[Character(".").asciiValue!] = KeyMapping(
            keyCode: CGKeyCode(kVK_ANSI_Period), modifiers: []
        )
        map[Character(",").asciiValue!] = KeyMapping(
            keyCode: CGKeyCode(kVK_ANSI_Comma), modifiers: []
        )
        map[Character("-").asciiValue!] = KeyMapping(
            keyCode: CGKeyCode(kVK_ANSI_Minus), modifiers: []
        )
        map[Character("=").asciiValue!] = KeyMapping(
            keyCode: CGKeyCode(kVK_ANSI_Equal), modifiers: []
        )
        map[Character("/").asciiValue!] = KeyMapping(
            keyCode: CGKeyCode(kVK_ANSI_Slash), modifiers: []
        )
        map[Character(";").asciiValue!] = KeyMapping(
            keyCode: CGKeyCode(kVK_ANSI_Semicolon), modifiers: []
        )
        map[Character("'").asciiValue!] = KeyMapping(
            keyCode: CGKeyCode(kVK_ANSI_Quote), modifiers: []
        )
        map[Character("[").asciiValue!] = KeyMapping(
            keyCode: CGKeyCode(kVK_ANSI_LeftBracket), modifiers: []
        )
        map[Character("]").asciiValue!] = KeyMapping(
            keyCode: CGKeyCode(kVK_ANSI_RightBracket), modifiers: []
        )
        map[Character("\\").asciiValue!] = KeyMapping(
            keyCode: CGKeyCode(kVK_ANSI_Backslash), modifiers: []
        )
        map[Character("`").asciiValue!] = KeyMapping(
            keyCode: CGKeyCode(kVK_ANSI_Grave), modifiers: []
        )

        // Shifted punctuation
        map[Character("!").asciiValue!] = KeyMapping(
            keyCode: CGKeyCode(kVK_ANSI_1), modifiers: .maskShift
        )
        map[Character("@").asciiValue!] = KeyMapping(
            keyCode: CGKeyCode(kVK_ANSI_2), modifiers: .maskShift
        )
        map[Character("#").asciiValue!] = KeyMapping(
            keyCode: CGKeyCode(kVK_ANSI_3), modifiers: .maskShift
        )
        map[Character("$").asciiValue!] = KeyMapping(
            keyCode: CGKeyCode(kVK_ANSI_4), modifiers: .maskShift
        )
        map[Character("%").asciiValue!] = KeyMapping(
            keyCode: CGKeyCode(kVK_ANSI_5), modifiers: .maskShift
        )
        map[Character("^").asciiValue!] = KeyMapping(
            keyCode: CGKeyCode(kVK_ANSI_6), modifiers: .maskShift
        )
        map[Character("&").asciiValue!] = KeyMapping(
            keyCode: CGKeyCode(kVK_ANSI_7), modifiers: .maskShift
        )
        map[Character("*").asciiValue!] = KeyMapping(
            keyCode: CGKeyCode(kVK_ANSI_8), modifiers: .maskShift
        )
        map[Character("(").asciiValue!] = KeyMapping(
            keyCode: CGKeyCode(kVK_ANSI_9), modifiers: .maskShift
        )
        map[Character(")").asciiValue!] = KeyMapping(
            keyCode: CGKeyCode(kVK_ANSI_0), modifiers: .maskShift
        )
        map[Character("?").asciiValue!] = KeyMapping(
            keyCode: CGKeyCode(kVK_ANSI_Slash), modifiers: .maskShift
        )
        map[Character(":").asciiValue!] = KeyMapping(
            keyCode: CGKeyCode(kVK_ANSI_Semicolon), modifiers: .maskShift
        )
        map[Character("\"").asciiValue!] = KeyMapping(
            keyCode: CGKeyCode(kVK_ANSI_Quote), modifiers: .maskShift
        )
        map[Character("<").asciiValue!] = KeyMapping(
            keyCode: CGKeyCode(kVK_ANSI_Comma), modifiers: .maskShift
        )
        map[Character(">").asciiValue!] = KeyMapping(
            keyCode: CGKeyCode(kVK_ANSI_Period), modifiers: .maskShift
        )
        map[Character("_").asciiValue!] = KeyMapping(
            keyCode: CGKeyCode(kVK_ANSI_Minus), modifiers: .maskShift
        )
        map[Character("+").asciiValue!] = KeyMapping(
            keyCode: CGKeyCode(kVK_ANSI_Equal), modifiers: .maskShift
        )
        map[Character("~").asciiValue!] = KeyMapping(
            keyCode: CGKeyCode(kVK_ANSI_Grave), modifiers: .maskShift
        )
        map[Character("{").asciiValue!] = KeyMapping(
            keyCode: CGKeyCode(kVK_ANSI_LeftBracket), modifiers: .maskShift
        )
        map[Character("}").asciiValue!] = KeyMapping(
            keyCode: CGKeyCode(kVK_ANSI_RightBracket), modifiers: .maskShift
        )
        map[Character("|").asciiValue!] = KeyMapping(
            keyCode: CGKeyCode(kVK_ANSI_Backslash), modifiers: .maskShift
        )

        return map
    }()
}
```

> ⚠️ **Warning**: Key code mappings assume a US keyboard layout. For international
> keyboard layouts, CGEvent's Unicode string override (set via
> `keyboardSetUnicodeString`) is essential. VaulType always sets the Unicode string
> on every CGEvent to ensure correct character output regardless of the user's keyboard
> layout.

---

## Clipboard-Paste Method Implementation

### NSPasteboard Usage

The clipboard-paste method bypasses keystroke simulation entirely. Instead, it writes
text to the system pasteboard and simulates a Command+V keystroke to paste it. This is
dramatically faster for long text and handles Unicode perfectly.

```swift
import AppKit
import CoreGraphics
import Carbon.HIToolbox

/// Clipboard-based text injection with pasteboard preservation.
final class ClipboardInjector: @unchecked Sendable {

    private let pasteboard = NSPasteboard.general
    private let eventSource: CGEventSource?

    init() {
        self.eventSource = CGEventSource(stateID: .combinedSessionState)
    }

    /// Injects text via clipboard paste with automatic clipboard preservation.
    /// - Parameters:
    ///   - text: The text to inject into the active text field.
    ///   - restoreDelay: Time to wait before restoring the original clipboard contents.
    func injectText(_ text: String, restoreDelay: UInt64 = 100_000_000) async throws {
        // 1. Save current clipboard contents
        let savedContents = ClipboardPreserver.save(from: pasteboard)

        // 2. Write our text to the pasteboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 3. Brief delay to ensure pasteboard is ready
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms

        // 4. Simulate Command+V
        try simulatePaste()

        // 5. Wait for the paste to be processed by the target app
        try await Task.sleep(nanoseconds: restoreDelay)

        // 6. Restore original clipboard contents
        ClipboardPreserver.restore(savedContents, to: pasteboard)
    }

    /// Simulates the Command+V keystroke to trigger paste in the active application.
    private func simulatePaste() throws {
        guard let keyDown = CGEvent(
            keyboardEventSource: eventSource,
            virtualKey: CGKeyCode(kVK_ANSI_V),
            keyDown: true
        ) else {
            throw InjectionError.eventCreationFailed
        }

        guard let keyUp = CGEvent(
            keyboardEventSource: eventSource,
            virtualKey: CGKeyCode(kVK_ANSI_V),
            keyDown: false
        ) else {
            throw InjectionError.eventCreationFailed
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
```

### Simulating Command-V

The paste simulation requires careful handling of modifier flags:

```swift
extension ClipboardInjector {

    /// Posts a full Command+V sequence with proper modifier key event ordering.
    /// Some apps require explicit modifier key down/up events in addition to flags.
    func simulatePasteExplicit() throws {
        // Post Command key down
        guard let cmdDown = CGEvent(
            keyboardEventSource: eventSource,
            virtualKey: CGKeyCode(kVK_Command),
            keyDown: true
        ) else {
            throw InjectionError.eventCreationFailed
        }
        cmdDown.flags = .maskCommand
        cmdDown.post(tap: .cghidEventTap)

        // Post V key down with Command flag
        guard let vDown = CGEvent(
            keyboardEventSource: eventSource,
            virtualKey: CGKeyCode(kVK_ANSI_V),
            keyDown: true
        ) else {
            throw InjectionError.eventCreationFailed
        }
        vDown.flags = .maskCommand
        vDown.post(tap: .cghidEventTap)

        // Post V key up with Command flag
        guard let vUp = CGEvent(
            keyboardEventSource: eventSource,
            virtualKey: CGKeyCode(kVK_ANSI_V),
            keyDown: false
        ) else {
            throw InjectionError.eventCreationFailed
        }
        vUp.flags = .maskCommand
        vUp.post(tap: .cghidEventTap)

        // Post Command key up
        guard let cmdUp = CGEvent(
            keyboardEventSource: eventSource,
            virtualKey: CGKeyCode(kVK_Command),
            keyDown: false
        ) else {
            throw InjectionError.eventCreationFailed
        }
        cmdUp.flags = []
        cmdUp.post(tap: .cghidEventTap)
    }
}
```

> 💡 **Tip**: Most apps only need the simple paste simulation (setting `.maskCommand`
> on the V key events). The explicit version with separate Command key events is needed
> for some terminal emulators and custom input frameworks.

### When to Use Clipboard vs CGEvent

The injection router uses the following decision matrix:

| Criteria | CGEvent Preferred | Clipboard Preferred |
|----------|-------------------|---------------------|
| Text length | < 64 characters | >= 64 characters |
| Character set | ASCII only | Unicode, emoji, CJK |
| Target app | Standard text fields | Rich text editors |
| User typing | User may be typing | User finished speaking |
| Clipboard importance | N/A | User's clipboard can be briefly interrupted |
| Terminal apps | Avoid (special chars) | Preferred (most terminals) |
| Speed requirement | Acceptable latency | Minimal latency needed |

### Implementation Details

```swift
/// Determines the optimal injection method for the given context.
struct InjectionMethodSelector {

    struct InjectionContext {
        let text: String
        let targetBundleID: String?
        let targetRole: String?
        let userPreference: InjectionMethod?
    }

    enum InjectionMethod {
        case cgEvent
        case clipboard
        case clipboardExplicit  // For apps that need explicit modifier events
    }

    /// Selects the best injection method for the given context.
    static func selectMethod(for context: InjectionContext) -> InjectionMethod {
        // User preference always wins
        if let preference = context.userPreference {
            return preference
        }

        // Per-app overrides
        if let bundleID = context.targetBundleID,
           let override = appOverrides[bundleID] {
            return override
        }

        // Heuristic selection
        let text = context.text

        // Clipboard for long text
        if text.count > 64 {
            return .clipboard
        }

        // Clipboard for non-ASCII
        if !text.allSatisfy({ $0.isASCII }) {
            return .clipboard
        }

        // CGEvent for short ASCII text
        return .cgEvent
    }

    /// Per-app injection method overrides.
    private static let appOverrides: [String: InjectionMethod] = [
        // Terminals generally prefer clipboard
        "com.apple.Terminal": .clipboardExplicit,
        "com.googlecode.iterm2": .clipboard,
        "dev.warp.Warp-Stable": .clipboard,
        "io.alacritty": .clipboard,

        // Electron apps work better with clipboard
        "com.microsoft.VSCode": .clipboard,
        "com.tinyspeck.slackmacgap": .clipboard,
        "com.hnc.Discord": .clipboard,

        // Some apps need explicit modifier events
        "com.jetbrains.intellij": .clipboardExplicit,
    ]
}
```

---

## Clipboard Preservation Strategy

### Saving Current Clipboard Contents

Before using the clipboard for injection, VaulType preserves the user's existing
clipboard contents. The pasteboard can contain multiple item types simultaneously
(text, RTF, images, files, custom data), all of which must be saved and restored.

```swift
import AppKit

/// Represents saved clipboard contents across all types.
struct SavedClipboardContents {
    /// Each item is an array of type-data pairs representing one pasteboard item.
    let items: [[(NSPasteboard.PasteboardType, Data)]]
    let changeCount: Int
}

/// Handles saving and restoring clipboard contents across injection operations.
enum ClipboardPreserver {

    /// Saves all current pasteboard contents, including all types per item.
    static func save(from pasteboard: NSPasteboard) -> SavedClipboardContents {
        let changeCount = pasteboard.changeCount
        var items: [[(NSPasteboard.PasteboardType, Data)]] = []

        for item in pasteboard.pasteboardItems ?? [] {
            var typeDataPairs: [(NSPasteboard.PasteboardType, Data)] = []

            for type in item.types {
                if let data = item.data(forType: type) {
                    typeDataPairs.append((type, data))
                }
            }

            if !typeDataPairs.isEmpty {
                items.append(typeDataPairs)
            }
        }

        return SavedClipboardContents(items: items, changeCount: changeCount)
    }

    /// Restores previously saved pasteboard contents.
    /// Only restores if the pasteboard hasn't been modified by another app since saving.
    static func restore(_ saved: SavedClipboardContents, to pasteboard: NSPasteboard) {
        // Safety check: if the clipboard was modified by something other than us
        // (changeCount jumped by more than 1), don't overwrite the new contents.
        // Our injection changed it once (+1), so we expect changeCount = saved + 1.
        let expectedChangeCount = saved.changeCount + 1
        guard pasteboard.changeCount == expectedChangeCount else {
            // Another app modified the clipboard; preserve the new content
            return
        }

        pasteboard.clearContents()

        for itemTypes in saved.items {
            let item = NSPasteboardItem()
            for (type, data) in itemTypes {
                item.setData(data, forType: type)
            }
            pasteboard.writeObjects([item])
        }
    }
}
```

### Restoring After Injection

The restoration timing is critical. Too early and the paste hasn't completed; too late
and the user notices their clipboard was changed:

```swift
extension ClipboardInjector {

    /// Injects text with smart clipboard restoration timing.
    func injectWithSmartRestore(_ text: String) async throws {
        let savedContents = ClipboardPreserver.save(from: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        try await Task.sleep(nanoseconds: 10_000_000) // 10ms settle time

        try simulatePaste()

        // Wait for paste processing.
        // The delay scales with text length because larger pastes take longer
        // for apps to process.
        let baseDelay: UInt64 = 50_000_000 // 50ms minimum
        let perCharDelay: UInt64 = 10_000   // 0.01ms per character
        let totalDelay = baseDelay + UInt64(text.count) * perCharDelay
        let cappedDelay = min(totalDelay, 500_000_000) // cap at 500ms

        try await Task.sleep(nanoseconds: cappedDelay)

        ClipboardPreserver.restore(savedContents, to: pasteboard)
    }
}
```

### Handling Different Pasteboard Types

The macOS pasteboard supports numerous data types. VaulType preserves all of them:

| Pasteboard Type | Constant | Description |
|---|---|---|
| Plain text | `.string` | UTF-8 string data |
| RTF | `.rtf` | Rich Text Format data |
| RTFD | `.rtfd` | RTF with attachments |
| HTML | `.html` | HTML string content |
| PDF | `.pdf` | PDF document data |
| PNG | `.png` | PNG image data |
| TIFF | `.tiff` | TIFF image data |
| File URL | `.fileURL` | File system path reference |
| URL | `.URL` | Web URL |
| Color | `NSPasteboard.PasteboardType("com.apple.cocoa.pasteboard.color")` | NSColor data |

```swift
/// Extended pasteboard type handling with type-specific validation.
extension ClipboardPreserver {

    /// Validates that saved contents can be properly restored.
    static func validate(_ saved: SavedClipboardContents) -> Bool {
        for itemTypes in saved.items {
            for (type, data) in itemTypes {
                // Verify data integrity for known types
                switch type {
                case .string:
                    guard String(data: data, encoding: .utf8) != nil else {
                        return false
                    }
                case .rtf:
                    guard let _ = try? NSAttributedString(
                        data: data,
                        options: [.documentType: NSAttributedString.DocumentType.rtf],
                        documentAttributes: nil
                    ) else {
                        return false
                    }
                case .png, .tiff:
                    guard NSImage(data: data) != nil else {
                        return false
                    }
                default:
                    // Unknown types are preserved as raw data
                    break
                }
            }
        }
        return true
    }
}
```

### Edge Cases

Several edge cases require special handling in clipboard preservation:

> ⚠️ **Warning**: Be aware of these clipboard preservation edge cases:
>
> 1. **Empty clipboard**: If the user's clipboard is empty before injection, do not
>    attempt to restore (there is nothing to restore).
> 2. **Large clipboard contents**: Images and files can be very large. VaulType caps
>    clipboard preservation at 50MB to avoid memory pressure.
> 3. **Transient pasteboard types**: Some apps use custom transient types that cannot
>    be meaningfully saved/restored (e.g., drag session data).
> 4. **Clipboard managers**: Third-party clipboard managers (Paste, Maccy, CopyClip)
>    may record VaulType's injection as a clipboard entry. There is no reliable way to
>    prevent this.
> 5. **Rapid sequential injections**: If multiple injections occur in quick succession,
>    each must complete its full save-inject-restore cycle before the next begins.
> 6. **Concealed pasteboard types**: Some apps use `NSPasteboard.PasteboardType` values
>    marked as concealed. These are preserved as opaque data.

```swift
/// Manages clipboard injection with proper serialization of sequential operations.
actor ClipboardInjectionQueue {

    private let injector = ClipboardInjector()
    private var isProcessing = false
    private var queue: [String] = []

    /// Enqueues text for clipboard injection. Operations are serialized.
    func enqueue(_ text: String) async throws {
        queue.append(text)
        try await processQueue()
    }

    private func processQueue() async throws {
        guard !isProcessing else { return }
        isProcessing = true

        defer { isProcessing = false }

        while !queue.isEmpty {
            let text = queue.removeFirst()
            try await injector.injectWithSmartRestore(text)

            // Small gap between sequential injections to allow the target app
            // to fully process each paste
            if !queue.isEmpty {
                try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            }
        }
    }
}
```

---

## Active App and Text Field Detection

### AXUIElement API

VaulType uses the macOS Accessibility API (`AXUIElement`) to determine what application
is frontmost, which element is focused, and whether that element accepts text input.
This information drives injection routing decisions.

```
Accessibility Hierarchy:
========================

  AXApplication (frontmost app)
       |
       +-- AXWindow (key window)
              |
              +-- AXGroup / AXScrollArea / ...
                     |
                     +-- AXTextArea / AXTextField (focused element)
                            |
                            +-- AXValue (current text content)
                            +-- AXSelectedTextRange
                            +-- AXInsertionPointLineNumber
```

> 🔒 **Security**: The Accessibility API requires explicit user consent. VaulType must
> be listed in System Settings > Privacy & Security > Accessibility. Without this
> permission, all `AXUIElement` queries return `kAXErrorAPIDisabled`. See
> [PERMISSIONS.md](PERMISSIONS.md) for details on requesting and verifying this permission.

### Detecting the Focused Element

```swift
import ApplicationServices

/// Provides access to the currently focused UI element via the Accessibility API.
final class AccessibilityDetector {

    /// Returns the currently focused UI element across all applications.
    /// - Returns: The focused AXUIElement, or nil if none is focused or access is denied.
    func focusedElement() -> AXUIElement? {
        // Get the frontmost application
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Query the focused UI element of the frontmost application
        var focusedValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )

        guard result == .success else {
            return nil
        }

        return (focusedValue as! AXUIElement)
    }

    /// Returns detailed information about the focused text element.
    struct FocusedTextInfo {
        let element: AXUIElement
        let role: String
        let value: String?
        let selectedRange: CFRange?
        let isEditable: Bool
        let bundleIdentifier: String?
        let appName: String?
    }

    /// Gathers comprehensive information about the currently focused text element.
    func focusedTextInfo() -> FocusedTextInfo? {
        guard let element = focusedElement() else {
            return nil
        }

        let role = attribute(of: element, key: kAXRoleAttribute) as? String ?? ""
        let value = attribute(of: element, key: kAXValueAttribute) as? String
        let isEditable = !(attribute(of: element, key: kAXIsReadOnlyAttribute) as? Bool ?? false)

        var selectedRange: CFRange? = nil
        if let rangeValue = attribute(of: element, key: kAXSelectedTextRangeAttribute) {
            let axValue = rangeValue as! AXValue
            var range = CFRange(location: 0, length: 0)
            if AXValueGetValue(axValue, .cfRange, &range) {
                selectedRange = range
            }
        }

        let app = NSWorkspace.shared.frontmostApplication
        let bundleID = app?.bundleIdentifier
        let appName = app?.localizedName

        return FocusedTextInfo(
            element: element,
            role: role,
            value: value,
            selectedRange: selectedRange,
            isEditable: isEditable,
            bundleIdentifier: bundleID,
            appName: appName
        )
    }

    /// Helper to query a single accessibility attribute.
    private func attribute(of element: AXUIElement, key: String) -> AnyObject? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, key as CFString, &value)
        return result == .success ? value : nil
    }
}
```

### Checking If Element Accepts Text Input

Not all focused elements accept text input. VaulType must verify the element's role
and editability before attempting injection:

```swift
extension AccessibilityDetector {

    /// Roles that typically accept text input.
    private static let textInputRoles: Set<String> = [
        "AXTextArea",
        "AXTextField",
        "AXComboBox",
        "AXSearchField",
        "AXTextMarkedContent",
    ]

    /// Roles that might accept text input depending on context.
    private static let conditionalTextRoles: Set<String> = [
        "AXWebArea",        // Browsers — depends on focused sub-element
        "AXGroup",          // Some custom controls
        "AXCell",           // Spreadsheet cells
        "AXStaticText",     // Some editable static text fields
    ]

    /// Determines whether the focused element can receive text injection.
    func canAcceptTextInput() -> Bool {
        guard let info = focusedTextInfo() else {
            return false
        }

        // Direct text input roles
        if Self.textInputRoles.contains(info.role) {
            return info.isEditable
        }

        // Conditional roles need deeper inspection
        if Self.conditionalTextRoles.contains(info.role) {
            return checkConditionalTextInput(element: info.element, role: info.role)
        }

        // For unknown roles, check if the element has AXValue and is not read-only
        if info.value != nil && info.isEditable {
            return true
        }

        return false
    }

    /// Performs deeper inspection for elements with conditional text input support.
    private func checkConditionalTextInput(element: AXUIElement, role: String) -> Bool {
        switch role {
        case "AXWebArea":
            // For web areas, check if there is a focused sub-element that is editable
            if let focused = attribute(of: element, key: kAXFocusedUIElementAttribute) as! AXUIElement? {
                let subRole = attribute(of: focused, key: kAXRoleAttribute) as? String ?? ""
                return Self.textInputRoles.contains(subRole)
            }
            return false

        case "AXCell":
            // Spreadsheet cells are editable when in edit mode
            let isEditing = attribute(of: element, key: "AXIsEditing") as? Bool ?? false
            return isEditing

        default:
            return false
        }
    }
}
```

### Getting Cursor Position

Knowing the cursor position allows VaulType to provide visual feedback and handle
text insertion accurately:

```swift
extension AccessibilityDetector {

    /// Cursor position information in the focused text element.
    struct CursorInfo {
        let insertionPoint: Int           // Character offset in the text
        let lineNumber: Int?              // Line number if available
        let screenPosition: CGPoint?      // Screen coordinates of the cursor
        let selectedTextRange: CFRange?   // Selection range if text is selected
        let selectedText: String?         // The actual selected text
    }

    /// Retrieves cursor position information from the focused text element.
    func cursorInfo() -> CursorInfo? {
        guard let element = focusedElement() else {
            return nil
        }

        // Get the selected text range (insertion point = range with length 0)
        var range = CFRange(location: 0, length: 0)
        if let rangeValue = attribute(of: element, key: kAXSelectedTextRangeAttribute) {
            let axValue = rangeValue as! AXValue
            AXValueGetValue(axValue, .cfRange, &range)
        }

        // Get line number
        let lineNumber = attribute(of: element, key: "AXInsertionPointLineNumber") as? Int

        // Get screen position of the insertion point
        var screenPosition: CGPoint? = nil
        var posValue: AnyObject?
        let paramResult = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXBoundsForRange" as CFString,
            AXValueCreate(.cfRange, &range)! as CFTypeRef,
            &posValue
        )
        if paramResult == .success, let axPos = posValue {
            var rect = CGRect.zero
            AXValueGetValue(axPos as! AXValue, .cgRect, &rect)
            screenPosition = rect.origin
        }

        // Get selected text if any
        let selectedText: String?
        if range.length > 0 {
            selectedText = attribute(of: element, key: kAXSelectedTextAttribute) as? String
        } else {
            selectedText = nil
        }

        return CursorInfo(
            insertionPoint: range.location,
            lineNumber: lineNumber,
            screenPosition: screenPosition,
            selectedTextRange: range.length > 0 ? range : nil,
            selectedText: selectedText
        )
    }
}
```

### Frontmost App Detection

VaulType monitors the frontmost application to apply per-app injection strategies:

```swift
import Combine

/// Monitors the frontmost application and publishes changes.
final class FrontmostAppMonitor: ObservableObject {

    @Published var currentApp: NSRunningApplication?
    @Published var currentBundleID: String?

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Subscribe to app activation notifications
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .compactMap { notification in
                notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] app in
                self?.currentApp = app
                self?.currentBundleID = app.bundleIdentifier
            }
            .store(in: &cancellables)

        // Set initial value
        currentApp = NSWorkspace.shared.frontmostApplication
        currentBundleID = currentApp?.bundleIdentifier
    }

    /// Returns the bundle identifier of the frontmost application.
    /// Falls back to process-based detection if NSWorkspace is unavailable.
    static func frontmostBundleID() -> String? {
        if let app = NSWorkspace.shared.frontmostApplication {
            return app.bundleIdentifier
        }

        // Fallback: query the system for the frontmost PID
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApp
        )

        guard result == .success else { return nil }

        var pid: pid_t = 0
        AXUIElementGetPid(focusedApp as! AXUIElement, &pid)

        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }
}
```

---

## Handling Special Characters and Unicode

### Emoji Injection

Emoji characters cannot be represented by single key codes. VaulType uses the Unicode
string override on CGEvents or falls back to clipboard injection:

```swift
extension CGEventKeystrokeInjector {

    /// Injects a single emoji character via CGEvent with Unicode string override.
    func injectEmoji(_ emoji: Character) throws {
        let utf16 = Array(String(emoji).utf16)

        guard let keyDown = CGEvent(
            keyboardEventSource: eventSource,
            virtualKey: CGKeyCode(kVK_ANSI_A), // Carrier key code
            keyDown: true
        ) else {
            throw InjectionError.eventCreationFailed
        }

        guard let keyUp = CGEvent(
            keyboardEventSource: eventSource,
            virtualKey: CGKeyCode(kVK_ANSI_A),
            keyDown: false
        ) else {
            throw InjectionError.eventCreationFailed
        }

        // Set the Unicode string on the key event.
        // This overrides the key code and produces the exact character specified.
        keyDown.keyboardSetUnicodeString(
            stringLength: utf16.count,
            unicodeString: utf16
        )
        keyUp.keyboardSetUnicodeString(
            stringLength: utf16.count,
            unicodeString: utf16
        )

        keyDown.post(tap: tapLocation)
        keyUp.post(tap: tapLocation)
    }
}
```

> ⚠️ **Warning**: Some emoji are composed of multiple Unicode code points joined by
> Zero Width Joiners (ZWJ). For example, the family emoji (U+1F468 U+200D U+1F469
> U+200D U+1F467) has 5 code points. `keyboardSetUnicodeString` supports a maximum
> of 20 UTF-16 code units. Most emoji fit within this limit, but extremely complex
> ZWJ sequences may not. VaulType falls back to clipboard injection for emoji that
> exceed the CGEvent Unicode string limit.

### CJK Characters

Chinese, Japanese, and Korean characters are fully supported through the Unicode string
override mechanism. However, CJK input presents unique challenges:

```swift
extension CGEventKeystrokeInjector {

    /// Injects CJK text with proper handling for multi-byte characters.
    /// CJK characters require clipboard injection when the system has an active
    /// IME (Input Method Editor) that might intercept CGEvents.
    func injectCJKText(_ text: String, forceClipboard: Bool = false) async throws {
        // Check if an IME is currently active
        let inputSource = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let sourceID = TISGetInputSourceProperty(
            inputSource,
            kTISPropertyInputSourceID
        )

        let sourceIDString = Unmanaged<CFString>
            .fromOpaque(sourceID!)
            .takeUnretainedValue() as String

        let isIMEActive = sourceIDString.contains("inputmethod") ||
                          sourceIDString.contains("SCIM") ||
                          sourceIDString.contains("Kotoeri") ||
                          sourceIDString.contains("Korean")

        if isIMEActive || forceClipboard {
            // IME may intercept CGEvent keystrokes; use clipboard instead
            let clipboardInjector = ClipboardInjector()
            try await clipboardInjector.injectText(text)
        } else {
            // Direct CGEvent injection with Unicode override
            try await injectText(text, interKeyDelay: 2_000_000)
        }
    }
}
```

> ℹ️ **Info**: When a CJK Input Method Editor (IME) is active, it intercepts raw key
> events and presents a candidate selection UI. CGEvent keystrokes would trigger the IME
> rather than producing the intended characters. VaulType detects active IMEs and
> automatically switches to clipboard injection for CJK text.

### Diacritics and Combining Characters

Characters with diacritics (e.g., e, n, u) can be either precomposed (NFC) or decomposed
(NFD) in Unicode. macOS internally uses NFD, but most applications expect NFC:

```swift
extension String {
    /// Normalizes the string to NFC form for consistent text injection.
    /// macOS uses NFD internally, but most apps and text fields expect NFC.
    var normalizedForInjection: String {
        return self.precomposedStringWithCanonicalMapping // NFC
    }
}

extension CGEventKeystrokeInjector {

    /// Injects text with proper Unicode normalization.
    func injectNormalized(_ text: String) async throws {
        let normalized = text.normalizedForInjection
        try await injectText(normalized)
    }
}
```

### Special Symbols

Mathematical symbols, currency signs, arrows, and other special characters are handled
through the same Unicode string override mechanism:

| Category | Examples | CGEvent Support | Notes |
|----------|----------|-----------------|-------|
| Currency | $ EUR GBP JPY | Yes | Most are single code points |
| Math | +- x / = | Yes | Use Unicode string override |
| Arrows | Left Right Up Down | Yes | Single code points |
| Box Drawing | --- | Yes | Single code points |
| Ligatures | fi, fl | Yes | Should use precomposed forms |
| Musical | Crotchet Quaver | Yes | Single code points in SMP |
| Braille | ... | Yes | Single code points |

### Newlines and Tabs

Newlines and tabs have special key codes and may be interpreted differently by
applications:

```swift
extension KeyCodeMapper {

    /// Special whitespace character handling.
    static func whitespaceKeystroke(for character: Character) -> Keystroke? {
        switch character {
        case "\n", "\r":
            // Return/Enter key
            return Keystroke(keyCode: CGKeyCode(kVK_Return), modifiers: [])

        case "\r\n":
            // Windows-style line ending: single Return key press
            return Keystroke(keyCode: CGKeyCode(kVK_Return), modifiers: [])

        case "\t":
            // Tab key
            return Keystroke(keyCode: CGKeyCode(kVK_Tab), modifiers: [])

        case "\u{00A0}":
            // Non-breaking space: Option+Space on macOS
            return Keystroke(
                keyCode: CGKeyCode(kVK_Space),
                modifiers: .maskAlternate,
                character: character
            )

        default:
            return nil
        }
    }
}
```

> ⚠️ **Warning**: In terminal applications, the Return key sends different escape
> sequences depending on the terminal mode. In normal mode, Return sends `\r` (0x0D).
> In some terminal apps, pasting text with newlines can execute commands. VaulType
> warns the user before injecting multi-line text into detected terminal applications.

---

## Per-App Injection Quirks and Workarounds

### App Compatibility Table

| Application | Bundle ID | CGEvent | Clipboard | Notes |
|---|---|---|---|---|
| **Native macOS** | | | | |
| TextEdit | `com.apple.TextEdit` | Excellent | Excellent | Full support |
| Notes | `com.apple.Notes` | Good | Excellent | Rich text may strip formatting |
| Pages | `com.apple.iWork.Pages` | Good | Excellent | Use clipboard for styled text |
| Mail | `com.apple.mail` | Good | Excellent | Compose window only |
| Messages | `com.apple.MobileSMS` | Good | Good | Emoji via clipboard only |
| Spotlight | `com.apple.Spotlight` | Good | Poor | Clipboard paste may dismiss |
| **Terminals** | | | | |
| Terminal.app | `com.apple.Terminal` | Limited | Good | See Terminal section |
| iTerm2 | `com.googlecode.iterm2` | Limited | Excellent | Bracketed paste support |
| Warp | `dev.warp.Warp-Stable` | Limited | Good | Custom input handling |
| Alacritty | `io.alacritty` | Limited | Good | GPU-rendered, minimal AX |
| **Electron Apps** | | | | |
| VS Code | `com.microsoft.VSCode` | Fair | Good | See Electron section |
| Slack | `com.tinyspeck.slackmacgap` | Fair | Good | Message compose field |
| Discord | `com.hnc.Discord` | Fair | Good | Similar to Slack |
| Notion | `notion.id` | Fair | Good | Rich text editor quirks |
| Obsidian | `md.obsidian` | Fair | Good | Markdown editor |
| **Browsers** | | | | |
| Safari | `com.apple.Safari` | Good | Good | See Browser section |
| Chrome | `com.google.Chrome` | Fair | Good | Chromium input quirks |
| Firefox | `org.mozilla.firefox` | Fair | Good | Gecko input handling |
| Arc | `company.thebrowser.Browser` | Fair | Good | Chromium-based |
| **Productivity** | | | | |
| Microsoft Word | `com.microsoft.Word` | Fair | Good | Use clipboard for long text |
| Excel | `com.microsoft.Excel` | Fair | Good | Cell edit mode required |
| Google Docs (browser) | N/A | Poor | Good | contentEditable quirks |
| **IDEs** | | | | |
| Xcode | `com.apple.dt.Xcode` | Good | Good | Source editor works well |
| IntelliJ | `com.jetbrains.intellij` | Fair | Good | Custom editor framework |
| Sublime Text | `com.sublimetext.4` | Good | Excellent | Excellent CGEvent support |

Legend:
- **Excellent**: Full support, no known issues
- **Good**: Works reliably with minor considerations
- **Fair**: Works but with known quirks requiring workarounds
- **Limited**: Significant issues, alternative method preferred
- **Poor**: Not recommended, frequent failures

### Known Issues and Solutions

```swift
/// Per-app workarounds for known injection issues.
enum AppWorkarounds {

    /// Applies any necessary pre-injection workarounds for the target app.
    static func preInjection(bundleID: String) async {
        switch bundleID {
        case "com.apple.Spotlight":
            // Spotlight can lose focus during clipboard operations.
            // Add a small delay to ensure the search field is stable.
            try? await Task.sleep(nanoseconds: 50_000_000)

        case "com.microsoft.Excel":
            // Excel requires the cell to be in edit mode (double-clicked or F2).
            // We check if the focused element is an AXCell and it is not yet
            // in editing mode. If so, we send an F2 keystroke first.
            break

        case "notion.id":
            // Notion has a custom block editor that intercepts certain keystrokes.
            // Using clipboard paste avoids issues with Notion's input interception.
            break

        default:
            break
        }
    }

    /// Applies any necessary post-injection cleanup for the target app.
    static func postInjection(bundleID: String) async {
        switch bundleID {
        case "com.tinyspeck.slackmacgap":
            // Slack sometimes doesn't update its message preview after paste.
            // A brief delay and then a no-op event can trigger a refresh.
            try? await Task.sleep(nanoseconds: 20_000_000)

        case "com.hnc.Discord":
            // Similar to Slack, Discord's message input may need a nudge.
            try? await Task.sleep(nanoseconds: 20_000_000)

        default:
            break
        }
    }
}
```

---

## Terminal Compatibility

Terminal applications have unique text injection challenges because they process input
at the TTY (pseudo-terminal) level rather than through the standard macOS text input
system.

```
Standard App Text Flow:
  CGEvent -> WindowServer -> NSEvent -> NSTextInputContext -> NSTextView

Terminal App Text Flow:
  CGEvent -> WindowServer -> NSEvent -> Terminal Emulator -> PTY -> Shell -> Program
                                              |
                                              +-- Escape sequence interpretation
                                              +-- Bracketed paste mode handling
                                              +-- Line editing (readline/zle)
```

### Terminal.app

Apple's built-in Terminal.app processes input through its own event handling:

- **CGEvent injection**: Works for simple ASCII text but special characters may trigger
  unexpected terminal escape sequences. Tab triggers command completion. Return executes
  the current line. Backslash, quotes, and other shell metacharacters are not escaped.
- **Clipboard paste**: Works well. Terminal.app wraps pasted text in bracketed paste
  escape sequences (`\e[200~...\e[201~`) when the running program supports it.
- **Recommendation**: Use clipboard paste for Terminal.app. For safety, VaulType wraps
  the pasted text in single quotes if it contains shell metacharacters and the focused
  element appears to be a shell prompt.

```swift
/// Terminal-specific injection handling.
struct TerminalInjectionStrategy {

    /// Characters that have special meaning in shell contexts.
    private static let shellMetacharacters: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "|&;()<>{}[]$`!#*?~\"'\\")
        set.insert(charactersIn: "\n\r")
        return set
    }()

    /// Checks if text contains characters that could be dangerous in a shell.
    static func containsShellMetacharacters(_ text: String) -> Bool {
        return text.unicodeScalars.contains { shellMetacharacters.contains($0) }
    }

    /// Returns whether the text contains newlines that could execute commands.
    static func containsNewlines(_ text: String) -> Bool {
        return text.contains("\n") || text.contains("\r")
    }
}
```

### iTerm2

iTerm2 has the best support for programmatic text injection among terminal emulators:

- **Bracketed paste**: iTerm2 properly supports bracketed paste mode, wrapping pasted
  text in `\e[200~...\e[201~` sequences so shells know not to execute line by line.
- **Shell integration**: With iTerm2's shell integration installed, VaulType can detect
  when a shell prompt is active versus when a program is running.
- **AppleScript API**: iTerm2 exposes a comprehensive AppleScript/JXA interface that
  can be used for text injection as an alternative to CGEvent/clipboard.
- **Recommendation**: Clipboard paste is preferred. For advanced use, iTerm2's
  `write text` AppleScript command provides the most reliable injection.

### Warp

Warp is a modern terminal built with Rust and a custom rendering engine:

- **Input handling**: Warp uses a custom text input field (not a standard NSTextView),
  which means standard CGEvent handling may not work as expected.
- **Block editing**: Warp's block-based input model means pasted text goes into the
  current input block rather than directly to the PTY.
- **Accessibility**: Warp's accessibility support is evolving. The focused element may
  not be reported as a standard text field role.
- **Recommendation**: Clipboard paste works reliably. CGEvent injection is unreliable
  due to Warp's custom input handling.

### Alacritty

Alacritty is a GPU-accelerated terminal with minimal UI chrome:

- **Input handling**: Alacritty processes input at a very low level and passes it
  directly to the PTY with minimal interpretation.
- **Accessibility**: Alacritty has limited accessibility support. AXUIElement queries
  may return minimal information about the focused element.
- **Paste handling**: Alacritty supports bracketed paste mode and handles clipboard
  paste correctly.
- **Recommendation**: Clipboard paste is the only reliable method. CGEvent injection
  works for basic ASCII but is unreliable for special characters.

### Terminal Injection Strategy

```swift
/// Unified terminal injection strategy that selects the best method per terminal.
struct TerminalInjector {

    enum TerminalApp {
        case terminalApp
        case iterm2
        case warp
        case alacritty
        case unknown

        init(bundleID: String) {
            switch bundleID {
            case "com.apple.Terminal":
                self = .terminalApp
            case "com.googlecode.iterm2":
                self = .iterm2
            case "dev.warp.Warp-Stable":
                self = .warp
            case "io.alacritty":
                self = .alacritty
            default:
                self = .unknown
            }
        }
    }

    /// Injects text into a terminal application with appropriate safety measures.
    static func inject(
        text: String,
        terminal: TerminalApp,
        clipboardInjector: ClipboardInjector
    ) async throws {
        // Safety check: warn about multi-line text in terminals
        if TerminalInjectionStrategy.containsNewlines(text) {
            // In a real implementation, this would present a confirmation dialog
            // to the user before injecting multi-line text into a terminal.
            NotificationCenter.default.post(
                name: .vaulTypeTerminalMultilineWarning,
                object: nil,
                userInfo: ["text": text, "terminal": terminal]
            )
        }

        switch terminal {
        case .iterm2:
            // iTerm2: prefer clipboard with bracketed paste support
            try await clipboardInjector.injectWithSmartRestore(text)

        case .terminalApp:
            // Terminal.app: clipboard paste with explicit Cmd+V
            try await clipboardInjector.injectWithSmartRestore(text)

        case .warp:
            // Warp: clipboard paste; CGEvent is unreliable with Warp's custom input
            try await clipboardInjector.injectWithSmartRestore(text)

        case .alacritty:
            // Alacritty: clipboard paste is the only reliable method
            try await clipboardInjector.injectWithSmartRestore(text)

        case .unknown:
            // Default terminal strategy: clipboard paste
            try await clipboardInjector.injectWithSmartRestore(text)
        }
    }
}

extension Notification.Name {
    static let vaulTypeTerminalMultilineWarning = Notification.Name(
        "com.vaultype.terminalMultilineWarning"
    )
}
```

> ❌ **Error**: Never inject text containing newlines into a terminal via CGEvent
> keystroke simulation. Each newline character generates a Return keystroke, which the
> shell interprets as "execute this command." This could cause unintended command
> execution. Always use clipboard paste with bracketed paste mode support for multi-line
> terminal injection.

---

## Electron App Compatibility

### VS Code

VS Code uses a custom text editor (Monaco) running inside an Electron shell:

- **CGEvent handling**: Monaco processes CGEvent keystrokes but may drop characters at
  high injection speeds. An inter-key delay of at least 2ms is recommended.
- **Clipboard paste**: Works reliably. VS Code processes paste events through its own
  text model and handles Unicode correctly.
- **Multi-cursor**: If VS Code has multiple cursors active, both CGEvent and clipboard
  injection will insert text at all cursor positions. This is usually desirable.
- **Integrated terminal**: The VS Code integrated terminal has the same issues as
  standalone terminals. VaulType detects when the terminal panel is focused.
- **Known quirk**: VS Code's "editor.acceptSuggestionOnCommitCharacter" setting can
  cause autocomplete suggestions to be accepted during CGEvent injection if the
  injected character matches a commit character (e.g., `.`, `(`).

```swift
/// VS Code-specific injection handling.
struct VSCodeInjector {

    /// Detects whether the focused element in VS Code is the editor or the terminal.
    static func detectFocusedComponent(detector: AccessibilityDetector) -> VSCodeComponent {
        guard let info = detector.focusedTextInfo() else {
            return .unknown
        }

        // VS Code's terminal uses a different AX role than the editor
        if info.role == "AXTextArea" {
            // Check the element's description or hierarchy for terminal indicators
            return .editor
        }

        // The integrated terminal may present as AXGroup or AXWebArea
        return .terminal
    }

    enum VSCodeComponent {
        case editor
        case terminal
        case unknown
    }
}
```

### Slack

Slack's message input field is a contentEditable div inside Electron's Chromium:

- **CGEvent handling**: Works for basic text but Slack's rich text editor may
  misinterpret certain key sequences. Markdown formatting characters (`*`, `_`, `~`)
  trigger inline formatting.
- **Clipboard paste**: Generally reliable. Slack processes pasted text through its own
  formatting pipeline.
- **Known quirk**: Pasting text that starts with `/` triggers Slack's command parser.
  VaulType adds a zero-width space prefix if the transcribed text begins with `/` and
  the target is Slack.
- **Threading**: If a thread is open, text injection goes to the thread reply field,
  not the main channel input.

### Discord

Discord's input handling is similar to Slack:

- **CGEvent handling**: Works for basic text. Discord's markdown rendering may interpret
  certain character sequences as formatting.
- **Clipboard paste**: Reliable for plain text. Rich text paste may include formatting
  that Discord cannot render.
- **Known quirk**: Discord splits long messages at 2000 characters. VaulType does not
  automatically split injected text; the user sees Discord's character limit warning.
- **Voice channels**: When in a voice channel, Discord's input focus may be on the
  voice controls rather than a text field. VaulType detects this and avoids injection.

### Electron Input Handling Quirks

Common issues across all Electron applications:

```
Electron Input Pipeline:
========================

  CGEvent/Clipboard
       |
       v
  Chromium Browser Process
       |
       v
  IPC to Renderer Process
       |
       v
  JavaScript Event Loop
       |
       v
  Web App Event Handlers (React, Vue, etc.)
       |
       v
  DOM Update + Virtual DOM Reconciliation
       |
       v
  Rendered Output
```

| Issue | Description | Workaround |
|-------|-------------|------------|
| **Event coalescing** | Rapid CGEvents may be coalesced by Chromium's event processing | Increase inter-key delay to 2-3ms |
| **IME interference** | Chromium's IME handling can intercept Unicode CGEvents | Use clipboard paste for non-ASCII |
| **Focus loss** | Electron apps may briefly lose focus during clipboard operations | Add 20ms delay after clipboard write |
| **Synthetic event detection** | Some web apps reject events without `isTrusted: true` | Use `.cghidEventTap` tap location |
| **Accessibility tree lag** | Electron's AX tree updates asynchronously after DOM changes | Allow 50-100ms for AX tree sync |

> 💡 **Tip**: For all Electron applications, clipboard paste is generally more reliable
> than CGEvent keystroke injection. The clipboard path bypasses Chromium's complex event
> processing pipeline and delivers text directly through the system paste mechanism.

---

## Browser Text Field Handling

### Safari

Safari uses WebKit for rendering and has the best macOS integration among browsers:

- **Text fields (`<input>`, `<textarea>`)**: CGEvent injection works well. Safari
  correctly processes Unicode CGEvents through WebKit's input pipeline.
- **contentEditable elements**: CGEvent works but rich text editors (Google Docs,
  Notion web) may have custom key handlers that interfere.
- **Clipboard paste**: Reliable. Safari preserves the HTML format of pasted content
  in contentEditable fields.
- **Accessibility**: Safari exposes a comprehensive AX tree for web content. Text
  fields are properly reported as AXTextField or AXTextArea.

### Chrome

Chrome/Chromium has its own input handling that differs from WebKit:

- **Text fields**: CGEvent injection works but may have issues with password fields
  (Chrome may ignore programmatic input in secure fields).
- **contentEditable elements**: Similar to Safari but Chrome's Blink engine has
  different IME handling that can interfere with CGEvent Unicode injection.
- **Clipboard paste**: Reliable. Chrome's paste handling works through the same
  code path as user-initiated paste.
- **Extensions**: Browser extensions that intercept keyboard input (e.g., Vimium,
  keyboard shortcut managers) may capture injected CGEvents. Clipboard paste is
  unaffected by these extensions.

### Firefox

Firefox uses the Gecko engine with distinct input handling characteristics:

- **Text fields**: CGEvent injection works for basic text. Firefox's input handling
  sends events through a different pipeline than WebKit/Blink.
- **contentEditable elements**: Firefox's handling of contentEditable fields is
  notably different from Chrome and Safari. Some rich text editors may not work
  correctly with CGEvent injection.
- **Clipboard paste**: Reliable and the recommended method for Firefox.
- **Accessibility**: Firefox has good AX support but the element hierarchy differs
  from Safari. VaulType handles Firefox's AX tree structure separately.

### ContentEditable Fields

Rich text editors using `contentEditable` present the most complex injection target:

```swift
/// Strategy for injecting text into browser contentEditable fields.
struct ContentEditableStrategy {

    /// Determines the best injection approach for contentEditable elements.
    /// - Parameters:
    ///   - browser: The detected browser type.
    ///   - text: The text to inject.
    /// - Returns: The recommended injection method.
    static func recommendedMethod(
        browser: BrowserType,
        text: String
    ) -> InjectionMethodSelector.InjectionMethod {
        // Always use clipboard for contentEditable to avoid rich text editor quirks
        return .clipboard
    }

    enum BrowserType {
        case safari
        case chrome
        case firefox
        case arc
        case other

        init(bundleID: String) {
            switch bundleID {
            case "com.apple.Safari", "com.apple.SafariTechnologyPreview":
                self = .safari
            case "com.google.Chrome", "com.google.Chrome.canary":
                self = .chrome
            case "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition":
                self = .firefox
            case "company.thebrowser.Browser":
                self = .arc
            default:
                self = .other
            }
        }
    }
}
```

### Textarea and Input Fields

Standard `<textarea>` and `<input>` HTML elements are the most straightforward browser
injection targets:

| Element | CGEvent Support | Clipboard Support | Notes |
|---------|----------------|-------------------|-------|
| `<input type="text">` | Good | Good | Standard text input |
| `<input type="search">` | Good | Good | May trigger search-as-you-type |
| `<input type="email">` | Good | Good | Browser may validate on each keystroke |
| `<input type="password">` | Fair | Fair | Chrome may block programmatic input |
| `<input type="url">` | Good | Good | Browser may validate format |
| `<textarea>` | Good | Good | Multi-line support works well |
| `<div contenteditable>` | Fair | Good | Rich text editor complexity |
| `<input type="number">` | Limited | Limited | Non-numeric CGEvents are rejected |

---

## Per-App Injection Method Selection

The following code ties together all the per-app logic into a unified injection
coordinator:

```swift
import AppKit
import CoreGraphics
import Combine

/// Errors that can occur during text injection.
enum InjectionError: Error, LocalizedError {
    case eventCreationFailed
    case accessibilityNotAvailable
    case noFocusedElement
    case elementNotEditable
    case textTooLong(Int)
    case clipboardPreservationFailed
    case unknownTargetApp

    var errorDescription: String? {
        switch self {
        case .eventCreationFailed:
            return "Failed to create CGEvent for keystroke injection"
        case .accessibilityNotAvailable:
            return "Accessibility permission not granted"
        case .noFocusedElement:
            return "No focused text element detected"
        case .elementNotEditable:
            return "The focused element does not accept text input"
        case .textTooLong(let length):
            return "Text too long for CGEvent injection (\(length) characters)"
        case .clipboardPreservationFailed:
            return "Failed to preserve clipboard contents"
        case .unknownTargetApp:
            return "Unable to determine the target application"
        }
    }
}

/// Coordinates text injection across all supported applications and injection methods.
actor TextInjectionCoordinator {

    private let accessibilityDetector = AccessibilityDetector()
    private let cgEventInjector = CGEventKeystrokeInjector()
    private let clipboardInjector = ClipboardInjector()
    private let appMonitor = FrontmostAppMonitor()

    /// Maximum text length for CGEvent injection before falling back to clipboard.
    private let cgEventMaxLength = 64

    /// Injects the given text into the currently focused text element.
    /// Automatically selects the optimal injection method based on context.
    func inject(_ text: String) async throws {
        // 1. Verify accessibility permission
        guard AXIsProcessTrusted() else {
            throw InjectionError.accessibilityNotAvailable
        }

        // 2. Detect the focused element
        guard let textInfo = accessibilityDetector.focusedTextInfo() else {
            throw InjectionError.noFocusedElement
        }

        guard textInfo.isEditable else {
            throw InjectionError.elementNotEditable
        }

        // 3. Build injection context
        let context = InjectionMethodSelector.InjectionContext(
            text: text,
            targetBundleID: textInfo.bundleIdentifier,
            targetRole: textInfo.role,
            userPreference: nil
        )

        // 4. Select injection method
        let method = InjectionMethodSelector.selectMethod(for: context)

        // 5. Apply pre-injection workarounds
        if let bundleID = textInfo.bundleIdentifier {
            await AppWorkarounds.preInjection(bundleID: bundleID)
        }

        // 6. Execute injection
        switch method {
        case .cgEvent:
            try await cgEventInjector.injectText(text)

        case .clipboard:
            try await clipboardInjector.injectWithSmartRestore(text)

        case .clipboardExplicit:
            try await clipboardInjector.injectText(text)
        }

        // 7. Apply post-injection workarounds
        if let bundleID = textInfo.bundleIdentifier {
            await AppWorkarounds.postInjection(bundleID: bundleID)
        }
    }

    /// Injects text with a specific method override (for user preferences or testing).
    func inject(
        _ text: String,
        method: InjectionMethodSelector.InjectionMethod
    ) async throws {
        guard AXIsProcessTrusted() else {
            throw InjectionError.accessibilityNotAvailable
        }

        switch method {
        case .cgEvent:
            try await cgEventInjector.injectText(text)
        case .clipboard:
            try await clipboardInjector.injectWithSmartRestore(text)
        case .clipboardExplicit:
            try await clipboardInjector.injectText(text)
        }
    }
}
```

---

## Error Handling and Recovery

Text injection can fail for numerous reasons. VaulType implements a multi-layer error
handling strategy:

```
Error Recovery Flow:
====================

  Injection Attempt
       |
       v
  [Success?]---YES---> Done
       |
       NO
       |
       v
  [Error Type?]
       |
       +--- AccessibilityNotAvailable --> Prompt user to grant permission
       |
       +--- NoFocusedElement --> Show notification with text in clipboard
       |
       +--- ElementNotEditable --> Show notification, offer clipboard copy
       |
       +--- EventCreationFailed --> Retry with clipboard method
       |
       +--- ClipboardPreservationFailed --> Inject without clipboard preservation
       |
       +--- Timeout --> Retry with increased delays
```

```swift
/// Handles injection failures with automatic recovery strategies.
struct InjectionErrorHandler {

    /// Attempts injection with automatic fallback on failure.
    static func injectWithRecovery(
        text: String,
        coordinator: TextInjectionCoordinator
    ) async -> InjectionResult {
        // First attempt: automatic method selection
        do {
            try await coordinator.inject(text)
            return .success
        } catch InjectionError.eventCreationFailed {
            // Fallback: try clipboard method
            do {
                try await coordinator.inject(text, method: .clipboard)
                return .successWithFallback(.clipboard)
            } catch {
                return .failure(error)
            }
        } catch InjectionError.accessibilityNotAvailable {
            // Cannot recover from missing permissions.
            // Copy text to clipboard so the user can paste manually.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            return .copiedToClipboard
        } catch InjectionError.noFocusedElement {
            // No text field is focused. Copy to clipboard as fallback.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            return .copiedToClipboard
        } catch {
            return .failure(error)
        }
    }

    enum InjectionResult {
        case success
        case successWithFallback(InjectionMethodSelector.InjectionMethod)
        case copiedToClipboard
        case failure(Error)
    }
}
```

> ✅ **Success**: VaulType's multi-layer error recovery ensures that transcribed text
> is never lost. In the worst case, the text is placed on the clipboard with a
> notification telling the user to paste manually with Command+V.

---

## Performance Optimization

### Injection Latency Budget

The target end-to-end injection latency from transcription completion to text appearing
in the target application:

```
Latency Budget (target: < 100ms for typical sentences):
========================================================

  Component                  Budget     Actual (P50)   Actual (P99)
  -------------------------------------------------------------------
  Method selection           < 1ms      0.2ms          0.5ms
  Accessibility query        < 5ms      1ms            8ms
  Pre-injection workaround   < 10ms     0ms            50ms
  CGEvent injection (short)  < 50ms     15ms           80ms
  Clipboard injection        < 30ms     12ms           45ms
  Post-injection cleanup     < 10ms     2ms            20ms
  Clipboard restoration      < 5ms      1ms            3ms
  -------------------------------------------------------------------
  Total (CGEvent, short)     < 81ms     ~19ms          ~162ms
  Total (Clipboard)          < 61ms     ~16ms          ~126ms
```

### Optimization Techniques

```swift
/// Performance-optimized injection with pre-computed method selection.
final class OptimizedInjector {

    /// Pre-computed injection plan for a specific target context.
    struct InjectionPlan {
        let method: InjectionMethodSelector.InjectionMethod
        let interKeyDelay: UInt64
        let preInjectionDelay: UInt64
        let postInjectionDelay: UInt64
        let clipboardRestoreDelay: UInt64
    }

    /// Cache of injection plans per bundle ID.
    private var planCache: [String: InjectionPlan] = [:]

    /// Builds or retrieves a cached injection plan for the target app.
    func plan(for bundleID: String, textLength: Int, isASCII: Bool) -> InjectionPlan {
        let cacheKey = "\(bundleID)_\(textLength > 64 ? "long" : "short")_\(isASCII)"

        if let cached = planCache[cacheKey] {
            return cached
        }

        let plan = buildPlan(bundleID: bundleID, textLength: textLength, isASCII: isASCII)
        planCache[cacheKey] = plan
        return plan
    }

    private func buildPlan(bundleID: String, textLength: Int, isASCII: Bool) -> InjectionPlan {
        // Determine method
        let context = InjectionMethodSelector.InjectionContext(
            text: String(repeating: "x", count: textLength), // dummy text for length check
            targetBundleID: bundleID,
            targetRole: nil,
            userPreference: nil
        )
        let method = InjectionMethodSelector.selectMethod(for: context)

        // Compute optimal delays based on app category
        let isElectron = [
            "com.microsoft.VSCode",
            "com.tinyspeck.slackmacgap",
            "com.hnc.Discord",
            "notion.id",
            "md.obsidian",
        ].contains(bundleID)

        let isTerminal = [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "dev.warp.Warp-Stable",
            "io.alacritty",
        ].contains(bundleID)

        return InjectionPlan(
            method: method,
            interKeyDelay: isElectron ? 2_000_000 : 1_000_000,
            preInjectionDelay: isTerminal ? 20_000_000 : 0,
            postInjectionDelay: isElectron ? 30_000_000 : 10_000_000,
            clipboardRestoreDelay: isElectron ? 150_000_000 : 80_000_000
        )
    }
}
```

### Memory Considerations

> ℹ️ **Info**: Clipboard preservation can use significant memory when the user has
> large items on the clipboard (e.g., high-resolution images). VaulType limits
> clipboard preservation to 50MB. If the clipboard contents exceed this limit,
> VaulType skips preservation and notifies the user that their clipboard was replaced.

```swift
extension ClipboardPreserver {

    /// Maximum clipboard size to preserve (50MB).
    static let maxPreservationSize: Int = 50 * 1024 * 1024

    /// Checks if the current clipboard contents are within the preservation limit.
    static func canPreserve(pasteboard: NSPasteboard) -> Bool {
        var totalSize = 0

        for item in pasteboard.pasteboardItems ?? [] {
            for type in item.types {
                if let data = item.data(forType: type) {
                    totalSize += data.count
                }
            }
        }

        return totalSize <= maxPreservationSize
    }
}
```

---

## Related Documentation

| Document | Description |
|----------|-------------|
| [Architecture Overview](../architecture/ARCHITECTURE.md) | System architecture and component relationships |
| [Permissions Guide](PERMISSIONS.md) | Accessibility, microphone, and other macOS permissions |
| [API Documentation](../api/API_DOCUMENTATION.md) | Public API reference for the injection subsystem |
| [Tech Stack](../architecture/TECH_STACK.md) | Frameworks and libraries used in VaulType |
| [Security Model](../security/SECURITY.md) | Security considerations for event injection |
| [Accessibility Reference](../reference/ACCESSIBILITY.md) | macOS accessibility API usage guide |

---

*This document is part of the [VaulType](https://github.com/vaultype/vaultype) project,
licensed under GPL-3.0. All processing happens locally on your Mac — no cloud, no telemetry,
no network calls.*
