//
//  BuilderV3ExercisePickerSheet.swift
//  AmakaFlow
//
//  AMA-2372 / AMA-2384 — category-first multi-select exercise picker.
//  Category browse and search go through the thin client, with an honest
//  LIVE empty state and a visible MOCK badge for fixture-backed results.
//

import SwiftUI

struct BuilderV3ExercisePickerSheet: View {
    enum Tab: String, CaseIterable {
        case all = "All"
        case recent = "Recent"
    }
    
    enum Mode {
        case add
        case replace(exerciseID: String, exerciseName: String)
    }

    /// Current format label ("EMOM", "Superset", …) shown in the footer hint.
    var formatLabel: String?
    /// `nil` = no coaching profile loaded — never mark anything missing.
    var availableEquipmentKeys: Set<String>?
    var mode: Mode = .add
    /// Exercise names currently on the canvas (for suggestions).
    var canvasExerciseNames: [String] = []
    /// Whether the canvas already has a warm-up section.
    var hasWarmupSection: Bool = false
    /// Whether the canvas already has a cool-down section.
    var hasCooldownSection: Bool = false
    /// Hide quick-block chips when adding to a specific destination group.
    var hideQuickBlocks: Bool = false
    var onAddExercises: ([String]) -> Void
    var onDone: () -> Void
    /// Callback when "Ask Amaka" is tapped with the typed query.
    var onAskAmaka: ((String) -> Void)?
    /// Callback when a format block chip is tapped (Superset, EMOM, etc).
    var onAddBlock: ((EditorV2GroupType) -> Void)?
    /// Callback when Warm-up or Cool-down chip is tapped.
    var onQuickAddSoftSection: ((EnrichmentKind) -> Void)?

    @State var query = ""
    @State var tab: Tab = .all
    @State var selectedCategory: BuilderV3BrowseCategory?
    @State var muscleFilter: String?
    @State var equipmentFilter: String?
    /// Selection order is preserved (tap order → canvas order).
    @State var selectedNames: [String] = []
    /// Custom names created from no-match search — survive filters until batch add.
    @State var createdItems: [BuilderV3ExerciseItem] = []
    @State var searchResults: [BuilderV3ExerciseItem] = []
    @State var fetchMode: BuilderV3ExerciseFetchMode?
    @State var isLoading = false
    @State var isLoadingNextPage = false
    @State var canLoadMore = false
    @State var nextOffset = 0
    @State var suggestedExercises: [BuilderV3ExerciseItem] = []
    let searchClient = BuilderV3ExerciseSearchClient()
    static let browsePageSize = 40

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var baseItems: [BuilderV3ExerciseItem] {
        let source: [BuilderV3ExerciseItem]
        switch tab {
        case .recent:
            source = BuilderV3ExerciseLibrary.recent.filter {
                BuilderV3ExerciseLibrary.matches($0, query: trimmedQuery)
            }
        case .all:
            source = searchResults
        }
        var merged = source
        for created in createdItems where !merged.contains(where: { $0.name == created.name }) {
            if BuilderV3ExerciseLibrary.matches(created, query: trimmedQuery) {
                merged.insert(created, at: 0)
            }
        }
        return merged
    }

    var filteredItems: [BuilderV3ExerciseItem] {
        var items = baseItems
        // Apply promoted equipment filter when typing (feature 3)
        if !trimmedQuery.isEmpty, let filter = equipmentFilter {
            items = items.filter { $0.equipmentKey == filter }
        }
        return items
    }

    var loadKey: String {
        [
            tab.rawValue,
            trimmedQuery,
            selectedCategory?.rawValue ?? "",
            muscleFilter ?? "",
            equipmentFilter ?? ""
        ].joined(separator: "|")
    }

