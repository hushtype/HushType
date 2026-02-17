import SwiftUI
import SwiftData
import os

struct LanguageSettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @State private var settings: UserSettings?
    @State private var autoDetect: Bool = false
    @State private var defaultLanguage: String = "en"

    // Common language codes
    private let languages = [
        ("en", "English"), ("tr", "Turkish"), ("de", "German"), ("fr", "French"),
        ("es", "Spanish"), ("it", "Italian"), ("pt", "Portuguese"), ("nl", "Dutch"),
        ("pl", "Polish"), ("ru", "Russian"), ("zh", "Chinese"), ("ja", "Japanese"),
        ("ko", "Korean"), ("ar", "Arabic"), ("hi", "Hindi"), ("auto", "Auto-detect")
    ]

    var body: some View {
        Form {
            Section("Language Detection") {
                Toggle("Auto-detect language", isOn: $autoDetect)
                    .onChange(of: autoDetect) { _, newValue in
                        settings?.autoDetectLanguage = newValue
                        saveSettings()
                    }

                Text("When enabled, whisper.cpp will analyze the first 30 seconds to detect the spoken language.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Default Language") {
                Picker("Language", selection: $defaultLanguage) {
                    ForEach(languages.filter { $0.0 != "auto" }, id: \.0) { code, name in
                        Text("\(name) (\(code))").tag(code)
                    }
                }
                .onChange(of: defaultLanguage) { _, newValue in
                    settings?.defaultLanguage = newValue
                    saveSettings()
                }
                .disabled(autoDetect)

                Text("Used when auto-detect is off. Per-app overrides take priority.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { loadSettings() }
    }

    private func loadSettings() {
        if let s = try? UserSettings.shared(in: modelContext) {
            settings = s
            autoDetect = s.autoDetectLanguage
            defaultLanguage = s.defaultLanguage
        }
    }

    private func saveSettings() {
        try? modelContext.save()
        NotificationCenter.default.post(name: .userSettingsChanged, object: nil)
    }
}

#Preview {
    LanguageSettingsTab()
        .modelContainer(for: UserSettings.self, inMemory: true)
}
