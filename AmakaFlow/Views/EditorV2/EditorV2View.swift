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
                    content
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
        .overlay(alignment: .top) {
            Text(" ")
                .font(.system(size: 1))
                .opacity(0.01)
                .accessibilityIdentifier("workout_editor_screen")
                .accessibilityIdentifier("editor_v2_screen")
        }
        .overlay(alignment: .bottom) { toastOverlay }
        .onChange(of: saveModel.didSave) { _, saved in
            if saved { dismiss() }
        }
        .sheet(item: menuExerciseBinding) { exercise in
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
        .sheet(item: editExerciseBinding) { exercise in
            EditorV2EditSheet(exercise: exercise) { updated in
                if let index = session.exercises.firstIndex(where: { $0.id == updated.id }) {
                    session.exercises[index] = updated
                }
                editExerciseID = nil
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: configGroupBinding) { item in
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
        .sheet(item: pairSourceBinding) { source in
            EditorV2PairSheet(
                source: source,
                candidates: session.exercises.filter { $0.id != source.id },
                groups: session.groups,
                onPick: { targetID in
                    session.pairSuperset(sourceID: source.id, targetID: targetID)
                    pairSourceID = nil
                    showToast("Superset paired ✓")
                }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $addSheetOpen) {
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
    }

    // MARK: - Header

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
                            .foregroundColor(isReorderMode ? DailyDriver.lime : DailyDriver.foregroundMuted)
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

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isReorderMode {
            reorderList
        } else if session.exercises.isEmpty, session.formatGroupKey == nil {
            emptyState
            addExerciseButton(emphasized: true)
        } else if session.exercises.isEmpty, let fmtKey = session.formatGroupKey,
                  let group = session.groups[fmtKey] {
            formatPinnedPlaceholder(group: group, key: fmtKey)
            addExerciseButton(emphasized: false)
        } else {
            ForEach(session.runs) { run in
                if let key = run.groupKey, let group = session.groups[key] {
                    EditorV2GroupedRun(
                        group: group,
                        exercises: run.exercises,
                        onPill: { configGroupKey = key },
                        onOpen: { editExerciseID = $0.id },
                        onMenu: { menuExerciseID = $0.id }
                    )
                } else {
                    ForEach(run.exercises) { exercise in
                        EditorV2ExerciseCard(
                            exercise: exercise,
                            onOpen: { editExerciseID = exercise.id },
                            onMenu: { menuExerciseID = exercise.id }
                        )
                    }
                }
            }
            addExerciseButton(emphasized: false)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Text("Start with any exercise")
                .ddDisplayText(15, weight: .bold)
                .foregroundColor(DailyDriver.foreground)
            Text(
                "Every exercise lands as 3 × 10 · 60s rest — tap it to tweak. Pair any two into a superset with ⋯ whenever you're ready."
            )
            .font(.system(size: 11.5))
            .foregroundColor(DailyDriver.foregroundMuted)
            .multilineTextAlignment(.center)
            .padding(.top, 6)
            .lineSpacing(3)

            Text("KNOW THE FORMAT ALREADY?")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundDim)
                .padding(.top, 18)
                .padding(.bottom, 8)

            FlexibleFormatChips {
                ForEach(EditorV2GroupType.formatChips, id: \.self) { type in
                    Button {
                        _ = session.startFormat(type)
                        showToast("\(type.label) — add the moves, timing is set")
                    } label: {
                        Text(type.label)
                            .ddDisplayText(12, weight: .bold)
                            .foregroundColor(DailyDriver.foreground)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .background(DailyDriver.card2)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(type.accentColor.opacity(0.45), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("editor_v2_format_chip_\(type.rawValue)")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 10)
    }

    private func formatPinnedPlaceholder(group: EditorV2Group, key: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorV2GroupPill(group: group) { configGroupKey = key }
            VStack(spacing: 5) {
                Text("Timing's set — add the moves")
                    .ddDisplayText(13.5, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                Text(
                    "Everything you add runs inside this \(group.type.label). Tap the pill to change the numbers — or the format."
                )
                .font(.system(size: 11))
                .foregroundColor(DailyDriver.foregroundMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
            }
            .frame(maxWidth: .infinity)
            .padding(22)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    .foregroundColor(DailyDriver.borderStrong)
            )
        }
        .padding(.bottom, 10)
    }

    private var reorderList: some View {
        VStack(spacing: 6) {
            List {
                ForEach(session.exercises) { exercise in
                    EditorV2ReorderRow(
                        exercise: exercise,
                        group: exercise.groupKey.flatMap { session.groups[$0] }
                    )
                    .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .onMove { indices, offset in
                    session.reorder(fromOffsets: indices, toOffset: offset)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(minHeight: CGFloat(session.exercises.count) * 56)
            .environment(\.editMode, .constant(.active))

            Button {
                isReorderMode = false
            } label: {
                Text("Done")
                    .ddDisplayText(14, weight: .bold)
                    .foregroundColor(DailyDriver.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(DailyDriver.lime)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .ddLimeGlow()
            .padding(.top, 10)
            .accessibilityIdentifier("editor_v2_reorder_done")
        }
    }

    private func addExerciseButton(emphasized: Bool) -> some View {
        Button {
            replaceExerciseID = nil
            addSheetOpen = true
        } label: {
            Text("＋ Add exercise")
                .ddDisplayText(13.5, weight: .bold)
                .foregroundColor(emphasized ? DailyDriver.ink : DailyDriver.foregroundMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(emphasized ? DailyDriver.lime : Color.clear)
                .overlay {
                    if !emphasized {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                            .foregroundColor(DailyDriver.borderStrong)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("editor_v2_add_exercise")
    }

    // MARK: - Helpers

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

private struct FlexibleFormatChips: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
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
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#if DEBUG
#Preview("Editor v2 edit") {
    EditorV2View(mode: .edit)
}
#Preview("Editor v2 new") {
    EditorV2View(mode: .new)
}
#endif
