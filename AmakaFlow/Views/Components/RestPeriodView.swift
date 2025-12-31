//
//  RestPeriodView.swift
//  AmakaFlow
//
//  Displays the rest period between exercises
//

import SwiftUI

struct RestPeriodView: View {
    @ObservedObject var engine: WorkoutEngine

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            // Rest icon
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(Theme.Colors.accentBlue)

            // Title
            Text("Rest")
                .font(Theme.Typography.title1)
                .foregroundColor(Theme.Colors.textPrimary)

            // Timer or manual rest message
            if engine.isManualRest {
                Text("Take your time")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
            } else if engine.restRemainingSeconds > 0 {
                // Countdown timer
                Text(formattedRestTime)
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundColor(restTimerColor)
                    .monospacedDigit()

                // Progress ring
                ZStack {
                    Circle()
                        .stroke(Theme.Colors.borderLight, lineWidth: 8)
                        .frame(width: 180, height: 180)

                    Circle()
                        .trim(from: 0, to: restProgress)
                        .stroke(
                            restTimerColor,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 180, height: 180)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.5), value: restProgress)
                }
            }

            // Next exercise preview
            if let nextStep = nextStep {
                VStack(spacing: Theme.Spacing.xs) {
                    Text("Up Next")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)

                    Text(nextStep.displayLabel)
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .multilineTextAlignment(.center)

                    if !nextStep.details.isEmpty {
                        Text(nextStep.details)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.surface)
                .cornerRadius(Theme.CornerRadius.md)
            }

            Spacer()

            // Continue button
            Button {
                engine.skipRest()
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 24))
                    Text(engine.isManualRest ? "Continue" : "Skip Rest")
                        .font(Theme.Typography.bodyBold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md)
                .background(Theme.Colors.accentGreen)
                .cornerRadius(Theme.CornerRadius.lg)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xl)
        }
    }

    // MARK: - Computed Properties

    private var formattedRestTime: String {
        let minutes = engine.restRemainingSeconds / 60
        let seconds = engine.restRemainingSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var restProgress: Double {
        guard let currentStep = engine.currentStep,
              let totalRest = currentStep.restAfterSeconds,
              totalRest > 0 else {
            return 0
        }
        return 1.0 - (Double(engine.restRemainingSeconds) / Double(totalRest))
    }

    private var restTimerColor: Color {
        if engine.restRemainingSeconds <= 3 {
            return Theme.Colors.accentRed
        } else if engine.restRemainingSeconds <= 10 {
            return Color.orange
        } else {
            return Theme.Colors.accentBlue
        }
    }

    private var nextStep: FlattenedInterval? {
        let nextIndex = engine.currentStepIndex + 1
        guard nextIndex < engine.flattenedSteps.count else { return nil }
        return engine.flattenedSteps[nextIndex]
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Theme.Colors.background.ignoresSafeArea()
        RestPeriodView(engine: WorkoutEngine.shared)
    }
}
