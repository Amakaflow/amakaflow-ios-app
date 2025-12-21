//
//  StepDisplayView.swift
//  AmakaFlow
//
//  Displays the current workout step with timer and progress
//

import SwiftUI

struct StepDisplayView: View {
    @ObservedObject var engine: WorkoutEngine

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            // Round info (if applicable)
            if let roundInfo = engine.currentStep?.roundInfo {
                Text(roundInfo)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.accentBlue)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(Theme.Colors.accentBlue.opacity(0.15))
                    .cornerRadius(Theme.CornerRadius.sm)
            }

            // Step name
            Text(engine.currentStep?.label ?? "")
                .font(Theme.Typography.title1)
                .foregroundColor(Theme.Colors.textPrimary)
                .multilineTextAlignment(.center)

            // Timer display (for timed steps)
            if engine.currentStep?.stepType == .timed {
                timerDisplay
            } else if engine.currentStep?.stepType == .reps {
                repsDisplay
            }

            // Step details
            if let details = engine.currentStep?.details, !details.isEmpty {
                Text(details)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Follow-along button
            if let url = engine.currentStep?.followAlongUrl {
                followAlongButton(url: url)
            }
        }
        .padding(Theme.Spacing.lg)
    }

    // MARK: - Timer Display

    private var timerDisplay: some View {
        VStack(spacing: Theme.Spacing.sm) {
            // Large timer text
            Text(engine.formattedRemainingTime)
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundColor(timerColor)
                .monospacedDigit()

            // Progress ring
            ZStack {
                Circle()
                    .stroke(Theme.Colors.borderLight, lineWidth: 8)
                    .frame(width: 200, height: 200)

                Circle()
                    .trim(from: 0, to: engine.stepProgress)
                    .stroke(
                        timerColor,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: engine.stepProgress)
            }
            .overlay {
                VStack {
                    Text("remaining")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }
        }
    }

    private var timerColor: Color {
        if engine.remainingSeconds <= 3 {
            return Theme.Colors.accentRed
        } else if engine.remainingSeconds <= 10 {
            return Color.orange
        } else {
            return Theme.Colors.accentGreen
        }
    }

    // MARK: - Reps Display

    private var repsDisplay: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 48))
                .foregroundColor(Theme.Colors.accentGreen)

            Text("Complete and tap Next")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .padding(.vertical, Theme.Spacing.xl)
    }

    // MARK: - Follow Along Button

    private func followAlongButton(url: String) -> some View {
        Button {
            openFollowAlongUrl(url)
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 20))
                Text("Watch Demo")
                    .font(Theme.Typography.bodyBold)
            }
            .foregroundColor(.white)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                LinearGradient(
                    colors: [Color.pink, Color.purple],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(Theme.CornerRadius.md)
        }
    }

    private func openFollowAlongUrl(_ urlString: String) {
        // Check if it's an Instagram URL
        if urlString.contains("instagram.com") {
            // Try to open in Instagram app first
            let reelId = urlString.components(separatedBy: "/").last ?? ""
            if let instagramUrl = URL(string: "instagram://reel/\(reelId)"),
               UIApplication.shared.canOpenURL(instagramUrl) {
                UIApplication.shared.open(instagramUrl)
                return
            }
        }

        // Fallback to Safari
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Theme.Colors.background.ignoresSafeArea()

        StepDisplayView(engine: WorkoutEngine.shared)
    }
}
