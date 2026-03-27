//
//  WeeklyProgressRing.swift
//  AmakaFlow
//
//  Apple Watch-style circular progress ring for weekly workout target (AMA-1286)
//

import SwiftUI

struct WeeklyProgressRing: View {
    let workoutsCompleted: Int
    let weeklyTarget: Int
    let ringPercentage: Double
    let motivationalText: String

    @State private var animatedProgress: Double = 0

    private let ringColor = Color(hex: "6C5CE7") // AmakaFlow purple
    private let trackColor = Color.gray.opacity(0.3)
    private let lineWidth: CGFloat = 14

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            ZStack {
                // Background track
                Circle()
                    .stroke(trackColor, lineWidth: lineWidth)
                    .frame(width: 120, height: 120)

                // Progress arc
                Circle()
                    .trim(from: 0, to: animatedProgress)
                    .stroke(
                        ringColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))

                // Center text
                VStack(spacing: 2) {
                    Text("\(workoutsCompleted)/\(weeklyTarget)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)

                    Text("workouts")
                        .font(Theme.Typography.footnote)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }

            // Motivational Zeigarnik text
            Text(motivationalText)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.lg)
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                animatedProgress = ringPercentage
            }
        }
        .onChange(of: ringPercentage) { _, newValue in
            withAnimation(.easeOut(duration: 0.5)) {
                animatedProgress = newValue
            }
        }
        .accessibilityIdentifier("weekly_progress_ring")
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        WeeklyProgressRing(
            workoutsCompleted: 2,
            weeklyTarget: 3,
            ringPercentage: 0.67,
            motivationalText: "2 of 3 — one more to go!"
        )
        WeeklyProgressRing(
            workoutsCompleted: 3,
            weeklyTarget: 3,
            ringPercentage: 1.0,
            motivationalText: "Target hit! 3 of 3 — crushing it!"
        )
    }
    .padding()
    .preferredColorScheme(.dark)
}
