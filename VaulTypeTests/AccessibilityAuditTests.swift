import AppKit
import XCTest

@testable import VaulType

// MARK: - AccessibilityAuditTests

/// Unit tests verifying accessibility-related logic in VaulType.
///
/// Focus areas:
/// - AppState announcement methods (VoiceOver-friendly state change callbacks)
/// - AppState system preference computed properties (reduced motion, transparency, contrast)
/// - OverlayWindow transparency preference application
/// - Callable method signatures that must not crash under test conditions
@MainActor
final class AccessibilityAuditTests: XCTestCase {
    // MARK: - Properties

    private var appState: AppState!

    // MARK: - Lifecycle

    override func setUp() async throws {
        try await super.setUp()
        appState = AppState()
    }

    override func tearDown() async throws {
        appState = nil
        try await super.tearDown()
    }

    // MARK: - AppState Announcement Method Tests

    /// Calling `announceStateChange(_:)` with a non-empty string must not crash.
    func testAnnounceStateChangeDoesNotCrash() {
        // NSAccessibility.post is a no-op when VoiceOver is not running in tests,
        // but the call must complete without throwing or crashing.
        appState.announceStateChange("Test announcement")
    }

    /// Calling `announceStateChange(_:)` with an empty string must not crash.
    func testAnnounceStateChangeWithEmptyStringDoesNotCrash() {
        appState.announceStateChange("")
    }

    /// `announceRecordingStarted()` delegates to `announceStateChange` and must not crash.
    func testAnnounceRecordingStartedDoesNotCrash() {
        appState.announceRecordingStarted()
    }

    /// `announceRecordingCompleted()` delegates to `announceStateChange` and must not crash.
    func testAnnounceRecordingCompletedDoesNotCrash() {
        appState.announceRecordingCompleted()
    }

    /// `announceProcessing()` delegates to `announceStateChange` and must not crash.
    func testAnnounceProcessingDoesNotCrash() {
        appState.announceProcessing()
    }

    /// `announceProcessingComplete()` delegates to `announceStateChange` and must not crash.
    func testAnnounceProcessingCompleteDoesNotCrash() {
        appState.announceProcessingComplete()
    }

    /// `announceError(_:)` delegates to `announceStateChange` and must not crash.
    func testAnnounceErrorDoesNotCrash() {
        appState.announceError("An error occurred during transcription")
    }

    /// `announceError(_:)` called with an empty message must not crash.
    func testAnnounceErrorWithEmptyMessageDoesNotCrash() {
        appState.announceError("")
    }

    /// All announcement helpers can be called in sequence without crashing.
    func testAllAnnouncementMethodsCalledInSequenceDoNotCrash() {
        appState.announceRecordingStarted()
        appState.announceProcessing()
        appState.announceProcessingComplete()
        appState.announceRecordingCompleted()
        appState.announceError("Simulated error")
        appState.announceStateChange("Custom message")
    }

    // MARK: - AppState System Preference Tests

    /// `prefersReducedMotion` must return a Bool without crashing.
    func testPrefersReducedMotionReturnsBool() {
        let value = appState.prefersReducedMotion
        // Verify the returned value matches the live NSWorkspace value.
        let expected = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        XCTAssertEqual(
            value,
            expected,
            "prefersReducedMotion must reflect NSWorkspace.shared.accessibilityDisplayShouldReduceMotion"
        )
    }

    /// `prefersReducedTransparency` must return a Bool without crashing.
    func testPrefersReducedTransparencyReturnsBool() {
        let value = appState.prefersReducedTransparency
        let expected = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        XCTAssertEqual(
            value,
            expected,
            "prefersReducedTransparency must reflect NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency"
        )
    }

    /// `prefersHighContrast` must return a Bool without crashing.
    func testPrefersHighContrastReturnsBool() {
        let value = appState.prefersHighContrast
        let expected = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        XCTAssertEqual(
            value,
            expected,
            "prefersHighContrast must reflect NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast"
        )
    }

