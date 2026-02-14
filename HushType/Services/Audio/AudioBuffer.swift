import Foundation
import os

/// Thread-safe circular ring buffer for audio samples.
/// Designed for use in real-time audio contexts with minimal overhead.
final class AudioBuffer: @unchecked Sendable {
    // MARK: - Properties

    /// Maximum number of samples the buffer can hold.
    let capacity: Int

    /// Internal storage for audio samples.
    private var buffer: [Float]

    /// Current write position in the buffer.
    private var writeIndex: Int = 0

    /// Number of valid samples currently stored.
    private var validCount: Int = 0

    /// Whether the buffer has wrapped around (overwritten oldest data).
    private var hasWrapped: Bool = false

    /// Lock for thread-safe access.
    /// Using os_unfair_lock for minimal overhead in real-time audio context.
    private var lock = os_unfair_lock()

    // MARK: - Computed Properties

    /// Current number of valid samples in the buffer.
    var count: Int {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return validCount
    }

    /// Whether the buffer is empty.
    var isEmpty: Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return validCount == 0
    }

    // MARK: - Initialization

    /// Create a new audio buffer with the specified capacity.
    /// - Parameter capacity: Maximum number of Float samples to store. Default is 480,000 (30 seconds at 16kHz).
    init(capacity: Int = 480_000) {
        self.capacity = capacity
        self.buffer = [Float](repeating: 0.0, count: capacity)
        Logger.audio.debug("AudioBuffer initialized with capacity \(capacity) samples")
    }

    // MARK: - Methods

    /// Append samples to the buffer.
    /// If the buffer is full, oldest samples are overwritten.
    /// - Parameter samples: Array of Float samples to append.
    func write(_ samples: [Float]) {
        guard !samples.isEmpty else { return }

        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        for sample in samples {
            buffer[writeIndex] = sample
            writeIndex = (writeIndex + 1) % capacity

            if validCount < capacity {
                validCount += 1
            } else {
                hasWrapped = true
            }
        }

        Logger.audio.debug("Wrote \(samples.count) samples to buffer (total: \(self.validCount))")
    }

    /// Read all samples in chronological order and reset the buffer.
    /// - Returns: Array of all valid samples in the order they were written.
    func readAll() -> [Float] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        guard validCount > 0 else {
            Logger.audio.debug("Buffer is empty on readAll()")
            return []
        }

        var result = [Float]()
        result.reserveCapacity(validCount)

        if hasWrapped {
            // Read from writeIndex to end, then from start to writeIndex
            let readStartIndex = writeIndex
            result.append(contentsOf: buffer[readStartIndex..<capacity])
            result.append(contentsOf: buffer[0..<writeIndex])
        } else {
            // Read from start to writeIndex
            result.append(contentsOf: buffer[0..<validCount])
        }

        Logger.audio.info("Read \(result.count) samples from buffer, resetting")

        // Reset state
        writeIndex = 0
        validCount = 0
        hasWrapped = false

        return result
    }

    /// Clear the buffer without returning data.
    func reset() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        Logger.audio.debug("Resetting buffer (was holding \(self.validCount) samples)")

        writeIndex = 0
        validCount = 0
        hasWrapped = false
    }
}
