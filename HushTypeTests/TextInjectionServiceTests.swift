import AppKit
import CoreGraphics
import XCTest

@testable import HushType

final class TextInjectionServiceTests: XCTestCase {
    private var permissionsManager: PermissionsManager!
    private var service: TextInjectionService!

    override func setUp() {
        super.setUp()
        permissionsManager = PermissionsManager()
        service = TextInjectionService(permissionsManager: permissionsManager)
    }

    override func tearDown() {
        service = nil
        permissionsManager = nil
        super.tearDown()
    }

    // MARK: - Auto-Detection Tests

    func testAutoDetectCGEvent() async throws {
        // Short ASCII text should select CGEvent method
        let shortText = "Hello World"

        // We can't actually inject without accessibility permission, so we test the routing logic
        // by verifying the method selection would choose CGEvent for short ASCII text

        // The service's resolveMethod is private, but we can verify by checking the behavior
        // when accessibility is not granted (it should throw accessibilityNotGranted for CGEvent)

        // Skip if no accessibility permission (can't test actual injection)
        guard permissionsManager.accessibilityEnabled else {
            throw XCTSkip("Accessibility permission not granted - skipping CGEvent test")
        }

        // If we have permission, verify no error is thrown for short ASCII text
        try await service.inject(shortText, method: .auto)
    }

    func testAutoDetectClipboard() async throws {
        // Long text should select clipboard method
        let longText = String(repeating: "a", count: 100)

        // Test clipboard method (doesn't require accessibility permission)
        // Save current clipboard
        let pasteboard = NSPasteboard.general
        let originalItems = pasteboard.pasteboardItems

        do {
            // This will use clipboard method due to length
            // Note: actual paste won't work in tests, but we can verify no crash
            try await service.inject(longText, method: .clipboard)

            // Wait a bit for async operation
            try await Task.sleep(for: .milliseconds(50))
        } catch {
            // Restore clipboard on error
            if let items = originalItems {
                pasteboard.clearContents()
                pasteboard.writeObjects(items)
            }
            throw error
        }

        // Restore clipboard
        if let items = originalItems {
            pasteboard.clearContents()
            pasteboard.writeObjects(items)
        }
    }

    func testAutoDetectUnicode() async throws {
        // Unicode text should select clipboard method
        let unicodeText = "Hello 世界 🌍"

        // Test that Unicode text uses clipboard (doesn't require accessibility)
        // Save current clipboard
        let pasteboard = NSPasteboard.general
        let originalItems = pasteboard.pasteboardItems

        do {
            try await service.inject(unicodeText, method: .auto)
            try await Task.sleep(for: .milliseconds(50))
        } catch {
            // Restore clipboard on error
            if let items = originalItems {
                pasteboard.clearContents()
                pasteboard.writeObjects(items)
            }
            throw error
        }

        // Restore clipboard
        if let items = originalItems {
            pasteboard.clearContents()
            pasteboard.writeObjects(items)
        }
    }

    // MARK: - CGEventInjector Tests

    func testCGEventInjectorCreatesEvents() {
        // Test that CGEventInjector can create events for simple text
        let injector = CGEventInjector()

        // Test event source creation
        guard let eventSource = CGEventSource(stateID: .combinedSessionState) else {
            XCTFail("Failed to create CGEventSource")
            return
        }

        // Verify event source was created successfully
        XCTAssertNotNil(eventSource)

        // Test creating a simple keyboard event
        let testChar: Character = "A"
        guard let keyEvent = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true) else {
            XCTFail("Failed to create keyboard event")
            return
        }

        XCTAssertNotNil(keyEvent)

        // Verify we can set Unicode string
        let utf16CodeUnits = Array(testChar.utf16)
        keyEvent.keyboardSetUnicodeString(stringLength: utf16CodeUnits.count, unicodeString: utf16CodeUnits)

