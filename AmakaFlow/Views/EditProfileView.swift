//
//  EditProfileView.swift
//  AmakaFlow
//
//  AMA-1899: hi-fi Edit Profile refresh backed by the coaching-profile
//  GET/PUT contract where fields exist, while preserving existing local
//  display-name and unit preferences.
//

import Combine
import Foundation
import SwiftUI

// MARK: - Distance Unit

enum DistanceUnit: String, Codable, CaseIterable {
    case mi
    case km

    var display: String {
        switch self {
        case .mi: return "mi"
        case .km: return "km"
        }
    }
}

@MainActor
final class EditProfileViewModel: ObservableObject {
    typealias CoachingProfile = Components.Schemas.CoachingProfile
    typealias CoachingProfileUpsert = Components.Schemas.CoachingProfileUpsert
    typealias GoalEntry = Components.Schemas.GoalEntry

    enum ScreenState: Equatable {
        case loading
        case content
        case empty
        case error(CTAError)
    }

    enum FailedAction: Equatable {
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

        var title: String {
            switch self {
            case .race: return "Race / event"
            case .strength: return "Strength"
            case .health: return "Health"
            case .mobility: return "Mobility"
            case .none: return "No specific goal"
            }
        }

        var icon: String {
            switch self {
            case .race: return "figure.run"
            case .strength: return "dumbbell.fill"
            case .health: return "heart.text.square.fill"
            case .mobility: return "figure.flexibility"
            case .none: return "sparkles"
            }
        }
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
            case .lookGood: return "Look good"
            }
        }
    }

    @Published private(set) var state: ScreenState = .loading
    @Published private(set) var ctaError: CTAError?
    @Published private(set) var isSaving = false
    @Published private(set) var selectedGoalTypes = Set<GoalType>()
    @Published var experience: ExperienceLevel = .intermediate
    @Published var sessionsPerWeek: Int = 3
    @Published var sessionDurationMinutes: Int = 45
    @Published var raceEvent = ""
    @Published var raceDate = ""
    @Published var strengthSubtype: StrengthSubtype = .buildMuscle

    private let apiService: APIServiceProviding
    private var profile: CoachingProfile?
    private var originalSnapshot: Snapshot?
    private(set) var lastFailedAction: FailedAction?

    init(apiService: APIServiceProviding? = nil) {
        self.apiService = apiService ?? AppDependencies.current.apiService
    }

    var canSave: Bool {
        profile != nil && !isSaving && isDirty
    }

    var isDirty: Bool {
        snapshot != originalSnapshot
    }

    var weeklyMinutes: Int {
        sessionsPerWeek * sessionDurationMinutes
    }

    var weeklyHoursLabel: String {
        let hours = Double(weeklyMinutes) / 60.0
        if hours == floor(hours) {
            return "\(Int(hours)) hr / week"
        }
        return String(format: "%.1f hr / week", hours)
    }

    var saveButtonTitle: String {
        isSaving ? "Saving…" : "Save profile"
    }

    var showsInlineSaveRetry: Bool {
        lastFailedAction == .save && !isSaving
    }

    func load() async {
        state = .loading
        ctaError = nil
        lastFailedAction = nil

        do {
            let fetched = try await apiService.getCoachingProfile() ?? Self.emptyProfileDraft()
            apply(profile: fetched)
            state = selectedGoalTypes.isEmpty ? .empty : .content
        } catch {
            let mapped = CTAError.map(error)
            ctaError = mapped
            state = .error(mapped)
            lastFailedAction = .load
        }
    }

    func save() async {
        guard profile != nil, !isSaving else { return }
        isSaving = true
        ctaError = nil
        lastFailedAction = nil

        do {
            // AMA-1997 pattern: load the latest profile immediately before PUT
            // so editing goals/training hours never clobbers equipment or other
            // fields written by adjacent screens.
            let latest = try await apiService.getCoachingProfile() ?? profile ?? Self.emptyProfileDraft()
            profile = latest
            let upsert = CoachingProfileUpsert(
                equipment: latest.equipment,
                experienceLevel: experience.rawValue,
                goals: buildGoals(),
                injuriesLimitations: latest.injuriesLimitations,
                preferredDays: latest.preferredDays,
                primaryGoal: latest.primaryGoal,
                sessionDurationMinutes: sessionDurationMinutes,
                sessionsPerWeek: sessionsPerWeek
            )
            let saved = try await apiService.upsertCoachingProfile(upsert)
            apply(profile: saved)
            state = selectedGoalTypes.isEmpty ? .empty : .content
        } catch {
            let mapped = CTAError.map(error)
            ctaError = mapped
            lastFailedAction = .save
        }

        isSaving = false
    }

    func retryLastAction() async {
        switch lastFailedAction {
        case .load:
            await load()
        case .save:
            await save()
        case .none:
            break
        }
    }

    func dismissError() {
        let currentError = ctaError
        ctaError = nil
        if lastFailedAction == .load, let currentError {
            state = .error(currentError)
        }
    }

    func reportError(reporter: ErrorReporting? = nil) {
        guard let ctaError else { return }
        let reporter = reporter ?? ErrorReporter.shared
        reporter.report(
            action: lastFailedAction == .load ? "edit_profile_load" : "edit_profile_save",
            error: ctaError,
            endpoint: "/v1/coaching/profile",
            userId: PairingService.shared.userProfile?.id
        )
    }

    func isSelected(_ goalType: GoalType) -> Bool {
        selectedGoalTypes.contains(goalType)
    }

    func toggleGoal(_ goalType: GoalType) {
        if selectedGoalTypes.contains(goalType) {
            removeGoal(goalType)
        } else {
            selectGoal(goalType)
        }
        updateStateForCurrentSelection()
    }

    func selectStrengthSubtype(_ subtype: StrengthSubtype) {
        strengthSubtype = subtype
        selectGoal(.strength)
    }

    func setSessionsPerWeek(_ value: Int) {
        sessionsPerWeek = Self.clamp(value, lower: 1, upper: 7)
    }

    func setSessionDurationMinutes(_ value: Int) {
        sessionDurationMinutes = Self.clamp(value, lower: 15, upper: 180)
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

    private var snapshot: Snapshot {
        Snapshot(
            experience: experience.rawValue,
            goals: buildGoals(),
            sessionDurationMinutes: sessionDurationMinutes,
            sessionsPerWeek: sessionsPerWeek
        )
    }

    private static func emptyProfileDraft() -> CoachingProfile {
        CoachingProfile(
            createdAt: "",
            equipment: nil,
            experienceLevel: "intermediate",
            goals: nil,
            primaryGoal: "general_fitness",
            sessionDurationMinutes: 45,
            sessionsPerWeek: 3,
            updatedAt: "",
            userId: ""
        )
    }

    private func apply(profile fetched: CoachingProfile) {
        profile = fetched
        experience = ExperienceLevel(rawValue: fetched.experienceLevel) ?? .intermediate
        sessionsPerWeek = Self.clamp(fetched.sessionsPerWeek, lower: 1, upper: 7)
        sessionDurationMinutes = Self.clamp(fetched.sessionDurationMinutes ?? 45, lower: 15, upper: 180)
        applyGoals(fetched.goals ?? [])
        originalSnapshot = snapshot
        ctaError = nil
        lastFailedAction = nil
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

    private func selectGoal(_ goalType: GoalType) {
        if goalType == .none {
            selectedGoalTypes = [.none]
            raceEvent = ""
            raceDate = ""
            strengthSubtype = .buildMuscle
        } else {
            selectedGoalTypes.remove(.none)
            selectedGoalTypes.insert(goalType)
        }
    }

    private func removeGoal(_ goalType: GoalType) {
        selectedGoalTypes.remove(goalType)
        if goalType == .race {
            raceEvent = ""
            raceDate = ""
        }
        if goalType == .strength {
            strengthSubtype = .buildMuscle
        }
    }

    private func updateStateForCurrentSelection() {
        guard profile != nil else { return }
        if case .error = state { return }
        if case .loading = state { return }
        state = selectedGoalTypes.isEmpty ? .empty : .content
    }

    private func trimmedOptional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func clamp(_ value: Int, lower: Int, upper: Int) -> Int {
        min(max(value, lower), upper)
    }

    private struct Snapshot: Equatable {
        let experience: String
        let goals: [GoalEntry]
        let sessionDurationMinutes: Int
        let sessionsPerWeek: Int
    }
}

// MARK: - Edit Profile View

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(DefaultsKey.userDisplayName.rawValue) private var displayName: String = ""
    @AppStorage(DefaultsKey.userWeightUnit.rawValue) private var weightUnit: WeightUnit = .lbs
    @AppStorage(DefaultsKey.userDistanceUnit.rawValue) private var distanceUnit: DistanceUnit = .mi

    /// Read-only fallback shown as the field's placeholder when the user
    /// hasn't set a local display name. Never written back to displayName
    /// — only the user's explicit edits are persisted.
    let initialNameFallback: String?

    @StateObject private var viewModel: EditProfileViewModel
    @State private var draftName: String = ""
    @State private var hasEditedName: Bool = false
    @State private var didLoad = false

    init(
        initialNameFallback: String? = nil,
        viewModel: EditProfileViewModel? = nil
    ) {
        self.initialNameFallback = initialNameFallback
        _viewModel = StateObject(wrappedValue: viewModel ?? EditProfileViewModel())
    }

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            Group {
                switch viewModel.state {
                case .loading:
                    loadingView
                case .content, .empty:
                    formView(showEmptyBanner: viewModel.state == .empty)
                case .error:
                    loadErrorView
                }
            }
        }
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    Task { await saveAndDismissIfNeeded() }
                }
                .disabled(!canSave)
                .accessibilityIdentifier("edit_profile_save")
            }
        }
        .overlay(alignment: .top) {
            if let error = viewModel.ctaError {
                ErrorToast(
                    actionTitle: viewModel.lastFailedAction == .load ? "Couldn't load profile" : "Couldn't save profile",
                    error: error,
                    onRetry: error.isRetryable ? { Task { await viewModel.retryLastAction() } } : nil,
                    onReport: { viewModel.reportError() },
                    onDismiss: { viewModel.dismissError() }
                )
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)
            }
        }
        .task {
            guard !didLoad else { return }
            didLoad = true
            draftName = displayName
            hasEditedName = false
            await viewModel.load()
        }
    }

    private var canSave: Bool {
        viewModel.canSave || hasEditedName
    }

    private var loadingView: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .tint(Theme.Colors.textPrimary)
            Text("Loading profile")
                .afMuted()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("edit_profile_loading")
    }

    private func formView(showEmptyBanner: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                if showEmptyBanner {
                    emptyBanner
                }
                accountCard
                trainingCard
                goalsCard
                unitsCard
                if viewModel.showsInlineSaveRetry {
                    inlineRetryCard
                }
                saveButton
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.lg)
            .padding(.bottom, 80)
        }
    }

    private var emptyBanner: some View {
        AFCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("No goals saved yet")
                    .font(Theme.Typography.title3)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("Choose the goals and weekly training time your coach should use next.")
                    .afMuted()
            }
        }
        .accessibilityIdentifier("edit_profile_empty")
    }

    private var accountCard: some View {
        AFCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                AFLabel(text: "Account")
                TextField(
                    "Display name",
                    text: $draftName,
                    prompt: Text(initialNameFallback ?? "Your name")
                )
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                        .stroke(Theme.Colors.borderLight, lineWidth: 1)
                )
                .accessibilityIdentifier("edit_profile_name_field")
                .onChange(of: draftName) { _, _ in hasEditedName = true }

                Text("Handle and bio are not in the coaching-profile contract yet, so this screen does not invent them.")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
    }

    private var trainingCard: some View {
        AFCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                AFLabel(text: "Training profile")

                Picker("Experience", selection: $viewModel.experience) {
                    ForEach(ExperienceLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("edit_profile_experience")

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack {
                        Text("Sessions / week")
                            .foregroundColor(Theme.Colors.textPrimary)
                        Spacer()
                        Text("\(viewModel.sessionsPerWeek)")
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    Stepper(
                        "Sessions per week",
                        value: Binding(
                            get: { viewModel.sessionsPerWeek },
                            set: { viewModel.setSessionsPerWeek($0) }
                        ),
                        in: 1...7
                    )
                    .labelsHidden()
                    .accessibilityIdentifier("edit_profile_sessions_per_week")
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack {
                        Text("Minutes / session")
                            .foregroundColor(Theme.Colors.textPrimary)
                        Spacer()
                        Text("\(viewModel.sessionDurationMinutes) min")
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(viewModel.sessionDurationMinutes) },
                            set: { viewModel.setSessionDurationMinutes(Int($0)) }
                        ),
                        in: 15...180,
                        step: 5
                    )
                    .tint(Theme.Colors.primary)
                    .accessibilityIdentifier("edit_profile_session_duration")
                }

                HStack {
                    Image(systemName: "clock.fill")
                    Text(viewModel.weeklyHoursLabel)
                    Spacer()
                }
                .font(Theme.Typography.footnote.weight(.semibold))
                .foregroundColor(Theme.Colors.textSecondary)
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.chipBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
            }
        }
    }

    private var goalsCard: some View {
        AFCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                AFLabel(text: "Goals")
                goalGrid

                if viewModel.isSelected(.race) {
                    raceFields
                }
                if viewModel.isSelected(.strength) {
                    strengthSubtypePicker
                }
            }
        }
    }

    private var goalGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.sm) {
            ForEach(EditProfileViewModel.GoalType.allCases) { goal in
                Button {
                    viewModel.toggleGoal(goal)
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: goal.icon)
                        Text(goal.title)
                            .font(Theme.Typography.footnote.weight(.semibold))
                    }
                    .foregroundColor(viewModel.isSelected(goal) ? Theme.Colors.primaryForeground : Theme.Colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(viewModel.isSelected(goal) ? Theme.Colors.primary : Theme.Colors.chipBackground)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("edit_profile_goal_\(goal.rawValue)")
                .accessibilityAddTraits(viewModel.isSelected(goal) ? .isSelected : [])
            }
        }
    }

    private var raceFields: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            TextField("Event name", text: $viewModel.raceEvent)
                .textInputAutocapitalization(.words)
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                .accessibilityIdentifier("edit_profile_race_event")
            TextField("Date (YYYY-MM-DD)", text: $viewModel.raceDate)
                .keyboardType(.numbersAndPunctuation)
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                .accessibilityIdentifier("edit_profile_race_date")
        }
    }

    private var strengthSubtypePicker: some View {
        Picker("Strength focus", selection: $viewModel.strengthSubtype) {
            ForEach(EditProfileViewModel.StrengthSubtype.allCases) { subtype in
                Text(subtype.title).tag(subtype)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("edit_profile_strength_subtype")
    }

    private var unitsCard: some View {
        AFCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                AFLabel(text: "Units")
                Picker("Weight", selection: $weightUnit) {
                    Text("lbs").tag(WeightUnit.lbs)
                    Text("kg").tag(WeightUnit.kg)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("edit_profile_weight_unit")

                Picker("Distance", selection: $distanceUnit) {
                    Text("mi").tag(DistanceUnit.mi)
                    Text("km").tag(DistanceUnit.km)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("edit_profile_distance_unit")
            }
        }
    }

    private var inlineRetryCard: some View {
        AFCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Save did not complete")
                    .font(Theme.Typography.title3)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("Your edits are still here. Try saving again when the connection is back.")
                    .afMuted()
                Button("Retry save") {
                    Task { await viewModel.retryLastAction() }
                }
                .buttonStyle(AFGhostButtonStyle(size: .sm, isWide: false))
                .accessibilityIdentifier("edit_profile_retry_save")
            }
        }
    }

    private var saveButton: some View {
        Button {
            Task { await saveAndDismissIfNeeded() }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                if viewModel.isSaving {
                    ProgressView().tint(Theme.Colors.primaryForeground)
                }
                Text(viewModel.saveButtonTitle)
            }
        }
        .buttonStyle(AFPrimaryButtonStyle(size: .lg))
        .disabled(!canSave)
        .accessibilityIdentifier("edit_profile_save_bottom")
    }

    private var loadErrorView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            AFCard {
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundColor(Theme.Colors.accentRed)
                    Text("We couldn't load your profile.")
                        .afH2()
                        .multilineTextAlignment(.center)
                    Text("Retry to edit goals, training time, and experience.")
                        .afMuted()
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await viewModel.load() }
                    }
                    .buttonStyle(AFPrimaryButtonStyle(size: .md))
                    .accessibilityIdentifier("edit_profile_retry_load")
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            Spacer()
        }
    }

    private func saveAndDismissIfNeeded() async {
        if hasEditedName {
            displayName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
            hasEditedName = false
        }
        if viewModel.canSave {
            await viewModel.save()
            if viewModel.ctaError == nil {
                dismiss()
            }
        } else {
            dismiss()
        }
    }
}

#Preview("Edit Profile") {
    NavigationStack {
        EditProfileView(initialNameFallback: "Sample User")
    }
    .preferredColorScheme(.dark)
}
