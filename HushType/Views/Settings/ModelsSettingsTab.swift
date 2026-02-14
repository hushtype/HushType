import SwiftUI
import SwiftData
import os

struct ModelsSettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allModels: [ModelInfo]
    private var whisperModels: [ModelInfo] {
        allModels.filter { $0.type == .whisper }
    }

    @State private var settings: UserSettings?
    @State private var downloader = ModelDownloader()

    var body: some View {
        Form {
            Section("Active Model") {
                Picker("Selected Whisper Model", selection: Binding(
                    get: { settings?.selectedWhisperModel ?? "ggml-base.en.bin" },
                    set: { newValue in
                        settings?.selectedWhisperModel = newValue
                        saveSettings()
                    }
                )) {
                    ForEach(whisperModels, id: \.fileName) { model in
                        if model.isDownloaded {
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
                }
                .help("Speech-to-text model used for transcription")
            }

            Section("Available Models") {
                if whisperModels.isEmpty {
                    Text("No models found. Models will be seeded on first launch.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    List {
                        ForEach(whisperModels) { model in
                            ModelRow(model: model, downloader: downloader)
                        }
                    }
                    .frame(height: 250)
                }
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
            Logger.ui.debug("Loaded user settings in Models tab")
        } catch {
            Logger.ui.error("Failed to load UserSettings: \(error.localizedDescription)")
        }
    }

    private func saveSettings() {
        do {
            try modelContext.save()
            Logger.ui.debug("Saved user settings from Models tab")
        } catch {
            Logger.ui.error("Failed to save UserSettings: \(error.localizedDescription)")
        }
    }
}

struct ModelRow: View {
    let model: ModelInfo
    let downloader: ModelDownloader
    @Environment(\.modelContext) private var modelContext

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
                    deleteModel(model)
                } label: {
                    Label("Delete", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .help("Delete this model from disk")
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
        .padding(.vertical, 4)
    }

    private func deleteModel(_ model: ModelInfo) {
        Logger.models.info("Delete requested for model: \(model.name)")
        do {
            try FileManager.default.removeItem(at: model.filePath)
            model.isDownloaded = false
            try modelContext.save()
            Logger.models.info("Deleted model: \(model.name)")
        } catch {
            Logger.models.error("Failed to delete model \(model.name): \(error.localizedDescription)")
        }
    }
}

#Preview {
    ModelsSettingsTab()
        .modelContainer(for: [ModelInfo.self, UserSettings.self], inMemory: true)
        .frame(width: 500, height: 400)
}
