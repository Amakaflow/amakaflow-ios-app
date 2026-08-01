//
//  EditorV2View.swift
//  AmakaFlow
//
//  AMA-2307 — calm Hevy-pattern editor for .edit / .importReview / .new (not .backfill).
//

import SwiftUI

struct EditorV2View: View {
    let mode: DDEditorMode
    var workout: Workout?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var saveModel: WorkoutEditorViewModel
    @StateObject private var matchController: WorkoutTypeMatchController

    @State private var session: EditorV2Session
    @State private var isReorderMode = false
    @State private var toastMessage: String?
    @State private var menuExerciseID: String?
    @State private var editExerciseID: String?
    @State private var configGroupKey: String?
    @State private var pairSourceID: String?
    @State private var addSheetOpen = false
    @State private var replaceExerciseID: String?
    @State private var isMatchSheetPresented = false
    @FocusState private var isTitleFocused: Bool
    /// AMA-2336 — `workout_preferences` cache; fetched on the first quick-add.
    @State private var enrichmentPrefs: WorkoutPreferences?

    init(
        mode: DDEditorMode,
        workout: Workout? = nil,
        preset: WorkoutTypeItem? = nil
    ) {
        self.mode = mode
        self.workout = workout
        let presetSeed = preset.map(WorkoutTypePresetEditorSeed.init)
        let initialSession = presetSeed.map { EditorV2Session(title: $0.title) }
            ?? EditorV2Session.from(mode: mode, workout: workout)
        _session = State(initialValue: initialSession)
        _matchController = StateObject(
            wrappedValue: WorkoutTypeMatchController(
                apiService: AppDependencies.current.apiService,
                state: presetSeed?.matchState
                    ?? CanonicalMatchState(
                        canonicalId: workout?.canonicalId,
                        source: workout?.canonicalSource
                    )
            )
        )
        if let workout {
            _saveModel = StateObject(wrappedValue: WorkoutEditorViewModel(workout: workout))
        } else {
            _saveModel = StateObject(wrappedValue: WorkoutEditorViewModel())
        }
    }

