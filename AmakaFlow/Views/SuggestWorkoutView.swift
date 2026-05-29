//
//  SuggestWorkoutView.swift
//  AmakaFlow
//
//  Sheet view showing AI-generated workout preview with start/swap/rest actions (AMA-1994).
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
                    loadingView

                case .needsOnboarding:
                    CoachingProfileOnboardingView(viewModel: viewModel)

                case .loading:
                    loadingView

                case .success(let workout):
                    contentView(workout)

                case .empty:
                    emptyView

                case .error(let ctaError):
                    errorView(ctaError)
                }
            }
            .navigationBarHidden(true)
            .overlay(alignment: .top) {
                if let error = viewModel.ctaError {
                    ErrorToast(
                        actionTitle: "Couldn't generate workout",
                        error: error,
                        onRetry: error.isRetryable ? { Task { await viewModel.retry() } } : nil,
                        onReport: { viewModel.reportError() },
                        onDismiss: { viewModel.dismissError() }
                    )
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.md)
                }
            }
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ProgressView()
                .scaleEffect(1.4)
                .tint(Theme.Colors.textPrimary)

            VStack(spacing: Theme.Spacing.sm) {
                Text("Generating your workout")
                    .afH2()
                Text("The coach is using today’s available signals. No fallback workout will be shown if generation fails.")
                    .afMuted()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("suggest_workout_loading")
    }

    // MARK: - Content

    private func contentView(_ workout: Workout) -> some View {
        scrollContainer {
            readinessCard
            workoutCard(workout)
            actionButtons(for: workout)
        }
        .accessibilityIdentifier("ama1842.suggest.preview")
    }

    private var readinessCard: some View {
        AFCard {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(viewModel.readinessLevel.color.opacity(0.14))
                    Circle()
                        .fill(viewModel.readinessLevel.color)
                        .frame(width: 14, height: 14)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 6) {
                    AFLabel(text: "Readiness")
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(viewModel.readinessLevel.title)
                            .afH2()
                        AFChip(text: viewModel.readinessLevel.badgeText, outline: true)
                    }

                    if let message = viewModel.readinessMessage, !message.isEmpty {
                        Text(message)
                            .afMuted()
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Connect a wearable for detailed metrics.")
                            .afMuted()
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .accessibilityIdentifier("af_suggest_readiness")
    }

    private func workoutCard(_ workout: Workout) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            AFCard(padding: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    HStack(alignment: .top, spacing: Theme.Spacing.md) {
                        iconTile(symbolName: workout.sport.symbolName)

                        VStack(alignment: .leading, spacing: 8) {
                            AFLabel(text: "Suggested workout")
                            Text(workout.name)
                                .font(Theme.Typography.title1)
                                .foregroundColor(Theme.Colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            workoutMeta(workout)
                        }
                    }

                    if let rationale = workout.description?.trimmingCharacters(in: .whitespacesAndNewlines), !rationale.isEmpty {
                        Divider()
                            .overlay(Theme.Colors.borderLight)

                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            AFLabel(text: "About this session")
                            Text(rationale)
                                .afBody()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if !workout.intervals.isEmpty {
                AFCard {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        AFLabel(text: "Session plan")
                        LazyVStack(spacing: Theme.Spacing.sm) {
                            ForEach(Array(workout.intervals.enumerated()), id: \.offset) { index, interval in
                                SuggestIntervalRow(index: index + 1, interval: interval)
                            }
                        }
                    }
                }
            }
        }
    }

    private func workoutMeta(_ workout: Workout) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            AFChip(text: workout.formattedDuration)
            AFChip(text: workout.sport.displayName)
            AFChip(text: "\(workout.intervals.count) steps")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func actionButtons(for workout: Workout) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            Button {
                startWorkout(workout)
            } label: {
                Label("Start workout", systemImage: "play.fill")
            }
            .buttonStyle(AFPrimaryButtonStyle(size: .lg))
            .accessibilityIdentifier("af_suggest_start")

            Button {
                Task { await viewModel.suggestAnother() }
            } label: {
                Label("Suggest another", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(AFGhostButtonStyle(size: .lg))
            .accessibilityIdentifier("af_suggest_swap")

            Button {
                viewModel.restToday()
                dismiss()
            } label: {
                Label("Rest today", systemImage: "moon.zzz")
            }
            .buttonStyle(AFGhostButtonStyle(size: .lg))
            .accessibilityIdentifier("af_suggest_rest")
        }
    }

    // MARK: - Empty + Error

    private var emptyView: some View {
        scrollContainer {
            AFCard(padding: Theme.Spacing.lg) {
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "sparkles.square.filled.on.square")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundColor(Theme.Colors.textSecondary)
                    Text("No suggestion available")
                        .afH2()
                    Text("The coach did not return a workout for today. Try again when you’re ready.")
                        .afMuted()
                        .multilineTextAlignment(.center)

                    Button {
                        Task { await viewModel.retry() }
                    } label: {
                        Text("Try again")
                    }
                    .buttonStyle(AFPrimaryButtonStyle(size: .md))
                }
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("suggest_workout_empty")
        }
    }

    private func errorView(_ error: CTAError) -> some View {
        scrollContainer {
            AFCard(padding: Theme.Spacing.lg) {
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundColor(Theme.Colors.accentRed)
                    Text(errorTitle(for: error))
                        .afH2()
                        .multilineTextAlignment(.center)
                    Text(error.userMessage)
                        .afMuted()
                        .multilineTextAlignment(.center)

                    if error.isRetryable {
                        Button {
                            Task { await viewModel.retry() }
                        } label: {
                            Text("Retry")
                        }
                        .buttonStyle(AFPrimaryButtonStyle(size: .md))
                        .accessibilityIdentifier("suggest_workout_retry")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("suggest_workout_error")
        }
    }

    private func errorTitle(for error: CTAError) -> String {
        if case .unauthenticated = error {
            return "Please sign in again"
        }
        return "Couldn’t generate a workout"
    }

    // MARK: - Shared layout

    @ViewBuilder
    private func scrollContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                AFTopBar(
                    title: "Today’s suggestion",
                    subtitle: "Readiness, rationale, and one generated session",
                    backIdentifier: "suggest_workout_done",
                    backAction: { dismiss() },
                    right: { AFChip(text: "AI Coach", outline: true) }
                )
                .padding(.horizontal, -Theme.Spacing.lg)

                content()
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, 40)
        }
    }

    private func iconTile(symbolName: String) -> some View {
        RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous)
            .fill(Theme.Colors.accentBackground)
            .frame(width: 46, height: 46)
            .overlay(
                Image(systemName: symbolName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Theme.Colors.textPrimary)
            )
    }

    // MARK: - Actions

    private func startWorkout(_ workout: Workout) {
        // AMA-1751: persist + surface. Backend has no accept-suggestion
        // endpoint yet, so the view model's local store is the only thing
        // keeping this workout alive across the next API refresh.
        workoutsViewModel.acceptSuggestedWorkout(workout)
        viewModel.reset()
        dismiss()
    }
}

// MARK: - Display helpers

private extension SuggestReadinessLevel {
    var title: String {
        switch self {
        case .green: return "Ready to train"
        case .yellow: return "Proceed with care"
        case .red: return "Recovery-first day"
        case .unknown: return "Readiness unavailable"
        }
    }

    var badgeText: String {
        switch self {
        case .green: return "Green"
        case .yellow: return "Yellow"
        case .red: return "Red"
        case .unknown: return "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .green: return Theme.Colors.readyHigh
        case .yellow: return Theme.Colors.readyModerate
        case .red: return Theme.Colors.readyLow
        case .unknown: return Theme.Colors.textTertiary
        }
    }
}

private extension WorkoutSport {
    var displayName: String {
        rawValue.capitalized
    }

    var symbolName: String {
        switch self {
        case .running: return "figure.run"
        case .cycling: return "figure.outdoor.cycle"
        case .strength: return "dumbbell.fill"
        case .mobility: return "figure.flexibility"
        case .swimming: return "figure.pool.swim"
        case .cardio: return "heart.fill"
        case .other: return "figure.mixed.cardio"
        }
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

            VStack(alignment: .leading, spacing: 3) {
                Text(intervalName)
                    .afH3()

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
}
