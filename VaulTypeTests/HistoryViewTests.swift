import Foundation
import SwiftData
import XCTest

@testable import VaulType

@MainActor
final class HistoryViewTests: XCTestCase {
    var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()

        let schema = Schema([
            DictationEntry.self,
            UserSettings.self,
            AppProfile.self,
            VocabularyEntry.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            XCTFail("Failed to create ModelContainer: \(error)")
            throw error
        }
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeContext() -> ModelContext {
        ModelContext(container)
    }

    // MARK: - Age-Based Cleanup Tests

    func testRunCleanupDeletesOldEntries() throws {
        let context = makeContext()

        // Insert entries older than the default retention of 90 days
        let oldDate = Date().addingTimeInterval(-100 * 24 * 60 * 60) // 100 days ago
        let oldEntry1 = DictationEntry(
            rawText: "Old entry one",
            timestamp: oldDate,
            isFavorite: false
        )
        let oldEntry2 = DictationEntry(
            rawText: "Old entry two",
            timestamp: oldDate,
            isFavorite: false
        )
        let recentEntry = DictationEntry(
            rawText: "Recent entry",
            timestamp: Date(),
            isFavorite: false
        )

        context.insert(oldEntry1)
        context.insert(oldEntry2)
        context.insert(recentEntry)
        try context.save()

        let cleanup = HistoryCleanupService(modelContainer: container)
        cleanup.runCleanup()

        let descriptor = FetchDescriptor<DictationEntry>()
        let remaining = try context.fetch(descriptor)

        // Only the recent entry should survive
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.rawText, "Recent entry")
    }

