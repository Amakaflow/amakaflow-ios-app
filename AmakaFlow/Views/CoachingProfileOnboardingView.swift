//
//  CoachingProfileOnboardingView.swift
//  AmakaFlow
//
//  Coaching profile onboarding for workout suggestions.
//  AMA-1997 replaces the old single primary-goal question with a
//  generated-contract-backed multi-goal picker persisted to goals[].
//

import Combine
import SwiftUI

@MainActor
final class CoachingProfileOnboardingViewModel: ObservableObject {
    typealias GoalEntry = Components.Schemas.GoalEntry
    typealias GeneratedCoachingProfile = Components.Schemas.CoachingProfile
    typealias CoachingProfileUpsert = Components.Schemas.CoachingProfileUpsert

    enum ScreenState: Equatable {
        case loading
        case content
        case empty
        case error(CTAError)
    }

    enum FailedAction {
        case load
        case save
    }

    enum GoalType: String, CaseIterable, Identifiable, Hashable {
        case race
        case strength
        case health
        case mobility
        case none

        var id: String { rawValue }

        var emoji: String {
            switch self {
            case .race: return "🏃"
            case .strength: return "🏋️"
            case .health: return "🩺"
            case .mobility: return "🧘"
            case .none: return "😶"
            }
        }

        var title: String {
            switch self {
            case .race: return "Race or event"
            case .strength: return "Strength / aesthetic"
            case .health: return "Medical / general health"
            case .mobility: return "Mobility"
            case .none: return "No specific goal"
            }
        }

        var subtitle: String {
            switch self {
            case .race: return "Add the event name and date if you have one."
            case .strength: return "Pick the body-composition outcome that fits best."
            case .health: return "General wellness, energy, and sustainable training."
            case .mobility: return "Layer mobility work into the plan."
            case .none: return "Keep coach flexible; this clears other goals."
            }
        }

        var accessibilityIdentifier: String { "goal_card_\(rawValue)" }
        var removeAccessibilityIdentifier: String { "goal_remove_\(rawValue)" }
    }

