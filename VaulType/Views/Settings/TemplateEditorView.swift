import SwiftUI
import SwiftData
import os

struct TemplateEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PromptTemplate.name) private var templates: [PromptTemplate]

    @State private var selectedTemplate: PromptTemplate?
    @State private var showNewTemplateSheet = false

    var body: some View {
        NavigationSplitView {
            // Template list sidebar
            TemplateListView(
                templates: templates,
                selectedTemplate: $selectedTemplate,
                onNew: { showNewTemplateSheet = true }
            )
        } detail: {
            // Template editor detail
            if let template = selectedTemplate {
                TemplateDetailView(template: template)
            } else {
                ContentUnavailableView(
                    "No Template Selected",
                    systemImage: "text.bubble",
                    description: Text("Select a template to edit or create a new one")
                )
            }
        }
        .sheet(isPresented: $showNewTemplateSheet) {
            NewTemplateSheet(onSave: { name, mode in
                createNewTemplate(name: name, mode: mode)
                showNewTemplateSheet = false
            })
        }
        .onAppear {
            // Select first template if none selected
            if selectedTemplate == nil, let first = templates.first {
                selectedTemplate = first
            }
        }
    }

    private func createNewTemplate(name: String, mode: ProcessingMode) {
        let template = PromptTemplate.createUserTemplate(
            name: name,
            mode: mode,
            systemPrompt: "You are a helpful assistant.",
            userPromptTemplate: "{{transcription}}",
            in: modelContext
        )

        do {
            try modelContext.save()
            selectedTemplate = template
            Logger.ui.info("Created new template: \(name)")
        } catch {
            Logger.ui.error("Failed to create template: \(error.localizedDescription)")
        }
    }
}

// MARK: - Template List

private struct TemplateListView: View {
    let templates: [PromptTemplate]
    @Binding var selectedTemplate: PromptTemplate?
    let onNew: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var showDeleteConfirmation = false
    @State private var templateToDelete: PromptTemplate?

    private var groupedTemplates: [(ProcessingMode, [PromptTemplate])] {
        let grouped = Dictionary(grouping: templates, by: { $0.mode })
        return ProcessingMode.allCases.compactMap { mode in
            guard let templates = grouped[mode], !templates.isEmpty else { return nil }
            return (mode, templates)
        }
    }

    var body: some View {
        List(selection: $selectedTemplate) {
            ForEach(groupedTemplates, id: \.0) { mode, templates in
                Section {
                    ForEach(templates) { template in
                        TemplateListRow(template: template)
                            .tag(template)
                            .contextMenu {
                                Button {
                                    duplicateTemplate(template)
                                } label: {
                                    Label("Duplicate", systemImage: "doc.on.doc")
                                }

                                if template.isDeletable {
                                    Divider()
                                    Button(role: .destructive) {
                                        templateToDelete = template
                                        showDeleteConfirmation = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                    }
                } header: {
                    HStack {
                        Image(systemName: mode.iconName)
                        Text(mode.displayName)
                    }
                }
            }
        }
        .navigationTitle("Templates")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    onNew()
                } label: {
                    Label("New Template", systemImage: "plus")
                }
            }
        }
        .alert("Delete Template", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let template = templateToDelete {
                    deleteTemplate(template)
                }
            }
        } message: {
            if let template = templateToDelete {
                Text("Delete '\(template.name)'? This action cannot be undone.")
            }
        }
    }

    private func duplicateTemplate(_ template: PromptTemplate) {
        let duplicate = template.duplicate(in: modelContext)
        do {
            try modelContext.save()
            selectedTemplate = duplicate
            Logger.ui.info("Duplicated template: \(template.name)")
        } catch {
            Logger.ui.error("Failed to duplicate template: \(error.localizedDescription)")
        }
    }

    private func deleteTemplate(_ template: PromptTemplate) {
        let success = template.deleteIfAllowed(from: modelContext)
        if success {
            do {
                try modelContext.save()
                if selectedTemplate?.id == template.id {
                    selectedTemplate = templates.first { $0.id != template.id }
                }
                Logger.ui.info("Deleted template: \(template.name)")
            } catch {
                Logger.ui.error("Failed to delete template: \(error.localizedDescription)")
            }
        } else {
            Logger.ui.warning("Attempted to delete built-in template: \(template.name)")
        }
    }
}

private struct TemplateListRow: View {
    let template: PromptTemplate

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(template.name)
                        .font(.headline)

                    if template.isBuiltIn {
                        Text("Built-in")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.blue.opacity(0.2))
                            .foregroundStyle(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }

