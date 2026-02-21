import AppKit
import Foundation
import os

/// Dispatches parsed voice commands to the appropriate handler.
/// Checks command registry enabled state and permissions before execution.
@Observable
final class CommandExecutor {
    private let registry: CommandRegistry

    init(registry: CommandRegistry) {
        self.registry = registry
    }

    /// Execute a single parsed command.
    func execute(_ command: ParsedCommand) async -> CommandResult {
        // Check if command is enabled
        guard registry.isEnabled(command.intent) else {
            Logger.commands.info("Command disabled: \(command.intent.rawValue)")
            return CommandResult(
                success: false,
                message: "\(command.intent.displayName) is disabled",
                intent: command.intent
            )
        }

        // Check accessibility permission for window management commands
        if command.intent.category == .windowManagement && command.intent != .fullScreenToggle {
            guard AXIsProcessTrusted() else {
                Logger.commands.warning("Accessibility permission required for \(command.intent.rawValue)")
                return CommandResult(
                    success: false,
                    message: "Accessibility permission required for window management",
                    intent: command.intent
                )
            }
        }

        Logger.commands.info("Executing command: \(command.intent.rawValue)")

        do {
            let message = try await dispatch(command)
            Logger.commands.info("Command succeeded: \(command.intent.rawValue)")
            return CommandResult(success: true, message: message, intent: command.intent)
        } catch {
            Logger.commands.error("Command failed: \(command.intent.rawValue) — \(error.localizedDescription)")
            return CommandResult(
                success: false,
                message: error.localizedDescription,
                intent: command.intent
            )
        }
    }

    /// Execute a chain of commands sequentially. Stops on first failure.
    func executeChain(_ commands: [ParsedCommand]) async -> [CommandResult] {
        var results: [CommandResult] = []
        for command in commands {
            let result = await execute(command)
            results.append(result)
            if !result.success {
                Logger.commands.warning("Chain stopped at \(command.intent.rawValue): \(result.message)")
                break
            }
        }
        return results
    }

    // MARK: - Dispatch

    private func dispatch(_ command: ParsedCommand) async throws -> String {
        switch command.intent {
        // App Management
        case .openApp:
            return try await handleOpenApp(command.entities["appName"] ?? "")
        case .switchToApp:
            return try handleSwitchToApp(command.entities["appName"] ?? "")
        case .closeApp:
            return try await handleCloseApp(command.entities["appName"] ?? "")
        case .quitApp:
            return try handleQuitApp(command.entities["appName"] ?? "")
        case .hideApp:
            return try handleHideApp(command.entities["appName"] ?? "")
        case .showAllWindows:
            return try handleShowAllWindows()

        // Window Management
        case .moveWindowLeft:
            return try handleTileWindow(.left)
        case .moveWindowRight:
            return try handleTileWindow(.right)
        case .maximizeWindow:
            return try handleTileWindow(.maximize)
        case .minimizeWindow:
            return try handleMinimizeWindow()
        case .centerWindow:
            return try handleTileWindow(.center)
        case .fullScreenToggle:
            return try handleFullScreenToggle()
        case .moveToNextScreen:
            return try handleMoveToNextScreen()

        // System Control
        case .volumeUp:
            return try await handleMediaKey(.volumeUp)
        case .volumeDown:
            return try await handleMediaKey(.volumeDown)
        case .volumeMute:
            return try await handleMediaKey(.mute)
        case .volumeSet:
            let level = command.entities["level"] ?? "50"
            return try await handleSetVolume(level)
        case .brightnessUp:
            return try await handleMediaKey(.brightnessUp)
        case .brightnessDown:
            return try await handleMediaKey(.brightnessDown)
        case .doNotDisturbToggle:
            return try await handleDNDToggle()
        case .darkModeToggle:
            return try await handleDarkModeToggle()
        case .lockScreen:
            return try await handleLockScreen()
        case .takeScreenshot:
            return try await handleScreenshot()

        // Keyboard Shortcuts
        case .injectShortcut:
            return try handleInjectShortcut(
                modifiers: command.entities["modifiers"] ?? "",
                key: command.entities["key"] ?? ""
            )
        case .runShortcut:
            return try await handleRunShortcut(command.entities["shortcutName"] ?? "")
        case .customAlias:
            throw CommandError.executionFailed("Custom alias resolved at pipeline level")
        }
    }

