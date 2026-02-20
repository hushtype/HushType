import SwiftUI
import SwiftData
import os

/// Unified view for managing both Whisper and LLM models.
struct ModelManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allModels: [ModelInfo]

    @State private var settings: UserSettings?
    @State private var downloader = ModelDownloader()
    @State private var modelManager = ModelManager()
    @State private var registryService = ModelRegistryService()
    @State private var selectedModelType: ModelType = .whisper

    private var whisperModels: [ModelInfo] {
        allModels.filter { $0.type == .whisper }
    }

    private var llmModels: [ModelInfo] {
        allModels.filter { $0.type == .llm }
    }

    var body: some View {
        Form {
            // Model Registry Status
            registrySection

            // Model Type Selector
            Section {
                Picker("Model Type", selection: $selectedModelType) {
                    ForEach(ModelType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Model type: \(selectedModelType.displayName)")
                .accessibilityHint("Switch between Whisper speech-to-text models and LLM text-processing models")
            }

            // Model info guide (type-specific)
            modelInfoSection

            // Active Model Selection
            activeModelSection

            // Available Models List
            availableModelsSection

        }
        .formStyle(.grouped)
        .onAppear {
            loadSettings()
            modelManager.syncDownloadStates(allModels)
            registryService.modelContainer = modelContext.container
            Task { await registryService.refreshIfNeeded() }
        }
    }

    // MARK: - Registry Section

    @ViewBuilder
    private var registrySection: some View {
        Section {
            HStack {
                if let lastRefresh = registryService.lastRefreshDate {
                    Text("Last checked: \(lastRefresh, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Model registry not yet checked")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task { await registryService.refresh() }
                } label: {
                    if registryService.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Checking for model updates")
                    } else {
                        Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(registryService.isRefreshing)
                .accessibilityLabel(registryService.isRefreshing ? "Checking for updates" : "Check for model updates")
                .accessibilityHint("Refreshes the list of available models from the registry")
            }

            if let error = registryService.lastRefreshError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Model Registry")
        }
    }

    // MARK: - Model Info Section

    @ViewBuilder
    private var modelInfoSection: some View {
        if selectedModelType == .whisper {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Larger models are more accurate but slower and use more memory. English-only models (.en) are optimized for English speech.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                        GridRow {
                            Text("Model").bold()
                            Text("Size").bold()
                            Text("RAM").bold()
                            Text("Speed").bold()
                            Text("Accuracy").bold()
                        }
                        .font(.caption)
                        Divider().gridCellColumns(5)
                        GridRow {
                            Text("Tiny"); Text("75 MB"); Text("~273 MB"); Text("Fastest"); Text("Basic")
                        }
                        GridRow {
                            Text("Base"); Text("142 MB"); Text("~388 MB"); Text("Fast"); Text("Good")
                        }
                        GridRow {
                            Text("Small"); Text("466 MB"); Text("~852 MB"); Text("Moderate"); Text("Better")
                        }
                        GridRow {
                            Text("Medium"); Text("1.5 GB"); Text("~2.1 GB"); Text("Slow"); Text("Very Good")
                        }
                        GridRow {
                            Text("Large v3 Turbo"); Text("1.5 GB"); Text("~2.1 GB"); Text("Slow"); Text("Best")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Text("Recommended: Base for daily use. Upgrade to Small if you notice frequent errors.")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            } header: {
                Text("Choosing a Model")
            }
        } else {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("LLM models post-process transcriptions: fixing grammar, structuring text, or generating code. Larger models produce better results but use more memory.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                        GridRow {
                            Text("Model").bold()
                            Text("Size").bold()
                            Text("RAM").bold()
                            Text("Quality").bold()
                        }
                        .font(.caption)
                        Divider().gridCellColumns(4)
                        GridRow {
                            Text("Qwen 2.5 0.5B"); Text("463 MB"); Text("~900 MB"); Text("Good")
                        }
                        GridRow {
                            Text("Gemma 3 1B"); Text("806 MB"); Text("~1.5 GB"); Text("Better")
                        }
                        GridRow {
                            Text("Llama 3.2 1B"); Text("808 MB"); Text("~1.5 GB"); Text("Better")
                        }
                        GridRow {
                            Text("Qwen 2.5 1.5B"); Text("1.1 GB"); Text("~2 GB"); Text("Great")
                        }
                        GridRow {
                            Text("Phi-4 Mini 3.8B"); Text("2.5 GB"); Text("~4 GB"); Text("Best")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Text("Recommended: Qwen 2.5 0.5B for fast cleanup. Phi-4 Mini for best quality.")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            } header: {
                Text("Choosing a Model")
            }
        }
    }

    // MARK: - Active Model Section

    @ViewBuilder
    private var activeModelSection: some View {
        Section("Active Model") {
            if selectedModelType == .whisper {
                Picker("Selected Whisper Model", selection: Binding(
                    get: { settings?.selectedWhisperModel ?? "ggml-base.en.bin" },
                    set: { newValue in
                        settings?.selectedWhisperModel = newValue
                        saveSettings()
                    }
                )) {
                    ForEach(whisperModels.filter { $0.isDownloaded }, id: \.fileName) { model in
                        HStack {
                            Text(model.name)
                            if model.isDefault {
                                Text("(Default)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(model.fileName)
                    }
                }
                .help("Speech-to-text model used for transcription")
            } else {
                Picker("Selected LLM", selection: Binding(
                    get: { settings?.selectedLLMModel ?? "" },
                    set: { newValue in
                        settings?.selectedLLMModel = newValue.isEmpty ? nil : newValue
                        saveSettings()
                    }
                )) {
                    Text("None").tag("")
                    ForEach(llmModels.filter { $0.isDownloaded }, id: \.fileName) { model in
                        HStack {
                            Text(model.name)
                            if model.isDefault {
                                Text("(Default)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(model.fileName)
                    }
                }
                .help("Language model used for post-processing")
            }
        }
    }

    // MARK: - Available Models Section

    @ViewBuilder
    private var availableModelsSection: some View {
        Section("Available Models") {
            let models = selectedModelType == .whisper ? whisperModels : llmModels

            if models.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No \(selectedModelType.displayName) models found.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    Text("Use the Import button below to add a model, or wait for models to be seeded on first launch.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            } else {
                ForEach(models) { model in
                    UnifiedModelRow(
                        model: model,
                        downloader: downloader,
                        modelManager: modelManager,
                        selectedModelFileName: selectedModelType == .whisper
                            ? (settings?.selectedWhisperModel ?? "ggml-base.en.bin")
                            : (settings?.selectedLLMModel ?? "")
                    )
                }
            }
        }
    }

    // MARK: - Actions

    private func loadSettings() {
        do {
            settings = try UserSettings.shared(in: modelContext)
            Logger.ui.debug("Loaded user settings in ModelManagement view")
        } catch {
            Logger.ui.error("Failed to load UserSettings: \(error.localizedDescription)")
        }
    }

    private func saveSettings() {
        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .userSettingsChanged, object: nil)
            Logger.ui.debug("Saved user settings from ModelManagement view")
        } catch {
            Logger.ui.error("Failed to save UserSettings: \(error.localizedDescription)")
        }
    }
}

// MARK: - Unified Model Row

/// Row view for a single model (works for both Whisper and LLM).
struct UnifiedModelRow: View {
    let model: ModelInfo
    let downloader: ModelDownloader
    let modelManager: ModelManager
    let selectedModelFileName: String

    @Environment(\.modelContext) private var modelContext
    @State private var showDeleteConfirmation = false

    private var isActiveModel: Bool {
        model.fileName == selectedModelFileName
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(model.name)
                        .font(.headline)

                    if model.isDefault {
                        Text("Default")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.2))
                            .foregroundStyle(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    if isActiveModel && model.isDownloaded {
                        Text("Active")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.2))
                            .foregroundStyle(.green)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    if model.isDeprecated {
                        Text("Deprecated")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.2))
                            .foregroundStyle(.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                HStack(spacing: 12) {
                    Label(model.formattedFileSize, systemImage: "doc")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let progress = model.downloadProgress {
                        ProgressView(value: progress, total: 1.0)
                            .frame(width: 80)
                        Text("\(Int(progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if model.isDownloaded {
                        Label("Downloaded", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else if let error = model.lastDownloadError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    } else {
                        Label("Not Downloaded", systemImage: "icloud.and.arrow.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let notes = model.registryNotes {
                    Text(notes)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Action Buttons
            HStack(spacing: 8) {
                if downloader.isDownloading(model) {
                    Button {
                        downloader.cancel(model)
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                            .labelStyle(.iconOnly)
                    }
                    .help("Cancel download")
                    .accessibilityLabel("Cancel download of \(model.name)")
                    .accessibilityHint("Stops the current download")
                } else if model.isDownloaded {
                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .labelStyle(.iconOnly)
                    }
                    .help(isActiveModel ? "Cannot delete the active model" : "Delete this model from disk")
                    .disabled(isActiveModel)
                    .accessibilityLabel(isActiveModel ? "Cannot delete active model \(model.name)" : "Delete \(model.name)")
                    .accessibilityHint(isActiveModel ? "This model is currently active and cannot be deleted" : "Removes \(model.name) from disk. You can re-download it later.")
                } else if model.lastDownloadError != nil {
                    Button {
                        model.lastDownloadError = nil
                        downloader.download(model)
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .labelStyle(.iconOnly)
                    }
                    .help("Retry download")
                    .accessibilityLabel("Retry download of \(model.name)")
                    .accessibilityHint("Attempts to download the model again after a previous failure")
                } else {
                    Button {
                        downloader.download(model)
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                            .labelStyle(.iconOnly)
                    }
                    .help("Download this model")
                    .accessibilityLabel("Download \(model.name)")
                    .accessibilityHint("Downloads \(model.formattedFileSize) model file for offline use")
                }
            }
        }
        .padding(.vertical, 4)
        .alert("Delete Model", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteModel()
            }
        } message: {
            Text("Delete \(model.name) (\(model.formattedFileSize))? You can re-download it later.")
        }
    }

    private func deleteModel() {
        Logger.models.info("Delete requested for model: \(model.name)")
        do {
            try modelManager.deleteModelFile(model)
            try modelContext.save()
            Logger.models.info("Deleted model: \(model.name)")
        } catch {
            Logger.models.error("Failed to delete model \(model.name): \(error.localizedDescription)")
        }
    }
}

// MARK: - Preview

#Preview {
    ModelManagementView()
        .modelContainer(for: [ModelInfo.self, UserSettings.self], inMemory: true)
        .frame(width: 600, height: 500)
}
