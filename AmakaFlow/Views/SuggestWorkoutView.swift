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
                        CreateWithAICancelledView(onEditAsk: onEditAsk)
                    } else {
                        // AMA-2371: daily-coach staged generating (extracted from loadingView).
                        SuggestWorkoutGeneratingView(viewModel: viewModel) { dismiss() }
                    }

                case .needsOnboarding:
                    CoachingProfileOnboardingView(viewModel: viewModel)

                case .loading:
                    if mode == .createWithAI {
                        // AMA-2373 fix round 1: only the *initial* generate uses the
                        // staged full-screen generating view. A refine keeps the draft
                        // + refine dock on screen with an "applying…" indicator.
                        if viewModel.isApplyingRefine, let refiningWorkout = viewModel.suggestedWorkout {
                            createWithAIDraft(refiningWorkout)
                        } else {
                            CreateWithAIGeneratingView(
                                ask: viewModel.currentAsk,
                                chips: attachedSignalChips,
                                onCancel: cancelGeneration
                            )
                        }
                    } else {
                        SuggestWorkoutGeneratingView(viewModel: viewModel) { dismiss() }
                    }

                case .success(let workout):
                    if mode == .createWithAI {
                        createWithAIDraft(workout)
                    } else {
                        scrollContainer {
                            SuggestWorkoutDailyCoachContent(
                                viewModel: viewModel,
                                workout: workout,
                                mode: mode,
                                onStart: { startWorkout(workout) },
                                onDismiss: { dismiss() }
                            )
                        }
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
                        onRetry: retryPersist
                    ) {
                        self.persistError = nil
                        self.retryPersist = nil
                    }
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

    // MARK: - Create with AI

    /// AMA-2373 fix round 1: cancel from the generating view must not dead-end
    /// on an indefinite spinner — return to compose so the user can re-ask.
    private func cancelGeneration() {
        viewModel.cancelGenerate()
        onEditAsk()
    }

    private func createWithAIDraft(_ workout: Workout) -> some View {
        CreateWithAIDraftView(
            viewModel: viewModel,
            workout: workout,
            onEditAsk: onEditAsk,
            onWorkoutStarted: onWorkoutStarted,
            persistError: $persistError,
            retryPersist: $retryPersist,
            showingUnifiedStart: $showingUnifiedStart,
            unifiedStartWorkout: $unifiedStartWorkout
        )
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

#Preview {
    SuggestWorkoutView(viewModel: SuggestWorkoutViewModel())
        .environmentObject(WorkoutsViewModel())
}
