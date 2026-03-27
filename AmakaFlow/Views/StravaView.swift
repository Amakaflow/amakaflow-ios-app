//
//  StravaView.swift
//  AmakaFlow
//
//  Strava integration screen - connect account, view athlete info and activities.
//  AMA-1235
//

import SwiftUI

struct StravaView: View {
    @StateObject private var viewModel = StravaViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    if viewModel.isLoading {
                        loadingView
                    } else if viewModel.isConnected {
                        connectedView
                    } else {
                        disconnectedView
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.lg)
                .padding(.bottom, 100)
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle("Strava")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(Theme.Colors.accentBlue)
                }
            }
            .task {
                await viewModel.checkConnectionStatus()
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer().frame(height: 80)
            ProgressView()
                .tint(Theme.Colors.accentOrange)
            Text("Checking Strava connection...")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
            Spacer()
        }
    }

    // MARK: - Disconnected View

    private var disconnectedView: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer().frame(height: 40)

            // Strava branding
            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(Color(hex: "FC4C02"))

                Text("Connect to Strava")
                    .font(Theme.Typography.title1)
                    .foregroundColor(Theme.Colors.textPrimary)

                Text("View your Strava activities and sync workout data between AmakaFlow and Strava.")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
            }

            // Error message
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.accentOrange)
                    .padding(.horizontal)
            }

            // Connect button
            Button {
                Task {
                    await viewModel.connect()
                }
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    if viewModel.isConnecting {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(viewModel.isConnecting ? "Connecting..." : "Connect with Strava")
                        .font(Theme.Typography.bodyBold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md)
                .background(Color(hex: "FC4C02"))
                .cornerRadius(Theme.CornerRadius.lg)
            }
            .disabled(viewModel.isConnecting)
            .padding(.horizontal, Theme.Spacing.lg)

            Spacer()
        }
    }

    // MARK: - Connected View

    private var connectedView: some View {
        VStack(spacing: Theme.Spacing.xl) {
            // Athlete info card
            if let athlete = viewModel.athlete {
                athleteCard(athlete: athlete)
            }

            // Error message
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.accentOrange)
            }

            // Activities section
            activitiesSection

            // Disconnect button
            disconnectButton
        }
    }

    // MARK: - Athlete Card

    private func athleteCard(athlete: StravaAthlete) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            // Profile icon
            ZStack {
                Circle()
                    .fill(Color(hex: "FC4C02").opacity(0.1))
                    .frame(width: 56, height: 56)

                Image(systemName: "person.fill")
                    .font(.system(size: 24))
                    .foregroundColor(Color(hex: "FC4C02"))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(athlete.displayName)
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)

                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                        Text("Connected")
                            .font(Theme.Typography.footnote)
                    }
                    .foregroundColor(Theme.Colors.accentGreen)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 2)
                    .background(Theme.Colors.accentGreen.opacity(0.1))
                    .cornerRadius(Theme.CornerRadius.sm)
                }

                if !athlete.username.isEmpty {
                    Text("@\(athlete.username)")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }

            Spacer()
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.md)
    }

    // MARK: - Activities Section

    private var activitiesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("RECENT ACTIVITIES")
                    .font(Theme.Typography.footnote)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .tracking(1)

                Spacer()

                Text("\(viewModel.activities.count) activities")
                    .font(Theme.Typography.footnote)
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            .padding(.horizontal, Theme.Spacing.xs)

            if viewModel.activities.isEmpty {
                emptyActivitiesView
            } else {
                VStack(spacing: 1) {
                    ForEach(viewModel.activities) { activity in
                        activityRow(activity: activity)
                    }
                }
                .background(Theme.Colors.borderLight)
                .cornerRadius(Theme.CornerRadius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                        .stroke(Theme.Colors.borderLight, lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Activity Row

    private func activityRow(activity: StravaActivity) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            // Activity type icon
            ZStack {
                RoundedRectangle(cornerRadius: Theme.CornerRadius.sm)
                    .fill(Color(hex: "FC4C02").opacity(0.1))
                    .frame(width: 40, height: 40)

                Image(systemName: activity.typeIcon)
                    .font(.system(size: 18))
                    .foregroundColor(Color(hex: "FC4C02"))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(activity.name)
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: Theme.Spacing.sm) {
                    Text(activity.dateFormatted)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(activity.distanceKm)
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)

                Text(activity.durationFormatted)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
    }

    // MARK: - Empty Activities

    private var emptyActivitiesView: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "figure.run")
                .font(.system(size: 32))
                .foregroundColor(Theme.Colors.textTertiary)

            Text("No recent activities")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)

            Text("Your Strava activities will appear here once synced.")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.xl)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.md)
    }

    // MARK: - Disconnect Button

    private var disconnectButton: some View {
        Button {
            viewModel.disconnect()
        } label: {
            Text("Disconnect Strava")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.accentOrange)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Theme.Colors.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                        .stroke(Theme.Colors.borderLight, lineWidth: 1)
                )
                .cornerRadius(Theme.CornerRadius.md)
        }
    }
}

// MARK: - Preview

#Preview {
    StravaView()
        .preferredColorScheme(.dark)
}
