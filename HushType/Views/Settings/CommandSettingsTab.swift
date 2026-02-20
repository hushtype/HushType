import SwiftUI
import SwiftData
import os

struct CommandSettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query private var customCommands: [CustomCommand]
    @State private var settings: UserSettings?
    @State private var commandsEnabled = true
    @State private var commandWakePhrase = "Hey Type"
    @State private var showCustomCommandEditor = false
    @State private var wakePhraseDebounceTask: Task<Void, Never>?

    var body: some View {
        if let registry = appState.commandRegistry {
            commandsForm(registry: registry)
        } else {
            ContentUnavailableView(
                "Loading Commands",
                systemImage: "hourglass",
                description: Text("Voice command registry is initializing...")
            )
        }
    }

    @ViewBuilder
    private func commandsForm(registry: CommandRegistry) -> some View {
        Form {
            // MARK: - Voice Commands section
            Section("Voice Commands") {
                Toggle("Enable Voice Commands", isOn: $commandsEnabled)
                    .onChange(of: commandsEnabled) { _, newValue in
                        settings?.commandsEnabled = newValue
                        saveSettings()
                    }
                    .help("When enabled, HushType listens for the wake phrase and executes voice commands.")
                    .accessibilityHint("When on, say the wake phrase followed by a command to control your Mac by voice")

                LabeledContent("Wake Phrase") {
                    TextField("e.g. Hey Type", text: $commandWakePhrase)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                        .disabled(!commandsEnabled)
                        .onSubmit {
                            settings?.commandWakePhrase = commandWakePhrase
                            saveSettings()
                        }
                        .onChange(of: commandWakePhrase) { _, newValue in
                            wakePhraseDebounceTask?.cancel()
                            wakePhraseDebounceTask = Task {
                                try? await Task.sleep(for: .milliseconds(500))
                                guard !Task.isCancelled else { return }
                                settings?.commandWakePhrase = newValue
                                saveSettings()
                            }
                        }
                        .accessibilityLabel("Wake phrase: \(commandWakePhrase)")
                        .accessibilityHint("The phrase you say before a voice command, for example Hey Type open Safari")
                }

                Text("Say the wake phrase followed by a command. For example: \"\(commandWakePhrase), open Safari\" or \"\(commandWakePhrase), volume up\".")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: - Built-in Commands section (grouped by category)
            ForEach(CommandCategory.allCases) { category in
                Section {
                    ForEach(registry.entries(for: category)) { entry in
                        BuiltInCommandRow(entry: entry, isParentEnabled: commandsEnabled) { intent, enabled in
                            registry.setEnabled(intent, enabled: enabled)
                            persistRegistryState()
                        }
                    }
                } header: {
                    Label(category.rawValue, systemImage: category.iconName)
                }
            }

            // MARK: - Custom Commands section
            Section {
                if customCommands.isEmpty {
                    Text("No custom commands yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 4)
                } else {
                    ForEach(customCommands) { command in
                        CustomCommandRow(command: command)
                    }
                    .onDelete(perform: deleteCustomCommands)
                }

                Button {
                    showCustomCommandEditor = true
                } label: {
                    Label("Manage Custom Commands", systemImage: "square.and.pencil")
                }
                .disabled(!commandsEnabled)
                .accessibilityLabel("Manage custom commands")
                .accessibilityHint("Opens the editor to create or edit your own voice command triggers")
            } header: {
                Text("Custom Commands")
            } footer: {
                Text("Custom commands let you define your own trigger phrases and map them to one or more built-in actions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadSettings()
        }
        .sheet(isPresented: $showCustomCommandEditor) {
            CustomCommandEditorView()
                .frame(minWidth: 700, minHeight: 500)
        }
    }

    // MARK: - Private helpers

    private func loadSettings() {
        do {
            settings = try UserSettings.shared(in: modelContext)
            commandsEnabled = settings?.commandsEnabled ?? true
            commandWakePhrase = settings?.commandWakePhrase ?? "Hey Type"
            Logger.ui.debug("Loaded user settings in Commands tab")
        } catch {
            Logger.ui.error("Failed to load UserSettings in Commands tab: \(error.localizedDescription)")
        }
    }

    /// Persist the registry's disabled intents to UserSettings.
    private func persistRegistryState() {
        settings?.disabledCommandIntents = appState.commandRegistry?.disabledIntentRawValues() ?? []
        saveSettings()
    }

    private func saveSettings() {
        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .userSettingsChanged, object: nil)
            Logger.ui.debug("Saved user settings from Commands tab")
        } catch {
            Logger.ui.error("Failed to save UserSettings from Commands tab: \(error.localizedDescription)")
        }
    }

    private func deleteCustomCommands(at offsets: IndexSet) {
        for index in offsets {
            let command = customCommands[index]
            modelContext.delete(command)
            Logger.commands.info("Deleted custom command: \"\(command.name)\"")
        }
        saveSettings()
    }
}

// MARK: - BuiltInCommandRow

private struct BuiltInCommandRow: View {
    let entry: CommandRegistry.CommandEntry
    let isParentEnabled: Bool
    let onToggle: (CommandIntent, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(
                get: { entry.isEnabled },
                set: { newValue in onToggle(entry.intent, newValue) }
            )) {
                Label(entry.intent.displayName, systemImage: entry.intent.iconName)
            }
            .disabled(!isParentEnabled)
            .accessibilityHint(
                entry.examplePhrases.isEmpty
                    ? "Enables or disables the \(entry.intent.displayName) voice command"
                    : "Enables or disables the \(entry.intent.displayName) command. Example: \(entry.examplePhrases[0])"
            )

            if !entry.examplePhrases.isEmpty {
                Text(entry.examplePhrases.joined(separator: " • "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 28)
                    .accessibilityLabel("Example phrases: \(entry.examplePhrases.joined(separator: ", "))")
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - CustomCommandRow

private struct CustomCommandRow: View {
    let command: CustomCommand

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "star")
                    .foregroundStyle(command.isEnabled ? Color.accentColor : Color.secondary)
                Text(command.name)
                    .fontWeight(.medium)
                Spacer()
                if !command.isEnabled {
                    Text("Disabled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("\"\(command.triggerPhrase)\"")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 24)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

#Preview {
    CommandSettingsTab()
        .environment(AppState())
        .modelContainer(for: [UserSettings.self, CustomCommand.self], inMemory: true)
        .frame(width: 500, height: 600)
}