                    if template.isDefault {
                        Text("Default")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.green.opacity(0.2))
                            .foregroundStyle(.green)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }

                if !template.variables.isEmpty {
                    Text("Variables: \(template.variables.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Template Detail Editor

private struct TemplateDetailView: View {
    let template: PromptTemplate

    @Environment(\.modelContext) private var modelContext
    @State private var validationResult: PromptTemplate.ValidationResult?

    var body: some View {
        Form {
            Section("Template Information") {
                TextField("Name", text: Binding(
                    get: { template.name },
                    set: { template.name = $0; saveChanges() }
                ))

                Picker("Processing Mode", selection: Binding(
                    get: { template.mode },
                    set: { template.mode = $0; saveChanges() }
                )) {
                    ForEach(ProcessingMode.allCases) { mode in
                        HStack {
                            Image(systemName: mode.iconName)
                            Text(mode.displayName)
                        }
                        .tag(mode)
                    }
                }
                .disabled(template.isBuiltIn)

                if template.isBuiltIn {
                    Text("Built-in templates cannot be edited. Duplicate this template to create a customizable version.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("System Prompt")
                        .font(.headline)

                    TextEditor(text: Binding(
                        get: { template.systemPrompt },
                        set: { template.systemPrompt = $0; saveChanges() }
                    ))
                    .font(.body)
                    .frame(minHeight: 100)
                    .disabled(template.isBuiltIn)

                    Text("Defines the LLM's role and behavior. This sets the context for how the model should process the transcription.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Prompts")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("User Prompt Template")
                        .font(.headline)

                    TextEditor(text: Binding(
                        get: { template.userPromptTemplate },
                        set: { template.userPromptTemplate = $0; saveChanges() }
                    ))
                    .font(.body.monospaced())
                    .frame(minHeight: 150)
                    .disabled(template.isBuiltIn)

                    Text("Use {{variable_name}} for placeholders. The {{transcription}} variable contains the raw whisper output.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Variables") {
                VariablesList(template: template, onSave: saveChanges)
            }

            Section("Built-in Variables") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("These variables are automatically available:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
                        BuiltInVariableRow(name: "transcription", description: "Raw whisper output")
                        BuiltInVariableRow(name: "language", description: "Detected language code")
                        BuiltInVariableRow(name: "app_name", description: "Active application name")
                        BuiltInVariableRow(name: "app_bundle_id", description: "Active app bundle ID")
                        BuiltInVariableRow(name: "timestamp", description: "Unix timestamp")
                        BuiltInVariableRow(name: "date", description: "Current date (YYYY-MM-DD)")
                        BuiltInVariableRow(name: "time", description: "Current time (HH:MM:SS)")
                    }
                    .font(.caption)
                }
            }

            if let result = validationResult, !result.warnings.isEmpty {
                Section("Validation Warnings") {
                    ForEach(result.warnings, id: \.self) { warning in
                        Label {
                            Text(warning)
                                .font(.callout)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(template.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    validateTemplate()
                } label: {
                    Label("Validate", systemImage: "checkmark.circle")
                }
            }
        }
        .onAppear {
            validateTemplate()
        }
    }

    private func saveChanges() {
        template.updatedAt = .now
        do {
            try modelContext.save()
            validateTemplate()
            Logger.ui.debug("Saved template changes: \(template.name)")
        } catch {
            Logger.ui.error("Failed to save template: \(error.localizedDescription)")
        }
    }

    private func validateTemplate() {
        validationResult = template.validate()
        if validationResult?.isValid == true {
            Logger.ui.debug("Template validation passed: \(template.name)")
        } else {
            Logger.ui.warning("Template validation warnings: \(template.name)")
        }
    }
}

private struct BuiltInVariableRow: View {
    let name: String
    let description: String

    var body: some View {
        GridRow {
            Text("{{\(name)}}")
                .font(.caption.monospaced())
                .foregroundStyle(.blue)
            Text(description)
                .foregroundStyle(.secondary)
        }
    }
}

private struct VariablesList: View {
    let template: PromptTemplate
    let onSave: () -> Void

    @State private var newVariableName = ""
    @State private var showAddVariable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if template.variables.isEmpty {
                Text("No custom variables defined")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(template.variables, id: \.self) { variable in
                    HStack {
                        Text("{{\(variable)}}")
                            .font(.body.monospaced())
                            .foregroundStyle(.blue)

                        Spacer()

                        if !template.isBuiltIn {
                            Button {
                                removeVariable(variable)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if !template.isBuiltIn {
                if showAddVariable {
                    HStack {
                        TextField("Variable name", text: $newVariableName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                addVariable()
                            }

                        Button {
                            addVariable()
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)
                        .disabled(newVariableName.isEmpty)

                        Button {
                            showAddVariable = false
                            newVariableName = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Button {
                        showAddVariable = true
                    } label: {
                        Label("Add Variable", systemImage: "plus.circle")
                    }
                }
            }
        }
    }

    private func addVariable() {
        let trimmed = newVariableName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !template.variables.contains(trimmed) else { return }

        template.variables.append(trimmed)
        newVariableName = ""
        showAddVariable = false
        onSave()
        Logger.ui.info("Added variable '\(trimmed)' to template: \(template.name)")
    }

    private func removeVariable(_ variable: String) {
        template.variables.removeAll { $0 == variable }
        onSave()
        Logger.ui.info("Removed variable '\(variable)' from template: \(template.name)")
    }
}

// MARK: - New Template Sheet

private struct NewTemplateSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (String, ProcessingMode) -> Void

    @State private var templateName = ""
    @State private var selectedMode: ProcessingMode = .clean

    var body: some View {
        VStack(spacing: 20) {
            Text("New Template")
                .font(.title2)
                .fontWeight(.semibold)

            Form {
                TextField("Template Name", text: $templateName)
                    .textFieldStyle(.roundedBorder)

                Picker("Processing Mode", selection: $selectedMode) {
                    ForEach(ProcessingMode.allCases) { mode in
                        HStack {
                            Image(systemName: mode.iconName)
                            Text(mode.displayName)
                        }
                        .tag(mode)
                    }
                }

                Text(selectedMode.description)
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
                    onSave(templateName, selectedMode)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(templateName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 300)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var container: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: PromptTemplate.self, configurations: config)
        let context = ModelContext(container)
        for template in PromptTemplate.builtInTemplates {
            context.insert(template)
        }
        return container
    }()

    TemplateEditorView()
        .modelContainer(container)
        .frame(width: 800, height: 600)
}
