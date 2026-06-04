//
//  LandingView.swift
//  AmakaFlow
//
//  Marketing landing shell (`screens-marketing.jsx` → LandingMobile).
//

import SwiftUI

struct LandingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var didJoin = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                hero
                previewCard
                howItWorks
                productStory
                footer
            }
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .accessibilityIdentifier("landing_screen")
    }

    private var topBar: some View {
        HStack {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.Colors.textPrimary)
                    .frame(width: 22, height: 22)
                    .overlay {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Theme.Colors.background)
                    }
                Text("AmakaFlow")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.Colors.textPrimary)
            }

            Spacer()

            AFChip(text: "BETA", outline: true)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.lg)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            AFLabel(text: "ADAPTIVE COACHING FOR HYBRID ATHLETES")
            Text("Train on the\nright day.")
                .font(.system(size: 36, weight: .semibold))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineSpacing(2)
            Text("An AI coach for hybrid athletes. Every 6am, your plan adapts to HRV, sleep, and yesterday's load.")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
                .lineSpacing(3)
                .padding(.top, Theme.Spacing.xs)

            if didJoin {
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    Image(systemName: "checkmark")
                        .foregroundColor(Theme.Colors.readyHigh)
                    Text("You're on the list. We'll email when your spot opens.")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textPrimary)
                }
                .padding(Theme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Colors.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous)
                        .stroke(Theme.Colors.borderLight, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous))
                .padding(.top, Theme.Spacing.md)
            } else {
                HStack(spacing: Theme.Spacing.sm) {
                    TextField("your@email.com", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .font(Theme.Typography.body)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, 12)
                        .background(Theme.Colors.inputBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous)
                                .stroke(Theme.Colors.borderLight, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous))
                        .accessibilityIdentifier("landing_email_field")

                    Button {
                        guard email.contains("@") else { return }
                        didJoin = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("Join")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .buttonStyle(AFPrimaryButtonStyle(size: .md, isWide: false))
                    .accessibilityIdentifier("landing_join_button")
                }
                .padding(.top, Theme.Spacing.md)
            }

            Text("1,482 ATHLETES ON WAITLIST · NEXT COHORT MAY 15")
                .font(Theme.Typography.label)
                .foregroundColor(Theme.Colors.textTertiary)
                .padding(.top, Theme.Spacing.sm)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.xl)
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                AFReadinessRing(value: 84, size: 56, stroke: 5)
                VStack(alignment: .leading, spacing: 4) {
                    AFLabel(text: "READINESS · TODAY")
                    Text("Ready")
                        .font(Theme.Typography.title3)
                        .foregroundColor(Theme.Colors.textPrimary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                AFLabel(text: "THRESHOLD RUN")
                Text("4×8 min @ threshold")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("64m · Z3–4 · TSS 78")
                    .font(Theme.Typography.mono)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.surfaceElevated)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous)
                    .stroke(Theme.Colors.borderLight, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous))
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.backgroundSubtle)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg, style: .continuous)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg, style: .continuous))
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.xl)
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 0) {
            AFLabel(text: "HOW IT WORKS")
                .padding(.bottom, Theme.Spacing.sm)

            ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    Text(step.number)
                        .font(Theme.Typography.mono)
                        .foregroundColor(Theme.Colors.textTertiary)
                        .frame(width: 26, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.title)
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text(step.detail)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .lineSpacing(2)
                    }
                }
                .padding(.vertical, Theme.Spacing.md)
                .overlay(alignment: .top) {
                    Rectangle().fill(Theme.Colors.borderLight).frame(height: 1)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.xl)
    }

    private var productStory: some View {
        VStack(alignment: .leading, spacing: 0) {
            AFLabel(text: "HOW AMAKAFLOW WORKS")
                .padding(.bottom, Theme.Spacing.sm)

            ForEach(Array(stories.enumerated()), id: \.offset) { _, story in
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    AFLabel(text: story.heading)
                    Text(story.body)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineSpacing(4)
                }
                .padding(.vertical, Theme.Spacing.md)
                .overlay(alignment: .top) {
                    Rectangle().fill(Theme.Colors.borderLight).frame(height: 1)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.lg)
    }

    private var footer: some View {
        HStack {
            Text("© 2026 AMAKAFLOW")
            Spacer()
            Text("PRIVACY · TERMS")
        }
        .font(Theme.Typography.label)
        .foregroundColor(Theme.Colors.textTertiary)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.xl)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.Colors.borderLight).frame(height: 1)
        }
    }

    private var steps: [(number: String, title: String, detail: String)] {
        [
            ("01", "Wear your watch", "Sync Garmin or Apple Watch. We read HRV, sleep, and training load."),
            ("02", "Answer 5 questions", "Tell us your goal, hours, and modalities. Takes under 2 minutes."),
            ("03", "Train on the right day", "Each morning at 6am, your plan reshapes to match your readiness.")
        ]
    }

    private var stories: [(heading: String, body: String)] {
        [
            (
                "TELEGRAM — YOUR COACH, EVERY MORNING",
                "A daily briefing lands in Telegram with today's session and the reason behind it. Reply to swap a workout, scale it back, or adjust around fatigue."
            ),
            (
                "THE APP — SETUP AND REVIEW",
                "Answer a few questions about your goal, training time, and what you do. AmakaFlow builds your plan and keeps a record of every adaptation over time."
            ),
            (
                "YOUR WATCH — WHERE TRAINING HAPPENS",
                "Open the day's session and send the workout to your Garmin. Completed training data feeds back into what comes next."
            )
        ]
    }
}

#Preview {
    LandingView()
}
