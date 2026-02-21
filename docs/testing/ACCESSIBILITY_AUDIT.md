# VaulType Accessibility Audit — WCAG 2.1 Level AA

## Overview

This document is the official WCAG 2.1 Level AA compliance audit checklist for every user-facing
surface in VaulType. It is intended to be executed manually before each public release and
whenever a UI component is added or substantially changed.

**Standard targeted:** WCAG 2.1 Level AA (W3C Recommendation 5 June 2018)
**Platform:** macOS 14.0+ (Sonoma)

**Primary testing tools:**

| Tool | Purpose |
|------|---------|
| VoiceOver (macOS built-in) | Screen-reader compliance, focus order, announcements |
| Accessibility Inspector (Xcode) | Accessibility tree inspection, label/hint auditing |
| Color Contrast Analyser (macOS) | Foreground/background contrast ratio verification |
| Xcode Accessibility Audit API | Automated element auditing in `XCUITest` |
| `VaulTypeTests/AccessibilityAuditTests.swift` | Unit-level announcement and preference tests |

**Scope — UI surfaces covered:**

1. Menu Bar Popover (`MenuBarView`)
2. Settings Window — 10 tabs (`SettingsView`)
3. Overlay Window (`OverlayContentView` inside `OverlayWindow`)
4. Onboarding Wizard (`OnboardingView`)
5. History Window (`HistoryView`)

**Out of scope:** System menus, OS-level dialogs (permission prompts), Sparkle update sheets
(third-party), and any future web or iOS surfaces.

---

## Testing Environment Setup

### macOS Accessibility Settings to Enable Before Testing

Navigate to **System Settings > Accessibility** and configure the following for full coverage:

| Setting | Location | Enable For |
|---------|---------|-----------|
| VoiceOver | Vision > VoiceOver | All VoiceOver tests |
| Increase Contrast | Display > Increase Contrast | Section 7 — High Contrast |
| Reduce Motion | Accessibility > Motion > Reduce Motion | Section 7 — Reduce Motion |
| Reduce Transparency | Accessibility > Display > Reduce Transparency | Overlay transparency test |
| Keyboard Navigation | Keyboard > Keyboard Navigation | Section 5 — Keyboard |
| Full Keyboard Access | Keyboard > Keyboard Shortcuts > All Controls | Section 5 — Keyboard |

### VoiceOver Setup

1. Launch VoiceOver: press `Cmd+F5` or navigate via System Settings.
2. Set verbosity to maximum: **VoiceOver Utility > Verbosity > All**.
3. Enable "Speak items under mouse cursor" to aid cursor-based auditing.
4. Keep **Accessibility Inspector** open alongside VoiceOver for tree inspection.
5. Disable "Cursor tracking follows VoiceOver cursor" during keyboard-only tests.

### Accessibility Inspector Setup

1. Open Xcode > Open Developer Tool > Accessibility Inspector.
2. Choose the VaulType process from the target picker.
3. Enable **Audit** tab to run automated checks per-window.
4. Enable **Inspection** mode (crosshair icon) to click-inspect any element.

### Running the Automated Test Suite

```bash
xcodebuild test \
  -scheme VaulType \
  -destination 'platform=macOS' \
  -only-testing:VaulTypeTests/AccessibilityAuditTests
```

All tests in `AccessibilityAuditTests` must pass before a release is considered audited.

---

## 1. Perceivable

### 1.1 — Text Alternatives for Non-Text Content (WCAG 1.1.1, Level A)

Every non-text element (icon, image, graphic, progress indicator) must have a text alternative
conveying the same information, or be marked decorative so screen readers skip it.

**General rule applied in VaulType codebase:**
- Decorative SF Symbols use `.accessibilityHidden(true)`.
- Combined elements use `.accessibilityElement(children: .combine)` + `.accessibilityLabel(...)`.
- Interactive controls use `.accessibilityLabel(...)` + `.accessibilityHint(...)`.

#### Menu Bar Popover — Icon Alternatives

| Element | Expected label / treatment | Pass | Fail | N/A | Notes |
|---------|--------------------------|------|------|-----|-------|
| Red circle (recording indicator) | `.accessibilityHidden(true)` — parent `HStack` combines to "Status: Recording" | | | | |
| ProgressView (processing indicator) | `.accessibilityHidden(true)` — parent `HStack` combines to "Status: Processing transcription" | | | | |
| Mode icon (`appState.activeMode.iconName`) | `.accessibilityHidden(true)` — parent combines to "Mode: <name>, Language: <code>" | | | | |
| Error triangle icon | `.accessibilityHidden(true)` — parent combines to "Error: <message>" | | | | |
| History button clock icon | Decorative within button; button label "History" sufficient | | | | |
| Settings gear icon | Decorative within button; button label "Settings" sufficient | | | | |
| Quit power icon | Decorative within button; button label "Quit VaulType" sufficient | | | | |

#### Overlay Window — Icon Alternatives

| Element | Expected label / treatment | Pass | Fail | N/A | Notes |
|---------|--------------------------|------|------|-----|-------|
| Mode icon in header | Hidden or combined with parent label | | | | |
| ProgressView (processing header) | Combined with "Processing..." text | | | | |
| ProgressView (transcribing body) | Combined with "Transcribing..." text | | | | |
| Edit pencil icon (Edit button) | `Label("Edit", systemImage:)` — SF label provides text automatically | | | | |

#### Onboarding Wizard — Icon Alternatives

| Element | Expected label / treatment | Pass | Fail | N/A | Notes |
|---------|--------------------------|------|------|-----|-------|
| Progress dot circles (5 total) | Parent combines to "Setup progress: step N of 5" | | | | |
| Individual step dots | Each has `.accessibilityLabel("Step N completed / current / N")` | | | | |
| Decorative illustrations (if any) | Must be `.accessibilityHidden(true)` | | | | |
| Permission shield/mic icons | Must have labels if used as standalone graphics | | | | |

#### Settings Tabs — Tab Icons

