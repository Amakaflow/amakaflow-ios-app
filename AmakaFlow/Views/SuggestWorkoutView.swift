//
//  SuggestWorkoutView.swift
//  AmakaFlow
//
//  Sheet view showing AI-generated workout preview with start/swap/rest actions (AMA-1994).
//

import SwiftUI

enum SuggestWorkoutMode: Equatable {
    case dailyCoach
    case createWithAI
}

struct SuggestWorkoutView: View {
    @ObservedObject var viewModel: SuggestWorkoutViewModel
    var mode: SuggestWorkoutMode = .dailyCoach
    var onWorkoutStarted: () -> Void = {}
    /// AMA-2373: lets the createWithAI draft's "Edit ask" link return to compose.
    var onEditAsk: () -> Void = {}
    @EnvironmentObject var workoutsViewModel: WorkoutsViewModel
    @Environment(\.dismiss) private var dismiss
    /// AMA-2373 fix round 1: createWithAI's "▸ Start" hands off to the same
    /// gym/device sheet + enrichment → push handoff as Library's detail view,
    /// instead of a bespoke save-and-close for Garmin/Apple.
    @State private var showingUnifiedStart = false
    @State private var unifiedStartWorkout: Workout?
    /// AMA-2373 fix round 2: surfaces a failed `persistDraftToBackend` without
    /// touching `viewModel.ctaError` (see the overlay above for why).
    @State private var persistError: CTAError?
    @State private var retryPersist: (() -> Void)?

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundColor.ignoresSafeArea()

