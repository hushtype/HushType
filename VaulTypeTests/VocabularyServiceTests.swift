import Foundation
import SwiftData
import XCTest

@testable import VaulType

@MainActor
final class VocabularyServiceTests: XCTestCase {
    private var modelContainer: ModelContainer!
    private var modelContext: ModelContext!

    override func setUp() async throws {
        try await super.setUp()

        let schema = Schema([
            VocabularyEntry.self,
            AppProfile.self,
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

    // MARK: - Helper

    private func makeEntry(
        spokenForm: String,
        replacement: String,
        caseSensitive: Bool = false,
        isGlobal: Bool = true,
        appProfile: AppProfile? = nil
    ) -> VocabularyEntry {
        let entry = VocabularyEntry(
            spokenForm: spokenForm,
            replacement: replacement,
            isGlobal: isGlobal,
            caseSensitive: caseSensitive,
            appProfile: appProfile
        )
        modelContext.insert(entry)
        return entry
    }

    // MARK: - Tests

    func testNoReplacements() {
        let result = VocabularyService.apply(
            to: "hello world",
            globalEntries: [],
            appEntries: []
        )

        XCTAssertEqual(result, "hello world")
    }

    func testGlobalReplacement() {
        let global = makeEntry(spokenForm: "jay son", replacement: "JSON")

        let result = VocabularyService.apply(
            to: "parse jay son data",
            globalEntries: [global],
            appEntries: []
        )

        XCTAssertEqual(result, "parse JSON data")
    }

    func testAppEntryAppliedFirst() {
        // App entry replaces "xcode" before global has a chance to run on the original.
        let appEntry = makeEntry(spokenForm: "ecks code", replacement: "Xcode", isGlobal: false)
        let globalEntry = makeEntry(spokenForm: "jay son", replacement: "JSON")

        let result = VocabularyService.apply(
            to: "open ecks code and parse jay son",
            globalEntries: [globalEntry],
            appEntries: [appEntry]
        )

        XCTAssertEqual(result, "open Xcode and parse JSON")
    }

    func testCaseSensitiveReplacement() {
        // caseSensitive=true: "json" should NOT match "JSON"
        let entry = makeEntry(spokenForm: "json", replacement: "REPLACED", caseSensitive: true)

        let result = VocabularyService.apply(
            to: "parse JSON data",
            globalEntries: [entry],
            appEntries: []
        )

        XCTAssertEqual(result, "parse JSON data", "Case-sensitive match on wrong case should not replace")
    }

    func testCaseInsensitiveReplacement() {
        // caseSensitive=false: "json" should match "JSON"
        let entry = makeEntry(spokenForm: "json", replacement: "JSON", caseSensitive: false)

        let result = VocabularyService.apply(
            to: "parse json data",
            globalEntries: [entry],
            appEntries: []
        )

        XCTAssertEqual(result, "parse JSON data")
    }

    func testMultipleReplacements() {
        let entry1 = makeEntry(spokenForm: "jay son", replacement: "JSON")
        let entry2 = makeEntry(spokenForm: "ecks code", replacement: "Xcode")

        let result = VocabularyService.apply(
            to: "open ecks code and parse jay son",
            globalEntries: [entry1, entry2],
            appEntries: []
        )

        XCTAssertEqual(result, "open Xcode and parse JSON")
    }

    func testAppOverridesGlobal() {
        // App entry is applied first, so the global entry never sees the original spoken form.
        let appEntry = makeEntry(
            spokenForm: "jay son",
            replacement: "JSON (app-specific)",
            isGlobal: false
        )
        let globalEntry = makeEntry(
            spokenForm: "jay son",
            replacement: "JSON (global)"
        )

        let result = VocabularyService.apply(
            to: "parse jay son data",
            globalEntries: [globalEntry],
            appEntries: [appEntry]
        )

        // The app entry fires first, replacing "jay son" with "JSON (app-specific)".
        // The global entry then tries to match "jay son" in the already-replaced text, finds none.
        XCTAssertEqual(result, "parse JSON (app-specific) data")
        XCTAssertFalse(result.contains("global"), "Global replacement should not win when app entry matches first")
    }

    func testEmptyText() {
        let entry = makeEntry(spokenForm: "jay son", replacement: "JSON")

        let result = VocabularyService.apply(
            to: "",
            globalEntries: [entry],
            appEntries: []
        )

        XCTAssertEqual(result, "")
    }
}