    var hasExactMatch: Bool {
        let needle = trimmedQuery.lowercased()
        guard !needle.isEmpty else { return false }
        return filteredItems.contains { $0.name.lowercased() == needle }
            || searchResults.contains { $0.name.lowercased() == needle }
            || BuilderV3ExerciseLibrary.demo.contains { $0.name.lowercased() == needle }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if case .replace(_, let exerciseName) = mode {
                outgoingExerciseRow(exerciseName)
            }
            selectedChips
            searchField
            tabPicker
            quickBlockChips
            filterChips
            Divider().background(DailyDriver.border).padding(.top, 8)
            resultsList
            footer
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 24)
        .background(DailyDriver.backgroundElevated)
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("builder_v3_exercise_picker_sheet")
        .task(id: loadKey) { await loadExercises() }
        .onAppear {
            computeSuggestions()
        }
    }
    
    private func outgoingExerciseRow(_ exerciseName: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(DailyDriver.amber)
                VStack(alignment: .leading, spacing: 2) {
                    Text(exerciseName)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(DailyDriver.foreground)
                    Text("OUTGOING")
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundColor(DailyDriver.amber)
                }
                Spacer()
            }
            .padding(.vertical, 10)
            .padding(.bottom, 8)
            .accessibilityIdentifier("builder_v3_outgoing_exercise")
            Divider().background(DailyDriver.border)
        }
    }

    private var header: some View {
        HStack {
            Text(headerTitle)
                .ddDisplayText(18, weight: .bold)
                .foregroundColor(DailyDriver.foreground)
            Spacer()
            if case .add = mode, !selectedNames.isEmpty {
                Text("\(selectedNames.count) selected")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(DailyDriver.lime)
                    .accessibilityIdentifier("builder_v3_exercise_selected_count")
            }
            if fetchMode == .mock {
                Text("MOCK")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(DailyDriver.ink)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(DailyDriver.amber))
                    .accessibilityIdentifier("builder_v3_exercise_mode_mock")
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
    
    private var headerTitle: String {
        switch mode {
        case .add:
            return "Add exercises"
        case .replace:
            return "Replace exercise"
        }
    }

    /// Always-visible selection strip so Create / search → category-grid doesn't hide what was picked.
    @ViewBuilder
    private var selectedChips: some View {
        // In replace mode, hide chips (single-select shows in footer button instead)
        if case .add = mode, !selectedNames.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(selectedNames, id: \.self) { name in
                        Button {
                            toggleSelection(name)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(name)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .lineLimit(1)
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundColor(DailyDriver.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(DailyDriver.lime))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("builder_v3_selected_chip_\(name)")
                        // Chip lands from the row it was picked in, and leaves
                        // by shrinking back rather than blinking out.
                        .transition(
                            .scale(scale: 0.7).combined(with: .opacity)
                        )
                    }
                }
            }
            .padding(.bottom, 10)
            .accessibilityIdentifier("builder_v3_selected_chips")
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    /// Re-arms the row entrance whenever the list's content changes.
    ///
    /// Derived rather than bumped by hand at each call site — a new filter added
    /// later joins the signature here, instead of silently animating nothing.
    var revealGeneration: Int {
        var hasher = Hasher()
        hasher.combine(trimmedQuery)
        hasher.combine(tab)
        hasher.combine(selectedCategory?.id)
        hasher.combine(muscleFilter)
        hasher.combine(equipmentFilter)
        hasher.combine(filteredItems.count)
        return hasher.finalize()
    }

    func isSelected(_ name: String) -> Bool {
        selectedNames.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    func toggleSelection(_ name: String) {
        withAnimation(MotionTokens.spring) {
            switch mode {
            case .add:
                if let index = selectedNames.firstIndex(where: {
                    $0.caseInsensitiveCompare(name) == .orderedSame
                }) {
                    selectedNames.remove(at: index)
                } else {
                    selectedNames.append(name)
                }
            case .replace:
                // Single-select: replace current selection or select if empty
                if selectedNames.first?.caseInsensitiveCompare(name) == .orderedSame {
                    selectedNames.removeAll()
                } else {
                    selectedNames = [name]
                }
            }
        }
    }

    private var searchField: some View {
        TextField("Search — chest press, pull up...", text: $query)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(12)
            .background(DailyDriver.inputBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundColor(DailyDriver.foreground)
            .accessibilityIdentifier("builder_v3_exercise_search")
    }

    private var tabPicker: some View {
        HStack(spacing: 8) {
            ForEach(Tab.allCases, id: \.self) { candidate in
                Button {
                    tab = candidate
                } label: {
                    Text(candidate.rawValue)
                        .ddDisplayText(11.5, weight: .bold)
                        .foregroundColor(tab == candidate ? DailyDriver.ink : DailyDriver.foregroundMuted)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(tab == candidate ? DailyDriver.lime : DailyDriver.card2))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("builder_v3_tab_\(candidate.rawValue.lowercased())")
            }
            Spacer()
        }
        .padding(.top, 10)
    }
}

// MARK: - Zero-query chips, filters, suggestions (extension keeps the
// struct body under the 300-line type_body_length lint cap — AMA-2443).
extension BuilderV3ExercisePickerSheet {
    @ViewBuilder
    private var quickBlockChips: some View {
        if tab == .all, trimmedQuery.isEmpty, selectedCategory == nil, case .add = mode, !hideQuickBlocks {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Format chips: Superset, EMOM, AMRAP, Tabata, For time, Circuit
                    Button {
                        onAddBlock?(.superset)
                        onDone()
                    } label: {
                        blockChipLabel("Superset")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("builder_v3_quick_block_superset")
                    
                    ForEach(EditorV2GroupType.formatChips, id: \.self) { type in
                        Button {
                            onAddBlock?(type)
                            onDone()
                        } label: {
                            blockChipLabel(type.label)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("builder_v3_quick_block_\(type.rawValue)")
                    }
                    
                    // Warm-up chip (only if not already present)
                    if !hasWarmupSection {
                        Button {
                            onQuickAddSoftSection?(.sessionWarmup)
                            onDone()
                        } label: {
                            blockChipLabel("Warm-up")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("builder_v3_quick_block_warmup")
                    }
                    
                    // Cool-down chip (only if not already present)
                    if !hasCooldownSection {
                        Button {
                            onQuickAddSoftSection?(.cooldown)
                            onDone()
                        } label: {
                            blockChipLabel("Cool-down")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("builder_v3_quick_block_cooldown")
                    }
                }
            }
            .padding(.top, 10)
            .accessibilityIdentifier("builder_v3_quick_block_chips")
        }
    }
    
    private func blockChipLabel(_ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 11.5, weight: .semibold))
        }
        .foregroundColor(DailyDriver.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(DailyDriver.lime))
    }

    private var filterChips: some View {
        Group {
            if tab == .all, trimmedQuery.isEmpty, selectedCategory == .strength {
                EditorV2FlowWrap {
                    filterChip(label: "All muscles", isSelected: muscleFilter == nil, id: "builder_v3_muscle_chip_all") { muscleFilter = nil }
                    ForEach(BuilderV3ExerciseLibrary.strengthMuscleChips.indices, id: \.self) { index in
                        let chip = BuilderV3ExerciseLibrary.strengthMuscleChips[index]
                        filterChip(
                            label: chip.label,
                            isSelected: muscleFilter == chip.key,
                            id: "builder_v3_muscle_chip_\(chip.key)"
                        ) {
                            muscleFilter = muscleFilter == chip.key ? nil : chip.key
                        }
                    }
                }
                .padding(.top, 10)
            } else if tab == .all, trimmedQuery.isEmpty, selectedCategory == .cardio {
                EditorV2FlowWrap {
                    filterChip(label: "All equipment", isSelected: equipmentFilter == nil, id: "builder_v3_equipment_chip_all") { equipmentFilter = nil }
                    ForEach(BuilderV3ExerciseLibrary.cardioEquipmentChips.indices, id: \.self) { index in
                        let chip = BuilderV3ExerciseLibrary.cardioEquipmentChips[index]
                        filterChip(
                            label: chip.label,
                            isSelected: equipmentFilter == chip.key,
                            id: "builder_v3_equipment_chip_\(chip.key)"
                        ) {
                            equipmentFilter = equipmentFilter == chip.key ? nil : chip.key
                        }
                    }
                }
                .padding(.top, 10)
            } else if tab == .all, !trimmedQuery.isEmpty {
                // Promoted equipment chips while typing (feature 3)
                promotedEquipmentChips
            }
        }
    }
    
    @ViewBuilder
    private var promotedEquipmentChips: some View {
        let labels = BuilderV3ExerciseLibrary.promotedEquipment
        EditorV2FlowWrap {
            ForEach(labels.indices, id: \.self) { index in
                let chip = labels[index]
                filterChip(
                    label: chip.label,
                    isSelected: equipmentFilter == chip.key,
                    id: "builder_v3_promoted_equipment_\(chip.key)"
                ) {
                    equipmentFilter = equipmentFilter == chip.key ? nil : chip.key
                }
            }
        }
        .padding(.top, 10)
        .accessibilityIdentifier("builder_v3_promoted_equipment_chips")
    }

    private func filterChip(
        label: String,
        isSelected: Bool,
        id: String? = nil,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(isSelected ? DailyDriver.ink : DailyDriver.foregroundMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(isSelected ? DailyDriver.lime : DailyDriver.card2))
        }
        .buttonStyle(.plain)
        .modifier(OptionalAccessibilityId(id: id))
    }
    
    func computeSuggestions() {
        guard !canvasExerciseNames.isEmpty else {
            suggestedExercises = []
            return
        }
        suggestedExercises = BuilderV3ExerciseSuggestions.suggestedExercises(
            canvasNames: canvasExerciseNames,
            catalog: BuilderV3ExerciseLibrary.demo,
            limit: 6
        )
    }
    
    var didYouMeanResult: String? {
        guard !trimmedQuery.isEmpty, filteredItems.isEmpty else { return nil }
        return BuilderV3ExerciseSuggestions.didYouMean(
            query: trimmedQuery,
            catalog: BuilderV3ExerciseLibrary.demo
        )
    }
}

#if DEBUG
#Preview {
    BuilderV3ExercisePickerSheet(
        formatLabel: nil,
        availableEquipmentKeys: ["barbell"],
        onAddExercises: { _ in },
        onDone: {}
    )
}
#endif
