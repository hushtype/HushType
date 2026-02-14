import XCTest

@testable import HushType

final class VoiceActivityDetectorTests: XCTestCase {
    private let sampleRate = 16_000
    private var detector: VoiceActivityDetector!

    override func setUp() {
        super.setUp()
        detector = VoiceActivityDetector()
    }

    override func tearDown() {
        detector = nil
        super.tearDown()
    }

    // MARK: - Trim Silence Tests

    func testTrimSilenceEmptyInput() {
        let result = detector.trimSilence(from: [], sensitivity: 0.5)

        XCTAssertEqual(result.count, 0)
        XCTAssertTrue(result.isEmpty)
    }

    func testTrimSilenceAllSilence() {
        // Create all-zero samples (pure silence)
        let samples = [Float](repeating: 0.0, count: 16_000)  // 1 second of silence

        let result = detector.trimSilence(from: samples, sensitivity: 0.5)

        XCTAssertEqual(result.count, 0)
    }

    func testTrimSilenceWithSpeech() {
        // Create a signal with silence at the beginning and end, and a sinusoidal burst in the middle
        var samples: [Float] = []

        // 0.5 seconds of silence
        samples.append(contentsOf: [Float](repeating: 0.0, count: sampleRate / 2))

        // 1 second of speech-like signal (sinusoidal burst)
        let frequency: Float = 200.0  // 200 Hz
        for i in 0..<sampleRate {
            let t = Float(i) / Float(sampleRate)
            let amplitude: Float = 0.5
            let sample = amplitude * sin(2.0 * .pi * frequency * t)
            samples.append(sample)
        }

        // 0.5 seconds of silence
        samples.append(contentsOf: [Float](repeating: 0.0, count: sampleRate / 2))

        let result = detector.trimSilence(from: samples, sensitivity: 0.5)

        // Result should be shorter than input (silence trimmed)
        XCTAssertGreaterThan(result.count, 0)
        XCTAssertLessThan(result.count, samples.count)

        // Result should contain mostly the middle section with signal
        // Allow some margin due to hangover and frame boundaries
        XCTAssertGreaterThan(result.count, sampleRate / 2)  // At least half the speech signal
    }

    func testTrimSilenceMultipleBursts() {
        // Create a signal with multiple speech bursts separated by silence
        var samples: [Float] = []

        // First burst
        for i in 0..<(sampleRate / 4) {
            let t = Float(i) / Float(sampleRate)
            samples.append(0.5 * sin(2.0 * .pi * 200.0 * t))
        }

        // Silence
        samples.append(contentsOf: [Float](repeating: 0.0, count: sampleRate / 4))

        // Second burst
        for i in 0..<(sampleRate / 4) {
            let t = Float(i) / Float(sampleRate)
            samples.append(0.5 * sin(2.0 * .pi * 200.0 * t))
        }

        let result = detector.trimSilence(from: samples, sensitivity: 0.5)

        // Result should contain both bursts
        XCTAssertGreaterThan(result.count, 0)
        XCTAssertLessThanOrEqual(result.count, samples.count)
    }

    // MARK: - Detect Voice Activity Tests

    func testDetectVoiceActivity() {
        // Create a signal with a clear speech burst
        var samples: [Float] = []

        // Silence
        samples.append(contentsOf: [Float](repeating: 0.0, count: sampleRate / 2))

        // Speech signal
        for i in 0..<sampleRate {
            let t = Float(i) / Float(sampleRate)
            samples.append(0.5 * sin(2.0 * .pi * 200.0 * t))
        }

        // Silence
        samples.append(contentsOf: [Float](repeating: 0.0, count: sampleRate / 2))

        let ranges = detector.detectVoiceActivity(in: samples, sensitivity: 0.5)

        // Should detect at least one range
        XCTAssertGreaterThan(ranges.count, 0)

        if let firstRange = ranges.first {
            // Range should be roughly in the middle section
            XCTAssertGreaterThan(firstRange.start, 0)
            XCTAssertLessThan(firstRange.end, samples.count)
            XCTAssertGreaterThan(firstRange.end, firstRange.start)
        }
    }

    func testDetectVoiceActivityEmptyInput() {
        let ranges = detector.detectVoiceActivity(in: [], sensitivity: 0.5)

        XCTAssertEqual(ranges.count, 0)
    }

