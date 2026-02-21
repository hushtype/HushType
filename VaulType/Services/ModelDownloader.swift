import Foundation
import os

extension Notification.Name {
    static let whisperModelDownloaded = Notification.Name("com.vaultype.whisperModelDownloaded")
    static let llmModelDownloaded = Notification.Name("com.vaultype.llmModelDownloaded")
    static let userSettingsChanged = Notification.Name("com.vaultype.userSettingsChanged")
}

/// Downloads whisper/LLM models from remote URLs with progress tracking.
///
/// Supports HTTP status validation, SHA-256 checksum verification, and
/// automatic fallback to mirror URLs on failure.
@Observable
final class ModelDownloader: @unchecked Sendable {
    private(set) var activeDownloads: Set<String> = []
    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var observations: [String: NSKeyValueObservation] = [:]

    /// Tracks which URL index is being tried for mirror fallback.
    var urlIndices: [String: Int] = [:]

    /// SHA-256 verification function. Override in tests to avoid ModelManager dependency.
    var verifyChecksum: (ModelInfo, String) -> Bool = { model, expectedHash in
        ModelManager().verifySHA256(for: model, expectedHash: expectedHash)
    }

    func download(_ model: ModelInfo) {
        startDownload(model, urlIndex: 0)
    }

    func cancel(_ model: ModelInfo) {
        tasks[model.fileName]?.cancel()
        cleanup(model)
        model.downloadProgress = nil
        urlIndices.removeValue(forKey: model.fileName)
        Logger.models.info("Cancelled download: \(model.name)")
    }

    func isDownloading(_ model: ModelInfo) -> Bool {
        activeDownloads.contains(model.fileName)
    }

    // MARK: - Private

    /// Builds the ordered list of URLs to try: primary + mirrors.
    func allURLs(for model: ModelInfo) -> [URL] {
        var urls: [URL] = []
        if let primary = model.downloadURL {
            urls.append(primary)
        }
        urls.append(contentsOf: model.mirrorURLs.compactMap { URL(string: $0) })
        return urls
    }

    /// Starts a download attempt at the given URL index.
    private func startDownload(_ model: ModelInfo, urlIndex: Int) {
        let urls = allURLs(for: model)
        guard urlIndex < urls.count else {
            Logger.models.error("No download URL for model: \(model.name)")
            model.lastDownloadError = "No download URL available"
            return
        }

        guard !activeDownloads.contains(model.fileName) else {
            Logger.models.warning("Already downloading: \(model.name)")
            return
        }

        let url = urls[urlIndex]
        urlIndices[model.fileName] = urlIndex
        model.lastDownloadError = nil

        Logger.models.info("Starting download: \(model.name) from \(url) (URL \(urlIndex + 1)/\(urls.count))")
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

    func handleCompletion(model: ModelInfo, tempURL: URL?, response: URLResponse?, error: Error?) {
        // NOTE: cleanup(model) is called explicitly on each path rather than
        // via `defer`, because tryNextMirror() calls startDownload() which
        // sets up new state. A defer would wipe that new state after return.

        if let error = error as? URLError, error.code == .cancelled {
            cleanup(model)
            return
        }

        // Network error — try next mirror
        if let error {
            let msg = error.localizedDescription
            Logger.models.error("Download failed for \(model.name): \(msg)")
            cleanup(model)
            if tryNextMirror(model: model, error: msg) { return }
            model.downloadProgress = nil
            model.lastDownloadError = msg
            return
        }

        // HTTP status validation
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            let msg = "HTTP \(httpResponse.statusCode)"
            Logger.models.error("Download rejected for \(model.name): \(msg)")
            cleanup(model)
            if tryNextMirror(model: model, error: msg) { return }
            model.downloadProgress = nil
            model.lastDownloadError = msg
            return
        }

        guard let tempURL else {
            let msg = "No file received"
            Logger.models.error("\(msg) for \(model.name)")
            cleanup(model)
            if tryNextMirror(model: model, error: msg) { return }
            model.downloadProgress = nil
            model.lastDownloadError = msg
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
        } catch {
            let msg = "Failed to save: \(error.localizedDescription)"
            Logger.models.error("Failed to save model \(model.name): \(error.localizedDescription)")
            cleanup(model)
            model.downloadProgress = nil
            model.lastDownloadError = msg
            return
        }

        // SHA-256 checksum validation
        if let expectedHash = model.sha256 {
            if !verifyChecksum(model, expectedHash) {
                try? FileManager.default.removeItem(at: model.filePath)
                let msg = "Checksum mismatch — file deleted"
                Logger.models.error("SHA-256 verification failed for \(model.name)")
                cleanup(model)
                if tryNextMirror(model: model, error: msg) { return }
                model.downloadProgress = nil
                model.lastDownloadError = msg
                return
            }
            Logger.models.info("SHA-256 verified for \(model.name)")
        }

        // Success
        cleanup(model)
        model.isDownloaded = true
        model.downloadProgress = nil
        model.lastDownloadError = nil
        urlIndices.removeValue(forKey: model.fileName)
        Logger.models.info("Download complete: \(model.name) -> \(model.filePath.path)")

        // Notify the pipeline to load the newly downloaded model
        let notificationName: Notification.Name = model.type == .llm
            ? .llmModelDownloaded
            : .whisperModelDownloaded
        NotificationCenter.default.post(
            name: notificationName,
            object: nil,
            userInfo: ["fileName": model.fileName]
        )
    }

    /// Tries the next mirror URL. Returns true if a retry was started.
    private func tryNextMirror(model: ModelInfo, error: String) -> Bool {
        let currentIndex = urlIndices[model.fileName] ?? 0
        let nextIndex = currentIndex + 1
        let urls = allURLs(for: model)

        guard nextIndex < urls.count else {
            urlIndices.removeValue(forKey: model.fileName)
            return false
        }

        Logger.models.info("Trying mirror \(nextIndex + 1)/\(urls.count) for \(model.name) after: \(error)")
        // cleanup was already called, so we can start fresh
        startDownload(model, urlIndex: nextIndex)
        return true
    }

    private func cleanup(_ model: ModelInfo) {
        activeDownloads.remove(model.fileName)
        observations[model.fileName]?.invalidate()
        observations.removeValue(forKey: model.fileName)
        tasks.removeValue(forKey: model.fileName)
    }
}
