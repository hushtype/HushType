import AppKit
import Foundation
import SwiftUI

@Observable
final class AppState {
    // MARK: - Recording State

    var isRecording: Bool = false {
        didSet { updateMenuBarState() }
    }
    var isProcessing: Bool = false {
        didSet { updateMenuBarState() }
    }

    // MARK: - Active Mode

    var activeMode: ProcessingMode = .raw

    // MARK: - Menu Bar Icon

    /// The menu bar image — always use Image(nsImage:) in the label.
    var menuBarImage: NSImage = renderStaticBars()

    private var animationTimer: Timer?
    private var animationTime: Double = 0

    // Waveform bar configuration
    private static let barCount = 5
    private static let barWidth: CGFloat = 1.2
    private static let barSpacing: CGFloat = 2.0
    private static let barMaxHeight: CGFloat = 16
    private static let barMinHeight: CGFloat = 2.5
    private static let imageSize = NSSize(width: 18, height: 18)

    // Idle bar heights matching the SF Symbol waveform shape: short-medium-tall-medium-short
    private static let idleHeights: [CGFloat] = [4, 9, 15, 9, 4]

    // Layered sine waves: primary traveling wave + slower modulation for organic feel
    private static let primarySpeed: Double = 3.0
    private static let primaryPhaseStep: Double = 0.8
    private static let secondarySpeed: Double = 1.1
    private static let secondaryPhaseStep: Double = 1.3
    private static let tertiarySpeed: Double = 0.4
    private static let tertiaryPhaseStep: Double = 2.1

    private func updateMenuBarState() {
        stopAnimation()
        if isRecording {
            startWaveformAnimation()
        } else if isProcessing {
            startProcessingAnimation()
        } else {
            menuBarImage = Self.renderStaticBars()
        }
    }

    // MARK: - Static Idle Bars (matches waveform SF Symbol shape)

    private static func renderStaticBars() -> NSImage {
        renderBars(heights: idleHeights)
    }

    // MARK: - Recording Animation (waveform bars)

    private func startWaveformAnimation() {
        animationTime = 0
        menuBarImage = renderAnimatedBars(at: animationTime)
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.animationTime += 0.08
            self.menuBarImage = self.renderAnimatedBars(at: self.animationTime)
        }
    }

    private func renderAnimatedBars(at time: Double) -> NSImage {
        var heights: [CGFloat] = []
        for i in 0..<Self.barCount {
            let idx = Double(i)
            // Primary wave: main rhythm traveling across bars
            let primary = sin(time * Self.primarySpeed - idx * Self.primaryPhaseStep) * 0.55
            // Secondary wave: slower, wider modulation
            let secondary = sin(time * Self.secondarySpeed - idx * Self.secondaryPhaseStep) * 0.3
            // Tertiary wave: slow drift so the pattern evolves over time
            let tertiary = sin(time * Self.tertiarySpeed - idx * Self.tertiaryPhaseStep) * 0.15

            let combined = primary + secondary + tertiary
            let normalized = (combined + 1) / 2
            let height = Self.barMinHeight + (Self.barMaxHeight - Self.barMinHeight) * normalized
            heights.append(height)
        }
        return Self.renderBars(heights: heights, color: .systemRed, template: false)
    }

    // MARK: - Bar Rendering

    private static func renderBars(
        heights: [CGFloat],
        color: NSColor = .black,
        template: Bool = true
    ) -> NSImage {
        let size = imageSize
        let image = NSImage(size: size, flipped: false) { _ in
            let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
            let startX = (size.width - totalWidth) / 2

            color.setFill()

            for i in 0..<barCount {
                let height = heights[i]
                let x = startX + CGFloat(i) * (barWidth + barSpacing)
                let y = (size.height - height) / 2

                let barRect = NSRect(x: x, y: y, width: barWidth, height: height)
                let path = NSBezierPath(roundedRect: barRect, xRadius: 0.6, yRadius: 0.6)
                path.fill()
            }
            return true
        }
        image.isTemplate = template
        return image
    }

    // MARK: - Processing Animation (pulsing bars in monochrome)

    private func startProcessingAnimation() {
        animationTime = 0
        menuBarImage = renderProcessingBars(at: animationTime)
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.animationTime += 0.08
            self.menuBarImage = self.renderProcessingBars(at: self.animationTime)
        }
    }

    private func renderProcessingBars(at time: Double) -> NSImage {
        // All bars pulse together in a slow breathe
        let pulse = (sin(time * 2.0) + 1) / 2
        var heights: [CGFloat] = []
        for i in 0..<Self.barCount {
            let base = Self.idleHeights[i]
            let height = base + (Self.barMaxHeight - base) * pulse * 0.5
            heights.append(height)
        }
        return Self.renderBars(heights: heights)
    }

    // MARK: - Helpers

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    // MARK: - Last Transcription Preview

    var lastTranscriptionPreview: String?

    // MARK: - Error State

    var currentError: String?

    // MARK: - Overlay State

    /// Text to display in the overlay (set after transcription/processing completes).
    var overlayText: String?

    /// Whether the overlay should be visible.
    var showOverlay: Bool = false

    /// Detected language from the last transcription.
    var detectedLanguage: String?

    /// Text edited by the user in the overlay (for edit-before-inject).
    var overlayEditedText: String?

    /// Set to true when user confirms injection from overlay.
    var overlayEditConfirmed: Bool = false

    /// Set to true when user cancels injection from overlay.
    var overlayEditCancelled: Bool = false

    // MARK: - Command State

    /// Whether a voice command is currently being executed.
    var isExecutingCommand: Bool = false

    /// Human-readable result of the last voice command execution.
    var lastCommandResult: String?

    /// Shared command registry used by both the pipeline and settings UI.
    var commandRegistry: CommandRegistry?

    // MARK: - Plugin State

    /// Shared plugin manager used by both the pipeline and settings UI.
    var pluginManager: PluginManager = PluginManager()

    // MARK: - System Accessibility Preferences

    /// True when the user has enabled Reduce Motion in System Settings > Accessibility.
    var prefersReducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// True when the user has enabled Reduce Transparency in System Settings > Accessibility.
    var prefersReducedTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    /// True when the user has enabled Increase Contrast in System Settings > Accessibility.
    var prefersHighContrast: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    // MARK: - Accessibility Announcements

    /// Post an NSAccessibility announcement so VoiceOver reads the message aloud.
    func announceStateChange(_ message: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high
            ]
        )
    }

    func announceRecordingStarted() {
        announceStateChange("Recording started")
    }

    func announceRecordingCompleted() {
        announceStateChange("Recording stopped")
    }

    func announceProcessing() {
        announceStateChange("Processing transcription")
    }

    func announceProcessingComplete() {
        announceStateChange("Processing complete")
    }

    func announceError(_ message: String) {
        announceStateChange(message)
    }
}
