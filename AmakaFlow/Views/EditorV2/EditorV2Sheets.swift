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
    /// AMA-2336 — warm-up sets are a sibling list, not a change to `sets`.
    var onAddWarmupSets: () -> Void = {}
    var onRemoveWarmupSets: () -> Void = {}
    var onRemove: () -> Void

    /// Only strength shapes take warm-up sets (spec §2).
    private var canAddWarmupSets: Bool {
        exercise.sets != nil && exercise.warmupSets.isEmpty
    }

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
            if canAddWarmupSets {
                menuRow(
                    systemImage: "flame",
                    title: "Add warm-up sets",
                    action: onAddWarmupSets
                )
            }
            if !exercise.warmupSets.isEmpty {
                menuRow(
                    systemImage: "flame.fill",
                    title: "Remove warm-up sets",
                    action: onRemoveWarmupSets
                )
            }
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

// MARK: - Group config (Runs as)

struct EditorV2GroupConfigSheet: View {
    let groupKey: String
    @State private var group: EditorV2Group
    /// True when this group is already the format pin (next adds land here).
    var isInsertionTarget: Bool = false
    var onChange: (EditorV2Group) -> Void
    var onSwitchType: (EditorV2GroupType) -> Void = { _ in }
    var onDone: () -> Void
    var onUngroup: () -> Void
    /// Delete the group + its moves, then re-pin an empty format group (tri-set / superset).
    var onDiscardAndRepin: (() -> Void)?
    /// Re-pin this group so Add exercises targets it again.
    var onFocusForAdds: (() -> Void)?
    /// AMA-2336 — soft sections are deleted (tombstoned), never "ungrouped".
    var onRemoveSoftSection: () -> Void

    init(
        groupKey: String,
        group: EditorV2Group,
        isInsertionTarget: Bool = false,
        onChange: @escaping (EditorV2Group) -> Void,
        onSwitchType: @escaping (EditorV2GroupType) -> Void = { _ in },
        onDone: @escaping () -> Void,
        onUngroup: @escaping () -> Void,
        onDiscardAndRepin: (() -> Void)? = nil,
        onFocusForAdds: (() -> Void)? = nil,
        onRemoveSoftSection: @escaping () -> Void = {}
    ) {
        self.groupKey = groupKey
        _group = State(initialValue: group)
        self.isInsertionTarget = isInsertionTarget
        self.onChange = onChange
        self.onSwitchType = onSwitchType
        self.onDone = onDone
        self.onUngroup = onUngroup
        self.onDiscardAndRepin = onDiscardAndRepin
        self.onFocusForAdds = onFocusForAdds
        self.onRemoveSoftSection = onRemoveSoftSection
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sheetTitle(group.name)
            if !group.type.isSoftSection {
                Text("RUNS AS")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundMuted)
                FlowRunsAsChips(selected: group.type, groupName: group.name) { type in
                    guard type != group.type else { return }
                    onSwitchType(type)
                }
            }
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
                spacing: 8
            ) {
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
                    .gridCellColumns(row.key == .capMinutes && group.stepperRows.count == 1 ? 2 : 1)
                }
            }
            if group.stepperRows.contains(where: { $0.key == .capMinutes }) {
                capMinutesQuickPicks
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

            if group.type.isSoftSection {
                Button(action: onRemoveSoftSection) {
                    Text("Remove \(group.type.label.lowercased())")
                        .ddDisplayText(12.5, weight: .bold)
                        .foregroundColor(DailyDriver.destructive)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("editor_v2_remove_soft_section")
            } else {
                if group.type == .superset, !isInsertionTarget, let onFocusForAdds {
                    Button(action: onFocusForAdds) {
                        Text("Add more moves to this \(group.name.lowercased())")
                            .ddDisplayText(12.5, weight: .bold)
                            .foregroundColor(DailyDriver.lime)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("editor_v2_focus_format_group")
                }
                if group.type == .superset, let onDiscardAndRepin {
                    Button(action: onDiscardAndRepin) {
                        Text("Delete this \(group.name.lowercased()) — start a new one")
                            .ddDisplayText(12.5, weight: .bold)
                            .foregroundColor(DailyDriver.destructive)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("editor_v2_discard_superset_group")
                }
                Button(action: onUngroup) {
                    Text("Ungroup — keep exercises as straight sets")
                        .ddDisplayText(12.5, weight: .bold)
                        .foregroundColor(DailyDriver.foregroundMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("editor_v2_ungroup")
            }
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

    private static let capMinutePresets = [5, 10, 12, 15, 20, 30, 45, 60]

    private var capMinutesQuickPicks: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("QUICK CAP")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundMuted)
            EditorV2FlowWrap {
                ForEach(Self.capMinutePresets, id: \.self) { minutes in
                    let selected = value(for: .capMinutes) == minutes
                    Button {
                        setValue(minutes, for: .capMinutes)
                    } label: {
                        Text("\(minutes)m")
                            .ddDisplayText(12, weight: .bold)
                            .foregroundColor(selected ? DailyDriver.ink : DailyDriver.foreground)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(selected ? DailyDriver.foreground : DailyDriver.card2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("editor_v2_cap_preset_\(minutes)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .padding(.top, 2)
        .accessibilityIdentifier("editor_v2_cap_quick_picks")
    }
}

private struct FlowRunsAsChips: View {
    let selected: EditorV2GroupType
    let groupName: String
    var onSelect: (EditorV2GroupType) -> Void

    var body: some View {
        EditorV2FlowWrap {
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

/// AMA-2443 slice 2 — DEPRECATED in favor of BuilderV3ExercisePickerSheet.
/// This old single-select sheet is no longer in the replace path as of slice 2.
/// Kept for reference until the full AMA-2443 implementation is complete.
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

func editorV2SheetTitle(_ text: String) -> some View {
    Text(text)
        .ddDisplayText(18, weight: .bold)
        .foregroundColor(DailyDriver.foreground)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .padding(.bottom, 14)
}

/// Backward-compatible alias used inside this file.
private func sheetTitle(_ text: String) -> some View {
    editorV2SheetTitle(text)
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
