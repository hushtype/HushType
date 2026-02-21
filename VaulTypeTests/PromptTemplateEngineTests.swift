import Foundation
import XCTest

@testable import VaulType

final class PromptTemplateEngineTests: XCTestCase {
    // MARK: - Variable Substitution Tests

    func test_render_substitutesTranscription() {
        let template = PromptTemplate(
            name: "Test",
            mode: .clean,
            systemPrompt: "System",
            userPromptTemplate: "Input: {{transcription}}"
        )

        let (_, userPrompt) = PromptTemplateEngine.render(
            template: template,
            transcription: "hello world"
        )

        XCTAssertEqual(userPrompt, "Input: hello world")
    }

    func test_render_substitutesMultipleOccurrences() {
        let template = PromptTemplate(
            name: "Test",
            mode: .clean,
            systemPrompt: "System",
            userPromptTemplate: "{{transcription}} - {{transcription}}"
        )

        let (_, userPrompt) = PromptTemplateEngine.render(
            template: template,
            transcription: "test"
        )

        XCTAssertEqual(userPrompt, "test - test")
    }

    // MARK: - Built-in Variable Tests

    func test_render_substitutesLanguage() {
        let template = PromptTemplate(
            name: "Test",
            mode: .clean,
            systemPrompt: "System",
            userPromptTemplate: "Language: {{language}}"
        )

        let (_, userPrompt) = PromptTemplateEngine.render(
            template: template,
            transcription: "text"
        )

        XCTAssertTrue(userPrompt.hasPrefix("Language: "))
        XCTAssertFalse(userPrompt.contains("{{language}}"))
    }

    func test_render_substitutesDate() {
        let template = PromptTemplate(
            name: "Test",
            mode: .clean,
            systemPrompt: "System",
            userPromptTemplate: "Date: {{date}}"
        )

        let (_, userPrompt) = PromptTemplateEngine.render(
            template: template,
            transcription: "text"
        )

        XCTAssertTrue(userPrompt.hasPrefix("Date: "))
        XCTAssertFalse(userPrompt.contains("{{date}}"))
    }

    func test_render_substitutesTime() {
        let template = PromptTemplate(
            name: "Test",
            mode: .clean,
            systemPrompt: "System",
            userPromptTemplate: "Time: {{time}}"
        )

        let (_, userPrompt) = PromptTemplateEngine.render(
            template: template,
            transcription: "text"
        )

        XCTAssertTrue(userPrompt.hasPrefix("Time: "))
        XCTAssertFalse(userPrompt.contains("{{time}}"))
    }

    func test_render_substitutesTimestamp() {
        let template = PromptTemplate(
            name: "Test",
            mode: .clean,
            systemPrompt: "System",
            userPromptTemplate: "Timestamp: {{timestamp}}"
        )

        let (_, userPrompt) = PromptTemplateEngine.render(
            template: template,
            transcription: "text"
        )

        XCTAssertTrue(userPrompt.hasPrefix("Timestamp: "))
        XCTAssertFalse(userPrompt.contains("{{timestamp}}"))
    }

    func test_render_substitutesAppName() {
        let template = PromptTemplate(
            name: "Test",
            mode: .clean,
            systemPrompt: "System",
            userPromptTemplate: "App: {{app_name}}"
        )

        let (_, userPrompt) = PromptTemplateEngine.render(
            template: template,
            transcription: "text"
        )

        XCTAssertTrue(userPrompt.hasPrefix("App: "))
        XCTAssertFalse(userPrompt.contains("{{app_name}}"))
    }

    func test_render_substitutesAppBundleId() {
        let template = PromptTemplate(
            name: "Test",
            mode: .clean,
            systemPrompt: "System",
            userPromptTemplate: "Bundle: {{app_bundle_id}}"
        )

        let (_, userPrompt) = PromptTemplateEngine.render(
            template: template,
            transcription: "text"
        )

        XCTAssertTrue(userPrompt.hasPrefix("Bundle: "))
        XCTAssertFalse(userPrompt.contains("{{app_bundle_id}}"))
    }

    // MARK: - User Variable Tests

    func test_render_substitutesUserVariables() {
        let template = PromptTemplate(
            name: "Test",
            mode: .clean,
            systemPrompt: "System",
            userPromptTemplate: "Tone: {{tone}}, Style: {{style}}",
            variables: ["tone", "style"]
        )

        let (_, userPrompt) = PromptTemplateEngine.render(
            template: template,
            transcription: "text",
            userVariables: ["tone": "formal", "style": "concise"]
        )

        XCTAssertEqual(userPrompt, "Tone: formal, Style: concise")
    }

    func test_render_userVariablesOverrideBuiltIn() {
        let template = PromptTemplate(
            name: "Test",
            mode: .clean,
            systemPrompt: "System",
            userPromptTemplate: "Language: {{language}}"
        )

        let (_, userPrompt) = PromptTemplateEngine.render(
            template: template,
            transcription: "text",
            userVariables: ["language": "custom"]
        )

        XCTAssertEqual(userPrompt, "Language: custom")
    }

    // MARK: - System Prompt Substitution Tests

