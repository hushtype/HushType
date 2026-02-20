import Foundation
import os

// MARK: - Transcription Result

/// Result of a whisper transcription.
struct TranscriptionResult: Sendable {
    /// The transcribed text.
    let text: String

    /// Language detected or specified.
    let language: String

    /// Duration of audio processed in seconds.
    let audioDuration: TimeInterval

    /// Time taken for inference in seconds.
    let inferenceDuration: TimeInterval

    /// Number of segments produced.
    let segmentCount: Int
}

// MARK: - WhisperContext Errors

enum WhisperContextError: Error, LocalizedError {
    case modelLoadFailed(String)
    case transcriptionFailed
    case contextNotInitialized
    case invalidAudioData

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let path):
            return "Failed to load whisper model at: \(path)"
        case .transcriptionFailed:
            return "Whisper transcription failed"
        case .contextNotInitialized:
            return "Whisper context is not initialized"
        case .invalidAudioData:
            return "Invalid audio data provided for transcription"
        }
    }
}

// MARK: - WhisperContext

/// Swift wrapper around whisper.cpp C context.
/// Thread-safe via dedicated dispatch queue. All C calls happen off the main thread.
final class WhisperContext: @unchecked Sendable {
    // MARK: - Properties

    /// Opaque pointer to the whisper_context C struct.
    private var context: OpaquePointer?

    /// Dedicated queue for all whisper C API calls (never call on main thread).
    private let queue = DispatchQueue(
        label: "com.hushtype.whisper.context",
        qos: .userInitiated
    )

    /// Whether a model is currently loaded.
    var isLoaded: Bool {
        context != nil
    }

    // MARK: - Lifecycle

    /// Initialize with a model file path.
    /// - Parameter modelPath: Path to the whisper GGML model file.
    /// - Throws: `WhisperContextError.modelLoadFailed` if the model cannot be loaded.
    init(modelPath: String) throws {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw WhisperContextError.modelLoadFailed(modelPath)
        }

        let params = whisper_context_default_params()
        guard let ctx = whisper_init_from_file_with_params(modelPath, params) else {
            throw WhisperContextError.modelLoadFailed(modelPath)
        }

        self.context = ctx
        Logger.whisper.info("Whisper model loaded: \(modelPath)")
    }

    deinit {
        // Synchronize on the dedicated queue to avoid freeing the C pointer
        // while an in-flight transcription closure is still using it.
        queue.sync {
            if let ctx = context {
                whisper_free(ctx)
                context = nil
            }
        }
        Logger.whisper.info("Whisper context freed")
    }

    // MARK: - Transcription

    /// Transcribe audio samples.
    /// - Parameters:
    ///   - samples: Float32 audio samples at 16kHz mono.
    ///   - language: Language code (e.g., "en") or "auto" for detection.
    ///   - translate: Whether to translate to English.
    ///   - threadCount: Number of threads (0 = auto).
    /// - Returns: Transcription result.
    /// - Throws: WhisperContextError if transcription fails.
    func transcribe(
        samples: [Float],
        language: String = "en",
        translate: Bool = false,
        threadCount: Int = 0
    ) async throws -> TranscriptionResult {
        guard !samples.isEmpty else {
            throw WhisperContextError.invalidAudioData
        }

        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard let ctx = self.context else {
                    continuation.resume(throwing: WhisperContextError.contextNotInitialized)
                    return
                }

                do {
                    let result = try self._transcribe(
                        ctx: ctx,
                        samples: samples,
                        language: language,
                        translate: translate,
                        threadCount: threadCount
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Internal transcription (must be called on queue).
    private func _transcribe(
        ctx: OpaquePointer,
        samples: [Float],
        language: String,
        translate: Bool,
        threadCount: Int
    ) throws -> TranscriptionResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        let audioDuration = Double(samples.count) / 16000.0

        // Configure parameters
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = Int32(threadCount > 0 ? threadCount : ProcessInfo.processInfo.activeProcessorCount)
        params.translate = translate
        params.no_timestamps = true
        params.single_segment = false
        params.print_special = false
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false

        // Set language — keep withCString scope around whisper_full to avoid use-after-free
        let result: Int32 = language.withCString { langPtr in
            params.language = langPtr

            return samples.withUnsafeBufferPointer { bufferPtr in
                guard let baseAddress = bufferPtr.baseAddress else {
                    return -1 // should never happen — samples.isEmpty guard above
                }
                return whisper_full(ctx, params, baseAddress, Int32(samples.count))
            }
        }

        guard result == 0 else {
            Logger.whisper.error("Whisper transcription failed with code: \(result)")
            throw WhisperContextError.transcriptionFailed
        }

        // Extract text from segments
        let segmentCount = Int(whisper_full_n_segments(ctx))
        var fullText = ""

        for i in 0..<segmentCount {
            if let segmentText = whisper_full_get_segment_text(ctx, Int32(i)) {
                fullText += String(cString: segmentText)
            }
        }

        let inferenceDuration = CFAbsoluteTimeGetCurrent() - startTime
        let trimmedText = fullText.trimmingCharacters(in: .whitespacesAndNewlines)

        Logger.whisper.info(
            "Transcribed \(String(format: "%.1f", audioDuration))s audio in \(String(format: "%.2f", inferenceDuration))s (\(segmentCount) segments)"
        )

        // Detect language if auto
        let detectedLanguage: String
        if language == "auto" {
            let langId = whisper_full_lang_id(ctx)
            if let langStr = whisper_lang_str(langId) {
                detectedLanguage = String(cString: langStr)
            } else {
                detectedLanguage = "en"
            }
        } else {
            detectedLanguage = language
        }

        return TranscriptionResult(
            text: trimmedText,
            language: detectedLanguage,
            audioDuration: audioDuration,
            inferenceDuration: inferenceDuration,
            segmentCount: segmentCount
        )
    }

    /// Unload the model and free resources.
    func unload() {
        queue.sync {
            if let ctx = context {
                whisper_free(ctx)
                context = nil
                Logger.whisper.info("Whisper model unloaded")
            }
        }
    }
}
