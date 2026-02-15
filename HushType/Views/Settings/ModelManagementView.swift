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
    @State private var selectedModelType: ModelType = .whisper

    private var whisperModels: [ModelInfo] {
        allModels.filter { $0.type == .whisper }
    }

    private var llmModels: [ModelInfo] {
        allModels.filter { $0.type == .llm }
    }

    var body: some View {
        Form {
            // Model Type Selector
            Section {
                Picker("Model Type", selection: $selectedModelType) {
                    ForEach(ModelType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Active Model Selection
            activeModelSection

            // Disk Usage Summary
            diskUsageSection

            // Available Models List
            availableModelsSection

            // Import Button
            Section {
                Button {
                    importModel()
                } label: {
                    Label("Import GGUF Model", systemImage: "square.and.arrow.down")
                }
                .help("Import a custom \(selectedModelType == .whisper ? "Whisper" : "LLM") model from disk")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadSettings()
            modelManager.syncDownloadStates(allModels)
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
                        settings?.selectedLLMModel = newValue
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

    // MARK: - Disk Usage Section

    @ViewBuilder
    private var diskUsageSection: some View {
        Section("Disk Usage") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Whisper Models:")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatBytes(modelManager.diskUsage(for: .whisper, models: allModels)))
                        .fontWeight(.medium)
                }

                HStack {
                    Text("LLM Models:")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatBytes(modelManager.diskUsage(for: .llm, models: allModels)))
                        .fontWeight(.medium)
                }

                Divider()

                HStack {
                    Text("Total:")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(formatBytes(modelManager.totalDiskUsage(models: allModels)))
                        .fontWeight(.semibold)
                }
            }
            .font(.callout)
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
                List {
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
                .frame(height: 250)
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
            Logger.ui.debug("Saved user settings from ModelManagement view")
        } catch {
            Logger.ui.error("Failed to save UserSettings: \(error.localizedDescription)")
        }
    }

    private func importModel() {
        if let importedModel = modelManager.importGGUFModel(type: selectedModelType, context: modelContext) {
            do {
                try modelContext.save()
                Logger.ui.info("Successfully imported model: \(importedModel.name)")
            } catch {
                Logger.ui.error("Failed to save imported model: \(error.localizedDescription)")
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
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
                    } else {
                        Label("Not Downloaded", systemImage: "icloud.and.arrow.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
                } else if model.isDownloaded {
                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .labelStyle(.iconOnly)
                    }
                    .help(isActiveModel ? "Cannot delete the active model" : "Delete this model from disk")
                    .disabled(isActiveModel)
                } else {
                    Button {
                        downloader.download(model)
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                            .labelStyle(.iconOnly)
                    }
                    .help("Download this model")
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
            Text("Delete \(model.name) (\(model.formattedFileSize))? You can re-download it later if it has a download URL.")
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
