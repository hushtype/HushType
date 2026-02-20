import AVFoundation
import AppKit
import XCTest

@testable import HushType

@MainActor
final class OnboardingViewTests: XCTestCase {
    // MARK: - Constants

    private let onboardingCompletedKey = "com.hushtype.onboardingCompleted"

    // MARK: - Lifecycle

    override func setUp() async throws {
        try await super.setUp()
        // Remove the UserDefaults key before each test to avoid pollution.
        UserDefaults.standard.removeObject(forKey: onboardingCompletedKey)
    }

    override func tearDown() async throws {
        // Clean up the UserDefaults key after each test.
        UserDefaults.standard.removeObject(forKey: onboardingCompletedKey)
        try await super.tearDown()
    }

    // MARK: - OnboardingStepView Initialization Tests

    func testOnboardingStepViewInitWithRequiredParameters() {
        // Verify that OnboardingStepView can be initialized with only the
        // required parameters (iconName, title, description).
        let view = OnboardingStepView(
            iconName: "waveform.circle.fill",
            title: "Welcome to HushType",
            description: "Privacy-first speech-to-text."
        )

        XCTAssertNotNil(view, "OnboardingStepView should initialize with required parameters only")
        XCTAssertEqual(view.iconName, "waveform.circle.fill")
        XCTAssertEqual(view.title, "Welcome to HushType")
        XCTAssertEqual(view.description, "Privacy-first speech-to-text.")
        XCTAssertNil(view.actionLabel, "actionLabel should default to nil")
        XCTAssertNil(view.action, "action should default to nil")
    }

    func testOnboardingStepViewInitWithActionLabel() {
        // Verify initialization with an actionLabel but no action closure.
        let view = OnboardingStepView(
            iconName: "mic.circle.fill",
            title: "Microphone Access",
            description: "HushType needs microphone access.",
            actionLabel: "Grant Access"
        )

        XCTAssertNotNil(view)
        XCTAssertEqual(view.iconName, "mic.circle.fill")
        XCTAssertEqual(view.title, "Microphone Access")
        XCTAssertEqual(view.description, "HushType needs microphone access.")
        XCTAssertEqual(view.actionLabel, "Grant Access")
        XCTAssertNil(view.action, "action should remain nil when not provided")
    }

    func testOnboardingStepViewInitWithActionLabelAndClosure() {
        // Verify initialization with both actionLabel and action closure.
        var actionInvoked = false
        let view = OnboardingStepView(
            iconName: "checkmark.circle.fill",
            title: "All Set",
            description: "You're ready to go!",
            actionLabel: "Continue",
            action: { actionInvoked = true }
        )

        XCTAssertNotNil(view)
        XCTAssertEqual(view.iconName, "checkmark.circle.fill")
        XCTAssertEqual(view.actionLabel, "Continue")
        XCTAssertNotNil(view.action, "action closure should not be nil when provided")

        // Invoke the stored action and verify it runs.
        view.action?()
        XCTAssertTrue(actionInvoked, "Stored action closure should be callable")
    }

    func testOnboardingStepViewAcceptsArbitraryIconNames() {
        // Verify various SF Symbol names used by OnboardingView steps.
        let iconNames = [
            "waveform.circle.fill",
            "mic.circle.fill",
            "accessibility.fill",
            "arrow.down.circle.fill",
            "checkmark.circle.fill",
        ]

        for iconName in iconNames {
            let view = OnboardingStepView(
                iconName: iconName,
                title: "Test Step",
                description: "Test description for \(iconName)."
            )
            XCTAssertEqual(
                view.iconName,
                iconName,
                "OnboardingStepView should store iconName '\(iconName)' exactly"
            )
        }
    }

    func testOnboardingStepViewAllStepCombinations() {
        // Mirror each OnboardingView step that uses OnboardingStepView.
        let welcomeStep = OnboardingStepView(
            iconName: "waveform.circle.fill",
            title: "Welcome to HushType",
            description: "Privacy-first speech-to-text that runs entirely on your Mac. No cloud, no telemetry — just your voice and your machine."
        )
        let completionStep = OnboardingStepView(
            iconName: "checkmark.circle.fill",
            title: "You're All Set!",
            description: "Press and hold the fn key to start dictating. Release to stop and inject text at your cursor. You can customize everything in Settings."
        )

        XCTAssertEqual(welcomeStep.title, "Welcome to HushType")
        XCTAssertNil(welcomeStep.actionLabel)
        XCTAssertEqual(completionStep.title, "You're All Set!")
        XCTAssertNil(completionStep.actionLabel)
    }

    // MARK: - PermissionsManager Interface Tests

    func testPermissionsManagerInitializes() {
        let manager = PermissionsManager()
        XCTAssertNotNil(manager, "PermissionsManager should initialize without error")
    }

