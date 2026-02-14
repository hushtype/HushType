import Foundation
import SwiftData

@Model
final class PromptTemplate {
    // MARK: - Identity

    @Attribute(.unique)
    var id: UUID

    // MARK: - Template Definition

    /// Human-readable name for this template (e.g., "Email Draft", "Meeting Notes").
    var name: String

    /// The processing mode this template is associated with.
    var mode: ProcessingMode

    /// System prompt sent to the LLM to define its role and behavior.
    ///
    /// Example: "You are a professional editor. Clean up the following dictated
    /// text while preserving the speaker's intent and tone."
    var systemPrompt: String

    /// User prompt template with variable placeholders.
    ///
    /// Variables are enclosed in double braces: `{{variable_name}}`.
    /// The `{{transcription}}` variable is always available and contains
    /// the raw whisper output.
    ///
    /// Example: "Rewrite this as a {{tone}} email:\n\n{{transcription}}"
    var userPromptTemplate: String

    /// List of variable names used in `userPromptTemplate` (excluding
    /// the built-in `transcription` variable).
    var variables: [String]

    // MARK: - Metadata

    /// Whether this template ships with the app and cannot be deleted.
    var isBuiltIn: Bool

    /// Whether this is the default template for its associated mode.
    var isDefault: Bool

    /// When this template was created.
    var createdAt: Date

    /// When this template was last modified.
    var updatedAt: Date

    // MARK: - Initializer

    init(
        id: UUID = UUID(),
        name: String,
        mode: ProcessingMode,
        systemPrompt: String,
        userPromptTemplate: String,
        variables: [String] = [],
        isBuiltIn: Bool = false,
        isDefault: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.systemPrompt = systemPrompt
        self.userPromptTemplate = userPromptTemplate
        self.variables = variables
        self.isBuiltIn = isBuiltIn
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Template Rendering

    /// Renders the user prompt by substituting variables.
    ///
    /// - Parameters:
    ///   - transcription: The raw transcribed text from whisper.cpp.
    ///   - values: Dictionary mapping variable names to their values.
    /// - Returns: The fully rendered prompt string.
    func render(
        transcription: String,
        values: [String: String] = [:]
    ) -> String {
        var result = userPromptTemplate
        result = result.replacingOccurrences(
            of: "{{transcription}}",
            with: transcription
        )
        for (key, value) in values {
            result = result.replacingOccurrences(
                of: "{{\(key)}}",
                with: value
            )
        }
        return result
    }
}

// MARK: - Built-in Templates

extension PromptTemplate {
    static let builtInTemplates: [PromptTemplate] = [
        PromptTemplate(
            name: "Clean Transcript",
            mode: .clean,
            systemPrompt: """
                You are a text editor. Clean up the following dictated text. \
                Fix punctuation, capitalization, and remove filler words \
                (um, uh, like, you know). Preserve the speaker's original \
                meaning and tone. Do not add or change content.
                """,
            userPromptTemplate: "{{transcription}}",
            isBuiltIn: true,
            isDefault: true
        ),
        PromptTemplate(
            name: "Structured Notes",
            mode: .structure,
            systemPrompt: """
                You are a note-taking assistant. Organize the following \
                dictated text into well-structured notes with headings, \
                bullet points, and paragraphs as appropriate. Preserve \
                all information.
                """,
            userPromptTemplate: "{{transcription}}",
            isBuiltIn: true,
            isDefault: true
        ),
        PromptTemplate(
            name: "Code Dictation",
            mode: .code,
            systemPrompt: """
                You are a code transcription assistant. Convert the \
                following spoken programming instructions into valid \
                source code. Interpret spoken syntax naturally \
                (e.g., "open paren" → "(", "new line" → line break). \
                Output only the code, no explanations.
                """,
            userPromptTemplate: """
                Language: {{language}}

                {{transcription}}
                """,
            variables: ["language"],
            isBuiltIn: true,
            isDefault: true
        ),
        PromptTemplate(
            name: "Email Draft",
            mode: .prompt,
            systemPrompt: """
                You are a professional email writer. Convert the following \
                dictated thoughts into a well-formatted email. Use a \
                {{tone}} tone. Include a subject line.
                """,
            userPromptTemplate: """
                Tone: {{tone}}
                Recipient: {{recipient}}

                {{transcription}}
                """,
            variables: ["tone", "recipient"],
            isBuiltIn: true,
            isDefault: true
        ),
    ]
}
