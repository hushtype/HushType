import SwiftUI
import SwiftData
import os

struct AudioSettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @State private var settings: UserSettings?
    @State private var selectedDeviceID: String = "default"
    @State private var availableDevices: [(id: String, name: String)] = []
    @State private var audioService = AudioCaptureService()
    @State private var previewSoundService = SoundFeedbackService()

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
                    HStack {
                        Text("Live Audio Input")
                            .font(.headline)
                        Spacer()
                        Text(audioService.isCapturing ? "Listening..." : "Stopped")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    GeometryReader { geometry in
                        let vadThreshold = CGFloat(settings?.vadSensitivity ?? 0.5)
                        let thresholdX = geometry.size.width * vadThreshold

                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.secondary.opacity(0.2))

                            // Level bar
                            RoundedRectangle(cornerRadius: 4)
                                .fill(levelColor(threshold: vadThreshold))
                                .frame(width: max(0, geometry.size.width * CGFloat(audioService.currentLevel)))
                                .animation(.linear(duration: 0.05), value: audioService.currentLevel)

                            // VAD threshold line
                            Rectangle()
                                .fill(.orange)
                                .frame(width: 2)
                                .offset(x: thresholdX - 1)

                            // Threshold label
                            Text("VAD")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.orange)
                                .offset(x: thresholdX + 4, y: -1)
                        }
                    }
                    .frame(height: 24)

                    HStack {
                        Button(audioService.isCapturing ? "Stop Preview" : "Start Preview") {
                            toggleAudioPreview()
                        }
                        .font(.caption)

                        Spacer()

                        Text("Audio above the orange line is detected as speech")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Sound Feedback") {
                Toggle("Enable Sound Effects", isOn: Binding(
                    get: { settings?.playSoundEffects ?? true },
                    set: { newValue in
                        settings?.playSoundEffects = newValue
                        saveSettings()
                    }
                ))
                .help("Play audio feedback when recording starts, stops, and commands execute")

                Picker("Sound Theme", selection: Binding(
                    get: {
                        SoundFeedbackService.SoundTheme(rawValue: settings?.soundTheme ?? "subtle") ?? .subtle
                    },
                    set: { newValue in
                        settings?.soundTheme = newValue.rawValue
                        saveSettings()
                    }
                )) {
                    ForEach(SoundFeedbackService.SoundTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .disabled(!(settings?.playSoundEffects ?? true))
                .help("Choose the style of sound effects")

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Volume")
                        Spacer()
                        Text(String(format: "%.0f%%", (settings?.soundVolume ?? 0.5) * 100))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Slider(
                        value: Binding(
                            get: { settings?.soundVolume ?? 0.5 },
                            set: { newValue in
                                settings?.soundVolume = newValue
                                saveSettings()
                            }
                        ),
                        in: 0.0...1.0,
                        step: 0.05
                    )
                    .disabled(!(settings?.playSoundEffects ?? true))
                }

                Button("Preview Sound") {
                    let theme = SoundFeedbackService.SoundTheme(
                        rawValue: settings?.soundTheme ?? "subtle"
                    ) ?? .subtle
                    previewSoundService.isEnabled = true
                    previewSoundService.theme = theme
                    previewSoundService.volume = Float(settings?.soundVolume ?? 0.5)
                    previewSoundService.play(.recordingStart)
                }
                .disabled(!(settings?.playSoundEffects ?? true))
                .help("Play a preview of the current sound theme")
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

                Picker("Inference Threads", selection: Binding(
                    get: { settings?.whisperThreadCount ?? 0 },
                    set: { newValue in
                        settings?.whisperThreadCount = newValue
                        saveSettings()
                    }
                )) {
                    Text("Auto (Recommended)").tag(0)
                    Text("2").tag(2)
                    Text("4").tag(4)
                    Text("6").tag(6)
                    Text("8").tag(8)
                }
                .help("CPU threads for whisper inference. Auto uses all available cores for fastest transcription.")
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

    private func levelColor(threshold: CGFloat) -> Color {
        let level = CGFloat(audioService.currentLevel)
        if level > 0.9 { return .red } // clipping
        if level >= threshold { return .green } // above VAD = speech detected
        return .secondary.opacity(0.4) // below VAD = silence/noise
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
            NotificationCenter.default.post(name: .userSettingsChanged, object: nil)
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
