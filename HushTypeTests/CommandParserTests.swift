import XCTest

@testable import HushType

@MainActor
final class CommandParserTests: XCTestCase {
    private var parser: CommandParser!

    override func setUp() {
        super.setUp()
        parser = CommandParser()
    }

    override func tearDown() {
        parser = nil
        super.tearDown()
    }

    // MARK: - App Management Tests

    func testOpenApp() {
        let result = parser.parse("open Safari")
        XCTAssertNotNil(result, "Expected a parsed command for 'open Safari'")
        XCTAssertEqual(result?.intent, .openApp)
        XCTAssertEqual(result?.entities["appName"], "Safari")
    }

    func testLaunchApp() {
        let result = parser.parse("launch Xcode")
        XCTAssertNotNil(result, "Expected a parsed command for 'launch Xcode'")
        XCTAssertEqual(result?.intent, .openApp)
        XCTAssertEqual(result?.entities["appName"], "Xcode")
    }

    func testSwitchToApp() {
        let result = parser.parse("switch to Finder")
        XCTAssertNotNil(result, "Expected a parsed command for 'switch to Finder'")
        XCTAssertEqual(result?.intent, .switchToApp)
        XCTAssertEqual(result?.entities["appName"], "Finder")
    }

    func testCloseApp() {
        let result = parser.parse("close Terminal")
        XCTAssertNotNil(result, "Expected a parsed command for 'close Terminal'")
        XCTAssertEqual(result?.intent, .closeApp)
        XCTAssertEqual(result?.entities["appName"], "Terminal")
    }

    func testQuitApp() {
        let result = parser.parse("quit Xcode")
        XCTAssertNotNil(result, "Expected a parsed command for 'quit Xcode'")
        XCTAssertEqual(result?.intent, .quitApp)
    }

    func testHideApp() {
        let result = parser.parse("hide Finder")
        XCTAssertNotNil(result, "Expected a parsed command for 'hide Finder'")
        XCTAssertEqual(result?.intent, .hideApp)
    }

    func testShowAllWindows() {
        let result = parser.parse("show all windows")
        XCTAssertNotNil(result, "Expected a parsed command for 'show all windows'")
        XCTAssertEqual(result?.intent, .showAllWindows)
    }

    func testMissionControl() {
        let result = parser.parse("mission control")
        XCTAssertNotNil(result, "Expected a parsed command for 'mission control'")
        XCTAssertEqual(result?.intent, .showAllWindows)
    }

    // MARK: - Window Management Tests

    func testMaximizeWindow() {
        let result = parser.parse("maximize window")
        XCTAssertNotNil(result, "Expected a parsed command for 'maximize window'")
        XCTAssertEqual(result?.intent, .maximizeWindow)
    }

    func testMoveWindowLeft() {
        let result = parser.parse("move window left")
        XCTAssertNotNil(result, "Expected a parsed command for 'move window left'")
        XCTAssertEqual(result?.intent, .moveWindowLeft)
    }

    // MARK: - Volume Control Tests

    func testVolumeUp() {
        let result = parser.parse("volume up")
        XCTAssertNotNil(result, "Expected a parsed command for 'volume up'")
        XCTAssertEqual(result?.intent, .volumeUp)
    }

    func testVolumeDown() {
        let result = parser.parse("volume down")
        XCTAssertNotNil(result, "Expected a parsed command for 'volume down'")
        XCTAssertEqual(result?.intent, .volumeDown)
    }

    func testMute() {
        let result = parser.parse("mute")
        XCTAssertNotNil(result, "Expected a parsed command for 'mute'")
        XCTAssertEqual(result?.intent, .volumeMute)
    }

    func testSetVolume() {
        let result = parser.parse("volume 50")
        XCTAssertNotNil(result, "Expected a parsed command for 'volume 50'")
        XCTAssertEqual(result?.intent, .volumeSet)
        XCTAssertEqual(result?.entities["level"], "50")
    }

    // MARK: - Brightness Tests

    func testBrightnessUp() {
        let result = parser.parse("brightness up")
        XCTAssertNotNil(result, "Expected a parsed command for 'brightness up'")
        XCTAssertEqual(result?.intent, .brightnessUp)
    }

    // MARK: - System Toggle Tests

    func testDarkMode() {
        let result = parser.parse("dark mode")
        XCTAssertNotNil(result, "Expected a parsed command for 'dark mode'")
        XCTAssertEqual(result?.intent, .darkModeToggle)
    }

    func testLockScreen() {
        let result = parser.parse("lock screen")
        XCTAssertNotNil(result, "Expected a parsed command for 'lock screen'")
        XCTAssertEqual(result?.intent, .lockScreen)
    }

    func testTakeScreenshot() {
        let result = parser.parse("take screenshot")
        XCTAssertNotNil(result, "Expected a parsed command for 'take screenshot'")
        XCTAssertEqual(result?.intent, .takeScreenshot)
    }

    // MARK: - Workflow Tests

    func testRunShortcut() {
        let result = parser.parse("run shortcut Morning Routine")
        XCTAssertNotNil(result, "Expected a parsed command for 'run shortcut Morning Routine'")
        XCTAssertEqual(result?.intent, .runShortcut)
        XCTAssertEqual(result?.entities["shortcutName"], "Morning Routine")
    }

    // MARK: - Negative / Edge Case Tests

    func testUnrecognizedText() {
        let result = parser.parse("hello world foo bar")
        XCTAssertNil(result, "Expected nil for unrecognized text")
    }

    func testEmptyText() {
        let result = parser.parse("")
        XCTAssertNil(result, "Expected nil for empty string")
    }

    func testCaseInsensitive() {
        let result = parser.parse("VOLUME UP")
        XCTAssertNotNil(result, "Expected a parsed command for 'VOLUME UP' (case insensitive)")
        XCTAssertEqual(result?.intent, .volumeUp)
    }

    // MARK: - parseChain(_:) Tests

    func testSingleCommandChain() {
        let results = parser.parseChain("open Safari")
        XCTAssertEqual(results.count, 1, "Expected exactly 1 parsed command")
        XCTAssertEqual(results.first?.intent, .openApp)
    }

    func testChainWithAnd() {
        let results = parser.parseChain("open Safari and volume up")
        XCTAssertEqual(results.count, 2, "Expected 2 parsed commands when chained with 'and'")
        XCTAssertEqual(results[0].intent, .openApp)
        XCTAssertEqual(results[1].intent, .volumeUp)
    }

    func testChainWithThen() {
        let results = parser.parseChain("mute then dark mode")
        XCTAssertEqual(results.count, 2, "Expected 2 parsed commands when chained with 'then'")
        XCTAssertEqual(results[0].intent, .volumeMute)
        XCTAssertEqual(results[1].intent, .darkModeToggle)
    }

    func testNoChainForNonCommand() {
        // "and cheese" should not be split because "cheese" is not a command verb
        let results = parser.parseChain("open Safari and cheese")
        XCTAssertEqual(results.count, 1, "Expected 1 command — 'cheese' is not a recognized verb so no split should occur")
        XCTAssertEqual(results.first?.intent, .openApp)
    }
}
