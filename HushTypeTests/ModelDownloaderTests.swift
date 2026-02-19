import Foundation
import SwiftData
import XCTest

@testable import HushType

@MainActor
final class ModelDownloaderTests: XCTestCase {
    private var modelContainer: ModelContainer!
    private var modelContext: ModelContext!
    private var downloader: ModelDownloader!
    private var createdFilePaths: [URL] = []

    override func setUp() async throws {
        try await super.setUp()

        let schema = Schema([ModelInfo.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        modelContext = ModelContext(modelContainer)
        downloader = ModelDownloader()
        createdFilePaths = []
    }

    override func tearDown() async throws {
        for path in createdFilePaths {
            try? FileManager.default.removeItem(at: path)
        }
        createdFilePaths = []
        modelContainer = nil
        modelContext = nil
        downloader = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeModel(
        name: String = "Test Model",
        type: ModelType = .whisper,
        fileName: String? = nil,
        fileSize: Int64 = 1000,
        downloadURL: URL? = URL(string: "https://example.com/model.bin"),
        sha256: String? = nil,
        mirrorURLs: [String] = []
    ) -> ModelInfo {
        let model = ModelInfo(
            name: name,
            type: type,
            fileName: fileName ?? "test-\(UUID().uuidString).bin",
            fileSize: fileSize,
            downloadURL: downloadURL,
            sha256: sha256,
            mirrorURLs: mirrorURLs
        )
        modelContext.insert(model)
        return model
    }

    private func makeTempFile(content: String = "test content") throws -> URL {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data(content.utf8).write(to: tempFile)
        return tempFile
    }

    private func makeOKResponse() -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://example.com/model.bin")!,
            statusCode: 200, httpVersion: nil, headerFields: nil
        )!
    }

    // MARK: - URL Construction

    func test_allURLs_primaryAndMirrors() {
        let model = makeModel(
            downloadURL: URL(string: "https://example.com/primary.bin"),
            mirrorURLs: ["https://mirror1.com/m.bin", "https://mirror2.com/m.bin"]
        )
        let urls = downloader.allURLs(for: model)
        XCTAssertEqual(urls.count, 3)
        XCTAssertEqual(urls[0].absoluteString, "https://example.com/primary.bin")
        XCTAssertEqual(urls[1].absoluteString, "https://mirror1.com/m.bin")
        XCTAssertEqual(urls[2].absoluteString, "https://mirror2.com/m.bin")
    }

    func test_allURLs_primaryOnly() {
        let model = makeModel(downloadURL: URL(string: "https://example.com/model.bin"))
        let urls = downloader.allURLs(for: model)
        XCTAssertEqual(urls.count, 1)
    }

    func test_allURLs_mirrorsOnly() {
        let model = makeModel(downloadURL: nil, mirrorURLs: ["https://mirror.com/m.bin"])
        let urls = downloader.allURLs(for: model)
        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls[0].absoluteString, "https://mirror.com/m.bin")
    }

    func test_allURLs_noURLs() {
        let model = makeModel(downloadURL: nil)
        let urls = downloader.allURLs(for: model)
        XCTAssertTrue(urls.isEmpty)
    }

    // MARK: - Error Handling

    func test_handleCompletion_cancelledError_doesNotSetError() {
        let model = makeModel()
        downloader.handleCompletion(
            model: model, tempURL: nil, response: nil,
            error: URLError(.cancelled)
        )
        XCTAssertNil(model.lastDownloadError)
    }

    func test_handleCompletion_networkError_setsError() {
        let model = makeModel()
        model.downloadProgress = 0.5

        downloader.handleCompletion(
            model: model, tempURL: nil, response: nil,
            error: URLError(.notConnectedToInternet)
        )

        XCTAssertNotNil(model.lastDownloadError)
        XCTAssertNil(model.downloadProgress)
    }

    func test_handleCompletion_httpError_setsError() {
        let model = makeModel()
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com/m.bin")!,
            statusCode: 404, httpVersion: nil, headerFields: nil
        )

        downloader.handleCompletion(
            model: model, tempURL: nil, response: response, error: nil
        )

