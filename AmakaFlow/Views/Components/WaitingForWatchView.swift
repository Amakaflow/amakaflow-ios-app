//
//  WaitingForWatchView.swift
//  AmakaFlow
//
//  Shows instruction to open Watch app, monitors connectivity, and starts workout when connected
//

import SwiftUI

struct WaitingForWatchView: View {
    let workout: Workout
    let onWatchConnected: () -> Void
    let onCancel: () -> Void
    let onUsePhoneInstead: () -> Void

    @ObservedObject private var watchManager = WatchConnectivityManager.shared
    @State private var pulseAnimation = false
    @State private var checkCount = 0

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            VStack(spacing: Theme.Spacing.xl) {
                Spacer()

                // Watch icon with pulse animation
                ZStack {
                    // Pulse rings
                    ForEach(0..<3) { index in
                        Circle()
                            .stroke(Theme.Colors.accentBlue.opacity(0.3), lineWidth: 2)
                            .frame(width: 120 + CGFloat(index * 40), height: 120 + CGFloat(index * 40))
                            .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                            .opacity(pulseAnimation ? 0 : 0.6)
                            .animation(
                                .easeOut(duration: 1.5)
                                    .repeatForever(autoreverses: false)
                                    .delay(Double(index) * 0.3),
                                value: pulseAnimation
                            )
                    }
                    .allowsHitTesting(false)

                    // Watch icon
                    Image(systemName: "applewatch")
                        .font(.system(size: 80))
                        .foregroundColor(Theme.Colors.accentBlue)
                }
                .frame(height: 200)
                .allowsHitTesting(false)

                VStack(spacing: Theme.Spacing.md) {
                    Text("Open AmakaFlow on Apple Watch")
                        .font(Theme.Typography.title2)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("Please open the AmakaFlow app on your Apple Watch to start tracking your workout.")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.lg)
                }

                // Status indicator
                HStack(spacing: Theme.Spacing.sm) {
                    if watchManager.isWatchReachable {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Theme.Colors.accentGreen)
                        Text("Watch connected!")
                            .foregroundColor(Theme.Colors.accentGreen)
                    } else {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Waiting for Watch...")
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }
                .font(Theme.Typography.body)

                Spacer()

                // Workout info card
                VStack(spacing: Theme.Spacing.sm) {
                    Text("Ready to start:")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)

                    Text(workout.name)
                        .font(Theme.Typography.title3)
                        .foregroundColor(Theme.Colors.textPrimary)

                    Text(workout.formattedDuration)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .padding(Theme.Spacing.lg)
                .frame(maxWidth: .infinity)
                .background(Theme.Colors.surface)
                .cornerRadius(Theme.CornerRadius.lg)

                // Buttons
                VStack(spacing: Theme.Spacing.md) {
                    Button {
                        onUsePhoneInstead()
                    } label: {
                        Text("Start on Phone Only")
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(Theme.Colors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.md)
                            .background(Theme.Colors.surface)
                            .cornerRadius(Theme.CornerRadius.md)
                    }

                    Button {
                        onCancel()
                    } label: {
                        Text("Cancel")
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }
                .padding(.bottom, Theme.Spacing.xl)
            }
            .padding(.horizontal, Theme.Spacing.lg)
        }
        .onAppear {
            pulseAnimation = true
        }
        .onChange(of: watchManager.isWatchReachable) { _, isReachable in
            if isReachable {
                // Small delay to show the "connected" state before starting
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    onWatchConnected()
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    WaitingForWatchView(
        workout: Workout(
            id: "test",
            name: "Test Workout",
            sport: .strength,
            duration: 1800,
            intervals: [],
            source: .amaka
        ),
        onWatchConnected: {},
        onCancel: {},
        onUsePhoneInstead: {}
    )
}
