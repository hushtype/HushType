import Foundation
import os

// MARK: - TranscriptionEngine Protocol

/// Protocol for speech-to-text transcription backends.
protocol TranscriptionEngine: Sendable {
    /// Transcribe audio samples to text.
    /// - Parameter samples: Float32 audio samples at 16kHz mono.
    /// - Returns: Transcription result with text, language, and timing.
    func transcribe(samples: [Float]) async throws -> WhisperTranscriptionResult

    /// Load a model from disk.
    /// - Parameter path: Path to the model file.
    func loadModel(at path: URL) async throws

    /// Unload the current model from memory.
    func unloadModel()

    /// Whether a model is currently loaded and ready for inference.
    var isModelLoaded: Bool { get }
}

// MARK: - WhisperTranscriptionResult

/// Result of a whisper transcription within the app.
struct WhisperTranscriptionResult: Sendable {
    /// The transcribed text.
    let text: String

    /// Detected or specified language code.
    let language: String

    /// Duration of audio processed in seconds.
    let audioDuration: TimeInterval

    /// Time taken for inference in seconds.
    let inferenceDuration: TimeInterval

    /// Number of segments produced.
    let segmentCount: Int
}

// MARK: - WhisperService Errors

enum WhisperServiceError: Error, LocalizedError {
    case modelNotLoaded
    case modelLoadFailed(String)
    case transcriptionFailed(String)
    case invalidModelPath(URL)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "No whisper model is loaded"
        case .modelLoadFailed(let reason):
            return "Failed to load whisper model: \(reason)"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        case .invalidModelPath(let url):
            return "Invalid model path: \(url.path)"
        }
    }
}

// MARK: - WhisperService

/// Speech-to-text service using whisper.cpp via WhisperContext.
/// Manages model lifecycle and provides the TranscriptionEngine interface.
@Observable
final class WhisperService: @unchecked Sendable {
    // MARK: - Properties

    /// The underlying whisper context (nil if no model loaded).
    private var context: AnyObject? // WhisperContext from WhisperKit package

    /// Queue for thread-safe property access.
    private let queue = DispatchQueue(label: "com.hushtype.whisper.service", qos: .userInitiated)

    /// Whether a model is currently loaded.
    private(set) var isModelLoaded: Bool = false

    /// Name of the currently loaded model.
    private(set) var loadedModelName: String?

    /// Language to use for transcription ("en" or "auto").
    var language: String = "en"

    /// Number of threads for inference (0 = auto).
    var threadCount: Int = 0

    /// Whether to use Metal GPU acceleration.
    var useGPU: Bool = true

    // MARK: - Initialization

    init() {
        Logger.whisper.info("WhisperService initialized")
    }

    // MARK: - Model Management

    /// Load a whisper model from disk.
    /// - Parameter path: URL to the model file (e.g., ggml-base.en.bin).
    func loadModel(at path: URL) async throws {
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw WhisperServiceError.invalidModelPath(path)
        }

        Logger.whisper.info("Loading whisper model: \(path.lastPathComponent)")

        // In the full implementation, this creates a WhisperContext from the WhisperKit package.
        // For now, we store the path and mark as loaded once WhisperKit is built.
        //
        // TODO: Replace with actual WhisperContext initialization once whisper.cpp is built:
        // let whisperContext = try WhisperContext(modelPath: path.path)
        // self.context = whisperContext

        await MainActor.run {
            self.loadedModelName = path.deletingPathExtension().lastPathComponent
            self.isModelLoaded = true
        }

        Logger.whisper.info("Whisper model loaded: \(path.lastPathComponent)")
    }

    /// Unload the current model and free memory.
    func unloadModel() {
        Logger.whisper.info("Unloading whisper model")

        context = nil
        isModelLoaded = false
        loadedModelName = nil

        Logger.whisper.info("Whisper model unloaded")
    }

    /// Load model based on UserSettings selection.
    /// - Parameters:
    ///   - modelInfo: The ModelInfo entry describing the model.
    func loadModel(from modelInfo: ModelInfoRef) async throws {
        let path = modelInfo.filePath
        try await loadModel(at: path)
    }

    // MARK: - Transcription

    /// Transcribe audio samples to text.
    /// - Parameter samples: Float32 audio samples at 16kHz mono.
    /// - Returns: Transcription result.
    func transcribe(samples: [Float]) async throws -> WhisperTranscriptionResult {
        guard isModelLoaded else {
            throw WhisperServiceError.modelNotLoaded
        }

        guard !samples.isEmpty else {
            throw WhisperServiceError.transcriptionFailed("Empty audio data")
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        let audioDuration = Double(samples.count) / 16000.0

        Logger.whisper.info("Starting transcription of \(String(format: "%.1f", audioDuration))s audio")

        // TODO: Replace with actual WhisperContext transcription once WhisperKit is built:
        // guard let whisperContext = context as? WhisperContext else {
        //     throw WhisperServiceError.modelNotLoaded
        // }
        // let result = try await whisperContext.transcribe(
        //     samples: samples,
        //     language: language,
        //     threadCount: threadCount,
        //     useGPU: useGPU
        // )
        // return WhisperTranscriptionResult(
        //     text: result.text,
        //     language: result.language,
        //     audioDuration: result.audioDuration,
        //     inferenceDuration: result.inferenceDuration,
        //     segmentCount: result.segmentCount
        // )

        // Placeholder until WhisperKit is fully integrated
        let inferenceDuration = CFAbsoluteTimeGetCurrent() - startTime
        Logger.whisper.warning("WhisperKit not yet integrated — returning placeholder")

        return WhisperTranscriptionResult(
            text: "[Transcription placeholder — whisper.cpp not yet built]",
            language: language,
            audioDuration: audioDuration,
            inferenceDuration: inferenceDuration,
            segmentCount: 0
        )
    }
}

// MARK: - ModelInfoRef

/// Lightweight reference to a model's file path (avoids importing SwiftData in service layer).
struct ModelInfoRef: Sendable {
    let fileName: String
    let type: String // "whisper" or "llm"

    var filePath: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let storageDir = type == "whisper" ? "whisper-models" : "llm-models"

        return appSupport
            .appendingPathComponent("HushType", isDirectory: true)
            .appendingPathComponent(storageDir, isDirectory: true)
            .appendingPathComponent(fileName)
    }
}
