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
    ///   - variables: Variable values for template rendering.
    /// - Returns: Processed text (or raw text if mode is .raw or LLM fails).
    func process(
        text: String,
        mode: ProcessingMode,
        template: PromptTemplate? = nil,
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
            variables: variables
        )

        return try await llmService.process(
            text: text,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt
        )
    }

    /// Resolve system and user prompts for a given mode.
    private func resolvePrompts(
        text: String,
        mode: ProcessingMode,
        template: PromptTemplate?,
        variables: [String: String]
    ) -> (systemPrompt: String, userPrompt: String) {
        // If a template is provided, use it
        if let template = template {
            return (template.systemPrompt, template.render(transcription: text, values: variables))
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
