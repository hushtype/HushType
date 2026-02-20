import AVFoundation
import Foundation
import os

// MARK: - AudioCapturing Protocol

/// Protocol for audio capture services.
protocol AudioCapturing: Sendable {
    /// Start capturing audio from the input device.
    /// - Throws: Audio engine errors or permission errors.
    func startCapture() async throws

    /// Stop capturing audio and return all captured samples.
    /// - Returns: Array of Float samples captured since `startCapture()`.
    func stopCapture() async -> [Float]

    /// Whether audio capture is currently active.
    var isCapturing: Bool { get }
}

// MARK: - AudioCaptureService

/// Audio capture service using AVAudioEngine.
/// Captures audio at 16kHz mono Float32 PCM format.
@Observable
final class AudioCaptureService: AudioCapturing, @unchecked Sendable {
    // MARK: - Properties

    /// Audio engine for capturing audio.
    private let engine = AVAudioEngine()

    /// Audio buffer for storing captured samples.
    private let buffer: AudioBuffer

    /// Internal queue for thread-safe operations.
    private let queue = DispatchQueue(label: "com.hushtype.audio.capture", qos: .userInitiated)

    /// Whether audio capture is currently active.
    private(set) var isCapturing: Bool = false

    /// Most recent audio input level (0.0 to 1.0), updated during capture.
    private(set) var currentLevel: Float = 0

    /// Timestamp of last level update for throttling.
    private var lastLevelUpdate: TimeInterval = 0

    /// Target audio format: 16kHz mono Float32 PCM.
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    /// Audio converter for format conversion (created when needed).
    private var converter: AVAudioConverter?

    // MARK: - Initialization

    init(buffer: AudioBuffer = AudioBuffer()) {
        self.buffer = buffer
        Logger.audio.info("AudioCaptureService initialized")
    }

    // MARK: - Public Methods

