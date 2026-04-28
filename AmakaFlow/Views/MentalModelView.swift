import SwiftUI

struct MentalModelView: View {
    let onContinue: () -> Void
    let onSkip: () -> Void

    private let places = [
        MentalModelPlace(icon: "iphone", title: "Phone app", body: "Plan, review, and approve coach decisions before they change your week."),
        MentalModelPlace(icon: "applewatch", title: "Garmin watch", body: "The right workout appears when it is time to train — no copying intervals."),
        MentalModelPlace(icon: "bolt.fill", title: "Coach agent", body: "Watches recovery, missed sessions, and data gaps so your plan stays current.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            AFTopBar {
                Button(action: onSkip) {
                    Image(systemName: "chevron.left")
                }
            } right: {
                Button("Skip", action: onSkip)
                    .font(Theme.Typography.captionBold)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        AFLabel(text: "Mental model")
                        Text("Three places. One coach.")
                            .font(Theme.Typography.largeTitle)
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text("AmakaFlow keeps the app, watch, and coach agent in sync so every training decision has a visible home.")
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .lineSpacing(Theme.Spacing.xs)
                    }
                    .padding(.top, Theme.Spacing.lg)

                    AFCard(padding: Theme.Spacing.xs) {
                        VStack(spacing: 0) {
                            ForEach(Array(places.enumerated()), id: \.element.title) { index, place in
                                mentalModelRow(place)
                                if index < places.count - 1 {
                                    Divider().overlay(Theme.Colors.borderLight)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
            }

            Button {
                onContinue()
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Text("Pair my watch")
                    Image(systemName: "chevron.right")
                }
            }
            .buttonStyle(AFPrimaryButtonStyle())
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
    }

    private func mentalModelRow(_ place: MentalModelPlace) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .fill(Theme.Colors.backgroundSubtle)
                .frame(width: Theme.Spacing.xl + Theme.Spacing.sm, height: Theme.Spacing.xl + Theme.Spacing.sm)
                .overlay(
                    Image(systemName: place.icon)
                        .font(Theme.Typography.title2)
                        .foregroundColor(Theme.Colors.textPrimary)
                )

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(place.title)
                    .font(Theme.Typography.title3)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(place.body)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineSpacing(Theme.Spacing.xs)
            }
        }
        .padding(Theme.Spacing.md)
    }
}

private struct MentalModelPlace {
    let icon: String
    let title: String
    let body: String
}

#Preview {
    MentalModelView(onContinue: {}, onSkip: {})
        .preferredColorScheme(.dark)
}
