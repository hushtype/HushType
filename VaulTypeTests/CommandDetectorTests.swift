import XCTest

@testable import VaulType

@MainActor
final class CommandDetectorTests: XCTestCase {

    // MARK: - Wake Phrase Matching

    func testExactWakePhraseMatch() {
        let result = CommandDetector.detect(in: "Hey Type open Safari")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.commandText, "open Safari")
    }

    func testCaseInsensitiveMatch() {
        let result = CommandDetector.detect(in: "hey type open Safari")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.commandText, "open Safari")
    }

    func testWakePhraseWithSeparators() {
        let result = CommandDetector.detect(in: "Hey Type, open Safari")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.commandText, "open Safari")
    }

    func testWakePhraseWithColon() {
        let result = CommandDetector.detect(in: "Hey Type: open Safari")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.commandText, "open Safari")
    }

    // MARK: - No Match Cases

    func testNoWakePhrase() {
        let result = CommandDetector.detect(in: "open Safari")

        XCTAssertNil(result)
    }

    func testWakePhraseOnly() {
        let result = CommandDetector.detect(in: "Hey Type")

        XCTAssertNil(result)
    }

    func testWakePhraseOnlyWithSeparator() {
        let result = CommandDetector.detect(in: "Hey Type,")

        XCTAssertNil(result)
    }

    func testEmptyText() {
        let result = CommandDetector.detect(in: "")

        XCTAssertNil(result)
    }

    // MARK: - Custom Wake Phrase

    func testCustomWakePhrase() {
        let result = CommandDetector.detect(in: "Computer open Safari", wakePhrase: "Computer")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.commandText, "open Safari")
    }

    // MARK: - Position Constraints

    func testWakePhraseInMiddle() {
        let result = CommandDetector.detect(in: "please Hey Type open Safari")

        XCTAssertNil(result)
    }

    // MARK: - Multi-Word Command

    func testMultiWordCommand() {
        let result = CommandDetector.detect(in: "Hey Type switch to dark mode")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.commandText, "switch to dark mode")
    }

    // MARK: - Separator Edge Cases

    func testWakePhraseWithPeriod() {
        let result = CommandDetector.detect(in: "Hey Type. open Safari")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.commandText, "open Safari")
    }

    func testWakePhraseWithDash() {
        let result = CommandDetector.detect(in: "Hey Type- open Safari")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.commandText, "open Safari")
    }
}
