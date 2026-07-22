//
//  DDEditorView.swift
//  AmakaFlow
//
//  Daily Driver workout editor shell.
//  AMA-2307: .edit / .importReview / .new → Editor v2 (screens-editor2.jsx).
//  .backfill keeps the legacy accordion (dd-editor-backfill-dark.png).
//

import SwiftUI

// MARK: - Mode

enum DDEditorMode: Equatable {
    case edit
    case new
    case importReview
    case backfill
}

// MARK: - Block structure kinds (DD_STRUCTURES)

enum DDEditorStructureKind: String, CaseIterable, Identifiable {
    case circuit
    case emom
    case amrap
    case tabata
    case forTime = "for-time"
    case sets
    case superset
    case rounds
    case warmup
    case cooldown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .circuit: return "Circuit"
        case .emom: return "EMOM"
        case .amrap: return "AMRAP"
        case .tabata: return "Tabata"
        case .forTime: return "For Time"
        case .sets: return "Sets"
        case .superset: return "Superset"
        case .rounds: return "Rounds"
        case .warmup: return "Warm-up"
        case .cooldown: return "Cool-down"
        }
    }

    var emoji: String {
        switch self {
        case .circuit, .rounds: return "🟢"
        case .emom: return "🔵"
        case .amrap: return "🟠"
        case .tabata: return "🔴"
        case .forTime: return "🟣"
        case .sets: return "⚫"
        case .superset: return "🟡"
        case .warmup, .cooldown: return "⬜"
        }
    }

    var accentColor: Color {
        switch self {
        case .circuit, .rounds: return Color(hex: "4AD97F")
        case .emom: return DailyDriver.blue
        case .amrap: return DailyDriver.orange
        case .tabata: return DailyDriver.red
        case .forTime: return DailyDriver.purple
        case .sets: return Color.white.opacity(0.35)
        case .superset: return DailyDriver.amber
        case .warmup, .cooldown: return Color(hex: "8890A0")
        }
    }

    static func from(blockStructure: BlockStructure) -> DDEditorStructureKind {
        switch blockStructure {
        case .circuit: return .circuit
        case .emom: return .emom
        case .amrap: return .amrap
        case .tabata: return .tabata
        case .superset: return .superset
        case .straight: return .sets
        }
    }
}

// MARK: - Draft models

struct DDEditorExerciseDraft: Identifiable, Equatable {
    let id: String
    var name: String
    var sets: Int?
    var reps: Int?
    var durationSeconds: Int?
    var distanceMeters: Int?
    var weightKg: Double?
    var calories: Int?
    var restSeconds: Int?
    var showsLastTime: Bool
    var swapMessage: String?
    var swapReplacementName: String?

    init(
        id: String = UUID().uuidString,
        name: String,
        sets: Int? = 3,
        reps: Int? = 10,
        durationSeconds: Int? = nil,
        distanceMeters: Int? = nil,
        weightKg: Double? = nil,
        calories: Int? = nil,
        restSeconds: Int? = 60,
        showsLastTime: Bool = false,
        swapMessage: String? = nil,
        swapReplacementName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.sets = sets
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.weightKg = weightKg
        self.calories = calories
        self.restSeconds = restSeconds
        self.showsLastTime = showsLastTime
        self.swapMessage = swapMessage
        self.swapReplacementName = swapReplacementName
    }

    var summaryLine: String {
        var parts: [String] = []
        if let sets { parts.append("\(sets) SETS") }
        if let reps { parts.append("\(reps) REPS") }
        if let durationSeconds {
            parts.append(durationSeconds >= 60 ? "\(durationSeconds / 60) MIN" : "\(durationSeconds)S")
        }
        if let distanceMeters { parts.append("\(distanceMeters) M") }
        if let calories { parts.append("\(calories) CAL") }
        if let weightKg {
            let text = weightKg.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(weightKg))
                : String(format: "%.1f", weightKg)
            parts.append("\(text) KG")
        }
        if let restSeconds { parts.append("REST \(restSeconds)S") }
        var line = parts.joined(separator: " · ")
        if showsLastTime { line += " · LAST TIME" }
        return line
    }
}

