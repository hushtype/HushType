import SwiftUI
import SwiftData
import os

struct CustomCommandEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CustomCommand.name) private var commands: [CustomCommand]

    @State private var selectedCommand: CustomCommand?
    @State private var showNewCommandSheet = false

    var body: some View {
        NavigationSplitView {
            CommandListView(
                commands: commands,
                selectedCommand: $selectedCommand,
                onNew: { showNewCommandSheet = true }
            )
        } detail: {
            if let command = selectedCommand {
                CommandDetailView(command: command)
            } else {
                ContentUnavailableView(
                    "No Command Selected",
                    systemImage: "mic.badge.plus",
                    description: Text("Select a command to edit or create a new one")
                )
            }
        }
        .sheet(isPresented: $showNewCommandSheet) {
            NewCommandSheet(onSave: { name, phrase in
                createNewCommand(name: name, triggerPhrase: phrase)
                showNewCommandSheet = false
            })
        }
        .onAppear {
            if selectedCommand == nil, let first = commands.first {
                selectedCommand = first
            }
        }
    }

    private func createNewCommand(name: String, triggerPhrase: String) {
        let command = CustomCommand(
            name: name,
            triggerPhrase: triggerPhrase,
            actions: [],
            isEnabled: true
        )
        modelContext.insert(command)

        do {
            try modelContext.save()
            selectedCommand = command
            Logger.ui.info("Created new custom command: \(name)")
        } catch {
            Logger.ui.error("Failed to create custom command: \(error.localizedDescription)")
        }
    }
}

// MARK: - Command List

