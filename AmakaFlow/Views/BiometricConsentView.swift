import SwiftUI

struct BiometricConsentView: View {
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 64))
                .foregroundColor(Theme.Colors.accentGreen)

            VStack(spacing: Theme.Spacing.sm) {
                Text("Before we begin")
                    .font(Theme.Typography.title1)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("AmakaFlow uses biometric data — heart rate, HRV, training load, and sleep — to personalise your plan and coach you in real time.\n\nThis data is processed by AI and stored securely. You can export or delete it at any time from Settings → Privacy.")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.lg)
            }

            VStack(spacing: Theme.Spacing.sm) {
                Button(action: onAccept) {
                    Text("I agree — continue")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.Colors.accentGreen)
                        .cornerRadius(Theme.CornerRadius.md)
                }
                .accessibilityIdentifier("biometric_consent_accept")

                Button(action: onDecline) {
                    Text("No thanks")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .accessibilityIdentifier("biometric_consent_decline")
            }
            .padding(.horizontal, Theme.Spacing.lg)

            Spacer()

            Link(destination: URL(string: "https://app.amakaflow.com/privacy")!) {
                Text("Privacy notice")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
                    .underline()
            }
            .padding(.bottom, Theme.Spacing.lg)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .accessibilityIdentifier("biometric_consent_view")
    }
}

#Preview {
    BiometricConsentView(onAccept: {}, onDecline: {})
        .preferredColorScheme(.dark)
}
