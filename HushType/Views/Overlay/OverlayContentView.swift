import SwiftUI
import os

/// SwiftUI content view displayed inside the OverlayWindow.
/// Shows transcription result with optional edit-before-inject capability.
struct OverlayContentView: View {
    var appState: AppState

    @State private var editableText: String = ""
    @State private var isEditing: Bool = false
    @FocusState private var textFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            headerBar

            Divider()

            // MARK: - Content
            if let text = appState.overlayText, !text.isEmpty {
                if isEditing {
                    editView
                } else {
                    displayView(text: text)
                }
            } else if appState.isProcessing {
                processingView
            } else {
                emptyView
            }

            Divider()

            // MARK: - Footer Controls
            footerBar
        }
        .frame(width: 420)
        .frame(minHeight: 120)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .onChange(of: appState.overlayText ?? "") { oldValue, newValue in
            if !newValue.isEmpty {
                editableText = newValue
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 8) {
            // Mode indicator
            HStack(spacing: 4) {
                Image(systemName: appState.activeMode.iconName)
                    .font(.caption2)
                Text(appState.activeMode.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.secondary)

            // Language indicator
            if let lang = appState.detectedLanguage {
                Text(lang.uppercased())
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule())
            }

            Spacer()

            // Status
            if appState.isProcessing {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                    Text("Processing...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Display View (read-only)

    private func displayView(text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
        }
        .frame(maxHeight: 200)
    }

    // MARK: - Edit View

    private var editView: some View {
        TextEditor(text: $editableText)
            .font(.body)
            .focused($textFieldFocused)
            .frame(maxHeight: 200)
            .padding(6)
            .scrollContentBackground(.hidden)
            .onAppear {
                textFieldFocused = true
            }
    }

    // MARK: - Processing View

    private var processingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Transcribing...")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 60)
        .padding(14)
    }

    // MARK: - Empty View

    private var emptyView: some View {
        Text("Waiting for transcription...")
            .font(.body)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, minHeight: 60)
            .padding(14)
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: 10) {
            if isEditing {
                Button("Cancel") {
                    appState.overlayEditCancelled = true
                    isEditing = false
                }
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button("Inject") {
                    appState.overlayEditedText = editableText
                    appState.overlayEditConfirmed = true
                    isEditing = false
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                Button {
                    isEditing = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .controlSize(.small)
                .disabled(appState.overlayText == nil)

                Spacer()

                Button("Dismiss") {
                    appState.showOverlay = false
                }
                .keyboardShortcut(.escape, modifiers: [])
                .controlSize(.small)

                Button("Inject") {
                    appState.overlayEditConfirmed = true
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(appState.overlayText == nil)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
