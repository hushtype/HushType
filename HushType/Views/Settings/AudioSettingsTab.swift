import SwiftUI
import SwiftData
import os

struct AudioSettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @State private var settings: UserSettings?
    @State private var selectedDeviceID: String = "default"
    @State private var availableDevices: [(id: String, name: String)] = []
    @State private var audioService = AudioCaptureService()

    var body: some View {
        Form {
            Section("Input Device") {
                Picker("Microphone", selection: $selectedDeviceID) {
                    Text("System Default").tag("default")
                    ForEach(availableDevices, id: \.id) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .onChange(of: selectedDeviceID) { _, newValue in
                    let deviceID = newValue == "default" ? nil : newValue
                    settings?.audioInputDeviceID = deviceID
                    saveSettings()
                    Logger.ui.info("Audio device changed to: \(newValue)")
                }
                .help("Audio input device for recording")

                Button("Refresh Devices") {
                    loadDevices()
                }
                .font(.caption)
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

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.secondary.opacity(0.2))

                            RoundedRectangle(cornerRadius: 4)
                                .fill(levelColor)
                                .frame(width: max(0, geometry.size.width * CGFloat(audioService.currentLevel)))
                                .animation(.linear(duration: 0.05), value: audioService.currentLevel)
                        }
                    }
                    .frame(height: 24)

                    HStack {
                        Button(audioService.isCapturing ? "Stop Preview" : "Start Preview") {
                            toggleAudioPreview()
                        }
                        .font(.caption)

                        Spacer()

                        Text(audioService.isCapturing ? "Listening..." : "Stopped")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
            loadDevices()
        }
        .onDisappear {
            stopAudioPreview()
        }
    }

    // MARK: - Audio Level

    private var levelColor: Color {
        let level = audioService.currentLevel
        if level > 0.8 { return .red }
        if level > 0.5 { return .yellow }
        return .green
    }

    private func toggleAudioPreview() {
        if audioService.isCapturing {
            stopAudioPreview()
        } else {
            startAudioPreview()
        }
    }

    private func startAudioPreview() {
        Task {
            do {
                try await audioService.startCapture()
                Logger.ui.info("Audio preview started")
            } catch {
                Logger.ui.error("Failed to start audio preview: \(error.localizedDescription)")
            }
        }
    }

    private func stopAudioPreview() {
        Task {
            _ = await audioService.stopCapture()
            Logger.ui.info("Audio preview stopped")
        }
    }

    // MARK: - Data

    private func loadDevices() {
        availableDevices = audioService.enumerateInputDevices()
    }

    private func loadSettings() {
        do {
            settings = try UserSettings.shared(in: modelContext)
            selectedDeviceID = settings?.audioInputDeviceID ?? "default"
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
