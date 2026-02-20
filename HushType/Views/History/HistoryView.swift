import SwiftUI
import SwiftData
import os

// MARK: - HistoryView

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DictationEntry.timestamp, order: .reverse)
    private var entries: [DictationEntry]

    @State private var searchText: String = ""
    @State private var selectedEntry: DictationEntry?
    @State private var entryToDelete: DictationEntry?
    @State private var showDeleteConfirmation = false

    // Filters
    @State private var filterApp: String? = nil
    @State private var filterMode: ProcessingMode? = nil
    @State private var filterFavoritesOnly: Bool = false
    @State private var filterDateFrom: Date? = nil
    @State private var filterDateTo: Date? = nil

    // Edit/re-inject
    @State private var isEditingForInject: Bool = false
    @State private var editText: String = ""
    @State private var editEntry: DictationEntry?

    /// All unique app names in history, for the filter picker.
    private var uniqueAppNames: [String] {
        Array(Set(entries.compactMap(\.appName))).sorted()
    }

    private var filteredEntries: [DictationEntry] {
        var result = entries

        // Text search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { entry in
                entry.outputText.lowercased().contains(query)
                    || entry.rawText.lowercased().contains(query)
                    || (entry.appName?.lowercased().contains(query) ?? false)
                    || entry.mode.displayName.lowercased().contains(query)
            }
        }

        // App filter
        if let app = filterApp {
            result = result.filter { $0.appName == app }
        }

        // Mode filter
        if let mode = filterMode {
            result = result.filter { $0.mode == mode }
        }

        // Favorites filter
        if filterFavoritesOnly {
            result = result.filter(\.isFavorite)
        }

        // Date range filter
        if let from = filterDateFrom {
            result = result.filter { $0.timestamp >= from }
        }
        if let to = filterDateTo {
            let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: to) ?? to
            result = result.filter { $0.timestamp < endOfDay }
        }

        return result
    }

    private var hasActiveFilters: Bool {
        filterApp != nil || filterMode != nil || filterFavoritesOnly || filterDateFrom != nil || filterDateTo != nil
    }

    var body: some View {
        HStack(spacing: 0) {
            listSidebar
                .frame(maxWidth: .infinity)

            Divider()

            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 600, minHeight: 400)
        .alert("Delete Entry", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let entry = entryToDelete {
                    deleteEntry(entry)
                }
            }
        } message: {
            Text("Delete this dictation entry? This action cannot be undone.")
        }
        .sheet(isPresented: $isEditingForInject) {
            editAndInjectSheet
        }
    }

    // MARK: - Edit & Re-inject Sheet

    private var editAndInjectSheet: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Edit & Inject")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    isEditingForInject = false
                }
                .accessibilityLabel("Cancel")
                .accessibilityHint("Closes the editor without injecting")
            }

            TextEditor(text: $editText)
                .font(.body)
                .frame(minHeight: 120)
                .border(Color.secondary.opacity(0.3))
                .accessibilityLabel("Edit text before injection")
                .accessibilityHint("Modify the text, then press Inject at Cursor to insert it")

            HStack {
                Spacer()
                Button("Inject at Cursor") {
                    injectText(editText)
                    isEditingForInject = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityLabel("Inject at cursor")
                .accessibilityHint("Types the edited text at the current cursor position")
            }
        }
        .padding(20)
        .frame(width: 450, height: 250)
    }

    private func injectText(_ text: String) {
        let injector = TextInjectionService(permissionsManager: PermissionsManager())
        Task {
            do {
                try await injector.inject(text, method: .auto)
                Logger.ui.info("Re-injected text from history: \(text.count) chars")
            } catch {
                Logger.ui.error("Re-inject failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Sidebar

    private var listSidebar: some View {
        VStack(spacing: 0) {
            // Search + filter bar
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .accessibilityHidden(true)
                    TextField("Search history", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.callout)
                        .accessibilityLabel("Search history")
                        .accessibilityHint("Filter entries by text, app name, or processing mode")
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 6))

                Menu {
                    Menu("App") {
                        Button("All Apps") { filterApp = nil }
                        Divider()
                        ForEach(uniqueAppNames, id: \.self) { name in
                            Button(name) { filterApp = name }
                        }
                    }
                    Menu("Mode") {
                        Button("All Modes") { filterMode = nil }
                        Divider()
                        ForEach(ProcessingMode.allCases, id: \.self) { mode in
                            Button(mode.displayName) { filterMode = mode }
                        }
                    }
                    Toggle("Favorites Only", isOn: $filterFavoritesOnly)
                    Divider()
                    Button("Clear Filters") {
                        filterApp = nil
                        filterMode = nil
                        filterFavoritesOnly = false
                        filterDateFrom = nil
                        filterDateTo = nil
                    }
                } label: {
                    Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .accessibilityLabel(hasActiveFilters ? "Filters active" : "Filter")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel(hasActiveFilters ? "Filter history (filters active)" : "Filter history")
                .accessibilityHint("Filter by app, processing mode, or favorites")

                Text("\(filteredEntries.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .accessibilityLabel("\(filteredEntries.count) entries")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            if filteredEntries.isEmpty {
                emptyStateView
            } else {
                ScrollViewReader { proxy in
                    List(selection: $selectedEntry) {
                        ForEach(filteredEntries) { entry in
                            HistoryRowView(entry: entry, onToggleFavorite: {
                                toggleFavorite(entry)
                            })
                            .tag(entry)
                            .id(entry.id)
                            .contextMenu {
                                Button {
                                    toggleFavorite(entry)
                                } label: {
                                    Label(
                                        entry.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                                        systemImage: entry.isFavorite ? "star.slash" : "star"
                                    )
                                }

                                Divider()

                                Button(role: .destructive) {
                                    entryToDelete = entry
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    entryToDelete = entry
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }

                                Button {
                                    toggleFavorite(entry)
                                } label: {
                                    Label(
                                        entry.isFavorite ? "Unfavorite" : "Favorite",
                                        systemImage: entry.isFavorite ? "star.slash.fill" : "star.fill"
                                    )
                                }
                                .tint(.yellow)
                            }
                        }
                        .onDelete { offsets in
                            deleteAtOffsets(offsets)
                        }
                    }
                    .onChange(of: searchText) {
                        scrollToTop(proxy: proxy)
                    }
                    .onChange(of: filterApp) {
                        scrollToTop(proxy: proxy)
                    }
                    .onChange(of: filterMode) {
                        scrollToTop(proxy: proxy)
                    }
                    .onChange(of: filterFavoritesOnly) {
                        scrollToTop(proxy: proxy)
                    }
                }
            }
        }
    }

    // MARK: - Detail Pane

    @ViewBuilder
    private var detailPane: some View {
        if let entry = selectedEntry {
            HistoryDetailView(entry: entry, onToggleFavorite: {
                toggleFavorite(entry)
            }, onDelete: {
                entryToDelete = entry
                showDeleteConfirmation = true
                selectedEntry = nil
            }, onEditAndInject: {
                editEntry = entry
                editText = entry.outputText
                isEditingForInject = true
            })
        } else {
            ContentUnavailableView(
                "No Entry Selected",
                systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                description: Text("Select a dictation entry to view its full content")
            )
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            VStack(spacing: 4) {
                Text(searchText.isEmpty ? "No Dictation History" : "No Results")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Text(
                    searchText.isEmpty
                        ? "Your dictation history will appear here after your first recording."
                        : "No entries match \"\(searchText)\"."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func scrollToTop(proxy: ScrollViewProxy) {
        if let first = filteredEntries.first {
            withAnimation {
                proxy.scrollTo(first.id, anchor: .top)
            }
        }
    }

    private func toggleFavorite(_ entry: DictationEntry) {
        entry.isFavorite.toggle()
        do {
            try modelContext.save()
            Logger.ui.debug("Toggled favorite for entry: \(entry.id)")
        } catch {
            Logger.ui.error("Failed to save favorite toggle: \(error.localizedDescription)")
        }
    }

    private func deleteEntry(_ entry: DictationEntry) {
        if selectedEntry?.id == entry.id {
            selectedEntry = nil
        }
        modelContext.delete(entry)
        do {
            try modelContext.save()
            Logger.ui.info("Deleted dictation entry: \(entry.id)")
        } catch {
            Logger.ui.error("Failed to delete entry: \(error.localizedDescription)")
        }
    }

    private func deleteAtOffsets(_ offsets: IndexSet) {
        for index in offsets {
            let entry = filteredEntries[index]
            if selectedEntry?.id == entry.id {
                selectedEntry = nil
            }
            modelContext.delete(entry)
        }
        do {
            try modelContext.save()
            Logger.ui.info("Deleted \(offsets.count) dictation entries via swipe/keyboard")
        } catch {
            Logger.ui.error("Failed to delete entries: \(error.localizedDescription)")
        }
    }
}

// MARK: - History Row View

private struct HistoryRowView: View {
    let entry: DictationEntry
    let onToggleFavorite: () -> Void

    private var preview: String {
        let text = entry.outputText
        guard text.count > 80 else { return text }
        return String(text.prefix(80)) + "…"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Left: favorite star + mode icon
            VStack(spacing: 6) {
                Button {
                    onToggleFavorite()
                } label: {
                    Image(systemName: entry.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 13))
                        .foregroundStyle(entry.isFavorite ? Color.yellow : Color.gray.opacity(0.3))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(entry.isFavorite ? "Remove from favorites" : "Add to favorites")
                .accessibilityHint("Toggles the favorite status of this entry")

                Image(systemName: entry.mode.iconName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Mode: \(entry.mode.displayName)")
            }
            .frame(width: 22)

            // Center: text preview + app name
            VStack(alignment: .leading, spacing: 3) {
                Text(preview)
                    .font(.body)
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                HStack(spacing: 4) {
                    if let appName = entry.appName, !appName.isEmpty {
                        Text(appName)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Text(entry.mode.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            // Right: relative time + word count
            VStack(alignment: .trailing, spacing: 3) {
                Text(entry.timestamp.relativeFormatted)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Text("\(entry.wordCount)w")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - History Detail View

private struct HistoryDetailView: View {
    let entry: DictationEntry
    let onToggleFavorite: () -> Void
    let onDelete: () -> Void
    var onEditAndInject: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header metadata
                metadataHeader

                Divider()

                // Output text (the injected text)
                textSection(
                    title: "Output Text",
                    icon: "text.quote",
                    content: entry.outputText
                )

                // Raw text if it differs
                if let processed = entry.processedText, processed != entry.rawText {
                    Divider()

                    textSection(
                        title: "Raw Transcription",
                        icon: "waveform",
                        content: entry.rawText
                    )
                }
            }
            .padding(24)
        }
        .safeAreaInset(edge: .top) {
            HStack(spacing: 10) {
                if let onEditAndInject {
                    Button {
                        onEditAndInject()
                    } label: {
                        Label("Edit & Inject", systemImage: "text.cursor")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Edit and inject")
                    .accessibilityHint("Opens the editor to modify this entry and inject text at the cursor")
                }

                Spacer()

                Button {
                    onToggleFavorite()
                } label: {
                    Label(
                        entry.isFavorite ? "Unfavorite" : "Favorite",
                        systemImage: entry.isFavorite ? "star.fill" : "star"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundStyle(entry.isFavorite ? .yellow : .secondary)
                .accessibilityLabel(entry.isFavorite ? "Remove from favorites" : "Add to favorites")
                .accessibilityHint("Toggles the favorite status of this entry")

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Delete entry")
                .accessibilityHint("Permanently deletes this dictation entry")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var metadataHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: entry.mode.iconName)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)

                Text(entry.mode.displayName)
                    .font(.title3)
                    .fontWeight(.semibold)

                if entry.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }

                Spacer()
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    metadataLabel("Date")
                    Text(entry.timestamp, style: .date)
                        .font(.callout)
                }
                GridRow {
                    metadataLabel("Time")
                    Text(entry.timestamp, style: .time)
                        .font(.callout)
                }
                if let appName = entry.appName, !appName.isEmpty {
                    GridRow {
                        metadataLabel("App")
                        Text(appName)
                            .font(.callout)
                    }
                }
                GridRow {
                    metadataLabel("Words")
                    Text("\(entry.wordCount)")
                        .font(.callout)
                }
                GridRow {
                    metadataLabel("Duration")
                    Text(entry.audioDuration.durationFormatted)
                        .font(.callout)
                }
                if entry.wordsPerMinute > 0 {
                    GridRow {
                        metadataLabel("WPM")
                        Text(String(format: "%.0f", entry.wordsPerMinute))
                            .font(.callout)
                    }
                }
                GridRow {
                    metadataLabel("Language")
                    Text(entry.language.uppercased())
                        .font(.callout)
                }
            }
        }
    }

    private func metadataLabel(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(minWidth: 72, alignment: .leading)
    }

    private func textSection(title: String, icon: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(content, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Copy \(title.lowercased())")
                .accessibilityHint("Copies the text to the clipboard")
            }

            Text(content)
                .font(.body)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Date Formatting Helpers

private extension Date {
    /// Returns a concise relative string like "2h ago", "3d ago", "just now".
    var relativeFormatted: String {
        let seconds = Date.now.timeIntervalSince(self)

        switch seconds {
        case ..<60:
            return "just now"
        case ..<3_600:
            let minutes = Int(seconds / 60)
            return "\(minutes)m ago"
        case ..<86_400:
            let hours = Int(seconds / 3_600)
            return "\(hours)h ago"
        case ..<604_800:
            let days = Int(seconds / 86_400)
            return "\(days)d ago"
        default:
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            return formatter.string(from: self)
        }
    }
}

private extension TimeInterval {
    /// Returns a human-readable duration like "1m 23s" or "45s".
    var durationFormatted: String {
        let total = Int(self)
        let minutes = total / 60
        let seconds = total % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var container: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: DictationEntry.self, configurations: config)
        let context = ModelContext(container)

        let sampleEntries: [DictationEntry] = [
            DictationEntry(
                rawText: "this is a raw transcription without any processing applied to it",
                processedText: "This is a raw transcription without any processing applied to it.",
                mode: .clean,
                language: "en",
                appBundleIdentifier: "com.apple.TextEdit",
                appName: "TextEdit",
                audioDuration: 4.2,
                wordCount: 13,
                timestamp: Date().addingTimeInterval(-3_600),
                isFavorite: true
            ),
            DictationEntry(
                rawText: "write a function that calculates the fibonacci sequence recursively",
                processedText: "func fibonacci(_ n: Int) -> Int {\n    guard n > 1 else { return n }\n    return fibonacci(n - 1) + fibonacci(n - 2)\n}",
                mode: .code,
                language: "en",
                appBundleIdentifier: "com.apple.dt.Xcode",
                appName: "Xcode",
                audioDuration: 6.1,
                wordCount: 10,
                timestamp: Date().addingTimeInterval(-7_200),
                isFavorite: false
            ),
            DictationEntry(
                rawText: "meeting notes from today agenda items include project status update and team feedback session",
                processedText: "## Meeting Notes\n\n**Agenda:**\n- Project status update\n- Team feedback session",
                mode: .structure,
                language: "en",
                appBundleIdentifier: "com.apple.Notes",
                appName: "Notes",
                audioDuration: 8.5,
                wordCount: 16,
                timestamp: Date().addingTimeInterval(-86_400),
                isFavorite: false
            ),
            DictationEntry(
                rawText: "um so basically what I'm trying to say is that the quick brown fox jumps over the lazy dog",
                mode: .raw,
                language: "en",
                appBundleIdentifier: "com.apple.Safari",
                appName: "Safari",
                audioDuration: 5.8,
                wordCount: 18,
                timestamp: Date().addingTimeInterval(-172_800),
                isFavorite: false
            ),
        ]

        for entry in sampleEntries {
            context.insert(entry)
        }
        return container
    }()

    HistoryView()
        .modelContainer(container)
        .frame(width: 800, height: 550)
}
