//
//  PRCelebrationView.swift
//  AmakaFlow
//
//  Full-screen confetti overlay shown when a personal record is detected.
//  Auto-dismisses after 3 seconds or tap to dismiss.
//  AMA-1282
//

import SwiftUI

struct PRCelebrationView: View {
    let newPRs: [PRDetectionResult.NewPR]
    let onDismiss: () -> Void

    @State private var showContent = false
    @State private var confettiParticles: [ConfettiParticle] = []
    @State private var autoDismissTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            // Semi-transparent backdrop
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            // Confetti layer
            ForEach(confettiParticles) { particle in
                ConfettiPiece(particle: particle)
            }

            // Content
            VStack(spacing: Theme.Spacing.lg) {
                Spacer()

                // Trophy icon
                Image(systemName: "trophy.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .scaleEffect(showContent ? 1.0 : 0.3)
                    .opacity(showContent ? 1 : 0)

                Text("New Personal Record!")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .opacity(showContent ? 1 : 0)

                // PR details
                VStack(spacing: Theme.Spacing.md) {
                    ForEach(Array(newPRs.enumerated()), id: \.offset) { _, pr in
                        PRDetailRow(pr: pr)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .opacity(showContent ? 1 : 0)

                Spacer()

                Text("Tap anywhere to dismiss")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
                    .opacity(showContent ? 0.7 : 0)
                    .padding(.bottom, Theme.Spacing.xl)
            }
        }
        .onAppear {
            spawnConfetti()
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                showContent = true
            }
            autoDismissTask = Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if !Task.isCancelled { dismiss() }
            }
        }
        .onDisappear {
            autoDismissTask?.cancel()
        }
        .accessibilityIdentifier("pr_celebration_overlay")
    }

    private func dismiss() {
        autoDismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.3)) {
            showContent = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
    }

    private func spawnConfetti() {
        let colors: [Color] = [
            Color(hex: "FFD700"), // Gold
            Color(hex: "6C5CE7"), // Purple
            Color(hex: "FF6B6B"), // Red
            Color(hex: "4EDF9B"), // Green
            Color(hex: "3A8BFF"), // Blue
            Color(hex: "FFA500"), // Orange
        ]

        confettiParticles = (0..<50).map { i in
            ConfettiParticle(
                id: i,
                color: colors[i % colors.count],
                startX: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                startY: CGFloat.random(in: -100...(-20)),
                endY: UIScreen.main.bounds.height + 50,
                size: CGFloat.random(in: 6...14),
                duration: Double.random(in: 2.0...4.0),
                delay: Double.random(in: 0...0.8),
                rotation: Double.random(in: 0...360),
                isCircle: Bool.random()
            )
        }
    }
}

// MARK: - PR Detail Row

private struct PRDetailRow: View {
    let pr: PRDetectionResult.NewPR

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text(pr.exerciseName)
                .font(Theme.Typography.title3)
                .foregroundColor(.white)

            HStack(spacing: Theme.Spacing.sm) {
                if let oldValue = pr.oldValue {
                    Text(formatValue(oldValue, type: pr.type, weight: pr.weight))
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .strikethrough()

                    Image(systemName: "arrow.right")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "FFD700"))
                }

                Text(formatValue(pr.newValue, type: pr.type, weight: pr.weight))
                    .font(Theme.Typography.title2)
                    .foregroundColor(Color(hex: "FFD700"))
                    .fontWeight(.bold)
            }

            Text(pr.type.displayLabel)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.surface.opacity(0.8))
        .cornerRadius(Theme.CornerRadius.md)
    }

    private func formatValue(_ value: Double, type: PersonalRecord.PRType, weight: Double?) -> String {
        switch type {
        case .heaviestWeight:
            return String(format: "%.1f kg", value)
        case .mostReps:
            if let w = weight {
                return "\(Int(value)) reps @ \(String(format: "%.1f", w)) kg"
            }
            return "\(Int(value)) reps"
        case .mostVolume:
            return String(format: "%.0f kg", value)
        }
    }
}

// MARK: - PR Type Display Extension

extension PersonalRecord.PRType {
    var displayLabel: String {
        switch self {
        case .heaviestWeight: return "Max Weight"
        case .mostReps: return "Max Reps"
        case .mostVolume: return "Max Volume"
        }
    }
}

// MARK: - Confetti

struct ConfettiParticle: Identifiable {
    let id: Int
    let color: Color
    let startX: CGFloat
    let startY: CGFloat
    let endY: CGFloat
    let size: CGFloat
    let duration: Double
    let delay: Double
    let rotation: Double
    let isCircle: Bool
}

private struct ConfettiPiece: View {
    let particle: ConfettiParticle
    @State private var animate = false

    var body: some View {
        Group {
            if particle.isCircle {
                Circle()
                    .fill(particle.color)
                    .frame(width: particle.size, height: particle.size)
            } else {
                Rectangle()
                    .fill(particle.color)
                    .frame(width: particle.size, height: particle.size * 0.6)
            }
        }
        .rotationEffect(.degrees(animate ? particle.rotation + 360 : particle.rotation))
        .position(
            x: particle.startX + (animate ? CGFloat.random(in: -40...40) : 0),
            y: animate ? particle.endY : particle.startY
        )
        .opacity(animate ? 0 : 1)
        .onAppear {
            withAnimation(
                .easeIn(duration: particle.duration)
                .delay(particle.delay)
            ) {
                animate = true
            }
        }
    }
}

// MARK: - Preview

#Preview {
    PRCelebrationView(
        newPRs: [
            PRDetectionResult.NewPR(
                exerciseName: "Bench Press",
                type: .heaviestWeight,
                oldValue: 80.0,
                newValue: 85.0,
                reps: 1,
                weight: nil
            ),
            PRDetectionResult.NewPR(
                exerciseName: "Squat",
                type: .mostVolume,
                oldValue: 2400,
                newValue: 2800,
                reps: nil,
                weight: nil
            )
        ],
        onDismiss: {}
    )
}
