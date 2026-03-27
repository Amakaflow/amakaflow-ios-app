//
//  ChallengeCompletionView.swift
//  AmakaFlow
//
//  Celebration overlay when a challenge is completed — confetti + badge unlock (AMA-1276)
//

import SwiftUI

struct ChallengeCompletionView: View {
    let badge: ChallengeBadge
    let onDismiss: () -> Void

    @State private var showContent = false
    @State private var confettiParticles: [ChallengeConfettiParticle] = []

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            // Confetti layer
            ForEach(confettiParticles) { particle in
                ChallengeConfettiPiece(particle: particle)
            }

            VStack(spacing: Theme.Spacing.lg) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .shadow(color: Color(hex: "FFD700").opacity(0.5), radius: 20)

                    Image(systemName: badge.iconName)
                        .font(.system(size: 44))
                        .foregroundColor(.white)
                }
                .scaleEffect(showContent ? 1.0 : 0.3)
                .animation(.spring(response: 0.6, dampingFraction: 0.5), value: showContent)

                Text("Challenge Complete!")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 20)
                    .animation(.easeOut(duration: 0.5).delay(0.3), value: showContent)

                VStack(spacing: 8) {
                    Text(badge.name)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color(hex: "FFD700"))

                    Text(badge.description)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 20)
                .animation(.easeOut(duration: 0.5).delay(0.5), value: showContent)

                Button {
                    onDismiss()
                } label: {
                    Text("Awesome!")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(.black)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 14)
                        .background(Color(hex: "FFD700"))
                        .cornerRadius(12)
                }
                .opacity(showContent ? 1 : 0)
                .animation(.easeOut(duration: 0.5).delay(0.7), value: showContent)
            }
            .padding(Theme.Spacing.xl)
        }
        .onAppear {
            showContent = true
            generateConfetti()
        }
    }

    private func generateConfetti() {
        let colors: [Color] = [
            Color(hex: "FFD700"),
            Theme.Colors.accentBlue,
            Theme.Colors.accentGreen,
            Theme.Colors.accentOrange,
            Color(hex: "FF69B4")
        ]

        confettiParticles = (0..<40).map { i in
            ChallengeConfettiParticle(
                id: i,
                color: colors[i % colors.count],
                startX: CGFloat.random(in: -180...180),
                startY: CGFloat.random(in: -400...(-200)),
                endY: CGFloat.random(in: 300...600),
                size: CGFloat.random(in: 4...10),
                duration: Double.random(in: 1.5...3.0),
                delay: Double(i) * 0.05
            )
        }
    }
}

// MARK: - Challenge Confetti Particle

struct ChallengeConfettiParticle: Identifiable {
    let id: Int
    let color: Color
    let startX: CGFloat
    let startY: CGFloat
    let endY: CGFloat
    let size: CGFloat
    let duration: Double
    let delay: Double
}

private struct ChallengeConfettiPiece: View {
    let particle: ChallengeConfettiParticle
    @State private var animate = false

    var body: some View {
        Circle()
            .fill(particle.color)
            .frame(width: particle.size, height: particle.size)
            .offset(
                x: particle.startX + (animate ? CGFloat.random(in: -30...30) : 0),
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

#Preview {
    ChallengeCompletionView(
        badge: ChallengeBadge(
            id: "badge-1",
            name: "Volume Champion",
            iconName: "trophy.fill",
            description: "Completed the 10k Volume Challenge"
        ),
        onDismiss: {}
    )
    .preferredColorScheme(.dark)
}
