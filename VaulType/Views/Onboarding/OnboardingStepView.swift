import SwiftUI

/// Reusable step component for the onboarding wizard.
struct OnboardingStepView: View {
    let iconName: String
    let title: String
    let description: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: iconName)
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)

            Text(title)
                .font(.title)
                .fontWeight(.bold)

            Text(description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            if let actionLabel, let action {
                Button(actionLabel) {
                    action()
                }
                .buttonStyle(.bordered)
            } else if let actionLabel {
                Text(actionLabel)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(.horizontal, 40)
    }
}

#Preview {
    OnboardingStepView(
        iconName: "waveform.circle.fill",
        title: "Welcome to VaulType",
        description: "Privacy-first speech-to-text that runs entirely on your Mac."
    )
    .frame(width: 520, height: 380)
}
