import Foundation
import os
import AppKit

/// Engine for rendering prompt templates with variable substitution.
/// Extends PromptTemplate.render() with additional built-in variables.
struct PromptTemplateEngine {
    /// Render a template with all built-in and user variables.
    /// - Parameters:
    ///   - template: The prompt template to render.
    ///   - transcription: Raw transcription text.
    ///   - userVariables: Additional user-defined variable values.
    /// - Returns: Tuple of (renderedSystemPrompt, renderedUserPrompt).
    static func render(
        template: PromptTemplate,
        transcription: String,
        userVariables: [String: String] = [:]
    ) -> (systemPrompt: String, userPrompt: String) {
        // Merge built-in variables with user variables
        var allVariables = builtInVariables()
        allVariables.merge(userVariables) { _, user in user }

        // Render user prompt template
        let renderedUserPrompt = template.render(
            transcription: transcription,
            values: allVariables
        )

        // Also substitute variables in system prompt
        var renderedSystemPrompt = template.systemPrompt
        for (key, value) in allVariables {
            renderedSystemPrompt = renderedSystemPrompt.replacingOccurrences(
                of: "{{\(key)}}",
                with: value
            )
        }
        renderedSystemPrompt = renderedSystemPrompt.replacingOccurrences(
            of: "{{transcription}}",
            with: transcription
        )

        return (renderedSystemPrompt, renderedUserPrompt)
    }

    /// Validate a template for unresolved variables.
    /// - Parameter template: The template to validate.
    /// - Returns: List of unresolved variable names (empty if all resolved).
    static func validate(template: PromptTemplate) -> [String] {
        let pattern = "\\{\\{([^}]+)\\}\\}"
        let regex = try? NSRegularExpression(pattern: pattern)

        let allText = template.systemPrompt + " " + template.userPromptTemplate
        let range = NSRange(allText.startIndex..., in: allText)
        let matches = regex?.matches(in: allText, range: range) ?? []

        let builtInNames = Set(["transcription", "language", "app_name", "app_bundle_id", "timestamp", "date", "time"])
        let declaredVariables = Set(template.variables)

        var unresolved: [String] = []
        for match in matches {
            if let varRange = Range(match.range(at: 1), in: allText) {
                let varName = String(allText[varRange])
                if !builtInNames.contains(varName) && !declaredVariables.contains(varName) {
                    unresolved.append(varName)
                }
            }
        }

        return Array(Set(unresolved)).sorted()
    }

    /// Built-in variables available in all templates.
    private static func builtInVariables() -> [String: String] {
        let now = Date()
        let formatter = DateFormatter()

        // Get active app info
        let activeApp = NSWorkspace.shared.frontmostApplication
        let appName = activeApp?.localizedName ?? "Unknown"
        let bundleId = activeApp?.bundleIdentifier ?? "unknown"

        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let dateString = formatter.string(from: now)

        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let timeString = formatter.string(from: now)

        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let timestampString = formatter.string(from: now)

        return [
            "language": Locale.current.language.languageCode?.identifier ?? "en",
            "app_name": appName,
            "app_bundle_id": bundleId,
            "timestamp": timestampString,
            "date": dateString,
            "time": timeString,
        ]
    }
}
