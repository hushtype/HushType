import SwiftUI
import SwiftData
import os

struct AudioSettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @State private var settings: UserSettings?
    @State private var selectedDevice = "Default"
    @State private var availableDevices = ["Default", "MacBook Microphone", "External USB Mic"]

    var body: some View {
        Form {
            Section("Input Device") {
                Picker("Microphone", selection: $selectedDevice) {
                    ForEach(availableDevices, id: \.self) { device in
                        Text(device)
                            .tag(device)
                    }
                }
                .help("Audio input device for recording. Will be wired to AudioCaptureService in a future release.")

                Text("Device selection is a placeholder — audio service integration pending")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Voice Activity Detection") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("VAD Sensitivity")
                        Spacer()
                        Text(String(format: "%.2f", settings?.vadSensitivity ?? 0.5))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Slider(
                        value: Binding(
                            get: { settings?.vadSensitivity ?? 0.5 },
                            set: { newValue in
                                settings?.vadSensitivity = newValue
                                saveSettings()
                            }
                        ),
                        in: 0.0...1.0,
                        step: 0.05
                    )

                    Text("Lower values detect quieter speech but may trigger on background noise")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Audio Level") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Live Audio Input")
                        .font(.headline)

                    // Placeholder audio level meter
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.secondary.opacity(0.2))
                            .frame(height: 24)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(.green)
                            .frame(width: 50, height: 24)

                        Text("Preview")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                    }

                    Text("Audio level meter preview — will be connected to live input in future release")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Advanced") {
                Toggle("Use GPU Acceleration", isOn: Binding(
                    get: { settings?.useGPUAcceleration ?? true },
                    set: { newValue in
                        settings?.useGPUAcceleration = newValue
                        saveSettings()
                    }
                ))
                .help("Use Metal GPU for whisper.cpp inference (recommended)")

                LabeledContent("Whisper Threads") {
                    TextField("Threads", value: Binding(
                        get: { settings?.whisperThreadCount ?? 0 },
                        set: { newValue in
                            settings?.whisperThreadCount = newValue
                            saveSettings()
                        }
                    ), format: .number)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    .help("Number of CPU threads for inference (0 = auto-detect)")
                }
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
            Logger.ui.debug("Loaded user settings in Audio tab")
        } catch {
            Logger.ui.error("Failed to load UserSettings: \(error.localizedDescription)")
        }
    }

    private func saveSettings() {
        do {
            try modelContext.save()
            Logger.ui.debug("Saved user settings from Audio tab")
        } catch {
            Logger.ui.error("Failed to save UserSettings: \(error.localizedDescription)")
        }
    }
}

#Preview {
    AudioSettingsTab()
        .modelContainer(for: [UserSettings.self], inMemory: true)
        .frame(width: 500, height: 400)
}
