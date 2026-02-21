import XCTest

@testable import VaulType

final class PerformanceBenchmarkTests: XCTestCase {

    // MARK: - CommandParser Single Parse Performance

    func testCommandParserSingleParsePerformance() {
        let parser = CommandParser()
        measure {
            _ = parser.parse("open Safari")
        }
    }

    // MARK: - CommandParser Chain Parse Performance

    func testCommandParserChainParsePerformance() {
        let parser = CommandParser()
        let input = "open Safari and volume up then mute"
        measure {
            _ = parser.parseChain(input)
        }
    }

    // MARK: - CommandParser 100 Parses Performance

    func testCommandParser100ParsesPerformance() {
        let parser = CommandParser()
        let commands = [
            "open Safari",
            "launch Xcode",
            "switch to Finder",
            "close Terminal",
            "quit Xcode",
            "hide Finder",
            "show all windows",
            "mission control",
            "maximize window",
            "minimize window",
            "center window",
            "full screen",
            "move window left",
            "move window right",
            "next screen",
            "volume up",
            "volume down",
            "mute",
            "volume 50",
            "brightness up",
            "brightness down",
            "dark mode",
            "lock screen",
            "take screenshot",
            "run shortcut Morning Routine",
            "do not disturb",
            "louder",
            "softer",
            "brighter",
            "dimmer",
            "go to Terminal",
            "activate Mail",
            "terminate Slack",
            "exit Notes",
            "tile left",
            "snap right",
            "fill screen",
            "expand window",
            "toggle full screen",
            "enter full screen",
            "move to next display",
            "other screen",
            "turn it up",
            "turn it down",
            "increase volume",
            "decrease volume",
            "toggle mute",
            "unmute",
            "set volume to 75",
            "increase brightness",
        ]
        measure {
            for i in 0..<100 {
                let input = commands[i % commands.count]
                _ = parser.parse(input)
            }
        }
    }

    // MARK: - CommandParser — No-Match Performance

    func testCommandParserNoMatchPerformance() {
        let parser = CommandParser()
        measure {
            _ = parser.parse("hello world this is not a command")
        }
    }

    // MARK: - CommandDetector Detect Performance

    func testCommandDetectorDetectPerformance() {
        let textWithWakePhrase = "Hey Type open Safari"
        let textWithoutWakePhrase = "open Safari without wake phrase"
        measure {
            _ = CommandDetector.detect(in: textWithWakePhrase)
            _ = CommandDetector.detect(in: textWithoutWakePhrase)
        }
    }

    // MARK: - CommandDetector 100 Detects Performance

    func testCommandDetector100DetectsPerformance() {
        let inputs = [
            "Hey Type open Safari",
            "Hey Type volume up",
            "Hey Type lock screen",
            "open Safari without wake phrase",
            "random text with no wake phrase",
            "Hey Type maximize window",
            "Hey Type mute",
            "hey type dark mode",
            "HEY TYPE brightness up",
            "Hello World no match",
        ]
        measure {
            for i in 0..<100 {
                let input = inputs[i % inputs.count]
                _ = CommandDetector.detect(in: input)
            }
        }
    }

    // MARK: - CommandDetector Custom Wake Phrase Performance

    func testCommandDetectorCustomWakePhrasePerformance() {
        let text = "Computer open Safari"
        measure {
            _ = CommandDetector.detect(in: text, wakePhrase: "Computer")
        }
    }

    // MARK: - SoundFeedbackService Creation Performance

    func testSoundFeedbackServiceCreationPerformance() {
        measure {
            _ = SoundFeedbackService()
        }
    }

    // MARK: - SoundFeedbackService Disabled Play Performance

    func testSoundFeedbackServiceDisabledPlayPerformance() {
        let service = SoundFeedbackService()
        service.isEnabled = false
        measure {
            service.play(.recordingStart)
            service.play(.recordingStop)
            service.play(.commandSuccess)
            service.play(.commandError)
            service.play(.injectionComplete)
        }
    }

