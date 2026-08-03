//
//  EditorV2View+Sheets.swift
//  AmakaFlow
//
//  Sheet/toast/bindings extracted from EditorV2View for file_length.
//

import SwiftUI

// MARK: - Sheets, toast, bindings (split for type_body_length)

extension EditorV2View {
    func loadFavoritePresets() async {
        do {
            let items = try await AppDependencies.current.apiService.fetchWorkoutTypes(
                aiPresetOnly: true
            )
            favoritePresets = WorkoutTypeFavoritesOrdering.visibleChips(from: items)
        } catch {
            favoritePresets = []
        }
    }

    private var formatLabel: String? {
        guard let key = session.formatGroupKey else { return nil }
        return session.groups[key]?.type.label
    }

    private func isInSuperset(_ exercise: EditorV2Exercise) -> Bool {
        guard let key = exercise.groupKey else { return false }
        return session.groups[key]?.type == .superset
    }

    func showToast(_ message: String) {
        withAnimation { toastMessage = message }
    }

    @ViewBuilder
    var toastOverlay: some View {
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

    func menuSheet(_ exercise: EditorV2Exercise) -> some View {
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

    func editSheet(_ exercise: EditorV2Exercise) -> some View {
        EditorV2EditSheet(exercise: exercise) { updated in
            if let index = session.exercises.firstIndex(where: { $0.id == updated.id }) {
                session.exercises[index] = updated
            }
            editExerciseID = nil
        }
        .presentationDetents([.medium, .large])
    }

    func configSheet(_ item: ConfigGroupItem) -> some View {
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

    func pairSheet(_ source: EditorV2Exercise) -> some View {
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

    /// AMA-2372 — replace stays single-select (old sheet); adding new exercises
    /// goes through the Hevy-style multi-select picker with gym overlay + search.
    @ViewBuilder
    var addSheet: some View {
        if let replaceID = replaceExerciseID {
            EditorV2AddExerciseSheet(
                formatLabel: formatLabel,
                replaceMode: true,
                onAdd: { name in
                    session.replaceExercise(replaceID, with: name)
                    replaceExerciseID = nil
                    addSheetOpen = false
                    showToast("Replaced ✓")
                },
                onDone: {
                    addSheetOpen = false
                    replaceExerciseID = nil
                }
            )
            .presentationDetents([.large])
        } else {
            BuilderV3ExercisePickerSheet(
                formatLabel: formatLabel,
                availableEquipmentKeys: gymEquipmentKeys,
                onAddExercises: { names in
                    for name in names {
                        _ = session.addExercise(named: name)
                    }
                    guard !names.isEmpty else { return }
                    if names.count == 1, let name = names.first {
                        let fmt = formatLabel
                        showToast(
                            fmt.map { "\(name) added to the \($0)" }
                                ?? "\(name) added · 3×10 · 60s — tap to tweak"
                        )
                    } else {
                        showToast("\(names.count) exercises added ✓")
                    }
                },
                onDone: {
                    addSheetOpen = false
                }
            )
            .presentationDetents([.large])
        }
    }

    /// Coaching profile equipment → gym overlay keys. Any failure (network,
    /// missing profile, decode) means "no profile" — never mark exercises
    /// as missing from the gym.
    func loadGymEquipmentKeys() async -> Set<String>? {
        do {
            guard let profile = try await AppDependencies.current.apiService.getCoachingProfile(),
                  let equipment = profile.equipment else {
                return nil
            }
            return BuilderV3GymOverlay.availableEquipmentKeys(
                bodyweight: equipment.bodyweight?.additionalProperties,
                cardio: equipment.cardio?.additionalProperties,
                strength: equipment.strength?.additionalProperties,
                mobility: equipment.mobility?.additionalProperties
            )
        } catch {
            return nil
        }
    }

    var workoutTypeMatchSheet: some View {
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

    var menuExerciseBinding: Binding<EditorV2Exercise?> {
        Binding(
            get: { menuExerciseID.flatMap { id in session.exercises.first { $0.id == id } } },
            set: { menuExerciseID = $0?.id }
        )
    }

    var editExerciseBinding: Binding<EditorV2Exercise?> {
        Binding(
            get: { editExerciseID.flatMap { id in session.exercises.first { $0.id == id } } },
            set: { editExerciseID = $0?.id }
        )
    }

    var pairSourceBinding: Binding<EditorV2Exercise?> {
        Binding(
            get: { pairSourceID.flatMap { id in session.exercises.first { $0.id == id } } },
            set: { pairSourceID = $0?.id }
        )
    }

    var configGroupBinding: Binding<ConfigGroupItem?> {
        Binding(
            get: {
                guard let key = configGroupKey, let group = session.groups[key] else { return nil }
                return ConfigGroupItem(id: key, group: group)
            },
            set: { configGroupKey = $0?.id }
        )
    }

    // MARK: - Actions (split for type_body_length)

    @ViewBuilder
    var builderV3TypeChangeButton: some View {
        if let builderV3Seed, onBuilderV3ChangeType != nil {
            let accent = Color(hex: builderV3Seed.category.accentHex)
            Button(action: builderV3ChangeTypeTapped) {
                Text("\(builderV3Seed.label.uppercased()) · CHANGE")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(accent.opacity(0.18)))
                    .overlay(Capsule().stroke(accent.opacity(0.45), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("builder_v3_type_change_button")
            .padding(.trailing, session.exercises.count > 1 ? 8 : 0)
        }
    }

    /// TYPE · CHANGE (AMA-2372) — confirms first when the canvas is dirty.
    func builderV3ChangeTypeTapped() {
        let isDirty = !session.exercises.isEmpty || !session.groups.isEmpty
        if isDirty {
            showBuilderV3ChangeTypeConfirm = true
        } else {
            onBuilderV3ChangeType?()
        }
    }

    /// Quick-add from prefs. An explicit tap re-opts in, so a previous delete
    /// (tombstone) is cleared first — presence by type still blocks duplicates.
    func quickAddSoftSection(_ kind: EnrichmentKind) {
        Task {
            let prefs = await loadEnrichmentPrefs()
            let added: Bool
            switch kind {
            case .cooldown:
                added = session.quickAddCooldown(from: prefs, clearingTombstone: true)
            case .sessionWarmup:
                added = session.quickAddSessionWarmup(from: prefs, clearingTombstone: true)
            case .betweenSetRest, .exerciseWarmupSets:
                assertionFailure("quickAddSoftSection called with unsupported kind \(kind)")
                return
            }
            guard added else {
                showToast(
                    kind == .cooldown
                        ? "No cool-down defaults yet — set them in Settings › Garmin"
                        : "No warm-up defaults yet — set them in Settings › Garmin"
                )
                return
            }
            showToast(kind == .cooldown ? "Cool-down added ✓" : "Warm-up added ✓")
        }
    }

    func addWarmupSets(to exerciseID: String) {
        Task {
            let prefs = await loadEnrichmentPrefs()
            let added = session.addDefaultWarmupSets(
                to: exerciseID,
                rows: prefs.defaultWarmupSetRows,
                clearingTombstone: true
            )
            showToast(
                added
                    ? "Warm-up sets added ✓"
                    : "No warm-up set defaults yet — set them in Settings › Garmin"
            )
        }
    }

    /// Prefs are a default source, never a gate: an unavailable mapper falls back
    /// to the shipped defaults so the quick-add still works offline.
    func loadEnrichmentPrefs() async -> WorkoutPreferences {
        if let enrichmentPrefs { return enrichmentPrefs }
        let loaded = (try? await AppDependencies.current.apiService.fetchWorkoutPreferences())
            ?? .defaults
        enrichmentPrefs = loaded
        return loaded
    }

    func saveTapped() {
        let trimmedTitle = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        saveModel.name = trimmedTitle
        saveModel.intervals = session.toSaveIntervals()
        session.mintMissingExerciseIDs()
        saveModel.saveBlocks = session.toSocialImportBlocks()
        // nil = leave server tombstones alone when this session never touched them.
        saveModel.saveEnrichmentTombstones = session.enrichmentTombstonesDirty
            ? session.enrichmentTombstones
            : nil
        Task {
            matchController.noteTitleForSave(trimmedTitle)
            let canonicalValues = await matchController.onSave(online: true)
            saveModel.canonicalId = canonicalValues.canonicalId
            saveModel.canonicalSource = canonicalValues.source
            await saveModel.save()
        }
    }

    func resolveLoadedMatchDisplayName() async {
        guard workout?.canonicalId != nil else { return }
        guard let catalog = try? await AppDependencies.current.apiService.fetchWorkoutTypes(
            aiPresetOnly: false
        ) else {
            return
        }
        matchController.resolveLoadedDisplayName(from: catalog)
    }

    func matchTitleIfNeeded() async {
        // Existing IDs are resolved against the catalog on load. A retired/unknown
        // ID stays hidden until the user actually changes the title.
        if workout?.canonicalId != nil, session.title == workout?.name {
            return
        }
        await matchController.onTitleIdle(title: session.title)
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
