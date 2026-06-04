//
//  WorkoutSwapSheet.swift
//  AmakaFlow
//
//  Design refresh: mid-workout SWAP sheet (screens-main.jsx PlayerScreen).
//

import SwiftUI

struct WorkoutSwapSheet: View {
    @StateObject private var viewModel = SuggestWorkoutViewModel()
    @Environment(\.dismiss) private var dismiss

    let onSwap: (Workout) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()

                switch viewModel.state {
                case .idle, .loading, .needsOnboarding:
                    loadingView
                case .success(let workout):
                    contentView(workout)
                case .empty:
                    emptyView
                case .error:
                    errorView
                }
            }
            .navigationBarHidden(true)
            .overlay(alignment: .top) {
                if let error = viewModel.ctaError {
                    ErrorToast(
                        actionTitle: "Couldn't load swap options",
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
        .task {
            await viewModel.suggestWorkout(
                notes: "The athlete wants to swap their current workout mid-session. Suggest one alternative session."
            )
        }
        .accessibilityIdentifier("af_workout_swap_sheet")
    }

    private var loadingView: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .tint(Theme.Colors.textPrimary)
            Text("Finding swap options")
                .afH2()
            Text("Coach is using today’s readiness and load.")
                .afMuted()
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("af_workout_swap_loading")
    }

    private func contentView(_ workout: Workout) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                AFTopBar(
                    title: "Swap workout",
                    subtitle: "Coach suggestions based on readiness and weekly load",
                    backIdentifier: "af_workout_swap_close",
                    backAction: { dismiss() },
                    right: { EmptyView() }
                )
                .padding(.horizontal, -Theme.Spacing.lg)

                Text(workout.name)
                    .afH2()

                if let description = workout.description, !description.isEmpty {
                    Text(description)
                        .afMuted()
                }

                HStack(spacing: Theme.Spacing.sm) {
                    AFChip(text: workout.formattedDuration)
                    AFChip(text: workout.sport.rawValue.capitalized)
                    AFChip(text: "\(workout.intervals.count) steps")
                }

                VStack(spacing: Theme.Spacing.sm) {
                    Button {
                        onSwap(workout)
                        dismiss()
                    } label: {
                        Label("Use this workout", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(AFPrimaryButtonStyle(size: .lg))
                    .accessibilityIdentifier("af_workout_swap_confirm")

                    Button {
                        Task { await viewModel.suggestAnother() }
                    } label: {
                        Label("Suggest another", systemImage: "sparkles")
                    }
                    .buttonStyle(AFGhostButtonStyle(size: .lg))
                    .accessibilityIdentifier("af_workout_swap_another")
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xl)
        }
    }

    private var emptyView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            AFTopBar(
                title: "Swap workout",
                subtitle: nil,
                backIdentifier: "af_workout_swap_close",
                backAction: { dismiss() },
                right: { EmptyView() }
            )
            Spacer()
            AFCard {
                VStack(spacing: Theme.Spacing.md) {
                    Text("No swap suggestion")
                        .afH2()
                    Text("The coach did not return an alternative. Try again or finish your current session.")
                        .afMuted()
                        .multilineTextAlignment(.center)
                    Button {
                        Task { await viewModel.retry() }
                    } label: {
                        Text("Try again")
                    }
                    .buttonStyle(AFPrimaryButtonStyle(size: .md))
                }
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }

    private var errorView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            AFTopBar(
                title: "Swap workout",
                subtitle: nil,
                backIdentifier: "af_workout_swap_close",
                backAction: { dismiss() },
                right: { EmptyView() }
            )
            Spacer()
            if let error = viewModel.ctaError {
                AFCard {
                    VStack(spacing: Theme.Spacing.md) {
                        Text("Couldn't load swap options")
                            .afH2()
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
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }
}
