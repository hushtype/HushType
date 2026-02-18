import SwiftUI
import SwiftData
import os

struct VocabularyEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VocabularyEntry.spokenForm) private var entries: [VocabularyEntry]

    @State private var selectedEntry: VocabularyEntry?
    @State private var showNewEntrySheet = false
    @State private var scopeFilter: ScopeFilter = .all

    enum ScopeFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case global = "Global"
        case perApp = "Per-App"

        var id: String { rawValue }
    }

    private var filteredEntries: [VocabularyEntry] {
        switch scopeFilter {
        case .all:
            return entries
        case .global:
            return entries.filter { $0.isGlobal }
        case .perApp:
            return entries.filter { !$0.isGlobal }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VocabularyListView(
                entries: filteredEntries,
                selectedEntry: $selectedEntry,
                scopeFilter: $scopeFilter,
                onNew: { showNewEntrySheet = true }
            )
            .frame(maxWidth: .infinity)

            Divider()

            Group {
                if let entry = selectedEntry {
                    VocabularyDetailView(entry: entry)
                } else {
                    ContentUnavailableView(
                        "No Entry Selected",
                        systemImage: "character.book.closed",
                        description: Text("Select a vocabulary entry to edit or create a new one")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showNewEntrySheet) {
            NewVocabularyEntrySheet { spokenForm, replacement, language, isGlobal, caseSensitive in
                createEntry(
                    spokenForm: spokenForm,
                    replacement: replacement,
                    language: language,
                    isGlobal: isGlobal,
                    caseSensitive: caseSensitive
                )
                showNewEntrySheet = false
            }
        }
        .onAppear {
            if selectedEntry == nil, let first = filteredEntries.first {
                selectedEntry = first
            }
        }
    }

    private func createEntry(
        spokenForm: String,
        replacement: String,
        language: String?,
        isGlobal: Bool,
        caseSensitive: Bool
    ) {
        let entry = VocabularyEntry(
            spokenForm: spokenForm,
            replacement: replacement,
            language: language?.isEmpty == false ? language : nil,
            isGlobal: isGlobal,
            caseSensitive: caseSensitive
        )
        modelContext.insert(entry)
        do {
            try modelContext.save()
            selectedEntry = entry
            Logger.ui.info("Created vocabulary entry: \(spokenForm) -> \(replacement)")
        } catch {
            Logger.ui.error("Failed to create vocabulary entry: \(error.localizedDescription)")
        }
    }
}

// MARK: - Vocabulary List

private struct VocabularyListView: View {
    let entries: [VocabularyEntry]
    @Binding var selectedEntry: VocabularyEntry?
    @Binding var scopeFilter: VocabularyEditorView.ScopeFilter
    let onNew: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var entryToDelete: VocabularyEntry?
    @State private var showDeleteConfirmation = false

    private var globalEntries: [VocabularyEntry] {
        entries.filter { $0.isGlobal }
    }

    private var perAppEntries: [VocabularyEntry] {
        entries.filter { !$0.isGlobal }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Scope", selection: $scopeFilter) {
                    ForEach(VocabularyEditorView.ScopeFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)

                Spacer()

                Button {
                    onNew()
                } label: {
                    Label("New Entry", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            List(selection: $selectedEntry) {
                if entries.isEmpty {
                    emptyStateView
                } else {
                    if !globalEntries.isEmpty {
                        Section {
                            ForEach(globalEntries) { entry in
                                VocabularyEntryRow(entry: entry)
                                    .tag(entry)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            entryToDelete = entry
                                            showDeleteConfirmation = true
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            entryToDelete = entry
                                            showDeleteConfirmation = true
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        } header: {
                            HStack {
                                Image(systemName: "globe")
                                Text("Global")
                            }
                        }
                    }

                    if !perAppEntries.isEmpty {
                        Section {
                            ForEach(perAppEntries) { entry in
                                VocabularyEntryRow(entry: entry)
                                    .tag(entry)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            entryToDelete = entry
                                            showDeleteConfirmation = true
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            entryToDelete = entry
                                            showDeleteConfirmation = true
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        } header: {
                            HStack {
                                Image(systemName: "app.badge")
                                Text("Per-App")
                            }
                        }
                    }
                }
            }
        }
        .alert("Delete Vocabulary Entry", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let entry = entryToDelete {
                    deleteEntry(entry)
                }
            }
        } message: {
            if let entry = entryToDelete {
                Text("Delete \"\(entry.spokenForm)\" → \"\(entry.replacement)\"? This action cannot be undone.")
            }
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView(
            "No Vocabulary Entries",
            systemImage: "character.book.closed",
            description: Text("Add entries to teach HushType custom word replacements")
        )
    }

    private func deleteEntry(_ entry: VocabularyEntry) {
        if selectedEntry?.id == entry.id {
            selectedEntry = entries.first { $0.id != entry.id }
        }
        modelContext.delete(entry)
        do {
            try modelContext.save()
            Logger.ui.info("Deleted vocabulary entry: \(entry.spokenForm)")
        } catch {
            Logger.ui.error("Failed to delete vocabulary entry: \(error.localizedDescription)")
        }
    }
}

// MARK: - Entry Row

private struct VocabularyEntryRow: View {
    let entry: VocabularyEntry

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\"\(entry.spokenForm)\"")
                        .font(.body)
                        .foregroundStyle(.primary)

                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\"\(entry.replacement)\"")
                        .font(.body)
                        .foregroundStyle(.primary)

                    if entry.caseSensitive {
                        Text("Aa")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.orange.opacity(0.2))
                            .foregroundStyle(.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }

                if let language = entry.language {
                    Text(language)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if !entry.isGlobal {
                Text(entry.appProfile?.appName ?? "App")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Entry Detail Editor

private struct VocabularyDetailView: View {
    let entry: VocabularyEntry

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Form {
            Section("Replacement Rule") {
                TextField("Spoken Form", text: Binding(
                    get: { entry.spokenForm },
                    set: { entry.spokenForm = $0; saveChanges() }
                ))
                .help("What whisper typically outputs, e.g. \"jay son\"")

                TextField("Replacement", text: Binding(
                    get: { entry.replacement },
                    set: { entry.replacement = $0; saveChanges() }
                ))
                .help("What should replace the spoken form, e.g. \"JSON\"")

                HStack(spacing: 6) {
                    Text("\"\(entry.spokenForm)\"")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\"\(entry.replacement)\"")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            Section("Matching Options") {
                Toggle("Case Sensitive", isOn: Binding(
                    get: { entry.caseSensitive },
                    set: { entry.caseSensitive = $0; saveChanges() }
                ))

                Text(entry.caseSensitive
                    ? "Only exact-case matches will be replaced (e.g. \"json\" won't match if spoken as \"JSON\")."
                    : "Matches regardless of case. \"json\", \"JSON\", and \"Json\" will all be replaced."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Scope") {
                Toggle("Global (all apps)", isOn: Binding(
                    get: { entry.isGlobal },
                    set: { entry.isGlobal = $0; saveChanges() }
                ))

                if !entry.isGlobal {
                    if let profile = entry.appProfile {
                        LabeledContent("App") {
                            Text(profile.appName)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No app profile linked. Enable Global or assign this entry to an app profile.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(entry.isGlobal
                    ? "This entry applies across all applications."
                    : "This entry only applies within the linked app profile."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Language") {
                Picker("Language", selection: Binding(
                    get: { entry.language ?? "" },
                    set: { entry.language = $0.isEmpty ? nil : $0; saveChanges() }
                )) {
                    Text("All Languages").tag("")
                    Text("English").tag("en")
                    Text("Turkish").tag("tr")
                    Text("German").tag("de")
                    Text("French").tag("fr")
                    Text("Spanish").tag("es")
                    Text("Italian").tag("it")
                    Text("Portuguese").tag("pt")
                    Text("Dutch").tag("nl")
                    Text("Polish").tag("pl")
                    Text("Russian").tag("ru")
                    Text("Japanese").tag("ja")
                    Text("Korean").tag("ko")
                    Text("Chinese").tag("zh")
                    Text("Arabic").tag("ar")
                    Text("Hindi").tag("hi")
                    Text("Swedish").tag("sv")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func saveChanges() {
        do {
            try modelContext.save()
            Logger.ui.debug("Saved vocabulary entry: \(entry.spokenForm) -> \(entry.replacement)")
        } catch {
            Logger.ui.error("Failed to save vocabulary entry: \(error.localizedDescription)")
        }
    }
}

// MARK: - New Entry Sheet

private struct NewVocabularyEntrySheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (String, String, String?, Bool, Bool) -> Void

    @State private var spokenForm = ""
    @State private var replacement = ""
    @State private var language = ""
    @State private var isGlobal = true
    @State private var caseSensitive = false

    private var canSave: Bool {
        !spokenForm.trimmingCharacters(in: .whitespaces).isEmpty &&
        !replacement.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("New Vocabulary Entry")
                .font(.title2)
                .fontWeight(.semibold)

            Form {
                Section("Replacement Rule") {
                    TextField("Spoken Form", text: $spokenForm)
                        .textFieldStyle(.roundedBorder)

                    TextField("Replacement", text: $replacement)
                        .textFieldStyle(.roundedBorder)

                    if !spokenForm.isEmpty || !replacement.isEmpty {
                        HStack(spacing: 6) {
                            Text("\"\(spokenForm.isEmpty ? "…" : spokenForm)\"")
                                .font(.callout)
                                .foregroundStyle(.secondary)

                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("\"\(replacement.isEmpty ? "…" : replacement)\"")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Options") {
                    Toggle("Case Sensitive", isOn: $caseSensitive)
                    Toggle("Global (all apps)", isOn: $isGlobal)
                    Picker("Language", selection: $language) {
                        Text("All Languages").tag("")
                        Text("English").tag("en")
                        Text("Turkish").tag("tr")
                        Text("German").tag("de")
                        Text("French").tag("fr")
                        Text("Spanish").tag("es")
                        Text("Italian").tag("it")
                        Text("Portuguese").tag("pt")
                        Text("Dutch").tag("nl")
                        Text("Polish").tag("pl")
                        Text("Russian").tag("ru")
                        Text("Japanese").tag("ja")
                        Text("Korean").tag("ko")
                        Text("Chinese").tag("zh")
                        Text("Arabic").tag("ar")
                        Text("Hindi").tag("hi")
                        Text("Swedish").tag("sv")
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
                    onSave(
                        spokenForm.trimmingCharacters(in: .whitespaces),
                        replacement.trimmingCharacters(in: .whitespaces),
                        language.trimmingCharacters(in: .whitespaces).isEmpty ? nil : language.trimmingCharacters(in: .whitespaces),
                        isGlobal,
                        caseSensitive
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding()
        .frame(width: 420, height: 420)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var container: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: VocabularyEntry.self, AppProfile.self, configurations: config)
        let context = ModelContext(container)

        context.insert(VocabularyEntry(spokenForm: "jay son", replacement: "JSON"))
        context.insert(VocabularyEntry(spokenForm: "ecks code", replacement: "Xcode"))
        context.insert(VocabularyEntry(spokenForm: "git hub", replacement: "GitHub", caseSensitive: true))
        context.insert(VocabularyEntry(spokenForm: "swift you eye", replacement: "SwiftUI", isGlobal: false))

        return container
    }()

    VocabularyEditorView()
        .modelContainer(container)
        .frame(width: 800, height: 600)
}