    func testDetectVoiceActivityAllSilence() {
        let samples = [Float](repeating: 0.0, count: sampleRate)

        let ranges = detector.detectVoiceActivity(in: samples, sensitivity: 0.5)

        XCTAssertEqual(ranges.count, 0)
    }

    // MARK: - Sensitivity Tests

    func testSensitivityEffect() {
        // Create a signal with low-amplitude speech
        var samples: [Float] = []

        // Low-amplitude signal (might be detected with high sensitivity, but not low)
        for i in 0..<sampleRate {
            let t = Float(i) / Float(sampleRate)
            let amplitude: Float = 0.1  // Low amplitude
            samples.append(amplitude * sin(2.0 * .pi * 200.0 * t))
        }

        // Test with low sensitivity (0.1) - should detect less
        let lowSensitivityRanges = detector.detectVoiceActivity(in: samples, sensitivity: 0.1)

        // Test with high sensitivity (0.9) - should detect more
        let highSensitivityRanges = detector.detectVoiceActivity(in: samples, sensitivity: 0.9)

        // Higher sensitivity should detect more or equal ranges/samples
        let lowSensitivitySamples = lowSensitivityRanges.reduce(0) { $0 + ($1.end - $1.start) }
        let highSensitivitySamples = highSensitivityRanges.reduce(0) { $0 + ($1.end - $1.start) }

        XCTAssertGreaterThanOrEqual(highSensitivitySamples, lowSensitivitySamples)
    }

    func testSensitivityBoundaries() {
        // Create a signal with moderate amplitude
        var samples: [Float] = []

        for i in 0..<sampleRate {
            let t = Float(i) / Float(sampleRate)
            samples.append(0.3 * sin(2.0 * .pi * 200.0 * t))
        }

        // Test with minimum sensitivity (0.0)
        let minSensitivity = detector.detectVoiceActivity(in: samples, sensitivity: 0.0)

        // Test with maximum sensitivity (1.0)
        let maxSensitivity = detector.detectVoiceActivity(in: samples, sensitivity: 1.0)

        // Both should work without crashing
        XCTAssertGreaterThanOrEqual(minSensitivity.count, 0)
        XCTAssertGreaterThanOrEqual(maxSensitivity.count, 0)
    }

    // MARK: - Edge Cases

    func testVeryShortInput() {
        // Input shorter than a single frame (480 samples)
        let samples: [Float] = [0.5, 0.5, 0.5, 0.5, 0.5]

        let result = detector.trimSilence(from: samples, sensitivity: 0.5)

        // Should handle gracefully (might return empty or the full input)
        XCTAssertGreaterThanOrEqual(result.count, 0)
        XCTAssertLessThanOrEqual(result.count, samples.count)
    }

    func testSingleFrame() {
        // Exactly one frame (480 samples at 16kHz = 30ms)
        var samples: [Float] = []
        for i in 0..<480 {
            let t = Float(i) / Float(sampleRate)
            samples.append(0.5 * sin(2.0 * .pi * 200.0 * t))
        }

        let result = detector.trimSilence(from: samples, sensitivity: 0.5)

        // Should process the single frame
        XCTAssertGreaterThanOrEqual(result.count, 0)
    }

    func testAlternatingSignalAndSilence() {
        // Create alternating bursts of signal and silence
        var samples: [Float] = []

        for _ in 0..<5 {
            // Signal burst (0.1 seconds)
            for i in 0..<(sampleRate / 10) {
                let t = Float(i) / Float(sampleRate)
                samples.append(0.5 * sin(2.0 * .pi * 200.0 * t))
            }

            // Silence (0.1 seconds)
            samples.append(contentsOf: [Float](repeating: 0.0, count: sampleRate / 10))
        }

        let ranges = detector.detectVoiceActivity(in: samples, sensitivity: 0.5)

        // Due to hangover, might merge some ranges
        XCTAssertGreaterThan(ranges.count, 0)
    }

    func testWhiteNoise() {
        // Create white noise (should be detected as voice activity with high enough amplitude)
        var samples: [Float] = []
        for _ in 0..<sampleRate {
            samples.append(Float.random(in: -0.5...0.5))
        }

        let ranges = detector.detectVoiceActivity(in: samples, sensitivity: 0.5)

        // White noise should be detected as activity
        XCTAssertGreaterThan(ranges.count, 0)

        let result = detector.trimSilence(from: samples, sensitivity: 0.5)
        XCTAssertGreaterThan(result.count, 0)
    }
}
