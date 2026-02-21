Last Updated: 2026-02-13

# Accessibility Reference

VaulType is, at its core, an accessibility tool — it gives voice-to-text capability to every user on macOS. The UI that wraps this capability must hold itself to the highest accessibility standard. This document defines the patterns, techniques, and compliance requirements that govern every VaulType interface element.

---

## Table of Contents

- [Accessibility Philosophy](#accessibility-philosophy)
- [VoiceOver Compatibility](#voiceover-compatibility)
  - [Accessibility Labels](#accessibility-labels)
  - [Accessibility Values and Hints](#accessibility-values-and-hints)
  - [Accessibility Actions](#accessibility-actions)
  - [Rotor Support](#rotor-support)
  - [Accessibility Containers](#accessibility-containers)
- [Keyboard Navigation](#keyboard-navigation)
  - [Tab Order and Focus Management](#tab-order-and-focus-management)
  - [Keyboard Shortcuts](#keyboard-shortcuts)
  - [Custom Focus States](#custom-focus-states)
- [High Contrast Mode](#high-contrast-mode)
  - [Detecting High Contrast](#detecting-high-contrast)
  - [Semantic Color Usage](#semantic-color-usage)
  - [Contrast Ratios](#contrast-ratios)
- [Dynamic Type Support](#dynamic-type-support)
  - [System Font Preferences](#system-font-preferences)
  - [Layout Adaptation](#layout-adaptation)
  - [Testing at All Sizes](#testing-at-all-sizes)
- [Reduced Motion Support](#reduced-motion-support)
  - [Detecting Reduced Motion](#detecting-reduced-motion)
  - [Conditional Animation](#conditional-animation)
  - [Alternative Transitions](#alternative-transitions)
- [Audio Feedback Alternatives](#audio-feedback-alternatives)
  - [Visual Indicators for Audio Cues](#visual-indicators-for-audio-cues)
  - [Haptic Feedback](#haptic-feedback)
- [Color Independence](#color-independence)
  - [Multi-Channel Communication](#multi-channel-communication)
  - [Icon and Shape Patterns](#icon-and-shape-patterns)
- [Accessibility Testing Checklist](#accessibility-testing-checklist)
- [SwiftUI Accessibility Patterns](#swiftui-accessibility-patterns)
  - [Reusable View Modifiers](#reusable-view-modifiers)
  - [Accessible Component Templates](#accessible-component-templates)
  - [Environment-Driven Accessibility](#environment-driven-accessibility)
- [Related Documentation](#related-documentation)

---

## Accessibility Philosophy

VaulType converts speech to text for anyone who benefits from hands-free input — users with motor impairments, repetitive strain injuries, situational disabilities, or simple preference. An app that exists to serve accessibility **must not itself be inaccessible**.

Every interface element in VaulType follows three principles:

| Principle | Meaning |
|---|---|
| **Perceivable** | All information is available through at least two sensory channels (visual + auditory, visual + haptic, etc.) |
| **Operable** | Every action can be performed via mouse, keyboard, VoiceOver, or Switch Control |
| **Understandable** | Labels, states, and feedback are clear and consistent — no ambiguity in any interaction mode |

> ℹ️ **WCAG Alignment** — VaulType targets WCAG 2.1 AA compliance as a baseline. Where feasible, AAA criteria are met (e.g., contrast ratios of 7:1 or higher in high-contrast mode).

> 🍎 **Platform Integration** — VaulType relies on macOS system accessibility APIs rather than custom reimplementations. This ensures compatibility with assistive technologies Apple ships and updates.

---

## VoiceOver Compatibility

VoiceOver is the primary screen reader on macOS. Every VaulType view must be fully navigable and comprehensible through VoiceOver alone.

### Accessibility Labels

Every interactive element requires a concise, descriptive label. SwiftUI's `.accessibilityLabel(_:)` modifier is the primary mechanism.

```swift
// MARK: - Menu Bar Icon

struct MenuBarButton: View {
    @Binding var isRecording: Bool

    var body: some View {
        Button(action: toggleRecording) {
            Image(systemName: isRecording ? "mic.fill" : "mic")
        }
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
    }
}
```

```swift
// MARK: - Settings Toggle

struct SettingsToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(title)
        .accessibilityHint(description)
    }
}
```

> ⚠️ **Label Guidelines** — Labels must describe the element's **purpose**, not its appearance. Use "Start recording" instead of "Microphone button." Never include the control type in the label — VoiceOver announces that automatically.

### Accessibility Values and Hints

Values communicate the current state of a control. Hints explain the result of interacting with it.

```swift
// MARK: - Recording Duration Display

struct RecordingIndicator: View {
    let duration: TimeInterval
    let isRecording: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isRecording ? Color.red : Color.gray)
                .frame(width: 8, height: 8)
            Text(formattedDuration)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recording status")
        .accessibilityValue(
            isRecording
                ? "Recording, \(formattedDuration) elapsed"
                : "Not recording"
        )
        .accessibilityHint(
            isRecording
                ? "Double-tap to stop recording"
                : "Double-tap to start recording"
        )
    }

    private var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
```

### Accessibility Actions

Custom actions surface operations that are available in the UI but may be difficult to discover through standard navigation.

```swift
// MARK: - Transcription History Row

struct TranscriptionRow: View {
    let transcription: Transcription
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(transcription.text)
                .lineLimit(2)
            Text(transcription.date, style: .relative)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Transcription from \(transcription.date.formatted())")
        .accessibilityValue(transcription.text)
        .accessibilityAction(named: "Copy to clipboard") {
            onCopy()
        }
        .accessibilityAction(named: "Delete transcription") {
            onDelete()
        }
    }
}
```

### Rotor Support

The VoiceOver rotor lets users navigate by category. VaulType registers custom rotor entries where they improve navigation efficiency.

```swift
// MARK: - Settings Window with Rotor

struct SettingsView: View {
    @State private var selectedSection: SettingsSection = .general

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(selection: $selectedSection)
        } detail: {
            SettingsDetail(section: selectedSection)
        }
        .accessibilityRotor("Settings Sections") {
            ForEach(SettingsSection.allCases) { section in
                AccessibilityRotorEntry(section.title, id: section.id) {
                    selectedSection = section
                }
            }
        }
        .accessibilityRotor("Actions") {
            AccessibilityRotorEntry("Reset to Defaults", id: "reset") {
                resetAllSettings()
            }
            AccessibilityRotorEntry("Export Settings", id: "export") {
                exportSettings()
            }
        }
    }
}
```

### Accessibility Containers

Group related elements into logical containers so VoiceOver navigates them coherently.

```swift
// MARK: - Status Bar Section

struct StatusSection: View {
    let modelName: String
    let modelStatus: ModelStatus

    var body: some View {
        HStack {
            Label(modelName, systemImage: "cpu")
            Spacer()
            StatusBadge(status: modelStatus)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Whisper model")
        .accessibilityValue("\(modelName), \(modelStatus.accessibilityDescription)")
    }
}
```

> 💡 **Combine vs. Contain** — Use `.accessibilityElement(children: .combine)` when child elements form a single logical unit (e.g., a label and its value). Use `.accessibilityElement(children: .contain)` when children are independently interactive.

---

## Keyboard Navigation

Every action in VaulType must be reachable without a pointing device. The settings window, popover, and any modal must support full keyboard operation.

### Tab Order and Focus Management

SwiftUI's `@FocusState` property wrapper governs focus. Define explicit focus sequences for all settings panels.

```swift
// MARK: - General Settings Panel

struct GeneralSettingsView: View {
    @FocusState private var focusedField: GeneralField?
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("outputMode") private var outputMode: OutputMode = .clipboard
    @AppStorage("selectedLanguage") private var selectedLanguage = "auto"

    enum GeneralField: Hashable, CaseIterable {
        case launchAtLogin
        case outputMode
        case language
    }

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .focused($focusedField, equals: .launchAtLogin)

            Picker("Output mode", selection: $outputMode) {
                ForEach(OutputMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .focused($focusedField, equals: .outputMode)

            Picker("Language", selection: $selectedLanguage) {
                Text("Auto-detect").tag("auto")
                ForEach(SupportedLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang.code)
                }
            }
            .focused($focusedField, equals: .language)
        }
        .onAppear {
            focusedField = .launchAtLogin
        }
        .onKeyPress(.tab) {
            advanceFocus()
            return .handled
        }
    }

    private func advanceFocus() {
        guard let current = focusedField,
              let currentIndex = GeneralField.allCases.firstIndex(of: current) else {
            focusedField = .launchAtLogin
            return
        }
        let nextIndex = GeneralField.allCases.index(after: currentIndex)
        focusedField = nextIndex < GeneralField.allCases.endIndex
            ? GeneralField.allCases[nextIndex]
            : GeneralField.allCases.first
    }
}
```

### Keyboard Shortcuts

VaulType defines global and local keyboard shortcuts for all primary actions.

| Action | Shortcut | Scope |
|---|---|---|
| Start/Stop recording | Configurable (default: `⌥ Space`) | Global hotkey |
| Open settings | `⌘ ,` | App-wide |
| Close window / popover | `Esc` | Active window |
| Copy last transcription | `⌘ ⇧ C` | App-wide |
| Switch settings tab | `⌘ 1`–`⌘ 5` | Settings window |
| Navigate sidebar | `↑` / `↓` | Settings sidebar |
| Toggle focused control | `Space` | Focused toggle/button |

```swift
// MARK: - Keyboard Shortcut Registration

struct SettingsWindow: View {
    @State private var selectedSection: SettingsSection = .general

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(selection: $selectedSection)
        } detail: {
            SettingsDetail(section: selectedSection)
        }
        .frame(minWidth: 600, minHeight: 400)
        .keyboardShortcut(.cancelAction) // Esc to close
        .onKeyPress(keys: [.init("1")], modifiers: .command) {
            selectedSection = .general; return .handled
        }
        .onKeyPress(keys: [.init("2")], modifiers: .command) {
            selectedSection = .audio; return .handled
        }
        .onKeyPress(keys: [.init("3")], modifiers: .command) {
            selectedSection = .model; return .handled
        }
        .onKeyPress(keys: [.init("4")], modifiers: .command) {
            selectedSection = .privacy; return .handled
        }
        .onKeyPress(keys: [.init("5")], modifiers: .command) {
            selectedSection = .about; return .handled
        }
    }
}
```

### Custom Focus States

Focus rings must be clearly visible, especially in dark mode and high-contrast mode.

```swift
// MARK: - Accessible Focus Ring Modifier

struct AccessibleFocusRing: ViewModifier {
    let isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isFocused ? Color.accentColor : Color.clear,
                        lineWidth: isFocused ? 3 : 0
                    )
            )
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

extension View {
    func accessibleFocusRing(isFocused: Bool) -> some View {
        modifier(AccessibleFocusRing(isFocused: isFocused))
    }
}
```

```swift
// Usage in a custom control
struct ModelCard: View {
    let model: WhisperModel
    let isSelected: Bool
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.name)
                .font(.headline)
            Text(model.sizeDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibleFocusRing(isFocused: isFocused)
        .focused($isFocused)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel("\(model.name) model, \(model.sizeDescription)")
    }
}
```

> ⚠️ **Never Remove System Focus Indicators** — Only supplement the default focus ring; do not replace or disable it. Users who depend on keyboard navigation rely on consistent focus appearance.

---

## High Contrast Mode

macOS provides a system-wide "Increase Contrast" setting. VaulType must respond to it by strengthening all visual boundaries.

### Detecting High Contrast

```swift
// MARK: - High Contrast Environment Key

struct HighContrastKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var isHighContrast: Bool {
        get { self[HighContrastKey.self] }
        set { self[HighContrastKey.self] = newValue }
    }
}

// MARK: - High Contrast Monitor

final class AccessibilityMonitor: ObservableObject {
    @Published var isHighContrastEnabled: Bool

    private var observer: NSObjectProtocol?

    init() {
        self.isHighContrastEnabled =
            NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast

        observer = NotificationCenter.default.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isHighContrastEnabled =
                NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
```

```swift
// MARK: - Injecting into Environment

@main
struct VaulTypeApp: App {
    @StateObject private var accessibilityMonitor = AccessibilityMonitor()

    var body: some Scene {
        MenuBarExtra("VaulType", systemImage: "mic") {
            ContentView()
                .environment(\.isHighContrast, accessibilityMonitor.isHighContrastEnabled)
        }
        Settings {
            SettingsView()
                .environment(\.isHighContrast, accessibilityMonitor.isHighContrastEnabled)
        }
    }
}
```

### Semantic Color Usage

Always use semantic system colors. They automatically adapt to appearance settings including high-contrast mode.

```swift
// MARK: - VaulType Color Tokens

enum VaulTypeColors {
    // Primary UI colors — all semantic
    static let primaryText = Color.primary          // Adapts to light/dark/high-contrast
    static let secondaryText = Color.secondary
    static let background = Color(nsColor: .windowBackgroundColor)
    static let controlBackground = Color(nsColor: .controlBackgroundColor)
    static let separator = Color(nsColor: .separatorColor)

    // Status colors with high-contrast overrides
    static func recordingIndicator(highContrast: Bool) -> Color {
        highContrast ? Color.red : Color.red.opacity(0.85)
    }

    static func successIndicator(highContrast: Bool) -> Color {
        highContrast ? Color.green : Color.green.opacity(0.85)
    }

    static func border(highContrast: Bool) -> Color {
        highContrast
            ? Color(nsColor: .labelColor)
            : Color(nsColor: .separatorColor)
    }
}
```

```swift
// Usage in a view
struct StatusBadge: View {
    let status: ModelStatus
    @Environment(\.isHighContrast) private var isHighContrast

    var body: some View {
        Text(status.title)
            .font(.caption)
            .fontWeight(isHighContrast ? .semibold : .regular)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(status.backgroundColor(highContrast: isHighContrast))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        VaulTypeColors.border(highContrast: isHighContrast),
                        lineWidth: isHighContrast ? 1.5 : 0
                    )
            )
    }
}
```

### Contrast Ratios

All text and interactive elements must meet minimum contrast ratios.

| Element | Normal Mode | High Contrast Mode |
|---|---|---|
| Body text | 4.5:1 minimum (AA) | 7:1 minimum (AAA) |
| Large text (18pt+) | 3:1 minimum (AA) | 4.5:1 minimum (AAA) |
| Interactive controls | 3:1 against background | 4.5:1 against background |
| Focus indicators | 3:1 against adjacent colors | 4.5:1 against adjacent colors |
| Status indicators | 3:1 against background | 4.5:1 against background |

> 🔒 **Automated Enforcement** — Use Xcode's Accessibility Inspector to verify contrast ratios during development. Run contrast audits before every release.

---

## Dynamic Type Support

VaulType respects the system font size configured in **System Settings > Accessibility > Display > Text Size** and **System Settings > Appearance > Text Size**.

### System Font Preferences

Use SwiftUI's built-in text styles. Never hard-code point sizes for user-facing text.

```swift
// MARK: - Correct: Dynamic Text Styles

struct TranscriptionView: View {
    let text: String
    let timestamp: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.body)                    // Scales with system setting
            Text(timestamp, style: .relative)
                .font(.caption)                 // Scales with system setting
                .foregroundStyle(.secondary)
        }
    }
}
```

```swift
// MARK: - Incorrect: Hard-Coded Sizes (DO NOT DO THIS)

// ❌ These will NOT scale with system font preferences
Text("Transcription")
    .font(.system(size: 14))

// ✅ Use semantic styles instead
Text("Transcription")
    .font(.body)
```

For cases where a specific relative size is needed, use `@ScaledMetric`:

```swift
// MARK: - Scaled Metric for Custom Spacing

struct RecordingButton: View {
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 24
    @ScaledMetric(relativeTo: .body) private var buttonPadding: CGFloat = 12

    var body: some View {
        Button(action: toggleRecording) {
            Image(systemName: "mic.fill")
                .font(.system(size: iconSize))
                .frame(width: iconSize * 2, height: iconSize * 2)
                .padding(buttonPadding)
        }
    }
}
```

### Layout Adaptation

Layouts must not break at extreme text sizes. Use flexible containers and test at the largest Dynamic Type setting.

```swift
// MARK: - Adaptive Layout for Large Text

struct ShortcutConfigRow: View {
    let title: String
    let description: String
    @Binding var shortcut: KeyboardShortcut
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            // Stack vertically for accessibility sizes
            VStack(alignment: .leading, spacing: 8) {
                labelContent
                ShortcutRecorder(shortcut: $shortcut)
            }
        } else {
            // Horizontal layout for standard sizes
            HStack {
                labelContent
                Spacer()
                ShortcutRecorder(shortcut: $shortcut)
            }
        }
    }

    private var labelContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
```

### Testing at All Sizes

Dynamic Type defines the following size categories. Test VaulType at every level marked with a checkmark:

| Size Category | Scale Factor | Test Required |
|---|---|---|
| `xSmall` | 0.82x | ✅ |
| `small` | 0.88x | spot-check |
| `medium` | 0.94x | spot-check |
| `large` (default) | 1.00x | ✅ |
| `xLarge` | 1.06x | spot-check |
| `xxLarge` | 1.12x | spot-check |
| `xxxLarge` | 1.19x | ✅ |
| `accessibility1` | 1.35x | ✅ |
| `accessibility2` | 1.53x | spot-check |
| `accessibility3` | 1.71x | spot-check |
| `accessibility4` | 1.94x | spot-check |
| `accessibility5` | 2.35x | ✅ |

> 💡 **Preview Helper** — Use SwiftUI previews to test Dynamic Type without changing system settings:
>
> ```swift
> #Preview("Accessibility 5") {
>     SettingsView()
>         .environment(\.dynamicTypeSize, .accessibility5)
> }
> ```

---

## Reduced Motion Support

Users who experience motion sensitivity enable **System Settings > Accessibility > Display > Reduce motion**. VaulType must respect this preference.

### Detecting Reduced Motion

SwiftUI provides the `accessibilityReduceMotion` environment value:

```swift
// MARK: - Motion-Aware Component

struct RecordingPulse: View {
    let isRecording: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        Circle()
            .fill(isRecording ? Color.red : Color.gray)
            .frame(width: 10, height: 10)
            .scaleEffect(isRecording && !reduceMotion ? pulseScale : 1.0)
            .opacity(isRecording ? 1.0 : 0.5)
            .onChange(of: isRecording) { _, newValue in
                if newValue && !reduceMotion {
                    startPulseAnimation()
                } else {
                    pulseScale = 1.0
                }
            }
    }

    private func startPulseAnimation() {
        withAnimation(
            .easeInOut(duration: 0.8)
            .repeatForever(autoreverses: true)
        ) {
            pulseScale = 1.3
        }
    }
}
```

### Conditional Animation

Wrap all animations in a reduced-motion check. Provide the following utility:

```swift
// MARK: - Motion-Safe Animation Utility

extension View {
    /// Applies an animation only when the user has not enabled Reduce Motion.
    /// Falls back to an instant state change when Reduce Motion is active.
    func motionSafeAnimation<V: Equatable>(
        _ animation: Animation = .default,
        value: V
    ) -> some View {
        modifier(MotionSafeAnimationModifier(animation: animation, value: value))
    }
}

struct MotionSafeAnimationModifier<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.animation(animation, value: value)
        }
    }
}
```

```swift
// Usage
struct PopoverContent: View {
    @State private var isExpanded = false

    var body: some View {
        VStack {
            headerView
            if isExpanded {
                detailView
            }
        }
        .motionSafeAnimation(.easeInOut(duration: 0.2), value: isExpanded)
    }
}
```

### Alternative Transitions

When animation is disabled, use instant transitions instead of animated ones. Users should still see state changes — just without motion.

```swift
// MARK: - Reduced Motion Transitions

extension AnyTransition {
    /// A transition that respects Reduce Motion: fades when motion is reduced,
    /// slides otherwise.
    static func motionSafe(
        slide edge: Edge = .leading,
        reduceMotion: Bool
    ) -> AnyTransition {
        if reduceMotion {
            return .opacity
        } else {
            return .asymmetric(
                insertion: .move(edge: edge).combined(with: .opacity),
                removal: .move(edge: edge).combined(with: .opacity)
            )
        }
    }
}
```

> ℹ️ **What Counts as Motion** — Transitions, loading spinners, pulsing indicators, parallax effects, and auto-scrolling all count as motion and must be gated behind the reduce-motion check. Simple opacity fades (under 200ms) are generally acceptable.

---

## Audio Feedback Alternatives

VaulType uses audio cues to signal recording start, recording stop, and transcription completion. Every audio cue must have an equivalent visual (and, where supported, haptic) alternative.

### Visual Indicators for Audio Cues

| Audio Cue | Visual Indicator | Implementation |
|---|---|---|
| Recording started | Red dot appears in menu bar icon; popover shows "Recording..." with pulsing indicator (or static indicator when Reduce Motion is on) | Menu bar icon swap + popover state change |
| Recording stopped | Red dot removed; popover shows "Transcribing..." | Menu bar icon swap + popover state change |
| Transcription complete | Popover shows "Copied to clipboard" with checkmark | Popover state change + brief notification |
| Error occurred | Popover shows error message with warning icon | Popover state change + optional system notification |

```swift
// MARK: - Multi-Modal Status Feedback

struct StatusIndicator: View {
    let state: RecordingState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            statusIcon
            statusText
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(state.accessibilityLabel)
        .accessibilityValue(state.accessibilityValue)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch state {
        case .idle:
            Image(systemName: "mic")
                .foregroundStyle(.secondary)
        case .recording:
            RecordingPulse(isRecording: true)
        case .transcribing:
            ProgressView()
                .controlSize(.small)
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private var statusText: some View {
        Text(state.displayText)
            .font(.callout)
            .fontWeight(.medium)
    }
}

// MARK: - RecordingState Accessibility Extensions

extension RecordingState {
    var accessibilityLabel: String {
        switch self {
        case .idle:         return "Ready to record"
        case .recording:    return "Recording in progress"
        case .transcribing: return "Transcribing audio"
        case .complete:     return "Transcription complete"
        case .error:        return "Error occurred"
        }
    }

    var accessibilityValue: String {
        switch self {
        case .idle:         return "Press your keyboard shortcut to start"
        case .recording:    return "Listening to your speech"
        case .transcribing: return "Processing, please wait"
        case .complete:     return "Text copied to clipboard"
        case .error(let msg): return msg
        }
    }

    var displayText: String {
        switch self {
        case .idle:         return "Ready"
        case .recording:    return "Recording..."
        case .transcribing: return "Transcribing..."
        case .complete:     return "Copied!"
        case .error:        return "Error"
        }
    }
}
```

### Haptic Feedback

macOS supports haptic feedback on trackpads with Force Touch. Use it to supplement audio and visual cues.

```swift
// MARK: - Haptic Feedback Manager

final class HapticManager {
    static let shared = HapticManager()

    private init() {}

    /// Plays an alignment haptic — a subtle tap.
    func playRecordingStarted() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment,
            performanceTime: .now
        )
    }

    /// Plays a level-change haptic — a more pronounced tap.
    func playRecordingComplete() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .levelChange,
            performanceTime: .now
        )
    }

    /// Plays a generic feedback for errors.
    func playError() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .generic,
            performanceTime: .now
        )
    }
}
```

> ⚠️ **Haptic Availability** — Not all Mac hardware supports haptic feedback. Always treat haptics as supplementary, never as the sole feedback channel.

---

## Color Independence

VaulType never uses color as the only means of conveying information. Every color-coded element has a secondary indicator — shape, icon, label, or pattern.

### Multi-Channel Communication

| Information | Color Channel | Secondary Channel | Tertiary Channel |
|---|---|---|---|
| Recording active | Red indicator dot | "Recording..." text label | Pulsing animation (or static indicator) |
| Model downloaded | Green checkmark | "Downloaded" text | Checkmark icon shape |
| Model not downloaded | Gray indicator | "Not downloaded" text | Download arrow icon |
| Error state | Orange/yellow | Error message text | Warning triangle icon |
| Selected item | Blue highlight | Bold text weight | Filled vs. outlined icon |

### Icon and Shape Patterns

```swift
// MARK: - Color-Independent Status Display

struct ModelStatusView: View {
    let status: ModelDownloadStatus

    var body: some View {
        HStack(spacing: 6) {
            statusIcon
            statusLabel
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(status.accessibilityDescription)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .downloaded:
            // Green checkmark — meaning conveyed by both color AND shape
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .downloading(let progress):
            // Progress ring — meaning conveyed by animation AND label
            ProgressView(value: progress)
                .progressViewStyle(.circular)
                .controlSize(.small)
        case .notDownloaded:
            // Download arrow — meaning conveyed by icon shape AND label
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(.secondary)
        case .error:
            // Warning triangle — meaning conveyed by shape AND color AND label
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private var statusLabel: some View {
        Text(status.displayText)
            .font(.caption)
            .foregroundStyle(status == .error ? .primary : .secondary)
    }
}
```

> ❌ **Anti-Pattern** — Never do this:
>
> ```swift
> // Bad: Color is the only differentiator
> Circle()
>     .fill(isActive ? .green : .red)
>     .frame(width: 8, height: 8)
> ```
>
> ✅ **Correct** — Add shape or icon differentiation:
>
> ```swift
> // Good: Shape + color + label
> HStack(spacing: 4) {
>     Image(systemName: isActive ? "checkmark.circle.fill" : "xmark.circle")
>         .foregroundStyle(isActive ? .green : .red)
>     Text(isActive ? "Active" : "Inactive")
>         .font(.caption)
> }
> ```

---

## Accessibility Testing Checklist

Run this checklist before every release. Every item must pass.

### VoiceOver Navigation

- [ ] Launch VoiceOver (`⌘ F5`) and navigate the entire settings window using only `VO + →` and `VO + ←`
- [ ] Verify every interactive element has a descriptive label (no "Button", "Image", or blank announcements)
- [ ] Verify every toggle/picker announces its current value
- [ ] Verify the recording state change is announced via VoiceOver notifications
- [ ] Verify the settings sidebar sections are navigable via rotor
- [ ] Verify grouped elements (status bars, form rows) are announced as single logical units
- [ ] Verify no duplicate or orphaned accessibility elements exist

### Keyboard-Only Operation

- [ ] Unplug mouse / disable trackpad and operate the entire app via keyboard
- [ ] Tab through every control in the settings window — confirm no focus traps
- [ ] Verify focus order matches visual layout (left-to-right, top-to-bottom)
- [ ] Verify `Escape` closes the settings window and any popovers
- [ ] Verify `Space` activates the focused button or toggle
- [ ] Verify all keyboard shortcuts work from any context
- [ ] Verify focus ring is clearly visible on every focused element

### High Contrast

- [ ] Enable **System Settings > Accessibility > Display > Increase contrast**
- [ ] Verify all text meets a 7:1 contrast ratio against its background
- [ ] Verify all borders and separators are visible
- [ ] Verify status indicators remain distinguishable
- [ ] Verify no UI element "disappears" in high-contrast mode
- [ ] Verify custom views respond to the `accessibilityDisplayShouldIncreaseContrast` flag

### Large Text

- [ ] Set Dynamic Type to `accessibility5` (the maximum)
- [ ] Verify no text is truncated or clipped without an accessible alternative
- [ ] Verify layouts reflow from horizontal to vertical where appropriate
- [ ] Verify the settings window can be resized to accommodate large text
- [ ] Verify all `@ScaledMetric` values produce usable layouts at extreme sizes

### Reduced Motion

- [ ] Enable **System Settings > Accessibility > Display > Reduce motion**
- [ ] Verify no pulsing, bouncing, or sliding animations play
- [ ] Verify state transitions are still visible (opacity change or instant swap)
- [ ] Verify no `withAnimation` calls bypass the reduce-motion check

### Switch Control

- [ ] Enable **System Settings > Accessibility > Switch Control**
- [ ] Verify every interactive element is reachable via scanning
- [ ] Verify no elements are grouped in a way that prevents individual activation
- [ ] Verify the global recording hotkey works alongside Switch Control

### Automated Audits

- [ ] Run **Xcode Accessibility Inspector** audit with zero warnings
- [ ] Run accessibility unit tests (see [SwiftUI Accessibility Patterns](#swiftui-accessibility-patterns))
- [ ] Verify all `accessibilityLabel` strings are localized

---

## SwiftUI Accessibility Patterns

Reusable patterns and modifiers used throughout the VaulType codebase.

### Reusable View Modifiers

```swift
// MARK: - Accessible Card Modifier

/// Wraps content in a card-style container with proper accessibility traits.
struct AccessibleCard: ViewModifier {
    let label: String
    let hint: String?
    let isSelected: Bool

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .accessibilityRemoveTraits(.isImage)
    }
}

extension View {
    func accessibleCard(
        label: String,
        hint: String? = nil,
        isSelected: Bool = false
    ) -> some View {
        modifier(AccessibleCard(label: label, hint: hint, isSelected: isSelected))
    }
}
```

```swift
// MARK: - Announce Changes Modifier

/// Posts a VoiceOver announcement when a value changes.
struct AnnounceChange<V: Equatable>: ViewModifier {
    let value: V
    let message: (V) -> String

    func body(content: Content) -> some View {
        content
            .onChange(of: value) { _, newValue in
                let announcement = message(newValue)
                NSAccessibility.post(
                    element: NSApp.mainWindow as Any,
                    notification: .announcementRequested,
                    userInfo: [
                        .announcement: announcement,
                        .priority: NSAccessibilityPriorityLevel.high.rawValue
                    ]
                )
            }
    }
}

extension View {
    func announceChange<V: Equatable>(
        of value: V,
        message: @escaping (V) -> String
    ) -> some View {
        modifier(AnnounceChange(value: value, message: message))
    }
}
```

```swift
// Usage: Announce recording state changes via VoiceOver
StatusIndicator(state: recordingState)
    .announceChange(of: recordingState) { state in
        state.accessibilityLabel
    }
```

### Accessible Component Templates

Use these templates when building new UI components for VaulType.

```swift
// MARK: - Accessible Settings Row Template

/// A standard settings row that is accessible by default.
/// Combines a title, description, and trailing control.
struct AccessibleSettingsRow<Control: View>: View {
    let title: String
    let description: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)  // Provided via hint
            }
            Spacer()
            control()
        }
        .accessibilityHint(description)
    }
}
```

```swift
// MARK: - Accessible Section Header Template

struct AccessibleSectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
    }
}
```

```swift
// MARK: - Accessible Error Banner

struct AccessibleErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)  // Redundant with label

            Text(message)
                .font(.callout)

            Spacer()

            Button("Dismiss", action: onDismiss)
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(.accentColor)
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
        .accessibilityAction(named: "Dismiss") { onDismiss() }
    }
}
```

### Environment-Driven Accessibility

VaulType provides a unified accessibility environment that components can read from to adapt their behavior.

```swift
// MARK: - Unified Accessibility Environment

final class AccessibilitySettings: ObservableObject {
    @Published var isHighContrast: Bool = false
    @Published var reduceMotion: Bool = false
    @Published var isVoiceOverRunning: Bool = false

    private var observers: [NSObjectProtocol] = []

    init() {
        refresh()

        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refresh()
            }
        )
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func refresh() {
        isHighContrast =
            NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        reduceMotion =
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        isVoiceOverRunning =
            NSWorkspace.shared.isVoiceOverEnabled
    }
}
```

```swift
// MARK: - Accessibility-Aware View Example

struct AdaptiveRecordingView: View {
    @EnvironmentObject private var accessibility: AccessibilitySettings
    @State private var isRecording = false

    var body: some View {
        VStack(spacing: 16) {
            recordingIndicator
            controlButton
        }
        .padding()
    }

    @ViewBuilder
    private var recordingIndicator: some View {
        HStack(spacing: 8) {
            // Shape + color + label — never color alone
            Circle()
                .fill(isRecording ? Color.red : Color.gray)
                .frame(width: indicatorSize, height: indicatorSize)
                .overlay(
                    Circle()
                        .stroke(
                            accessibility.isHighContrast
                                ? Color.primary
                                : Color.clear,
                            lineWidth: 1.5
                        )
                )
                .scaleEffect(
                    isRecording && !accessibility.reduceMotion ? 1.2 : 1.0
                )

            Text(isRecording ? "Recording" : "Ready")
                .font(.headline)
                .fontWeight(accessibility.isHighContrast ? .bold : .semibold)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isRecording ? "Recording in progress" : "Ready to record")
    }

    private var controlButton: some View {
        Button(action: { isRecording.toggle() }) {
            Label(
                isRecording ? "Stop" : "Record",
                systemImage: isRecording ? "stop.fill" : "mic.fill"
            )
        }
        .keyboardShortcut(.space, modifiers: [])
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
    }

    private var indicatorSize: CGFloat {
        accessibility.isHighContrast ? 12 : 10
    }
}
```

> 💡 **Testing Tip** — SwiftUI previews allow injection of accessibility overrides for fast iteration:
>
> ```swift
> #Preview("High Contrast + Reduced Motion") {
>     let settings = AccessibilitySettings()
>     settings.isHighContrast = true
>     settings.reduceMotion = true
>     return AdaptiveRecordingView()
>         .environmentObject(settings)
> }
> ```

---

## Related Documentation

- [Architecture Overview](./ARCHITECTURE.md) — System architecture and component boundaries
- [UI/UX Patterns](./UI_PATTERNS.md) — Design patterns and SwiftUI component library
- [Privacy Model](./PRIVACY.md) — Privacy-first design principles and data handling
- [Configuration Reference](./CONFIGURATION.md) — All settings and their default values
- [Contributing Guide](../CONTRIBUTING.md) — Development workflow and code standards
- [Testing Strategy](./TESTING.md) — Testing approach including accessibility test harnesses
