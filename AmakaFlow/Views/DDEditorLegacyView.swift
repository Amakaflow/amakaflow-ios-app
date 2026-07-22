//
//  DDEditorLegacyView.swift
//  AmakaFlow
//
//  AMA-2307 — legacy accordion editor used only for .backfill.
//

import SwiftUI

struct DDEditorLegacyView: View {
    let mode: DDEditorMode
    var workout: Workout?
    var onBackfillSaved: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var saveModel: WorkoutEditorViewModel

    @State private var title: String
    @State private var blocks: [DDEditorBlockDraft]
    @State private var blockPickerOpen: Bool
    @State private var toastMessage: String?
    @State private var exerciseEditTarget: DDExerciseEditTarget?

    init(mode: DDEditorMode = .new, workout: Workout? = nil, onBackfillSaved: (() -> Void)? = nil) {
        self.mode = mode
        self.workout = workout
        self.onBackfillSaved = onBackfillSaved
        let seed = DDEditorSeed.initialState(mode: mode, workout: workout)
        _title = State(initialValue: seed.title)
        _blocks = State(initialValue: seed.blocks)
        _blockPickerOpen = State(initialValue: mode == .new)
        if let workout {
            _saveModel = StateObject(wrappedValue: WorkoutEditorViewModel(workout: workout))
        } else {
            _saveModel = StateObject(wrappedValue: WorkoutEditorViewModel())
        }
    }

    private var swapCount: Int {
        blocks.reduce(0) { partial, block in
            partial + block.exercises.filter { $0.swapMessage != nil }.count
        }
    }

