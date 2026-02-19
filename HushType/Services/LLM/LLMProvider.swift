import Foundation

// MARK: - LLM Provider Protocol

/// Protocol abstracting LLM backends for swappable text generation.
/// Conforming types: `LlamaCppProvider` (local), `OllamaProvider` (HTTP).
protocol LLMProvider: Sendable {
    /// Load a model for inference.
    /// - Parameter path: Path to the model file (local) or model name (remote).
    func loadModel(at path: String) async throws

    /// Unload the current model and free resources.
    func unloadModel() async

    /// Generate text from a system prompt and user prompt.
    /// - Parameters:
    ///   - systemPrompt: The system instruction for the LLM.
    ///   - userPrompt: The user input (typically the transcription with template applied).
    ///   - maxTokens: Maximum number of tokens to generate.
    /// - Returns: The generated text.
    func generate(systemPrompt: String, userPrompt: String, maxTokens: Int) async throws -> String

    /// Whether a model is currently loaded and ready for inference.
    var isModelLoaded: Bool { get }
}