                switch viewModel.state {
                case .idle:
                    // AMA-2373 fix round 1: cancelGenerate() lands here. For createWithAI
                    // that must not be an indefinite spinner with no escape — bounce back
                    // to compose. (cancelGeneration() below already calls onEditAsk, so
                    // this is a defensive fallback for any other path into `.idle`.)
                    if mode == .createWithAI {
                        createWithAICancelledView
                    } else {
                        loadingView
                    }

                case .needsOnboarding:
                    CoachingProfileOnboardingView(viewModel: viewModel)

                case .loading:
                    if mode == .createWithAI {
                        // AMA-2373 fix round 1: only the *initial* generate uses the
                        // staged full-screen generating view. A refine keeps the draft
                        // + refine dock on screen with an "applying…" indicator.
                        if viewModel.isApplyingRefine, let refiningWorkout = viewModel.suggestedWorkout {
                            createWithAIDraftView(refiningWorkout)
                        } else {
                            CreateWithAIGeneratingView(
                                ask: viewModel.currentAsk,
                                chips: attachedSignalChips,
                                onCancel: cancelGeneration
                            )
                        }
                    } else {
                        loadingView
                    }

                case .success(let workout):
                    if mode == .createWithAI {
                        createWithAIDraftView(workout)
                    } else {
                        contentView(workout)
                    }

                case .empty:
                    emptyView

                case .error(let ctaError):
                    errorView(ctaError)
                }
            }
            .navigationBarHidden(true)
            .overlay(alignment: .top) {
                // AMA-2373 fix round 2: a failed Save/Start persist gets its own
                // toast (Retry re-runs the persist), never `viewModel.ctaError` —
                // that error's Retry re-runs suggestWorkout() (regenerate), which
                // would silently throw away this draft.
                if let persistError {
                    ErrorToast(
                        actionTitle: "Couldn't save workout",
                        error: persistError,
                        onRetry: retryPersist,
                        onDismiss: {
                            self.persistError = nil
                            self.retryPersist = nil
                        }
                    )
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.md)
                } else if let error = viewModel.ctaError {
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
        .preferredColorScheme(mode == .createWithAI ? .dark : nil)
        .fullScreenCover(isPresented: $showingUnifiedStart, onDismiss: finishAfterStart) {
            if let unifiedStartWorkout {
                UnifiedWorkoutDetailView(workout: unifiedStartWorkout, autoStartOnAppear: true)
            }
        }
    }

    private var backgroundColor: Color {
        mode == .createWithAI ? DailyDriver.screenBackground : Theme.Colors.background
    }

    private var attachedSignalChips: [CreateWithAIContextChip] {
        guard let flags = viewModel.currentIncludeContext else { return [] }
        var chips: [CreateWithAIContextChip] = []
        if flags.gym == true { chips.append(.gym) }
        if flags.profile == true { chips.append(.profile) }
        if flags.memories == true { chips.append(.memories) }
        return chips
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

            if mode == .dailyCoach {
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
    }

    // MARK: - Create with AI cancel

    /// AMA-2373 fix round 1: cancel from the generating view must not dead-end
    /// on an indefinite spinner — return to compose so the user can re-ask.
    private func cancelGeneration() {
        viewModel.cancelGenerate()
        onEditAsk()
    }

    private var createWithAICancelledView: some View {
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

    // MARK: - Create with AI draft

    private func createWithAIDraftView(_ workout: Workout) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                createWithAICloseRow
                draftHeader(workout)
                draftMetaPills(workout)
                draftWhyThis(workout)
                draftBands(workout)

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

                commitCTAs(workout)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.lg)
            .padding(.bottom, 40)
        }
        .accessibilityIdentifier("create_with_ai_draft_root")
    }

    private var createWithAICloseRow: some View {
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

    private func draftHeader(_ workout: Workout) -> some View {
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

    private func draftMetaPills(_ workout: Workout) -> some View {
        HStack(spacing: 8) {
            createWithAIMetaPill(workout.formattedDuration)
            createWithAIMetaPill(workout.sport.displayName)
            createWithAIMetaPill("\(workout.intervals.count) steps")
        }
    }

    private func createWithAIMetaPill(_ text: String) -> some View {
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
    private func draftWhyThis(_ workout: Workout) -> some View {
        let bullets = CreateWithAIDraftPresentation.whyThisBullets(
            whyThis: viewModel.whyThis,
            description: workout.description
        )
        if !bullets.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                createWithAISectionLabel(CreateWithAICopy.whyThisHeading)
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

    private func draftBands(_ workout: Workout) -> some View {
        let rows = CreateWithAIDraftPresentation.bandRows(
            warmUp: viewModel.draftWarmUp,
            blocks: viewModel.draftMainBlocks,
            cooldown: viewModel.draftCooldown
        )
        return VStack(alignment: .leading, spacing: 10) {
            createWithAISectionLabel("SESSION PLAN")
            ForEach(Self.numberedDraftRows(rows), id: \.offset) { item in
                draftRow(item.row, number: item.number)
            }
        }
        .accessibilityIdentifier("create_with_ai_session_plan")
    }

    private static func numberedDraftRows(
        _ rows: [DraftRow]
    ) -> [(offset: Int, row: DraftRow, number: Int?)] {
        var mainIndex = 0
        return rows.enumerated().map { offset, row in
            guard row.band == .main, !row.isSummary else {
                return (offset, row, nil)
            }
            mainIndex += 1
            return (offset, row, mainIndex)
        }
    }

    private func draftRow(_ row: DraftRow, number: Int?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            draftRowBadge(row, number: number)

            VStack(alignment: .leading, spacing: 3) {
                Text(draftRowTitle(row))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DailyDriver.foreground)
                if let detail = draftRowDetail(row) {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundColor(DailyDriver.foregroundMuted)
                }
            }

            Spacer(minLength: 8)

            if let restSeconds = row.restChipSeconds {
                createWithAIRestChip(seconds: restSeconds)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func draftRowBadge(_ row: DraftRow, number: Int?) -> some View {
        if row.isSummary {
            Image(systemName: row.band == .warmUp ? "flame.fill" : "wind")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DailyDriver.ink)
                .frame(width: 26, height: 26)
                .background(DailyDriver.amber)
                .clipShape(Circle())
        } else {
            Text("\(number ?? 0)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(DailyDriver.ink)
                .frame(width: 26, height: 26)
                .background(DailyDriver.lime)
                .clipShape(Circle())
        }
    }

    private func draftRowTitle(_ row: DraftRow) -> String {
        switch row.band {
        case .warmUp: return "Warm-up"
        case .cooldown: return "Cool-down"
        case .main: return createWithAIMainIntervalName(row.interval)
        }
    }

    private func createWithAIMainIntervalName(_ interval: WorkoutInterval) -> String {
        switch interval {
        case .warmup: return "Warm-up"
        case .cooldown: return "Cool-down"
        case .time(_, let target): return target ?? "Timed work"
        case .reps(_, _, let name, _, _, _): return name
        case .distance(let meters, _): return "\(meters)m"
        case .repeat(let reps, _): return "Repeat x\(reps)"
        case .rest: return "Rest"
        }
    }

    private func draftRowDetail(_ row: DraftRow) -> String? {
        if row.isSummary {
            return createWithAISummaryDetail(row.interval)
        }
        switch row.interval {
        case .reps(let sets, let reps, _, let load, _, _):
            var parts: [String] = []
            if let sets { parts.append("\(sets)x") }
            parts.append("\(reps) reps")
            if let load { parts.append("@ \(load)") }
            return parts.joined(separator: " ")
        case .time(let seconds, _):
            return "\(max(1, seconds / 60)) min"
        case .distance(_, let target):
            return target
        case .repeat(_, let intervals):
            return "\(intervals.count) exercises"
        default:
            return nil
        }
    }

    private func createWithAISummaryDetail(_ interval: WorkoutInterval) -> String? {
        switch interval {
        case .warmup(let seconds, let target), .cooldown(let seconds, let target):
            let minutes = max(1, seconds / 60)
            if let target, !target.isEmpty {
                return "\(minutes) min · \(target)"
            }
            return "\(minutes) min"
        default:
            return nil
        }
    }

    private func createWithAIRestChip(seconds: Int) -> some View {
        Text("\(seconds)s rest")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(DailyDriver.foregroundMuted)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DailyDriver.card2)
            .clipShape(Capsule())
    }

    private func createWithAISectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .tracking(1.25)
            .foregroundColor(DailyDriver.foregroundDim)
    }

    private var commitCTAsDisabled: Bool {
        viewModel.isApplyingRefine || viewModel.isPersistingDraft
    }

    private func commitCTAs(_ workout: Workout) -> some View {
        VStack(spacing: 10) {
            Button {
                saveToLibrary(workout)
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
                presentStartSheet(workout)
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

    private func saveToLibrary(_ workout: Workout) {
        persistError = nil
        Task {
            await persistThenProceed(workout, retry: { saveToLibrary(workout) }) { saved in
                workoutsViewModel.acceptSuggestedWorkout(saved)
                onWorkoutStarted()
                viewModel.reset()
                dismiss()
            }
        }
    }

    private func presentStartSheet(_ workout: Workout) {
        persistError = nil
        Task {
            await persistThenProceed(workout, retry: { presentStartSheet(workout) }) { saved in
                workoutsViewModel.acceptSuggestedWorkout(saved)
                unifiedStartWorkout = saved
                showingUnifiedStart = true
            }
        }
    }

    /// AMA-2373 fix round 2: awaits the real `POST /workouts/save` (via
    /// `viewModel.persistDraftToBackend`) so `onSuccess` always receives a
    /// workout with a genuine server id before Save bookkeeps it locally or
    /// Start hands off to `UnifiedWorkoutDetailView`'s enrichment/push path.
    private func persistThenProceed(
        _ workout: Workout,
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

    private func finishAfterStart() {
        onWorkoutStarted()
        viewModel.reset()
        dismiss()
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
                    title: topBarTitle,
                    subtitle: topBarSubtitle,
                    backIdentifier: "suggest_workout_done",
                    backAction: { dismiss() },
                    right: {
                        if mode == .dailyCoach {
                            AFChip(text: "AI Coach", outline: true)
                        }
                    }
                )
                .padding(.horizontal, -Theme.Spacing.lg)

                content()
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, 40)
        }
    }

    private var topBarTitle: String {
        switch mode {
        case .dailyCoach:
            return "Today’s suggestion"
        case .createWithAI:
            return "Create with AI"
        }
    }

    private var topBarSubtitle: String? {
        switch mode {
        case .dailyCoach:
            return "Readiness, rationale, and one generated session"
        case .createWithAI:
            return nil
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
        onWorkoutStarted()
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
