import Foundation
import os

// MARK: - Generation Result

/// Result of a llama.cpp text generation.
struct GenerationResult: Sendable {
    /// The generated text.
    let text: String

    /// Number of prompt tokens processed.
    let promptTokenCount: Int

    /// Number of tokens generated.
    let generatedTokenCount: Int

    /// Time taken for generation in seconds.
    let generationDuration: TimeInterval
}

// MARK: - LlamaContext Errors

enum LlamaContextError: Error, LocalizedError {
    case modelLoadFailed(String)
    case contextCreationFailed
    case contextNotInitialized
    case tokenizationFailed
    case decodeFailed
    case generationFailed(String)
    case emptyPrompt

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let path):
            return "Failed to load llama model at: \(path)"
        case .contextCreationFailed:
            return "Failed to create llama context from model"
        case .contextNotInitialized:
            return "Llama context is not initialized"
        case .tokenizationFailed:
            return "Failed to tokenize input text"
        case .decodeFailed:
            return "Llama decode failed during generation"
        case .generationFailed(let reason):
            return "Llama generation failed: \(reason)"
        case .emptyPrompt:
            return "Cannot generate from an empty prompt"
        }
    }
}

// MARK: - LlamaContext

/// Swift wrapper around llama.cpp C context.
/// Thread-safe via dedicated dispatch queue. All C calls happen off the main thread.
final class LlamaContext: @unchecked Sendable {
    // MARK: - Properties

    /// Opaque pointer to the llama_model C struct.
    private var model: OpaquePointer?

    /// Opaque pointer to the llama_context C struct.
    private var context: OpaquePointer?

    /// Sampler chain for token sampling.
    private var sampler: UnsafeMutablePointer<llama_sampler>?

    /// Dedicated queue for all llama C API calls (never call on main thread).
    private let queue = DispatchQueue(
        label: "com.hushtype.llama.context",
        qos: .userInitiated
    )

    /// Whether a model is currently loaded.
    var isLoaded: Bool {
        model != nil && context != nil
    }

    // MARK: - Lifecycle

    /// Initialize with a model file path.
    /// - Parameters:
    ///   - modelPath: Path to the GGUF model file.
    ///   - contextSize: Context window size (0 = model default).
    ///   - gpuLayers: Number of layers to offload to GPU (99 = all).
    /// - Throws: `LlamaContextError` if model or context creation fails.
    init(modelPath: String, contextSize: UInt32 = 0, gpuLayers: Int32 = 99) throws {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw LlamaContextError.modelLoadFailed(modelPath)
        }

        // Initialize backend (safe to call multiple times)
        llama_backend_init()

        // Load model
        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = gpuLayers

        guard let loadedModel = llama_model_load_from_file(modelPath, modelParams) else {
            throw LlamaContextError.modelLoadFailed(modelPath)
        }
        self.model = loadedModel

        // Create context
        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = contextSize  // 0 = use model default
        ctxParams.n_batch = 512
        ctxParams.n_threads = Int32(ProcessInfo.processInfo.activeProcessorCount)
        ctxParams.n_threads_batch = Int32(ProcessInfo.processInfo.activeProcessorCount)

        guard let ctx = llama_init_from_model(loadedModel, ctxParams) else {
            llama_model_free(loadedModel)
            self.model = nil
            throw LlamaContextError.contextCreationFailed
        }
        self.context = ctx

        // Create sampler chain (greedy by default)
        let chainParams = llama_sampler_chain_default_params()
        let chain = llama_sampler_chain_init(chainParams)
        llama_sampler_chain_add(chain, llama_sampler_init_greedy())
        self.sampler = chain

