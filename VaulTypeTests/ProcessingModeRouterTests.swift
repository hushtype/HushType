import Foundation
import XCTest

@testable import VaulType

@MainActor
final class ProcessingModeRouterTests: XCTestCase {
    private var mockProvider: MockLLMProvider!
    private var llmService: LLMService!
    private var router: ProcessingModeRouter!

    override func setUp() async throws {
        try await super.setUp()

        mockProvider = MockLLMProvider()
        llmService = LLMService()
        llmService.setProvider(mockProvider)
        router = ProcessingModeRouter(llmService: llmService)
    }

    override func tearDown() async throws {
        router = nil
        llmService = nil
        mockProvider = nil
        try await super.tearDown()
    }

    // MARK: - Raw Mode Tests

    func test_rawMode_returnsUnchangedText() async throws {
        let input = "this is raw text with no processing"

        let result = try await router.process(
            text: input,
            mode: .raw
        )

        XCTAssertEqual(result, input, "Raw mode should return text unchanged")
        XCTAssertFalse(mockProvider.generateWasCalled, "Raw mode should not call LLM")
    }

    // MARK: - Clean Mode Tests

    func test_cleanMode_callsLLMService() async throws {
        try await llmService.loadModel(at: "mock-model")

        let input = "um like hello world you know"
        mockProvider.mockResponse = "Hello world."

        let result = try await router.process(
            text: input,
            mode: .clean
        )

        XCTAssertTrue(mockProvider.generateWasCalled)
        XCTAssertEqual(result, "Hello world.")
    }

    func test_cleanMode_passesCorrectSystemPrompt() async throws {
        try await llmService.loadModel(at: "mock-model")

        let input = "test text"
        mockProvider.mockResponse = "cleaned"

        _ = try await router.process(
            text: input,
            mode: .clean
        )

        XCTAssertTrue(mockProvider.lastSystemPrompt?.contains("text editor") ?? false)
        XCTAssertTrue(mockProvider.lastSystemPrompt?.contains("punctuation") ?? false)
    }

    // MARK: - Structure Mode Tests

    func test_structureMode_callsLLMService() async throws {
        try await llmService.loadModel(at: "mock-model")

        let input = "first point second point third point"
        mockProvider.mockResponse = "- First point\n- Second point\n- Third point"

        let result = try await router.process(
            text: input,
            mode: .structure
        )

        XCTAssertTrue(mockProvider.generateWasCalled)
        XCTAssertEqual(result, "- First point\n- Second point\n- Third point")
    }

    func test_structureMode_passesCorrectSystemPrompt() async throws {
        try await llmService.loadModel(at: "mock-model")

        let input = "test text"
        mockProvider.mockResponse = "structured"

        _ = try await router.process(
            text: input,
            mode: .structure
        )

        XCTAssertTrue(mockProvider.lastSystemPrompt?.contains("note-taking") ?? false)
        XCTAssertTrue(mockProvider.lastSystemPrompt?.contains("headings") ?? false)
    }

    // MARK: - Code Mode Tests

    func test_codeMode_callsLLMService() async throws {
        try await llmService.loadModel(at: "mock-model")

        let input = "function hello open paren close paren"
        mockProvider.mockResponse = "function hello() {}"

        let result = try await router.process(
            text: input,
            mode: .code
        )

        XCTAssertTrue(mockProvider.generateWasCalled)
        XCTAssertEqual(result, "function hello() {}")
    }

    func test_codeMode_passesCorrectSystemPrompt() async throws {
        try await llmService.loadModel(at: "mock-model")

        let input = "test code"
        mockProvider.mockResponse = "code"

        _ = try await router.process(
            text: input,
            mode: .code
        )

        XCTAssertTrue(mockProvider.lastSystemPrompt?.contains("code transcription") ?? false)
        XCTAssertTrue(mockProvider.lastSystemPrompt?.contains("open paren") ?? false)
    }

    // MARK: - Prompt Mode Tests

