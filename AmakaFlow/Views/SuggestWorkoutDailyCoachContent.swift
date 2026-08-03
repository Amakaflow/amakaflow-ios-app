//
//  SuggestWorkoutDailyCoachContent.swift
//  AmakaFlow
//
//  AMA-2373 — daily-coach success surface extracted from SuggestWorkoutView
//  for SwiftLint type_body_length under --strict.
//

import SwiftUI

struct SuggestWorkoutDailyCoachContent: View {
    @ObservedObject var viewModel: SuggestWorkoutViewModel
    let workout: Workout
    var mode: SuggestWorkoutMode
    var onStart: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            readinessCard
            workoutCard
            actionButtons
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

    private var workoutCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            AFCard(padding: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    HStack(alignment: .top, spacing: Theme.Spacing.md) {
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous)
                            .fill(Theme.Colors.accentBackground)
                            .frame(width: 46, height: 46)
                            .overlay(
                                Image(systemName: workout.sport.symbolName)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(Theme.Colors.textPrimary)
                            )

                        VStack(alignment: .leading, spacing: 8) {
                            AFLabel(text: "Suggested workout")
                            Text(workout.name)
                                .font(Theme.Typography.title1)
                                .foregroundColor(Theme.Colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: Theme.Spacing.sm) {
                                AFChip(text: workout.formattedDuration)
                                AFChip(text: workout.sport.displayName)
                                AFChip(text: "\(workout.intervals.count) steps")
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if let rationale = workout.description?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                       !rationale.isEmpty {
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
                            ForEach(
                                Array(workout.intervals.enumerated()),
                                id: \.offset
                            ) { index, interval in
                                SuggestIntervalRow(index: index + 1, interval: interval)
                            }
                        }
                    }
                }
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Button(action: onStart) {
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

            if mode == .dailyCoach {
                Button {
                    viewModel.restToday()
                    onDismiss()
                } label: {
                    Label("Rest today", systemImage: "moon.zzz")
                }
                .buttonStyle(AFGhostButtonStyle(size: .lg))
                .accessibilityIdentifier("af_suggest_rest")
            }
        }
    }
}