struct DDEditorBlockDraft: Identifiable, Equatable {
    let id: String
    var structure: DDEditorStructureKind
    var label: String
    var rounds: Int
    var restBetweenRoundsSeconds: Int
    var timeCapSeconds: Int?
    var isOpen: Bool
    var exercises: [DDEditorExerciseDraft]

    init(
        id: String = UUID().uuidString,
        structure: DDEditorStructureKind,
        label: String,
        rounds: Int = 1,
        restBetweenRoundsSeconds: Int = 60,
        timeCapSeconds: Int? = nil,
        isOpen: Bool = true,
        exercises: [DDEditorExerciseDraft] = []
    ) {
        self.id = id
        self.structure = structure
        self.label = label
        self.rounds = rounds
        self.restBetweenRoundsSeconds = restBetweenRoundsSeconds
        self.timeCapSeconds = timeCapSeconds
        self.isOpen = isOpen
        self.exercises = exercises
    }

    var metaLine: String {
        let count = exercises.count
        let exercisePart = "\(count) EXERCISE\(count == 1 ? "" : "S")"
        if structure == .amrap || structure == .forTime {
            let cap = DDEditorFormatting.duration(timeCapSeconds ?? 600)
            return "\(exercisePart) · CAP \(cap.uppercased())"
        }
        if structure == .sets {
            return "\(exercisePart) · \(rounds) SETS · \(DDEditorFormatting.duration(restBetweenRoundsSeconds).uppercased()) REST"
        }
        if rounds > 1 {
            let rest = DDEditorFormatting.duration(restBetweenRoundsSeconds)
            return "\(exercisePart) · \(rounds) ROUNDS · \(rest.uppercased()) REST/ROUND"
        }
        return exercisePart
    }
}

enum DDEditorFormatting {
    static func duration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        if remainder == 0 { return "\(minutes) min" }
        return "\(minutes)m \(remainder)s"
    }
}

enum DDEditorSeed {
    static func initialState(mode: DDEditorMode, workout: Workout?) -> (title: String, blocks: [DDEditorBlockDraft]) {
        switch mode {
        case .new:
            return ("", [])
        case .backfill:
            return (
                "Lower body — posterior",
                [
                    DDEditorBlockDraft(
                        structure: .sets,
                        label: "Main lifts",
                        rounds: 3,
                        restBetweenRoundsSeconds: 120,
                        exercises: [
                            DDEditorExerciseDraft(name: "Back squat", sets: 3, reps: 5, weightKg: 85, restSeconds: 120, showsLastTime: true),
                            DDEditorExerciseDraft(name: "Romanian deadlift", sets: 3, reps: 8, weightKg: 70, restSeconds: 120, showsLastTime: true),
                            DDEditorExerciseDraft(name: "Split squat", sets: 2, reps: 10, weightKg: 20, restSeconds: 60, showsLastTime: true)
                        ]
                    )
                ]
            )
        case .importReview:
            return (
                "DB Full-body AMRAP",
                [
                    DDEditorBlockDraft(
                        structure: .amrap,
                        label: "AMRAP",
                        timeCapSeconds: 600,
                        exercises: [
                            DDEditorExerciseDraft(name: "Wall balls", sets: nil, reps: 20, restSeconds: nil),
                            DDEditorExerciseDraft(
                                name: "Barbell thrusters",
                                sets: nil,
                                reps: 12,
                                weightKg: 40,
                                restSeconds: nil,
                                swapMessage: "No barbell — swap to DB thrusters 2×16?",
                                swapReplacementName: "DB thrusters"
                            ),
                            DDEditorExerciseDraft(name: "Burpee broad jumps", sets: nil, reps: 10, restSeconds: nil)
                        ]
                    ),
                    DDEditorBlockDraft(
                        structure: .forTime,
                        label: "Finisher",
                        timeCapSeconds: 240,
                        isOpen: false,
                        exercises: [
                            DDEditorExerciseDraft(
                                name: "Sled push",
                                distanceMeters: 40,
                                swapMessage: "No sled — swap to heavy farmer carry?",
                                swapReplacementName: "Heavy farmer carry"
                            )
                        ]
                    )
                ]
            )
        case .edit:
            if let workout {
                if !workout.blocks.isEmpty {
                    return (workout.name, workout.blocks.map { blockDraft(from: $0) })
                }
                let exercises = workout.intervals.compactMap { interval -> DDEditorExerciseDraft? in
                    guard case .reps(let sets, let reps, let name, let load, let restSec, _) = interval else { return nil }
                    return DDEditorExerciseDraft(
                        name: name,
                        sets: sets,
                        reps: reps,
                        weightKg: Self.parseLoad(load),
                        restSeconds: restSec
                    )
                }
                if exercises.isEmpty {
                    return (workout.name, Self.hyroxDefaultBlocks())
                }
                return (
                    workout.name,
                    [DDEditorBlockDraft(structure: .sets, label: "Main block", exercises: exercises)]
                )
            }
            return ("Hyrox Sim — Stations 1–4", Self.hyroxDefaultBlocks())
        }
    }

