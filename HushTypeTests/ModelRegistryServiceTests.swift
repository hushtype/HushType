import Foundation
import SwiftData
import XCTest

@testable import HushType

@MainActor
final class ModelRegistryServiceTests: XCTestCase {
    private var modelContainer: ModelContainer!
    private var modelContext: ModelContext!
    private var service: ModelRegistryService!

    override func setUp() async throws {
        try await super.setUp()

        let schema = Schema([
            ModelInfo.self,
            UserSettings.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        modelContext = ModelContext(modelContainer)
        service = ModelRegistryService(modelContainer: modelContainer)
    }

    override func tearDown() async throws {
        service = nil
        modelContext = nil
        modelContainer = nil
        // Clear the last refresh timestamp
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.lastModelRegistryUpdate)
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeManifest(entries: [ModelManifestEntry]) -> ModelManifest {
        ModelManifest(
            version: 1,
            updatedAt: "2026-02-19T12:00:00Z",
            models: entries
        )
    }

    private func makeEntry(
        fileName: String = "test-model.bin",
        name: String = "Test Model",
        type: String = "whisper",
        fileSize: Int64 = 100_000,
        isDefault: Bool = false,
        sha256: String? = "abc123",
        downloadURLs: [String] = ["https://example.com/model.bin"],
        deprecated: Bool = false,
        notes: String? = nil
    ) -> ModelManifestEntry {
        ModelManifestEntry(
            fileName: fileName,
            name: name,
            type: type,
            fileSize: fileSize,
            isDefault: isDefault,
            sha256: sha256,
            downloadURLs: downloadURLs,
            deprecated: deprecated,
            notes: notes
        )
    }

    // MARK: - applyManifest Tests

    func test_applyManifest_updatesExistingModel() throws {
        // Seed an existing model
        let model = ModelInfo(
            name: "Old Name",
            type: .whisper,
            fileName: "test-model.bin",
            fileSize: 50_000,
            downloadURL: URL(string: "https://old-url.com/model.bin"),
            isDownloaded: true
        )
        modelContext.insert(model)
        try modelContext.save()

        // Apply manifest with updated data
        let entry = makeEntry(
            fileName: "test-model.bin",
            name: "New Name",
            fileSize: 100_000,
            sha256: "newsha256",
            downloadURLs: ["https://new-url.com/model.bin", "https://mirror.com/model.bin"],
            notes: "Updated notes"
        )
        let manifest = makeManifest(entries: [entry])

        // Use a fresh context (same as service does internally)
        service.applyManifestForTesting(manifest)

        // Read back from a fresh context to verify persistence
        let freshContext = ModelContext(modelContainer)
        let results = try freshContext.fetch(FetchDescriptor<ModelInfo>())
        XCTAssertEqual(results.count, 1)

        let updated = results[0]
        XCTAssertEqual(updated.name, "New Name")
        XCTAssertEqual(updated.fileSize, 100_000)
        XCTAssertEqual(updated.sha256, "newsha256")
        XCTAssertEqual(updated.downloadURL?.absoluteString, "https://new-url.com/model.bin")
        XCTAssertEqual(updated.mirrorURLs, ["https://mirror.com/model.bin"])
        XCTAssertEqual(updated.registryNotes, "Updated notes")
        // Local state should be preserved
        XCTAssertTrue(updated.isDownloaded)
    }

    func test_applyManifest_insertsNewModel() throws {
        // Start with empty database
        let entry = makeEntry(
            fileName: "new-model.gguf",
            name: "New Model",
            type: "llm",
            fileSize: 500_000,
            sha256: "sha123",
            downloadURLs: ["https://example.com/new.gguf"]
        )
        let manifest = makeManifest(entries: [entry])

        service.applyManifestForTesting(manifest)

        let freshContext = ModelContext(modelContainer)
        let results = try freshContext.fetch(FetchDescriptor<ModelInfo>())
        XCTAssertEqual(results.count, 1)

        let inserted = results[0]
        XCTAssertEqual(inserted.fileName, "new-model.gguf")
        XCTAssertEqual(inserted.name, "New Model")
        XCTAssertEqual(inserted.type, .llm)
        XCTAssertEqual(inserted.sha256, "sha123")
        XCTAssertFalse(inserted.isDownloaded)
    }

    func test_applyManifest_preservesLocalState() throws {
        let lastUsedDate = Date(timeIntervalSince1970: 1_000_000)
        let model = ModelInfo(
            name: "Model",
            type: .whisper,
            fileName: "test-model.bin",
            fileSize: 100_000,
            isDownloaded: true,
            lastUsed: lastUsedDate
        )
        model.downloadProgress = 0.5
        model.lastDownloadError = "Some error"
        modelContext.insert(model)
        try modelContext.save()

        let entry = makeEntry(fileName: "test-model.bin", name: "Updated Name")
        let manifest = makeManifest(entries: [entry])

        service.applyManifestForTesting(manifest)

        let freshContext = ModelContext(modelContainer)
        let results = try freshContext.fetch(FetchDescriptor<ModelInfo>())
        let updated = results[0]

        // These should NOT be changed by manifest
        XCTAssertTrue(updated.isDownloaded)
        XCTAssertEqual(updated.lastUsed, lastUsedDate)
        XCTAssertEqual(updated.downloadProgress, 0.5)
        XCTAssertEqual(updated.lastDownloadError, "Some error")
    }

    func test_applyManifest_doesNotDeleteMissingModels() throws {
        // Seed a model that won't be in the manifest
        let importedModel = ModelInfo(
            name: "Imported Model",
            type: .llm,
            fileName: "user-imported.gguf",
            fileSize: 300_000,
            isDownloaded: true
        )
        modelContext.insert(importedModel)
        try modelContext.save()

        // Apply manifest without the imported model
        let entry = makeEntry(fileName: "remote-model.bin")
        let manifest = makeManifest(entries: [entry])

        service.applyManifestForTesting(manifest)

        let freshContext = ModelContext(modelContainer)
        let results = try freshContext.fetch(FetchDescriptor<ModelInfo>())
        XCTAssertEqual(results.count, 2) // both should exist
        XCTAssertTrue(results.contains { $0.fileName == "user-imported.gguf" })
        XCTAssertTrue(results.contains { $0.fileName == "remote-model.bin" })
    }

    // MARK: - Manifest Parsing Tests

    func test_parseManifest_validJSON() throws {
        let json = """
        {
          "version": 1,
          "updatedAt": "2026-02-19T12:00:00Z",
          "models": [
            {
              "fileName": "model.bin",
              "name": "Test Model",
              "type": "whisper",
              "fileSize": 100000,
              "isDefault": true,
              "sha256": "abc123",
              "downloadURLs": ["https://example.com/model.bin"],
              "deprecated": false,
              "notes": "Test notes"
            }
          ]
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(ModelManifest.self, from: json)
        XCTAssertEqual(manifest.version, 1)
        XCTAssertEqual(manifest.models.count, 1)
        XCTAssertEqual(manifest.models[0].fileName, "model.bin")
        XCTAssertEqual(manifest.models[0].sha256, "abc123")
        XCTAssertTrue(manifest.models[0].isDefault)
    }

    func test_parseManifest_malformedJSON() {
        let badJSON = "{ invalid json".data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(ModelManifest.self, from: badJSON))
    }

    func test_parseManifest_nullSHA256() throws {
        let json = """
        {
          "version": 1,
          "updatedAt": "2026-02-19",
          "models": [
            {
              "fileName": "model.bin",
              "name": "Test",
              "type": "whisper",
              "fileSize": 100,
              "isDefault": false,
              "sha256": null,
              "downloadURLs": ["https://example.com/model.bin"],
              "deprecated": false,
              "notes": null
            }
          ]
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(ModelManifest.self, from: json)
        XCTAssertNil(manifest.models[0].sha256)
        XCTAssertNil(manifest.models[0].notes)
    }

    // MARK: - refreshIfNeeded Tests

    func test_refreshIfNeeded_skipsWhenRecent() async {
        // Set last refresh to now
        UserDefaults.standard.set(Date(), forKey: UserDefaultsKey.lastModelRegistryUpdate)
        service = ModelRegistryService(modelContainer: modelContainer)

        await service.refreshIfNeeded()

        // Should not have refreshed (no error, no network call happened)
        XCTAssertNil(service.lastRefreshError)
    }

    func test_applyManifest_skipsUnknownModelType() throws {
        let entry = makeEntry(fileName: "weird.xyz", type: "unknown_type")
        let manifest = makeManifest(entries: [entry])

        service.applyManifestForTesting(manifest)

        let freshContext = ModelContext(modelContainer)
        let results = try freshContext.fetch(FetchDescriptor<ModelInfo>())
        XCTAssertEqual(results.count, 0) // should be skipped
    }

    func test_applyManifest_setsDeprecatedFlag() throws {
        let model = ModelInfo(
            name: "Model",
            type: .whisper,
            fileName: "old-model.bin",
            fileSize: 100_000,
            isDeprecated: false
        )
        modelContext.insert(model)
        try modelContext.save()

        let entry = makeEntry(fileName: "old-model.bin", deprecated: true)
        let manifest = makeManifest(entries: [entry])

        service.applyManifestForTesting(manifest)

        let freshContext = ModelContext(modelContainer)
        let results = try freshContext.fetch(FetchDescriptor<ModelInfo>())
        XCTAssertTrue(results[0].isDeprecated)
    }
}
