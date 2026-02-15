import Foundation
import SwiftData
import XCTest

@testable import HushType

final class PromptTemplateTests: XCTestCase {
    private var modelContainer: ModelContainer!
    private var modelContext: ModelContext!

    override func setUp() async throws {
        try await super.setUp()

        // Create in-memory model container for testing
        let schema = Schema([
            PromptTemplate.self,
        ])

        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            modelContext = ModelContext(modelContainer)
        } catch {
            XCTFail("Failed to create ModelContainer: \(error)")
            throw error
        }
    }

    override func tearDown() async throws {
        modelContext = nil
        modelContainer = nil
        try await super.tearDown()
    }

    // MARK: - Render Tests

    func test_render_substitutesTranscription() {
        let template = PromptTemplate(
            name: "Test",
            mode: .clean,
            systemPrompt: "System",
            userPromptTemplate: "{{transcription}}"
        )

        let result = template.render(transcription: "hello world")

        XCTAssertEqual(result, "hello world")
    }

    func test_render_substitutesCustomVariables() {
        let template = PromptTemplate(
            name: "Test",
            mode: .prompt,
            systemPrompt: "System",
            userPromptTemplate: "Tone: {{tone}}, Text: {{transcription}}",
            variables: ["tone"]
        )

        let result = template.render(
            transcription: "test text",
            values: ["tone": "formal"]
        )

        XCTAssertEqual(result, "Tone: formal, Text: test text")
    }

    func test_render_handlesMultipleVariables() {
        let template = PromptTemplate(
            name: "Test",
            mode: .prompt,
            systemPrompt: "System",
            userPromptTemplate: "{{var1}} {{var2}} {{transcription}}",
            variables: ["var1", "var2"]
        )

        let result = template.render(
            transcription: "text",
            values: ["var1": "value1", "var2": "value2"]
        )

        XCTAssertEqual(result, "value1 value2 text")
    }

    func test_render_leavesUnprovidedVariablesAsIs() {
        let template = PromptTemplate(
            name: "Test",
            mode: .prompt,
            systemPrompt: "System",
            userPromptTemplate: "{{provided}} {{not_provided}}",
            variables: ["provided", "not_provided"]
        )

        let result = template.render(
            transcription: "text",
            values: ["provided": "yes"]
        )

        XCTAssertEqual(result, "yes {{not_provided}}")
    }

    // MARK: - Validation Tests

    func test_validate_warnsOnEmptySystemPrompt() {
        let template = PromptTemplate(
            name: "Test",
            mode: .clean,
            systemPrompt: "",
            userPromptTemplate: "{{transcription}}"
        )

        let validation = template.validate()

        XCTAssertTrue(validation.warnings.contains("System prompt is empty"))
    }

    func test_validate_warnsOnEmptyUserPrompt() {
        let template = PromptTemplate(
            name: "Test",
            mode: .clean,
            systemPrompt: "System",
            userPromptTemplate: ""
        )

        let validation = template.validate()

        XCTAssertTrue(validation.warnings.contains("User prompt template is empty"))
    }

    func test_validate_warnsOnMissingTranscription() {
        let template = PromptTemplate(
            name: "Test",
            mode: .clean,
            systemPrompt: "System",
            userPromptTemplate: "No transcription variable here"
        )

        let validation = template.validate()

        XCTAssertTrue(validation.warnings.contains { $0.contains("{{transcription}}") })
    }

    func test_validate_detectsUnresolvedVariables() {
        let template = PromptTemplate(
            name: "Test",
            mode: .prompt,
            systemPrompt: "System",
            userPromptTemplate: "{{transcription}} {{unknown}}",
            variables: []
        )

        let validation = template.validate()

        XCTAssertTrue(validation.unresolvedVariables.contains("unknown"))
        XCTAssertTrue(validation.warnings.contains { $0.contains("Unresolved variables") })
    }

    func test_validate_passesForValidTemplate() {
        let template = PromptTemplate(
            name: "Valid Template",
            mode: .clean,
            systemPrompt: "You are a helpful assistant.",
            userPromptTemplate: "Process: {{transcription}}",
            variables: []
        )

        let validation = template.validate()

        XCTAssertTrue(validation.isValid)
        XCTAssertTrue(validation.warnings.isEmpty)
        XCTAssertTrue(validation.unresolvedVariables.isEmpty)
    }

    func test_validate_isValidWithOnlyEmptySystemPrompt() {
        // According to implementation, only system prompt empty is still considered valid
        let template = PromptTemplate(
            name: "Test",
            mode: .clean,
            systemPrompt: "",
            userPromptTemplate: "{{transcription}}"
        )

        let validation = template.validate()

        XCTAssertTrue(validation.isValid)
        XCTAssertEqual(validation.warnings.count, 1)
        XCTAssertTrue(validation.warnings.first == "System prompt is empty")
    }

    // MARK: - Built-in Templates Tests

    func test_builtInTemplates_notEmpty() {
        XCTAssertFalse(PromptTemplate.builtInTemplates.isEmpty)
        XCTAssertGreaterThanOrEqual(PromptTemplate.builtInTemplates.count, 4)
    }

    func test_builtInTemplates_allMarkedAsBuiltIn() {
        for template in PromptTemplate.builtInTemplates {
            XCTAssertTrue(template.isBuiltIn)
        }
    }

    func test_builtInTemplates_haveUniqueNames() {
        let names = PromptTemplate.builtInTemplates.map { $0.name }
        let uniqueNames = Set(names)

        XCTAssertEqual(names.count, uniqueNames.count, "Built-in templates should have unique names")
    }

    func test_builtInTemplates_coversMainModes() {
        let modes = Set(PromptTemplate.builtInTemplates.map { $0.mode })

        XCTAssertTrue(modes.contains(.clean))
        XCTAssertTrue(modes.contains(.structure))
        XCTAssertTrue(modes.contains(.code))
        XCTAssertTrue(modes.contains(.prompt))
    }

    // MARK: - isDeletable Tests

    func test_isDeletable_builtInTemplatesNotDeletable() {
        let template = PromptTemplate(
            name: "Built-in",
            mode: .clean,
            systemPrompt: "System",
            userPromptTemplate: "{{transcription}}",
            isBuiltIn: true
        )

        XCTAssertFalse(template.isDeletable)
    }

    func test_isDeletable_userTemplatesDeletable() {
        let template = PromptTemplate(
            name: "User Template",
            mode: .clean,
            systemPrompt: "System",
            userPromptTemplate: "{{transcription}}",
            isBuiltIn: false
        )

        XCTAssertTrue(template.isDeletable)
    }

    // MARK: - SwiftData Persistence Tests

    func test_persistence() throws {
        let template = PromptTemplate(
            name: "Test Template",
            mode: .clean,
            systemPrompt: "System prompt",
            userPromptTemplate: "User: {{transcription}}",
            variables: ["var1", "var2"],
            isBuiltIn: false,
            isDefault: true
        )

        modelContext.insert(template)
        try modelContext.save()

        // Fetch all templates
        let descriptor = FetchDescriptor<PromptTemplate>()
        let templates = try modelContext.fetch(descriptor)

        XCTAssertEqual(templates.count, 1)

        guard let fetched = templates.first else {
            XCTFail("No template fetched")
            return
        }

        XCTAssertEqual(fetched.id, template.id)
        XCTAssertEqual(fetched.name, "Test Template")
        XCTAssertEqual(fetched.mode, .clean)
        XCTAssertEqual(fetched.systemPrompt, "System prompt")
        XCTAssertEqual(fetched.userPromptTemplate, "User: {{transcription}}")
        XCTAssertEqual(fetched.variables, ["var1", "var2"])
        XCTAssertFalse(fetched.isBuiltIn)
        XCTAssertTrue(fetched.isDefault)
    }

    func test_createUserTemplate() throws {
        let template = PromptTemplate.createUserTemplate(
            name: "My Template",
            mode: .code,
            systemPrompt: "Code system",
            userPromptTemplate: "{{transcription}}",
            variables: ["language"],
            in: modelContext
        )

        try modelContext.save()

        XCTAssertFalse(template.isBuiltIn)
        XCTAssertFalse(template.isDefault)
        XCTAssertEqual(template.name, "My Template")

        // Verify it's in the context
        let descriptor = FetchDescriptor<PromptTemplate>()
        let templates = try modelContext.fetch(descriptor)

        XCTAssertEqual(templates.count, 1)
    }

    func test_deleteIfAllowed_userTemplate() throws {
        let template = PromptTemplate.createUserTemplate(
            name: "Deletable",
            mode: .clean,
            systemPrompt: "System",
            userPromptTemplate: "{{transcription}}",
            in: modelContext
        )

        try modelContext.save()

        let deleted = template.deleteIfAllowed(from: modelContext)

        XCTAssertTrue(deleted)

        try modelContext.save()

        let descriptor = FetchDescriptor<PromptTemplate>()
        let templates = try modelContext.fetch(descriptor)

        XCTAssertEqual(templates.count, 0)
    }

    func test_deleteIfAllowed_builtInTemplate() throws {
        let template = PromptTemplate(
            name: "Built-in",
            mode: .clean,
            systemPrompt: "System",
            userPromptTemplate: "{{transcription}}",
            isBuiltIn: true
        )

        modelContext.insert(template)
        try modelContext.save()

        let deleted = template.deleteIfAllowed(from: modelContext)

        XCTAssertFalse(deleted)

        // Should still exist
        let descriptor = FetchDescriptor<PromptTemplate>()
        let templates = try modelContext.fetch(descriptor)

        XCTAssertEqual(templates.count, 1)
    }

    func test_duplicate() throws {
        let original = PromptTemplate(
            name: "Original",
            mode: .clean,
            systemPrompt: "System prompt",
            userPromptTemplate: "User {{transcription}}",
            variables: ["var1"]
        )

        modelContext.insert(original)
        try modelContext.save()

        let duplicate = original.duplicate(in: modelContext)

        try modelContext.save()

        XCTAssertNotEqual(duplicate.id, original.id)
        XCTAssertEqual(duplicate.name, "Original Copy")
        XCTAssertEqual(duplicate.mode, original.mode)
        XCTAssertEqual(duplicate.systemPrompt, original.systemPrompt)
        XCTAssertEqual(duplicate.userPromptTemplate, original.userPromptTemplate)
        XCTAssertEqual(duplicate.variables, original.variables)
        XCTAssertFalse(duplicate.isBuiltIn)

        // Should have 2 templates now
        let descriptor = FetchDescriptor<PromptTemplate>()
        let templates = try modelContext.fetch(descriptor)

        XCTAssertEqual(templates.count, 2)
    }

    func test_duplicate_customName() throws {
        let original = PromptTemplate(
            name: "Original",
            mode: .clean,
            systemPrompt: "System",
            userPromptTemplate: "{{transcription}}"
        )

        modelContext.insert(original)
        let duplicate = original.duplicate(name: "Custom Name", in: modelContext)

        XCTAssertEqual(duplicate.name, "Custom Name")
    }
}
