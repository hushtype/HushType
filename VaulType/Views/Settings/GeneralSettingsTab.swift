import Sparkle
import SwiftUI
import SwiftData
import ServiceManagement
import os

struct GeneralSettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @State private var settings: UserSettings?
    @State private var launchAtLogin = false
    @State private var hotkeyString = ""
    @State private var hotkeyError: String?
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
    }

    var body: some View {
        Form {
            Section("Input") {
                LabeledContent("Global Hotkey") {
                    HotkeyRecorderView(hotkeyString: $hotkeyString) { newValue in
                        applyHotkey(newValue)
                    }
                }
                .accessibilityLabel("Global Hotkey: \(hotkeyString)")
                .accessibilityHint("Press to record a new keyboard shortcut for starting dictation")
                if let error = hotkeyError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Hotkey error: \(error)")
                }

                Toggle("Push-to-Talk Mode", isOn: Binding(
                    get: { settings?.pushToTalkEnabled ?? false },
                    set: { newValue in
                        settings?.pushToTalkEnabled = newValue
                        saveSettings()
                    }
                ))
                .help("Hold hotkey to record, release to stop. When disabled, press to start, press again to stop.")
                .accessibilityHint("When on, hold the hotkey to record and release to stop. When off, press once to start and again to stop.")
            }

            Section("Startup & Appearance") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                        settings?.launchAtLogin = newValue
                        saveSettings()
                    }
                    .accessibilityHint("Automatically starts VaulType when you log in to your Mac")

                Toggle("Show Overlay After Dictation", isOn: Binding(
                    get: { settings?.showOverlayAfterDictation ?? true },
                    set: { newValue in
                        settings?.showOverlayAfterDictation = newValue
                        saveSettings()
                    }
                ))
                .help("Show a floating panel to review and edit text before injection")
                .accessibilityHint("Displays a floating panel showing the transcription so you can edit it before it is typed")

                Toggle("Play Sound Effects", isOn: Binding(
                    get: { settings?.playSoundEffects ?? true },
                    set: { newValue in
                        settings?.playSoundEffects = newValue
                        saveSettings()
                    }
                ))
                .help("Audio feedback when recording starts/stops")
                .accessibilityHint("Plays audio cues when recording starts and stops")
            }

            Section("Updates") {
                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
                .accessibilityHint("Checks if a newer version of VaulType is available")
            }

            Section("Text Injection") {
                Picker("Default Method", selection: Binding(
                    get: { settings?.defaultInjectionMethod ?? .auto },
                    set: { newValue in
                        settings?.defaultInjectionMethod = newValue
                        saveSettings()
                    }
                )) {
                    ForEach(InjectionMethod.allCases) { method in
                        Text(method.displayName).tag(method)
                    }
                }
                .help("How transcribed text is typed into the active app")
                .accessibilityHint("Choose how VaulType inserts transcribed text into applications")

                Text(injectionMethodHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Keystroke Delay") {
                    Stepper(
                        value: Binding(
                            get: { settings?.keystrokeDelay ?? 5 },
                            set: { newValue in
                                settings?.keystrokeDelay = newValue
                                saveSettings()
                            }
                        ),
                        in: 1...50,
                        step: 1
                    ) {
                        Text("\(settings?.keystrokeDelay ?? 5) ms")
                            .monospacedDigit()
                    }
                    .accessibilityLabel("Keystroke delay: \(settings?.keystrokeDelay ?? 5) milliseconds")
                    .accessibilityHint("Adjusts the pause between simulated keystrokes in CGEvent mode")
                }
                .help("Delay between simulated keystrokes (CGEvent mode)")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadSettings()
        }
    }

    private func loadSettings() {
        do {
            settings = try UserSettings.shared(in: modelContext)
            launchAtLogin = settings?.launchAtLogin ?? false
            hotkeyString = settings?.globalHotkey ?? "fn"
            Logger.ui.debug("Loaded user settings in General tab")
        } catch {
            Logger.ui.error("Failed to load UserSettings: \(error.localizedDescription)")
        }
    }

    private func applyHotkey(_ newValue: String) {
        guard let binding = HotkeyBinding.parse(newValue) else {
            hotkeyError = "Invalid shortcut. Try again."
            return
        }

        let conflicts = HotkeyManager.detectConflicts(for: binding)
        if !conflicts.isEmpty {
            hotkeyError = "May conflict with: \(conflicts.joined(separator: ", "))"
        } else {
            hotkeyError = nil
        }

        settings?.globalHotkey = newValue
        saveSettings()
        Logger.ui.info("Hotkey changed to: \(newValue)")
    }

    private var injectionMethodHelp: String {
        switch settings?.defaultInjectionMethod ?? .auto {
        case .auto:
            return "Automatically picks the best method for each app."
        case .cgEvent:
            return "Simulates keystrokes directly. Preserves clipboard but requires Accessibility permission."
        case .clipboard:
            return "Copies text to clipboard and pastes with Cmd+V. Works everywhere but overwrites clipboard."
        }
    }

    private func saveSettings() {
        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .userSettingsChanged, object: nil)
            Logger.ui.debug("Saved user settings from General tab")
        } catch {
            Logger.ui.error("Failed to save UserSettings: \(error.localizedDescription)")
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                Logger.ui.info("Registered app for launch at login")
            } else {
                try SMAppService.mainApp.unregister()
                Logger.ui.info("Unregistered app from launch at login")
            }
        } catch {
            Logger.ui.error("Failed to update launch at login: \(error.localizedDescription)")
        }
    }
}

#Preview {
    GeneralSettingsTab(updater: SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil).updater)
        .modelContainer(for: [UserSettings.self], inMemory: true)
        .frame(width: 500, height: 400)
}
