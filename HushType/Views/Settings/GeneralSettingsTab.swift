import SwiftUI
import SwiftData
import ServiceManagement
import os

struct GeneralSettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @State private var settings: UserSettings?
    @State private var launchAtLogin = false
    @State private var hotkeyInput = ""
    @State private var hotkeyError: String?

    var body: some View {
        Form {
            Section("Input") {
                LabeledContent("Global Hotkey") {
                    HStack {
                        TextField("Hotkey", text: $hotkeyInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                            .onSubmit {
                                applyHotkey()
                            }
                        if let parsed = HotkeyBinding.parse(hotkeyInput) {
                            Text(parsed.displayString)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                }
                if let error = hotkeyError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Toggle("Push-to-Talk Mode", isOn: Binding(
                    get: { settings?.pushToTalkEnabled ?? false },
                    set: { newValue in
                        settings?.pushToTalkEnabled = newValue
                        saveSettings()
                    }
                ))
                .help("Hold hotkey to record, release to stop. When disabled, press to start, press again to stop.")
            }

            Section("Processing") {
                Picker("Default Mode", selection: Binding(
                    get: { settings?.defaultMode ?? .clean },
                    set: { newValue in
                        settings?.defaultMode = newValue
                        saveSettings()
                    }
                )) {
                    ForEach(ProcessingMode.allCases) { mode in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.displayName)
                            Text(mode.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(mode)
                    }
                }
                .help("Processing mode applied when no app-specific override exists")
            }

            Section("Startup & Appearance") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                        settings?.launchAtLogin = newValue
                        saveSettings()
                    }

                Toggle("Show Menu Bar Icon", isOn: Binding(
                    get: { settings?.showMenuBarIcon ?? true },
                    set: { newValue in
                        settings?.showMenuBarIcon = newValue
                        saveSettings()
                    }
                ))

                Toggle("Show Recording Indicator", isOn: Binding(
                    get: { settings?.showRecordingIndicator ?? true },
                    set: { newValue in
                        settings?.showRecordingIndicator = newValue
                        saveSettings()
                    }
                ))
                .help("Display floating indicator while recording")

                Toggle("Play Sound Effects", isOn: Binding(
                    get: { settings?.playSoundEffects ?? true },
                    set: { newValue in
                        settings?.playSoundEffects = newValue
                        saveSettings()
                    }
                ))
                .help("Audio feedback when recording starts/stops")
            }

            Section("Privacy & History") {
                LabeledContent("Max History Entries") {
                    TextField("Count", value: Binding(
                        get: { settings?.maxHistoryEntries ?? 5000 },
                        set: { newValue in
                            settings?.maxHistoryEntries = newValue
                            saveSettings()
                        }
                    ), format: .number)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    .help("Maximum number of dictation entries to retain (0 = unlimited)")
                }

                LabeledContent("Retention Days") {
                    TextField("Days", value: Binding(
                        get: { settings?.historyRetentionDays ?? 90 },
                        set: { newValue in
                            settings?.historyRetentionDays = newValue
                            saveSettings()
                        }
                    ), format: .number)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    .help("Number of days to retain entries (0 = indefinite)")
                }

                Toggle("Store Transcription Text", isOn: Binding(
                    get: { settings?.storeTranscriptionText ?? true },
                    set: { newValue in
                        settings?.storeTranscriptionText = newValue
                        saveSettings()
                    }
                ))
                .help("When disabled, only metadata is stored (duration, word count, timestamp)")
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
            hotkeyInput = settings?.globalHotkey ?? "fn"
            Logger.ui.debug("Loaded user settings in General tab")
        } catch {
            Logger.ui.error("Failed to load UserSettings: \(error.localizedDescription)")
        }
    }

    private func applyHotkey() {
        guard HotkeyBinding.parse(hotkeyInput) != nil else {
            hotkeyError = "Invalid hotkey format. Use: fn, cmd+shift+space, ctrl+alt+r, etc."
            return
        }

        let conflicts = HotkeyManager.detectConflicts(for: HotkeyBinding.parse(hotkeyInput)!)
        if !conflicts.isEmpty {
            hotkeyError = "May conflict with: \(conflicts.joined(separator: ", "))"
        } else {
            hotkeyError = nil
        }

        settings?.globalHotkey = hotkeyInput
        saveSettings()
        Logger.ui.info("Hotkey changed to: \(hotkeyInput)")
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
    GeneralSettingsTab()
        .modelContainer(for: [UserSettings.self], inMemory: true)
        .frame(width: 500, height: 400)
}
