import Foundation
import os

// MARK: - LlamaCpp Provider Errors

enum LlamaCppProviderError: Error, LocalizedError {
    case modelNotLoaded
    case modelLoadFailed(String)
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "No llama.cpp model is loaded"
        case .modelLoadFailed(let reason):
            return "Failed to load llama.cpp model: \(reason)"
        case .generationFailed(let reason):
            return "llama.cpp generation failed: \(reason)"
        }
    }
}

// MARK: - LlamaCppProvider

/// Local LLM provider using llama.cpp via `LlamaContext`.
/// Uses actor isolation for thread-safe model lifecycle management.
actor LlamaCppProvider: LLMProvider {
    private var context: LlamaContext?
    private var modelPath: String?

    /// GPU layers to offload (99 = all).
    private let gpuLayers: Int32

    /// Context window size (0 = model default).
    private let contextSize: UInt32

    init(gpuLayers: Int32 = 99, contextSize: UInt32 = 2048) {
        self.gpuLayers = gpuLayers
        self.contextSize = contextSize
    }

    var isModelLoaded: Bool {
        context?.isLoaded ?? false
    }

    func loadModel(at path: String) async throws {
        // Unload existing model first
        if context != nil {
            await unloadModel()
        }

        do {
            let ctx = try LlamaContext(
                modelPath: path,
                contextSize: contextSize,
                gpuLayers: gpuLayers
            )
            self.context = ctx
            self.modelPath = path

            Logger.llm.info("LlamaCppProvider: model loaded from \(path)")
        } catch {
            Logger.llm.error("LlamaCppProvider: failed to load model: \(error.localizedDescription)")
            throw LlamaCppProviderError.modelLoadFailed(error.localizedDescription)
        }
    }

    func unloadModel() async {
        context?.unload()
        context = nil
        modelPath = nil
        Logger.llm.info("LlamaCppProvider: model unloaded")
    }

    func generate(systemPrompt: String, userPrompt: String, maxTokens: Int) async throws -> String {
        guard let ctx = context, ctx.isLoaded else {
            throw LlamaCppProviderError.modelNotLoaded
        }

        // Format as a single prompt with system + user
        let fullPrompt = formatPrompt(system: systemPrompt, user: userPrompt)

        do {
            let result = try await ctx.generate(
                prompt: fullPrompt,
                maxTokens: maxTokens,
                stopSequences: Self.defaultStopSequences
            )
            return result.text
        } catch {
            Logger.llm.error("LlamaCppProvider: generation failed: \(error.localizedDescription)")
            throw LlamaCppProviderError.generationFailed(error.localizedDescription)
        }
    }

    // MARK: - Private

    /// Common stop sequences to catch model-specific end tokens.
    private static let defaultStopSequences = [
        "</s>",
        "<|endoftext|>",
        "<|im_end|>",
        "<|end|>",
        "<|eot_id|>",
        "\nHuman:",
        "\nUser:",
    ]

    /// Format system and user prompts into a single prompt string.
    /// Uses ChatML format compatible with Qwen, Llama, Gemma, Phi models.
    private func formatPrompt(system: String, user: String) -> String {
        if system.isEmpty {
            return user
        }
        return """
        <|im_start|>system
        \(system)<|im_end|>
        <|im_start|>user
        \(user)<|im_end|>
        <|im_start|>assistant
        """
    }
}