    private var saveTitle: String {
        mode == .backfill ? "Save log" : "Save workout"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            DailyDriver.screenBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headerSection
                    blocksSection
                    addBlockSection
                }
                .padding(.bottom, 120)
            }
            .scrollContentBackground(.hidden)

            DDEditorSaveBar(title: saveTitle, isSaving: saveModel.isSaving, action: saveTapped)
                .accessibilityIdentifier("save_workout_button")
        }
        .preferredColorScheme(.dark)
        .overlay(alignment: .top) {
            Text(" ")
                .font(.system(size: 1))
                .opacity(0.01)
                .accessibilityIdentifier("workout_editor_screen")
        }
        .overlay(alignment: .bottom) {
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
        .onChange(of: saveModel.didSave) { _, saved in
            if saved { dismiss() }
        }
        .sheet(item: $exerciseEditTarget) { target in
            DDExerciseEditSheet(blocks: $blocks, target: target) {
                exerciseEditTarget = nil
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
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

                Button("COLLAPSE ALL") { collapseAll(open: false) }
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundMuted)

                Button("EXPAND ALL") { collapseAll(open: true) }
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundMuted)
            }

            TextField("Workout title", text: $title)
                .ddDisplayText(24, weight: .heavy)
                .foregroundColor(DailyDriver.foreground)
                .padding(.top, 10)
                .accessibilityIdentifier("workout_name_field")

            if swapCount > 0 {
                Text("⚠ \(swapCount) SWAP SUGGESTIONS")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundColor(DailyDriver.amber)
                    .padding(.top, 6)
            } else {
                Text("DEFAULT REST 60S · APPLIED UNLESS OVERRIDDEN")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }

    private var blocksSection: some View {
        VStack(spacing: 10) {
            if blocks.isEmpty, !blockPickerOpen {
                Text("Add your first block to start building")
                    .font(.system(size: 12.5))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            }

            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, _ in
                DDEditorBlockCard(
                    block: binding(for: index),
                    onMoveUp: { moveBlock(from: index, direction: -1) },
                    onMoveDown: { moveBlock(from: index, direction: 1) },
                    onDelete: { blocks.remove(at: index) },
                    onAddExercise: { addExercise(to: index) },
                    onDeleteExercise: { exerciseIndex in
                        blocks[index].exercises.remove(at: exerciseIndex)
                    },
                    onMoveExercise: { exerciseIndex, direction in
                        moveExercise(blockIndex: index, exerciseIndex: exerciseIndex, direction: direction)
                    },
                    onSwap: { exerciseIndex in
                        applySwap(blockIndex: index, exerciseIndex: exerciseIndex)
                    },
                    onEdit: { exerciseIndex in
                        exerciseEditTarget = DDExerciseEditTarget(blockIndex: index, exerciseIndex: exerciseIndex)
                    }
                )
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var addBlockSection: some View {
        Group {
            if blockPickerOpen {
                DDEditorBlockTypePicker(
                    onSelect: { kind in
                        addBlock(kind)
                        blockPickerOpen = false
                    },
                    onCancel: { blockPickerOpen = false }
                )
            } else {
                Button { blockPickerOpen = true } label: {
                    Text("＋ Add block")
                        .ddDisplayText(13.5, weight: .bold)
                        .foregroundColor(DailyDriver.foregroundMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                                .foregroundColor(DailyDriver.borderStrong)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
    }

    private func binding(for index: Int) -> Binding<DDEditorBlockDraft> {
        Binding(
            get: { blocks[index] },
            set: { blocks[index] = $0 }
        )
    }

    private func collapseAll(open: Bool) {
        blocks = blocks.map { block in
            var copy = block
            copy.isOpen = open
            return copy
        }
    }

    private func moveBlock(from index: Int, direction: Int) {
        let target = index + direction
        guard blocks.indices.contains(target) else { return }
        blocks.swapAt(index, target)
    }

    private func moveExercise(blockIndex: Int, exerciseIndex: Int, direction: Int) {
        let target = exerciseIndex + direction
        guard blocks[blockIndex].exercises.indices.contains(target) else { return }
        blocks[blockIndex].exercises.swapAt(exerciseIndex, target)
    }

    private func addBlock(_ kind: DDEditorStructureKind) {
        blocks.append(
            DDEditorBlockDraft(
                structure: kind,
                label: kind.label,
                rounds: kind == .circuit || kind == .rounds ? 3 : 1,
                restBetweenRoundsSeconds: 60,
                timeCapSeconds: kind == .amrap ? 600 : (kind == .forTime ? 1800 : nil)
            )
        )
    }

    private func addExercise(to blockIndex: Int) {
        blocks[blockIndex].exercises.append(DDEditorExerciseDraft(name: "New exercise"))
        blocks[blockIndex].isOpen = true
    }

    private func applySwap(blockIndex: Int, exerciseIndex: Int) {
        guard blocks.indices.contains(blockIndex),
              blocks[blockIndex].exercises.indices.contains(exerciseIndex) else { return }
        var exercise = blocks[blockIndex].exercises[exerciseIndex]
        guard let replacement = exercise.swapReplacementName else { return }
        exercise.name = replacement
        exercise.swapMessage = nil
        exercise.swapReplacementName = nil
        blocks[blockIndex].exercises[exerciseIndex] = exercise
    }

    private func saveTapped() {
        if mode == .backfill {
            DDEditorBackfillStore.save(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                blocks: blocks
            )
            onBackfillSaved?()
            toastMessage = "Weights saved to Monday's log"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { dismiss() }
            return
        }

        saveModel.name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        saveModel.intervals = blocks.flatMap { Self.intervals(from: $0) }
        Task { await saveModel.save() }
    }
}

extension DDEditorLegacyView {
    static func intervals(from block: DDEditorBlockDraft) -> [WorkoutSaveInterval] {
        block.exercises.map { exercise in
            interval(for: exercise, block: block)
        }
    }

    static func interval(for exercise: DDEditorExerciseDraft, block: DDEditorBlockDraft) -> WorkoutSaveInterval {
        let load = exercise.weightKg.map { weight in
            weight.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(weight)) kg"
                : String(format: "%.1f kg", weight)
        }
        if let seconds = exercise.durationSeconds, seconds > 0,
           exercise.reps == nil, exercise.sets == nil, exercise.distanceMeters == nil {
            return WorkoutSaveInterval(
                type: "time",
                name: exercise.name,
                seconds: seconds,
                restSeconds: exercise.restSeconds,
                load: load
            )
        }
        if let meters = exercise.distanceMeters, meters > 0 {
            return WorkoutSaveInterval(
                type: "distance",
                name: exercise.name,
                meters: meters,
                restSeconds: exercise.restSeconds,
                load: load
            )
        }
        if let calories = exercise.calories, calories > 0 {
            return WorkoutSaveInterval(
                type: "time",
                name: exercise.name,
                seconds: calories,
                restSeconds: exercise.restSeconds,
                target: "\(calories) cal"
            )
        }
        return WorkoutSaveInterval(
            type: "reps",
            name: exercise.name,
            sets: exercise.sets ?? block.rounds,
            reps: exercise.reps ?? 10,
            restSeconds: exercise.restSeconds ?? 60,
            load: load
        )
    }
}
