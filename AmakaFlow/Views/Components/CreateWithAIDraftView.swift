//
//  CreateWithAIDraftView.swift
//  AmakaFlow
//
//  AMA-2373 — Create with AI draft / cancelled UI extracted from
//  SuggestWorkoutView to satisfy SwiftLint file_length / type_body_length
//  (mirrors SuggestWorkoutGeneratingView for AMA-2371).
//

import SwiftUI

struct CreateWithAICancelledView: View {
    var onEditAsk: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 32, weight: .semibold))
                .foregroundColor(DailyDriver.foregroundMuted)
            Text("Generation cancelled")
                .ddDisplayText(17, weight: .bold)
                .foregroundColor(DailyDriver.foreground)
            Button(action: onEditAsk) {
                Text(CreateWithAICopy.editAsk)
                    .ddDisplayText(14, weight: .bold)
                    .foregroundColor(DailyDriver.ink)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(DailyDriver.lime)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("create_with_ai_cancelled_edit_ask")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("create_with_ai_cancelled")
    }
}

struct CreateWithAIDraftView: View {
    @ObservedObject var viewModel: SuggestWorkoutViewModel
    @EnvironmentObject var workoutsViewModel: WorkoutsViewModel
    @Environment(\.dismiss) private var dismiss

    let workout: Workout
    var onEditAsk: () -> Void
    var onWorkoutStarted: () -> Void
    @Binding var persistError: CTAError?
    @Binding var retryPersist: (() -> Void)?
    @Binding var showingUnifiedStart: Bool
    @Binding var unifiedStartWorkout: Workout?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                closeRow
                draftHeader
                draftMetaPills
                draftWhyThis
                CreateWithAIDraftSessionPlan(
                    warmUp: viewModel.draftWarmUp,
                    blocks: viewModel.draftMainBlocks,
                    cooldown: viewModel.draftCooldown
                )

                Text(CreateWithAICopy.noWearableNote)
                    .font(.system(size: 11))
                    .foregroundColor(DailyDriver.foregroundDim)

                CreateWithAIRefineDock(
                    appliedTweaks: viewModel.appliedTweaks,
                    canUndo: !viewModel.undoStack.isEmpty,
                    isApplying: viewModel.isApplyingRefine,
                    onApply: { tweak in Task { await viewModel.applyRefine(tweak: tweak) } },
                    onUndo: { viewModel.undoRefine() },
                    onSuggestAnother: { Task { await viewModel.suggestAnother() } }
                )

                commitCTAs
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.lg)
            .padding(.bottom, 40)
        }
        .accessibilityIdentifier("create_with_ai_draft_root")
    }

    private var closeRow: some View {
        HStack {
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(DailyDriver.foreground)
                    .frame(width: 32, height: 32)
                    .background(DailyDriver.card2)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("suggest_workout_done")
        }
    }

    private var draftHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(workout.name)
                .ddDisplayText(24, weight: .heavy)
                .foregroundColor(DailyDriver.foreground)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Text(CreateWithAICopy.draftBadge)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(DailyDriver.amber)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(DailyDriver.amber.opacity(0.14))
                    .overlay(Capsule().stroke(DailyDriver.amber.opacity(0.4), lineWidth: 1))
                    .clipShape(Capsule())

                Button(action: onEditAsk) {
                    Text(CreateWithAICopy.editAsk)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(DailyDriver.lime)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("create_with_ai_edit_ask")
            }
        }
    }

    private var draftMetaPills: some View {
        HStack(spacing: 8) {
            metaPill(workout.formattedDuration)
            metaPill(workout.sport.displayName)
            metaPill("\(workout.intervals.count) steps")
        }
    }

    private func metaPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundColor(DailyDriver.foregroundMuted)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(DailyDriver.card)
            .overlay(Capsule().stroke(DailyDriver.border, lineWidth: 1))
            .clipShape(Capsule())
    }

    @ViewBuilder
    private var draftWhyThis: some View {
        let bullets = CreateWithAIDraftPresentation.whyThisBullets(
            whyThis: viewModel.whyThis,
            description: workout.description
        )
        if !bullets.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel(CreateWithAICopy.whyThisHeading)
                ForEach(bullets, id: \.self) { bullet in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(DailyDriver.lime)
                            .frame(width: 5, height: 5)
                            .padding(.top, 6)
                        Text(bullet)
                            .font(.system(size: 13))
                            .foregroundColor(DailyDriver.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .accessibilityIdentifier("create_with_ai_why_this")
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .tracking(1.25)
            .foregroundColor(DailyDriver.foregroundDim)
    }

    private var commitCTAsDisabled: Bool {
        viewModel.isApplyingRefine || viewModel.isPersistingDraft
    }

    private var commitCTAs: some View {
        VStack(spacing: 10) {
            Button {
                saveToLibrary()
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isPersistingDraft {
                        ProgressView().tint(DailyDriver.foreground).scaleEffect(0.8)
                    }
                    Text(CreateWithAICopy.saveToLibrary)
                        .ddDisplayText(15, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(DailyDriver.tabBarBackground)
                .overlay(Capsule().stroke(DailyDriver.borderStrong, lineWidth: 1))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(commitCTAsDisabled)
            .opacity(commitCTAsDisabled ? 0.5 : 1)
            .accessibilityIdentifier("create_with_ai_save")

            Button {
                presentStartSheet()
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isPersistingDraft {
                        ProgressView().tint(DailyDriver.ink).scaleEffect(0.8)
                    }
                    Text(CreateWithAICopy.startCTA)
                        .ddDisplayText(15, weight: .bold)
                        .foregroundColor(DailyDriver.ink)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(DailyDriver.lime)
                .clipShape(Capsule())
                .ddLimeGlow()
            }
            .buttonStyle(.plain)
            .disabled(commitCTAsDisabled)
            .opacity(commitCTAsDisabled ? 0.5 : 1)
            .accessibilityIdentifier("create_with_ai_start")
        }
        .padding(.top, 4)
    }

    private func saveToLibrary() {
        persistError = nil
        Task {
            await persistThenProceed(
                retry: { saveToLibrary() },
                onSuccess: { saved in
                    workoutsViewModel.acceptSuggestedWorkout(saved)
                    onWorkoutStarted()
                    viewModel.reset()
                    dismiss()
                }
            )
        }
    }

    private func presentStartSheet() {
        persistError = nil
        Task {
            await persistThenProceed(
                retry: { presentStartSheet() },
                onSuccess: { saved in
                    workoutsViewModel.acceptSuggestedWorkout(saved)
                    unifiedStartWorkout = saved
                    showingUnifiedStart = true
                }
            )
        }
    }

    /// Awaits `POST /workouts/save` so Save/Start always receive a server id
    /// before local bookkeeping or enrichment push (AMA-2072 race lesson).
    private func persistThenProceed(
        retry: @escaping () -> Void,
        onSuccess: (Workout) -> Void
    ) async {
        switch await viewModel.persistDraftToBackend(workout) {
        case .success(let saved):
            onSuccess(saved)
        case .failure(let error):
            persistError = error
            retryPersist = retry
        }
    }
}
