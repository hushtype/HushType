import SwiftUI
import SwiftData
import os

struct ProcessingSettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allTemplates: [PromptTemplate]
    @State private var settings: UserSettings?
    private var templatesForMode: [PromptTemplate] {
        let mode = settings?.defaultMode ?? .clean
        return allTemplates.filter { $0.mode == mode }
    }

    var body: some View {
        Form {
            Section("Default Processing Mode") {
                Picker("Processing Mode", selection: Binding(
                    get: { settings?.defaultMode ?? .clean },
                    set: { newValue in
                        settings?.defaultMode = newValue
                        saveSettings()
                    }
                )) {
                    ForEach(ProcessingMode.allCases) { mode in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Image(systemName: mode.iconName)
                                Text(mode.displayName)
                            }
                            Text(mode.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(mode)
                    }
                }
                .help("Default processing mode applied when no app-specific override exists")

                if let mode = settings?.defaultMode, mode.requiresLLM {
                    Text("This mode requires an LLM to be configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Active LLM Model") {
                LabeledContent("Selected Model") {
                    if let modelName = settings?.selectedLLMModel {
                        Text(modelName)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("None")
                            .foregroundStyle(.tertiary)
                    }
                }

                Text("LLM models are managed in the Models tab")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Templates") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Available templates for \((settings?.defaultMode ?? .clean).displayName) mode:")
                        .font(.callout)

                    if templatesForMode.isEmpty {
                        Text("No templates found for this mode")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        List {
                            ForEach(templatesForMode) { template in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(template.name)
                                            .font(.headline)

                                        if !template.variables.isEmpty {
                                            Text("Variables: \(template.variables.joined(separator: ", "))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer()

                                    if template.isDefault {
                                        Text("Default")
                                            .font(.caption)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(.blue.opacity(0.2))
                                            .foregroundStyle(.blue)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }

                                    if template.isBuiltIn {
                                        Image(systemName: "lock.fill")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .help("Built-in template (cannot be deleted)")
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .frame(height: 150)
                    }

                }
            }

            Section("Advanced") {
                LabeledContent("LLM Context Length") {
                    TextField("Tokens", value: Binding(
                        get: { settings?.llmContextLength ?? 2048 },
                        set: { newValue in
                            settings?.llmContextLength = newValue
                            saveSettings()
                        }
                    ), format: .number)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    .help("Maximum context length in tokens for LLM processing (default: 2048)")
                }

                Text("Larger context lengths allow processing longer text but use more memory")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            Logger.ui.debug("Loaded user settings in Processing tab")
        } catch {
            Logger.ui.error("Failed to load UserSettings: \(error.localizedDescription)")
        }
    }

    private func saveSettings() {
        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .userSettingsChanged, object: nil)
            Logger.ui.debug("Saved user settings from Processing tab")
        } catch {
            Logger.ui.error("Failed to save UserSettings: \(error.localizedDescription)")
        }
    }
}

#Preview {
    ProcessingSettingsTab()
        .modelContainer(for: [UserSettings.self, PromptTemplate.self], inMemory: true)
        .frame(width: 500, height: 600)
}