    /// Start capturing audio from the default input device.
    func startCapture() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: AudioCaptureError.serviceReleased)
                    return
                }

                do {
                    try self._startCapture()
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Stop capturing audio and return all captured samples.
    func stopCapture() async -> [Float] {
        // Wait briefly for in-flight audio buffers to flush before stopping the engine
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms

        return await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: [])
                    return
                }

                let samples = self._stopCapture()
                continuation.resume(returning: samples)
            }
        }
    }

    /// Enumerate available audio input devices.
    /// - Returns: Array of tuples containing device ID and name.
    func enumerateInputDevices() -> [(id: String, name: String)] {
        #if targetEnvironment(macCatalyst)
        Logger.audio.warning("Audio device enumeration not available on Mac Catalyst")
        return []
        #else
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )

        let devices = discoverySession.devices.map { device in
            (id: device.uniqueID, name: device.localizedName)
        }

        Logger.audio.info("Found \(devices.count) audio input devices")
        return devices
        #endif
    }

    /// Set the audio input device.
    /// - Parameter deviceID: Device unique identifier. Pass `nil` to use system default.
    func setInputDevice(id deviceID: String?) {
        queue.async { [weak self] in
            guard self != nil else { return }

            #if !targetEnvironment(macCatalyst)
            guard let deviceID = deviceID else {
                Logger.audio.info("Using system default audio input device")
                // AVAudioEngine uses default device when not configured
                return
            }

            guard let device = AVCaptureDevice(uniqueID: deviceID) else {
                Logger.audio.error("Failed to find audio device with ID: \(deviceID)")
                return
            }

            Logger.audio.info("Audio input device set to: \(device.localizedName)")
            // Note: AVAudioEngine doesn't provide direct device selection API.
            // This would require using Audio Units or Core Audio directly.
            // For MVP, we use the system default device.
            #endif
        }
    }

    // MARK: - Private Methods

    /// Internal implementation of startCapture (must be called on queue).
    private func _startCapture() throws {
        guard !isCapturing else {
            Logger.audio.warning("Audio capture already active")
            return
        }

        // Reset buffer
        buffer.reset()

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        Logger.audio.info("Input format: \(inputFormat.sampleRate) Hz, \(inputFormat.channelCount) channel(s)")

        // Check if format conversion is needed
        let needsConversion = inputFormat.sampleRate != targetFormat.sampleRate ||
                              inputFormat.channelCount != targetFormat.channelCount

        if needsConversion {
            // Create converter for format conversion
            guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
                Logger.audio.error("Failed to create audio converter")
                throw AudioCaptureError.formatConversionFailed
            }
            self.converter = converter
            Logger.audio.info("Audio converter created (input: \(inputFormat.sampleRate) Hz, output: \(self.targetFormat.sampleRate) Hz)")
        } else {
            self.converter = nil
            Logger.audio.info("No format conversion needed")
        }

        // Install tap on input node
        let bufferSize: AVAudioFrameCount = 4096
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] (buffer, time) in
            self?.handleAudioBuffer(buffer)
        }

        // Start engine
        try engine.start()

        DispatchQueue.main.async { [weak self] in
            self?.isCapturing = true
        }
        Logger.audio.info("Audio capture started")
    }

    /// Internal implementation of stopCapture (must be called on queue).
    private func _stopCapture() -> [Float] {
        guard isCapturing else {
            Logger.audio.warning("Audio capture not active")
            return []
        }

        // Stop engine and remove tap
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)

        DispatchQueue.main.async { [weak self] in
            self?.isCapturing = false
            self?.currentLevel = 0
        }

        // Read all samples from buffer
        let samples = buffer.readAll()

        Logger.audio.info("Audio capture stopped, captured \(samples.count) samples (\(String(format: "%.2f", Float(samples.count) / 16000.0))s)")

        return samples
    }

    /// Handle incoming audio buffer from the tap.
    /// - Parameter buffer: Audio buffer from AVAudioEngine tap.
    private func handleAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        let samples: [Float]

        if let converter = self.converter {
            // Convert format
            samples = convertBuffer(buffer, using: converter)
        } else {
            // Use buffer directly (already in target format)
            samples = extractSamples(from: buffer)
        }

        // Write to buffer
        self.buffer.write(samples)

        // Update audio level (~20fps throttle)
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastLevelUpdate > 0.05, !samples.isEmpty {
            lastLevelUpdate = now
            var sum: Float = 0
            for sample in samples {
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(samples.count))
            let level = min(1.0, rms * 5.0)
            DispatchQueue.main.async { [weak self] in
                self?.currentLevel = level
            }
        }
    }

    /// Convert audio buffer to target format.
    /// - Parameters:
    ///   - inputBuffer: Input audio buffer.
    ///   - converter: Audio converter.
    /// - Returns: Array of converted Float samples.
    private func convertBuffer(_ inputBuffer: AVAudioPCMBuffer, using converter: AVAudioConverter) -> [Float] {
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: AVAudioFrameCount(
                Float(inputBuffer.frameLength) * Float(targetFormat.sampleRate) / Float(inputBuffer.format.sampleRate)
            )
        ) else {
            Logger.audio.error("Failed to create output buffer for conversion")
            return []
        }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }

        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            Logger.audio.error("Audio conversion error: \(error.localizedDescription)")
            return []
        }

        return extractSamples(from: outputBuffer)
    }

    /// Extract Float samples from an AVAudioPCMBuffer.
    /// - Parameter buffer: PCM buffer.
    /// - Returns: Array of Float samples.
    private func extractSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else {
            Logger.audio.error("Failed to access buffer channel data")
            return []
        }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        var samples = [Float]()
        samples.reserveCapacity(frameLength)

        if channelCount == 1 {
            // Mono: copy directly
            let pointer = channelData[0]
            samples.append(contentsOf: UnsafeBufferPointer(start: pointer, count: frameLength))
        } else {
            // Multi-channel: mix down to mono by averaging channels
            for frame in 0..<frameLength {
                var sum: Float = 0.0
                for channel in 0..<channelCount {
                    sum += channelData[channel][frame]
                }
                samples.append(sum / Float(channelCount))
            }
        }

        return samples
    }
}

// MARK: - AudioCaptureError

enum AudioCaptureError: Error, LocalizedError {
    case serviceReleased
    case formatConversionFailed

    var errorDescription: String? {
        switch self {
        case .serviceReleased:
            return "Audio capture service was released"
        case .formatConversionFailed:
            return "Failed to create audio format converter"
        }
    }
}
