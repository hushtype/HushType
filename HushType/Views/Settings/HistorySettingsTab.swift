import SwiftUI
import SwiftData
import os

struct HistorySettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @State private var settings: UserSettings?
    @State private var maxEntries: Int = 5000
    @State private var retentionDays: Int = 90
    @State private var storeText: Bool = true
    @State private var showClearConfirmation: Bool = false
    @State private var showResetConfirmation: Bool = false
    @State private var entryCount: Int = 0

    var body: some View {
        Form {
            Section("Retention Policies") {
                HStack {
                    Text("Max entries")
                    Spacer()
                    TextField("", value: $maxEntries, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: maxEntries) { _, newValue in
                            settings?.maxHistoryEntries = newValue
                            saveSettings()
                        }
                        .accessibilityLabel("Maximum history entries: \(maxEntries)")
                        .accessibilityHint("Set to 0 for unlimited. Oldest entries beyond this limit are automatically removed.")
                }

                HStack {
                    Text("Retention (days)")
                    Spacer()
                    TextField("", value: $retentionDays, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: retentionDays) { _, newValue in
                            settings?.historyRetentionDays = newValue
                            saveSettings()
                        }
                        .accessibilityLabel("Retention days: \(retentionDays)")
                        .accessibilityHint("Entries older than this many days are automatically deleted. Set to 0 for unlimited.")
                }

                Text("Set to 0 for unlimited. Favorites are never auto-deleted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy") {
                Toggle("Store transcription text", isOn: $storeText)
                    .onChange(of: storeText) { _, newValue in
                        settings?.storeTranscriptionText = newValue
                        saveSettings()
                    }
                    .accessibilityHint("When off, only metadata such as duration, word count, and timestamp is saved — no transcription text")

                Text("When off, only metadata (duration, word count, timestamp) is stored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Storage") {
                LabeledContent("Total entries", value: "\(entryCount)")
                    .accessibilityLabel("Total history entries: \(entryCount)")

                Button("Clear All History") {
                    showClearConfirmation = true
                }
                .foregroundStyle(.red)
                .accessibilityLabel("Clear all history")
                .accessibilityHint("Permanently deletes all dictation history entries, including favorites")

                Button("Factory Reset") {
                    showResetConfirmation = true
                }
                .foregroundStyle(.red)
                .accessibilityLabel("Factory reset")
                .accessibilityHint("Deletes all data including history, app profiles, vocabulary, and resets all settings to defaults")
            }
        }
        .formStyle(.grouped)
        .onAppear { loadSettings(); countEntries() }
        .alert("Clear All History?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                let cleanup = HistoryCleanupService(modelContainer: modelContext.container)
                cleanup.clearAllHistory()
                countEntries()
            }
        } message: {
            Text("This will delete all dictation entries, including favorites. This cannot be undone.")
        }
        .alert("Factory Reset?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset Everything", role: .destructive) {
                let cleanup = HistoryCleanupService(modelContainer: modelContext.container)
                cleanup.factoryReset()
                loadSettings()
                countEntries()
            }
        } message: {
            Text("This will delete ALL data: history, profiles, vocabulary, and reset settings to defaults.")
        }
    }

    private func loadSettings() {
        if let s = try? UserSettings.shared(in: modelContext) {
            settings = s
            maxEntries = s.maxHistoryEntries
            retentionDays = s.historyRetentionDays
            storeText = s.storeTranscriptionText
        }
    }

    private func countEntries() {
        let descriptor = FetchDescriptor<DictationEntry>()
        entryCount = (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    private func saveSettings() {
        try? modelContext.save()
        NotificationCenter.default.post(name: .userSettingsChanged, object: nil)
    }
}

#Preview {
    HistorySettingsTab()
        .modelContainer(for: [UserSettings.self, DictationEntry.self], inMemory: true)
}
