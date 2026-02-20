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
    @State private var globalAliases: [String: String] = [:]
    @State private var showAddAliasSheet = false

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

            // MARK: - Global Shortcut Aliases section
            Section {
                let sortedAliases = globalAliases.sorted(by: { $0.key < $1.key })
                if sortedAliases.isEmpty {
                    Text("No global aliases yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 4)
                } else {
                    ForEach(sortedAliases, id: \.key) { phrase, shortcut in
                        HStack {
                            Text(phrase)
                                .fontWeight(.medium)
                            Spacer()
                            Text(shortcut)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Button(role: .destructive) {
                                globalAliases.removeValue(forKey: phrase)
                                saveAliases()
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Delete alias \(phrase)")
                        }
                        .padding(.vertical, 2)
                    }
                }

                Button {
                    showAddAliasSheet = true
                } label: {
                    Label("Add Alias", systemImage: "plus.circle")
                }
                .disabled(!commandsEnabled)
                .accessibilityLabel("Add global shortcut alias")
                .accessibilityHint("Define a spoken phrase that maps to a keyboard shortcut, available in all apps")
            } header: {
                Text("Global Shortcut Aliases")
            } footer: {
                Text("Say a phrase to trigger the mapped shortcut. Global aliases work in all apps. App-specific aliases override global ones.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .sheet(isPresented: $showAddAliasSheet) {
            AddAliasSheetView(existingAliases: globalAliases) { phrase, shortcut in
                globalAliases[phrase] = shortcut
                saveAliases()
            }
        }
    }

    // MARK: - Private helpers

    private func loadSettings() {
        do {
            settings = try UserSettings.shared(in: modelContext)
            commandsEnabled = settings?.commandsEnabled ?? true
            commandWakePhrase = settings?.commandWakePhrase ?? "Hey Type"
            globalAliases = settings?.globalShortcutAliases ?? [:]
            Logger.ui.debug("Loaded user settings in Commands tab")
        } catch {
            Logger.ui.error("Failed to load UserSettings in Commands tab: \(error.localizedDescription)")
        }
    }

    private func saveAliases() {
        settings?.globalShortcutAliases = globalAliases
        saveSettings()
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

// MARK: - AddAliasSheetView

private struct AddAliasSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let existingAliases: [String: String]
    let onSave: (String, String) -> Void

    @State private var phrase = ""
    @State private var shortcut = ""
    @State private var showDuplicateWarning = false
    @State private var showInvalidShortcutWarning = false

    private var isDuplicatePhrase: Bool {
        existingAliases.keys.contains(phrase.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var isShortcutValid: Bool {
        let trimmed = shortcut.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && HotkeyBinding.parse(trimmed) != nil
    }

    private var canSave: Bool {
        !phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && isShortcutValid
            && !isDuplicatePhrase
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Global Shortcut Alias")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Form
            Form {
                Section {
                    LabeledContent("Spoken Phrase") {
                        TextField("e.g. undo", text: $phrase)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 260)
                            .onChange(of: phrase) { _, _ in
                                showDuplicateWarning = false
                            }
                            .accessibilityLabel("Spoken phrase")
                            .accessibilityHint("The phrase you will say after the wake phrase to trigger the shortcut")
                    }

                    LabeledContent("Shortcut") {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("e.g. cmd+z", text: $shortcut)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 260)
                                .onChange(of: shortcut) { _, _ in
                                    showInvalidShortcutWarning = false
                                }
                                .accessibilityLabel("Keyboard shortcut")
                                .accessibilityHint("Enter a shortcut like cmd+c, cmd+shift+z, or ctrl+option+t")

                            Text("Format: modifiers+key — e.g. cmd+c, cmd+shift+z, ctrl+option+t")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if isDuplicatePhrase {
                            Label("A global alias with this phrase already exists.", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        if showInvalidShortcutWarning {
                            Label("Shortcut format is invalid. Use modifier+key (e.g. cmd+z).", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer buttons
            HStack {
                Spacer()
                Button("Save") {
                    let normalizedPhrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let normalizedShortcut = shortcut.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    guard !normalizedPhrase.isEmpty else { return }
                    guard isShortcutValid else {
                        showInvalidShortcutWarning = true
                        return
                    }
                    onSave(normalizedPhrase, normalizedShortcut)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
                .accessibilityLabel("Save alias")
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 420, minHeight: 280)
    }
}

// MARK: - Preview

#Preview {
    CommandSettingsTab()
        .environment(AppState())
        .modelContainer(for: [UserSettings.self, CustomCommand.self], inMemory: true)
        .frame(width: 500, height: 600)
}
