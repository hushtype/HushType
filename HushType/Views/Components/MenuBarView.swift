//
//  MenuBarView.swift
//  HushType
//
//  Created by Claude on 14.02.2026.
//

import SwiftUI
import os.log

struct MenuBarView: View {
    var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: - Status Section
            VStack(alignment: .leading, spacing: 6) {
                if appState.isRecording {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text("Recording...")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Status: Recording")
                } else if appState.isProcessing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text("Processing...")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Status: Processing transcription")
                } else {
                    Text("Ready")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Status: Ready")
                }

                // Active mode indicator
                HStack(spacing: 6) {
                    Image(systemName: appState.activeMode.iconName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(appState.activeMode.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Language indicator
                    if let lang = appState.detectedLanguage {
                        Text(lang.uppercased())
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    appState.detectedLanguage.map { lang in
                        "Mode: \(appState.activeMode.displayName), Language: \(lang.uppercased())"
                    } ?? "Mode: \(appState.activeMode.displayName)"
                )
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
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Last transcription: \(truncatePreview(preview))")

                Divider()
            }

            // MARK: - Error Display
            if let error = appState.currentError {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        Text("Error")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Error: \(error)")

                Divider()
            }

            // MARK: - Action Buttons
            VStack(spacing: 8) {
                Button {
                    openWindow(id: "history")
                } label: {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("History")
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("h", modifiers: .command)
                .accessibilityLabel("History")
                .accessibilityHint("Opens the dictation history window")

                SettingsLink {
                    HStack {
                        Image(systemName: "gearshape")
                        Text("Settings")
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(SettingsButtonStyle())
                .foregroundStyle(.primary)
                .accessibilityLabel("Settings")
                .accessibilityHint("Opens the HushType settings window")

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
                .keyboardShortcut("q", modifiers: .command)
                .foregroundStyle(.red)
                .accessibilityLabel("Quit HushType")
                .accessibilityHint("Exits the application")
            }
        }
        .padding(12)
        .frame(width: 280)
        .onDisappear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                let hasSettingsWindow = NSApp.windows.contains { $0.isVisible && $0.level == .normal }
                if hasSettingsWindow {
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
    }

    // MARK: - Helper Methods

    private func truncatePreview(_ text: String) -> String {
        let maxLength = 120
        if text.count <= maxLength {
            return text
        }
        return String(text.prefix(maxLength)) + "..."
    }

    private func quitApp() {
        Logger.general.info("User requested quit from menu bar")
        NSApp.terminate(nil)
    }
}

private struct SettingsButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed {
                    // Activate after SettingsLink opens/shows the settings window
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
            }
    }
}

#Preview {
    MenuBarView(appState: AppState())
}
