import Foundation
import os

/// Energy-based voice activity detector for trimming silence from audio.
final class VoiceActivityDetector {
    // MARK: - Constants

    /// Sample rate (16kHz).
    private let sampleRate: Int = 16_000

    /// Frame size in samples (30ms at 16kHz).
    private let frameSizeInSamples: Int = 480

    /// Hangover time in seconds to avoid cutting trailing syllables.
    private let hangoverSeconds: Float = 0.3

    // MARK: - Methods

    /// Trim leading and trailing silence from audio samples.
    /// - Parameters:
    ///   - samples: Input audio samples.
    ///   - sensitivity: VAD sensitivity from 0.0 (least sensitive) to 1.0 (most sensitive).
    /// - Returns: Trimmed audio samples with silence removed.
    func trimSilence(from samples: [Float], sensitivity: Float) -> [Float] {
        guard !samples.isEmpty else {
            Logger.audio.debug("VAD: trimSilence called with empty samples")
            return []
        }

        let ranges = detectVoiceActivity(in: samples, sensitivity: sensitivity)

        guard !ranges.isEmpty else {
            Logger.audio.info("VAD: no voice activity detected, returning empty array")
            return []
        }

        // Merge all ranges and find overall start/end
        let start = ranges.first!.start
        let end = ranges.last!.end

        guard start < samples.count, end <= samples.count, start < end else {
            Logger.audio.warning("VAD: invalid range detected (start: \(start), end: \(end), total: \(samples.count))")
            return samples
        }

        let trimmed = Array(samples[start..<end])
        let trimmedDuration = Float(trimmed.count) / Float(sampleRate)
        let originalDuration = Float(samples.count) / Float(sampleRate)

        Logger.audio.info("VAD: trimmed from \(String(format: "%.2f", originalDuration))s to \(String(format: "%.2f", trimmedDuration))s")

        return trimmed
    }

    /// Detect voice activity regions in audio samples.
    /// - Parameters:
    ///   - samples: Input audio samples.
    ///   - sensitivity: VAD sensitivity from 0.0 (least sensitive) to 1.0 (most sensitive).
    /// - Returns: Array of ranges indicating voice activity (start and end sample indices).
    func detectVoiceActivity(in samples: [Float], sensitivity: Float) -> [(start: Int, end: Int)] {
        guard !samples.isEmpty else { return [] }

        // Calculate energy threshold based on sensitivity
        let energyThreshold = calculateEnergyThreshold(from: samples, sensitivity: sensitivity)

        // Calculate RMS energy per frame
        let frameEnergies = calculateFrameEnergies(samples: samples)

        // Detect voice activity frames
        var voiceFrames = [Bool](repeating: false, count: frameEnergies.count)
        for (index, energy) in frameEnergies.enumerated() {
            voiceFrames[index] = energy > energyThreshold
        }

        // Apply hangover (extend voice regions by hangover time)
        let hangoverFrames = Int(hangoverSeconds * Float(sampleRate) / Float(frameSizeInSamples))
        voiceFrames = applyHangover(to: voiceFrames, hangoverFrames: hangoverFrames)

        // Convert frame indices to sample ranges
        let ranges = convertFramesToRanges(voiceFrames: voiceFrames, totalSamples: samples.count)

        Logger.audio.debug("VAD: detected \(ranges.count) voice activity regions")

        return ranges
    }

    // MARK: - Private Methods

    /// Calculate RMS energy for each frame in the audio.
    /// - Parameter samples: Input audio samples.
    /// - Returns: Array of RMS energy values per frame.
    private func calculateFrameEnergies(samples: [Float]) -> [Float] {
        var energies: [Float] = []
        let frameCount = samples.count / frameSizeInSamples

        for frameIndex in 0..<frameCount {
            let startIndex = frameIndex * frameSizeInSamples
            let endIndex = min(startIndex + frameSizeInSamples, samples.count)

            let frame = samples[startIndex..<endIndex]
            let rms = calculateRMS(frame: Array(frame))
            energies.append(rms)
        }

        return energies
    }

