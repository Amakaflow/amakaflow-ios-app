//
//  EditorV2Content.swift
//  AmakaFlow
//
//  AMA-2307 — list / empty / format-pin / reorder sections for Editor v2.
//

import SwiftUI

struct EditorV2ContentActions {
    var onConfigGroup: (String) -> Void
    var onOpen: (String) -> Void
    var onMenu: (String) -> Void
    var onReorder: (IndexSet, Int) -> Void
    var onExitReorder: () -> Void
    var onAdd: () -> Void
    /// AMA-2443 slice 3 — group key of the run whose "＋ Add here" was tapped.
    var onAddHere: (String) -> Void = { _ in }
    /// Empty canvas only — REPLACES the canvas (`.addBlock`).
    var onStartFormat: (EditorV2GroupType) -> Void
    /// AMA-2443 slice 4 — appends a new pinned block mid-workout, then opens
    /// the picker into it. Never destructive.
    /// No default: a silent no-op here would make the block chips look
    /// functional while doing nothing.
    var onBeginFormatGroup: (EditorV2GroupType) -> Void
    /// AMA-2336 — quick-add the session warm-up from `workout_preferences`.
    var onAddWarmup: () -> Void = {}
    var onAddCooldown: () -> Void = {}
    /// Close the current tri-set / superset and pin a fresh group for more adds.
    var onBeginNextSupersetGroup: () -> Void = {}
}

// swiftlint:disable:next type_body_length
enum EditorV2Content {
    @ViewBuilder
    static func main(
        session: EditorV2Session,
        isReorderMode: Bool,
        actions: EditorV2ContentActions,
        builderV3Canvas: Bool = false
    ) -> some View {
        if isReorderMode {
            reorderList(session: session, actions: actions)
        } else if session.order.isEmpty, session.formatGroupKey == nil {
            if builderV3Canvas {
                builderV3BlankEmptyState()
            } else {
                emptyState(onStartFormat: actions.onStartFormat)
            }
            addExerciseButton(
                emphasized: !builderV3Canvas,
                plural: builderV3Canvas,
                onAdd: actions.onAdd
            )
        } else if session.order.isEmpty,
                  let fmtKey = session.formatGroupKey,
                  let group = session.groups[fmtKey] {
            formatPinnedPlaceholder(group: group, key: fmtKey, onConfig: actions.onConfigGroup)
            addExerciseButton(
                emphasized: false,
                plural: builderV3Canvas,
                destinationName: group.name,
                onAdd: actions.onAdd
            )
        } else {
            enrichmentChips(session: session, actions: actions)
            ForEach(session.runs) { run in
                if let key = run.groupKey, let group = session.groups[key] {
                    EditorV2GroupedRun(
                        group: group,
                        exercises: run.exercises,
                        isInsertionTarget: session.formatGroupKey == key,
                        onPill: { actions.onConfigGroup(key) },
                        onOpen: { actions.onOpen($0.id) },
                        onMenu: { actions.onMenu($0.id) },
                        onAddHere: { actions.onAddHere(key) }
                    )
                } else {
                    ForEach(run.exercises) { exercise in
                        EditorV2ExerciseCard(
                            exercise: exercise,
                            onOpen: { actions.onOpen(exercise.id) },
                            onMenu: { actions.onMenu(exercise.id) }
                        )
                    }
                }
            }
            // After ＋ Another tri-set / superset the new group is empty — draw the slot
            // so Add exercises has a visible destination (runs only include groups with moves).
            if isPinnedGroupEmpty(session: session),
               let fmtKey = session.formatGroupKey,
               let group = session.groups[fmtKey] {
                formatPinnedPlaceholder(group: group, key: fmtKey, onConfig: actions.onConfigGroup)
            }
            // Mutually exclusive: "＋ Another superset" is the superset-shaped
            // case of "＋ Add a block". Showing both stacked three full-width
            // CTAs doing near-identical things.
            if shouldOfferNextSupersetGroup(session: session) {
                nextSupersetGroupButton(
                    label: nextSupersetGroupLabel(session: session),
                    action: actions.onBeginNextSupersetGroup
                )
            } else if !isPinnedGroupEmpty(session: session) {
                // AMA-2443 slice 4 — non-destructive mid-workout block. Hidden
                // while the pin is empty: that block has no moves yet, so the
                // next thing to do is fill it, not start another one.
                EditorV2AddBlockButton(onSelect: actions.onBeginFormatGroup)
            }
            addExerciseButton(
                emphasized: false,
                plural: builderV3Canvas,
                destinationName: session.formatGroupKey.flatMap { session.groups[$0]?.name },
                onAdd: actions.onAdd
            )
        }
    }

    /// True when the pin names a group with no moves yet — the canvas draws
    /// `formatPinnedPlaceholder` for it and the user owes it exercises.
    ///
    /// Reads `memberIDs`, the D2 source of truth. The `exercise.groupKey`
    /// back-pointer is DERIVED and only synced by `syncGroupKeyFieldsD2()`
    /// inside `apply()`; a freshly decoded session has it nil on every
    /// exercise (`decodeFromBlocks` builds them with `groupKey: nil`), so
    /// scanning it reports a populated group as empty until the first edit.
    private static func isPinnedGroupEmpty(session: EditorV2Session) -> Bool {
        guard let key = session.formatGroupKey, let group = session.groups[key] else { return false }
        return group.memberIDs.isEmpty
    }

    private static func shouldOfferNextSupersetGroup(session: EditorV2Session) -> Bool {
        guard let key = session.formatGroupKey,
              let group = session.groups[key],
              group.type == .superset else { return false }
        return !group.memberIDs.isEmpty
    }

