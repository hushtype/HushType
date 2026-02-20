import Foundation
import XCTest

@testable import HushType

@MainActor
final class CommandExecutorTests: XCTestCase {
    private var registry: CommandRegistry!
    private var parser: CommandParser!
    private var executor: CommandExecutor!

    override func setUp() async throws {
        try await super.setUp()
        registry = CommandRegistry()
        parser = CommandParser()
        executor = CommandExecutor(registry: registry)
    }

    override func tearDown() async throws {
        executor = nil
        parser = nil
        registry = nil
        try await super.tearDown()
    }

    // MARK: - testDisabledCommandReturnsFailure

    func testDisabledCommandReturnsFailure() async throws {
        // Disable the volumeUp command in the registry.
        registry.setEnabled(.volumeUp, enabled: false)

        guard let command = parser.parse("volume up") else {
            XCTFail("Expected 'volume up' to parse successfully")
            return
        }

        XCTAssertEqual(command.intent, .volumeUp, "Parsed intent should be .volumeUp")

        let result = await executor.execute(command)

        XCTAssertFalse(result.success, "Disabled command should return success == false")
        XCTAssertEqual(result.intent, .volumeUp, "Result intent should match the attempted command")
        XCTAssertTrue(
            result.message.contains("disabled"),
            "Failure message should mention the command is disabled, got: \(result.message)"
        )
    }

    // MARK: - testUnknownAppReturnsFailure

    func testUnknownAppReturnsFailure() async throws {
        // Parse "open NonExistentApp12345" — the app will not be found on any machine.
        guard let command = parser.parse("open NonExistentApp12345") else {
            XCTFail("Expected 'open NonExistentApp12345' to parse successfully")
            return
        }

        XCTAssertEqual(command.intent, .openApp)
        XCTAssertEqual(command.entities["appName"], "NonExistentApp12345")

        let result = await executor.execute(command)

        XCTAssertFalse(result.success, "Executing open for a non-existent app should fail")
        XCTAssertEqual(result.intent, .openApp)
        // The error should mention the app name or failure reason.
        XCTAssertFalse(result.message.isEmpty, "Failure message should not be empty")
    }

    // MARK: - testExecuteChainStopsOnFailure

    func testExecuteChainStopsOnFailure() async throws {
        // Disable volumeDown so the second command in the chain will fail.
        registry.setEnabled(.volumeDown, enabled: false)

        guard let firstCommand = parser.parse("volume up"),
              let secondCommand = parser.parse("volume down") else {
            XCTFail("Expected both commands to parse successfully")
            return
        }

        XCTAssertEqual(firstCommand.intent, .volumeUp)
        XCTAssertEqual(secondCommand.intent, .volumeDown)

        // Build a three-element chain: [volumeUp (enabled), volumeDown (disabled), mute (enabled)]
        // The chain should stop at the second command (index 1).
        guard let thirdCommand = parser.parse("mute") else {
            XCTFail("Expected 'mute' to parse successfully")
            return
        }

        let chain = [firstCommand, secondCommand, thirdCommand]
        let results = await executor.executeChain(chain)

        // Only two results: the first (success) and the second (failure).
        // The chain must not reach the third command.
        XCTAssertEqual(results.count, 2, "Chain should stop after the first failure, producing exactly 2 results")

        XCTAssertTrue(results[0].success, "First command (volumeUp, enabled) should succeed")
        XCTAssertEqual(results[0].intent, .volumeUp)

        XCTAssertFalse(results[1].success, "Second command (volumeDown, disabled) should fail")
        XCTAssertEqual(results[1].intent, .volumeDown)
    }

    // MARK: - testExecuteChainAllSucceed

    func testExecuteChainAllSucceed() async throws {
        // Use system-control commands that do not require accessibility permissions
        // and that run synchronous osascript/key events (volumeUp, volumeDown, mute).
        // We only verify the CommandResult structure — not OS side-effects.
        guard let volumeUpCmd = parser.parse("volume up"),
              let volumeDownCmd = parser.parse("volume down"),
              let muteCmd = parser.parse("mute") else {
            XCTFail("Expected all three commands to parse successfully")
            return
        }

        let chain = [volumeUpCmd, volumeDownCmd, muteCmd]
        let results = await executor.executeChain(chain)

        // All three should succeed (or at least attempt to execute and return results).
        XCTAssertEqual(results.count, 3, "All three commands should produce results")

        for (index, result) in results.enumerated() {
            XCTAssertTrue(
                result.success,
                "Command at index \(index) (\(result.intent.rawValue)) should succeed"
            )
            XCTAssertFalse(result.message.isEmpty, "Each result should carry a non-empty message")
        }
    }
}
