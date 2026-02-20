import XCTest

@testable import HushType

@MainActor
final class CommandRegistryTests: XCTestCase {

    private var registry: CommandRegistry!

    override func setUp() async throws {
        try await super.setUp()
        registry = CommandRegistry()
    }

    override func tearDown() async throws {
        registry = nil
        try await super.tearDown()
    }

    // MARK: - Built-in Registration

    func testAllBuiltInCommandsRegistered() {
        XCTAssertEqual(
            registry.entries.count,
            CommandIntent.allCases.count,
            "Registry should have exactly one entry per CommandIntent case"
        )
        XCTAssertTrue(
            registry.entries.allSatisfy { $0.isBuiltIn },
            "All default entries should be marked as built-in"
        )
    }

    func testAllCommandsEnabledByDefault() {
        XCTAssertTrue(
            registry.entries.allSatisfy { $0.isEnabled },
            "Every built-in entry should be enabled on initialisation"
        )
    }

    // MARK: - isEnabled Query

    func testIsEnabledReturnsTrue() {
        XCTAssertTrue(
            registry.isEnabled(.openApp),
            "isEnabled(.openApp) should return true for a freshly initialised registry"
        )
    }

    // MARK: - Enable / Disable

    func testDisableCommand() {
        registry.setEnabled(.openApp, enabled: false)
        XCTAssertFalse(
            registry.isEnabled(.openApp),
            "isEnabled(.openApp) should return false after setEnabled(.openApp, enabled: false)"
        )
    }

    func testReenableCommand() {
        registry.setEnabled(.openApp, enabled: false)
        registry.setEnabled(.openApp, enabled: true)
        XCTAssertTrue(
            registry.isEnabled(.openApp),
            "isEnabled(.openApp) should return true after re-enabling a disabled command"
        )
    }

    // MARK: - Category Filtering

    func testEntriesForCategory_appManagement() {
        // openApp, switchToApp, closeApp, quitApp, hideApp, showAllWindows — 6 intents
        let entries = registry.entries(for: .appManagement)
        XCTAssertEqual(entries.count, 6, "appManagement category should contain 6 entries")

        let intents = Set(entries.map { $0.intent })
        XCTAssertEqual(intents, [.openApp, .switchToApp, .closeApp, .quitApp, .hideApp, .showAllWindows])
    }

    func testEntriesForWindowCategory() {
        // moveWindowLeft, moveWindowRight, maximizeWindow, minimizeWindow,
        // centerWindow, fullScreenToggle, moveToNextScreen — 7 intents
        let entries = registry.entries(for: .windowManagement)
        XCTAssertEqual(entries.count, 7, "windowManagement category should contain 7 entries")

        let intents = Set(entries.map { $0.intent })
        XCTAssertEqual(
            intents,
            [
                .moveWindowLeft, .moveWindowRight, .maximizeWindow, .minimizeWindow,
                .centerWindow, .fullScreenToggle, .moveToNextScreen
            ]
        )
    }

    // MARK: - Custom Command Resolution

    private func makeCustomCommand(
        triggerPhrase: String,
        actions: [CommandActionStep] = [],
        isEnabled: Bool = true
    ) -> CustomCommand {
        CustomCommand(
            name: "Test Command",
            triggerPhrase: triggerPhrase,
            actions: actions,
            isEnabled: isEnabled
        )
    }

    func testResolveCustomCommandMatch() {
        let expectedActions = [CommandActionStep(intent: .openApp, parameters: ["app": "Safari"])]
        let command = makeCustomCommand(triggerPhrase: "morning setup", actions: expectedActions)

        let result = registry.resolveCustomCommand("morning setup", customCommands: [command])

        XCTAssertNotNil(result, "resolveCustomCommand should return actions when trigger phrase matches")
        XCTAssertEqual(result?.count, 1)
        XCTAssertEqual(result?.first?.intent, .openApp)
    }

    func testResolveCustomCommandCaseInsensitive() {
        let expectedActions = [CommandActionStep(intent: .switchToApp)]
        let command = makeCustomCommand(triggerPhrase: "morning setup", actions: expectedActions)

        let result = registry.resolveCustomCommand("Morning Setup", customCommands: [command])

        XCTAssertNotNil(result, "resolveCustomCommand should match case-insensitively")
        XCTAssertEqual(result?.first?.intent, .switchToApp)
    }

    func testResolveCustomCommandNoMatch() {
        let command = makeCustomCommand(triggerPhrase: "morning setup")

        let result = registry.resolveCustomCommand("something else", customCommands: [command])

        XCTAssertNil(result, "resolveCustomCommand should return nil when no trigger phrase matches")
    }

    func testResolveCustomCommandDisabled() {
        let actions = [CommandActionStep(intent: .openApp)]
        let command = makeCustomCommand(triggerPhrase: "morning setup", actions: actions, isEnabled: false)

        let result = registry.resolveCustomCommand("morning setup", customCommands: [command])

        XCTAssertNil(result, "resolveCustomCommand should return nil for a disabled custom command")
    }

    // MARK: - Persistence Round-Trip

    func testDisabledIntentRawValues() {
        registry.setEnabled(.openApp, enabled: false)
        registry.setEnabled(.lockScreen, enabled: false)

        let rawValues = registry.disabledIntentRawValues()

        XCTAssertEqual(rawValues.count, 2, "Should have exactly 2 disabled intents")
        XCTAssertTrue(rawValues.contains("openApp"), "Should contain openApp")
        XCTAssertTrue(rawValues.contains("lockScreen"), "Should contain lockScreen")
    }

    func testLoadDisabledIntentsRoundTrip() {
        // Disable some intents
        registry.setEnabled(.volumeUp, enabled: false)
        registry.setEnabled(.brightnessDown, enabled: false)

        // Capture the raw values
        let rawValues = registry.disabledIntentRawValues()

        // Create a fresh registry and load the persisted state
        let freshRegistry = CommandRegistry()
        XCTAssertTrue(freshRegistry.isEnabled(.volumeUp), "Fresh registry should have all enabled")

        freshRegistry.loadDisabledIntents(rawValues)

        XCTAssertFalse(freshRegistry.isEnabled(.volumeUp), "volumeUp should be disabled after loading")
        XCTAssertFalse(freshRegistry.isEnabled(.brightnessDown), "brightnessDown should be disabled after loading")
        XCTAssertTrue(freshRegistry.isEnabled(.openApp), "openApp should remain enabled")
        XCTAssertTrue(freshRegistry.isEnabled(.lockScreen), "lockScreen should remain enabled")
    }

    func testLoadDisabledIntentsResetsAccumulation() {
        // Load disabled intents twice — second load should reset the first
        registry.loadDisabledIntents(["openApp", "volumeUp"])
        XCTAssertFalse(registry.isEnabled(.openApp))
        XCTAssertFalse(registry.isEnabled(.volumeUp))

        // Second load with different set — openApp should be re-enabled
        registry.loadDisabledIntents(["lockScreen"])
        XCTAssertTrue(registry.isEnabled(.openApp), "openApp should be re-enabled after second load")
        XCTAssertTrue(registry.isEnabled(.volumeUp), "volumeUp should be re-enabled after second load")
        XCTAssertFalse(registry.isEnabled(.lockScreen), "lockScreen should be disabled from second load")
    }
}
