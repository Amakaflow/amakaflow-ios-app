//
//  LevelUpCelebrationView.swift
//  AmakaFlow
//
//  Full-screen overlay shown when a user levels up.
//  Auto-dismisses after 3 seconds or tap to dismiss.
//  AMA-1285
//

import SwiftUI

struct LevelUpCelebrationView: View {
    let newLevel: Int
    let levelName: String
    let onDismiss: () -> Void

    @State private var showContent = false
    @State private var confettiParticles: [LevelUpConfettiParticle] = []
    @State private var autoDismissTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            // Semi-transparent backdrop
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            // Confetti layer
            ForEach(confettiParticles) { particle in
                LevelUpConfettiPiece(particle: particle)
            }

            // Content
            VStack(spacing: Theme.Spacing.lg) {
                Spacer()

                // Star icon with level color
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(
                        LinearGradient(
                            colors: levelGradient,
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .scaleEffect(showContent ? 1.0 : 0.3)
                    .opacity(showContent ? 1 : 0)

                Text("Level Up!")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .opacity(showContent ? 1 : 0)

                VStack(spacing: Theme.Spacing.sm) {
                    Text("Level \(newLevel)")
                        .font(.system(size: 48, weight: .heavy))
                        .foregroundStyle(
                            LinearGradient(
                                colors: levelGradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .opacity(showContent ? 1 : 0)

                    Text(levelName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .opacity(showContent ? 1 : 0)
                }

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
        .accessibilityIdentifier("level_up_celebration_overlay")
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

    private var levelGradient: [Color] {
        switch newLevel {
        case 1...2: return [Color(hex: "4EDF9B"), Color(hex: "22C55E")]
        case 3...4: return [Color(hex: "3A8BFF"), Color(hex: "2563EB")]
        case 5...6: return [Color(hex: "FFA500"), Color(hex: "F97316")]
        case 7...8: return [Color(hex: "9333EA"), Color(hex: "7C3AED")]
        case 9...10: return [Color(hex: "FFD700"), Color(hex: "FFA500")]
        default: return [Color(hex: "3A8BFF"), Color(hex: "2563EB")]
        }
    }

    private func spawnConfetti() {
        let colors: [Color] = [
            Color(hex: "FFD700"),
            Color(hex: "6C5CE7"),
            Color(hex: "FF6B6B"),
            Color(hex: "4EDF9B"),
            Color(hex: "3A8BFF"),
            Color(hex: "FFA500"),
        ]

        confettiParticles = (0..<50).map { i in
            LevelUpConfettiParticle(
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

// MARK: - Confetti

struct LevelUpConfettiParticle: Identifiable {
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

private struct LevelUpConfettiPiece: View {
    let particle: LevelUpConfettiParticle
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
    LevelUpCelebrationView(
        newLevel: 5,
        levelName: "Warrior",
        onDismiss: {}
    )
}
