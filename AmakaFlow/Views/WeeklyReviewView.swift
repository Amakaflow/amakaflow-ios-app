import SwiftUI

struct WeeklyReviewView: View {
    let onDismiss: () -> Void

    private let sessions = [
        ReviewSession(icon: "figure.run", title: "Threshold run", status: "Hit", note: "Intervals held within target."),
        ReviewSession(icon: "dumbbell.fill", title: "Lower strength", status: "Modified", note: "Reduced hinge load after soreness."),
        ReviewSession(icon: "bicycle", title: "Recovery spin", status: "Skipped", note: "Replaced with rest day.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            AFTopBar(title: "Sunday review", subtitle: "Apr 20–26 · adherence and next-week coaching note") {
                Button(action: onDismiss) { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Back")
            } right: {
                Button("Done", action: onDismiss).font(Theme.Typography.captionBold)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    HStack(spacing: Theme.Spacing.sm) {
                        stat(label: "DONE", value: "5/6", sub: "sessions")
                        stat(label: "ADHERENCE", value: "83%", sub: "green")
                        stat(label: "LOAD", value: "+6", sub: "TSS vs plan")
                    }

                    AFLabel(text: "Session notes").padding(.top, Theme.Spacing.xs)
                    AFCard(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(sessions.enumerated()), id: \.offset) { index, session in
                                sessionRow(session)
                                if index < sessions.count - 1 { Divider().overlay(Theme.Colors.borderLight) }
                            }
                        }
                    }

                    AFLabel(text: "Coach note").padding(.top, Theme.Spacing.xs)
                    AFCard(padding: Theme.Spacing.md) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text("You absorbed the build well.")
                                .font(Theme.Typography.title3)
                                .foregroundColor(Theme.Colors.textPrimary)
                            Text("Keep Monday easy. We will move the heavy hinge to Wednesday and preserve the Friday threshold run if HRV rebounds.")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                                .lineSpacing(Theme.Spacing.xs)
                        }
                    }
                    .background(Theme.Colors.backgroundSubtle)

                    AFLabel(text: "Next week").padding(.top, Theme.Spacing.xs)
                    AFCard(padding: Theme.Spacing.md) {
                        HStack(spacing: Theme.Spacing.md) {
                            AFReadinessRing(value: 72, size: Theme.Spacing.xl * 2, stroke: Theme.Spacing.xs + 1)
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                Text("Build week · 7h 05m")
                                    .font(Theme.Typography.title3)
                                    .foregroundColor(Theme.Colors.textPrimary)
                                Text("Two run quality days, one long aerobic day, two strength sessions.")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.textSecondary)
                                    .lineSpacing(Theme.Spacing.xs)
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
            }
        }
        .background(Theme.Colors.background.ignoresSafeArea())
    }

    private func stat(label: String, value: String, sub: String) -> some View {
        AFCard(padding: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                AFLabel(text: label)
                Text(value)
                    .font(Theme.Typography.title1)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(sub)
                    .font(Theme.Typography.footnote)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sessionRow(_ session: ReviewSession) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: session.icon)
                .foregroundColor(Theme.Colors.textPrimary)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(session.title)
                    .font(Theme.Typography.title3)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(session.note)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            Spacer()
            AFChip(text: session.status, outline: true)
        }
        .padding(Theme.Spacing.md)
    }
}

private struct ReviewSession {
    let icon: String
    let title: String
    let status: String
    let note: String
}

#Preview {
    WeeklyReviewView {}
        .preferredColorScheme(.dark)
}