    private static func nextSupersetGroupLabel(session: EditorV2Session) -> String {
        let name = session.formatGroupKey.flatMap { session.groups[$0]?.name } ?? "Superset"
        if name.localizedCaseInsensitiveContains("tri") {
            return "＋ Another tri-set"
        }
        return "＋ Another superset"
    }

    private static func nextSupersetGroupButton(
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .ddDisplayText(12.5, weight: .bold)
                .foregroundColor(DailyDriver.amber)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(DailyDriver.amber.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(DailyDriver.amber.opacity(0.4), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
        .accessibilityIdentifier("editor_v2_another_superset_group")
    }

    /// AMA-2372 mockup 6 — blank Builder v3 canvas (no format chips / old door).
    static func builderV3BlankEmptyState() -> some View {
        VStack(spacing: 0) {
            Text(
                "Every exercise lands as 3 × 10 · 60s rest. "
                    + "Pair into supersets or pin a format anytime."
            )
            .font(.system(size: 13))
            .monospacedDigit()
            .foregroundColor(DailyDriver.foregroundMuted)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 10)
        .accessibilityIdentifier("builder_v3_blank_empty_state")
    }

    /// AMA-2336 — quiet "add the section you're missing" row. Presence by type:
    /// an existing warm-up (whatever wrote it) hides the chip.
    @ViewBuilder
    static func enrichmentChips(
        session: EditorV2Session,
        actions: EditorV2ContentActions
    ) -> some View {
        if !session.hasWarmupSection || !session.hasCooldownSection {
            HStack(spacing: 6) {
                if !session.hasWarmupSection {
                    enrichmentChip(
                        title: "＋ Warm-up",
                        identifier: "editor_v2_add_warmup",
                        action: actions.onAddWarmup
                    )
                }
                if !session.hasCooldownSection {
                    enrichmentChip(
                        title: "＋ Cool-down",
                        identifier: "editor_v2_add_cooldown",
                        action: actions.onAddCooldown
                    )
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 10)
        }
    }

    private static func enrichmentChip(
        title: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .ddDisplayText(11.5, weight: .bold)
                .foregroundColor(DailyDriver.foregroundMuted)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(DailyDriver.card2)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(DailyDriver.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    static func emptyState(onStartFormat: @escaping (EditorV2GroupType) -> Void) -> some View {
        VStack(spacing: 0) {
            Text("Start with any exercise")
                .ddDisplayText(15, weight: .bold)
                .foregroundColor(DailyDriver.foreground)
            Text(
                "Every exercise lands as 3 × 10 · 60s rest — tap it to tweak. "
                    + "Pair any two into a superset with ⋯ whenever you're ready."
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

            EditorV2FormatChipRow(idPrefix: "editor_v2_format_chip") { onStartFormat($0) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 10)
    }

    static func formatPinnedPlaceholder(
        group: EditorV2Group,
        key: String,
        onConfig: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorV2GroupPill(group: group, isInsertionTarget: true) { onConfig(key) }
            VStack(spacing: 5) {
                Text("Next adds land in this \(group.name.lowercased())")
                    .ddDisplayText(13.5, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                Text(
                    group.type == .superset
                        ? "Empty slot — exercises you add go here until you tap ＋ Another."
                        : "Everything you add runs inside this \(group.type.label). "
                            + "Tap the pill to change the numbers — or the format."
                )
                .font(.system(size: 11))
                .foregroundColor(DailyDriver.foregroundMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
            }
            .frame(maxWidth: .infinity)
            .padding(22)
            .background(group.type.accentColor.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    .foregroundColor(group.type.accentColor.opacity(0.65))
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(group.type.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityIdentifier("editor_v2_format_insertion_slot")
        }
        .padding(.bottom, 10)
    }

    static func reorderList(
        session: EditorV2Session,
        actions: EditorV2ContentActions
    ) -> some View {
        VStack(spacing: 6) {
            // AMA-2459: iterate `session.reorderRows` — the SAME sequence
            // `.reorder(fromOffsets:toOffset:)` mutates. This previously walked
            // `exercises.values` (an unordered dictionary, at exercise rather
            // than row granularity), so the sheet showed a different order than
            // the editor and the drag offsets indexed a different collection
            // than the command changed.
            List {
                // Nested shape: group headers followed by their member rows,
                // so exercises can be dragged WITHIN a block. The translation
                // back to commands lives in `reorderNested` on the session.
                ForEach(session.reorderNestedRows) { entry in
                    EditorV2ReorderRow(entry: entry)
                        .listRowInsets(EdgeInsets(
                            top: 3, leading: entry.isMember ? 24 : 0, bottom: 3, trailing: 0
                        ))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .onMove { indices, offset in
                    actions.onReorder(indices, offset)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // No fixed row-height math: group rows (title + caption + member
            // names) are taller than loose rows, so a per-row estimate clips
            // and lets Done overlap the list. The List owns scrolling; it is
            // rendered outside the editor's ScrollView in reorder mode.
            .frame(maxHeight: .infinity)
            .environment(\.editMode, .constant(.active))

            Button(action: actions.onExitReorder) {
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

    static func addExerciseButton(
        emphasized: Bool,
        plural: Bool = false,
        destinationName: String? = nil,
        onAdd: @escaping () -> Void
    ) -> some View {
        let label: String = {
            if let destinationName {
                let trimmed = destinationName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return "＋ Add to this \(trimmed.lowercased())"
                }
            }
            return plural ? "＋ Add exercises" : "＋ Add exercise"
        }()
        return Button(action: onAdd) {
            Text(label)
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
}