    // MARK: - App Management Handlers

    private func handleOpenApp(_ name: String) async throws -> String {
        guard !name.isEmpty else { throw CommandError.missingEntity("appName") }

        // Try to find by name in running apps first
        if let app = findRunningApp(named: name) {
            app.activate(options: .activateAllWindows)
            return "Activated \(app.localizedName ?? name)"
        }

        // Try to open by name via NSWorkspace
        let workspace = NSWorkspace.shared
        if let url = workspace.urlForApplication(withBundleIdentifier: bundleIdGuess(for: name)) {
            let config = NSWorkspace.OpenConfiguration()
            try await workspace.openApplication(at: url, configuration: config)
            return "Opened \(name)"
        }

        // Search Applications folder
        let appsDir = URL(fileURLWithPath: "/Applications")
        let appURL = appsDir.appendingPathComponent("\(name).app")
        if FileManager.default.fileExists(atPath: appURL.path) {
            let config = NSWorkspace.OpenConfiguration()
            try await workspace.openApplication(at: appURL, configuration: config)
            return "Opened \(name)"
        }

        // Try user Applications
        let userAppsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications")
        let userAppURL = userAppsDir.appendingPathComponent("\(name).app")
        if FileManager.default.fileExists(atPath: userAppURL.path) {
            let config = NSWorkspace.OpenConfiguration()
            try await workspace.openApplication(at: userAppURL, configuration: config)
            return "Opened \(name)"
        }

        throw CommandError.appNotFound(name)
    }

    private func handleSwitchToApp(_ name: String) throws -> String {
        guard !name.isEmpty else { throw CommandError.missingEntity("appName") }
        guard let app = findRunningApp(named: name) else {
            throw CommandError.appNotRunning(name)
        }
        app.activate(options: .activateAllWindows)
        return "Switched to \(app.localizedName ?? name)"
    }

    private func handleCloseApp(_ name: String) async throws -> String {
        guard !name.isEmpty else { throw CommandError.missingEntity("appName") }
        guard let app = findRunningApp(named: name) else {
            throw CommandError.appNotRunning(name)
        }
        // Activate the target app first so Cmd+W goes to the right window
        app.activate(options: .activateAllWindows)
        // Brief delay for activation to complete
        try await Task.sleep(for: .milliseconds(100))
        sendKeyEvent(keyCode: 13, flags: .maskCommand) // W key
        return "Closed window in \(app.localizedName ?? name)"
    }

    private func handleQuitApp(_ name: String) throws -> String {
        guard !name.isEmpty else { throw CommandError.missingEntity("appName") }
        guard let app = findRunningApp(named: name) else {
            throw CommandError.appNotRunning(name)
        }
        app.terminate()
        return "Quit \(app.localizedName ?? name)"
    }

    private func handleHideApp(_ name: String) throws -> String {
        guard !name.isEmpty else { throw CommandError.missingEntity("appName") }
        guard let app = findRunningApp(named: name) else {
            throw CommandError.appNotRunning(name)
        }
        app.hide()
        return "Hid \(app.localizedName ?? name)"
    }

    private func handleShowAllWindows() throws -> String {
        // Ctrl+Up Arrow is the default Mission Control shortcut (no accessibility required)
        sendKeyEvent(keyCode: 126, flags: .maskControl) // Up Arrow key
        return "Showing Mission Control"
    }

    // MARK: - Window Management Handlers

    private enum TilePosition {
        case left, right, maximize, center
    }

    private func handleTileWindow(_ position: TilePosition) throws -> String {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            throw CommandError.executionFailed("No frontmost application")
        }

        let appRef = AXUIElementCreateApplication(frontApp.processIdentifier)
        var windowValue: AnyObject?
        guard AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
              let window = windowValue else {
            throw CommandError.executionFailed("No focused window")
        }

        // AXUIElement is a CFTypeRef — cast always succeeds for AnyObject
        let windowRef = window as! AXUIElement

        guard let screen = NSScreen.main else {
            throw CommandError.executionFailed("No main screen")
        }

