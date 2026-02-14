import Foundation
import SwiftData

@Model
final class ModelInfo {
    // MARK: - Identity

    @Attribute(.unique)
    var id: UUID

    // MARK: - Model Metadata

    /// Human-readable model name (e.g., "Whisper Base English", "Llama 3.2 1B").
    var name: String

    /// Whether this is a whisper STT model or an LLM.
    var type: ModelType

    /// The filename on disk (e.g., "ggml-base.en.bin", "llama-3.2-1b.Q4_K_M.gguf").
    @Attribute(.unique)
    var fileName: String

    /// Size of the model file in bytes.
    var fileSize: Int64

    // MARK: - Download State

    /// URL to download this model from. Nil for manually imported models.
    var downloadURL: URL?

    /// Whether the model file exists on disk and is ready for inference.
    var isDownloaded: Bool

    /// Whether this is the default model for its type.
    var isDefault: Bool

    /// Current download progress (0.0 to 1.0). Nil if not downloading.
    var downloadProgress: Double?

    // MARK: - Usage Tracking

    /// When this model was last used for inference.
    var lastUsed: Date?

    // MARK: - Initializer

    init(
        id: UUID = UUID(),
        name: String,
        type: ModelType,
        fileName: String,
        fileSize: Int64,
        downloadURL: URL? = nil,
        isDownloaded: Bool = false,
        isDefault: Bool = false,
        downloadProgress: Double? = nil,
        lastUsed: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.fileName = fileName
        self.fileSize = fileSize
        self.downloadURL = downloadURL
        self.isDownloaded = isDownloaded
        self.isDefault = isDefault
        self.downloadProgress = downloadProgress
        self.lastUsed = lastUsed
    }

    // MARK: - Computed Properties

    /// Human-readable file size string (e.g., "142 MB", "4.7 GB").
    var formattedFileSize: String {
        ByteCountFormatter.string(
            fromByteCount: fileSize,
            countStyle: .file
        )
    }

    /// The full path to the model file on disk.
    var filePath: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        return appSupport
            .appendingPathComponent("HushType", isDirectory: true)
            .appendingPathComponent(type.storageDirectory, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    /// Verifies the model file actually exists at the expected path.
    var fileExistsOnDisk: Bool {
        FileManager.default.fileExists(atPath: filePath.path)
    }
}

// MARK: - Pre-seeded Model Registry

extension ModelInfo {
    static let defaultModels: [ModelInfo] = [
        ModelInfo(
            name: "Whisper Tiny (English)",
            type: .whisper,
            fileName: "ggml-tiny.en.bin",
            fileSize: 77_691_713,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin"),
            isDefault: false
        ),
        ModelInfo(
            name: "Whisper Base (English)",
            type: .whisper,
            fileName: "ggml-base.en.bin",
            fileSize: 147_951_465,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"),
            isDefault: true
        ),
        ModelInfo(
            name: "Whisper Small (English)",
            type: .whisper,
            fileName: "ggml-small.en.bin",
            fileSize: 487_601_967,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin"),
            isDefault: false
        ),
        ModelInfo(
            name: "Whisper Medium (English)",
            type: .whisper,
            fileName: "ggml-medium.en.bin",
            fileSize: 1_533_774_781,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin"),
            isDefault: false
        ),
        ModelInfo(
            name: "Whisper Large v3 Turbo",
            type: .whisper,
            fileName: "ggml-large-v3-turbo.bin",
            fileSize: 1_622_089_216,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin"),
            isDefault: false
        ),
    ]
}
