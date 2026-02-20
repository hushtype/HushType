import AVFoundation
import os
import SwiftData
import SwiftUI

/// First-launch onboarding wizard guiding users through setup.
struct OnboardingView: View {
    @State private var currentStep = 0
    @State private var permissionsManager = PermissionsManager()
    @State private var microphoneGranted: Bool = false
    @State private var pollingTimer: Timer?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var allModels: [ModelInfo]

    /// The default whisper model, looked up from the full model list.
    private var defaultWhisperModel: ModelInfo? {
        allModels.first { $0.isDefault && $0.type == .whisper }
    }

    private let totalSteps = 5

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { step in
                    Circle()
                        .fill(step <= currentStep ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .accessibilityLabel(step < currentStep ? "Step \(step + 1) completed" : step == currentStep ? "Step \(step + 1), current" : "Step \(step + 1)")
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 16)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Setup progress: step \(currentStep + 1) of \(totalSteps)")

            // Step content
            TabView(selection: $currentStep) {
                welcomeStep.tag(0)
                microphoneStep.tag(1)
                accessibilityStep.tag(2)
                modelDownloadStep.tag(3)
                completionStep.tag(4)
            }
            .tabViewStyle(.automatic)

            // Navigation buttons
            HStack {
                if currentStep > 0 && currentStep < totalSteps - 1 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                    .accessibilityLabel("Back")
                    .accessibilityHint("Goes to the previous setup step")
                }

                Spacer()

                if currentStep < totalSteps - 1 {
                    Button("Continue") {
                        withAnimation { currentStep += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Continue")
                    .accessibilityHint("Proceeds to the next setup step")
                } else {
                    Button("Get Started") {
                        completeOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Get started")
                    .accessibilityHint("Completes the setup and opens HushType")
                }
            }
            .padding(24)
        }
        .frame(width: 520, height: 480)
        .onAppear {
            refreshMicrophoneStatus()
            permissionsManager.refreshAccessibilityStatus()
        }
        .onChange(of: currentStep) { _, newStep in
            stopPolling()
            if newStep == 1 || newStep == 2 {
                startPolling()
            }
        }
        .onDisappear {
            stopPolling()
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        OnboardingStepView(
            iconName: "waveform.circle.fill",
            title: "Welcome to HushType",
            description: "Privacy-first speech-to-text that runs entirely on your Mac. No cloud, no telemetry — just your voice and your machine."
        )
    }

    private var microphoneStep: some View {
        VStack(spacing: 20) {
            Spacer()

            if microphoneGranted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.green)
            } else {
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)
            }

            Text("Microphone Access")
                .font(.title)
                .fontWeight(.bold)

            Text("HushType needs microphone access to capture your voice. All audio is processed locally and never leaves your device.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            if microphoneGranted {
                Label("Microphone access granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.green)
                    .font(.callout)
                    .accessibilityLabel("Microphone access granted")
            } else {
                Button("Grant Microphone Access") {
                    permissionsManager.requestMicrophoneAccess()
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Grant microphone access")
                .accessibilityHint("Opens the system permission dialog to allow HushType to use the microphone")

                Text("Microphone access is required for dictation. You can grant it later in System Settings.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            Spacer()
        }
        .padding(.horizontal, 40)
    }

    private var accessibilityStep: some View {
        VStack(spacing: 20) {
            Spacer()

            if permissionsManager.accessibilityEnabled {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.green)
            } else {
                Image(systemName: "accessibility.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)
            }

            Text("Accessibility Permission")
                .font(.title)
                .fontWeight(.bold)

            Text("Accessibility permission enables HushType to type text into any app and manage windows via voice commands.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            if permissionsManager.accessibilityEnabled {
                Label("Accessibility access granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.green)
                    .font(.callout)
                    .accessibilityLabel("Accessibility access granted")
            } else {
                Button("Open Accessibility Settings") {
                    permissionsManager.openAccessibilitySettings()
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Open Accessibility Settings")
                .accessibilityHint("Opens System Settings so you can grant HushType accessibility permission for text injection and window management")

                Text("Without accessibility permission, text injection may be limited. You can grant it later in System Settings.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            Spacer()
        }
        .padding(.horizontal, 40)
    }

    private var modelDownloadStep: some View {
        VStack(spacing: 20) {
            Spacer()

            if let model = defaultWhisperModel, model.isDownloaded {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.green)
            } else {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)
            }

            Text("Download Speech Model")
                .font(.title)
                .fontWeight(.bold)

            Text("HushType uses a local AI model for speech recognition. The default model (Base English, ~150 MB) offers a good balance of speed and accuracy.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            if let model = defaultWhisperModel {
                if model.isDownloaded {
                    Label("\(model.name) is ready", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                        .font(.callout)
                } else if let progress = model.downloadProgress {
                    VStack(spacing: 8) {
                        ProgressView(value: progress)
                            .frame(maxWidth: 300)
                        Text("Downloading \(model.name)… \(Int(progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let errorMsg = model.lastDownloadError {
                    Text("Download failed: \(errorMsg)")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                } else {
                    Text("Download will start automatically")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("Download will start automatically")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(.horizontal, 40)
    }

    private var completionStep: some View {
        OnboardingStepView(
            iconName: "checkmark.circle.fill",
            title: "You're All Set!",
            description: "Press and hold the fn key to start dictating. Release to stop and inject text at your cursor. You can customize everything in Settings."
        )
    }

    // MARK: - Permission Polling

    private func startPolling() {
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            refreshMicrophoneStatus()
            permissionsManager.refreshAccessibilityStatus()
        }
    }

    private func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    private func refreshMicrophoneStatus() {
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    // MARK: - Completion

    private func completeOnboarding() {
        stopPolling()
        UserDefaults.standard.set(true, forKey: "com.hushtype.onboardingCompleted")
        Logger.ui.info("Onboarding completed")
        dismiss()
    }
}

#Preview {
    OnboardingView()
}
