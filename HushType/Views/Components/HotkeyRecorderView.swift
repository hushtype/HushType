import Carbon.HIToolbox
import SwiftUI

// MARK: - HotkeyRecorderView

/// A key-capture control that records modifier+key combinations for hotkey configuration.
/// Click to start recording, press a key combo, and it saves the binding.
struct HotkeyRecorderView: View {
    @Binding var hotkeyString: String
    var onChanged: ((String) -> Void)?

    @State private var isRecording = false
    @State private var displayText = ""

    var body: some View {
        HStack(spacing: 6) {
            // Visible pill with centered text
            Text(isRecording ? "Press shortcut\u{2026}" : displayText)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(isRecording ? .secondary : .primary)
                .frame(width: 160, height: 24, alignment: .center)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isRecording ? Color.accentColor.opacity(0.1) : Color(.controlBackgroundColor))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isRecording ? Color.accentColor : Color(.separatorColor), lineWidth: 1)
                }
                // Hidden key capture NSView in background — out of layout flow
                .background {
                    HotkeyRecorderField(
                        isRecording: $isRecording,
                        onKeyRecorded: { recorded in
                            hotkeyString = recorded
                            displayText = formattedDisplay(recorded)
                            isRecording = false
                            onChanged?(recorded)
                        }
                    )
                    .frame(width: 0, height: 0)
                    .opacity(0)
                }
                .onTapGesture {
                    isRecording = true
                }

            if !isRecording {
                Button {
                    isRecording = true
                } label: {
                    Image(systemName: "record.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Click to record a new shortcut")
            } else {
                Button {
                    isRecording = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Cancel recording")
            }
        }
        .onAppear {
            displayText = formattedDisplay(hotkeyString)
        }
        .onChange(of: hotkeyString) { _, newValue in
            displayText = formattedDisplay(newValue)
        }
    }

    private func formattedDisplay(_ serialized: String) -> String {
        HotkeyBinding.parse(serialized)?.displayString ?? serialized
    }
}

// MARK: - HotkeyRecorderField (NSViewRepresentable)

/// An NSView-backed field that becomes first responder to capture keystrokes.
private struct HotkeyRecorderField: NSViewRepresentable {
    @Binding var isRecording: Bool
    var onKeyRecorded: (String) -> Void

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onKeyRecorded = onKeyRecorded
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.onKeyRecorded = onKeyRecorded
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        } else if nsView.window?.firstResponder === nsView {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nil)
            }
        }
    }
}

// MARK: - KeyCaptureView

/// NSView that captures keyboard events when first responder.
private final class KeyCaptureView: NSView {
    var onKeyRecorded: ((String) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard window?.firstResponder === self else { return }
        captureKey(from: event)
    }

    override func flagsChanged(with event: NSEvent) {
        guard window?.firstResponder === self else { return }

        // Capture standalone fn/Globe key
        if event.modifierFlags.contains(.function) {
            onKeyRecorded?("fn")
        }
    }

    // performKeyEquivalent is called BEFORE keyDown for modifier combos (Cmd+X, etc.)
    // We must capture here, otherwise returning true swallows the event.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        if event.type == .keyDown {
            captureKey(from: event)
        }
        return true // suppress system beep
    }

    private func captureKey(from event: NSEvent) {
        let keyCode = CGKeyCode(event.keyCode)
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])

        // Ignore bare modifier keys (Escape is fine as a standalone key)
        let isEscape = Int(event.keyCode) == kVK_Escape
        if !isEscape && keyCode == CGKeyCode(kVK_Command) || keyCode == CGKeyCode(kVK_Shift)
            || keyCode == CGKeyCode(kVK_Option) || keyCode == CGKeyCode(kVK_Control)
        {
            return
        }

        // Build serialized string matching HotkeyBinding.parse format
        var parts: [String] = []
        if mods.contains(.control) { parts.append("ctrl") }
        if mods.contains(.option) { parts.append("option") }
        if mods.contains(.shift) { parts.append("shift") }
        if mods.contains(.command) { parts.append("cmd") }

        let keyName = HotkeyBinding.keyCodeName(keyCode).lowercased()
        parts.append(keyName)

        let serialized = parts.joined(separator: "+")

        // Validate it parses correctly before accepting
        if HotkeyBinding.parse(serialized) != nil {
            onKeyRecorded?(serialized)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var hotkey = "fn"
    Form {
        LabeledContent("Global Hotkey") {
            HotkeyRecorderView(hotkeyString: $hotkey)
        }
    }
    .formStyle(.grouped)
    .frame(width: 400)
}
