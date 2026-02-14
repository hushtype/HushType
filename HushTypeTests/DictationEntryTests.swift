import Foundation
import SwiftData
import XCTest

@testable import HushType

final class DictationEntryTests: XCTestCase {
    private var modelContainer: ModelContainer!
    private var modelContext: ModelContext!

    override func setUp() async throws {
        try await super.setUp()

        // Create in-memory model container for testing
        let schema = Schema([
            DictationEntry.self,
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

    // MARK: - Initialization Tests

    func testInit() {
        let entry = DictationEntry(
            rawText: "Hello world",
            mode: .raw,
            language: "en"
        )

        XCTAssertNotNil(entry.id)
        XCTAssertEqual(entry.rawText, "Hello world")
        XCTAssertNil(entry.processedText)
        XCTAssertEqual(entry.mode, .raw)
        XCTAssertEqual(entry.language, "en")
        XCTAssertNil(entry.appBundleIdentifier)
        XCTAssertNil(entry.appName)
        XCTAssertEqual(entry.audioDuration, 0)
        XCTAssertEqual(entry.wordCount, 0)
        XCTAssertFalse(entry.isFavorite)
        XCTAssertNotNil(entry.timestamp)
    }

    func testInitWithAllParameters() {
        let timestamp = Date()
        let entry = DictationEntry(
            id: UUID(),
            rawText: "Raw transcription",
            processedText: "Processed transcription",
            mode: .clean,
            language: "tr",
            appBundleIdentifier: "com.apple.TextEdit",
            appName: "TextEdit",
            audioDuration: 5.0,
            wordCount: 3,
            timestamp: timestamp,
            isFavorite: true
        )

        XCTAssertNotNil(entry.id)
        XCTAssertEqual(entry.rawText, "Raw transcription")
        XCTAssertEqual(entry.processedText, "Processed transcription")
        XCTAssertEqual(entry.mode, .clean)
        XCTAssertEqual(entry.language, "tr")
        XCTAssertEqual(entry.appBundleIdentifier, "com.apple.TextEdit")
        XCTAssertEqual(entry.appName, "TextEdit")
        XCTAssertEqual(entry.audioDuration, 5.0)
        XCTAssertEqual(entry.wordCount, 3)
        XCTAssertEqual(entry.timestamp, timestamp)
        XCTAssertTrue(entry.isFavorite)
    }

    // MARK: - Output Text Tests

    func testOutputText() {
        // When processedText is nil, should return rawText
        let entry = DictationEntry(
            rawText: "Hello world",
            processedText: nil,
            mode: .raw
        )

        XCTAssertEqual(entry.outputText, "Hello world")
    }

    func testOutputTextWithProcessed() {
        // When processedText is set, should return processedText
        let entry = DictationEntry(
            rawText: "hello world",
            processedText: "Hello world!",
            mode: .clean
        )

        XCTAssertEqual(entry.outputText, "Hello world!")
    }

    func testOutputTextPriorityProcessedOverRaw() {
        // processedText should take priority over rawText
        let entry = DictationEntry(
            rawText: "raw version",
            processedText: "processed version",
            mode: .clean
        )

        XCTAssertEqual(entry.outputText, "processed version")
        XCTAssertNotEqual(entry.outputText, entry.rawText)
    }

    // MARK: - Words Per Minute Tests

    func testWordsPerMinute() {
        // 100 words in 60 seconds = 100 WPM
        let entry = DictationEntry(
            rawText: "test",
            audioDuration: 60.0,
            wordCount: 100
        )

        XCTAssertEqual(entry.wordsPerMinute, 100.0, accuracy: 0.01)
    }

    func testWordsPerMinuteZeroDuration() {
        // Zero duration should return 0 WPM
        let entry = DictationEntry(
            rawText: "test",
            audioDuration: 0.0,
            wordCount: 100
        )

        XCTAssertEqual(entry.wordsPerMinute, 0.0)
    }

    func testWordsPerMinuteVariousDurations() {
        // Test various durations
        let testCases: [(duration: TimeInterval, wordCount: Int, expectedWPM: Double)] = [
            (30.0, 50, 100.0),  // 50 words in 30 seconds = 100 WPM
            (120.0, 200, 100.0),  // 200 words in 120 seconds = 100 WPM
            (15.0, 25, 100.0),  // 25 words in 15 seconds = 100 WPM
            (60.0, 150, 150.0),  // 150 words in 60 seconds = 150 WPM
            (60.0, 50, 50.0),  // 50 words in 60 seconds = 50 WPM
        ]

        for (duration, wordCount, expectedWPM) in testCases {
            let entry = DictationEntry(
                rawText: "test",
                audioDuration: duration,
                wordCount: wordCount
            )

            XCTAssertEqual(entry.wordsPerMinute, expectedWPM, accuracy: 0.01, "Failed for duration: \(duration), words: \(wordCount)")
        }
    }

    func testWordsPerMinuteZeroWords() {
        // Zero words should return 0 WPM even with non-zero duration
        let entry = DictationEntry(
            rawText: "test",
            audioDuration: 60.0,
            wordCount: 0
        )

        XCTAssertEqual(entry.wordsPerMinute, 0.0)
    }

    // MARK: - SwiftData Persistence Tests

    func testPersistence() throws {
        let entry = DictationEntry(
            rawText: "Persist this text",
            processedText: "Processed text",
            mode: .clean,
            language: "en",
            appBundleIdentifier: "com.example.app",
            appName: "Example App",
            audioDuration: 3.5,
            wordCount: 3,
            isFavorite: true
        )

        // Insert into context
        modelContext.insert(entry)

        // Save context
        try modelContext.save()

        // Fetch all entries
        let descriptor = FetchDescriptor<DictationEntry>()
        let entries = try modelContext.fetch(descriptor)

        XCTAssertEqual(entries.count, 1)

        guard let fetchedEntry = entries.first else {
            XCTFail("No entry fetched")
            return
        }

        XCTAssertEqual(fetchedEntry.id, entry.id)
        XCTAssertEqual(fetchedEntry.rawText, "Persist this text")
        XCTAssertEqual(fetchedEntry.processedText, "Processed text")
        XCTAssertEqual(fetchedEntry.mode, .clean)
        XCTAssertEqual(fetchedEntry.language, "en")
        XCTAssertEqual(fetchedEntry.appBundleIdentifier, "com.example.app")
        XCTAssertEqual(fetchedEntry.appName, "Example App")
        XCTAssertEqual(fetchedEntry.audioDuration, 3.5)
        XCTAssertEqual(fetchedEntry.wordCount, 3)
        XCTAssertTrue(fetchedEntry.isFavorite)
    }

    func testMultipleEntries() throws {
        // Create multiple entries
        let entry1 = DictationEntry(rawText: "First entry", mode: .raw)
        let entry2 = DictationEntry(rawText: "Second entry", mode: .clean)
        let entry3 = DictationEntry(rawText: "Third entry", mode: .code)

        modelContext.insert(entry1)
        modelContext.insert(entry2)
        modelContext.insert(entry3)

        try modelContext.save()

        // Fetch all entries
        let descriptor = FetchDescriptor<DictationEntry>()
        let entries = try modelContext.fetch(descriptor)

        XCTAssertEqual(entries.count, 3)
    }

    func testUpdateEntry() throws {
        let entry = DictationEntry(rawText: "Original text", isFavorite: false)

        modelContext.insert(entry)
        try modelContext.save()

        // Update the entry
        entry.isFavorite = true
        entry.processedText = "Updated processed text"
        entry.wordCount = 5

        try modelContext.save()

        // Fetch and verify
        let descriptor = FetchDescriptor<DictationEntry>(
            predicate: #Predicate { $0.id == entry.id }
        )
        let entries = try modelContext.fetch(descriptor)

        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entries.first?.isFavorite ?? false)
        XCTAssertEqual(entries.first?.processedText, "Updated processed text")
        XCTAssertEqual(entries.first?.wordCount, 5)
    }

    func testDeleteEntry() throws {
        let entry = DictationEntry(rawText: "To be deleted")

        modelContext.insert(entry)
        try modelContext.save()

        // Delete the entry
        modelContext.delete(entry)
        try modelContext.save()

        // Verify deletion
        let descriptor = FetchDescriptor<DictationEntry>()
        let entries = try modelContext.fetch(descriptor)

        XCTAssertEqual(entries.count, 0)
    }

    func testQueryByMode() throws {
        // Create entries with different modes
        let rawEntry = DictationEntry(rawText: "Raw entry", mode: .raw)
        let cleanEntry = DictationEntry(rawText: "Clean entry", mode: .clean)
        let codeEntry = DictationEntry(rawText: "Code entry", mode: .code)

        modelContext.insert(rawEntry)
        modelContext.insert(cleanEntry)
        modelContext.insert(codeEntry)
        try modelContext.save()

        // Query for clean mode entries
        let descriptor = FetchDescriptor<DictationEntry>(
            predicate: #Predicate { $0.mode == .clean }
        )
        let cleanEntries = try modelContext.fetch(descriptor)

        XCTAssertEqual(cleanEntries.count, 1)
        XCTAssertEqual(cleanEntries.first?.mode, .clean)
    }

    func testQueryByFavorite() throws {
        let favorite1 = DictationEntry(rawText: "Favorite 1", isFavorite: true)
        let favorite2 = DictationEntry(rawText: "Favorite 2", isFavorite: true)
        let normal = DictationEntry(rawText: "Normal", isFavorite: false)

        modelContext.insert(favorite1)
        modelContext.insert(favorite2)
        modelContext.insert(normal)
        try modelContext.save()

        // Query for favorites
        let descriptor = FetchDescriptor<DictationEntry>(
            predicate: #Predicate { $0.isFavorite == true }
        )
        let favorites = try modelContext.fetch(descriptor)

        XCTAssertEqual(favorites.count, 2)
        XCTAssertTrue(favorites.allSatisfy { $0.isFavorite })
    }

    func testSortByTimestamp() throws {
        // Create entries with different timestamps
        let now = Date()
        let entry1 = DictationEntry(rawText: "First", timestamp: now.addingTimeInterval(-100))
        let entry2 = DictationEntry(rawText: "Second", timestamp: now.addingTimeInterval(-50))
        let entry3 = DictationEntry(rawText: "Third", timestamp: now)

        modelContext.insert(entry1)
        modelContext.insert(entry2)
        modelContext.insert(entry3)
        try modelContext.save()

        // Fetch sorted by timestamp descending (newest first)
        let descriptor = FetchDescriptor<DictationEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let entries = try modelContext.fetch(descriptor)

        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].rawText, "Third")
        XCTAssertEqual(entries[1].rawText, "Second")
        XCTAssertEqual(entries[2].rawText, "First")
    }
}
