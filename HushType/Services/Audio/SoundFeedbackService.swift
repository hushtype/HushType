import AppKit
import os

// MARK: - SoundFeedbackService

/// Manages audio feedback sounds for dictation and command events.
final class SoundFeedbackService {
    // MARK: - Sound Events

    /// Sound events that trigger audio feedback.
    enum SoundEvent {
        case recordingStart
        case recordingStop
        case commandSuccess
        case commandError
        case injectionComplete
    }

    // MARK: - Properties

    /// Whether sound effects are enabled (master toggle).
    var isEnabled: Bool = true

    // MARK: - Playback

    /// Play a sound for the given event.
    func play(_ event: SoundEvent) {
        guard isEnabled else { return }
        NSSound(named: soundName(for: event))?.play()
    }

    // MARK: - Private

    private func soundName(for event: SoundEvent) -> String {
        switch event {
        case .recordingStart:    return "Tink"
        case .recordingStop:     return "Pop"
        case .commandSuccess:    return "Glass"
        case .commandError:      return "Basso"
        case .injectionComplete: return "Pop"
        }
    }
}
