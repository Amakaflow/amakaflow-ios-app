//
//  TeamView.swift
//  AmakaFlow
//
//  AMA-1240: Team Sharing - Share workouts via system share sheet
//

import SwiftUI

struct TeamView: View {
    @EnvironmentObject var viewModel: WorkoutsViewModel
    @State private var showingShareSheet = false
    @State private var shareText = ""
    @State private var recentShares: [RecentShare] = []

    /// All workouts available for sharing (scheduled + incoming)
    private var allWorkouts: [Workout] {
        let scheduled = viewModel.upcomingWorkouts.map { $0.workout }
        let incoming = viewModel.incomingWorkouts
        // Deduplicate by id
        var seen = Set<String>()
        var result: [Workout] = []
        for w in scheduled + incoming {
            if !seen.contains(w.id) {
                seen.insert(w.id)
                result.append(w)
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    headerCard

                    shareWorkoutsSection

                    if !recentShares.isEmpty {
                        recentSharesSection
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
                .padding(.bottom, 100)
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle("Team Sharing")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(activityItems: [shareText])
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .fill(Theme.Colors.accentBlue.opacity(0.15))
                    .frame(width: 48, height: 48)

                Image(systemName: "person.3.fill")
                    .font(.system(size: 22))
                    .foregroundColor(Theme.Colors.accentBlue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Share with Your Team")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)

                Text("Send workouts to friends, training partners, or your coach via any messaging app.")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Spacer()
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.accentBlue.opacity(0.08))
        .cornerRadius(Theme.CornerRadius.md)
    }

    // MARK: - Share Workouts Section

    private var shareWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("SHARE A WORKOUT")
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.textSecondary)
                .tracking(1)

            if allWorkouts.isEmpty {
                emptyWorkoutsCard
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(allWorkouts) { workout in
                        shareableWorkoutRow(workout: workout)
                    }
                }
            }
        }
    }

    private func shareableWorkoutRow(workout: Workout) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.name)
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(2)

                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.Colors.textTertiary)
                    Text("\(workout.formattedDuration) - \(workout.sportDisplayName)")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }

            Spacer()

            Button {
                shareWorkout(workout)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12))
                    Text("Share")
                        .font(Theme.Typography.captionBold)
                }
                .foregroundColor(Theme.Colors.accentBlue)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.Colors.accentBlue.opacity(0.12))
                .cornerRadius(Theme.CornerRadius.sm)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.md)
    }

    private var emptyWorkoutsCard: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "figure.run")
                .font(.system(size: 40))
                .foregroundColor(Theme.Colors.textTertiary)

            Text("No workouts to share")
                .font(Theme.Typography.bodyBold)
                .foregroundColor(Theme.Colors.textPrimary)

            Text("Push workouts from the web app or import one to start sharing.")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.xl)
        .background(Theme.Colors.surface)
        .cornerRadius(Theme.CornerRadius.md)
    }

    // MARK: - Recent Shares Section

    private var recentSharesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("RECENTLY SHARED")
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.textSecondary)
                .tracking(1)

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(recentShares) { share in
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16))
                            .foregroundColor(Theme.Colors.accentGreen)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(share.workoutName)
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.Colors.textPrimary)
                                .lineLimit(1)

                            Text(share.formattedDate)
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textTertiary)
                        }

                        Spacer()
                    }
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.surface)
                    .cornerRadius(Theme.CornerRadius.md)
                }
            }
        }
    }

    // MARK: - Actions

    private func shareWorkout(_ workout: Workout) {
        var text = "Check out this workout from AmakaFlow!\n\n"
        text += "\(workout.name)\n"
        text += "Sport: \(workout.sportDisplayName)\n"
        text += "Duration: \(workout.formattedDuration)\n"
        text += "Steps: \(workout.intervalCount)\n\n"
        text += "https://app.amakaflow.com/workout/\(workout.id)"

        shareText = text
        showingShareSheet = true

        let share = RecentShare(
            workoutName: workout.name,
            sharedAt: Date()
        )
        recentShares.insert(share, at: 0)
        if recentShares.count > 10 {
            recentShares = Array(recentShares.prefix(10))
        }
    }
}

// MARK: - Supporting Types

struct RecentShare: Identifiable {
    let id = UUID()
    let workoutName: String
    let sharedAt: Date

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: sharedAt)
    }
}

// MARK: - Workout Extension for display names

private extension Workout {
    var sportDisplayName: String {
        switch sport {
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .strength: return "Strength"
        case .mobility: return "Mobility"
        case .swimming: return "Swimming"
        case .cardio: return "Cardio"
        case .other: return "Other"
        }
    }
}

#Preview {
    TeamView()
        .environmentObject(WorkoutsViewModel())
        .preferredColorScheme(.dark)
}
