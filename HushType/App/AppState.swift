import Foundation
import SwiftUI

@Observable
final class AppState {
    // MARK: - Recording State

    var isRecording: Bool = false
    var isProcessing: Bool = false

    var isPipelineActive: Bool {
        isRecording || isProcessing
    }

    // MARK: - Active Mode

    var activeMode: ProcessingMode = .raw

    // MARK: - Menu Bar Icon State

    var menuBarIcon: String {
        if isRecording {
            return "mic.fill"
        } else if isProcessing {
            return "waveform"
        } else {
            return "mic"
        }
    }

    // MARK: - Last Transcription Preview

    var lastTranscriptionPreview: String?

    // MARK: - Error State

    var currentError: String?
}
