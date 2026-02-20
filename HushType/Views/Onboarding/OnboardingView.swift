import os
import SwiftUI

/// First-launch onboarding wizard guiding users through setup.
struct OnboardingView: View {
    @State private var currentStep = 0
    @Environment(\.dismiss) private var dismiss

    private let totalSteps = 5

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { step in
                    Circle()
                        .fill(step <= currentStep ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 16)

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
                }

                Spacer()

                if currentStep < totalSteps - 1 {
                    Button("Continue") {
                        withAnimation { currentStep += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") {
                        completeOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
        .frame(width: 520, height: 480)
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
        OnboardingStepView(
            iconName: "mic.circle.fill",
            title: "Microphone Access",
            description: "HushType needs microphone access to capture your voice. All audio is processed locally and never leaves your device.",
            actionLabel: "Grant Microphone Access",
            action: {
                PermissionsManager().requestMicrophoneAccess()
            }
        )
    }

    private var accessibilityStep: some View {
        OnboardingStepView(
            iconName: "accessibility.fill",
            title: "Accessibility Permission",
            description: "Accessibility permission enables HushType to type text into any app and manage windows via voice commands.",
            actionLabel: "Open Accessibility Settings",
            action: {
                PermissionsManager().openAccessibilitySettings()
            }
        )
    }

    private var modelDownloadStep: some View {
        OnboardingStepView(
            iconName: "arrow.down.circle.fill",
            title: "Download Speech Model",
            description: "HushType uses a local AI model for speech recognition. The default model (Base English, ~150 MB) offers a good balance of speed and accuracy.",
            actionLabel: "Download will start automatically"
        )
    }

    private var completionStep: some View {
        OnboardingStepView(
            iconName: "checkmark.circle.fill",
            title: "You're All Set!",
            description: "Press and hold the fn key to start dictating. Release to stop and inject text at your cursor. You can customize everything in Settings."
        )
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "com.hushtype.onboardingCompleted")
        Logger.ui.info("Onboarding completed")
        dismiss()
    }
}

#Preview {
    OnboardingView()
}
