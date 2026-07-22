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

    @State private var session: EditorV2Session
    @State private var isReorderMode = false
    @State private var toastMessage: String?
    @State private var menuExerciseID: String?
    @State private var editExerciseID: String?
    @State private var configGroupKey: String?
    @State private var pairSourceID: String?
    @State private var addSheetOpen = false
    @State private var replaceExerciseID: String?

    init(mode: DDEditorMode, workout: Workout? = nil) {
        self.mode = mode
        self.workout = workout
        _session = State(initialValue: EditorV2Session.from(mode: mode, workout: workout))
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
                            onExitReorder: { isReorderMode = false },
                            onAdd: {
                                replaceExerciseID = nil
                                addSheetOpen = true
                            },
                            onStartFormat: { type in
                                _ = session.startFormat(type)
                                showToast("\(type.label) — add the moves, timing is set")
                            }
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
                        isReorderMode.toggle()
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
                .accessibilityIdentifier("workout_name_field")

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
            return "DRAG ROWS TO REORDER · TAP DONE WHEN FINISHED"
        }
        if swapCount > 0 {
            return "⚠ \(swapCount) SWAP SUGGESTIONS"
        }
        if session.exercises.isEmpty {
            return "JUST ADD EXERCISES — STRUCTURE COMES LATER"
        }
        return "TAP AN EXERCISE TO EDIT IT · ⋯ FOR EVERYTHING ELSE"
    }

    private var formatLabel: String? {
        guard let key = session.formatGroupKey else { return nil }
        return session.groups[key]?.type.label
    }

    private func isInSuperset(_ exercise: EditorV2Exercise) -> Bool {
        guard let key = exercise.groupKey else { return false }
        return session.groups[key]?.type == .superset
    }

    private func saveTapped() {
        saveModel.name = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        saveModel.intervals = session.toSaveIntervals()
        saveModel.saveBlocks = session.toSocialImportBlocks()
        Task { await saveModel.save() }
    }

    private func showToast(_ message: String) {
        withAnimation { toastMessage = message }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toastMessage {
            Text(toastMessage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DailyDriver.foreground)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(DailyDriver.backgroundElevated)
                .clipShape(Capsule())
                .padding(.bottom, 88)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { self.toastMessage = nil }
                    }
                }
        }
    }

    private func menuSheet(_ exercise: EditorV2Exercise) -> some View {
        EditorV2MenuSheet(
            exercise: exercise,
            isInSuperset: isInSuperset(exercise),
            onReorder: {
                menuExerciseID = nil
                isReorderMode = true
            },
            onReplace: {
                replaceExerciseID = exercise.id
                menuExerciseID = nil
                addSheetOpen = true
            },
            onSupersetToggle: {
                if isInSuperset(exercise) {
                    session.removeFromSuperset(exercise.id)
                    showToast("Removed from superset")
                    menuExerciseID = nil
                } else {
                    pairSourceID = exercise.id
                    menuExerciseID = nil
                }
            },
            onAddSet: {
                session.addSet(to: exercise.id)
                showToast("Set added ✓")
                menuExerciseID = nil
            },
            onRemove: {
                session.removeExercise(exercise.id)
                showToast("Removed")
                menuExerciseID = nil
            }
        )
        .presentationDetents([.medium])
    }

    private func editSheet(_ exercise: EditorV2Exercise) -> some View {
        EditorV2EditSheet(exercise: exercise) { updated in
            if let index = session.exercises.firstIndex(where: { $0.id == updated.id }) {
                session.exercises[index] = updated
            }
            editExerciseID = nil
        }
        .presentationDetents([.medium, .large])
    }

    private func configSheet(_ item: ConfigGroupItem) -> some View {
        EditorV2GroupConfigSheet(
            groupKey: item.id,
            group: item.group,
            onChange: { session.groups[item.id] = $0 },
            onDone: { configGroupKey = nil },
            onUngroup: {
                session.ungroup(item.id)
                configGroupKey = nil
                showToast("Ungrouped — now straight sets")
            }
        )
        .presentationDetents([.medium, .large])
    }

    private func pairSheet(_ source: EditorV2Exercise) -> some View {
        EditorV2PairSheet(
            source: source,
            candidates: session.exercises.filter { $0.id != source.id },
            groups: session.groups
        ) { targetID in
            session.pairSuperset(sourceID: source.id, targetID: targetID)
            pairSourceID = nil
            showToast("Superset paired ✓")
        }
        .presentationDetents([.medium, .large])
    }

    private var addSheet: some View {
        EditorV2AddExerciseSheet(
            formatLabel: formatLabel,
            replaceMode: replaceExerciseID != nil,
            onAdd: { name in
                if let replaceID = replaceExerciseID {
                    session.replaceExercise(replaceID, with: name)
                    replaceExerciseID = nil
                    addSheetOpen = false
                    showToast("Replaced ✓")
                } else {
                    _ = session.addExercise(named: name)
                    let fmt = formatLabel
                    showToast(
                        fmt.map { "\(name) added to the \($0)" }
                            ?? "\(name) added · 3×10 · 60s — tap to tweak"
                    )
                }
            },
            onDone: {
                addSheetOpen = false
                replaceExerciseID = nil
            }
        )
        .presentationDetents([.large])
    }

    private var menuExerciseBinding: Binding<EditorV2Exercise?> {
        Binding(
            get: { menuExerciseID.flatMap { id in session.exercises.first { $0.id == id } } },
            set: { menuExerciseID = $0?.id }
        )
    }

    private var editExerciseBinding: Binding<EditorV2Exercise?> {
        Binding(
            get: { editExerciseID.flatMap { id in session.exercises.first { $0.id == id } } },
            set: { editExerciseID = $0?.id }
        )
    }

    private var pairSourceBinding: Binding<EditorV2Exercise?> {
        Binding(
            get: { pairSourceID.flatMap { id in session.exercises.first { $0.id == id } } },
            set: { pairSourceID = $0?.id }
        )
    }

    private var configGroupBinding: Binding<ConfigGroupItem?> {
        Binding(
            get: {
                guard let key = configGroupKey, let group = session.groups[key] else { return nil }
                return ConfigGroupItem(id: key, group: group)
            },
            set: { configGroupKey = $0?.id }
        )
    }
}

private struct ConfigGroupItem: Identifiable {
    let id: String
    let group: EditorV2Group
}

#if DEBUG
#Preview("Editor v2 edit") {
    EditorV2View(mode: .edit)
}
#Preview("Editor v2 new") {
    EditorV2View(mode: .new)
}
#endif