    func testRunCleanupKeepsFavorites() throws {
        let context = makeContext()

        // Insert an old favorite entry — it must not be deleted
        let oldDate = Date().addingTimeInterval(-100 * 24 * 60 * 60) // 100 days ago
        let oldFavorite = DictationEntry(
            rawText: "Old but favorited",
            timestamp: oldDate,
            isFavorite: true
        )
        let oldNormal = DictationEntry(
            rawText: "Old and not favorited",
            timestamp: oldDate,
            isFavorite: false
        )

        context.insert(oldFavorite)
        context.insert(oldNormal)
        try context.save()

        let cleanup = HistoryCleanupService(modelContainer: container)
        cleanup.runCleanup()

        let descriptor = FetchDescriptor<DictationEntry>()
        let remaining = try context.fetch(descriptor)

        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.rawText, "Old but favorited")
        XCTAssertTrue(remaining.first?.isFavorite ?? false)
    }

    // MARK: - Count-Based Cleanup Tests

    func testRunCleanupEnforcesCountLimit() throws {
        let context = makeContext()

        // Insert custom settings with a small count limit
        let settings = UserSettings(maxHistoryEntries: 3, historyRetentionDays: 0)
        context.insert(settings)

        // Insert 5 non-favorite entries with distinct timestamps
        let now = Date()
        for i in 0..<5 {
            let entry = DictationEntry(
                rawText: "Entry \(i)",
                timestamp: now.addingTimeInterval(Double(i)),
                isFavorite: false
            )
            context.insert(entry)
        }
        try context.save()

        let cleanup = HistoryCleanupService(modelContainer: container)
        cleanup.runCleanup()

        let descriptor = FetchDescriptor<DictationEntry>()
        let remaining = try context.fetch(descriptor)

        // Only the 3 newest entries should survive
        XCTAssertEqual(remaining.count, 3)
    }

    func testRunCleanupCountLimitKeepsFavorites() throws {
        let context = makeContext()

        // Limit of 2 entries, but one of the "excess" entries is a favorite
        let settings = UserSettings(maxHistoryEntries: 2, historyRetentionDays: 0)
        context.insert(settings)

        let now = Date()
        // Newest entries occupy positions 0, 1, 2 after sorting newest-first
        let newest = DictationEntry(rawText: "Newest", timestamp: now.addingTimeInterval(3), isFavorite: false)
        let second = DictationEntry(rawText: "Second", timestamp: now.addingTimeInterval(2), isFavorite: false)
        // This entry is beyond the count limit but is a favorite — must be kept
        let oldFavorite = DictationEntry(rawText: "Old Favorite", timestamp: now.addingTimeInterval(1), isFavorite: true)
        let oldest = DictationEntry(rawText: "Oldest", timestamp: now, isFavorite: false)

        context.insert(newest)
        context.insert(second)
        context.insert(oldFavorite)
        context.insert(oldest)
        try context.save()

        let cleanup = HistoryCleanupService(modelContainer: container)
        cleanup.runCleanup()

        let descriptor = FetchDescriptor<DictationEntry>()
        let remaining = try context.fetch(descriptor)

        // "Oldest" (non-favorite, beyond limit) should be deleted.
        // "Old Favorite" (favorite, beyond limit) should be kept.
        // Total remaining: newest + second + oldFavorite = 3
        XCTAssertEqual(remaining.count, 3)
        XCTAssertTrue(remaining.contains { $0.rawText == "Newest" })
        XCTAssertTrue(remaining.contains { $0.rawText == "Second" })
        XCTAssertTrue(remaining.contains { $0.rawText == "Old Favorite" })
        XCTAssertFalse(remaining.contains { $0.rawText == "Oldest" })
    }

    // MARK: - Clear All History Tests

    func testClearAllHistory() throws {
        let context = makeContext()

        for i in 0..<5 {
            let entry = DictationEntry(rawText: "Entry \(i)", isFavorite: false)
            context.insert(entry)
        }
        try context.save()

        let cleanup = HistoryCleanupService(modelContainer: container)
        cleanup.clearAllHistory()

        let descriptor = FetchDescriptor<DictationEntry>()
        let remaining = try context.fetch(descriptor)

        XCTAssertEqual(remaining.count, 0)
    }

    func testClearAllHistoryDeletesFavorites() throws {
        let context = makeContext()

        let favorite = DictationEntry(rawText: "I am a favorite", isFavorite: true)
        let normal = DictationEntry(rawText: "I am not a favorite", isFavorite: false)

        context.insert(favorite)
        context.insert(normal)
        try context.save()

        let cleanup = HistoryCleanupService(modelContainer: container)
        cleanup.clearAllHistory()

        let descriptor = FetchDescriptor<DictationEntry>()
        let remaining = try context.fetch(descriptor)

        XCTAssertEqual(remaining.count, 0, "clearAllHistory must delete favorites as well as regular entries")
    }

    // MARK: - Search Filter Logic Tests

    func testSearchFilterLogic() {
        // Mirror the filteredEntries logic from HistoryView so it can be tested
        // without spinning up a SwiftUI view.
        let entries: [DictationEntry] = [
            DictationEntry(
                rawText: "hello world dictation",
                processedText: "Hello world dictation.",
                mode: .clean,
                appName: "TextEdit"
            ),
            DictationEntry(
                rawText: "write a fibonacci function",
                processedText: "func fibonacci(_ n: Int) -> Int { ... }",
                mode: .code,
                appName: "Xcode"
            ),
            DictationEntry(
                rawText: "project status update for tomorrow",
                mode: .raw,
                appName: "Notes"
            ),
        ]

        // --- outputText match ---
        let query1 = "fibonacci"
        let result1 = entries.filter { entry in
            entry.outputText.lowercased().contains(query1)
                || entry.rawText.lowercased().contains(query1)
                || (entry.appName?.lowercased().contains(query1) ?? false)
                || entry.mode.displayName.lowercased().contains(query1)
        }
        XCTAssertEqual(result1.count, 1)
        XCTAssertEqual(result1.first?.appName, "Xcode")

        // --- rawText match ---
        let query2 = "status update"
        let result2 = entries.filter { entry in
            entry.outputText.lowercased().contains(query2)
                || entry.rawText.lowercased().contains(query2)
                || (entry.appName?.lowercased().contains(query2) ?? false)
                || entry.mode.displayName.lowercased().contains(query2)
        }
        XCTAssertEqual(result2.count, 1)
        XCTAssertEqual(result2.first?.rawText, "project status update for tomorrow")

        // --- appName match ---
        let query3 = "textedit"
        let result3 = entries.filter { entry in
            entry.outputText.lowercased().contains(query3)
                || entry.rawText.lowercased().contains(query3)
                || (entry.appName?.lowercased().contains(query3) ?? false)
                || entry.mode.displayName.lowercased().contains(query3)
        }
        XCTAssertEqual(result3.count, 1)
        XCTAssertEqual(result3.first?.appName, "TextEdit")

        // --- No match ---
        let query4 = "zzznomatch"
        let result4 = entries.filter { entry in
            entry.outputText.lowercased().contains(query4)
                || entry.rawText.lowercased().contains(query4)
                || (entry.appName?.lowercased().contains(query4) ?? false)
                || entry.mode.displayName.lowercased().contains(query4)
        }
        XCTAssertEqual(result4.count, 0)

        // --- Empty query returns all ---
        let query5 = ""
        let result5 = query5.isEmpty ? entries : entries.filter { entry in
            entry.outputText.lowercased().contains(query5)
                || entry.rawText.lowercased().contains(query5)
                || (entry.appName?.lowercased().contains(query5) ?? false)
                || entry.mode.displayName.lowercased().contains(query5)
        }
        XCTAssertEqual(result5.count, 3)
    }
}
