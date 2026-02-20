import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import os

// MARK: - Hotkey Binding

struct HotkeyBinding: Equatable, Identifiable {
    let id: UUID
    var keyCode: CGKeyCode
    var modifiers: CGEventFlags
    var mode: ProcessingMode?
    var isEnabled: Bool

    init(
        keyCode: CGKeyCode,
        modifiers: CGEventFlags,
        mode: ProcessingMode? = nil,
        isEnabled: Bool = true
    ) {
        self.id = UUID()
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.mode = mode
        self.isEnabled = isEnabled
    }

    /// Match against an NSEvent (used by global/local monitors).
    func matchesNSEvent(_ event: NSEvent) -> Bool {
        guard isEnabled else { return false }
        guard event.keyCode == keyCode else { return false }

        let eventMods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        var bindingMods: NSEvent.ModifierFlags = []
        if modifiers.contains(.maskCommand) { bindingMods.insert(.command) }
        if modifiers.contains(.maskShift) { bindingMods.insert(.shift) }
        if modifiers.contains(.maskAlternate) { bindingMods.insert(.option) }
        if modifiers.contains(.maskControl) { bindingMods.insert(.control) }

        return eventMods == bindingMods
    }

    // MARK: - Display

    var displayString: String {
        var parts: [String] = []
        if modifiers.contains(.maskControl) { parts.append("⌃") }
        if modifiers.contains(.maskAlternate) { parts.append("⌥") }
        if modifiers.contains(.maskShift) { parts.append("⇧") }
        if modifiers.contains(.maskCommand) { parts.append("⌘") }
        parts.append(Self.keyCodeName(keyCode))
        return parts.joined()
    }

    // MARK: - Serialization

    func serialize() -> String {
        // Standalone fn key — no modifiers prefix needed
        if modifiers.isEmpty, keyCode == CGKeyCode(kVK_Function) {
            return "fn"
        }
        var parts: [String] = []
        if modifiers.contains(.maskControl) { parts.append("ctrl") }
        if modifiers.contains(.maskAlternate) { parts.append("option") }
        if modifiers.contains(.maskShift) { parts.append("shift") }
        if modifiers.contains(.maskCommand) { parts.append("cmd") }
        parts.append(Self.keyCodeName(keyCode).lowercased())
        return parts.joined(separator: "+")
    }

    static func parse(_ string: String) -> HotkeyBinding? {
        let parts = string.lowercased().split(separator: "+").map(String.init)
        guard !parts.isEmpty else { return nil }

        // Handle standalone "fn" key (no modifiers required)
        if parts.count == 1, let keyCode = keyCodeForName(parts[0]) {
            return HotkeyBinding(keyCode: keyCode, modifiers: [])
        }

        guard parts.count >= 2 else { return nil }

        var modifiers: CGEventFlags = []
        for part in parts.dropLast() {
            switch part {
            case "cmd", "command": modifiers.insert(.maskCommand)
            case "shift": modifiers.insert(.maskShift)
            case "opt", "option", "alt": modifiers.insert(.maskAlternate)
            case "ctrl", "control": modifiers.insert(.maskControl)
            default: return nil
            }
        }

        guard let keyCode = keyCodeForName(parts.last!) else { return nil }
        return HotkeyBinding(keyCode: keyCode, modifiers: modifiers)
    }

    // MARK: - Key Code Mapping

    static func keyCodeForName(_ name: String) -> CGKeyCode? {
        let mapping: [String: Int] = [
            "space": kVK_Space, "return": kVK_Return, "enter": kVK_Return,
            "tab": kVK_Tab, "escape": kVK_Escape, "esc": kVK_Escape,
            "delete": kVK_Delete, "backspace": kVK_Delete,
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C,
            "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
            "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I,
            "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
            "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
            "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
            "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U,
            "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
            "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2,
            "3": kVK_ANSI_3, "4": kVK_ANSI_4, "5": kVK_ANSI_5,
            "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8,
            "9": kVK_ANSI_9,
            "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4,
            "f5": kVK_F5, "f6": kVK_F6, "f7": kVK_F7, "f8": kVK_F8,
            "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
            "fn": kVK_Function, "globe": kVK_Function,
        ]
        return mapping[name].map { CGKeyCode($0) }
    }

    static func keyCodeName(_ keyCode: CGKeyCode) -> String {
        let mapping: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "Return", kVK_Tab: "Tab",
            kVK_Escape: "Esc", kVK_Delete: "Delete", kVK_Function: "Fn",
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C",
            kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F",
            kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I",
            kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
            kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R",
            kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U",
            kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2",
            kVK_ANSI_3: "3", kVK_ANSI_4: "4", kVK_ANSI_5: "5",
            kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8",
            kVK_ANSI_9: "9",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
            kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
            kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        return mapping[Int(keyCode)] ?? "Key\(keyCode)"
    }
}

// MARK: - Hotkey Error

