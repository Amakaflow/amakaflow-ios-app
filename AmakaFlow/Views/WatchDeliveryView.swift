import SwiftUI

struct WatchDeliveryView: View {
    let onResend: () -> Void
    let onDismiss: () -> Void

    private let states = [
        WatchDeliveryState(label: "Queued", icon: "clock", body: "Workout is waiting for the next Garmin sync.", tone: Theme.Colors.textSecondary, action: false),
        WatchDeliveryState(label: "Sending", icon: "arrow.2.circlepath", body: "AmakaFlow is pushing intervals to your watch.", tone: Theme.Colors.readyModerate, action: false),
        WatchDeliveryState(label: "On watch", icon: "checkmark", body: "Ready to start from Training Calendar.", tone: Theme.Colors.accentGreen, action: false),
        WatchDeliveryState(label: "Delayed", icon: "info.circle", body: "Garmin has not confirmed delivery yet.", tone: Theme.Colors.readyModerate, action: true),
        WatchDeliveryState(label: "Failed", icon: "xmark.circle", body: "Last send failed. Try again when your watch is nearby.", tone: Theme.Colors.accentRed, action: true)
    ]

    var body: some View {
        VStack(spacing: 0) {
            AFTopBar(title: "Watch delivery", subtitle: "All Garmin workout send states.") {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Back")
            } right: {
                Button("Done", action: onDismiss).font(Theme.Typography.captionBold)
            }

            ScrollView {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(states) { state in
                        deliveryRow(state)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
            }
        }
        .background(Theme.Colors.background.ignoresSafeArea())
    }

    private func deliveryRow(_ state: WatchDeliveryState) -> some View {
        AFCard(padding: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .fill(Theme.Colors.backgroundSubtle)
                    .frame(width: Theme.Spacing.xl + Theme.Spacing.xs, height: Theme.Spacing.xl + Theme.Spacing.xs)
                    .overlay(
                        Image(systemName: state.icon)
                            .font(Theme.Typography.title3)
                            .foregroundColor(state.tone)
                    )

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(state.label)
                        .font(Theme.Typography.title3)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(state.body)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineSpacing(Theme.Spacing.xs)
                    if state.action {
                        Button {
                            onResend()
                        } label: {
                            Label("Resend to watch", systemImage: "applewatch")
                        }
                        .buttonStyle(AFGhostButtonStyle())
                        .padding(.top, Theme.Spacing.xs)
                    }
                }
            }
        }
    }
}

private struct WatchDeliveryState: Identifiable {
    let label: String
    var id: String { label }
    let icon: String
    let body: String
    let tone: Color
    let action: Bool
}

#Preview {
    WatchDeliveryView(onResend: {}, onDismiss: {})
        .preferredColorScheme(.dark)
}
