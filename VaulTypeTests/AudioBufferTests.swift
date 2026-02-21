import XCTest

@testable import VaulType

final class AudioBufferTests: XCTestCase {
    // MARK: - Basic Operations

    func testWriteAndReadAll() {
        let buffer = AudioBuffer(capacity: 1000)
        let samples: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]

        buffer.write(samples)

        let retrieved = buffer.readAll()

        XCTAssertEqual(retrieved.count, samples.count)
        XCTAssertEqual(retrieved, samples)
    }

    func testReset() {
        let buffer = AudioBuffer(capacity: 1000)
        let samples: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]

        buffer.write(samples)
        XCTAssertFalse(buffer.isEmpty)

        buffer.reset()

        XCTAssertTrue(buffer.isEmpty)
        XCTAssertEqual(buffer.count, 0)

        let retrieved = buffer.readAll()
        XCTAssertEqual(retrieved.count, 0)
    }

    func testOverflow() {
        // Create a small buffer that will overflow
        let capacity = 100
        let buffer = AudioBuffer(capacity: capacity)

        // Write more samples than capacity
        let totalSamples = 150
        var allSamples: [Float] = []
        for i in 0..<totalSamples {
            allSamples.append(Float(i) / Float(totalSamples))
        }

        buffer.write(allSamples)

        // Should only keep the last 'capacity' samples
        let retrieved = buffer.readAll()
        XCTAssertEqual(retrieved.count, capacity)

        // Verify the oldest samples were overwritten (first 50 should be gone)
        // The buffer should contain samples[50..<150]
        let expected = Array(allSamples.suffix(capacity))
        XCTAssertEqual(retrieved, expected)
    }

    func testEmptyRead() {
        let buffer = AudioBuffer(capacity: 1000)

        let retrieved = buffer.readAll()

        XCTAssertEqual(retrieved.count, 0)
        XCTAssertTrue(retrieved.isEmpty)
        XCTAssertTrue(buffer.isEmpty)
    }

    func testMultipleWrites() {
        let buffer = AudioBuffer(capacity: 1000)

        let batch1: [Float] = [0.1, 0.2, 0.3]
        let batch2: [Float] = [0.4, 0.5, 0.6]
        let batch3: [Float] = [0.7, 0.8, 0.9]

        buffer.write(batch1)
        buffer.write(batch2)
        buffer.write(batch3)

        let retrieved = buffer.readAll()

        let expected = batch1 + batch2 + batch3
        XCTAssertEqual(retrieved.count, expected.count)
        XCTAssertEqual(retrieved, expected)
    }

    func testWriteAfterReadAll() {
        let buffer = AudioBuffer(capacity: 1000)

        // First write and read
        let samples1: [Float] = [0.1, 0.2, 0.3]
        buffer.write(samples1)
        let retrieved1 = buffer.readAll()
        XCTAssertEqual(retrieved1, samples1)

        // Buffer should be empty after readAll
        XCTAssertTrue(buffer.isEmpty)

        // Second write and read
        let samples2: [Float] = [0.4, 0.5, 0.6]
        buffer.write(samples2)
        let retrieved2 = buffer.readAll()
        XCTAssertEqual(retrieved2, samples2)
    }

    func testCapacityExactFill() {
        let capacity = 10
        let buffer = AudioBuffer(capacity: capacity)

        // Write exactly capacity samples
        var samples: [Float] = []
        for i in 0..<capacity {
            samples.append(Float(i))
        }

        buffer.write(samples)

        let retrieved = buffer.readAll()
        XCTAssertEqual(retrieved.count, capacity)
        XCTAssertEqual(retrieved, samples)
    }

    func testLargeBuffer() {
        // Test with large buffer (30 seconds at 16kHz = 480,000 samples)
        let capacity = 480_000
        let buffer = AudioBuffer(capacity: capacity)

        // Write a large number of samples
        let sampleCount = 100_000
        var samples: [Float] = []
        for i in 0..<sampleCount {
            samples.append(Float(i) / Float(sampleCount))
        }

        buffer.write(samples)

        XCTAssertEqual(buffer.count, sampleCount)

        let retrieved = buffer.readAll()
        XCTAssertEqual(retrieved.count, sampleCount)
        XCTAssertEqual(retrieved, samples)
    }

    func testOverflowBoundary() {
        // Test wrap-around behavior at exact capacity boundary
        let capacity = 5
        let buffer = AudioBuffer(capacity: capacity)

        // First write: fill buffer completely
        let batch1: [Float] = [1.0, 2.0, 3.0, 4.0, 5.0]
        buffer.write(batch1)

        // Second write: should overwrite the oldest samples
        let batch2: [Float] = [6.0, 7.0]
        buffer.write(batch2)

        let retrieved = buffer.readAll()

        // Should contain: [3.0, 4.0, 5.0, 6.0, 7.0]
        let expected: [Float] = [3.0, 4.0, 5.0, 6.0, 7.0]
        XCTAssertEqual(retrieved, expected)
    }

    func testCountProperty() {
        let buffer = AudioBuffer(capacity: 1000)

        XCTAssertEqual(buffer.count, 0)

        buffer.write([0.1, 0.2, 0.3])
        XCTAssertEqual(buffer.count, 3)

        buffer.write([0.4, 0.5])
        XCTAssertEqual(buffer.count, 5)

        buffer.reset()
        XCTAssertEqual(buffer.count, 0)
    }

    func testIsEmptyProperty() {
        let buffer = AudioBuffer(capacity: 1000)

        XCTAssertTrue(buffer.isEmpty)

        buffer.write([0.1])
        XCTAssertFalse(buffer.isEmpty)

        buffer.readAll()
        XCTAssertTrue(buffer.isEmpty)
    }

    func testWriteEmptyArray() {
        let buffer = AudioBuffer(capacity: 1000)

        buffer.write([])

        XCTAssertTrue(buffer.isEmpty)
        XCTAssertEqual(buffer.count, 0)

        let retrieved = buffer.readAll()
        XCTAssertEqual(retrieved.count, 0)
    }

    func testThreadSafety() async {
        let buffer = AudioBuffer(capacity: 10_000)

        // Perform concurrent writes
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    let samples = [Float](repeating: Float(i), count: 100)
                    buffer.write(samples)
                }
            }
        }

        // Should have received 1000 samples total
        XCTAssertEqual(buffer.count, 1000)
    }
}
