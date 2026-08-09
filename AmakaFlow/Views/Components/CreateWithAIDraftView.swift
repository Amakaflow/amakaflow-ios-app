//
//  CreateWithAIDraftView.swift
//  AmakaFlow
//
//  AMA-2373 — Create with AI draft matching the approved mock: Edit ask +
//  purple DRAFT badge, meta pills, WHY THIS card, grouped blocks, refine dock,
//  Save | Start side-by-side.
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

// swiftlint:disable:next type_body_length
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

    private enum PendingCommit {
        case save
        case start
    }

    @State private var pendingCommit: PendingCommit?
    /// AMA-2383 — DRAFTING write-in (scripted fallback when response arrives whole).
    @StateObject private var draftingReveal: BuildRevealController
    @State private var draftingRevealDone = false

    init(
        viewModel: SuggestWorkoutViewModel,
        workout: Workout,
        onEditAsk: @escaping () -> Void,
        onWorkoutStarted: @escaping () -> Void,
        persistError: Binding<CTAError?>,
        retryPersist: Binding<(() -> Void)?>,
        showingUnifiedStart: Binding<Bool>,
        unifiedStartWorkout: Binding<Workout?>
    ) {
        self.viewModel = viewModel
        self.workout = workout
        self.onEditAsk = onEditAsk
        self.onWorkoutStarted = onWorkoutStarted
        self._persistError = persistError
        self._retryPersist = retryPersist
        self._showingUnifiedStart = showingUnifiedStart
        self._unifiedStartWorkout = unifiedStartWorkout

        let why = CreateWithAIDraftPresentation.whyThisBullets(
            whyThis: viewModel.whyThis,
            description: workout.description
        )
        // AMA-2395: the draft pill uses the estimator, like the saved detail.
        let pills = [
            WorkoutDurationEstimator.estimate(for: workout).pillLabel,
            workout.sport.displayName.uppercased(),
            "\(viewModel.draftMainBlocks.count) EXERCISES"
        ]
        _draftingReveal = StateObject(
            wrappedValue: BuildRevealController(
                config: BuildRevealScripts.aiFromDraft(
                    title: workout.name,
                    whyThis: why,
                    warmUp: viewModel.draftWarmUp,
                    mainBlocks: viewModel.draftMainBlocks,
                    cooldown: viewModel.draftCooldown,
                    metaPills: pills
                )
            )
        )
    }

    var body: some View {
        Group {
            if draftingRevealDone {
                draftContent
            } else {
                // Scripted DRAFTING reveal; CTA unlocks the refine/save draft.
                // When SSE lands, call sites can drive `draftingReveal.revealNext`
                // instead of `playScripted`.
                VStack(alignment: .leading, spacing: 0) {
                    draftNav
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.top, Theme.Spacing.md)
                    BuildRevealView(controller: draftingReveal) {
                        draftingRevealDone = true
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, 24)
                }
                .accessibilityIdentifier("create_with_ai_drafting_reveal")
            }
        }
        .accessibilityIdentifier("create_with_ai_draft_root")
    }

    private var draftContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                draftNav
                draftTitle
                draftMetaPills
                draftWhyThis
                CreateWithAIDraftSessionPlan(
                    mainTitle: mainBandTitle,
                    warmUp: viewModel.draftWarmUp,
                    blocks: viewModel.draftMainBlocks,
                    cooldown: viewModel.draftCooldown
                )

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
            .padding(.top, Theme.Spacing.md)
            .padding(.bottom, 40)
        }
    }

    private var draftNav: some View {
        HStack(spacing: 10) {
            Button(action: onEditAsk) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text(CreateWithAICopy.editAsk)
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(DailyDriver.foregroundMuted)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("create_with_ai_edit_ask")

            Spacer()

            Text(CreateWithAICopy.draftBadge)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(DailyDriver.foreground)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(DailyDriver.purple.opacity(0.22))
                .overlay(Capsule().stroke(DailyDriver.purple.opacity(0.55), lineWidth: 1))
                .clipShape(Capsule())
                .accessibilityIdentifier("create_with_ai_draft_badge")
        }
    }

    private var draftTitle: some View {
        Text(workout.name)
            .ddDisplayText(26, weight: .heavy)
            .foregroundColor(DailyDriver.foreground)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var draftMetaPills: some View {
        let pills = metaPillTexts
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(pills.prefix(3), id: \.self) { text in
                    metaPill(text)
                }
            }
            if pills.count > 3 {
                HStack(spacing: 8) {
                    ForEach(pills.dropFirst(3), id: \.self) { text in
                        metaPill(text)
                    }
                }
            }
        }
    }

    private var metaPillTexts: [String] {
        var pills = [
            durationPill,
            workout.sport.displayName.uppercased(),
            CreateWithAIDraftPresentation.exerciseCountLabel(
                warmUp: viewModel.draftWarmUp,
                blocks: viewModel.draftMainBlocks,
                cooldown: viewModel.draftCooldown
            )
        ]
        let gymAttached = viewModel.currentIncludeContext?.gym == true
        if let fits = CreateWithAIDraftPresentation.fitsGymLabel(
            gymAttached: gymAttached,
            gymName: DDActiveGymStore.load()?.name
        ) {
            pills.append(fits)
        }
        return pills
    }

    private var durationPill: String {
        WorkoutDurationEstimator.estimate(for: workout).pillLabel
    }

    private func metaPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(DailyDriver.foregroundMuted)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(DailyDriver.card)
            .overlay(Capsule().stroke(DailyDriver.border, lineWidth: 1))
            .clipShape(Capsule())
    }

    private var mainBandTitle: String {
        let name = workout.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "Session" }
        // Prefer a short block label: strip trailing "— 45" / " - 45" suffixes.
        // Require whitespace around ASCII hyphen so "Full-Body" stays intact.
        if let dash = name.range(of: "—") ?? name.range(of: " - ") {
            let head = name[..<dash.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            if !head.isEmpty { return head }
        }
        return name
    }

    @ViewBuilder
    private var draftWhyThis: some View {
        let bullets = CreateWithAIDraftPresentation.whyThisBullets(
            whyThis: viewModel.whyThis,
            description: workout.description
        )
        VStack(alignment: .leading, spacing: 10) {
            Text(CreateWithAICopy.whyThisHeading)
                .font(.system(size: 10, weight: .bold))
                .tracking(1.25)
                .foregroundColor(DailyDriver.foregroundDim)
                .frame(maxWidth: .infinity, alignment: .center)

            if !bullets.isEmpty {
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

            Text(CreateWithAICopy.noWearableNote.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundColor(DailyDriver.foregroundDim)
                .padding(.top, 2)
        }
        .padding(14)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier("create_with_ai_why_this")
    }

    private var commitCTAsDisabled: Bool {
        viewModel.isApplyingRefine || viewModel.isPersistingDraft
    }

    private var commitCTAs: some View {
        HStack(spacing: 10) {
            Button {
                saveToLibrary()
            } label: {
                HStack(spacing: 8) {
                    if pendingCommit == .save {
                        ProgressView().tint(DailyDriver.foreground).scaleEffect(0.8)
                    }
                    Text(CreateWithAICopy.saveToLibrary)
                        .ddDisplayText(13, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
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
                    if pendingCommit == .start {
                        ProgressView().tint(DailyDriver.ink).scaleEffect(0.8)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .bold))
                    }
                    Text(CreateWithAICopy.startCTA)
                        .ddDisplayText(15, weight: .bold)
                }
                .foregroundColor(DailyDriver.ink)
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
        pendingCommit = .save
        Task {
            await persistThenProceed(
                retry: { saveToLibrary() },
                onSuccess: { saved in
                    workoutsViewModel.acceptSuggestedWorkout(saved)
                    let minutes = max(1, saved.duration / 60)
                    DDToastCenter.shared.success(
                        DDToastCopy.savedToLibrary,
                        sub: DDToastCopy.savedSub(
                            workoutName: saved.name,
                            minutes: minutes,
                            collection: "Uncategorized"
                        )
                    )
                    onWorkoutStarted()
                    viewModel.reset()
                    dismiss()
                }
            )
        }
    }

    private func presentStartSheet() {
        persistError = nil
        pendingCommit = .start
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
        defer { pendingCommit = nil }
        switch await viewModel.persistDraftToBackend(workout) {
        case .success(let saved):
            onSuccess(saved)
        case .failure(let error):
            persistError = error
            retryPersist = retry
        }
    }
}
