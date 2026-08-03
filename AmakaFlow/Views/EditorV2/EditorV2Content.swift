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
    var onStartFormat: (EditorV2GroupType) -> Void
    /// AMA-2336 — quick-add the session warm-up from `workout_preferences`.
    var onAddWarmup: () -> Void = {}
    var onAddCooldown: () -> Void = {}
}

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
        } else if session.exercises.isEmpty, session.formatGroupKey == nil {
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
        } else if session.exercises.isEmpty,
                  let fmtKey = session.formatGroupKey,
                  let group = session.groups[fmtKey] {
            formatPinnedPlaceholder(group: group, key: fmtKey, onConfig: actions.onConfigGroup)
            addExerciseButton(
                emphasized: false,
                plural: builderV3Canvas,
                onAdd: actions.onAdd
            )
        } else {
            enrichmentChips(session: session, actions: actions)
            ForEach(session.runs) { run in
                if let key = run.groupKey, let group = session.groups[key] {
                    EditorV2GroupedRun(
                        group: group,
                        exercises: run.exercises,
                        onPill: { actions.onConfigGroup(key) },
                        onOpen: { actions.onOpen($0.id) },
                        onMenu: { actions.onMenu($0.id) }
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
            addExerciseButton(
                emphasized: false,
                plural: builderV3Canvas,
                onAdd: actions.onAdd
            )
        }
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

            EditorV2FlowWrap {
                ForEach(EditorV2GroupType.formatChips, id: \.self) { type in
                    Button {
                        onStartFormat(type)
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

    static func formatPinnedPlaceholder(
        group: EditorV2Group,
        key: String,
        onConfig: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorV2GroupPill(group: group) { onConfig(key) }
            VStack(spacing: 5) {
                Text("Timing's set — add the moves")
                    .ddDisplayText(13.5, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                Text(
                    "Everything you add runs inside this \(group.type.label). "
                        + "Tap the pill to change the numbers — or the format."
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

    static func reorderList(
        session: EditorV2Session,
        actions: EditorV2ContentActions
    ) -> some View {
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
                    actions.onReorder(indices, offset)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(minHeight: CGFloat(session.exercises.count) * 56)
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
        onAdd: @escaping () -> Void
    ) -> some View {
        let label = plural ? "＋ Add exercises" : "＋ Add exercise"
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
