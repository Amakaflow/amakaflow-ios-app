//
//  EditorV2Sheets.swift
//  AmakaFlow
//
//  AMA-2307 — ⋯ menu, focused edit, runs-as, pair, add exercise sheets.
//

import SwiftUI

// MARK: - ⋯ menu

struct EditorV2MenuSheet: View {
    let exercise: EditorV2Exercise
    let isInSuperset: Bool
    var onReorder: () -> Void
    var onReplace: () -> Void
    var onSupersetToggle: () -> Void
    var onAddSet: () -> Void
    var onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetTitle(exercise.name)
            menuRow(systemImage: "line.3.horizontal", title: "Reorder exercises", action: onReorder)
            menuRow(systemImage: "arrow.left.arrow.right", title: "Replace exercise", action: onReplace)
            menuRow(
                systemImage: "link",
                title: isInSuperset ? "Remove from superset" : "Add to superset",
                action: onSupersetToggle
            )
            menuRow(systemImage: "plus", title: "Add a set", action: onAddSet)
            menuRow(
                systemImage: "xmark",
                title: "Remove exercise",
                destructive: true,
                action: onRemove
            )
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 24)
        .background(DailyDriver.backgroundElevated)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Focused edit

struct EditorV2EditSheet: View {
    @State private var draft: EditorV2Exercise
    var onDone: (EditorV2Exercise) -> Void

