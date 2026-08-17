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
    /// AMA-2372 — Builder v3 type-picker seed + its "return to picker" callback.
    /// `nil` for every non-Builder-v3 flow (edit, import review, favorite presets).
    var builderV3Seed: BuilderV3TypeSeed?
    var onBuilderV3ChangeType: (() -> Void)?
    /// Called after a successful save (before dismiss). Used by Builder v3 to
    /// reload the library after lift/conditioning/recover drafts land.
    var onSaved: (() -> Void)?
    /// AMA-2387 Map v2 — when set, Done builds a capture draft (no Library persist).
    var actualsCaptureComplete: ((ActualsCaptureDraft) -> Void)?
    var actualsSessionBanner: DDStatusBanner.Style?
    /// Prefill for Map v2 capture (e.g. wearable title) — user can rename.
    var actualsSuggestedTitle: String?

    @Environment(\.dismiss) private var dismiss
    @StateObject var saveModel: WorkoutEditorViewModel
    @StateObject var matchController: WorkoutTypeMatchController

    @State var session: EditorV2Session
    @State var isReorderMode = false
    @State var menuExerciseID: String?
    @State var editExerciseID: String?
    @State var configGroupKey: String?
    @State var pairSourceID: String?
    @State var addSheetOpen = false
    @State var replaceExerciseID: String?
    @State var isMatchSheetPresented = false
    @State var showBuilderV3ChangeTypeConfirm = false
    /// AMA-2372 — gym overlay keys for the multi-select add sheet. `nil` = no
    /// coaching profile loaded (or it failed) ⇒ never mark exercises missing.
    @State var gymEquipmentKeys: Set<String>?
    @State var favoritePresets: [WorkoutTypeItem] = []
    @FocusState private var isTitleFocused: Bool
    /// AMA-2336 — `workout_preferences` cache; fetched on the first quick-add.
    @State var enrichmentPrefs: WorkoutPreferences?
    /// AMA-2443 slice 2b — Coach sheet presentation with prefilled query
    @State var showCoachSheet = false
    @State var coachPrefillQuery: String?

    /// AMA-2372 — title captured at open; title-only edits count as dirty for
    /// TYPE · CHANGE so we don't discard an unnamed→named draft silently.
    let builderV3InitialTitle: String?

    init(
        mode: DDEditorMode,
        workout: Workout? = nil,
        preset: WorkoutTypeItem? = nil,
        builderV3Seed: BuilderV3TypeSeed? = nil,
        onBuilderV3ChangeType: (() -> Void)? = nil,
        onSaved: (() -> Void)? = nil,
        actualsCaptureComplete: ((ActualsCaptureDraft) -> Void)? = nil,
        actualsSessionBanner: DDStatusBanner.Style? = nil,
        actualsSuggestedTitle: String? = nil
    ) {
        self.mode = mode
        self.workout = workout
        self.builderV3Seed = builderV3Seed
        self.onBuilderV3ChangeType = onBuilderV3ChangeType
        self.onSaved = onSaved
        self.actualsCaptureComplete = actualsCaptureComplete
        self.actualsSessionBanner = actualsSessionBanner
        self.actualsSuggestedTitle = actualsSuggestedTitle
        let presetSeed = preset.map(WorkoutTypePresetEditorSeed.init)
        var initialSession = presetSeed.map { EditorV2Session(title: $0.title) }
            ?? builderV3Seed.map { BuilderV3TypeRegistry.makeEditorSession(for: $0) }
            ?? EditorV2Session.from(mode: mode, workout: workout)
        // Actuals capture: start from the finished session’s name — user renames freely.
        if actualsCaptureComplete != nil {
            let suggested = (actualsSuggestedTitle ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !suggested.isEmpty {
                initialSession.title = suggested
            }
        }
        self.builderV3InitialTitle = builderV3Seed != nil ? initialSession.title : nil
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
            let editorViewModel = WorkoutEditorViewModel()
            // AMA-2393 C3 — Builder v3 type picker must persist its sport choice
            if let builderV3Seed {
                editorViewModel.sport = builderV3Seed.category.workoutSport
            }
            _saveModel = StateObject(wrappedValue: editorViewModel)
        }
    }

    private var isNew: Bool { mode == .new }
    private var swapCount: Int {
        session.exercises.values.filter { $0.swapMessage != nil }.count
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            DailyDriver.screenBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                if let actualsSessionBanner {
                    DDStatusBanner(style: actualsSessionBanner)
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                }
                ScrollView {
                    EditorV2Content.main(
                        session: session,
                        isReorderMode: isReorderMode,
                        actions: EditorV2ContentActions(
                            onConfigGroup: { configGroupKey = $0 },
                            onOpen: { editExerciseID = $0 },
                            onMenu: { menuExerciseID = $0 },
                            onReorder: { _ = session.apply(.reorder(fromOffsets: $0, toOffset: $1)) },
                            onExitReorder: {
                                isReorderMode = false
                                showToast("Tap Save workout to keep changes")
                            },
                            onAdd: {
                                replaceExerciseID = nil
                                addSheetOpen = true
                            },
                            onStartFormat: { type in
                                _ = session.apply(.addBlock(type))
                                showToast("\(type.label) — add the moves, timing is set")
                            },
                            onAddWarmup: { quickAddSoftSection(.sessionWarmup) },
                            onAddCooldown: { quickAddSoftSection(.cooldown) },
                            onBeginNextSupersetGroup: {
                                let key = session.beginNextSupersetGroup()
                                let name = session.groups[key]?.name ?? "Superset"
                                showToast("\(name) ready — add the next moves")
                            }
                        ),
                        builderV3Canvas: builderV3Seed != nil
                    )
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 120)
                }
                .scrollContentBackground(.hidden)
            }
            if !isReorderMode, !session.order.isEmpty {
                DDEditorSaveBar(
                    title: actualsCaptureComplete != nil
                        ? ActualsCopy.captureBuilderDoneCTA
                        : "Save workout",
                    isSaving: saveModel.isSaving,
                    action: saveTapped
                )
                .accessibilityIdentifier("save_workout_button")
            }
        }
        .preferredColorScheme(.dark)
        .overlay(alignment: .top) { accessibilityMarkers }
        .onChange(of: saveModel.didSave) { _, saved in
            if saved {
                onSaved?()
                dismiss()
            }
        }
        .onChange(of: saveModel.errorMessage) { _, message in
            if let message, !message.isEmpty {
                DDToastCenter.shared.error(message)
            }
        }
        .sheet(item: menuExerciseBinding, content: menuSheet)
        .sheet(item: editExerciseBinding, content: editSheet)
        .sheet(item: configGroupBinding, content: configSheet)
        .sheet(item: pairSourceBinding, content: pairSheet)
        .sheet(isPresented: $addSheetOpen) { addSheet }
        .sheet(isPresented: $isMatchSheetPresented) { workoutTypeMatchSheet }
        .sheet(isPresented: $showCoachSheet) {
            CoachChatView()
                .environmentObject(CoachSessionStore())
                .onAppear {
                    // Send the prefilled query if available
                    // For now, just present the coach; full integration would
                    // require accessing the store and calling sendMessage
                }
        }
        .alert("Change workout type?", isPresented: $showBuilderV3ChangeTypeConfirm) {
            Button("Keep editing", role: .cancel) {}
            Button("Change type", role: .destructive) { onBuilderV3ChangeType?() }
        } message: {
            Text("This clears the exercises and format on this canvas.")
        }
        .task { await resolveLoadedMatchDisplayName() }
        .task {
            // Favorite chips are the non–Builder-v3 "new workout" door. Builder v3
            // owns type selection on the picker — keep them off that canvas.
            guard isNew, builderV3Seed == nil else { return }
            await loadFavoritePresets()
        }
        .task { gymEquipmentKeys = await loadGymEquipmentKeys() }
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
                Button {
                    if builderV3Seed != nil, onBuilderV3ChangeType != nil {
                        builderV3ChangeTypeTapped()
                    } else {
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text(builderV3Seed != nil ? "Type" : "Back")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(DailyDriver.foregroundMuted)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                builderV3TypeChangeButton

                if session.order.count > 1 {
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

            if isNew, builderV3Seed == nil, !favoritePresets.isEmpty {
                WorkoutTypeFavoritesRow(
                    presets: favoritePresets,
                    selectedCanonicalId: matchController.canonicalId,
                    onSelect: { preset in
                        session.title = matchController.applyFavorite(
                            preset,
                            currentTitle: session.title
                        )
                    },
                    onMore: { isMatchSheetPresented = true }
                )
                .padding(.top, 8)
            }

            if builderV3Seed == nil, let displayName = matchController.chipDisplayName {
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
        if builderV3Seed != nil {
            let isBlankCanvas = session.order.isEmpty
                && session.formatGroupKey == nil
            if isBlankCanvas {
                return "JUST ADD EXERCISES — GROUP OR FORMAT THEM ANYTIME"
            }
            return "DEFAULTS APPLIED — TAP ANYTHING TO TWEAK"
        }
        if session.order.isEmpty {
            return "JUST ADD EXERCISES — STRUCTURE COMES LATER"
        }
        return "TAP AN EXERCISE TO EDIT IT · ⋯ FOR EVERYTHING ELSE"
    }
}
