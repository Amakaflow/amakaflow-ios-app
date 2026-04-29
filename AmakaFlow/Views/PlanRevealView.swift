import SwiftUI

struct PlanRevealView: View {
    let isReady: Bool
    let onConfirm: () -> Void

    private let blocks = [
        PlanBlock(week: "W1", title: "Foundation", focus: "Technique + easy volume", load: "6h 20m", color: Theme.Colors.accentGreen),
        PlanBlock(week: "W2", title: "Build", focus: "Threshold run + strength", load: "7h 05m", color: Theme.Colors.readyModerate),
        PlanBlock(week: "W3", title: "Peak", focus: "Race-specific density", load: "7h 40m", color: Theme.Colors.accentRed),
        PlanBlock(week: "W4", title: "Absorb", focus: "Deload + test readiness", load: "5h 10m", color: Theme.Colors.textSecondary)
    ]

    var body: some View {
        VStack(spacing: 0) {
            if isReady {
                readyContent
            } else {
                loadingContent
            }
        }
        .background(Theme.Colors.background.ignoresSafeArea())
    }

    private var loadingContent: some View {
        VStack(spacing: 0) {
            AFTopBar(title: "Building your plan", subtitle: "Coach is periodising your next block.") {
                EmptyView()
            } right: {
                EmptyView()
            }

            Spacer()
            VStack(spacing: Theme.Spacing.lg) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Theme.Colors.textPrimary))
                    .scaleEffect(1.6)
                    .padding(Theme.Spacing.lg)
                Text("Reading recent training…")
                    .font(Theme.Typography.title1)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("Balancing your Hyrox goal, watch history, recovery, and available hours.")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(Theme.Spacing.xs)
            }
            .padding(Theme.Spacing.xl)
            Spacer()
        }
    }

    private var readyContent: some View {
        VStack(spacing: 0) {
            AFTopBar(title: "Your 4-week block", subtitle: "Periodised around your race goal and recovery data.") {
                EmptyView()
            } right: {
                EmptyView()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    AFCard(padding: Theme.Spacing.md) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            AFLabel(text: "Coach rationale")
                            Text("Build durability without stacking red days.")
                                .font(Theme.Typography.title2)
                                .foregroundColor(Theme.Colors.textPrimary)
                            Text("Two quality run sessions, two strength touches, and one protected long aerobic day. Week 4 absorbs load before the next assessment.")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                                .lineSpacing(Theme.Spacing.xs)
                        }
                    }

                    AFLabel(text: "Block timeline")
                        .padding(.top, Theme.Spacing.xs)

                    ForEach(blocks, id: \.week) { block in
                        planRow(block)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
            }

            Button("Use this plan", action: onConfirm)
                .buttonStyle(AFPrimaryButtonStyle())
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
        }
    }

    private func planRow(_ block: PlanBlock) -> some View {
        AFCard(padding: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .stroke(block.color, lineWidth: 1)
                    .frame(width: Theme.Spacing.xl + Theme.Spacing.md, height: Theme.Spacing.xl + Theme.Spacing.md)
                    .overlay(
                        Text(block.week)
                            .font(Theme.Typography.mono)
                            .foregroundColor(block.color)
                    )
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(block.title)
                        .font(Theme.Typography.title3)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(block.focus)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                Spacer()
                AFChip(text: block.load, outline: true)
            }
        }
    }
}

private struct PlanBlock {
    let week: String
    let title: String
    let focus: String
    let load: String
    let color: Color
}

#Preview("Loading") {
    PlanRevealView(isReady: false, onConfirm: {})
        .preferredColorScheme(.dark)
}

#Preview("Ready") {
    PlanRevealView(isReady: true, onConfirm: {})
        .preferredColorScheme(.dark)
}