| Tab | SF Symbol | Expected treatment | Pass | Fail | N/A |
|-----|-----------|-------------------|------|------|-----|
| General | `gear.circle` | Tab label "General" provided by `Label` | | | |
| Audio | `waveform.circle` | Tab label "Audio" | | | |
| Processing | `sparkles` | Tab label "Processing" | | | |
| Models | `arrow.down.circle` | Tab label "Models" | | | |
| App Profiles | `apps.iphone` | Tab label "App Profiles" | | | |
| Vocabulary | `textformat.abc` | Tab label "Vocabulary" | | | |
| Language | `globe` | Tab label "Language" | | | |
| History | `clock.arrow.circlepath` | Tab label "History" | | | |
| Commands | `command` | Tab label "Commands" | | | |
| Plugins | `puzzlepiece.extension` | Tab label "Plugins" | | | |

Tab `Label` views automatically expose their text string as the accessibility label on macOS
`TabView`. Verify via Accessibility Inspector that the tab bar items show the string label, not
the SF Symbol name.

---

### 1.3 — Adaptable — Content Can Be Presented in Different Ways (WCAG 1.3.1–1.3.3, Level A)

#### 1.3.1 — Information and Relationships

| Criterion | Checklist Item | Pass | Fail | N/A | Notes |
|-----------|---------------|------|------|-----|-------|
| 1.3.1 | Settings tabs expose role "tab" in accessibility tree (Accessibility Inspector) | | | | |
| 1.3.1 | List items in History View expose row role | | | | |
| 1.3.1 | Form labels in Settings are programmatically associated with their controls | | | | |
| 1.3.1 | Section headings in Settings tabs (if any) exposed as headings | | | | |
| 1.3.1 | Group containers in Onboarding use `.accessibilityElement(children: .contain)` or `.combine` correctly | | | | |
| 1.3.1 | Error messages are adjacent to the control that caused them (or combined into the control's label) | | | | |

#### 1.3.2 — Meaningful Sequence

| Criterion | Checklist Item | Pass | Fail | N/A | Notes |
|-----------|---------------|------|------|-----|-------|
| 1.3.2 | VoiceOver reading order in Menu Bar Popover: Status → Mode → Last Transcription → Error (if shown) → Buttons | | | | |
| 1.3.2 | VoiceOver reading order in Overlay: Header (mode, language, status) → Content → Footer buttons | | | | |
| 1.3.2 | VoiceOver reading order in Onboarding: Progress indicator → Step content → Navigation buttons | | | | |
| 1.3.2 | VoiceOver reading order in History: Search field → Filters → Entry list → Detail/action panel | | | | |

#### 1.3.3 — Sensory Characteristics

| Criterion | Checklist Item | Pass | Fail | N/A | Notes |
|-----------|---------------|------|------|-----|-------|
| 1.3.3 | No instructions refer to shape/color/position alone (e.g., "click the red button") | | | | |
| 1.3.3 | Recording state communicated by text label, not only the red circle color | | | | |
| 1.3.3 | Processing state communicated by text label, not only the spinner animation | | | | |

---

### 1.4 — Distinguishable (WCAG 1.4.1–1.4.4, Level AA includes 1.4.3, 1.4.4)

#### 1.4.1 — Use of Color

| Criterion | Checklist Item | Pass | Fail | N/A | Notes |
|-----------|---------------|------|------|-----|-------|
| 1.4.1 | Error state in Menu Bar Popover conveyed by text "Error:" label, not orange color alone | | | | |
| 1.4.1 | Quit button text is red — must also be identifiable by position or label, not color alone | | | | |
| 1.4.1 | Onboarding progress dots — completed state conveyed by VoiceOver label, not fill color alone | | | | |
| 1.4.1 | Active/inactive processing mode in Settings — not distinguished by color alone | | | | |
| 1.4.1 | Favorites in History — star icon present; not indicated by color alone | | | | |

#### 1.4.3 — Contrast (Minimum) — 4.5:1 for normal text, 3:1 for large text (Level AA)

Measure with Color Contrast Analyser. Test in both light and dark appearance.

**Menu Bar Popover:**

| Text Element | Foreground | Background | Required Ratio | Measured Ratio | Pass | Fail |
|-------------|-----------|-----------|---------------|----------------|------|------|
| "Recording..." headline | `.primary` | popover bg | 4.5:1 | | | |
| "Processing..." headline | `.primary` | popover bg | 4.5:1 | | | |
| "Ready" (secondary) | `.secondary` | popover bg | 4.5:1 | | | |
| Mode name (caption, secondary) | `.secondary` | popover bg | 4.5:1 | | | |
| Language badge text | accent on accent/15% bg | 4.5:1 | | | | |
| "Last Transcription" label (caption) | `.secondary` | popover bg | 4.5:1 | | | |
| Last transcription body text | `.primary` | popover bg | 4.5:1 | | | |
| Error text (orange, caption) | `.orange` | popover bg | 4.5:1 | | | |
| Button text (History, Settings, Quit) | `.primary` / `.red` | popover bg | 4.5:1 | | | |

**Overlay Window:**

| Text Element | Foreground | Background | Required Ratio | Measured Ratio | Pass | Fail |
|-------------|-----------|-----------|---------------|----------------|------|------|
| Header mode text (caption) | `.secondary` | material/solid bg | 4.5:1 | | | |
| "Processing..." (caption2) | `.secondary` | material/solid bg | 4.5:1 | | | |
| Transcription body text | `.primary` | material/solid bg | 4.5:1 | | | |
| "Transcribing..." (secondary) | `.secondary` | material/solid bg | 4.5:1 | | | |
| "Waiting for transcription..." (tertiary) | `.tertiary` | material/solid bg | 4.5:1 | | | |
| Cancel button text | `.primary` | button bg | 4.5:1 | | | |
| Inject button text | white on accent | 4.5:1 | | | | |
| Dismiss button text | `.primary` | button bg | 4.5:1 | | | |
| Edit button text | `.primary` | button bg | 4.5:1 | | | |

Note: The overlay uses `.ultraThinMaterial` by default. Test with **Reduce Transparency** disabled
(material background) and enabled (solid `NSColor.windowBackgroundColor` background). Contrast
must pass in both states.

**Onboarding Wizard:**

| Text Element | Required Ratio | Pass | Fail | Notes |
|-------------|---------------|------|------|-------|
| Step headings | 3:1 (large text, bold) | | | |
| Step body text | 4.5:1 | | | |
| Button labels (Next, Allow, Download) | 4.5:1 | | | |
| Progress dot labels (if visible) | N/A — VoiceOver only | N/A | | |

**Settings Window (all tabs):**

| Text Category | Required Ratio | Pass | Fail | Notes |
|--------------|---------------|------|------|-------|
| Section headers | 3:1 (if large/bold) | | | |
| Control labels | 4.5:1 | | | |
| Picker/toggle labels | 4.5:1 | | | |
| Helper/description text (secondary) | 4.5:1 | | | |
| Disabled control text | 3:1 minimum | | | |

**History Window:**

| Text Category | Required Ratio | Pass | Fail | Notes |
|--------------|---------------|------|------|-------|
| Search field placeholder text | 4.5:1 | | | |
| Entry timestamp (secondary) | 4.5:1 | | | |
| Entry body text | 4.5:1 | | | |
| App name label (secondary) | 4.5:1 | | | |
| Filter picker text | 4.5:1 | | | |

#### 1.4.4 — Resize Text (Level AA)

| Criterion | Checklist Item | Pass | Fail | N/A | Notes |
|-----------|---------------|------|------|-----|-------|
| 1.4.4 | All text in VaulType respects macOS "Larger Text" setting (System Settings > Accessibility > Display > Larger Text) | | | | |
| 1.4.4 | Layout does not break or clip at larger text sizes | | | | |
| 1.4.4 | Overlay window height adjusts or scrolls when content grows with larger text | | | | |
| 1.4.4 | Settings tabs remain readable; no horizontal clipping of labels | | | | |

---

## 2. Operable

### 2.1 — Keyboard Accessible (WCAG 2.1.1–2.1.2, Level A)

Every interactive element must be reachable and operable with keyboard alone.

#### 2.1.1 — Keyboard

| Surface | Checklist Item | Pass | Fail | N/A | Notes |
|---------|---------------|------|------|-----|-------|
| Menu Bar | Open popover via keyboard (activate menu bar item with VoiceOver + Space) | | | | |
| Menu Bar Popover | Tab through all interactive elements: History button, Settings link, Quit button | | | | |
| Menu Bar Popover | Activate History button with Space/Return | | | | |
| Menu Bar Popover | Activate Settings link with Space/Return | | | | |
| Menu Bar Popover | Activate Quit button with Space/Return | | | | |
| Menu Bar Popover | Keyboard shortcut `Cmd+H` opens History window | | | | |
| Menu Bar Popover | Keyboard shortcut `Cmd+Q` quits app | | | | |
| Settings Window | `Cmd+,` opens Settings from anywhere | | | | |
| Settings Window | Arrow keys navigate between tabs | | | | |
| Settings Window | Tab navigates through controls within each tab | | | | |
| Settings Window | All toggles toggleable with Space | | | | |
| Settings Window | All text fields editable with keyboard | | | | |
| Settings Window | All pickers/dropdowns openable with Space and navigable with arrow keys | | | | |
| Overlay Window | `Cmd+E` enters edit mode | | | | |
| Overlay Window | In edit mode: Return/Enter confirms inject | | | | |
| Overlay Window | In edit mode: Escape cancels edit | | | | |
| Overlay Window | Dismiss button reachable and activatable by keyboard | | | | |
| Onboarding Wizard | All buttons (Next, Allow Microphone, Grant Accessibility, Download Model, Done) operable by keyboard | | | | |
| History Window | Tab to search field, type to search | | | | |
| History Window | Arrow keys to navigate entry list | | | | |
| History Window | Space/Return to select entry | | | | |
| History Window | Keyboard shortcut to delete selected entry (if defined) | | | | |
| History Window | Re-inject action reachable by keyboard | | | | |

#### 2.1.2 — No Keyboard Trap

| Criterion | Checklist Item | Pass | Fail | N/A | Notes |
|-----------|---------------|------|------|-----|-------|
| 2.1.2 | Overlay Window does not trap keyboard focus — Escape dismisses it | | | | |
| 2.1.2 | Onboarding Wizard does not trap focus — main app remains interactable if wizard is dismissed | | | | |
| 2.1.2 | Modal confirmation dialogs (e.g., delete entry) closeable with Escape | | | | |
| 2.1.2 | Settings Window closeable with `Cmd+W` at all times | | | | |

---

### 2.4 — Navigable (WCAG 2.4.3, 2.4.7, Level AA)

#### 2.4.3 — Focus Order

| Surface | Expected Tab/Focus Order | Pass | Fail | N/A | Notes |
|---------|------------------------|------|------|-----|-------|
| Menu Bar Popover | Status (read-only) → Mode (read-only) → Last Transcription (read-only) → Error (read-only) → History button → Settings link → Quit button | | | | |
| Overlay (display mode) | Header (read-only) → Content text → Edit button → Dismiss button | | | | |
| Overlay (edit mode) | Header (read-only) → TextEditor → Cancel button → Inject button | | | | |
| Onboarding step 0 (Welcome) | Heading → Body → Next button | | | | |
| Onboarding step 1 (Microphone) | Heading → Description → Allow Microphone button → Next button | | | | |
| Onboarding step 2 (Accessibility) | Heading → Description → Grant Accessibility button → Next button | | | | |
| Onboarding step 3 (Model Download) | Heading → Description → Download button → Next button (enabled after download) | | | | |
| Onboarding step 4 (Completion) | Heading → Description → Done button | | | | |
| History Window | Search field → Filter controls → Entry list rows → Detail panel → Action buttons | | | | |
| Settings: General | Update channel picker → Start at login toggle → Hotkey field → … | | | | |
| Settings: Audio | Input device picker → Sample rate → VAD threshold → … | | | | |
| Settings: Processing | Default mode picker → Language picker → … | | | | |
| Settings: Models | Model list → Download/delete buttons per model | | | | |
| Settings: App Profiles | App picker → Profile controls | | | | |
| Settings: Vocabulary | Add entry field → Vocabulary list → Edit/delete per entry | | | | |
| Settings: Language | Language picker → Dialect options | | | | |
| Settings: History | Retention count field → Age limit field → Clear history button | | | | |
| Settings: Commands | Wake phrase field → Command list → Enable/disable toggles | | | | |
| Settings: Plugins | Plugin list → Activate/deactivate toggles | | | | |

#### 2.4.7 — Focus Visible

| Criterion | Checklist Item | Pass | Fail | N/A | Notes |
|-----------|---------------|------|------|-----|-------|
| 2.4.7 | All interactive controls show a visible focus ring when navigated with keyboard (macOS default blue ring) | | | | |
| 2.4.7 | Focus ring visible in Menu Bar Popover on all buttons | | | | |
| 2.4.7 | Focus ring visible on Settings tab bar items | | | | |
| 2.4.7 | Focus ring visible on Overlay footer buttons | | | | |
| 2.4.7 | Focus ring visible on Onboarding buttons | | | | |
| 2.4.7 | Focus ring visible on History list rows and action buttons | | | | |
| 2.4.7 | Focus ring meets 3:1 contrast ratio against adjacent colors (WCAG 2.4.11, AA) | | | | |

---

## 3. Understandable

### 3.1 — Readable (WCAG 3.1.1, Level A)

| Criterion | Checklist Item | Pass | Fail | N/A | Notes |
|-----------|---------------|------|------|-----|-------|
| 3.1.1 | App language matches system locale (macOS localization via `Localizable.strings`) | | | | |
| 3.1.1 | VoiceOver uses correct language for spoken text (follows system language) | | | | |

---

### 3.2 — Predictable (WCAG 3.2.1–3.2.2, Level A)

#### 3.2.1 — On Focus

| Criterion | Checklist Item | Pass | Fail | N/A | Notes |
|-----------|---------------|------|------|-----|-------|
| 3.2.1 | Focusing on a Settings toggle does not automatically change its value | | | | |
| 3.2.1 | Focusing on a picker does not auto-select a different option | | | | |
| 3.2.1 | Focusing on the Onboarding "Download Model" button does not start download automatically | | | | |

#### 3.2.2 — On Input

| Criterion | Checklist Item | Pass | Fail | N/A | Notes |
|-----------|---------------|------|------|-----|-------|
| 3.2.2 | Toggling the processing mode toggle does not open a new window or navigate away unexpectedly | | | | |
| 3.2.2 | Changing the language picker in Settings does not trigger transcription or other side effects | | | | |
| 3.2.2 | Tab switching in Settings does not produce unexpected UI changes outside the tab panel | | | | |

---

### 3.3 — Input Assistance (WCAG 3.3.1–3.3.2, Level A)

#### 3.3.1 — Error Identification

| Criterion | Checklist Item | Pass | Fail | N/A | Notes |
|-----------|---------------|------|------|-----|-------|
| 3.3.1 | Errors in Settings fields (invalid hotkey, empty required field) are described in text | | | | |
| 3.3.1 | Error messages identify which field caused the error | | | | |
| 3.3.1 | Model download failure displays a text error, not only a color indicator | | | | |
| 3.3.1 | Permission denial in Onboarding is described in text with next steps | | | | |
| 3.3.1 | Transcription errors appear in Menu Bar Popover "Error:" section with text description | | | | |
| 3.3.1 | Error announcements are posted via `NSAccessibility.post(element:notification:)` (verified in `AccessibilityAuditTests.testAnnounceErrorDoesNotCrash`) | | | | |

#### 3.3.2 — Labels or Instructions

| Criterion | Checklist Item | Pass | Fail | N/A | Notes |
|-----------|---------------|------|------|-----|-------|
| 3.3.2 | Every text field in Settings has a visible label (not placeholder text alone) | | | | |
| 3.3.2 | Hotkey binding field has label explaining expected input format | | | | |
| 3.3.2 | Vocabulary entry fields have labels (Spoken form / Replacement) | | | | |
| 3.3.2 | Overlay TextEditor shows `.accessibilityHint("Modify the transcription before injecting")` | | | | |
| 3.3.2 | Onboarding steps include explanatory body text for each permission | | | | |

---

## 4. Robust

### 4.1 — Compatible (WCAG 4.1.2, 4.1.3, Level A/AA)

#### 4.1.2 — Name, Role, Value

| Criterion | Checklist Item | Pass | Fail | N/A | Notes |
|-----------|---------------|------|------|-----|-------|
| 4.1.2 | All interactive controls expose their name (label) in the accessibility tree | | | | |
| 4.1.2 | All interactive controls expose their role (button, textfield, checkbox, tab, etc.) | | | | |
| 4.1.2 | All state-bearing controls expose their value (toggle on/off, slider value, picker selection) | | | | |
| 4.1.2 | `isRecording` state exposed as VoiceOver announcement, not only visual change | | | | |
| 4.1.2 | `isProcessing` state exposed as VoiceOver announcement | | | | |
| 4.1.2 | Model download progress exposed as VoiceOver announcement or `accessibilityValue` | | | | |
| 4.1.2 | Onboarding step progress exposed ("Setup progress: step N of 5") | | | | |
| 4.1.2 | Disabled controls expose disabled state (greyed appearance + `isEnabled: false` in tree) | | | | |
| 4.1.2 | Overlay dismiss/inject buttons expose correct enabled/disabled state based on `overlayText` | | | | |

Run **Accessibility Inspector > Audit** on each window to auto-detect missing names/roles/values.

#### 4.1.3 — Status Messages (Level AA)

Status messages that are injected dynamically (not via focus change) must be announced by
assistive technology without receiving focus.

| Criterion | Checklist Item | Pass | Fail | N/A | Notes |
|-----------|---------------|------|------|-----|-------|
| 4.1.3 | "Recording started" — announced via `AppState.announceRecordingStarted()` → `NSAccessibility.post` | | | | |
| 4.1.3 | "Recording stopped / completed" — announced via `AppState.announceRecordingCompleted()` | | | | |
| 4.1.3 | "Processing transcription" — announced via `AppState.announceProcessing()` | | | | |
| 4.1.3 | "Processing complete" — announced via `AppState.announceProcessingComplete()` | | | | |
| 4.1.3 | "Text injected" — announced (implementation to be confirmed — create task if missing) | | | | |
| 4.1.3 | "Command executed" — announced (implementation to be confirmed) | | | | |
| 4.1.3 | Error messages — announced via `AppState.announceError(_:)` | | | | |
| 4.1.3 | Model download progress updates — announced periodically (not every percent) | | | | |
| 4.1.3 | All `NSAccessibility.post` calls verified crash-free in `AccessibilityAuditTests` | | | | |

---

## 5. Component-by-Component VoiceOver Walkthrough

Instructions: Enable VoiceOver (`Cmd+F5`). Navigate with `VO+Arrow` keys. Use `VO+Space` to
activate. Verify each element is reached, described correctly, and activatable.

### 5.1 — Menu Bar Popover (`MenuBarView`)

**Pre-condition:** App is running. VoiceOver active. Activate the VaulType menu bar item.

| Step | Action | Expected VoiceOver Output | Pass | Fail | Notes |
|------|--------|--------------------------|------|------|-------|
| 1 | Navigate to status area (idle) | "Status: Ready" | | | |
| 1a | Navigate to status area (recording) | "Status: Recording" | | | |
| 1b | Navigate to status area (processing) | "Status: Processing transcription" | | | |
| 2 | Navigate to mode/language area | "Mode: Clean" (or active mode name) — optionally "Language: EN" | | | |
| 3 | Navigate to Last Transcription section (if present) | "Last transcription: <text>" | | | |
| 4 | Navigate to Error section (if shown) | "Error: <error message>" | | | |
| 5 | Navigate to History button | "History, button" | | | |
| 5a | Read History button hint | "Opens the dictation history window" | | | |
| 5b | Activate History button | History window opens | | | |
| 6 | Navigate to Settings link | "Settings, button" | | | |
| 6a | Read Settings hint | "Opens the VaulType settings window" | | | |
| 6b | Activate Settings link | Settings window opens | | | |
| 7 | Navigate to Quit button | "Quit VaulType, button" | | | |
| 7a | Read Quit hint | "Exits the application" | | | |
| 8 | Verify no orphaned/unlabeled elements remain after step 7 | No unlabeled element announced | | | |

---

### 5.2 — Settings Window — All 10 Tabs

**Pre-condition:** Settings window open. VoiceOver active.

#### Tab Bar Navigation

| Step | Action | Expected Output | Pass | Fail | Notes |
|------|--------|----------------|------|------|-------|
| 1 | Navigate to tab bar | "tab group" or "toolbar" | | | |
| 2 | Move to General tab | "General, tab, 1 of 10" (or similar) | | | |
| 3 | Move to Audio tab | "Audio, tab, 2 of 10" | | | |
| 4 | Move to Processing tab | "Processing, tab, 3 of 10" | | | |
| 5 | Move to Models tab | "Models, tab, 4 of 10" | | | |
| 6 | Move to App Profiles tab | "App Profiles, tab, 5 of 10" | | | |
| 7 | Move to Vocabulary tab | "Vocabulary, tab, 6 of 10" | | | |
| 8 | Move to Language tab | "Language, tab, 7 of 10" | | | |
| 9 | Move to History tab | "History, tab, 8 of 10" | | | |
| 10 | Move to Commands tab | "Commands, tab, 9 of 10" | | | |
| 11 | Move to Plugins tab | "Plugins, tab, 10 of 10" | | | |

Note: macOS `TabView` announces tabs differently based on macOS version. Acceptable variations
include "selected" for the active tab. The text label must always be present.

#### General Tab

| Checklist Item | Pass | Fail | N/A | Notes |
|---------------|------|------|-----|-------|
| Start at login toggle — label announced | | | | |
| Start at login toggle — state (on/off) announced | | | | |
| Global hotkey binding field — label announced | | | | |
| Update channel picker — label and current value announced | | | | |
| Check for updates button — label announced | | | | |
| Version info text — readable by VoiceOver | | | | |

#### Audio Tab

| Checklist Item | Pass | Fail | N/A | Notes |
|---------------|------|------|-----|-------|
| Input device picker — label "Input device" or similar announced | | | | |
| Input device — current selection announced | | | | |
| Sample rate picker — label and current value announced | | | | |
| VAD threshold slider — label, value, and range announced | | | | |
| Silence duration field — label and value announced | | | | |

#### Processing Tab

| Checklist Item | Pass | Fail | N/A | Notes |
|---------------|------|------|-----|-------|
| Default mode picker — label and current value announced | | | | |
| Processing mode descriptions — readable | | | | |
| Overlay enable toggle — label and state announced | | | | |
| Overlay auto-inject delay field — label and value announced | | | | |

#### Models Tab

| Checklist Item | Pass | Fail | N/A | Notes |
|---------------|------|------|-----|-------|
| Model list — each row announces model name and download state | | | | |
| Download button per model — label includes model name | | | | |
| Delete button per model — label includes model name | | | | |
| Download progress — announced via VoiceOver (percentage or status text) | | | | |
| Default model indicator — announced | | | | |

#### App Profiles Tab

| Checklist Item | Pass | Fail | N/A | Notes |
|---------------|------|------|-----|-------|
| App picker — label announced | | | | |
| Selected app name announced | | | | |
| Per-app overrides (mode, vocabulary) — labels announced | | | | |
| Add profile button — label announced | | | | |
| Delete profile button — label includes app name | | | | |

#### Vocabulary Tab

| Checklist Item | Pass | Fail | N/A | Notes |
|---------------|------|------|-----|-------|
| "Spoken form" field — label announced | | | | |
| "Replacement" field — label announced | | | | |
| Add entry button — label announced | | | | |
| Vocabulary list — each row announces spoken form and replacement | | | | |
| Edit/delete buttons per entry — include entry name in label | | | | |

#### Language Tab

| Checklist Item | Pass | Fail | N/A | Notes |
|---------------|------|------|-----|-------|
| Language picker — label and current selection announced | | | | |
| Auto-detect language toggle — label and state announced | | | | |
| Dialect/region picker (if present) — label and value announced | | | | |

#### History Tab (Settings)

| Checklist Item | Pass | Fail | N/A | Notes |
|---------------|------|------|-----|-------|
| Retention count field — label and value announced | | | | |
| Age limit field — label and value announced | | | | |
| Favorites exemption toggle — label and state announced | | | | |
| Clear history button — label announced | | | | |
| Factory reset button — label announced | | | | |
| Destructive action confirmation dialog — announced before execution | | | | |

#### Commands Tab

| Checklist Item | Pass | Fail | N/A | Notes |
|---------------|------|------|-----|-------|
| Wake phrase field — label and current value announced | | | | |
| Command list — each row announces command name and enabled state | | | | |
| Enable/disable toggle per command — label includes command name | | | | |
| Add custom command button — label announced | | | | |
| Custom command name field — label announced | | | | |
| Action steps list — readable | | | | |

#### Plugins Tab

| Checklist Item | Pass | Fail | N/A | Notes |
|---------------|------|------|-----|-------|
| Plugin list — each row announces plugin name and activate/deactivate state | | | | |
| Activate/deactivate button per plugin — includes plugin name in label | | | | |
| "No plugins installed" empty state — announced | | | | |
| Plugin directory path — readable | | | | |

---

### 5.3 — Overlay Window (`OverlayContentView`)

**Pre-condition:** A dictation has been completed with overlay enabled. Overlay window is visible.
VoiceOver active.

| Step | Action | Expected VoiceOver Output | Pass | Fail | Notes |
|------|--------|--------------------------|------|------|-------|
| 1 | Navigate to header | Mode name + optionally language (e.g., "Clean, EN") | | | |
| 2 | Navigate to processing indicator (when processing) | "Processing..." or "Transcribing..." | | | |
| 3 | Navigate to transcription text (display mode) | Full transcription text announced | | | |
| 4 | Navigate to Edit button (display mode) | "Edit transcription, button" | | | |
| 4a | Read Edit button hint | "Opens the text editor to modify the transcription before injecting" | | | |
| 4b | Activate Edit button | Edit mode activated; TextEditor receives focus automatically | | | |
| 5 | In edit mode — TextEditor | "Edit transcription text, text editor, <current text>" | | | |
| 5a | Read TextEditor hint | "Modify the transcription before injecting" | | | |
| 6 | Navigate to Cancel button (edit mode) | "Cancel edit, button" | | | |
| 6a | Read Cancel hint | "Discards your edits and cancels injection" | | | |
| 6b | Activate Cancel | Returns to display mode; edit cancelled | | | |
| 7 | Navigate to Inject button (edit mode) | "Inject edited text, button" | | | |
| 7a | Read Inject hint | "Types your edited text at the cursor position" | | | |
| 7b | Activate Inject | Text injected; overlay dismisses | | | |
| 8 | Navigate to Dismiss button (display mode) | "Dismiss, button" (or "Dismiss overlay") | | | |
| 8a | Activate Dismiss | Overlay dismisses | | | |
| 9 | Empty state — navigate to content area | "Waiting for transcription..." | | | |

---

### 5.4 — Onboarding Wizard (`OnboardingView`)

**Pre-condition:** Fresh install or onboarding reset. Onboarding window visible. VoiceOver active.

#### Step 0 — Welcome

| Step | Expected VoiceOver Output | Pass | Fail | Notes |
|------|--------------------------|------|------|-------|
| Progress indicator | "Setup progress: step 1 of 5" | | | |
| Step heading | "Welcome to VaulType" (or similar) | | | |
| Step body | Description text read | | | |
| Next button | "Next, button" | | | |

#### Step 1 — Microphone Permission

| Step | Expected VoiceOver Output | Pass | Fail | Notes |
|------|--------------------------|------|------|-------|
| Progress indicator | "Setup progress: step 2 of 5" | | | |
| Step heading | Microphone permission heading | | | |
| Permission explanation | Body text read fully | | | |
| Allow Microphone button | "Allow Microphone Access, button" (or similar) | | | |
| Permission granted state | Some visual or textual acknowledgment announced | | | |
| Next button (enabled after grant) | "Next, button" | | | |

#### Step 2 — Accessibility Permission

| Step | Expected VoiceOver Output | Pass | Fail | Notes |
|------|--------------------------|------|------|-------|
| Progress indicator | "Setup progress: step 3 of 5" | | | |
| Explanation of accessibility use | Body text read | | | |
| Open System Settings button | Button label announced | | | |
| Permission granted state | Confirmed via text | | | |

#### Step 3 — Model Download

| Step | Expected VoiceOver Output | Pass | Fail | Notes |
|------|--------------------------|------|------|-------|
| Progress indicator | "Setup progress: step 4 of 5" | | | |
| Model name/description | Text read | | | |
| Download button | "Download, button" | | | |
| Download in progress | Progress announced (via VoiceOver notification or status text) | | | |
| Download complete | Completion state announced or text changes | | | |
| Next button (enabled after download) | "Next, button" | | | |

#### Step 4 — Completion

| Step | Expected VoiceOver Output | Pass | Fail | Notes |
|------|--------------------------|------|------|-------|
| Progress indicator | "Setup progress: step 5 of 5" | | | |
| Completion heading | Read | | | |
| Completion body | Read | | | |
| Done button | "Done, button" or "Get Started, button" | | | |
| Activate Done | Onboarding dismissed; main app usable | | | |

---

### 5.5 — History Window (`HistoryView`)

**Pre-condition:** History window open. Some dictation entries exist. VoiceOver active.

| Step | Action | Expected VoiceOver Output | Pass | Fail | Notes |
|------|--------|--------------------------|------|------|-------|
| 1 | Navigate to search field | "Search, text field" | | | |
| 1a | Type in search | Results update; VoiceOver announces count change or updates list | | | |
| 2 | Navigate to filter controls (app picker) | "Filter by app, popup button, All" | | | |
| 3 | Navigate to mode filter picker | "Filter by mode, popup button, All" | | | |
| 4 | Navigate to Favorites Only toggle | "Favorites only, checkbox, off" | | | |
| 5 | Navigate to date range fields (if present) | "From date" / "To date" announced | | | |
| 6 | Navigate to entry list | "dictation entries, list" or equivalent | | | |
| 6a | Navigate to first entry | "<output text preview>, <app name>, <timestamp>" | | | |
| 6b | Navigate to next entry | Second entry details announced | | | |
| 7 | Select an entry | Detail panel opens; VoiceOver shifts to detail | | | |
| 7a | Detail panel — full text | Text announced or readable | | | |
| 7b | Detail panel — Copy button | "Copy, button" or "Copy text, button" | | | |
| 7c | Detail panel — Re-inject button | "Re-inject, button" or similar with hint | | | |
| 7d | Detail panel — Favorite toggle | "Favorite, checkbox, off" | | | |
| 7e | Detail panel — Delete button | "Delete, button" + confirmation dialog | | | |
| 8 | Delete confirmation dialog | "Are you sure? Delete / Cancel" announced | | | |
| 8a | Cancel in dialog | Dialog dismissed; entry preserved | | | |
| 9 | Edit-and-reinject flow | Edit field focuses; Inject button announced | | | |
| 10 | Empty state (no entries) | "No dictation history" or similar announced | | | |
| 11 | Empty search results | "No results" or similar announced | | | |

---

## 6. Keyboard Navigation Checklist

### 6.1 — Tab Order Verification

Tab order must follow the logical reading order of the layout (top-to-bottom, left-to-right for
LTR locales). Verify with keyboard-only navigation (no mouse).

Enable **Full Keyboard Access** in System Settings > Keyboard before testing.

| Window / View | First Focusable Element | Last Focusable Element | Tab Cycles Correctly | Pass | Fail |
|--------------|------------------------|----------------------|---------------------|------|------|
| Menu Bar Popover | History button | Quit button | Yes — wraps to History | | |
| Settings Window | Tab bar item 0 (General) | Last control on active tab | Yes | | |
| Overlay (display) | Edit button | Dismiss button | Yes | | |
| Overlay (edit) | TextEditor | Inject button | Yes | | |
| Onboarding | First button on current step | Navigation button (Next/Done) | Yes | | |
| History Window | Search field | Last action button on selected entry | Yes | | |

### 6.2 — Essential Keyboard Shortcuts

| Shortcut | Action | Surface | Pass | Fail | Notes |
|----------|--------|---------|------|------|-------|
| `Cmd+,` | Open Settings | App-wide | | | |
| `Cmd+H` | Open History window | Menu Bar Popover | | | |
| `Cmd+Q` | Quit VaulType | Menu Bar Popover | | | |
| `Cmd+E` | Enter edit mode | Overlay | | | |
| `Return` | Confirm inject | Overlay (edit mode) | | | |
| `Escape` | Cancel edit / close overlay | Overlay | | | |
| `Cmd+W` | Close Settings window | Settings Window | | | |
| `Cmd+F` | Focus search (if implemented) | History Window | | | |
| Arrow keys | Navigate tab bar | Settings Window | | | |
| Arrow keys | Navigate list entries | History Window | | | |
| `Space` | Toggle checkbox/toggle | Settings tabs | | | |

### 6.3 — Global Hotkey (Push-to-Talk)

| Checklist Item | Pass | Fail | N/A | Notes |
|---------------|------|------|-----|-------|
| Default hotkey (fn) documented in Settings > General | | | | |
| Alternative hotkeys configurable for users who cannot press fn | | | | |
| Hotkey does not conflict with system VoiceOver shortcuts | | | | |
| Hotkey works when VoiceOver is active | | | | |
| Custom shortcut aliases (phrase → keyboard shortcut injection) operable without mouse | | | | |

---

## 7. State Announcement Checklist

Verify that each app state change is announced to assistive technology via
`NSAccessibility.post(element:notification:)` in `AppState`. Reference implementation:
`VaulTypeTests/AccessibilityAuditTests.swift`.

| State Change | Announcement Method | Expected Spoken Text (approximate) | Automated Test | Pass | Fail |
|-------------|--------------------|------------------------------------|---------------|------|------|
| Recording started | `announceRecordingStarted()` | "Recording started" | `testAnnounceRecordingStartedDoesNotCrash` | | |
| Recording stopped | `announceRecordingCompleted()` | "Recording stopped" | `testAnnounceRecordingCompletedDoesNotCrash` | | |
| Processing started | `announceProcessing()` | "Processing transcription" | `testAnnounceProcessingDoesNotCrash` | | |
| Processing complete | `announceProcessingComplete()` | "Processing complete" | `testAnnounceProcessingCompleteDoesNotCrash` | | |
| Error occurred | `announceError(_:)` | "Error: <message>" | `testAnnounceErrorDoesNotCrash` | | |
| Text injected | Custom announcement (verify exists) | "Text injected" | Create test if missing | | |
| Command executed (success) | Custom announcement (verify exists) | "Command executed: <name>" | Create test if missing | | |
| Command failed | `announceError(_:)` | "Command failed: <reason>" | `testAnnounceErrorDoesNotCrash` | | |
| Model download progress | Periodic announcement (verify exists) | "Downloading model: N percent" | Create test if missing | | |
| Model download complete | Custom announcement (verify exists) | "Model download complete" | Create test if missing | | |
| Onboarding step change | Implicit (focus shifts to new step content) | Focus on new heading reads it | N/A | | |
| Settings saved/applied | Custom announcement (verify exists) | "Settings saved" | Create test if missing | | |

**Note on gaps:** Announcements for "Text injected", "Command executed", "Model download progress",
"Model download complete", and "Settings saved" are marked as "verify exists" because their
implementation was not confirmed in the reviewed source files at audit time. If these announcements
are absent, create DevTrack tasks to add them and re-audit those rows.

---

## 8. High Contrast and Reduce Motion

### 8.1 — High Contrast Mode

Enable **System Settings > Accessibility > Display > Increase Contrast** before testing.

**Code reference:** `AppState.prefersHighContrast` mirrors
`NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast`. The overlay border width
increases to 2px and opacity increases to 0.5 when `prefersHighContrast` is true
(`OverlayContentView` line 51–55).

| Component | Checklist Item | Pass | Fail | N/A | Notes |
|-----------|---------------|------|------|-----|-------|
| Overlay border | Border visible at 2px / 0.5 opacity when contrast enabled | | | | |
| Overlay border | Colour contrast of border against window bg ≥ 3:1 | | | | |
| Menu Bar status text | Foreground/background contrast ≥ 4.5:1 in high contrast mode | | | | |
| Settings controls | All labels, toggles, pickers readable in high contrast | | | | |
| History entries | Text remains readable against row background in high contrast | | | | |
| Onboarding buttons | Button fills and text readable in high contrast | | | | |
| Focus rings | Focus ring visible and contrasting against all backgrounds | | | | |
| Active recording indicator | Red circle distinguishable from background in high contrast | | | | |
| Error text (orange) | Orange text remains distinguishable in high contrast | | | | |
| Language badge | Accent colour badge readable in high contrast | | | | |
| Inject button (borderedProminent) | Blue fill + white text readable in high contrast | | | | |

### 8.2 — Reduce Motion

Enable **System Settings > Accessibility > Motion > Reduce Motion** before testing.

**Code reference:** `AppState.prefersReducedMotion` mirrors
`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`. `OnboardingView` reads
`@Environment(\.accessibilityReduceMotion)`. `HistoryView` also reads `accessibilityReduceMotion`.

| Component | Checklist Item | Pass | Fail | N/A | Notes |
|-----------|---------------|------|------|-----|-------|
| Onboarding step transitions | Cross-fade or instant switch (no slide animation) when reduce motion enabled | | | | |
| Onboarding progress dots | Dot fill changes instantly (no spring animation) | | | | |
| History list insertions | Rows appear without slide-in animation | | | | |
| Overlay appearance | Overlay appears without scale/fade animation | | | | |
| ProgressView spinners | Spinners exempt — they are functional indicators, not decorative | | | | |
| Menu Bar popover open/close | Uses system default (controlled by macOS) | | | | |
| Any custom spring/bounce animations | Must check `prefersReducedMotion` / `accessibilityReduceMotion` and remove animation | | | | |

### 8.3 — Reduce Transparency

Enable **System Settings > Accessibility > Display > Reduce Transparency** before testing.

**Code reference:** `AppState.prefersReducedTransparency` mirrors
`NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency`.
`OverlayContentView` uses `appState.prefersReducedTransparency` to switch between `.ultraThinMaterial`
and solid `NSColor.windowBackgroundColor`. `OverlayWindow.applyTransparencyPreference(appState:)`
sets `isOpaque = true` and `backgroundColor = .windowBackgroundColor` when pref is active.

| Component | Checklist Item | Pass | Fail | N/A | Notes |
|-----------|---------------|------|------|-----|-------|
| Overlay background | Solid background applied instead of material when reduce transparency enabled | | | | |
| Overlay opacity | `OverlayWindow.isOpaque == true` when reduce transparency enabled (verified by `testOverlayWindowIsOpaqueWhenReducedTransparencyActive`) | | | | |
| Text contrast on overlay | Solid bg ensures text contrast ≥ 4.5:1 | | | | |
| Menu Bar Popover | System handles transparency; no custom material to override | | | | |
| Settings Window | Standard NSWindow; no custom material | | | | |

---

## 9. Results Template

Use this table to record the outcome of each audit run. One row per WCAG success criterion.

| WCAG SC | Level | Criterion | Status | Date Tested | Tester | Notes |
|---------|-------|-----------|--------|-------------|--------|-------|
| 1.1.1 | A | Non-text Content | | | | |
| 1.3.1 | A | Info and Relationships | | | | |
| 1.3.2 | A | Meaningful Sequence | | | | |
| 1.3.3 | A | Sensory Characteristics | | | | |
| 1.4.1 | A | Use of Color | | | | |
| 1.4.3 | AA | Contrast (Minimum) | | | | |
| 1.4.4 | AA | Resize Text | | | | |
| 2.1.1 | A | Keyboard | | | | |
| 2.1.2 | A | No Keyboard Trap | | | | |
| 2.4.3 | A | Focus Order | | | | |
| 2.4.7 | AA | Focus Visible | | | | |
| 3.1.1 | A | Language of Page | | | | |
| 3.2.1 | A | On Focus | | | | |
| 3.2.2 | A | On Input | | | | |
| 3.3.1 | A | Error Identification | | | | |
| 3.3.2 | A | Labels or Instructions | | | | |
| 4.1.2 | A | Name, Role, Value | | | | |
| 4.1.3 | AA | Status Messages | | | | |

**Status values:** `Pass` | `Fail` | `Partial` | `N/A` | `Not Tested`

---

## 10. Known Issues and Recommended Follow-Up Tasks

The following gaps were identified during the initial audit document creation based on code review.
Create DevTrack tasks for each before the next audit cycle.

| Issue | Severity | Affected Surface | Recommended Action |
|-------|---------|----------------|-------------------|
| "Text injected" VoiceOver announcement not confirmed in code | High | Overlay / Injection pipeline | Add `announceStateChange("Text injected")` call in `TextInjectionService` after successful injection |
| "Command executed" announcement not confirmed | High | Commands pipeline | Add announcement in `CommandExecutor` on success and failure paths |
| Model download progress announcement not confirmed | Medium | Models tab | Add periodic `announceStateChange` calls in `ModelManager` download handler |
| "Settings saved" announcement not confirmed | Low | Settings Window | Add announcement when settings are persisted |
| Overlay header mode/language area lacks `.accessibilityLabel` | Medium | Overlay Window | Add combined accessibility label to the header `HStack` in `OverlayContentView` |
| Overlay processing `ProgressView` in header lacks accessible text | Medium | Overlay Window | Add `.accessibilityElement(children: .combine)` + label to processing `HStack` in `headerBar` |
| "Waiting for transcription..." text uses `.tertiary` — contrast unconfirmed | Medium | Overlay Window | Measure `.tertiary` vs material background; adjust if below 4.5:1 |
| Settings per-tab audits require running app — cannot fully audit statically | Medium | All Settings tabs | Perform live VoiceOver walkthrough for each tab at release milestone |
| Vocabulary/Commands/App Profiles dynamic list item labels not verified | Medium | Settings tabs | Audit that dynamically generated list rows include item names in button labels |
| Custom keyboard shortcut injection may conflict with VoiceOver shortcuts | High | Commands / Injection | Test shortcut injection while VoiceOver is active; add conflict documentation |

---

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-02-20 | Initial audit document creation | Created from code review of Phase 5 codebase |

