//
//  MenuBarManager.swift
//  HushType
//
//  Created by Claude on 14.02.2026.
//

import Foundation
import Observation
import os.log

@Observable
final class MenuBarManager {
    // MARK: - Properties

    /// The currently displayed animated icon during processing.
    private(set) var animatedIcon: String = "waveform"

    /// Animation timer for cycling through waveform icons.
    private var animationTimer: Timer?

    /// Index for cycling through animation frames.
    private var animationIndex: Int = 0

    /// Animation frames for processing state.
    private let animationFrames: [String] = [
        "waveform",
        "waveform.circle",
        "waveform.circle.fill"
    ]

    // MARK: - Lifecycle

    deinit {
        stopProcessingAnimation()
    }

    // MARK: - Animation Control

    /// Start the menu bar icon animation during processing.
    /// Cycles through waveform SF Symbols at a fixed interval.
    func startProcessingAnimation() {
        guard animationTimer == nil else {
            Logger.ui.debug("Processing animation already running")
            return
        }

        Logger.ui.info("Starting menu bar processing animation")
        animationIndex = 0
        animatedIcon = animationFrames[animationIndex]

        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.animationIndex = (self.animationIndex + 1) % self.animationFrames.count
            self.animatedIcon = self.animationFrames[self.animationIndex]
        }
    }

    /// Stop the menu bar icon animation.
    func stopProcessingAnimation() {
        guard animationTimer != nil else { return }

        Logger.ui.info("Stopping menu bar processing animation")
        animationTimer?.invalidate()
        animationTimer = nil
        animationIndex = 0
        animatedIcon = "waveform"
    }
}
