import Foundation
import SwiftData
import CryptoKit
import os

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
    func computeSHA256(at url: URL) -> String? {
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

}