    private var isNew: Bool { mode == .new }
    private var swapCount: Int {
        session.exercises.filter { $0.swapMessage != nil }.count
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            DailyDriver.screenBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView {
                    EditorV2Content.main(
                        session: session,
                        isReorderMode: isReorderMode,
                        actions: EditorV2ContentActions(
                            onConfigGroup: { configGroupKey = $0 },
                            onOpen: { editExerciseID = $0 },
                            onMenu: { menuExerciseID = $0 },
                            onReorder: { session.reorder(fromOffsets: $0, toOffset: $1) },
                            onExitReorder: {
                                isReorderMode = false
                                showToast("Tap Save workout to keep changes")
                            },
                            onAdd: {
                                replaceExerciseID = nil
                                addSheetOpen = true
                            },
                            onStartFormat: { type in
                                _ = session.startFormat(type)
                                showToast("\(type.label) — add the moves, timing is set")
                            },
                            onAddWarmup: { quickAddSoftSection(.sessionWarmup) },
                            onAddCooldown: { quickAddSoftSection(.cooldown) }
                        )
                    )
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 120)
                }
                .scrollContentBackground(.hidden)
            }
            if !isReorderMode, !session.exercises.isEmpty {
                DDEditorSaveBar(
                    title: "Save workout",
                    isSaving: saveModel.isSaving,
                    action: saveTapped
                )
                .accessibilityIdentifier("save_workout_button")
            }
        }
        .preferredColorScheme(.dark)
        .overlay(alignment: .top) { accessibilityMarkers }
        .overlay(alignment: .bottom) { toastOverlay }
        .onChange(of: saveModel.didSave) { _, saved in
            if saved { dismiss() }
        }
        .onChange(of: saveModel.errorMessage) { _, message in
            if let message, !message.isEmpty {
                showToast(message)
            }
        }
        .sheet(item: menuExerciseBinding, content: menuSheet)
        .sheet(item: editExerciseBinding, content: editSheet)
        .sheet(item: configGroupBinding, content: configSheet)
        .sheet(item: pairSourceBinding, content: pairSheet)
        .sheet(isPresented: $addSheetOpen) { addSheet }
        .sheet(isPresented: $isMatchSheetPresented) { workoutTypeMatchSheet }
        .task { await resolveLoadedMatchDisplayName() }
        .task(id: session.title) {
            matchController.noteTitleForSave(session.title)
            do {
                try await Task.sleep(for: .milliseconds(600))
                try Task.checkCancellation()
                await matchTitleIfNeeded()
            } catch {
                // A newer title superseded this advisory match.
            }
        }
        .onChange(of: isTitleFocused) { _, focused in
            guard !focused else { return }
            Task { await matchTitleIfNeeded() }
        }
    }

    private var accessibilityMarkers: some View {
        ZStack {
            Text(" ").font(.system(size: 1)).opacity(0.01)
                .accessibilityIdentifier("workout_editor_screen")
            Text(" ").font(.system(size: 1)).opacity(0.01)
                .accessibilityIdentifier("editor_v2_screen")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(DailyDriver.foregroundMuted)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                if session.exercises.count > 1 {
                    Button {
                        if isReorderMode {
                            isReorderMode = false
                            showToast("Tap Save workout to keep changes")
                        } else {
                            isReorderMode = true
                        }
                    } label: {
                        Text(isReorderMode ? "✓ Done" : "⇅ Reorder")
                            .ddDisplayText(12.5, weight: .bold)
                            .foregroundColor(
                                isReorderMode ? DailyDriver.lime : DailyDriver.foregroundMuted
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("editor_v2_reorder_toggle")
                }
            }

            TextField(isNew ? "Name your workout" : "Workout title", text: $session.title)
                .ddDisplayText(24, weight: .heavy)
                .foregroundColor(DailyDriver.foreground)
                .padding(.top, 10)
                .focused($isTitleFocused)
                .accessibilityIdentifier("workout_name_field")

            if let displayName = matchController.chipDisplayName {
                WorkoutTypeMatchChip(displayName: displayName) {
                    isMatchSheetPresented = true
                }
                .padding(.top, 8)
            }

            Text(subtitle)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(swapCount > 0 ? DailyDriver.amber : DailyDriver.foregroundDim)
                .padding(.top, 5)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }

    private var subtitle: String {
        if isReorderMode {
            return "DRAG ROWS TO REORDER · DONE THEN SAVE WORKOUT"
        }
        if swapCount > 0 {
            return "⚠ \(swapCount) SWAP SUGGESTIONS"
        }
        if session.exercises.isEmpty {
            return "JUST ADD EXERCISES — STRUCTURE COMES LATER"
        }
        return "TAP AN EXERCISE TO EDIT IT · ⋯ FOR EVERYTHING ELSE"
    }

    /// Quick-add from prefs. An explicit tap re-opts in, so a previous delete
    /// (tombstone) is cleared first — presence by type still blocks duplicates.
    private func quickAddSoftSection(_ kind: EnrichmentKind) {
        Task {
            let prefs = await loadEnrichmentPrefs()
            let added: Bool
            switch kind {
            case .cooldown:
                added = session.quickAddCooldown(from: prefs, clearingTombstone: true)
            case .sessionWarmup:
                added = session.quickAddSessionWarmup(from: prefs, clearingTombstone: true)
            case .betweenSetRest, .exerciseWarmupSets:
                assertionFailure("quickAddSoftSection called with unsupported kind \(kind)")
                return
            }
            guard added else {
                showToast(
                    kind == .cooldown
                        ? "No cool-down defaults yet — set them in Settings › Garmin"
                        : "No warm-up defaults yet — set them in Settings › Garmin"
                )
                return
            }
            showToast(kind == .cooldown ? "Cool-down added ✓" : "Warm-up added ✓")
        }
    }

    private func addWarmupSets(to exerciseID: String) {
        Task {
            let prefs = await loadEnrichmentPrefs()
            let added = session.addDefaultWarmupSets(
                to: exerciseID,
                rows: prefs.defaultWarmupSetRows,
                clearingTombstone: true
            )
            showToast(
                added
                    ? "Warm-up sets added ✓"
                    : "No warm-up set defaults yet — set them in Settings › Garmin"
            )
        }
    }

    /// Prefs are a default source, never a gate: an unavailable mapper falls back
    /// to the shipped defaults so the quick-add still works offline.
    private func loadEnrichmentPrefs() async -> WorkoutPreferences {
        if let enrichmentPrefs { return enrichmentPrefs }
        let loaded = (try? await AppDependencies.current.apiService.fetchWorkoutPreferences())
            ?? .defaults
        enrichmentPrefs = loaded
        return loaded
    }

    private func saveTapped() {
        let trimmedTitle = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        saveModel.name = trimmedTitle
        saveModel.intervals = session.toSaveIntervals()
        session.mintMissingExerciseIDs()
        saveModel.saveBlocks = session.toSocialImportBlocks()
        // nil = leave server tombstones alone when this session never touched them.
        saveModel.saveEnrichmentTombstones = session.enrichmentTombstonesDirty
            ? session.enrichmentTombstones
            : nil
        Task {
            matchController.noteTitleForSave(trimmedTitle)
            let canonicalValues = await matchController.onSave(online: true)
            saveModel.canonicalId = canonicalValues.canonicalId
            saveModel.canonicalSource = canonicalValues.source
            await saveModel.save()
        }
    }

    private func resolveLoadedMatchDisplayName() async {
        guard workout?.canonicalId != nil else { return }
        guard let catalog = try? await AppDependencies.current.apiService.fetchWorkoutTypes(
            aiPresetOnly: false
        ) else {
            return
        }
        matchController.resolveLoadedDisplayName(from: catalog)
    }

    private func matchTitleIfNeeded() async {
        // Existing IDs are resolved against the catalog on load. A retired/unknown
        // ID stays hidden until the user actually changes the title.
        if workout?.canonicalId != nil, session.title == workout?.name {
            return
        }
        await matchController.onTitleIdle(title: session.title)
    }
}