    func test_render_substitutesVariablesInSystemPrompt() {
        let template = PromptTemplate(
            name: "Test",
            mode: .clean,
            systemPrompt: "You are a {{tone}} assistant for {{app_name}}.",
            userPromptTemplate: "{{transcription}}",
            variables: ["tone"]
        )

        let (systemPrompt, _) = PromptTemplateEngine.render(
            template: template,
            transcription: "text",
            userVariables: ["tone": "professional"]
        )

        XCTAssertTrue(systemPrompt.contains("professional"))
        XCTAssertFalse(systemPrompt.contains("{{tone}}"))
        XCTAssertFalse(systemPrompt.contains("{{app_name}}"))
    }

    func test_render_substitutesTranscriptionInSystemPrompt() {
        let template = PromptTemplate(
            name: "Test",
            mode: .clean,
            systemPrompt: "Process this: {{transcription}}",
            userPromptTemplate: "Additional: {{transcription}}"
        )

        let (systemPrompt, userPrompt) = PromptTemplateEngine.render(
            template: template,
            transcription: "hello"
        )

        XCTAssertEqual(systemPrompt, "Process this: hello")
        XCTAssertEqual(userPrompt, "Additional: hello")
    }

    // MARK: - Validation Tests

    func test_validate_findsUnresolvedVariables() {
        let template = PromptTemplate(
            name: "Test",
            mode: .clean,
            systemPrompt: "System",
            userPromptTemplate: "Missing: {{unknown_var}}",
            variables: []
        )

        let unresolved = PromptTemplateEngine.validate(template: template)

        XCTAssertTrue(unresolved.contains("unknown_var"))
    }

    func test_validate_ignoresBuiltInVariables() {
        let template = PromptTemplate(
            name: "Test",
            mode: .clean,
            systemPrompt: "System",
            userPromptTemplate: "{{transcription}} {{language}} {{app_name}} {{app_bundle_id}} {{timestamp}} {{date}} {{time}}"
        )

        let unresolved = PromptTemplateEngine.validate(template: template)

        XCTAssertTrue(unresolved.isEmpty, "Built-in variables should not be flagged as unresolved")
    }

    func test_validate_ignoresDeclaredVariables() {
        let template = PromptTemplate(
            name: "Test",
            mode: .clean,
            systemPrompt: "System",
            userPromptTemplate: "{{tone}} {{style}}",
            variables: ["tone", "style"]
        )

        let unresolved = PromptTemplateEngine.validate(template: template)

        XCTAssertTrue(unresolved.isEmpty, "Declared variables should not be flagged as unresolved")
    }

    func test_validate_detectsMultipleUnresolved() {
        let template = PromptTemplate(
            name: "Test",
            mode: .clean,
            systemPrompt: "{{var1}}",
            userPromptTemplate: "{{var2}} {{var3}}",
            variables: []
        )

        let unresolved = PromptTemplateEngine.validate(template: template)

        XCTAssertEqual(unresolved.count, 3)
        XCTAssertTrue(unresolved.contains("var1"))
        XCTAssertTrue(unresolved.contains("var2"))
        XCTAssertTrue(unresolved.contains("var3"))
    }

    func test_validate_deduplicatesUnresolved() {
        let template = PromptTemplate(
            name: "Test",
            mode: .clean,
            systemPrompt: "{{duplicate}}",
            userPromptTemplate: "{{duplicate}} {{duplicate}}",
            variables: []
        )

        let unresolved = PromptTemplateEngine.validate(template: template)

        // Should only contain "duplicate" once
        XCTAssertEqual(unresolved.count, 1)
        XCTAssertEqual(unresolved.first, "duplicate")
    }

    func test_validate_returnsEmptyForValidTemplate() {
        let template = PromptTemplate(
            name: "Test",
            mode: .clean,
            systemPrompt: "You are a {{tone}} assistant.",
            userPromptTemplate: "Process: {{transcription}}",
            variables: ["tone"]
        )

        let unresolved = PromptTemplateEngine.validate(template: template)

        XCTAssertTrue(unresolved.isEmpty)
    }

    // MARK: - Edge Case Tests

    func test_render_handlesEmptyTranscription() {
        let template = PromptTemplate(
            name: "Test",
            mode: .clean,
            systemPrompt: "System",
            userPromptTemplate: "Input: {{transcription}}"
        )

        let (_, userPrompt) = PromptTemplateEngine.render(
            template: template,
            transcription: ""
        )

        XCTAssertEqual(userPrompt, "Input: ")
    }

    func test_render_handlesSpecialCharacters() {
        let template = PromptTemplate(
            name: "Test",
            mode: .clean,
            systemPrompt: "System",
            userPromptTemplate: "{{transcription}}"
        )

        let specialChars = "Hello \"world\" with 'quotes' and $symbols & more!"

        let (_, userPrompt) = PromptTemplateEngine.render(
            template: template,
            transcription: specialChars
        )

        XCTAssertEqual(userPrompt, specialChars)
    }

    func test_render_handlesNoVariables() {
        let template = PromptTemplate(
            name: "Test",
            mode: .clean,
            systemPrompt: "Static system prompt",
            userPromptTemplate: "Static user prompt"
        )

        let (systemPrompt, userPrompt) = PromptTemplateEngine.render(
            template: template,
            transcription: "ignored"
        )

        XCTAssertEqual(systemPrompt, "Static system prompt")
        XCTAssertEqual(userPrompt, "Static user prompt")
    }
}