    /// Calculate RMS (Root Mean Square) energy of a frame.
    /// - Parameter frame: Array of Float samples.
    /// - Returns: RMS energy value.
    private func calculateRMS(frame: [Float]) -> Float {
        guard !frame.isEmpty else { return 0.0 }

        let sumOfSquares = frame.reduce(0.0) { $0 + ($1 * $1) }
        let meanOfSquares = sumOfSquares / Float(frame.count)
        return sqrt(meanOfSquares)
    }

    /// Calculate energy threshold based on sensitivity and audio statistics.
    /// - Parameters:
    ///   - samples: Input audio samples.
    ///   - sensitivity: VAD sensitivity (0.0 to 1.0).
    /// - Returns: Energy threshold value.
    private func calculateEnergyThreshold(from samples: [Float], sensitivity: Float) -> Float {
        // Calculate overall statistics
        let frameEnergies = calculateFrameEnergies(samples: samples)
        guard !frameEnergies.isEmpty else { return 0.0 }

        // Calculate mean and standard deviation of frame energies
        let mean = frameEnergies.reduce(0.0, +) / Float(frameEnergies.count)
        let variance = frameEnergies.reduce(0.0) { $0 + pow($1 - mean, 2) } / Float(frameEnergies.count)
        let stdDev = sqrt(variance)

        // Sensitivity 0.0 = mean + 2*stdDev (least sensitive, only loud sounds)
        // Sensitivity 1.0 = mean (most sensitive, detects quieter sounds)
        let multiplier = 2.0 - (sensitivity * 2.0)
        let threshold = mean + (multiplier * stdDev)

        Logger.audio.debug("VAD: energy threshold = \(String(format: "%.6f", threshold)) (mean: \(String(format: "%.6f", mean)), stdDev: \(String(format: "%.6f", stdDev)), sensitivity: \(String(format: "%.2f", sensitivity)))")

        return max(threshold, 0.0001) // Ensure minimum threshold
    }

    /// Apply hangover to voice frames to avoid cutting trailing syllables.
    /// - Parameters:
    ///   - voiceFrames: Boolean array indicating voice activity per frame.
    ///   - hangoverFrames: Number of frames to extend voice regions.
    /// - Returns: Modified voice frames with hangover applied.
    private func applyHangover(to voiceFrames: [Bool], hangoverFrames: Int) -> [Bool] {
        var result = voiceFrames
        var hangoverCounter = 0

        for i in 0..<result.count {
            if result[i] {
                hangoverCounter = hangoverFrames
            } else if hangoverCounter > 0 {
                result[i] = true
                hangoverCounter -= 1
            }
        }

        return result
    }

    /// Convert frame-level voice activity to sample ranges.
    /// - Parameters:
    ///   - voiceFrames: Boolean array indicating voice activity per frame.
    ///   - totalSamples: Total number of samples in the audio.
    /// - Returns: Array of sample ranges with voice activity.
    private func convertFramesToRanges(voiceFrames: [Bool], totalSamples: Int) -> [(start: Int, end: Int)] {
        var ranges: [(start: Int, end: Int)] = []
        var inVoiceRegion = false
        var regionStart = 0

        for (frameIndex, isVoice) in voiceFrames.enumerated() {
            let sampleStart = frameIndex * frameSizeInSamples

            if isVoice && !inVoiceRegion {
                // Start of voice region
                regionStart = sampleStart
                inVoiceRegion = true
            } else if !isVoice && inVoiceRegion {
                // End of voice region
                let regionEnd = min(sampleStart, totalSamples)
                ranges.append((start: regionStart, end: regionEnd))
                inVoiceRegion = false
            }
        }

        // Close final region if still in voice activity
        if inVoiceRegion {
            ranges.append((start: regionStart, end: totalSamples))
        }

        return ranges
    }
}
