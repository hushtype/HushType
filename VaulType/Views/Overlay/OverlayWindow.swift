import AppKit
import SwiftUI
import os

/// Floating NSPanel for showing transcription results and edit-before-inject UI.
/// Owned by AppDelegate. Non-activating so it doesn't steal focus from the target app.
final class OverlayWindow: NSPanel {
    // MARK: - Configuration

    enum Position: String, CaseIterable {
        case nearCursor = "nearCursor"
        case topCenter = "topCenter"
        case bottomCenter = "bottomCenter"
        case center = "center"

        var displayName: String {
            switch self {
            case .nearCursor: "Near Cursor"
            case .topCenter: "Top Center"
            case .bottomCenter: "Bottom Center"
            case .center: "Center"
            }
        }
    }

    // MARK: - Properties

    private var hostingView: NSHostingView<OverlayContentView>?
    private var appState: AppState?

    // MARK: - Initialization

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )

        configurePanel()
        Logger.ui.info("OverlayWindow initialized")
    }

    private func configurePanel() {
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        animationBehavior = .utilityWindow

        // Don't show in Mission Control or Expose
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    // MARK: - Content Setup

    /// Set the SwiftUI content view with app state binding.
    func setContent(appState: AppState) {
        self.appState = appState
        applyTransparencyPreference(appState: appState)
        let contentView = OverlayContentView(appState: appState)
        let hosting = NSHostingView(rootView: contentView)
        hosting.frame = contentRect(forFrameRect: frame)
        self.contentView = hosting
        self.hostingView = hosting
    }

    /// Adjust panel transparency to respect the system "Reduce Transparency" preference.
    func applyTransparencyPreference(appState: AppState) {
        if appState.prefersReducedTransparency {
            isOpaque = true
            backgroundColor = NSColor.windowBackgroundColor
        } else {
            isOpaque = false
            backgroundColor = .clear
        }
    }

    // MARK: - Show / Hide

    /// Show the overlay at the configured position with optional opacity.
    func showOverlay(position: Position = .bottomCenter, opacity: Double = 0.95) {
        // Re-evaluate transparency preference on each show in case settings changed.
        if let appState {
            applyTransparencyPreference(appState: appState)
        }
        alphaValue = opacity
        positionWindow(position)
        orderFrontRegardless()
        Logger.ui.info("Overlay shown at \(position.rawValue)")
    }

    /// Hide the overlay.
    func hideOverlay() {
        orderOut(nil)
        Logger.ui.info("Overlay hidden")
    }

    // MARK: - Positioning

    private func positionWindow(_ position: Position) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let windowSize = frame.size

        var origin: NSPoint

        switch position {
        case .nearCursor:
            let mouseLocation = NSEvent.mouseLocation
            // Position below and slightly right of cursor
            origin = NSPoint(
                x: mouseLocation.x - windowSize.width / 2,
                y: mouseLocation.y - windowSize.height - 20
            )
            // Clamp to screen bounds
            origin.x = max(screenFrame.minX, min(origin.x, screenFrame.maxX - windowSize.width))
            origin.y = max(screenFrame.minY, min(origin.y, screenFrame.maxY - windowSize.height))

        case .topCenter:
            origin = NSPoint(
                x: screenFrame.midX - windowSize.width / 2,
                y: screenFrame.maxY - windowSize.height - 40
            )

        case .bottomCenter:
            origin = NSPoint(
                x: screenFrame.midX - windowSize.width / 2,
                y: screenFrame.minY + 40
            )

        case .center:
            origin = NSPoint(
                x: screenFrame.midX - windowSize.width / 2,
                y: screenFrame.midY - windowSize.height / 2
            )
        }

        setFrameOrigin(origin)
    }

    // MARK: - Key Handling

    /// Allow the overlay to become key window for text editing,
    /// but only when explicitly requested (edit-before-inject mode).
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