        let frame = screen.visibleFrame
        var newOrigin: CGPoint
        var newSize: CGSize

        switch position {
        case .left:
            newOrigin = CGPoint(x: frame.origin.x, y: screen.frame.height - frame.maxY)
            newSize = CGSize(width: frame.width / 2, height: frame.height)
        case .right:
            newOrigin = CGPoint(x: frame.origin.x + frame.width / 2, y: screen.frame.height - frame.maxY)
            newSize = CGSize(width: frame.width / 2, height: frame.height)
        case .maximize:
            newOrigin = CGPoint(x: frame.origin.x, y: screen.frame.height - frame.maxY)
            newSize = CGSize(width: frame.width, height: frame.height)
        case .center:
            let windowWidth = frame.width * 0.6
            let windowHeight = frame.height * 0.7
            newOrigin = CGPoint(
                x: frame.origin.x + (frame.width - windowWidth) / 2,
                y: screen.frame.height - frame.maxY + (frame.height - windowHeight) / 2
            )
            newSize = CGSize(width: windowWidth, height: windowHeight)
        }

        var posPoint = newOrigin
        var sizeVal = newSize
        guard let positionValue = AXValueCreate(.cgPoint, &posPoint),
              let sizeValue = AXValueCreate(.cgSize, &sizeVal) else {
            throw CommandError.executionFailed("Failed to create accessibility values")
        }

        let posResult = AXUIElementSetAttributeValue(windowRef, kAXPositionAttribute as CFString, positionValue)
        let sizeResult = AXUIElementSetAttributeValue(windowRef, kAXSizeAttribute as CFString, sizeValue)
        if posResult != .success {
            Logger.commands.warning("Failed to set window position: \(posResult.rawValue)")
        }
        if sizeResult != .success {
            Logger.commands.warning("Failed to set window size: \(sizeResult.rawValue)")
        }

