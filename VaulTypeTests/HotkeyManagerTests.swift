import Carbon.HIToolbox
import CoreGraphics
import XCTest

@testable import VaulType

final class HotkeyManagerTests: XCTestCase {
    // MARK: - HotkeyBinding Tests

    func testParse() {
        // Test parsing "cmd+shift+space"
        let binding = HotkeyBinding.parse("cmd+shift+space")

        XCTAssertNotNil(binding)
        XCTAssertEqual(binding?.keyCode, CGKeyCode(kVK_Space))
        XCTAssertTrue(binding?.modifiers.contains(.maskCommand) ?? false)
        XCTAssertTrue(binding?.modifiers.contains(.maskShift) ?? false)
        XCTAssertFalse(binding?.modifiers.contains(.maskAlternate) ?? true)
        XCTAssertFalse(binding?.modifiers.contains(.maskControl) ?? true)
    }

    func testSerialize() {
        // Test serializing a binding back to string
        let binding = HotkeyBinding(
            keyCode: CGKeyCode(kVK_Space),
            modifiers: [.maskCommand, .maskShift]
        )

        let serialized = binding.serialize()

        // Should be "shift+cmd+space" (alphabetical order: ctrl, option, shift, cmd)
        XCTAssertEqual(serialized, "shift+cmd+space")
    }

    func testParseRoundTrip() {
        // Test that parse(serialize(binding)) == original binding
        let original = HotkeyBinding(
            keyCode: CGKeyCode(kVK_Return),
            modifiers: [.maskCommand, .maskAlternate]
        )

        let serialized = original.serialize()
        let parsed = HotkeyBinding.parse(serialized)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.keyCode, original.keyCode)
        XCTAssertEqual(parsed?.modifiers, original.modifiers)
    }

    func testDisplayString() {
        // Test display string format with symbols
        let binding = HotkeyBinding(
            keyCode: CGKeyCode(kVK_Space),
            modifiers: [.maskCommand, .maskShift]
        )

        let display = binding.displayString

        // Should be "⇧⌘Space" (order: control, option, shift, command)
        XCTAssertEqual(display, "⇧⌘Space")
    }

    func testDisplayStringAllModifiers() {
        // Test display string with all modifiers
        let binding = HotkeyBinding(
            keyCode: CGKeyCode(kVK_ANSI_A),
            modifiers: [.maskControl, .maskAlternate, .maskShift, .maskCommand]
        )

        let display = binding.displayString

        // Should be "⌃⌥⇧⌘A"
        XCTAssertEqual(display, "⌃⌥⇧⌘A")
    }

    func testKeyCodeForName() {
        // Test key code mapping for various keys
        let testCases: [(String, Int)] = [
            ("a", kVK_ANSI_A),
            ("z", kVK_ANSI_Z),
            ("0", kVK_ANSI_0),
            ("9", kVK_ANSI_9),
            ("space", kVK_Space),
            ("return", kVK_Return),
            ("tab", kVK_Tab),
            ("escape", kVK_Escape),
        ]

        for (name, expectedKeyCode) in testCases {
            let binding = HotkeyBinding.parse("cmd+\(name)")
            XCTAssertNotNil(binding, "Failed to parse key: \(name)")
            XCTAssertEqual(binding?.keyCode, CGKeyCode(expectedKeyCode), "Wrong keyCode for \(name)")
        }
    }

    func testDisabledBindingProperty() {
        // Test that isEnabled defaults to true and can be set to false
        let binding = HotkeyBinding(
            keyCode: CGKeyCode(kVK_Space),
            modifiers: [.maskCommand, .maskShift]
        )
        XCTAssertTrue(binding.isEnabled)

        let disabledBinding = HotkeyBinding(
            keyCode: CGKeyCode(kVK_Space),
            modifiers: [.maskCommand, .maskShift],
            isEnabled: false
        )
        XCTAssertFalse(disabledBinding.isEnabled)
    }

    func testConflictDetection() {
        // Test that Cmd+Space is detected as conflicting with Spotlight
        let binding = HotkeyBinding(
            keyCode: CGKeyCode(kVK_Space),
            modifiers: .maskCommand
        )

        let conflicts = HotkeyManager.detectConflicts(for: binding)

        XCTAssertTrue(conflicts.contains("Spotlight"))
    }

    func testMaxBindings() throws {
        let manager = HotkeyManager()

        // Register 4 bindings (should succeed)
        for i in 0..<4 {
            let binding = HotkeyBinding(
                keyCode: CGKeyCode(kVK_F1 + i),
                modifiers: .maskCommand
            )
            try manager.register(binding)
        }

        XCTAssertEqual(manager.bindings.count, 4)

        // Try to register a 5th binding (should throw maxBindingsReached)
        let extraBinding = HotkeyBinding(
            keyCode: CGKeyCode(kVK_F5),
            modifiers: .maskCommand
        )

        XCTAssertThrowsError(try manager.register(extraBinding)) { error in
            XCTAssertEqual(error as? HotkeyError, HotkeyError.maxBindingsReached)
        }
    }

    func testParseInvalidInput() {
        // Test parsing invalid inputs
        XCTAssertNil(HotkeyBinding.parse(""))
        // Note: standalone keys like "space" are valid (fn-style single key binding)
        XCTAssertNotNil(HotkeyBinding.parse("space"))
        XCTAssertNil(HotkeyBinding.parse("cmd+invalid_key"))
        XCTAssertNil(HotkeyBinding.parse("invalid+space"))
    }

    func testModifierVariations() {
        // Test various modifier name variations
        let testCases: [(String, CGEventFlags)] = [
            ("cmd+space", .maskCommand),
            ("command+space", .maskCommand),
            ("shift+space", .maskShift),
            ("opt+space", .maskAlternate),
            ("option+space", .maskAlternate),
            ("alt+space", .maskAlternate),
            ("ctrl+space", .maskControl),
            ("control+space", .maskControl),
        ]

        for (input, expectedModifier) in testCases {
            let binding = HotkeyBinding.parse(input)
            XCTAssertNotNil(binding, "Failed to parse: \(input)")
            XCTAssertTrue(binding?.modifiers.contains(expectedModifier) ?? false, "Wrong modifier for \(input)")
        }
    }
}