    enum StrengthSubtype: String, CaseIterable, Identifiable, Hashable {
        case buildMuscle = "build_muscle"
        case loseWeight = "lose_weight"
        case lookGood = "look_good"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .buildMuscle: return "Build muscle"
            case .loseWeight: return "Lose weight"
            case .lookGood: return "Just look good"
            }
        }

        var accessibilityIdentifier: String { "goal_strength_\(rawValue)" }
    }

    @Published private(set) var state: ScreenState = .loading
    @Published private(set) var ctaError: CTAError?
    @Published private(set) var isSaving = false
    @Published private(set) var selectedGoalTypes = Set<GoalType>()
    @Published var experience: ExperienceLevel = .intermediate
    @Published var daysPerWeek: Int = 3
    @Published var raceEvent = ""
    @Published var raceDate = ""
    @Published var strengthSubtype: StrengthSubtype = .buildMuscle

    private let apiService: APIServiceProviding
    private var profile: GeneratedCoachingProfile?
    private(set) var lastFailedAction: FailedAction?

    var selectedCount: Int { selectedGoalTypes.count }

    var canContinue: Bool {
        profile != nil && selectedCount > 0 && !isSaving
    }

    var legacyTrainingGoal: TrainingGoal {
        if selectedGoalTypes.contains(.strength) {
            switch strengthSubtype {
            case .buildMuscle: return .buildMuscle
            case .loseWeight: return .loseWeight
            case .lookGood: return .generalFitness
            }
        }
        if selectedGoalTypes.contains(.race) { return .athletic }
        return .generalFitness
    }

    init(apiService: APIServiceProviding? = nil) {
        self.apiService = apiService ?? AppDependencies.current.apiService
    }

    func load() async {
        state = .loading
        ctaError = nil
        lastFailedAction = nil

        do {
            let fetched = try await apiService.getCoachingProfile() ?? Self.emptyProfileDraft()
            profile = fetched
            experience = ExperienceLevel(rawValue: fetched.experienceLevel) ?? .intermediate
            daysPerWeek = clampDaysPerWeek(fetched.sessionsPerWeek)
            applyGoals(fetched.goals ?? [])
            state = selectedGoalTypes.isEmpty ? .empty : .content
        } catch {
            let mapped = CTAError.map(error)
            ctaError = mapped
            state = .error(mapped)
            lastFailedAction = .load
        }
    }

    func save() async -> Bool {
        guard canContinue else { return false }
        isSaving = true
        ctaError = nil
        lastFailedAction = nil

        let goals = buildGoals()

        do {
            let latestProfile = try await apiService.getCoachingProfile() ?? profile ?? Self.emptyProfileDraft()
            profile = latestProfile

            let upsert = CoachingProfileUpsert(
                equipment: latestProfile.equipment,
                experienceLevel: experience.rawValue,
                goals: goals,
                injuriesLimitations: latestProfile.injuriesLimitations,
                preferredDays: latestProfile.preferredDays,
                primaryGoal: latestProfile.primaryGoal,
                sessionDurationMinutes: latestProfile.sessionDurationMinutes,
                sessionsPerWeek: daysPerWeek
            )

            let saved = try await apiService.upsertCoachingProfile(upsert)
            self.profile = saved
            applyGoals(saved.goals ?? goals)
            state = .content
            isSaving = false
            return true
        } catch {
            let mapped = CTAError.map(error)
            ctaError = mapped
            lastFailedAction = .save
            // Save failures keep the form visible and surface a toast (inline
            // recovery); the screen only enters .error on a failed initial load.
            isSaving = false
            return false
        }
    }

    func retryLastAction() async {
        switch lastFailedAction {
        case .load:
            await load()
        case .save:
            _ = await save()
        case .none:
            break
        }
    }

    func dismissError() {
        let currentError = ctaError
        ctaError = nil

        if lastFailedAction == .load, let currentError {
            state = .error(currentError)
            return
        }

        if case .error = state {
            state = selectedGoalTypes.isEmpty ? .empty : .content
        }
    }

    func reportError(reporter: ErrorReporting? = nil) {
        guard let ctaError else { return }
        let reporter = reporter ?? ErrorReporter.shared
        reporter.report(
            action: lastFailedAction == .load ? "coaching_goals_load" : "coaching_goals_save",
            error: ctaError,
            endpoint: "/v1/coaching/profile",
            userId: PairingService.shared.userProfile?.id
        )
    }

    func isSelected(_ goalType: GoalType) -> Bool {
        selectedGoalTypes.contains(goalType)
    }

    func toggleGoal(_ goalType: GoalType) {
        if isSelected(goalType) {
            removeGoal(goalType)
        } else {
            selectGoal(goalType)
        }
    }

    func selectGoal(_ goalType: GoalType) {
        if goalType == .none {
            selectedGoalTypes = [.none]
            clearSpecificFields(except: GoalType.none)
        } else {
            selectedGoalTypes.remove(.none)
            selectedGoalTypes.insert(goalType)
        }
        updateStateForCurrentSelection()
    }

    func removeGoal(_ goalType: GoalType) {
        selectedGoalTypes.remove(goalType)
        clearSpecificFields(except: nil, removed: goalType)
        updateStateForCurrentSelection()
    }

    func selectStrengthSubtype(_ subtype: StrengthSubtype) {
        strengthSubtype = subtype
        selectGoal(.strength)
    }

    func buildGoals() -> [GoalEntry] {
        GoalType.allCases.compactMap { goalType in
            guard selectedGoalTypes.contains(goalType) else { return nil }
            switch goalType {
            case .race:
                return GoalEntry(
                    date: trimmedOptional(raceDate),
                    event: trimmedOptional(raceEvent),
                    _type: goalType.rawValue
                )
            case .strength:
                return GoalEntry(strengthSubtype: strengthSubtype.rawValue, _type: goalType.rawValue)
            case .health, .mobility, .none:
                return GoalEntry(_type: goalType.rawValue)
            }
        }
    }

    static func accessibilityIdentifiers() -> [String] {
        GoalType.allCases.map(\.accessibilityIdentifier) +
        GoalType.allCases.map(\.removeAccessibilityIdentifier) +
        StrengthSubtype.allCases.map(\.accessibilityIdentifier) +
        ["goal_race_event", "goal_race_date", "coaching_onboarding_continue"]
    }

    private static func emptyProfileDraft() -> GeneratedCoachingProfile {
        GeneratedCoachingProfile(
            createdAt: "",
            equipment: nil,
            experienceLevel: "intermediate",
            goals: nil,
            primaryGoal: "general_fitness",
            sessionsPerWeek: 3,
            updatedAt: "",
            userId: ""
        )
    }

    private func applyGoals(_ goals: [GoalEntry]) {
        selectedGoalTypes.removeAll()
        raceEvent = ""
        raceDate = ""
        strengthSubtype = .buildMuscle

        if goals.contains(where: { $0._type == GoalType.none.rawValue }) {
            selectedGoalTypes = [.none]
            return
        }

        for goal in goals {
            guard let goalType = GoalType(rawValue: goal._type) else { continue }
            selectedGoalTypes.insert(goalType)
            switch goalType {
            case .race:
                raceEvent = goal.event ?? ""
                raceDate = goal.date ?? ""
            case .strength:
                strengthSubtype = StrengthSubtype(rawValue: goal.strengthSubtype ?? "") ?? .buildMuscle
            case .health, .mobility, .none:
                break
            }
        }
    }

    private func updateStateForCurrentSelection() {
        guard profile != nil else { return }
        if case .error = state { return }
        if case .loading = state { return }
        state = selectedGoalTypes.isEmpty ? .empty : .content
    }

    private func clearSpecificFields(except: GoalType?, removed: GoalType? = nil) {
        if except == GoalType.none {
            raceEvent = ""
            raceDate = ""
            strengthSubtype = .buildMuscle
            return
        }

        if removed == .race {
            raceEvent = ""
            raceDate = ""
        }
        if removed == .strength {
            strengthSubtype = .buildMuscle
        }
    }

    private func trimmedOptional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func clampDaysPerWeek(_ value: Int) -> Int {
        min(max(value, 1), 7)
    }
}

