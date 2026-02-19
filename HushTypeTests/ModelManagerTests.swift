import Foundation
import SwiftData
import XCTest

@testable import HushType

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

    // MARK: - Total Disk Usage Tests

    func test_totalDiskUsage_withNoModels() {
        let models: [ModelInfo] = []

        let usage = manager.totalDiskUsage(models: models)

        XCTAssertEqual(usage, 0)
    }

    func test_totalDiskUsage_withDownloadedModels() throws {
        let model1 = ModelInfo(
            name: "Model 1",
            type: .whisper,
            fileName: "test-model1.bin",
            fileSize: 100_000_000,
            isDownloaded: true
        )

        let model2 = ModelInfo(
            name: "Model 2",
            type: .llm,
            fileName: "test-model2.gguf",
            fileSize: 200_000_000,
            isDownloaded: true
        )

        try createPlaceholderFile(for: model1)
        try createPlaceholderFile(for: model2)

        let models = [model1, model2]

        let usage = manager.totalDiskUsage(models: models)

        XCTAssertEqual(usage, 300_000_000)
    }

    func test_totalDiskUsage_ignoresNotDownloaded() throws {
        let downloaded = ModelInfo(
            name: "Downloaded",
            type: .whisper,
            fileName: "test-downloaded.bin",
            fileSize: 100_000_000,
            isDownloaded: true
        )

        let notDownloaded = ModelInfo(
            name: "Not Downloaded",
            type: .whisper,
            fileName: "test-not-downloaded.bin",
            fileSize: 200_000_000,
            isDownloaded: false
        )

        try createPlaceholderFile(for: downloaded)

        let models = [downloaded, notDownloaded]

        let usage = manager.totalDiskUsage(models: models)

        // Should only count the downloaded model
        XCTAssertEqual(usage, 100_000_000)
    }

    func test_totalDiskUsage_checksFileExistence() {
        // Model marked as downloaded but file doesn't exist
        let model = ModelInfo(
            name: "Phantom",
            type: .whisper,
            fileName: "phantom.bin",
            fileSize: 100_000_000,
            isDownloaded: true
        )

        let models = [model]

        let usage = manager.totalDiskUsage(models: models)

        // Should be 0 because fileExistsOnDisk will return false
        XCTAssertEqual(usage, 0)
    }

    // MARK: - Disk Usage by Type Tests

    func test_diskUsage_filtersByType() throws {
        let whisperModel = ModelInfo(
            name: "Whisper",
            type: .whisper,
            fileName: "test-whisper.bin",
            fileSize: 100_000_000,
            isDownloaded: true
        )

        let llmModel = ModelInfo(
            name: "LLM",
            type: .llm,
            fileName: "test-llm.gguf",
            fileSize: 200_000_000,
            isDownloaded: true
        )

        try createPlaceholderFile(for: whisperModel)
        try createPlaceholderFile(for: llmModel)

        let models = [whisperModel, llmModel]

        let whisperUsage = manager.diskUsage(for: .whisper, models: models)
        let llmUsage = manager.diskUsage(for: .llm, models: models)

        XCTAssertEqual(whisperUsage, 100_000_000)
        XCTAssertEqual(llmUsage, 200_000_000)
    }

    func test_diskUsage_multipleModelsOfSameType() throws {
        let whisper1 = ModelInfo(
            name: "Whisper 1",
            type: .whisper,
            fileName: "test-whisper1.bin",
            fileSize: 100_000_000,
            isDownloaded: true
        )

        let whisper2 = ModelInfo(
            name: "Whisper 2",
            type: .whisper,
            fileName: "test-whisper2.bin",
            fileSize: 150_000_000,
            isDownloaded: true
        )

        try createPlaceholderFile(for: whisper1)
        try createPlaceholderFile(for: whisper2)

        let models = [whisper1, whisper2]

        let usage = manager.diskUsage(for: .whisper, models: models)

        XCTAssertEqual(usage, 250_000_000)
    }

    func test_diskUsage_ignoresNotDownloaded() throws {
        let downloaded = ModelInfo(
            name: "Downloaded",
            type: .whisper,
            fileName: "test-dl.bin",
            fileSize: 100_000_000,
            isDownloaded: true
        )

        let notDownloaded = ModelInfo(
            name: "Not Downloaded",
            type: .whisper,
            fileName: "test-not-dl.bin",
            fileSize: 200_000_000,
            isDownloaded: false
        )

        try createPlaceholderFile(for: downloaded)

        let models = [downloaded, notDownloaded]

        let usage = manager.diskUsage(for: .whisper, models: models)

        XCTAssertEqual(usage, 100_000_000)
    }

    func test_diskUsage_noMatchingType() throws {
        let llmModel = ModelInfo(
            name: "LLM",
            type: .llm,
            fileName: "test-llm-only.gguf",
            fileSize: 200_000_000,
            isDownloaded: true
        )

        try createPlaceholderFile(for: llmModel)

        let models = [llmModel]

        let whisperUsage = manager.diskUsage(for: .whisper, models: models)

        XCTAssertEqual(whisperUsage, 0)
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

    // MARK: - Edge Cases

    func test_totalDiskUsage_withLargeNumbers() {
        let largeModel = ModelInfo(
            name: "Large",
            type: .llm,
            fileName: "large.gguf",
            fileSize: Int64.max / 2,
            isDownloaded: true
        )

        let models = [largeModel]

        // Should not overflow
        let usage = manager.totalDiskUsage(models: models)

        // Since file doesn't exist, should be 0
        XCTAssertEqual(usage, 0)
    }

    func test_diskUsage_withZeroSizeModel() {
        let zeroModel = ModelInfo(
            name: "Zero",
            type: .whisper,
            fileName: "zero.bin",
            fileSize: 0,
            isDownloaded: true
        )

        let models = [zeroModel]

        let usage = manager.diskUsage(for: .whisper, models: models)

        XCTAssertEqual(usage, 0)
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

    // MARK: - Mixed Download States Tests

    func test_totalDiskUsage_mixedDownloadStates() {
        let downloaded1 = ModelInfo(
            name: "D1",
            type: .whisper,
            fileName: "d1.bin",
            fileSize: 100_000_000,
            isDownloaded: true
        )

        let notDownloaded = ModelInfo(
            name: "ND",
            type: .whisper,
            fileName: "nd.bin",
            fileSize: 200_000_000,
            isDownloaded: false
        )

        let downloaded2 = ModelInfo(
            name: "D2",
            type: .llm,
            fileName: "d2.gguf",
            fileSize: 300_000_000,
            isDownloaded: true
        )

        let models = [downloaded1, notDownloaded, downloaded2]

        let usage = manager.totalDiskUsage(models: models)

        // Should be 0 because files don't actually exist
        XCTAssertEqual(usage, 0)
    }
}
