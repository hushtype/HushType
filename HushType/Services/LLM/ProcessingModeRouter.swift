import Foundation
import os

/// Routes transcription through the correct processing pipeline.
@Observable
final class ProcessingModeRouter {
    private let llmService: LLMService

    init(llmService: LLMService) {
        self.llmService = llmService
    }

    /// Process transcription based on the specified mode.
    /// - Parameters:
    ///   - text: Raw transcription text from whisper.
    ///   - mode: The processing mode to apply.
    ///   - template: Optional PromptTemplate for prompt/custom modes.
    ///   - detectedLanguage: Language detected by whisper (passed to PromptTemplateEngine).
    ///   - variables: Variable values for template rendering.
    /// - Returns: Processed text (or raw text if mode is .raw or LLM fails).
    func process(
        text: String,
        mode: ProcessingMode,
        template: PromptTemplate? = nil,
        detectedLanguage: String? = nil,
        variables: [String: String] = [:]
    ) async throws -> String {
        // If mode doesn't require LLM, return raw
        guard mode.requiresLLM else {
            return text
        }

        // Get the appropriate system prompt and user prompt based on mode
        let (systemPrompt, userPrompt) = resolvePrompts(
            text: text,
            mode: mode,
            template: template,
            detectedLanguage: detectedLanguage,
            variables: variables
        )

        let maxTokens = maxTokensForMode(mode, inputLength: text.count)

        return try await llmService.process(
            text: text,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            maxTokens: maxTokens
        )
    }

    /// Resolve system and user prompts for a given mode.
    private func resolvePrompts(
        text: String,
        mode: ProcessingMode,
        template: PromptTemplate?,
        detectedLanguage: String?,
        variables: [String: String]
    ) -> (systemPrompt: String, userPrompt: String) {
        // If a template is provided, use PromptTemplateEngine for full variable substitution
        // (built-in vars: app_name, app_bundle_id, language, timestamp, date, time)
        if let template = template {
            return PromptTemplateEngine.render(
                template: template,
                transcription: text,
                detectedLanguage: detectedLanguage,
                userVariables: variables
            )
        }

        // Otherwise use built-in defaults per mode
        switch mode {
        case .raw:
            return ("", text)
        case .clean:
            return (cleanSystemPrompt, text)
        case .structure:
            return (structureSystemPrompt, text)
        case .code:
            return (codeSystemPrompt, text)
        case .prompt, .custom:
            // No template provided — fall back to clean
            Logger.llm.warning("No template provided for \(mode.rawValue) mode, falling back to clean")
            return (cleanSystemPrompt, text)
        }
    }

    // MARK: - Token Limits

    /// Estimate appropriate max tokens based on mode and input length.
    private func maxTokensForMode(_ mode: ProcessingMode, inputLength: Int) -> Int {
        // Rough estimate: 1 token ≈ 4 chars
        let estimatedInputTokens = max(inputLength / 4, 32)

        switch mode {
        case .raw:
            return estimatedInputTokens
        case .clean:
            // Clean output ≈ same length as input
            return min(estimatedInputTokens * 2, 256)
        case .structure:
            // Structure adds headings/bullets — allow more
            return min(estimatedInputTokens * 3, 512)
        case .code:
            // Code can expand significantly from spoken instructions
            return min(estimatedInputTokens * 4, 1024)
        case .prompt, .custom:
            return 512
        }
    }

    // MARK: - Built-in System Prompts

    private var cleanSystemPrompt: String {
        """
        You are a text editor. Clean up the following dictated text. \
        Fix punctuation, capitalization, and remove filler words \
        (um, uh, like, you know). Preserve the speaker's original \
        meaning and tone. Do not add or change content. Output only \
        the cleaned text.
        """
    }

    private var structureSystemPrompt: String {
        """
        You are a note-taking assistant. Organize the following \
        dictated text into well-structured notes with headings, \
        bullet points, and paragraphs as appropriate. Preserve all \
        information. Output only the structured text.
        """
    }

    private var codeSystemPrompt: String {
        """
        You are a code transcription assistant. Convert the following \
        spoken programming instructions into valid source code. Interpret \
        spoken syntax naturally (e.g., "open paren" → "(", "new line" → \
        line break). Output only the code, no explanations.
        """
    }
}
