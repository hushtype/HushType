//
//  MenuBarView.swift
//  HushType
//
//  Created by Claude on 14.02.2026.
//

import SwiftUI
import os.log

struct MenuBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: - Status Section
            VStack(alignment: .leading, spacing: 6) {
                if appState.isRecording {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                        Text("Recording...")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                } else if appState.isProcessing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 8, height: 8)
                        Text("Processing...")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                } else {
                    Text("Ready")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                // Active mode indicator
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(appState.activeMode.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // MARK: - Last Transcription Preview
            if let preview = appState.lastTranscriptionPreview, !preview.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last Transcription")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(truncatePreview(preview))
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }

                Divider()
            }

            // MARK: - Error Display
            if let error = appState.currentError {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text("Error")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }

                Divider()
            }

            // MARK: - Action Buttons
            VStack(spacing: 8) {
                Button {
                    openSettings()
                } label: {
                    HStack {
                        Image(systemName: "gearshape")
                        Text("Settings...")
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)

                Button {
                    quitApp()
                } label: {
                    HStack {
                        Image(systemName: "power")
                        Text("Quit HushType")
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    // MARK: - Helper Methods

    private func truncatePreview(_ text: String) -> String {
        let maxLength = 120
        if text.count <= maxLength {
            return text
        }
        return String(text.prefix(maxLength)) + "..."
    }

    private func openSettings() {
        Logger.ui.info("Opening Settings window")
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func quitApp() {
        Logger.general.info("User requested quit from menu bar")
        NSApp.terminate(nil)
    }
}

#Preview {
    MenuBarView()
        .environment(AppState())
}