        let posName: String
        switch position {
        case .maximize: posName = "maximized"
        case .center: posName = "centered"
        case .left: posName = "tiled left"
        case .right: posName = "tiled right"
        }
        return "Window \(posName)"
    }

    private func handleMinimizeWindow() throws -> String {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            throw CommandError.executionFailed("No frontmost application")
        }

        let appRef = AXUIElementCreateApplication(frontApp.processIdentifier)
        var windowValue: AnyObject?
        guard AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
              let window = windowValue else {
            throw CommandError.executionFailed("No focused window")
        }

        let windowRef = window as! AXUIElement
        let result = AXUIElementSetAttributeValue(windowRef, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        if result != .success {
            Logger.commands.warning("Failed to minimize window: \(result.rawValue)")
        }
        return "Window minimized"
    }

    private func handleFullScreenToggle() throws -> String {
        // Ctrl+Cmd+F toggles native full screen
        sendKeyEvent(keyCode: 3, flags: [.maskCommand, .maskControl]) // F key
        return "Toggled full screen"
    }

    private func handleMoveToNextScreen() throws -> String {
        let screens = NSScreen.screens
        guard screens.count > 1 else {
            throw CommandError.executionFailed("Only one display connected")
        }

        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            throw CommandError.executionFailed("No frontmost application")
        }

        let appRef = AXUIElementCreateApplication(frontApp.processIdentifier)
        var windowValue: AnyObject?
        guard AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
              let window = windowValue else {
            throw CommandError.executionFailed("No focused window")
        }

        let windowRef = window as! AXUIElement

        // Get current window position
        var posValue: AnyObject?
        AXUIElementCopyAttributeValue(windowRef, kAXPositionAttribute as CFString, &posValue)
        var currentPos = CGPoint.zero
        if let val = posValue {
            // AXValue is a CFTypeRef — cast always succeeds for AnyObject
            AXValueGetValue(val as! AXValue, .cgPoint, &currentPos)
        }

        // Find which screen the window is on
        let currentScreenIndex = screens.firstIndex { screen in
            return currentPos.x >= screen.frame.origin.x && currentPos.x < screen.frame.maxX
        } ?? 0

        // Move to next screen
        let nextIndex = (currentScreenIndex + 1) % screens.count
        let nextScreen = screens[nextIndex]
        let visibleFrame = nextScreen.visibleFrame

        var newPos = CGPoint(
            x: visibleFrame.origin.x + 50,
            y: nextScreen.frame.height - visibleFrame.maxY + 50
        )
        guard let positionValue = AXValueCreate(.cgPoint, &newPos) else {
            throw CommandError.executionFailed("Failed to create accessibility value")
        }
        let moveResult = AXUIElementSetAttributeValue(windowRef, kAXPositionAttribute as CFString, positionValue)
        if moveResult != .success {
            Logger.commands.warning("Failed to move window to next screen: \(moveResult.rawValue)")
        }

        return "Moved window to next screen"
    }

    // MARK: - System Control Handlers

    private enum MediaAction {
        case volumeUp, volumeDown, mute, brightnessUp, brightnessDown
    }

    private func handleMediaKey(_ action: MediaAction) async throws -> String {
        let script: String
        let description: String

        switch action {
        case .volumeUp:
            script = "set volume output volume ((output volume of (get volume settings)) + 10)"
            description = "Volume increased"
        case .volumeDown:
            script = "set volume output volume ((output volume of (get volume settings)) - 10)"
            description = "Volume decreased"
        case .mute:
            script = "set volume output muted (not (output muted of (get volume settings)))"
            description = "Toggled mute"
        case .brightnessUp:
            script = """
                tell application "System Events"
                    key code 144
                end tell
                """
            description = "Brightness increased"
        case .brightnessDown:
            script = """
                tell application "System Events"
                    key code 145
                end tell
                """
            description = "Brightness decreased"
        }

        try await runProcess("/usr/bin/osascript", arguments: ["-e", script])
        return description
    }

    private func handleSetVolume(_ levelStr: String) async throws -> String {
        guard let level = Int(levelStr), level >= 0, level <= 100 else {
            throw CommandError.invalidArgument("Volume must be 0-100")
        }
        try await runProcess("/usr/bin/osascript", arguments: ["-e", "set volume output volume \(level)"])
        return "Volume set to \(level)%"
    }

    private func handleDNDToggle() async throws -> String {
        // Try toggling via Shortcuts CLI (requires user to have "Toggle Focus" shortcut)
        do {
            try await runProcess("/usr/bin/shortcuts", arguments: ["run", "Toggle Focus"])
            return "Toggled Do Not Disturb"
        } catch {
            Logger.commands.warning("DND toggle failed — no 'Toggle Focus' Shortcut found")
            throw CommandError.executionFailed("Do Not Disturb toggle requires a 'Toggle Focus' Shortcut")
        }
    }

    private func handleDarkModeToggle() async throws -> String {
        let script = """
            tell application "System Events"
                tell appearance preferences
                    set dark mode to not dark mode
                end tell
            end tell
            """
        try await runAppleScript(script)
        return "Toggled dark mode"
    }

    private func handleLockScreen() async throws -> String {
        try await runProcess("/usr/bin/pmset", arguments: ["displaysleepnow"])
        return "Screen locked"
    }

    private func handleScreenshot() async throws -> String {
        // Cmd+Shift+5 opens screenshot UI
        sendKeyEvent(keyCode: 23, flags: [.maskCommand, .maskShift]) // 5 key
        return "Screenshot tool opened"
    }

    // MARK: - Workflow Handlers

    private func handleRunShortcut(_ name: String) async throws -> String {
        guard !name.isEmpty else { throw CommandError.missingEntity("shortcutName") }

        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "shortcuts://run-shortcut?name=\(encoded)") else {
            throw CommandError.invalidArgument("Invalid shortcut name")
        }

        NSWorkspace.shared.open(url)
        return "Running shortcut: \(name)"
    }

    // MARK: - Keyboard Shortcut Handler

    private func handleInjectShortcut(modifiers modifiersStr: String, key keyStr: String) throws -> String {
        guard !keyStr.isEmpty else { throw CommandError.missingEntity("key") }

        // Parse modifier words into CGEventFlags
        var flags: CGEventFlags = []
        let modWords = modifiersStr.lowercased()
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }

        for word in modWords {
            switch word {
            case "command", "cmd": flags.insert(.maskCommand)
            case "control", "ctrl": flags.insert(.maskControl)
            case "option", "opt", "alt": flags.insert(.maskAlternate)
            case "shift": flags.insert(.maskShift)
            default: break
            }
        }

        guard !flags.isEmpty else {
            throw CommandError.invalidArgument("No modifier keys recognized in: \(modifiersStr)")
        }

        // Resolve key name to virtual key code
        guard let keyCode = HotkeyBinding.keyCodeForName(keyStr.lowercased()) else {
            throw CommandError.invalidArgument("Unknown key: \(keyStr)")
        }

        // Inject the keystroke via CGEvent
        sendKeyEvent(keyCode: keyCode, flags: flags)

        // Build human-readable description
        var parts: [String] = []
        if flags.contains(.maskControl) { parts.append("Ctrl") }
        if flags.contains(.maskAlternate) { parts.append("Opt") }
        if flags.contains(.maskShift) { parts.append("Shift") }
        if flags.contains(.maskCommand) { parts.append("Cmd") }
        parts.append(HotkeyBinding.keyCodeName(keyCode))

        return "Pressed \(parts.joined(separator: "+"))"
    }

    // MARK: - Helpers

    private func findRunningApp(named name: String) -> NSRunningApplication? {
        let lowered = name.lowercased()
        // Exact match first, then prefix match (avoids "mail" matching "Airmail")
        return NSWorkspace.shared.runningApplications.first { app in
            guard let appName = app.localizedName else { return false }
            return appName.lowercased() == lowered
        } ?? NSWorkspace.shared.runningApplications.first { app in
            guard let appName = app.localizedName else { return false }
            return appName.lowercased().hasPrefix(lowered)
        }
    }

    private func bundleIdGuess(for name: String) -> String {
        // Common app bundle ID mappings
        let known: [String: String] = [
            "safari": "com.apple.Safari",
            "finder": "com.apple.finder",
            "mail": "com.apple.mail",
            "messages": "com.apple.MobileSMS",
            "notes": "com.apple.Notes",
            "calendar": "com.apple.iCal",
            "music": "com.apple.Music",
            "maps": "com.apple.Maps",
            "photos": "com.apple.Photos",
            "preview": "com.apple.Preview",
            "terminal": "com.apple.Terminal",
            "xcode": "com.apple.dt.Xcode",
            "system preferences": "com.apple.systempreferences",
            "system settings": "com.apple.systempreferences",
            "activity monitor": "com.apple.ActivityMonitor",
            "calculator": "com.apple.calculator",
            "textedit": "com.apple.TextEdit",
            "dictionary": "com.apple.Dictionary",
            "books": "com.apple.iBooksX",
            "app store": "com.apple.AppStore",
            "facetime": "com.apple.FaceTime",
            "reminders": "com.apple.reminders",
            "shortcuts": "com.apple.shortcuts",
        ]
        return known[name.lowercased()] ?? "com.apple.\(name)"
    }

    private func sendKeyEvent(keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let src = CGEventSource(stateID: .hidSystemState)
        if let keyDown = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
           let keyUp = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) {
            keyDown.flags = flags
            keyUp.flags = flags
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        } else {
            Logger.commands.warning("Failed to create CGEvent for keyCode \(keyCode)")
        }
    }

    private func runAppleScript(_ source: String) async throws {
        try await runProcess("/usr/bin/osascript", arguments: ["-e", source])
    }

    /// Runs an external process asynchronously using a continuation to avoid blocking
    /// the cooperative thread pool.
    private func runProcess(_ path: String, arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments

            let pipe = Pipe()
            process.standardError = pipe

            process.terminationHandler = { finished in
                if finished.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                    let stderr = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let errorMsg = stderr.isEmpty ? "Process exited with code \(finished.terminationStatus)" : stderr
                    continuation.resume(throwing: CommandError.executionFailed(errorMsg.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

// MARK: - Command Error

enum CommandError: LocalizedError {
    case appNotFound(String)
    case appNotRunning(String)
    case missingEntity(String)
    case invalidArgument(String)
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .appNotFound(let name): "App not found: \(name)"
        case .appNotRunning(let name): "App not running: \(name)"
        case .missingEntity(let key): "Missing required: \(key)"
        case .invalidArgument(let msg): "Invalid argument: \(msg)"
        case .executionFailed(let msg): msg
        }
    }
}