    // MARK: - SoundFeedbackService Theme None Play Performance

    func testSoundFeedbackServiceThemeNonePlayPerformance() {
        let service = SoundFeedbackService()
        service.isEnabled = true
        service.theme = .none
        measure {
            service.play(.recordingStart)
            service.play(.commandSuccess)
        }
    }

    // MARK: - PowerManagementService Creation Performance

    func testPowerManagementServiceCreationPerformance() {
        measure {
            let service = PowerManagementService()
            // Immediately stop to avoid lingering timers/monitors
            service.stop()
        }
    }

    // MARK: - Memory Baseline — CommandParser Instantiation

    func testCommandParserMemoryFootprint() {
        // Instantiate CommandParser and confirm it doesn't crash; serves as a memory baseline.
        let parser = CommandParser()
        let result = parser.parse("open Safari")
        XCTAssertNotNil(result, "CommandParser baseline: expected a valid parse result")
        XCTAssertEqual(result?.intent, .openApp)
    }

    // MARK: - Batch Command Parsing

    func testBatchCommandParsing() {
        let parser = CommandParser()
        let realisticCommands = [
            "open Safari",
            "switch to Finder",
            "volume up",
            "mute",
            "dark mode",
            "lock screen",
            "maximize window",
            "move window left",
            "take screenshot",
            "brightness up",
            "close Terminal",
            "quit Xcode",
            "center window",
            "full screen",
            "volume 75",
            "do not disturb",
            "brightness down",
            "minimize window",
            "next screen",
            "run shortcut Morning Routine",
            "hide Finder",
            "show all windows",
            "move window right",
            "volume down",
            "launch Mail",
            "switch to Safari",
            "toggle mute",
            "increase brightness",
            "decrease volume",
            "exit Notes",
            "go to Terminal",
            "activate Slack",
            "terminate Chrome",
            "tile left",
            "snap right",
            "expand window",
            "toggle full screen",
            "other screen",
            "louder",
            "softer",
            "brighter",
            "dimmer",
            "set volume to 50",
            "turn it up",
            "shortcut Evening Routine",
            "screen capture",
            "move to next screen",
            "move to next monitor",
            "capture screen",
            "increase volume",
        ]
        XCTAssertEqual(realisticCommands.count, 50, "Batch should contain exactly 50 commands")

        measure {
            var successCount = 0
            for command in realisticCommands {
                if parser.parse(command) != nil {
                    successCount += 1
                }
            }
            // Most commands should parse; just ensure the loop completes without crash
            XCTAssertGreaterThan(successCount, 0)
        }
    }

    // MARK: - CommandParser Chain — Long Chain Performance

    func testCommandParserLongChainPerformance() {
        let parser = CommandParser()
        let longChain = "open Safari and volume up and mute then dark mode and lock screen"
        measure {
            _ = parser.parseChain(longChain)
        }
    }

    // MARK: - CommandDetector Edge Cases Performance

    func testCommandDetectorEdgeCasesPerformance() {
        // Tests empty string, whitespace-only, and wake-phrase-only inputs
        measure {
            _ = CommandDetector.detect(in: "")
            _ = CommandDetector.detect(in: "   ")
            _ = CommandDetector.detect(in: "Hey Type")
            _ = CommandDetector.detect(in: "Hey Type,")
            _ = CommandDetector.detect(in: "Hey Type: open Safari")
        }
    }

    // MARK: - PowerManagementService Property Access Performance

    func testPowerManagementServicePropertyAccessPerformance() {
        let service = PowerManagementService()
        defer { service.stop() }
        measure {
            _ = service.isOnBattery
            _ = service.thermalState
            _ = service.isMemoryConstrained
            _ = service.recommendedWhisperThreadCount
            _ = service.shouldSkipLLMProcessing
            _ = service.shouldThrottle
        }
    }
}