        XCTAssertEqual(model.lastDownloadError, "HTTP 404")
        XCTAssertNil(model.downloadProgress)
    }

    func test_handleCompletion_http500_setsError() {
        let model = makeModel()
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com/m.bin")!,
            statusCode: 500, httpVersion: nil, headerFields: nil
        )

        downloader.handleCompletion(
            model: model, tempURL: nil, response: response, error: nil
        )

        XCTAssertEqual(model.lastDownloadError, "HTTP 500")
    }

    func test_handleCompletion_nilTempURL_setsError() {
        let model = makeModel()
        let response = makeOKResponse()

        downloader.handleCompletion(
            model: model, tempURL: nil, response: response, error: nil
        )

        XCTAssertEqual(model.lastDownloadError, "No file received")
    }

    // MARK: - Mirror Fallback

    func test_handleCompletion_networkError_triesMirror() {
        let model = makeModel(
            downloadURL: URL(string: "https://example.com/m.bin"),
            mirrorURLs: ["https://mirror.com/m.bin"]
        )
        downloader.urlIndices[model.fileName] = 0

        downloader.handleCompletion(
            model: model, tempURL: nil, response: nil,
            error: URLError(.timedOut)
        )

        // Mirror retry started — model is still downloading
        XCTAssertTrue(downloader.isDownloading(model))
        XCTAssertNil(model.lastDownloadError)

        downloader.cancel(model)
    }

    func test_handleCompletion_httpError_triesMirror() {
        let model = makeModel(
            downloadURL: URL(string: "https://example.com/m.bin"),
            mirrorURLs: ["https://mirror.com/m.bin"]
        )
        downloader.urlIndices[model.fileName] = 0

        let response = HTTPURLResponse(
            url: URL(string: "https://example.com/m.bin")!,
            statusCode: 502, httpVersion: nil, headerFields: nil
        )

        downloader.handleCompletion(
            model: model, tempURL: nil, response: response, error: nil
        )

        XCTAssertTrue(downloader.isDownloading(model))
        XCTAssertNil(model.lastDownloadError)

        downloader.cancel(model)
    }

    func test_handleCompletion_allMirrorsExhausted_setsFinalError() {
        let model = makeModel(
            downloadURL: URL(string: "https://example.com/m.bin"),
            mirrorURLs: ["https://mirror.com/m.bin"]
        )
        // At index 1 (last URL), no more mirrors to try
        downloader.urlIndices[model.fileName] = 1

        downloader.handleCompletion(
            model: model, tempURL: nil, response: nil,
            error: URLError(.timedOut)
        )

        XCTAssertFalse(downloader.isDownloading(model))
        XCTAssertNotNil(model.lastDownloadError)
        XCTAssertNil(model.downloadProgress)
    }

    // MARK: - Success Path

    func test_handleCompletion_success_setsIsDownloaded() throws {
        let model = makeModel()
        model.lastDownloadError = "Previous error"

        let tempFile = try makeTempFile(content: "model data")
        let response = makeOKResponse()

        downloader.handleCompletion(
            model: model, tempURL: tempFile, response: response, error: nil
        )

        XCTAssertTrue(model.isDownloaded)
        XCTAssertNil(model.lastDownloadError)
        XCTAssertNil(model.downloadProgress)

        createdFilePaths.append(model.filePath)
    }

    func test_handleCompletion_success_postsWhisperNotification() throws {
        let model = makeModel(type: .whisper)
        let tempFile = try makeTempFile()
        let response = makeOKResponse()

        var notified = false
        let observer = NotificationCenter.default.addObserver(
            forName: .whisperModelDownloaded, object: nil, queue: nil
        ) { notification in
            if let fileName = notification.userInfo?["fileName"] as? String,
               fileName == model.fileName {
                notified = true
            }
        }

        downloader.handleCompletion(
            model: model, tempURL: tempFile, response: response, error: nil
        )

        XCTAssertTrue(notified)
        NotificationCenter.default.removeObserver(observer)
        createdFilePaths.append(model.filePath)
    }

    func test_handleCompletion_success_postsLLMNotification() throws {
        let model = makeModel(type: .llm)
        let tempFile = try makeTempFile()
        let response = makeOKResponse()

        var notified = false
        let observer = NotificationCenter.default.addObserver(
            forName: .llmModelDownloaded, object: nil, queue: nil
        ) { notification in
            if let fileName = notification.userInfo?["fileName"] as? String,
               fileName == model.fileName {
                notified = true
            }
        }

        downloader.handleCompletion(
            model: model, tempURL: tempFile, response: response, error: nil
        )

        XCTAssertTrue(notified)
        NotificationCenter.default.removeObserver(observer)
        createdFilePaths.append(model.filePath)
    }

    // MARK: - SHA-256 Verification

    func test_handleCompletion_checksumMismatch_deletesFile() throws {
        let model = makeModel(sha256: "expected_hash")

        // Override verifyChecksum to always fail
        downloader.verifyChecksum = { _, _ in false }

        let tempFile = try makeTempFile(content: "content with wrong hash")
        let response = makeOKResponse()

        downloader.handleCompletion(
            model: model, tempURL: tempFile, response: response, error: nil
        )

        XCTAssertFalse(model.isDownloaded)
        XCTAssertTrue(model.lastDownloadError?.contains("Checksum") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: model.filePath.path))
    }

    func test_handleCompletion_checksumMatch_succeeds() throws {
        let model = makeModel(sha256: "correct_hash")

        // Override verifyChecksum to always pass
        downloader.verifyChecksum = { _, _ in true }

        let tempFile = try makeTempFile(content: "verified content")
        let response = makeOKResponse()

        downloader.handleCompletion(
            model: model, tempURL: tempFile, response: response, error: nil
        )

        XCTAssertTrue(model.isDownloaded)
        XCTAssertNil(model.lastDownloadError)
        createdFilePaths.append(model.filePath)
    }

    func test_handleCompletion_checksumMismatch_triesMirror() throws {
        let model = makeModel(
            downloadURL: URL(string: "https://example.com/m.bin"),
            sha256: "expected_hash",
            mirrorURLs: ["https://mirror.com/m.bin"]
        )
        downloader.urlIndices[model.fileName] = 0

        // Override verifyChecksum to always fail
        downloader.verifyChecksum = { _, _ in false }

        let tempFile = try makeTempFile(content: "bad hash content")
        let response = makeOKResponse()

        downloader.handleCompletion(
            model: model, tempURL: tempFile, response: response, error: nil
        )

        // Should retry with mirror after checksum failure
        XCTAssertTrue(downloader.isDownloading(model))
        XCTAssertFalse(FileManager.default.fileExists(atPath: model.filePath.path))

        downloader.cancel(model)
    }

    // MARK: - State Management

    func test_isDownloading_falseForInactiveModel() {
        let model = makeModel()
        XCTAssertFalse(downloader.isDownloading(model))
    }

    func test_cancel_clearsProgressAndState() {
        let model = makeModel()
        model.downloadProgress = 0.5

        downloader.download(model)
        XCTAssertTrue(downloader.isDownloading(model))

        downloader.cancel(model)
        XCTAssertFalse(downloader.isDownloading(model))
        XCTAssertNil(model.downloadProgress)
    }
}
