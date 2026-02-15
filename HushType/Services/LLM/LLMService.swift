import Foundation
import os

// MARK: - LLMService Errors

enum LLMServiceError: Error, LocalizedError {
    case noProviderConfigured
    case modelNotLoaded
    case processingFailed(String)

    var errorDescription: String? {
        switch self {
        case .noProviderConfigured:
            return "No LLM provider is configured"
        case .modelNotLoaded:
            return "No LLM model is loaded"
        case .processingFailed(let reason):
            return "LLM processing failed: \(reason)"
        }
    }
}

// MARK: - LLMService

/// High-level LLM service that wraps an LLMProvider and provides text processing API.
/// Manages provider lifecycle, model loading, and text generation.
@Observable
final class LLMService: @unchecked Sendable {
    // MARK: - Properties

    /// The currently active LLM provider.
    private(set) var activeProvider: (any LLMProvider)?

    /// Whether currently processing/generating text.
    private(set) var isProcessing: Bool = false

    /// Last error message for UI display.
    private(set) var lastError: String?

    // MARK: - Initialization

    init() {
        Logger.llm.info("LLMService initialized")
    }

    // MARK: - Provider Management

    /// Set the active LLM provider.
    /// - Parameter provider: The provider to use for text generation.
    func setProvider(_ provider: any LLMProvider) {
        self.activeProvider = provider
        Logger.llm.info("Active LLM provider set: \(String(describing: type(of: provider)))")
    }

    // MARK: - Model Management

    /// Load a model on the active provider.
    /// - Parameter path: Path to the model file (local) or model name (remote).
    /// - Throws: `LLMServiceError.noProviderConfigured` if no provider is set.
    func loadModel(at path: String) async throws {
        guard let provider = activeProvider else {
            throw LLMServiceError.noProviderConfigured
        }

        Logger.llm.info("Loading LLM model: \(path)")

        do {
            try await provider.loadModel(at: path)
            lastError = nil
            Logger.llm.info("LLM model loaded successfully")
        } catch {
            let errorMessage = error.localizedDescription
            lastError = errorMessage
            Logger.llm.error("Failed to load LLM model: \(errorMessage)")
            throw error
        }
    }

    /// Unload the model on the active provider.
    func unloadModel() async {
        guard let provider = activeProvider else {
            return
        }

        Logger.llm.info("Unloading LLM model")
        await provider.unloadModel()
        Logger.llm.info("LLM model unloaded")
    }

    // MARK: - Text Processing

    /// Process text through the LLM.
    /// - Parameters:
    ///   - text: The input text (transcription).
    ///   - systemPrompt: The system instruction for the LLM.
    ///   - userPrompt: The user prompt with `{{transcription}}` already replaced.
    ///   - maxTokens: Maximum number of tokens to generate (default: 512).
    /// - Returns: The generated/processed text.
    /// - Throws: `LLMServiceError` if no provider is configured or generation fails.
    func process(
        text: String,
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int = 512
    ) async throws -> String {
        guard let provider = activeProvider else {
            throw LLMServiceError.noProviderConfigured
        }

        guard provider.isModelLoaded else {
            throw LLMServiceError.modelNotLoaded
        }

        isProcessing = true
        defer { isProcessing = false }

        Logger.llm.info("Processing text (\(text.count) chars) with LLM")

        do {
            let result = try await provider.generate(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                maxTokens: maxTokens
            )

            lastError = nil
            Logger.llm.info("LLM processing complete: \(result.count) chars generated")
            return result
        } catch {
            let errorMessage = error.localizedDescription
            lastError = errorMessage
            Logger.llm.error("LLM processing failed: \(errorMessage)")
            throw LLMServiceError.processingFailed(errorMessage)
        }
    }

    // MARK: - Status

    /// Whether a model is currently loaded and ready for inference.
    var isModelLoaded: Bool {
        activeProvider?.isModelLoaded ?? false
    }
}