private struct CommandListView: View {
    let commands: [CustomCommand]
    @Binding var selectedCommand: CustomCommand?
    let onNew: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var showDeleteConfirmation = false
    @State private var commandToDelete: CustomCommand?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedCommand) {
                ForEach(commands) { command in
                    CommandListRow(command: command)
                        .tag(command)
                        .contextMenu {
                            Button(role: .destructive) {
                                commandToDelete = command
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .navigationTitle("Voice Commands")

            Divider()

            Button {
                onNew()
            } label: {
                Label("New Command", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
        .alert("Delete Command", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let command = commandToDelete {
                    deleteCommand(command)
                }
            }
        } message: {
            if let command = commandToDelete {
                Text("Delete '\(command.name)'? This action cannot be undone.")
            }
        }
    }

    private func deleteCommand(_ command: CustomCommand) {
        modelContext.delete(command)
        do {
            try modelContext.save()
            if selectedCommand?.id == command.id {
                selectedCommand = commands.first { $0.id != command.id }
            }
            Logger.ui.info("Deleted custom command: \(command.name)")
        } catch {
            Logger.ui.error("Failed to delete custom command: \(error.localizedDescription)")
        }
    }
}

private struct CommandListRow: View {
    let command: CustomCommand

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(command.name)
                        .font(.headline)

                    if !command.isEnabled {
                        Text("Disabled")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.orange.opacity(0.2))
                            .foregroundStyle(.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }

                Text("\"\(command.triggerPhrase)\"")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            }

            Spacer()

            Text("\(command.actions.count) action\(command.actions.count == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Command Detail Editor

private struct CommandDetailView: View {
    let command: CustomCommand

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Form {
            Section("Command Information") {
                TextField("Name", text: Binding(
                    get: { command.name },
                    set: { command.name = $0; saveChanges() }
                ))

                TextField("Trigger Phrase", text: Binding(
                    get: { command.triggerPhrase },
                    set: { command.triggerPhrase = $0; saveChanges() }
                ))

                Text("Speak this phrase after the wake word to trigger the command.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Enabled", isOn: Binding(
                    get: { command.isEnabled },
                    set: { command.isEnabled = $0; saveChanges() }
                ))
            }

            Section {
                ActionSequenceBuilder(command: command, onSave: saveChanges)
            } header: {
                Text("Action Sequence")
            } footer: {
                Text("Actions execute in order. If any action fails, the chain stops.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(command.name)
    }

    private func saveChanges() {
        command.updatedAt = .now
        do {
            try modelContext.save()
            Logger.ui.debug("Saved custom command changes: \(command.name)")
        } catch {
            Logger.ui.error("Failed to save custom command: \(error.localizedDescription)")
        }
    }
}

// MARK: - Action Sequence Builder

private struct ActionSequenceBuilder: View {
    let command: CustomCommand
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if command.actions.isEmpty {
                Text("No actions defined. Add a step below.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(command.actions.enumerated()), id: \.element.id) { index, step in
                    ActionStepRow(
                        step: step,
                        index: index,
                        onUpdate: { updated in
                            updateStep(at: index, with: updated)
                        },
                        onRemove: {
                            removeStep(at: index)
                        }
                    )

                    if index < command.actions.count - 1 {
                        HStack {
                            Spacer()
                            Image(systemName: "arrow.down")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Spacer()
                        }
                    }
                }
            }

            Button {
                addStep()
            } label: {
                Label("Add Step", systemImage: "plus.circle")
            }
            .padding(.top, 4)
        }
    }

    private func addStep() {
        let newStep = CommandActionStep(intent: .volumeUp, parameters: [:])
        command.actions.append(newStep)
        onSave()
        Logger.ui.info("Added action step to command: \(command.name)")
    }

    private func updateStep(at index: Int, with updated: CommandActionStep) {
        guard index < command.actions.count else { return }
        command.actions[index] = updated
        onSave()
    }

    private func removeStep(at index: Int) {
        guard index < command.actions.count else { return }
        command.actions.remove(at: index)
        onSave()
        Logger.ui.info("Removed action step from command: \(command.name)")
    }
}

// MARK: - Action Step Row

private struct ActionStepRow: View {
    let step: CommandActionStep
    let index: Int
    let onUpdate: (CommandActionStep) -> Void
    let onRemove: () -> Void

    @State private var selectedIntent: CommandIntent
    @State private var appNameParam: String
    @State private var levelParam: String
    @State private var shortcutNameParam: String

    init(step: CommandActionStep, index: Int, onUpdate: @escaping (CommandActionStep) -> Void, onRemove: @escaping () -> Void) {
        self.step = step
        self.index = index
        self.onUpdate = onUpdate
        self.onRemove = onRemove
        self._selectedIntent = State(initialValue: step.intent)
        self._appNameParam = State(initialValue: step.parameters["appName"] ?? "")
        self._levelParam = State(initialValue: step.parameters["level"] ?? "")
        self._shortcutNameParam = State(initialValue: step.parameters["shortcutName"] ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Step \(index + 1)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }

            Picker("Action", selection: $selectedIntent) {
                ForEach(CommandCategory.allCases) { category in
                    Section(category.rawValue) {
                        ForEach(CommandIntent.allCases.filter { $0.category == category }) { intent in
                            HStack {
                                Image(systemName: intent.iconName)
                                Text(intent.displayName)
                            }
                            .tag(intent)
                        }
                    }
                }
            }
            .onChange(of: selectedIntent) { _, _ in
                commitUpdate()
            }

            parameterFields
        }
        .padding(8)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var parameterFields: some View {
        switch selectedIntent {
        case .openApp, .switchToApp, .closeApp, .quitApp, .hideApp:
            TextField("App Name", text: $appNameParam)
                .textFieldStyle(.roundedBorder)
                .onChange(of: appNameParam) { _, _ in commitUpdate() }

        case .volumeSet:
            HStack {
                TextField("Level (0-100)", text: $levelParam)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: levelParam) { _, _ in commitUpdate() }
                Text("%")
                    .foregroundStyle(.secondary)
            }

        case .runShortcut:
            TextField("Shortcut Name", text: $shortcutNameParam)
                .textFieldStyle(.roundedBorder)
                .onChange(of: shortcutNameParam) { _, _ in commitUpdate() }

        default:
            EmptyView()
        }
    }

    private func commitUpdate() {
        var params: [String: String] = [:]

        switch selectedIntent {
        case .openApp, .switchToApp, .closeApp, .quitApp, .hideApp:
            if !appNameParam.isEmpty { params["appName"] = appNameParam }
        case .volumeSet:
            if !levelParam.isEmpty { params["level"] = levelParam }
        case .runShortcut:
            if !shortcutNameParam.isEmpty { params["shortcutName"] = shortcutNameParam }
        default:
            break
        }

        let updated = CommandActionStep(intent: selectedIntent, parameters: params)
        onUpdate(updated)
    }
}

// MARK: - New Command Sheet

private struct NewCommandSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (String, String) -> Void

    @State private var commandName = ""
    @State private var triggerPhrase = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("New Voice Command")
                .font(.title2)
                .fontWeight(.semibold)

            Form {
                TextField("Command Name", text: $commandName)
                    .textFieldStyle(.roundedBorder)

                TextField("Trigger Phrase", text: $triggerPhrase)
                    .textFieldStyle(.roundedBorder)

                Text("The exact phrase you will say after the wake word (e.g., \"morning setup\").")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create") {
                    onSave(commandName, triggerPhrase)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    commandName.trimmingCharacters(in: .whitespaces).isEmpty ||
                    triggerPhrase.trimmingCharacters(in: .whitespaces).isEmpty
                )
            }
        }
        .padding()
        .frame(width: 420, height: 320)
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: CustomCommand.self, configurations: config)
    let context = ModelContext(container)

    let sample = CustomCommand(
        name: "Morning Setup",
        triggerPhrase: "morning setup",
        actions: [
            CommandActionStep(intent: .volumeSet, parameters: ["level": "50"]),
            CommandActionStep(intent: .darkModeToggle, parameters: [:])
        ],
        isEnabled: true
    )
    context.insert(sample)
    try? context.save()

    return CustomCommandEditorView()
        .modelContainer(container)
        .frame(width: 800, height: 600)
}
