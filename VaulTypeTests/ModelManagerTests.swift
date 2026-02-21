import Foundation
import SwiftData
import XCTest

@testable import VaulType

@MainActor
final class ModelManagerTests: XCTestCase {
    private var modelContainer: ModelContainer!
    private var modelContext: ModelContext!
    private var manager: ModelManager!
    private var createdFilePaths: [URL] = []

    override func setUp() async throws {
        try await super.setUp()

        // Create in-memory model container for testing
        let schema = Schema([
            ModelInfo.self,
        ])

        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            modelContext = ModelContext(modelContainer)
            manager = ModelManager()
            createdFilePaths = []
        } catch {
            XCTFail("Failed to create ModelContainer: \(error)")
            throw error
        }
    }

    override func tearDown() async throws {
        // Clean up any temp files created during tests
        for path in createdFilePaths {
            try? FileManager.default.removeItem(at: path)
        }
        createdFilePaths = []
        manager = nil
        modelContext = nil
        modelContainer = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Create a placeholder file at the model's expected filePath so fileExistsOnDisk returns true.
    private func createPlaceholderFile(for model: ModelInfo) throws {
        let dir = model.filePath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: model.filePath.path, contents: Data([0]))
        createdFilePaths.append(model.filePath)
    }

    // MARK: - Sync Download States Tests

    func test_syncDownloadStates_updatesIsDownloaded() {
        // Create models with mismatched download state
        let model1 = ModelInfo(
            name: "Model 1",
            type: .whisper,
            fileName: "model1.bin",
            fileSize: 100_000_000,
            isDownloaded: true // marked as downloaded but file doesn't exist
        )

        let model2 = ModelInfo(
            name: "Model 2",
            type: .whisper,
            fileName: "model2.bin",
            fileSize: 100_000_000,
            isDownloaded: false // marked as not downloaded
        )

        let models = [model1, model2]

        manager.syncDownloadStates(models)

        // Both should be false since files don't exist
        XCTAssertFalse(model1.isDownloaded)
        XCTAssertFalse(model2.isDownloaded)
    }

    func test_syncDownloadStates_preservesCorrectState() {
        let model = ModelInfo(
            name: "Model",
            type: .whisper,
            fileName: "model.bin",
            fileSize: 100_000_000,
            isDownloaded: false
        )

        let models = [model]

        // Store initial state
        let initialState = model.isDownloaded

        manager.syncDownloadStates(models)

        // State should remain false (file doesn't exist)
        XCTAssertEqual(model.isDownloaded, initialState)
    }

    func test_syncDownloadStates_multipleModels() {
        let model1 = ModelInfo(
            name: "Model 1",
            type: .whisper,
            fileName: "model1.bin",
            fileSize: 100,
            isDownloaded: true
        )

        let model2 = ModelInfo(
            name: "Model 2",
            type: .llm,
            fileName: "model2.gguf",
            fileSize: 100,
            isDownloaded: true
        )

        let model3 = ModelInfo(
            name: "Model 3",
            type: .whisper,
            fileName: "model3.bin",
            fileSize: 100,
            isDownloaded: false
        )

        let models = [model1, model2, model3]

        manager.syncDownloadStates(models)

        // All should be false since files don't exist
        XCTAssertFalse(model1.isDownloaded)
        XCTAssertFalse(model2.isDownloaded)
        XCTAssertFalse(model3.isDownloaded)
    }

    // MARK: - SHA-256 Verification Tests

    func test_verifySHA256_matchingHash() throws {
        let model = ModelInfo(
            name: "Hash Test",
            type: .whisper,
            fileName: "hash-test.bin",
            fileSize: 5
        )

        // Create a file with known content
        let dir = model.filePath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let content = Data("hello".utf8) // SHA-256 of "hello"
        try content.write(to: model.filePath)
        createdFilePaths.append(model.filePath)
        model.isDownloaded = true

        // SHA-256 of "hello" = 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824
        let expectedHash = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        XCTAssertTrue(manager.verifySHA256(for: model, expectedHash: expectedHash))
    }

    func test_verifySHA256_mismatchingHash() throws {
        let model = ModelInfo(
            name: "Hash Mismatch",
            type: .whisper,
            fileName: "hash-mismatch.bin",
            fileSize: 5
        )

        let dir = model.filePath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let content = Data("hello".utf8)
        try content.write(to: model.filePath)
        createdFilePaths.append(model.filePath)
        model.isDownloaded = true

        XCTAssertFalse(manager.verifySHA256(for: model, expectedHash: "wrong_hash"))
    }

    func test_verifySHA256_missingFile() {
        let model = ModelInfo(
            name: "Missing",
            type: .whisper,
            fileName: "nonexistent-file.bin",
            fileSize: 100
        )

        XCTAssertFalse(manager.verifySHA256(for: model, expectedHash: "any_hash"))
    }

    func test_computeSHA256_knownContent() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("sha-test-\(UUID().uuidString).bin")
        try Data("hello".utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let hash = manager.computeSHA256(at: tempURL)
        XCTAssertEqual(hash, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }

}
