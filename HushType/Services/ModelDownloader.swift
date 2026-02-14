import Foundation
import os

/// Downloads whisper/LLM models from remote URLs with progress tracking.
@Observable
final class ModelDownloader: @unchecked Sendable {
    private(set) var activeDownloads: Set<String> = []
    private var tasks: [String: URLSessionDownloadTask] = []
    private var observations: [String: NSKeyValueObservation] = []

    func download(_ model: ModelInfo) {
        guard let url = model.downloadURL else {
            Logger.models.error("No download URL for model: \(model.name)")
            return
        }

        guard !activeDownloads.contains(model.fileName) else {
            Logger.models.warning("Already downloading: \(model.name)")
            return
        }

        Logger.models.info("Starting download: \(model.name) from \(url)")
        activeDownloads.insert(model.fileName)
        model.downloadProgress = 0.0

        let task = URLSession.shared.downloadTask(with: url) { [weak self] tempURL, response, error in
            DispatchQueue.main.async {
                self?.handleCompletion(model: model, tempURL: tempURL, response: response, error: error)
            }
        }

        // Observe progress
        let observation = task.progress.observe(\.fractionCompleted) { progress, _ in
            DispatchQueue.main.async {
                model.downloadProgress = progress.fractionCompleted
            }
        }

        tasks[model.fileName] = task
        observations[model.fileName] = observation
        task.resume()
    }

    func cancel(_ model: ModelInfo) {
        tasks[model.fileName]?.cancel()
        cleanup(model)
        model.downloadProgress = nil
        Logger.models.info("Cancelled download: \(model.name)")
    }

    func isDownloading(_ model: ModelInfo) -> Bool {
        activeDownloads.contains(model.fileName)
    }

    // MARK: - Private

    private func handleCompletion(model: ModelInfo, tempURL: URL?, response: URLResponse?, error: Error?) {
        defer { cleanup(model) }

        if let error = error as? URLError, error.code == .cancelled {
            return
        }

        if let error {
            Logger.models.error("Download failed for \(model.name): \(error.localizedDescription)")
            model.downloadProgress = nil
            return
        }

        guard let tempURL else {
            Logger.models.error("No file received for \(model.name)")
            model.downloadProgress = nil
            return
        }

        // Move to final location
        let destDir = model.filePath.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

            if FileManager.default.fileExists(atPath: model.filePath.path) {
                try FileManager.default.removeItem(at: model.filePath)
            }

            try FileManager.default.moveItem(at: tempURL, to: model.filePath)

            model.isDownloaded = true
            model.downloadProgress = nil
            Logger.models.info("Download complete: \(model.name) -> \(model.filePath.path)")
        } catch {
            Logger.models.error("Failed to save model \(model.name): \(error.localizedDescription)")
            model.downloadProgress = nil
        }
    }

    private func cleanup(_ model: ModelInfo) {
        activeDownloads.remove(model.fileName)
        observations[model.fileName]?.invalidate()
        observations.removeValue(forKey: model.fileName)
        tasks.removeValue(forKey: model.fileName)
    }
}