enum HotkeyError: LocalizedError {
    case alreadyRunning
    case maxBindingsReached

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            "Hotkey manager is already running"
        case .maxBindingsReached:
            "Maximum of \(HotkeyManager.maxBindings) hotkey bindings reached"
        }
    }
}

// MARK: - Hotkey Manager

@Observable
final class HotkeyManager: @unchecked Sendable {
    static let maxBindings = 4

    // MARK: - Observable State

    private(set) var isRunning = false

    // MARK: - Callbacks (set on main thread before start)

    @ObservationIgnored var onHotkeyDown: (@Sendable (HotkeyBinding) -> Void)?
    @ObservationIgnored var onHotkeyUp: (@Sendable (HotkeyBinding) -> Void)?

    // MARK: - Thread-Safe Bindings

    private var _bindings: [HotkeyBinding] = []
    private let bindingsLock = NSLock()

    var bindings: [HotkeyBinding] {
        bindingsLock.lock()
        defer { bindingsLock.unlock() }
        return _bindings
    }

    // MARK: - NSEvent Monitors

    private var globalMonitor: Any?
    private var localMonitor: Any?

    // MARK: - State Tracking

    /// Tracks whether the fn key is currently held (for push-to-talk).
    private var fnKeyDown = false

    // MARK: - Lifecycle

    func start() throws {
        guard !isRunning else { throw HotkeyError.alreadyRunning }

        // Global monitor: captures events from other apps (no accessibility needed)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.keyDown, .keyUp, .flagsChanged]
        ) { [weak self] event in
            self?.handleNSEvent(event)
        }

        // Local monitor: captures events when HushType itself is focused
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .keyUp, .flagsChanged]
        ) { [weak self] event in
            self?.handleNSEvent(event)
            return event
        }

        isRunning = true
        Logger.hotkey.info("Hotkey manager started with \(self.bindings.count) binding(s)")
    }

    func stop() {
        guard isRunning else { return }

        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }

        fnKeyDown = false
        isRunning = false
        Logger.hotkey.info("Hotkey manager stopped")
    }

    deinit {
        stop()
    }

    // MARK: - Binding Management

    func register(_ binding: HotkeyBinding) throws {
        bindingsLock.lock()
        defer { bindingsLock.unlock() }
        guard _bindings.count < Self.maxBindings else {
            throw HotkeyError.maxBindingsReached
        }
        _bindings.append(binding)
        Logger.hotkey.info("Registered hotkey: \(binding.displayString)")
    }

    func loadFromSettings(hotkey: String) throws {
        guard let binding = HotkeyBinding.parse(hotkey) else {
            Logger.hotkey.error("Failed to parse hotkey string: \(hotkey)")
            return
        }
        bindingsLock.lock()
        _bindings.removeAll()
        bindingsLock.unlock()
        try register(binding)
    }

    // MARK: - Event Handling

    private func handleNSEvent(_ event: NSEvent) {
        // Handle fn/Globe key via flagsChanged events
        if event.type == .flagsChanged {
            let currentBindings = bindings
            for binding in currentBindings where binding.keyCode == CGKeyCode(kVK_Function) && binding.isEnabled {
                let fnPressed = event.modifierFlags.contains(.function)
                if fnPressed && !fnKeyDown {
                    fnKeyDown = true
                    let callback = onHotkeyDown
                    DispatchQueue.main.async { callback?(binding) }
                    Logger.hotkey.debug("Fn key down")
                    return
                } else if !fnPressed && fnKeyDown {
                    fnKeyDown = false
                    let callback = onHotkeyUp
                    DispatchQueue.main.async { callback?(binding) }
                    Logger.hotkey.debug("Fn key up")
                    return
                }
            }
            return
        }

        // Handle regular key events
        guard event.type == .keyDown || event.type == .keyUp else { return }

        let currentBindings = bindings
        for binding in currentBindings {
            if binding.matchesNSEvent(event) {
                if event.type == .keyDown {
                    let callback = onHotkeyDown
                    DispatchQueue.main.async { callback?(binding) }
                    Logger.hotkey.debug("Hotkey down: \(binding.displayString)")
                } else {
                    let callback = onHotkeyUp
                    DispatchQueue.main.async { callback?(binding) }
                    Logger.hotkey.debug("Hotkey up: \(binding.displayString)")
                }
                return
            }
        }
    }

    // MARK: - Conflict Detection

    static func detectConflicts(for binding: HotkeyBinding) -> [String] {
        var conflicts: [String] = []
        let knownShortcuts: [(String, CGKeyCode, CGEventFlags)] = [
            ("Spotlight", CGKeyCode(kVK_Space), .maskCommand),
        ]
        for (name, keyCode, modifiers) in knownShortcuts {
            let bindingMods = binding.modifiers.intersection(
                [.maskCommand, .maskShift, .maskAlternate, .maskControl])
            if keyCode == binding.keyCode && modifiers == bindingMods {
                conflicts.append(name)
            }
        }
        return conflicts
    }
}