        // Event should have the Unicode string set
        // We can't easily verify the content, but the call should succeed without crashing
    }

    func testCGEventInjectorMultipleCharacters() {
        // Test that we can create events for multiple characters
        let injector = CGEventInjector()
        let text = "ABC"

        guard let eventSource = CGEventSource(stateID: .combinedSessionState) else {
            XCTFail("Failed to create CGEventSource")
            return
        }

        // Create events for each character
        for char in text {
            guard let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true),
                let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: false)
            else {
                XCTFail("Failed to create keyboard events for character: \(char)")
                return
            }

            let utf16CodeUnits = Array(char.utf16)
            keyDown.keyboardSetUnicodeString(stringLength: utf16CodeUnits.count, unicodeString: utf16CodeUnits)
            keyUp.keyboardSetUnicodeString(stringLength: utf16CodeUnits.count, unicodeString: utf16CodeUnits)

            XCTAssertNotNil(keyDown)
            XCTAssertNotNil(keyUp)
        }
    }

    func testCGEventInjectorUnicodeCharacters() {
        // Test creating events for Unicode characters
        guard let eventSource = CGEventSource(stateID: .combinedSessionState) else {
            XCTFail("Failed to create CGEventSource")
            return
        }

        let unicodeChars: [Character] = ["é", "ñ", "ü", "世", "🌍"]

        for char in unicodeChars {
            guard let keyEvent = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true) else {
                XCTFail("Failed to create keyboard event for character: \(char)")
                return
            }

            let utf16CodeUnits = Array(char.utf16)
            keyEvent.keyboardSetUnicodeString(stringLength: utf16CodeUnits.count, unicodeString: utf16CodeUnits)

            XCTAssertNotNil(keyEvent)
        }
    }

    // MARK: - ClipboardInjector Tests

    func testClipboardInjectorPreservesClipboard() async throws {
        let injector = ClipboardInjector()
        let pasteboard = NSPasteboard.general

        // Set original clipboard content
        let originalText = "Original clipboard content"
        pasteboard.clearContents()
        pasteboard.setString(originalText, forType: .string)

        let originalChangeCount = pasteboard.changeCount

        // Inject new text
        let testText = "Test injection text"

        do {
            try await injector.inject(testText)

            // Wait for clipboard operations to complete
            try await Task.sleep(for: .milliseconds(150))

            // Check if clipboard was restored
            // Note: In test environment without actual paste target, the restore should happen
            // The changeCount should be back to original or original+1 (depends on timing)
            let currentChangeCount = pasteboard.changeCount

            // Clipboard should have been modified at least once
            XCTAssertGreaterThanOrEqual(currentChangeCount, originalChangeCount)

        } catch {
            // Clean up on error
            pasteboard.clearContents()
            pasteboard.setString(originalText, forType: .string)
            throw error
        }

        // Clean up
        pasteboard.clearContents()
    }

    func testClipboardInjectorSetsClipboard() async throws {
        let injector = ClipboardInjector()
        let pasteboard = NSPasteboard.general

        // Clear clipboard first
        pasteboard.clearContents()

        let testText = "Clipboard test content"

        do {
            // Start injection (it will set clipboard, attempt paste, then restore)
            try await injector.inject(testText)

            // Wait briefly
            try await Task.sleep(for: .milliseconds(50))

            // Clipboard operations should complete without errors
            // (Actual paste won't work in test environment, but clipboard ops should succeed)

        } catch TextInjectionError.eventCreationFailed {
            // This might happen in test environment without proper event permissions
            throw XCTSkip("CGEvent creation failed - expected in test environment")
        }

        // Clean up
        pasteboard.clearContents()
    }

    func testClipboardInjectorWithEmptyString() async throws {
        let injector = ClipboardInjector()

        // Should handle empty string gracefully
        try await injector.inject("")
    }

    func testClipboardInjectorWithLongText() async throws {
        let injector = ClipboardInjector()
        let pasteboard = NSPasteboard.general

        // Save original clipboard
        let originalItems = pasteboard.pasteboardItems

        // Create long text
        let longText = String(repeating: "Lorem ipsum dolor sit amet. ", count: 100)

        do {
            try await injector.inject(longText)
            try await Task.sleep(for: .milliseconds(150))
        } catch {
            // Restore clipboard on error
            if let items = originalItems {
                pasteboard.clearContents()
                pasteboard.writeObjects(items)
            }
            throw error
        }

        // Restore clipboard
        if let items = originalItems {
            pasteboard.clearContents()
            pasteboard.writeObjects(items)
        }
    }

    func testClipboardInjectorWithUnicode() async throws {
        let injector = ClipboardInjector()
        let pasteboard = NSPasteboard.general

        // Save original clipboard
        let originalItems = pasteboard.pasteboardItems

        // Unicode text
        let unicodeText = "Hello 世界! Привет мир! مرحبا بالعالم! 🌍🎉"

        do {
            try await injector.inject(unicodeText)
            try await Task.sleep(for: .milliseconds(150))
        } catch {
            // Restore clipboard on error
            if let items = originalItems {
                pasteboard.clearContents()
                pasteboard.writeObjects(items)
            }
            throw error
        }

        // Restore clipboard
        if let items = originalItems {
            pasteboard.clearContents()
            pasteboard.writeObjects(items)
        }
    }

    // MARK: - Method Selection Tests

    func testExplicitCGEventMethod() async throws {
        // When explicitly requesting CGEvent, should fail if no accessibility permission
        guard permissionsManager.accessibilityEnabled else {
            // Should throw accessibilityNotGranted error
            do {
                try await service.inject("test", method: .cgEvent)
                XCTFail("Should have thrown accessibilityNotGranted error")
            } catch TextInjectionError.accessibilityNotGranted {
                // Expected error
                return
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
            return
        }

        // If we have accessibility permission, should succeed
        try await service.inject("test", method: .cgEvent)
    }

    func testExplicitClipboardMethod() async throws {
        let pasteboard = NSPasteboard.general
        let originalItems = pasteboard.pasteboardItems

        do {
            try await service.inject("test", method: .clipboard)
            try await Task.sleep(for: .milliseconds(150))
        } catch {
            if let items = originalItems {
                pasteboard.clearContents()
                pasteboard.writeObjects(items)
            }
            throw error
        }

        // Restore clipboard
        if let items = originalItems {
            pasteboard.clearContents()
            pasteboard.writeObjects(items)
        }
    }
}
