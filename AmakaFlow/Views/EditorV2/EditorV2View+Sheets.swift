//
//  EditorV2View+Sheets.swift
//  AmakaFlow
//
//  Sheet/toast/bindings extracted from EditorV2View for file_length.
//

import SwiftUI

// MARK: - Sheets, toast, bindings (split for type_body_length)

extension EditorV2View {
    private var formatLabel: String? {
        guard let key = session.formatGroupKey else { return nil }
        return session.groups[key]?.type.label
    }

    private func isInSuperset(_ exercise: EditorV2Exercise) -> Bool {
        guard let key = exercise.groupKey else { return false }
        return session.groups[key]?.type == .superset
    }

    fileprivate func showToast(_ message: String) {
        withAnimation { toastMessage = message }
    }

    @ViewBuilder
    fileprivate var toastOverlay: some View {
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

    fileprivate func menuSheet(_ exercise: EditorV2Exercise) -> some View {
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
            onAddWarmupSets: {
                menuExerciseID = nil
                addWarmupSets(to: exercise.id)
            },
            onRemoveWarmupSets: {
                _ = session.removeWarmupSets(from: exercise.id)
                showToast("Warm-up sets removed")
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

    fileprivate func editSheet(_ exercise: EditorV2Exercise) -> some View {
        EditorV2EditSheet(exercise: exercise) { updated in
            if let index = session.exercises.firstIndex(where: { $0.id == updated.id }) {
                session.exercises[index] = updated
            }
            editExerciseID = nil
        }
        .presentationDetents([.medium, .large])
    }

    fileprivate func configSheet(_ item: ConfigGroupItem) -> some View {
        EditorV2GroupConfigSheet(
            groupKey: item.id,
            group: item.group,
            onChange: { session.groups[item.id] = $0 },
            onDone: { configGroupKey = nil },
            onUngroup: {
                session.ungroup(item.id)
                configGroupKey = nil
                showToast("Ungrouped — now straight sets")
            },
            onRemoveSoftSection: {
                if item.group.type == .cooldown {
                    session.removeCooldown()
                    showToast("Cool-down removed")
                } else {
                    session.removeSessionWarmup()
                    showToast("Warm-up removed")
                }
                configGroupKey = nil
            }
        )
        .presentationDetents([.medium, .large])
    }

    fileprivate func pairSheet(_ source: EditorV2Exercise) -> some View {
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

    fileprivate var addSheet: some View {
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

    fileprivate var workoutTypeMatchSheet: some View {
        WorkoutTypeMatchSheet(
            candidates: matchController.lastCandidates,
            apiService: AppDependencies.current.apiService,
            onPick: { canonicalId, displayName in
                matchController.applyUserPick(
                    canonicalId: canonicalId,
                    displayName: displayName
                )
            },
            onClear: {
                Task { await matchController.clear() }
            }
        )
        .presentationDetents([.medium, .large])
    }

    fileprivate var menuExerciseBinding: Binding<EditorV2Exercise?> {
        Binding(
            get: { menuExerciseID.flatMap { id in session.exercises.first { $0.id == id } } },
            set: { menuExerciseID = $0?.id }
        )
    }

    fileprivate var editExerciseBinding: Binding<EditorV2Exercise?> {
        Binding(
            get: { editExerciseID.flatMap { id in session.exercises.first { $0.id == id } } },
            set: { editExerciseID = $0?.id }
        )
    }

    fileprivate var pairSourceBinding: Binding<EditorV2Exercise?> {
        Binding(
            get: { pairSourceID.flatMap { id in session.exercises.first { $0.id == id } } },
            set: { pairSourceID = $0?.id }
        )
    }

    fileprivate var configGroupBinding: Binding<ConfigGroupItem?> {
        Binding(
            get: {
                guard let key = configGroupKey, let group = session.groups[key] else { return nil }
                return ConfigGroupItem(id: key, group: group)
            },
            set: { configGroupKey = $0?.id }
        )
    }
}

struct ConfigGroupItem: Identifiable {
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
