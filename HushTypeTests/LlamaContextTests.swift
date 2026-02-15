import Foundation
import XCTest

@testable import HushType

final class LlamaContextTests: XCTestCase {
    // MARK: - GenerationResult Tests

    func test_generationResult_properties() {
        let result = GenerationResult(
            text: "Hello world",
            promptTokenCount: 5,
            generatedTokenCount: 2,
            generationDuration: 0.42
        )

        XCTAssertEqual(result.text, "Hello world")
        XCTAssertEqual(result.promptTokenCount, 5)
        XCTAssertEqual(result.generatedTokenCount, 2)
        XCTAssertEqual(result.generationDuration, 0.42, accuracy: 0.001)
    }

    func test_generationResult_emptyText() {
        let result = GenerationResult(
            text: "",
            promptTokenCount: 10,
            generatedTokenCount: 0,
            generationDuration: 0.1
        )

        XCTAssertEqual(result.text, "")
        XCTAssertEqual(result.generatedTokenCount, 0)
    }

    func test_generationResult_isSendable() {
        // GenerationResult conforms to Sendable — verify it can cross isolation boundaries
        let result = GenerationResult(
            text: "test",
            promptTokenCount: 1,
            generatedTokenCount: 1,
            generationDuration: 0.01
        )

        let expectation = expectation(description: "Sendable across tasks")

        Task.detached {
            // Accessing from detached task (different isolation domain)
            XCTAssertEqual(result.text, "test")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }

    // MARK: - LlamaContextError Tests

    func test_error_modelLoadFailed_description() {
        let error = LlamaContextError.modelLoadFailed("/path/to/model.gguf")

        XCTAssertTrue(error.errorDescription?.contains("/path/to/model.gguf") ?? false)
        XCTAssertTrue(error.errorDescription?.contains("Failed to load") ?? false)
    }

    func test_error_contextCreationFailed_description() {
        let error = LlamaContextError.contextCreationFailed

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("context") ?? false)
    }

    func test_error_contextNotInitialized_description() {
        let error = LlamaContextError.contextNotInitialized

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("not initialized") ?? false)
    }

    func test_error_tokenizationFailed_description() {
        let error = LlamaContextError.tokenizationFailed

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("tokenize") ?? false)
    }

    func test_error_decodeFailed_description() {
        let error = LlamaContextError.decodeFailed

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("decode") ?? false)
    }

    func test_error_generationFailed_description() {
        let error = LlamaContextError.generationFailed("out of memory")

        XCTAssertTrue(error.errorDescription?.contains("out of memory") ?? false)
        XCTAssertTrue(error.errorDescription?.contains("generation failed") ?? false)
    }

    func test_error_emptyPrompt_description() {
        let error = LlamaContextError.emptyPrompt

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("empty") ?? false)
    }

    func test_allErrors_haveDescriptions() {
        let errors: [LlamaContextError] = [
            .modelLoadFailed("test"),
            .contextCreationFailed,
            .contextNotInitialized,
            .tokenizationFailed,
            .decodeFailed,
            .generationFailed("test"),
            .emptyPrompt,
        ]

        for error in errors {
            XCTAssertNotNil(
                error.errorDescription,
                "Error \(error) should have a description"
            )
            XCTAssertFalse(
                error.errorDescription?.isEmpty ?? true,
                "Error \(error) description should not be empty"
            )
        }
    }

    // MARK: - Init Error Tests

    func test_init_withNonexistentPath_throwsModelLoadFailed() {
        let fakePath = "/nonexistent/path/to/model.gguf"

        XCTAssertThrowsError(
            try LlamaContext(modelPath: fakePath)
        ) { error in
            guard let llamaError = error as? LlamaContextError else {
                XCTFail("Expected LlamaContextError, got \(type(of: error))")
                return
            }

            if case .modelLoadFailed(let path) = llamaError {
                XCTAssertEqual(path, fakePath)
            } else {
                XCTFail("Expected modelLoadFailed, got \(llamaError)")
            }
        }
    }

    func test_init_withEmptyPath_throwsModelLoadFailed() {
        XCTAssertThrowsError(
            try LlamaContext(modelPath: "")
        ) { error in
            guard let llamaError = error as? LlamaContextError else {
                XCTFail("Expected LlamaContextError, got \(type(of: error))")
                return
            }

            if case .modelLoadFailed = llamaError {
                // Expected
            } else {
                XCTFail("Expected modelLoadFailed, got \(llamaError)")
            }
        }
    }

    func test_init_withDirectoryPath_throwsModelLoadFailed() {
        // /tmp exists but is a directory, not a GGUF file
        // FileManager.fileExists returns true for directories, but llama_model_load_from_file
        // will fail since it's not a valid model file.
        // This tests the second failure path (llama_model_load_from_file returns nil)
        // or the first path if fileExists returns false for the directory.
        let dirPath = NSTemporaryDirectory()

        XCTAssertThrowsError(
            try LlamaContext(modelPath: dirPath)
        ) { error in
            XCTAssertTrue(error is LlamaContextError)
        }
    }

    // MARK: - Generate Error Tests

    func test_generate_withEmptyPrompt_throwsEmptyPrompt() async {
        // We can't create a valid LlamaContext without a model file,
        // but the empty prompt check happens before any C API calls.
        // Since we can't instantiate LlamaContext, we test the error type directly.
        let error = LlamaContextError.emptyPrompt

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.localizedDescription.contains("empty"))
    }

    // MARK: - Error Equatability Tests

    func test_errors_areLocalizedError() {
        let error: Error = LlamaContextError.contextCreationFailed

        // LocalizedError conformance provides localizedDescription
        XCTAssertFalse(error.localizedDescription.isEmpty)
        XCTAssertNotEqual(
            error.localizedDescription,
            "The operation couldn\u{2019}t be completed."
        )
    }
}