struct CoachingProfileOnboardingView: View {
    @ObservedObject var viewModel: SuggestWorkoutViewModel
    @StateObject private var onboardingViewModel: CoachingProfileOnboardingViewModel

    @State private var consentAccepted = UserDefaults.standard.bool(forKey: "biometric_consent_v1")
    @State private var didLoad = false

    init(
        viewModel: SuggestWorkoutViewModel,
        onboardingViewModel: CoachingProfileOnboardingViewModel? = nil
    ) {
        self.viewModel = viewModel
        _onboardingViewModel = StateObject(wrappedValue: onboardingViewModel ?? CoachingProfileOnboardingViewModel())
    }

    var body: some View {
        if !consentAccepted {
            BiometricConsentView(
                onAccept: {
                    UserDefaults.standard.set(true, forKey: "biometric_consent_v1")
                    consentAccepted = true
                },
                onDecline: {
                    UserDefaults.standard.set(false, forKey: "biometric_consent_v1")
                }
            )
        } else {
            onboardingBody
        }
    }

    private var onboardingBody: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            Group {
                switch onboardingViewModel.state {
                case .loading:
                    loadingView
                case .content, .empty:
                    formView(showEmptyBanner: onboardingViewModel.state == .empty)
                case .error:
                    loadErrorView
                }
            }
        }
        .overlay(alignment: .top) {
            if let error = onboardingViewModel.ctaError {
                ErrorToast(
                    actionTitle: onboardingViewModel.lastFailedAction == .load ? "Couldn't load goals" : "Couldn't save goals",
                    error: error,
                    onRetry: error.isRetryable ? { Task { await onboardingViewModel.retryLastAction() } } : nil,
                    onReport: { onboardingViewModel.reportError() },
                    onDismiss: { onboardingViewModel.dismissError() }
                )
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)
            }
        }
        .task {
            guard !didLoad else { return }
            didLoad = true
            await onboardingViewModel.load()
        }
        .accessibilityIdentifier("coaching_onboarding")
    }

    private var loadingView: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .tint(Theme.Colors.textPrimary)
            Text("Loading your coaching profile")
                .afMuted()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("coaching_onboarding_loading")
    }

    private var loadErrorView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            header
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.lg)

            Spacer()

            AFCard {
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundColor(Theme.Colors.accentRed)
                    Text("We couldn't load your goals.")
                        .afH2()
                        .multilineTextAlignment(.center)
                    Text("Retry when you’re back online. Nothing has been changed.")
                        .afMuted()
                        .multilineTextAlignment(.center)
                    Button {
                        Task { await onboardingViewModel.load() }
                    } label: {
                        Text("Retry")
                    }
                    .buttonStyle(AFPrimaryButtonStyle(size: .md))
                    .accessibilityIdentifier("coaching_onboarding_retry_load")
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Theme.Spacing.lg)

            Spacer()
        }
        .accessibilityIdentifier("coaching_onboarding_error")
    }

    private func formView(showEmptyBanner: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header

                if showEmptyBanner {
                    emptyBanner
                }

                experienceCard
                goalsCard
                daysPerWeekCard
                equipmentLink
                continueButton
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.lg)
            .padding(.bottom, 40)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            AFLabel(text: "Coaching Profile")

            Text("What are you training for?")
                .font(Theme.Typography.largeTitle)
                .foregroundColor(Theme.Colors.textPrimary)

            Text("Select all that apply. Add a date if you have one.")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyBanner: some View {
        AFCard {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: "target")
                    .foregroundColor(Theme.Colors.readyModerate)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pick at least one goal")
                        .afH3()
                    Text("You can choose multiple goals, or choose No specific goal if you want coach to keep the plan flexible.")
                        .afMuted()
                }
            }
        }
        .accessibilityIdentifier("coaching_onboarding_empty_state")
    }

    private var experienceCard: some View {
        AFCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Experience Level")
                    .afH3()

                Picker("Experience", selection: $onboardingViewModel.experience) {
                    ForEach(ExperienceLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var goalsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Training Goals")
                .afH3()

            ForEach(CoachingProfileOnboardingViewModel.GoalType.allCases) { goalType in
                goalCard(goalType)
            }
        }
    }

    private func goalCard(_ goalType: CoachingProfileOnboardingViewModel.GoalType) -> some View {
        let isSelected = onboardingViewModel.isSelected(goalType)

        return AFCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            onboardingViewModel.toggleGoal(goalType)
                        }
                    } label: {
                        HStack(alignment: .top, spacing: Theme.Spacing.md) {
                            Text(goalType.emoji)
                                .font(.system(size: 24))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(goalType.title)
                                    .afH3()
                                Text(goalType.subtitle)
                                    .afMuted()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    if isSelected {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                onboardingViewModel.removeGoal(goalType)
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(Theme.Colors.textTertiary)
                                .padding(.top, 2)
                        }
                        .accessibilityLabel("Remove \(goalType.title)")
                        .accessibilityIdentifier(goalType.removeAccessibilityIdentifier)
                    } else {
                        Image(systemName: "circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(Theme.Colors.borderMedium)
                            .padding(.top, 2)
                    }
                }
                .padding(Theme.Spacing.lg)

                if isSelected {
                    expandedFields(for: goalType)
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.bottom, Theme.Spacing.lg)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous)
                .stroke(isSelected ? Theme.Colors.readyHigh : Theme.Colors.borderLight, lineWidth: isSelected ? 1.5 : 1)
        )
        .accessibilityIdentifier(goalType.accessibilityIdentifier)
    }

    @ViewBuilder
    private func expandedFields(for goalType: CoachingProfileOnboardingViewModel.GoalType) -> some View {
        switch goalType {
        case .race:
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                TextField("Event name", text: $onboardingViewModel.raceEvent)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.inputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous))
                    .accessibilityIdentifier("goal_race_event")

                TextField("Date (YYYY-MM-DD)", text: $onboardingViewModel.raceDate)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.inputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous))
                    .accessibilityIdentifier("goal_race_date")
            }
        case .strength:
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                ForEach(CoachingProfileOnboardingViewModel.StrengthSubtype.allCases) { subtype in
                    Button {
                        onboardingViewModel.selectStrengthSubtype(subtype)
                    } label: {
                        HStack {
                            Text(subtype.title)
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.Colors.textPrimary)
                            Spacer()
                            Image(systemName: onboardingViewModel.strengthSubtype == subtype ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(onboardingViewModel.strengthSubtype == subtype ? Theme.Colors.readyHigh : Theme.Colors.borderMedium)
                        }
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(subtype.accessibilityIdentifier)
                }
            }
        case .health:
            Text("Medical guidance is personal. Consult your doctor before changing training around a diagnosis, medication, pain, or symptoms.")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
                .lineSpacing(3)
                .accessibilityIdentifier("goal_health_disclaimer")
        case .mobility, .none:
            EmptyView()
        }
    }

    private var daysPerWeekCard: some View {
        AFCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Days Per Week")
                    .afH3()

                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(1...7, id: \.self) { day in
                        Button {
                            onboardingViewModel.daysPerWeek = day
                        } label: {
                            Text("\(day)")
                                .font(Theme.Typography.bodyBold)
                                .foregroundColor(onboardingViewModel.daysPerWeek == day ? Theme.Colors.primaryForeground : Theme.Colors.textPrimary)
                                .frame(width: 40, height: 40)
                                .background(onboardingViewModel.daysPerWeek == day ? Theme.Colors.primary : Theme.Colors.accentBackground)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.sm))
                        }
                        .accessibilityIdentifier("coaching_days_\(day)")
                    }
                }
            }
        }
    }

    private var equipmentLink: some View {
        NavigationLink {
            EquipmentProfileView()
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "dumbbell.fill")
                    .foregroundColor(Theme.Colors.readyHigh)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Equipment")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("Tell coach what you can train with before generating.")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            .padding(Theme.Spacing.lg)
            .background(Theme.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .stroke(Theme.Colors.borderLight, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
        }
        .accessibilityIdentifier("coaching_onboarding_equipment")
    }

    private var continueButton: some View {
        Button {
            Task {
                let didSave = await onboardingViewModel.save()
                guard didSave else { return }
                viewModel.completeOnboarding(
                    experience: onboardingViewModel.experience,
                    goal: onboardingViewModel.legacyTrainingGoal,
                    daysPerWeek: onboardingViewModel.daysPerWeek
                )
            }
        } label: {
            HStack {
                if onboardingViewModel.isSaving {
                    ProgressView()
                        .tint(Theme.Colors.primaryForeground)
                } else {
                    Image(systemName: "sparkles")
                }
                Text(onboardingViewModel.isSaving ? "Saving…" : "Continue")
            }
            .font(Theme.Typography.bodyBold)
            .foregroundColor(Theme.Colors.primaryForeground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
            .background(onboardingViewModel.canContinue ? Theme.Colors.primary : Theme.Colors.borderMedium)
            .clipShape(Capsule())
        }
        .disabled(!onboardingViewModel.canContinue)
        .accessibilityIdentifier("coaching_onboarding_continue")
    }
}

#Preview {
    CoachingProfileOnboardingView(viewModel: SuggestWorkoutViewModel())
        .background(Theme.Colors.background)
}
