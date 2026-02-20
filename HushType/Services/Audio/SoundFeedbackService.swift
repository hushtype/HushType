import AppKit

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

    // MARK: - Sound Theme

    /// Sound theme presets.
    enum SoundTheme: String, CaseIterable, Identifiable {
        case subtle = "subtle"
        case mechanical = "mechanical"
        case none = "none"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .subtle: "Subtle"
            case .mechanical: "Mechanical"
            case .none: "None"
            }
        }
    }

    // MARK: - Properties

    /// Whether sound effects are enabled (master toggle).
    var isEnabled: Bool = true

    /// Current sound theme.
    var theme: SoundTheme = .subtle

    /// Sound volume (0.0 to 1.0).
    var volume: Float = 0.5

    // MARK: - Playback

    /// Play a sound for the given event.
    func play(_ event: SoundEvent) {
        guard isEnabled, theme != .none else { return }
        guard let name = soundName(for: event) else { return }
        guard let sound = NSSound(named: name) else { return }
        sound.volume = volume
        sound.play()
    }

    // MARK: - Private

    private func soundName(for event: SoundEvent) -> String? {
        switch theme {
        case .subtle:
            switch event {
            case .recordingStart:    return "Tink"
            case .recordingStop:     return "Pop"
            case .commandSuccess:    return "Glass"
            case .commandError:      return "Basso"
            case .injectionComplete: return "Pop"
            }
        case .mechanical:
            switch event {
            case .recordingStart:    return "Morse"
            case .recordingStop:     return "Purr"
            case .commandSuccess:    return "Funk"
            case .commandError:      return "Sosumi"
            case .injectionComplete: return "Purr"
            }
        case .none:
            return nil
        }
    }
}