        Logger.llm.info("Llama model loaded: \(modelPath), ctx=\(llama_n_ctx(ctx)), gpu_layers=\(gpuLayers)")
    }

    deinit {
        // Synchronize on the dedicated queue to avoid freeing C pointers
        // while an in-flight generation closure is still using them.
        queue.sync {
            if let smpl = sampler {
                llama_sampler_free(smpl)
                sampler = nil
            }
            if let ctx = context {
                llama_free(ctx)
                context = nil
            }
            if let mdl = model {
                llama_model_free(mdl)
                model = nil
            }
            llama_backend_free()
        }
        Logger.llm.info("Llama context freed")
    }

    // MARK: - Generation

    /// Generate text from a prompt.
    /// - Parameters:
    ///   - prompt: The input prompt text.
    ///   - maxTokens: Maximum number of tokens to generate.
    ///   - stopSequences: Optional stop sequences to terminate generation early.
    /// - Returns: GenerationResult with the generated text and stats.
    /// - Throws: LlamaContextError if generation fails.
    func generate(
        prompt: String,
        maxTokens: Int = 512,
        stopSequences: [String] = []
    ) async throws -> GenerationResult {
        guard !prompt.isEmpty else {
            throw LlamaContextError.emptyPrompt
        }

        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard let mdl = self.model,
                      let ctx = self.context,
                      let smpl = self.sampler else {
                    continuation.resume(throwing: LlamaContextError.contextNotInitialized)
                    return
                }

                do {
                    let result = try self._generate(
                        model: mdl,
                        ctx: ctx,
                        sampler: smpl,
                        prompt: prompt,
                        maxTokens: maxTokens,
                        stopSequences: stopSequences
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Internal generation (must be called on queue).
    private func _generate(
        model: OpaquePointer,
        ctx: OpaquePointer,
        sampler: UnsafeMutablePointer<llama_sampler>,
        prompt: String,
        maxTokens: Int,
        stopSequences: [String]
    ) throws -> GenerationResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        guard let vocab = llama_model_get_vocab(model) else {
            throw LlamaContextError.generationFailed("Failed to get vocab from model")
        }

        // Clear KV cache for fresh generation
        let memory = llama_get_memory(ctx)
        if let mem = memory {
            llama_memory_clear(mem, true)
        }

        // Tokenize prompt
        let promptTokens = try tokenize(vocab: vocab, text: prompt, addBOS: true)
        let promptCount = promptTokens.count

        guard promptCount > 0 else {
            throw LlamaContextError.tokenizationFailed
        }

        let contextSize = Int(llama_n_ctx(ctx))
        guard promptCount < contextSize else {
            throw LlamaContextError.generationFailed(
                "Prompt (\(promptCount) tokens) exceeds context size (\(contextSize))"
            )
        }

        // Create batch and decode prompt
        var batch = llama_batch_init(Int32(max(promptCount, 1)), 0, 1)
        defer { llama_batch_free(batch) }

        // Fill batch with prompt tokens
        for (i, token) in promptTokens.enumerated() {
            let isLast = (i == promptCount - 1)
            addTokenToBatch(&batch, token: token, pos: Int32(i), seqID: 0, logits: isLast)
        }

        var decodeResult = llama_decode(ctx, batch)
        guard decodeResult == 0 else {
            throw LlamaContextError.decodeFailed
        }

        // Generation loop
        let eosToken = llama_vocab_eos(vocab)
        var generatedTokens: [llama_token] = []
        var generatedText = ""
        var currentPos = Int32(promptCount)

        for _ in 0..<maxTokens {
            // Sample next token
            let newToken = llama_sampler_sample(sampler, ctx, -1)

            // Check for EOS
            if newToken == eosToken {
                break
            }

            // Detokenize the new token
            let piece = tokenToPiece(vocab: vocab, token: newToken)
            generatedTokens.append(newToken)
            generatedText += piece

            // Check stop sequences
            if !stopSequences.isEmpty {
                let shouldStop = stopSequences.contains { generatedText.hasSuffix($0) }
                if shouldStop {
                    // Remove the stop sequence from output
                    for stop in stopSequences where generatedText.hasSuffix(stop) {
                        generatedText = String(generatedText.dropLast(stop.count))
                        break
                    }
                    break
                }
            }

            // Prepare batch for next token
            batch.n_tokens = 0
            addTokenToBatch(&batch, token: newToken, pos: currentPos, seqID: 0, logits: true)
            currentPos += 1

            decodeResult = llama_decode(ctx, batch)
            guard decodeResult == 0 else {
                throw LlamaContextError.decodeFailed
            }
        }

        let generationDuration = CFAbsoluteTimeGetCurrent() - startTime

        Logger.llm.info(
            "Generated \(generatedTokens.count) tokens from \(promptCount) prompt tokens in \(String(format: "%.2f", generationDuration))s"
        )

        return GenerationResult(
            text: generatedText.trimmingCharacters(in: .whitespacesAndNewlines),
            promptTokenCount: promptCount,
            generatedTokenCount: generatedTokens.count,
            generationDuration: generationDuration
        )
    }

    // MARK: - Tokenization

    /// Tokenize a string into llama tokens.
    private func tokenize(vocab: OpaquePointer, text: String, addBOS: Bool) throws -> [llama_token] {
        let utf8Count = text.utf8.count
        // Allocate buffer larger than input (tokens can expand for special tokens)
        let maxTokens = utf8Count + (addBOS ? 1 : 0) + 16
        var tokens = [llama_token](repeating: 0, count: maxTokens)

        let tokenCount = text.withCString { textPtr in
            llama_tokenize(vocab, textPtr, Int32(utf8Count), &tokens, Int32(maxTokens), addBOS, true)
        }

        guard tokenCount >= 0 else {
            throw LlamaContextError.tokenizationFailed
        }

        return Array(tokens.prefix(Int(tokenCount)))
    }

    /// Convert a token back to a string piece.
    private func tokenToPiece(vocab: OpaquePointer, token: llama_token) -> String {
        let bufSize = 128
        var buf = [CChar](repeating: 0, count: bufSize)
        let len = llama_token_to_piece(vocab, token, &buf, Int32(bufSize), 0, true)

        if len > 0 {
            return String(cString: buf)
        } else if len < 0 {
            // Buffer too small, retry with correct size
            let needed = Int(-len)
            var bigBuf = [CChar](repeating: 0, count: needed + 1)
            let retryLen = llama_token_to_piece(vocab, token, &bigBuf, Int32(needed + 1), 0, true)
            if retryLen > 0 {
                return String(cString: bigBuf)
            }
        }
        return ""
    }

    // MARK: - Batch Helpers

    /// Add a token to a batch.
    private func addTokenToBatch(
        _ batch: inout llama_batch,
        token: llama_token,
        pos: Int32,
        seqID: llama_seq_id,
        logits: Bool
    ) {
        let idx = Int(batch.n_tokens)
        batch.token[idx] = token
        batch.pos[idx] = pos
        batch.n_seq_id[idx] = 1
        if let seqIdPtr = batch.seq_id?[idx] {
            seqIdPtr[0] = seqID
        }
        batch.logits[idx] = logits ? 1 : 0
        batch.n_tokens += 1
    }

    /// Unload the model and free resources.
    func unload() {
        queue.sync {
            if let smpl = sampler {
                llama_sampler_free(smpl)
                sampler = nil
            }
            if let ctx = context {
                llama_free(ctx)
                context = nil
            }
            if let mdl = model {
                llama_model_free(mdl)
                model = nil
            }
            Logger.llm.info("Llama model unloaded")
        }
    }
}
