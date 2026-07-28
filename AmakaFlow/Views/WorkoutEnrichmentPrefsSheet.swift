//
//  WorkoutEnrichmentPrefsSheet.swift
//  AmakaFlow
//
//  AMA-2336 — Settings editor for `workout_preferences` (spec §5).
//
//  This sheet edits declared defaults and nothing else: it never calls
//  `/workout/enrich`. Existing workouts change only when the editor quick-adds
//  or the pre-push sheet applies them.
//

import SwiftUI

struct WorkoutEnrichmentPrefsSheet: View {
    var onSaved: ((WorkoutPreferences) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var prefs: WorkoutPreferences = .defaults
    @State private var excludeKeysText: String = ""
    @State private var restSecText: String = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var loadFailed = false
    @State private var errorMessage: String?

    private let apiService: APIServiceProviding

    init(
        apiService: APIServiceProviding? = nil,
        onSaved: ((WorkoutPreferences) -> Void)? = nil
    ) {
        self.apiService = apiService ?? AppDependencies.current.apiService
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    header

                    if isLoading {
                        loadingRow
                    } else {
                        if loadFailed {
                            noticeRow(
                                "Couldn’t load your saved defaults — showing the standard ones. Saving will overwrite."
                            )
                        }
                        sessionWarmupSection
                        cooldownSection
                        betweenSetRestSection
                        warmupSetsSection

                        if let errorMessage {
                            noticeRow(errorMessage)
                        }

                        Button {
                            Task { await save() }
                        } label: {
                            Text(isSaving ? "Saving…" : "Save defaults")
                        }
                        .buttonStyle(AFPrimaryButtonStyle(size: .lg))
                        .disabled(isSaving)
                        .accessibilityIdentifier("af_enrichment_prefs_save")
                    }
                }
                .padding(Theme.Spacing.lg)
            }
            .background(DailyDriver.screenBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("af_enrichment_prefs_sheet")
        .task { await load() }
    }
}