    /// Repeated reads of `prefersReducedMotion` return the same value (idempotent).
    func testPrefersReducedMotionIsIdempotent() {
        let first = appState.prefersReducedMotion
        let second = appState.prefersReducedMotion
        XCTAssertEqual(first, second, "Repeated reads of prefersReducedMotion should be consistent")
    }

    /// Repeated reads of `prefersReducedTransparency` return the same value (idempotent).
    func testPrefersReducedTransparencyIsIdempotent() {
        let first = appState.prefersReducedTransparency
        let second = appState.prefersReducedTransparency
        XCTAssertEqual(first, second, "Repeated reads of prefersReducedTransparency should be consistent")
    }

    /// Repeated reads of `prefersHighContrast` return the same value (idempotent).
    func testPrefersHighContrastIsIdempotent() {
        let first = appState.prefersHighContrast
        let second = appState.prefersHighContrast
        XCTAssertEqual(first, second, "Repeated reads of prefersHighContrast should be consistent")
    }

    // MARK: - OverlayWindow Transparency Preference Tests

    /// `OverlayWindow.init()` must complete without crashing.
    func testOverlayWindowInitializesWithoutCrash() {
        let window = OverlayWindow()
        XCTAssertNotNil(window, "OverlayWindow should initialize without error")
    }

    /// `applyTransparencyPreference(appState:)` must not crash when called on a fresh window.
    func testApplyTransparencyPreferenceDoesNotCrash() {
        let window = OverlayWindow()
        // Should not crash regardless of the current system transparency setting.
        window.applyTransparencyPreference(appState: appState)
    }

    /// When `prefersReducedTransparency` is simulated as true, the window becomes opaque.
    func testOverlayWindowIsOpaqueWhenReducedTransparencyActive() {
        // Only meaningful when the system pref is enabled; otherwise validate
        // that the method executes without crashing in either code path.
        let window = OverlayWindow()
        // Directly call the method and verify it does not throw.
        window.applyTransparencyPreference(appState: appState)

        if appState.prefersReducedTransparency {
            XCTAssertTrue(
                window.isOpaque,
                "OverlayWindow should be opaque when Reduce Transparency is enabled"
            )
            XCTAssertEqual(
                window.backgroundColor,
                NSColor.windowBackgroundColor,
                "Background should be windowBackgroundColor when Reduce Transparency is enabled"
            )
        } else {
            XCTAssertFalse(
                window.isOpaque,
                "OverlayWindow should be transparent when Reduce Transparency is disabled"
            )
        }
    }

    /// `OverlayWindow.canBecomeKey` must return true (required for text editing support).
    func testOverlayWindowCanBecomeKeyIsTrue() {
        let window = OverlayWindow()
        XCTAssertTrue(
            window.canBecomeKey,
            "OverlayWindow must be able to become key window for edit-before-inject support"
        )
    }

    /// `OverlayWindow.canBecomeMain` must return false (overlay must not steal main window status).
    func testOverlayWindowCanBecomeMainIsFalse() {
        let window = OverlayWindow()
        XCTAssertFalse(
            window.canBecomeMain,
            "OverlayWindow must never become the main window so it does not disrupt the active app"
        )
    }

    // MARK: - AppState State Property Tests

    /// Initial `isRecording` state is false.
    func testAppStateInitialIsRecordingIsFalse() {
        XCTAssertFalse(appState.isRecording, "isRecording should start as false")
    }

    /// Initial `isProcessing` state is false.
    func testAppStateInitialIsProcessingIsFalse() {
        XCTAssertFalse(appState.isProcessing, "isProcessing should start as false")
    }

    /// `currentError` is initially nil (no error at startup).
    func testAppStateInitialCurrentErrorIsNil() {
        XCTAssertNil(appState.currentError, "currentError should be nil at startup")
    }

    /// Setting `currentError` and then clearing it resets to nil.
    func testAppStateCurrentErrorCanBeSetAndCleared() {
        appState.currentError = "Microphone unavailable"
        XCTAssertEqual(appState.currentError, "Microphone unavailable")

        appState.currentError = nil
        XCTAssertNil(appState.currentError, "currentError should be nil after being cleared")
    }
}