    func test_promptMode_withTemplate_usesTemplate() async throws {
        try await llmService.loadModel(at: "mock-model")

        let template = PromptTemplate(
            name: "Test Template",
            mode: .prompt,
            systemPrompt: "You are a test assistant.",
            userPromptTemplate: "Process: {{transcription}}"
        )

        let input = "test input"
        mockProvider.mockResponse = "template processed"

        let result = try await router.process(
            text: input,
            mode: .prompt,
            template: template
        )

        XCTAssertTrue(mockProvider.generateWasCalled)
        XCTAssertEqual(mockProvider.lastSystemPrompt, "You are a test assistant.")
        XCTAssertEqual(mockProvider.lastUserPrompt, "Process: test input")
        XCTAssertEqual(result, "template processed")
    }

    func test_promptMode_withoutTemplate_fallsBackToClean() async throws {
        try await llmService.loadModel(at: "mock-model")

        let input = "test input"
        mockProvider.mockResponse = "cleaned fallback"

        let result = try await router.process(
            text: input,
            mode: .prompt
        )

        XCTAssertTrue(mockProvider.generateWasCalled)
        XCTAssertTrue(mockProvider.lastSystemPrompt?.contains("text editor") ?? false)
        XCTAssertEqual(result, "cleaned fallback")
    }

    // MARK: - Custom Mode Tests

    func test_customMode_withoutTemplate_fallsBackToClean() async throws {
        try await llmService.loadModel(at: "mock-model")

        let input = "test input"
        mockProvider.mockResponse = "cleaned fallback"

        let result = try await router.process(
            text: input,
            mode: .custom
        )

        XCTAssertTrue(mockProvider.generateWasCalled)
        XCTAssertTrue(mockProvider.lastSystemPrompt?.contains("text editor") ?? false)
        XCTAssertEqual(result, "cleaned fallback")
    }

    // MARK: - All Modes Coverage Tests

    func test_allProcessingModes_areCovered() async throws {
        try await llmService.loadModel(at: "mock-model")
        mockProvider.mockResponse = "output"

        for mode in ProcessingMode.allCases {
            mockProvider.generateWasCalled = false

            let result = try await router.process(
                text: "test",
                mode: mode
            )

            XCTAssertNotNil(result, "Mode \(mode.rawValue) returned nil")

            if mode.requiresLLM {
                XCTAssertTrue(mockProvider.generateWasCalled, "Mode \(mode.rawValue) should call LLM")
            } else {
                XCTAssertFalse(mockProvider.generateWasCalled, "Mode \(mode.rawValue) should not call LLM")
            }
        }
    }

    // MARK: - Template Variable Substitution Tests

    func test_templateWithVariables_substitutesCorrectly() async throws {
        try await llmService.loadModel(at: "mock-model")

        let template = PromptTemplate(
            name: "Variable Template",
            mode: .prompt,
            systemPrompt: "System prompt",
            userPromptTemplate: "Tone: {{tone}}, Text: {{transcription}}",
            variables: ["tone"]
        )

        let input = "hello world"
        mockProvider.mockResponse = "result"

        _ = try await router.process(
            text: input,
            mode: .prompt,
            template: template,
            variables: ["tone": "professional"]
        )

        XCTAssertEqual(mockProvider.lastUserPrompt, "Tone: professional, Text: hello world")
    }
}

// MARK: - Mock LLM Provider

final class MockLLMProvider: LLMProvider, @unchecked Sendable {
    var isModelLoaded: Bool = false
    var generateWasCalled: Bool = false
    var mockResponse: String = "mock llm output"
    var lastSystemPrompt: String?
    var lastUserPrompt: String?

    func loadModel(at path: String) async throws {
        isModelLoaded = true
    }

    func unloadModel() async {
        isModelLoaded = false
    }

    func generate(systemPrompt: String, userPrompt: String, maxTokens: Int) async throws -> String {
        generateWasCalled = true
        lastSystemPrompt = systemPrompt
        lastUserPrompt = userPrompt
        return mockResponse
    }
}
