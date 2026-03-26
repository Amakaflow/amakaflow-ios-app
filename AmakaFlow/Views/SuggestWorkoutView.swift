//
//  SuggestWorkoutView.swift
//  AmakaFlow
//
//  Sheet view showing AI-generated workout preview with accept/modify/dismiss actions (AMA-1265).
//

import SwiftUI

struct SuggestWorkoutView: View {
    @ObservedObject var viewModel: SuggestWorkoutViewModel
    @EnvironmentObject var workoutsViewModel: WorkoutsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()

                switch viewModel.state {
                case .idle:
                    EmptyView()

                case .needsOnboarding:
                    CoachingProfileOnboardingView(viewModel: viewModel)

                case .loading:
                    loadingView

                case .success(let workout):
                    workoutPreview(workout)

                case .error(let message):
                    errorView(message)
                }
            }
            .navigationTitle("Suggested Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(Theme.Colors.accentOrange)

            Text("Generating your workout...")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)

            Text("Our AI coach is crafting a workout based on your profile")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)
        }
        .accessibilityIdentifier("suggest_workout_loading")
    }

    // MARK: - Workout Preview

    private func workoutPreview(_ workout: Workout) -> some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                // Workout header
                VStack(spacing: Theme.Spacing.sm) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "sparkles")
                            .foregroundColor(Theme.Colors.accentOrange)
                        Text("AI Coach Suggestion")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.accentOrange)
                    }

                    Text(workout.name)
                        .font(Theme.Typography.title2)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: Theme.Spacing.md) {
                        Label(workout.formattedDuration, systemImage: "clock")
                        Label(workout.sport.rawValue.capitalized, systemImage: "figure.run")
                        Label("\(workout.intervals.count) steps", systemImage: "list.bullet")
                    }
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)

                    if let description = workout.description {
                        Text(description)
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, Theme.Spacing.xs)
                    }
                }
                .padding(Theme.Spacing.lg)
                .frame(maxWidth: .infinity)
                .background(Theme.Colors.surface)
                .cornerRadius(Theme.CornerRadius.lg)

                // Workout intervals
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Workout Steps")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)

                    ForEach(Array(workout.intervals.enumerated()), id: \.offset) { index, interval in
                        SuggestIntervalRow(index: index + 1, interval: interval)
                    }
                }
                .padding(Theme.Spacing.lg)
                .background(Theme.Colors.surface)
                .cornerRadius(Theme.CornerRadius.lg)

                // Action buttons
                VStack(spacing: Theme.Spacing.sm) {
                    // Accept button
                    Button {
                        acceptWorkout(workout)
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Accept & Save")
                        }
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.md)
                        .background(Theme.Colors.accentGreen)
                        .cornerRadius(Theme.CornerRadius.md)
                    }
                    .accessibilityIdentifier("accept_workout_button")

                    // Try again button
                    Button {
                        Task {
                            await viewModel.suggestWorkout()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Suggest Another")
                        }
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.accentBlue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.md)
                        .background(Theme.Colors.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                                .stroke(Theme.Colors.accentBlue, lineWidth: 1)
                        )
                        .cornerRadius(Theme.CornerRadius.md)
                    }
                    .accessibilityIdentifier("suggest_another_button")

                    // Dismiss button
                    Button {
                        viewModel.reset()
                        dismiss()
                    } label: {
                        Text("Dismiss")
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.sm)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, 40)
        }
        .accessibilityIdentifier("suggest_workout_preview")
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(Theme.Colors.accentOrange)

            Text("Something went wrong")
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)

            Text(message)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)

            Button {
                Task {
                    await viewModel.suggestWorkout()
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Try Again")
                }
                .font(Theme.Typography.bodyBold)
                .foregroundColor(.white)
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.md)
                .background(Theme.Colors.accentOrange)
                .cornerRadius(Theme.CornerRadius.md)
            }
        }
        .accessibilityIdentifier("suggest_workout_error")
    }

    // MARK: - Actions

    private func acceptWorkout(_ workout: Workout) {
        // Add to incoming workouts so it shows in the list
        workoutsViewModel.incomingWorkouts.append(workout)
        viewModel.reset()
        dismiss()
    }
}

// MARK: - Interval Row

private struct SuggestIntervalRow: View {
    let index: Int
    let interval: WorkoutInterval

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Text("\(index)")
                .font(Theme.Typography.captionBold)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(intervalColor)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(intervalName)
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)

                if let detail = intervalDetail {
                    Text(detail)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private var intervalName: String {
        switch interval {
        case .warmup: return "Warm Up"
        case .cooldown: return "Cool Down"
        case .time(_, let target): return target ?? "Timed Interval"
        case .reps(_, _, let name, _, _, _): return name
        case .distance(let meters, _): return "\(meters)m"
        case .repeat(let reps, _): return "Repeat x\(reps)"
        case .rest: return "Rest"
        }
    }

    private var intervalDetail: String? {
        switch interval {
        case .warmup(let seconds, _), .cooldown(let seconds, _), .time(let seconds, _):
            return "\(seconds / 60) min"
        case .reps(let sets, let reps, _, let load, let restSec, _):
            var parts: [String] = []
            if let sets = sets { parts.append("\(sets) sets x") }
            parts.append("\(reps) reps")
            if let load = load { parts.append("@ \(load)") }
            if let rest = restSec { parts.append("(\(rest)s rest)") }
            return parts.joined(separator: " ")
        case .distance(_, let target): return target
        case .repeat(_, let intervals): return "\(intervals.count) exercises"
        case .rest(let seconds):
            if let sec = seconds { return "\(sec)s" }
            return "Until ready"
        }
    }

    private var intervalColor: Color {
        switch interval {
        case .warmup: return .orange
        case .cooldown: return .blue
        case .reps: return Theme.Colors.accentGreen
        case .time: return Theme.Colors.accentBlue
        case .rest: return .gray
        default: return Theme.Colors.accentBlue
        }
    }
}

#Preview {
    SuggestWorkoutView(viewModel: SuggestWorkoutViewModel())
        .environmentObject(WorkoutsViewModel())
        .preferredColorScheme(.dark)
}
