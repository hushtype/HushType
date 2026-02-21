import AppKit
import XCTest

@testable import VaulType

@MainActor
final class OverlayWindowTests: XCTestCase {
    // MARK: - Lifecycle

    override func setUp() async throws {
        try await super.setUp()
    }

    override func tearDown() async throws {
        try await super.tearDown()
    }

    // MARK: - Initialization Tests

    func testOverlayInitNotVisible() {
        let window = OverlayWindow()

        XCTAssertFalse(window.isVisible, "A newly created OverlayWindow should not be visible")
    }

    // MARK: - Show / Hide Tests

    func testShowAndHideOverlay() {
        let window = OverlayWindow()

        window.showOverlay()
        XCTAssertTrue(window.isVisible, "showOverlay() should make the window visible")

        window.hideOverlay()
        XCTAssertFalse(window.isVisible, "hideOverlay() should hide the window")
    }

    // MARK: - Position Enum Tests

    func testOverlayPositionEnum() {
        // Verify every Position case has a non-empty displayName
        for position in OverlayWindow.Position.allCases {
            XCTAssertFalse(
                position.displayName.isEmpty,
                "Position.\(position.rawValue) must have a non-empty displayName"
            )
        }

        // Spot-check specific expected display names
        XCTAssertEqual(OverlayWindow.Position.nearCursor.displayName, "Near Cursor")
        XCTAssertEqual(OverlayWindow.Position.topCenter.displayName, "Top Center")
        XCTAssertEqual(OverlayWindow.Position.bottomCenter.displayName, "Bottom Center")
        XCTAssertEqual(OverlayWindow.Position.center.displayName, "Center")
    }

    func testOverlayPositionAllCasesCount() {
        XCTAssertEqual(
            OverlayWindow.Position.allCases.count, 4,
            "OverlayWindow.Position should have exactly 4 cases"
        )
    }

    // MARK: - Key / Main Window Tests

    func testOverlayCanBecomeKey() {
        let window = OverlayWindow()

        XCTAssertTrue(
            window.canBecomeKey,
            "OverlayWindow must be able to become key window to support text editing"
        )
    }

    func testOverlayCannotBecomeMain() {
        let window = OverlayWindow()

        XCTAssertFalse(
            window.canBecomeMain,
            "OverlayWindow must not become the main window"
        )
    }

    // MARK: - AppState Overlay Property Tests

    func testAppStateOverlayProperties() {
        let appState = AppState()

        XCTAssertNil(appState.overlayText, "overlayText should default to nil")
        XCTAssertFalse(appState.showOverlay, "showOverlay should default to false")
        XCTAssertNil(appState.detectedLanguage, "detectedLanguage should default to nil")
        XCTAssertNil(appState.overlayEditedText, "overlayEditedText should default to nil")
        XCTAssertFalse(appState.overlayEditConfirmed, "overlayEditConfirmed should default to false")
        XCTAssertFalse(appState.overlayEditCancelled, "overlayEditCancelled should default to false")
    }
}
