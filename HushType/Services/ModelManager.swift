import Foundation
import SwiftData
import CryptoKit
import os
import AppKit
import UniformTypeIdentifiers

/// Manages model lifecycle — download, verification, storage, and import.
@Observable
final class ModelManager {
    let downloader: ModelDownloader

    init(downloader: ModelDownloader = ModelDownloader()) {
        self.downloader = downloader
    }

    // MARK: - SHA-256 Verification

    /// Verify a downloaded model's SHA-256 hash.
    func verifySHA256(for model: ModelInfo, expectedHash: String) -> Bool {
        guard model.fileExistsOnDisk else { return false }
        guard let hash = computeSHA256(at: model.filePath) else { return false }
        let matches = hash.lowercased() == expectedHash.lowercased()
        if !matches {
            Logger.models.warning("SHA-256 mismatch for \(model.name): expected \(expectedHash), got \(hash)")
        }
        return matches
    }

    /// Compute SHA-256 hash of a file.
    private func computeSHA256(at url: URL) -> String? {
        guard let stream = InputStream(url: url) else { return nil }
        stream.open()
        defer { stream.close() }

        var hasher = SHA256()
        let bufferSize = 1024 * 1024 // 1MB chunks
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        while stream.hasBytesAvailable {
            let bytesRead = stream.read(&buffer, maxLength: bufferSize)
            if bytesRead > 0 {
                hasher.update(data: buffer[0..<bytesRead])
            } else {
                break
            }
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Storage Management

    /// Get total disk usage for all downloaded models.
    func totalDiskUsage(models: [ModelInfo]) -> Int64 {
        models.filter { $0.isDownloaded && $0.fileExistsOnDisk }
            .reduce(0) { $0 + $1.fileSize }
    }

    /// Get disk usage by model type.
    func diskUsage(for type: ModelType, models: [ModelInfo]) -> Int64 {
        models.filter { $0.type == type && $0.isDownloaded && $0.fileExistsOnDisk }
            .reduce(0) { $0 + $1.fileSize }
    }

    /// Delete a model's file from disk.
    func deleteModelFile(_ model: ModelInfo) throws {
        guard model.fileExistsOnDisk else { return }
        try FileManager.default.removeItem(at: model.filePath)
        model.isDownloaded = false
        model.downloadProgress = nil
        Logger.models.info("Deleted model file: \(model.name) at \(model.filePath.path)")
    }

    /// Sync model download states with actual files on disk.
    func syncDownloadStates(_ models: [ModelInfo]) {
        for model in models {
            let exists = model.fileExistsOnDisk
            if model.isDownloaded != exists {
                model.isDownloaded = exists
                Logger.models.info("Synced \(model.name): isDownloaded=\(exists)")
            }
        }
    }

    // MARK: - Custom Model Import

    /// Import a GGUF model file via NSOpenPanel.
    /// Returns the created ModelInfo, or nil if user cancelled.
    @MainActor
    func importGGUFModel(type: ModelType, context: ModelContext) -> ModelInfo? {
        let panel = NSOpenPanel()
        panel.title = "Import GGUF Model"
        panel.allowedContentTypes = [.data]  // GGUF files
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.nameFieldStringValue = ""
        panel.message = "Select a GGUF model file to import"

        guard panel.runModal() == .OK, let sourceURL = panel.url else {
            return nil
        }

        // Validate file extension
        let fileName = sourceURL.lastPathComponent
        guard fileName.hasSuffix(".gguf") || fileName.hasSuffix(".bin") else {
            Logger.models.error("Invalid model file format: \(fileName)")
            return nil
        }

        // Get file size
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: sourceURL.path),
              let fileSize = attrs[.size] as? Int64 else {
            Logger.models.error("Cannot read file size: \(fileName)")
            return nil
        }

        // Create ModelInfo
        let modelName = fileName
            .replacingOccurrences(of: ".gguf", with: "")
            .replacingOccurrences(of: ".bin", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized

        let model = ModelInfo(
            name: modelName,
            type: type,
            fileName: fileName,
            fileSize: fileSize
        )

        // Copy file to app's model directory
        let destDir = model.filePath.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: model.filePath.path) {
                try FileManager.default.removeItem(at: model.filePath)
            }
            try FileManager.default.copyItem(at: sourceURL, to: model.filePath)
            model.isDownloaded = true
            context.insert(model)
            Logger.models.info("Imported model: \(modelName) (\(model.formattedFileSize))")
            return model
        } catch {
            Logger.models.error("Failed to import model: \(error.localizedDescription)")
            return nil
        }
    }
}