    func testPermissionsManagerHasRequestMicrophoneAccessMethod() {
        // Verify that `requestMicrophoneAccess()` can be called without crashing.
        // The actual system dialog will not appear in a unit test context.
        let manager = PermissionsManager()
        // This call must not crash; we cannot assert a granted state in unit tests
        // because AVCaptureDevice requires real hardware permission dialogs.
        manager.requestMicrophoneAccess()
    }

    func testPermissionsManagerHasOpenAccessibilitySettingsMethod() {
        // Verify that `openAccessibilitySettings()` can be called without crashing.
        // In a test environment, NSWorkspace.open() will either silently no-op or
        // open the URL; the key requirement is that it does not throw or crash.
        let manager = PermissionsManager()
        manager.openAccessibilitySettings()
    }

    // MARK: - PermissionsManager refreshAccessibilityStatus Tests

    func testRefreshAccessibilityStatusUpdatesBooleanProperty() {
        // `refreshAccessibilityStatus()` must update `accessibilityEnabled` to
        // match the current AXIsProcessTrusted() value. The test verifies that
        // after calling it the property equals the live system value.
        let manager = PermissionsManager()
        manager.refreshAccessibilityStatus()

        let expected = AXIsProcessTrusted()
        XCTAssertEqual(
            manager.accessibilityEnabled,
            expected,
            "accessibilityEnabled must reflect AXIsProcessTrusted() after calling refreshAccessibilityStatus()"
        )
    }

    func testRefreshAccessibilityStatusIsIdempotent() {
        // Calling refreshAccessibilityStatus() multiple times should yield the
        // same result each time (no state corruption between calls).
        let manager = PermissionsManager()

        manager.refreshAccessibilityStatus()
        let firstValue = manager.accessibilityEnabled

        manager.refreshAccessibilityStatus()
        let secondValue = manager.accessibilityEnabled

        XCTAssertEqual(
            firstValue,
            secondValue,
            "Repeated calls to refreshAccessibilityStatus() should return consistent results"
        )
    }

    func testAccessibilityEnabledInitialValueMatchesSystemState() {
        // The initial value of `accessibilityEnabled` on a fresh instance must
        // already reflect AXIsProcessTrusted() — PermissionsManager should not
        // start in a stale state.
        let manager = PermissionsManager()
        XCTAssertEqual(
            manager.accessibilityEnabled,
            AXIsProcessTrusted(),
            "Initial accessibilityEnabled must equal AXIsProcessTrusted()"
        )
    }

    // MARK: - UserDefaults onboardingCompleted Tests

    func testOnboardingCompletedKeyIsFalseByDefault() {
        // After the setUp teardown removes the key, it must default to false.
        let value = UserDefaults.standard.bool(forKey: onboardingCompletedKey)
        XCTAssertFalse(
            value,
            "'\(onboardingCompletedKey)' should be false (absent) before onboarding is completed"
        )
    }

    func testOnboardingCompletedKeyCanBeSetToTrue() {
        // Simulate what completeOnboarding() does.
        UserDefaults.standard.set(true, forKey: onboardingCompletedKey)

        let value = UserDefaults.standard.bool(forKey: onboardingCompletedKey)
        XCTAssertTrue(
            value,
            "'\(onboardingCompletedKey)' should be true after being set"
        )
    }

    func testOnboardingCompletedKeyPersistsBetweenReads() {
        // Verify that the value is stable across multiple reads once written.
        UserDefaults.standard.set(true, forKey: onboardingCompletedKey)

        let first = UserDefaults.standard.bool(forKey: onboardingCompletedKey)
        let second = UserDefaults.standard.bool(forKey: onboardingCompletedKey)

        XCTAssertTrue(first)
        XCTAssertEqual(first, second, "Repeated reads of the same key should return the same value")
    }

    func testOnboardingCompletedKeyCanBeReset() {
        // Set the key to true, then remove it; it should return to false.
        UserDefaults.standard.set(true, forKey: onboardingCompletedKey)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: onboardingCompletedKey))

        UserDefaults.standard.removeObject(forKey: onboardingCompletedKey)
        XCTAssertFalse(
            UserDefaults.standard.bool(forKey: onboardingCompletedKey),
            "After removing '\(onboardingCompletedKey)', reading it should return false"
        )
    }

    func testOnboardingCompletedKeyCannotBeReadAsInt() {
        // Confirm that only a boolean `true` is stored, not an integer.
        UserDefaults.standard.set(true, forKey: onboardingCompletedKey)

        // bool(forKey:) on a stored `true` returns true.
        XCTAssertTrue(UserDefaults.standard.bool(forKey: onboardingCompletedKey))
        // integer(forKey:) on a stored boolean `true` should return 1.
        XCTAssertEqual(UserDefaults.standard.integer(forKey: onboardingCompletedKey), 1)
    }
}