    static func hyroxDefaultBlocks() -> [DDEditorBlockDraft] {
        [
            DDEditorBlockDraft(
                structure: .circuit,
                label: "Stations 1–4",
                rounds: 2,
                restBetweenRoundsSeconds: 90,
                exercises: [
                    DDEditorExerciseDraft(name: "SkiErg", distanceMeters: 250, restSeconds: 30),
                    DDEditorExerciseDraft(name: "Sled push", distanceMeters: 40, weightKg: 80, restSeconds: 30),
                    DDEditorExerciseDraft(name: "Burpee broad jumps", sets: nil, reps: 10, restSeconds: 30),
                    DDEditorExerciseDraft(name: "Rower", distanceMeters: 500, restSeconds: 60)
                ]
            ),
            DDEditorBlockDraft(
                structure: .rounds,
                label: "Run intervals",
                rounds: 4,
                restBetweenRoundsSeconds: 60,
                isOpen: false,
                exercises: [
                    DDEditorExerciseDraft(name: "Run", distanceMeters: 400)
                ]
            )
        ]
    }

    private static func blockDraft(from block: Block) -> DDEditorBlockDraft {
        DDEditorBlockDraft(
            structure: DDEditorStructureKind.from(blockStructure: block.structure),
            label: block.label ?? block.structure.displayName,
            rounds: block.rounds,
            restBetweenRoundsSeconds: block.restBetweenSeconds ?? 60,
            exercises: block.exercises.map { exercise in
                DDEditorExerciseDraft(
                    name: exercise.name,
                    sets: exercise.sets,
                    reps: Int(exercise.reps ?? ""),
                    durationSeconds: exercise.durationSeconds,
                    distanceMeters: exercise.distance.map { Int($0) },
                    weightKg: exercise.load?.value,
                    restSeconds: exercise.restSeconds
                )
            }
        )
    }

    private static func parseLoad(_ load: String?) -> Double? {
        guard let load else { return nil }
        let trimmed = load.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = trimmed.range(
            of: #"^(\d+(?:\.\d+)?)"#,
            options: .regularExpression
        ) else { return nil }
        return Double(trimmed[match])
    }
}

// MARK: - Editor view