    init(exercise: EditorV2Exercise, onDone: @escaping (EditorV2Exercise) -> Void) {
        _draft = State(initialValue: exercise)
        self.onDone = onDone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sheetTitle(draft.name)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                if draft.sets != nil {
                    EditorV2Stepper(label: "Sets", value: draft.sets ?? 0, min: 1, max: 12) { draft.sets = $0 }
                }
                if draft.reps != nil {
                    EditorV2Stepper(label: "Reps", value: draft.reps ?? 0, min: 1, max: 50) { draft.reps = $0 }
                }
                if draft.distanceMeters != nil {
                    EditorV2Stepper(
                        label: "Distance",
                        value: draft.distanceMeters ?? 0,
                        unit: " m",
                        min: 10,
                        max: 5000,
                        step: 10
                    ) { draft.distanceMeters = $0 }
                }
                if draft.weightKg != nil {
                    EditorV2Stepper(
                        label: "Weight",
                        value: Int(draft.weightKg ?? 0),
                        unit: " kg",
                        min: 0,
                        max: 300,
                        step: 2
                    ) { draft.weightKg = Double($0) }
                }
                if draft.restSeconds != nil {
                    EditorV2Stepper(
                        label: "Rest",
                        value: draft.restSeconds ?? 0,
                        unit: "s",
                        min: 0,
                        max: 300,
                        step: 15
                    ) { draft.restSeconds = $0 }
                }
            }
            Button {
                onDone(draft)
            } label: {
                Text("Done")
                    .ddDisplayText(14, weight: .bold)
                    .foregroundColor(DailyDriver.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(DailyDriver.foreground)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("editor_v2_edit_done")
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 24)
        .background(DailyDriver.backgroundElevated)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Group config (Runs as)

struct EditorV2GroupConfigSheet: View {
    let groupKey: String
    @State private var group: EditorV2Group
    var onChange: (EditorV2Group) -> Void
    var onDone: () -> Void
    var onUngroup: () -> Void

    init(
        groupKey: String,
        group: EditorV2Group,
        onChange: @escaping (EditorV2Group) -> Void,
        onDone: @escaping () -> Void,
        onUngroup: @escaping () -> Void
    ) {
        self.groupKey = groupKey
        _group = State(initialValue: group)
        self.onChange = onChange
        self.onDone = onDone
        self.onUngroup = onUngroup
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sheetTitle(group.name)
            if group.type != .warmup {
                Text("RUNS AS")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundMuted)
                FlowRunsAsChips(selected: group.type) { type in
                    guard type != group.type else { return }
                    var next = group
                    let keepCustom = !EditorV2GroupType.allCases.map(\.label).contains(group.name)
                    next.type = type
                    next.config = type.defaultConfig
                    if !keepCustom { next.name = type.label }
                    next.structureSource = .userConfirmed
                    group = next
                    onChange(next)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                ForEach(group.stepperRows, id: \.key) { row in
                    EditorV2Stepper(
                        label: row.label,
                        value: value(for: row.key),
                        min: row.min,
                        max: row.max,
                        step: row.step
                    ) { newValue in
                        setValue(newValue, for: row.key)
                    }
                }
            }
            Button(action: onDone) {
                Text("Done")
                    .ddDisplayText(14, weight: .bold)
                    .foregroundColor(DailyDriver.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(DailyDriver.lime)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .ddLimeGlow()

            Button(action: onUngroup) {
                Text("Ungroup — back to straight sets")
                    .ddDisplayText(12.5, weight: .bold)
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 24)
        .background(DailyDriver.backgroundElevated)
        .preferredColorScheme(.dark)
    }

    private func value(for key: EditorV2ConfigKey) -> Int {
        switch key {
        case .rounds: return group.config.rounds ?? 0
        case .restSeconds: return group.config.restSeconds ?? 0
        case .capMinutes: return group.config.capMinutes ?? 0
        case .workSeconds: return group.config.workSeconds ?? 0
        }
    }

    private func setValue(_ value: Int, for key: EditorV2ConfigKey) {
        switch key {
        case .rounds: group.config.rounds = value
        case .restSeconds: group.config.restSeconds = value
        case .capMinutes: group.config.capMinutes = value
        case .workSeconds: group.config.workSeconds = value
        }
        onChange(group)
    }
}

private struct FlowRunsAsChips: View {
    let selected: EditorV2GroupType
    var onSelect: (EditorV2GroupType) -> Void

    var body: some View {
        EditorV2ChipWrap {
            ForEach(EditorV2GroupType.runsAsOptions, id: \.self) { type in
                Button {
                    onSelect(type)
                } label: {
                    Text(type.label)
                        .ddDisplayText(11.5, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(
                                type == selected
                                    ? type.accentColor.opacity(0.3)
                                    : DailyDriver.card2
                            )
                        )
                        .overlay(
                            Capsule().stroke(
                                type == selected ? type.accentColor : Color.clear,
                                lineWidth: 1
                            )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Superset picker

struct EditorV2PairSheet: View {
    let source: EditorV2Exercise
    let candidates: [EditorV2Exercise]
    let groups: [String: EditorV2Group]
    var onPick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetTitle("Superset \(source.name) with:")
            ForEach(candidates) { exercise in
                Button {
                    onPick(exercise.id)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name)
                                .ddDisplayText(13.5, weight: .semibold)
                                .foregroundColor(DailyDriver.foreground)
                            Text(exercise.summaryLine)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(DailyDriver.foregroundMuted)
                        }
                        Spacer()
                        if let key = exercise.groupKey, let group = groups[key] {
                            Text(group.name.uppercased())
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(group.type.accentColor)
                        }
                        Image(systemName: "link")
                            .foregroundColor(DailyDriver.foregroundDim)
                    }
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                Divider().background(DailyDriver.border)
            }
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 24)
        .background(DailyDriver.backgroundElevated)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Add / replace exercise

struct EditorV2AddExerciseSheet: View {
    var formatLabel: String?
    var replaceMode: Bool
    @State private var query = ""
    var onAdd: (String) -> Void
    var onDone: () -> Void

    private var filtered: [EditorV2LibraryItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return EditorV2LibraryItem.demo }
        return EditorV2LibraryItem.demo.filter { $0.name.lowercased().contains(needle) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetTitle(replaceMode ? "Replace exercise" : "Add exercise")
            TextField("Search exercises...", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(DailyDriver.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundColor(DailyDriver.foreground)
                .padding(.bottom, 10)
                .accessibilityIdentifier("editor_v2_add_search")

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(filtered) { item in
                        Button {
                            onAdd(item.name)
                        } label: {
                            HStack(spacing: 11) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.system(size: 13.5, weight: .semibold))
                                        .foregroundColor(DailyDriver.foreground)
                                    Text(item.meta)
                                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                                        .foregroundColor(
                                            item.isMissingEquipment
                                                ? DailyDriver.amber
                                                : DailyDriver.foregroundDim
                                        )
                                }
                                Spacer()
                                Image(systemName: "plus")
                                    .foregroundColor(DailyDriver.foregroundDim)
                            }
                            .padding(.vertical, 11)
                        }
                        .buttonStyle(.plain)
                        Divider().background(DailyDriver.border)
                    }

                    if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button {
                            onAdd(query.trimmingCharacters(in: .whitespacesAndNewlines))
                        } label: {
                            Text("＋ Create “\(query.trimmingCharacters(in: .whitespacesAndNewlines))”")
                                .ddDisplayText(12.5, weight: .bold)
                                .foregroundColor(DailyDriver.lime)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text(
                formatLabel.map { "Added straight into the \($0)." }
                    ?? "Added as 3 × 10 · 60s rest — tap the card after to change anything."
            )
            .font(.system(size: 10))
            .foregroundColor(DailyDriver.foregroundDim)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)

            if !replaceMode {
                Button(action: onDone) {
                    Text("Done adding")
                        .ddDisplayText(14, weight: .bold)
                        .foregroundColor(DailyDriver.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(DailyDriver.lime)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
                .accessibilityIdentifier("editor_v2_done_adding")
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 24)
        .background(DailyDriver.backgroundElevated)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Shared chrome

private func sheetTitle(_ text: String) -> some View {
    Text(text)
        .ddDisplayText(18, weight: .bold)
        .foregroundColor(DailyDriver.foreground)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .padding(.bottom, 14)
}

private func menuRow(
    systemImage: String,
    title: String,
    destructive: Bool = false,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        HStack(spacing: 13) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(destructive ? DailyDriver.destructive : DailyDriver.foregroundMuted)
                .frame(width: 22)
            Text(title)
                .ddDisplayText(14, weight: .semibold)
                .foregroundColor(destructive ? DailyDriver.destructive : DailyDriver.foreground)
            Spacer()
        }
        .padding(.vertical, 13)
    }
    .buttonStyle(.plain)
    .overlay(alignment: .bottom) {
        Rectangle().fill(DailyDriver.border).frame(height: 1)
    }
}

/// Wrap layout for Runs-as chips (distinct from clarify FlexibleChipWrap View).
private struct EditorV2ChipWrap: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var originX: CGFloat = 0
        var originY: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if originX + size.width > maxWidth, originX > 0 {
                originX = 0
                originY += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            originX += size.width + spacing
        }
        return CGSize(width: maxWidth, height: originY + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var originX = bounds.minX
        var originY = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if originX + size.width > bounds.maxX, originX > bounds.minX {
                originX = bounds.minX
                originY += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: originX, y: originY), proposal: ProposedViewSize(size))
            originX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