extension WorkoutEnrichmentPrefsSheet {
    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Workout enrichment defaults")
                .afH2()
                .accessibilityAddTraits(.isHeader)
            Text("What we offer to add when a workout is missing it. Saved workouts don’t change until you add it in the editor or accept the offer before a Garmin push.")
                .afMuted()
        }
    }

    private var loadingRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ProgressView()
            Text("Loading your defaults…")
                .afMuted()
        }
    }

    private func noticeRow(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.caption)
            .foregroundColor(DailyDriver.foregroundMuted)
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous)
                    .fill(DailyDriver.card)
            )
    }

    // MARK: - Sections

    private var sessionWarmupSection: some View {
        section(
            title: "Session warm-up",
            subtitle: "A short warm-up section at the top of the workout."
        ) {
            Toggle("Offer a session warm-up", isOn: $prefs.sessionWarmup.enabled)
                .tint(DailyDriver.lime)
                .accessibilityIdentifier("af_enrichment_prefs_warmup_toggle")

            if prefs.sessionWarmup.enabled {
                activityEditor(
                    activities: $prefs.sessionWarmup.activities,
                    identifierPrefix: "warmup"
                )
            }
        }
    }

    private var cooldownSection: some View {
        section(
            title: "Cool-down",
            subtitle: "Off by default. Turn on to be offered one at the end."
        ) {
            Toggle("Offer a cool-down", isOn: $prefs.cooldown.enabled)
                .tint(DailyDriver.lime)
                .accessibilityIdentifier("af_enrichment_prefs_cooldown_toggle")

            if prefs.cooldown.enabled {
                activityEditor(
                    activities: $prefs.cooldown.activities,
                    identifierPrefix: "cooldown"
                )
            }
        }
    }

    private var betweenSetRestSection: some View {
        section(
            title: "Between-set rest",
            subtitle: "Used when a workout doesn’t say how long to rest."
        ) {
            Toggle("Offer between-set rest", isOn: $prefs.betweenSetRest.enabled)
                .tint(DailyDriver.lime)
                .accessibilityIdentifier("af_enrichment_prefs_rest_toggle")

            if prefs.betweenSetRest.enabled {
                Toggle("Rest until I press Lap", isOn: restOpenBinding)
                    .tint(DailyDriver.lime)
                    .accessibilityIdentifier("af_enrichment_prefs_rest_open_toggle")

                if !prefs.betweenSetRest.restOpen {
                    HStack(spacing: Theme.Spacing.md) {
                        Text("Rest seconds")
                            .font(Theme.Typography.body)
                            .foregroundColor(DailyDriver.foreground)
                        Spacer(minLength: 0)
                        TextField("60", text: $restSecText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 72)
                            .accessibilityIdentifier("af_enrichment_prefs_rest_sec")
                    }
                    .padding(Theme.Spacing.md)
                    .background(cardBackground)
                }
            }
        }
    }

    private var warmupSetsSection: some View {
        section(
            title: "Exercise warm-up sets",
            subtitle: "Lighter sets before the working sets. Your set count stays as written."
        ) {
            Toggle("Offer warm-up sets", isOn: $prefs.exerciseWarmupSets.enabled)
                .tint(DailyDriver.lime)
                .accessibilityIdentifier("af_enrichment_prefs_warmup_sets_toggle")

            if prefs.exerciseWarmupSets.enabled {
                ForEach(prefs.exerciseWarmupSets.defaultSets) { row in
                    HStack(spacing: Theme.Spacing.md) {
                        Text("Set \(warmupSetNumber(for: row.id))")
                            .font(Theme.Typography.body)
                            .foregroundColor(DailyDriver.foreground)
                        Spacer(minLength: 0)
                        Text("\(row.reps) reps")
                            .font(Theme.Typography.body)
                            .foregroundColor(DailyDriver.foregroundMuted)
                        Stepper("") {
                            adjustWarmupSetReps(id: row.id, by: 1)
                        } onDecrement: {
                            adjustWarmupSetReps(id: row.id, by: -1)
                        }
                        .labelsHidden()
                        Button {
                            prefs.exerciseWarmupSets.defaultSets.removeAll { $0.id == row.id }
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundColor(DailyDriver.foregroundMuted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove warm-up set \(warmupSetNumber(for: row.id))")
                    }
                    .padding(Theme.Spacing.md)
                    .background(cardBackground)
                }

                Button {
                    prefs.exerciseWarmupSets.defaultSets.append(WarmupSetDefault(reps: 8))
                } label: {
                    Label("Add warm-up set", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .foregroundColor(DailyDriver.lime)
                .accessibilityIdentifier("af_enrichment_prefs_add_warmup_set")

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Skip these exercises")
                        .font(Theme.Typography.caption)
                        .foregroundColor(DailyDriver.foregroundMuted)
                    TextField("e.g. plank, farmer carry", text: $excludeKeysText, axis: .vertical)
                        .font(Theme.Typography.body)
                        .foregroundColor(DailyDriver.foreground)
                        .padding(Theme.Spacing.md)
                        .background(cardBackground)
                        .accessibilityIdentifier("af_enrichment_prefs_exclude_keys")
                    Text("One name per line or comma-separated. Matching happens on the server.")
                        .font(Theme.Typography.caption)
                        .foregroundColor(DailyDriver.foregroundMuted)
                }
            }
        }
    }

    // MARK: - Activity editor

    private func activityEditor(
        activities: Binding<[EnrichmentActivityPref]>,
        identifierPrefix: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if activities.wrappedValue.isEmpty {
                Text("No activities yet — add one so we have something to offer.")
                    .font(Theme.Typography.caption)
                    .foregroundColor(DailyDriver.foregroundMuted)
            }

            ForEach(activities.wrappedValue) { activity in
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack(spacing: Theme.Spacing.md) {
                        TextField(
                            "Activity",
                            text: activityNameBinding(activities: activities, id: activity.id)
                        )
                            .font(Theme.Typography.body)
                            .foregroundColor(DailyDriver.foreground)
                            .accessibilityIdentifier(
                                "af_enrichment_prefs_\(identifierPrefix)_name_\(activity.id.uuidString)"
                            )
                        Button {
                            activities.wrappedValue.removeAll { $0.id == activity.id }
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundColor(DailyDriver.foregroundMuted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove activity \(activity.name)")
                    }

                    Toggle(
                        "Until I press Lap",
                        isOn: openDurationBinding(activities: activities, id: activity.id)
                    )
                    .tint(DailyDriver.lime)
                    .font(Theme.Typography.caption)
                    .accessibilityIdentifier(
                        "af_enrichment_prefs_\(identifierPrefix)_open_\(activity.id.uuidString)"
                    )

                    if let matched = activities.wrappedValue.first { $0.id == activity.id },
                       let seconds = matched.durationSec {
                        Stepper(
                            "\(seconds)s",
                            value: durationBinding(activities: activities, id: activity.id),
                            in: 15...1800,
                            step: 15
                        )
                        .font(Theme.Typography.caption)
                        .foregroundColor(DailyDriver.foregroundMuted)
                    }
                }
                .padding(Theme.Spacing.md)
                .background(cardBackground)
            }

            Button {
                activities.wrappedValue.append(EnrichmentActivityPref(name: "", durationSec: 300))
            } label: {
                Label("Add activity", systemImage: "plus")
            }
            .buttonStyle(.plain)
            .foregroundColor(DailyDriver.lime)
            .accessibilityIdentifier("af_enrichment_prefs_\(identifierPrefix)_add")
        }
    }

    // MARK: - Bindings

    private var restOpenBinding: Binding<Bool> {
        Binding(
            get: { prefs.betweenSetRest.restOpen },
            set: { isOpen in
                // Contradictory intent is unrepresentable: open rest clears seconds.
                try? prefs.betweenSetRest.setRest(
                    restSec: isOpen ? nil : (Int(restSecText) ?? 60),
                    restOpen: isOpen
                )
                if !isOpen, restSecText.isEmpty {
                    restSecText = "60"
                }
            }
        )
    }

    private func activityNameBinding(
        activities: Binding<[EnrichmentActivityPref]>,
        id: UUID
    ) -> Binding<String> {
        Binding(
            get: { activities.wrappedValue.first { $0.id == id }?.name ?? "" },
            set: { name in
                let index = activities.wrappedValue.firstIndex { $0.id == id }
                guard let index else { return }
                activities.wrappedValue[index].name = name
            }
        )
    }

    private func openDurationBinding(
        activities: Binding<[EnrichmentActivityPref]>,
        id: UUID
    ) -> Binding<Bool> {
        Binding(
            get: { activities.wrappedValue.first { $0.id == id }?.durationSec == nil },
            set: { isOpen in
                let index = activities.wrappedValue.firstIndex { $0.id == id }
                guard let index else { return }
                activities.wrappedValue[index].durationSec = isOpen ? nil : 300
            }
        )
    }

    private func durationBinding(
        activities: Binding<[EnrichmentActivityPref]>,
        id: UUID
    ) -> Binding<Int> {
        Binding(
            get: { activities.wrappedValue.first { $0.id == id }?.durationSec ?? 300 },
            set: { seconds in
                let index = activities.wrappedValue.firstIndex { $0.id == id }
                guard let index else { return }
                activities.wrappedValue[index].durationSec = seconds
            }
        )
    }

    private func warmupSetNumber(for id: UUID) -> Int {
        (prefs.exerciseWarmupSets.defaultSets.firstIndex { $0.id == id } ?? 0) + 1
    }

    private func adjustWarmupSetReps(id: UUID, by delta: Int) {
        let index = prefs.exerciseWarmupSets.defaultSets.firstIndex { $0.id == id }
        guard let index else { return }
        let reps = prefs.exerciseWarmupSets.defaultSets[index].reps + delta
        prefs.exerciseWarmupSets.defaultSets[index].reps = min(30, max(1, reps))
    }

    // MARK: - Load / save

    private func load() async {
        guard isLoading else { return }
        do {
            let loaded = try await apiService.fetchWorkoutPreferences()
            prefs = loaded
            loadFailed = false
        } catch {
            prefs = .defaults
            loadFailed = true
        }
        restSecText = prefs.betweenSetRest.restSec.map(String.init) ?? "60"
        excludeKeysText = prefs.exerciseWarmupSets.excludeExerciseKeys.joined(separator: "\n")
        isLoading = false
    }

    private func save() async {
        isSaving = true
        errorMessage = nil

        var payload = prefs
        payload.exerciseWarmupSets.excludeExerciseKeys = Self.parseExcludeKeys(excludeKeysText)
        if !payload.betweenSetRest.restOpen {
            let seconds = Int(restSecText.trimmingCharacters(in: .whitespaces))
            guard let seconds, seconds > 0 else {
                errorMessage = "Rest seconds needs a number above 0 — or switch on “Rest until I press Lap”."
                isSaving = false
                return
            }
            do {
                try payload.betweenSetRest.setRest(restSec: seconds, restOpen: false)
            } catch {
                errorMessage = "Rest can be timed or until Lap, not both."
                isSaving = false
                return
            }
        }

        do {
            let saved = try await apiService.updateWorkoutPreferences(payload)
            prefs = saved
            excludeKeysText = saved.exerciseWarmupSets.excludeExerciseKeys.joined(separator: "\n")
            onSaved?(saved)
            isSaving = false
            dismiss()
        } catch {
            errorMessage = "Couldn’t save your defaults — check your connection and try again."
            isSaving = false
        }
    }

    /// Normalized for display parity only — exclusion matching is server-side.
    static func parseExcludeKeys(_ text: String) -> [String] {
        text
            .split { $0 == "\n" || $0 == "," }
            .map { ExerciseKeyNormalizer.normalize(String($0)) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Layout helpers

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous)
            .fill(DailyDriver.card)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous)
                    .stroke(DailyDriver.border, lineWidth: 1)
            )
    }

    private func section<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.bodyBold)
                .foregroundColor(DailyDriver.foreground)
            Text(subtitle)
                .font(Theme.Typography.caption)
                .foregroundColor(DailyDriver.foregroundMuted)
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                content()
            }
        }
    }
}

#if DEBUG
#Preview("Enrichment defaults") {
    WorkoutEnrichmentPrefsSheet()
}
#endif
