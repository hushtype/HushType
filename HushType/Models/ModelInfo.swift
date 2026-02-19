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

    // MARK: - Registry & Integrity

    /// SHA-256 checksum for download integrity validation. Nil for manually imported models.
    var sha256: String?

    /// Alternate download URLs (mirrors/fallbacks). Empty for locally imported models.
    var mirrorURLs: [String] = []

    /// Most recent error message from a failed download attempt. Nil when no error.
    var lastDownloadError: String?

    /// Whether this model is deprecated in the remote registry.
    var isDeprecated: Bool = false

    /// Optional notes from the registry (e.g., "Recommended for daily use").
    var registryNotes: String?

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
        sha256: String? = nil,
        mirrorURLs: [String] = [],
        lastDownloadError: String? = nil,
        isDeprecated: Bool = false,
        registryNotes: String? = nil
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
        self.sha256 = sha256
        self.mirrorURLs = mirrorURLs
        self.lastDownloadError = lastDownloadError
        self.isDeprecated = isDeprecated
        self.registryNotes = registryNotes
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
            isDefault: false,
            sha256: "921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f"
        ),
        ModelInfo(
            name: "Whisper Base (English)",
            type: .whisper,
            fileName: "ggml-base.en.bin",
            fileSize: 147_951_465,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"),
            isDefault: true,
            sha256: "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002"
        ),
        ModelInfo(
            name: "Whisper Small (English)",
            type: .whisper,
            fileName: "ggml-small.en.bin",
            fileSize: 487_601_967,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin"),
            isDefault: false,
            sha256: "c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d"
        ),
        ModelInfo(
            name: "Whisper Medium (English)",
            type: .whisper,
            fileName: "ggml-medium.en.bin",
            fileSize: 1_533_774_781,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin"),
            isDefault: false,
            sha256: "cc37e93478338ec7700281a7ac30a10128929eb8f427dda2e865faa8f6da4356"
        ),
        ModelInfo(
            name: "Whisper Large v3 Turbo",
            type: .whisper,
            fileName: "ggml-large-v3-turbo.bin",
            fileSize: 1_622_089_216,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin"),
            isDefault: false,
            sha256: "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69"
        ),

        // MARK: LLM Models

        ModelInfo(
            name: "Qwen 2.5 0.5B Instruct (Q4_K_M)",
            type: .llm,
            fileName: "qwen2.5-0.5b-instruct-q4_k_m.gguf",
            fileSize: 491_000_000,
            downloadURL: URL(string: "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf"),
            isDefault: true,
            sha256: "74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db"
        ),
        ModelInfo(
            name: "Qwen 2.5 1.5B Instruct (Q4_K_M)",
            type: .llm,
            fileName: "qwen2.5-1.5b-instruct-q4_k_m.gguf",
            fileSize: 1_100_000_000,
            downloadURL: URL(string: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf"),
            isDefault: false,
            sha256: "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e"
        ),
        ModelInfo(
            name: "Llama 3.2 1B Instruct (Q4_K_M)",
            type: .llm,
            fileName: "Llama-3.2-1B-Instruct-Q4_K_M.gguf",
            fileSize: 808_000_000,
            downloadURL: URL(string: "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf"),
            isDefault: false,
            sha256: "6f85a640a97cf2bf5b8e764087b1e83da0fdb51d7c9fab7d0fece9385611df83"
        ),
        ModelInfo(
            name: "Gemma 3 1B Instruct (Q4_K_M)",
            type: .llm,
            fileName: "gemma-3-1b-it-Q4_K_M.gguf",
            fileSize: 806_000_000,
            downloadURL: URL(string: "https://huggingface.co/bartowski/google_gemma-3-1b-it-GGUF/resolve/main/gemma-3-1b-it-Q4_K_M.gguf"),
            isDefault: false,
            sha256: "f36668ddf22403a332f978057d527cf285b01468bc3431b04094a7bafa6aba59"
        ),
        ModelInfo(
            name: "Phi-4 Mini Instruct (Q4_K_M)",
            type: .llm,
            fileName: "microsoft_Phi-4-mini-instruct-Q4_K_M.gguf",
            fileSize: 2_490_000_000,
            downloadURL: URL(string: "https://huggingface.co/bartowski/microsoft_Phi-4-mini-instruct-GGUF/resolve/main/microsoft_Phi-4-mini-instruct-Q4_K_M.gguf"),
            isDefault: false,
            sha256: "01999f17c39cc3074afae5e9c539bc82d45f2dd7faa3917c66cbef76fce8c0c2"
        ),
    ]
}