struct DDEditorView: View {
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
        // AMA-2307: calm Editor v2 for edit / import / new; legacy accordion only for backfill.
        if mode == .backfill {
            legacyEditorBody
        } else {
            EditorV2View(mode: mode, workout: workout)
        }
    }

    private var legacyEditorBody: some View {
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

            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
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
        saveModel.intervals = blocks.flatMap(Self.intervals(from:))
        Task { await saveModel.save() }
    }

    private static func intervals(from block: DDEditorBlockDraft) -> [WorkoutSaveInterval] {
        block.exercises.map { exercise in
            interval(for: exercise, block: block)
        }
    }

    private static func interval(for exercise: DDEditorExerciseDraft, block: DDEditorBlockDraft) -> WorkoutSaveInterval {
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

// MARK: - Block card

private struct DDEditorBlockCard: View {
    @Binding var block: DDEditorBlockDraft
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void
    let onAddExercise: () -> Void
    let onDeleteExercise: (Int) -> Void
    let onMoveExercise: (Int, Int) -> Void
    let onSwap: (Int) -> Void
    let onEdit: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ReorderColumn(onUp: onMoveUp, onDown: onMoveDown)

                Text(block.structure.label.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(block.structure.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(block.structure.accentColor.opacity(0.18))
                    .clipShape(Capsule())

                Button { block.isOpen.toggle() } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(block.label)
                            .ddDisplayText(13.5, weight: .bold)
                            .foregroundColor(DailyDriver.foreground)
                            .lineLimit(1)
                        Text(block.metaLine)
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                            .foregroundColor(DailyDriver.foregroundDim)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DailyDriver.foregroundDim)
                        .padding(4)
                }
                .buttonStyle(.plain)

                Button { block.isOpen.toggle() } label: {
                    Image(systemName: block.isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(DailyDriver.foregroundDim)
                        .padding(4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)

            if block.isOpen {
                VStack(spacing: 0) {
                    if block.exercises.isEmpty {
                        Text("No exercises yet — add one below")
                            .font(.system(size: 11.5))
                            .foregroundColor(DailyDriver.foregroundDim)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }

                    ForEach(Array(block.exercises.enumerated()), id: \.element.id) { index, exercise in
                        DDEditorExerciseRow(
                            exercise: exercise,
                            onMoveUp: { onMoveExercise(index, -1) },
                            onMoveDown: { onMoveExercise(index, 1) },
                            onDelete: { onDeleteExercise(index) },
                            onSwap: { onSwap(index) },
                            onEdit: { onEdit(index) }
                        )
                        if index < block.exercises.count - 1 {
                            Divider().overlay(DailyDriver.border)
                        }
                    }

                    Button(action: onAddExercise) {
                        Text("＋ Add exercise")
                            .ddDisplayText(12.5, weight: .bold)
                            .foregroundColor(DailyDriver.foregroundMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                                    .foregroundColor(DailyDriver.borderStrong)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .background(Color.black.opacity(0.3))
                .overlay(alignment: .top) {
                    Rectangle().fill(DailyDriver.border).frame(height: 1)
                }
            }
        }
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(block.structure.accentColor)
                .frame(width: 3)
                .padding(.vertical, 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct DDEditorExerciseRow: View {
    let exercise: DDEditorExerciseDraft
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void
    let onSwap: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ReorderColumn(onUp: onMoveUp, onDown: onMoveDown)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(DailyDriver.foreground)
                Text(exercise.summaryLine)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(exercise.showsLastTime ? DailyDriver.foregroundDim : DailyDriver.foregroundMuted)

                if let swapMessage = exercise.swapMessage {
                    HStack(alignment: .top, spacing: 8) {
                        Text(swapMessage)
                            .font(.system(size: 11))
                            .foregroundColor(DailyDriver.amber)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(action: onSwap) {
                            Text("Swap")
                                .ddDisplayText(11, weight: .bold)
                                .foregroundColor(Color(hex: "1A1200"))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 5)
                                .background(DailyDriver.amber)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                }
            }

            Spacer(minLength: 0)

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 13))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .padding(3)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("dd_editor_exercise_edit")

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 13))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .padding(3)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
    }
}

private struct ReorderColumn: View {
    let onUp: () -> Void
    let onDown: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onUp) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .padding(1)
            }
            .buttonStyle(.plain)
            Button(action: onDown) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .padding(1)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct DDEditorBlockTypePicker: View {
    let onSelect: (DDEditorStructureKind) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What type of block?")
                .ddDisplayText(14, weight: .bold)
                .foregroundColor(DailyDriver.foreground)

            DDEditorFlowLayout(spacing: 7) {
                ForEach(DDEditorStructureKind.allCases) { kind in
                    Button { onSelect(kind) } label: {
                        Text("\(kind.emoji) \(kind.label)")
                            .ddDisplayText(12.5, weight: .semibold)
                            .foregroundColor(DailyDriver.foreground)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .background(DailyDriver.card2)
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(kind.accentColor.opacity(0.45), lineWidth: 1)
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Button(action: onCancel) {
                Text("Cancel")
                    .ddDisplayText(12, weight: .bold)
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Simple wrapping layout for block-type chips.
private struct DDEditorFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}

#if DEBUG
#Preview { DDEditorView(mode: .backfill) }
#endif
