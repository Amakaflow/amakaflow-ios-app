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
    var onAddExercises: ([String]) -> Void
    var onDone: () -> Void

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
        baseItems
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
                    }
                }
            }
            .padding(.bottom, 10)
            .accessibilityIdentifier("builder_v3_selected_chips")
        }
    }

    func isSelected(_ name: String) -> Bool {
        selectedNames.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    func toggleSelection(_ name: String) {
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

    private var filterChips: some View {
        Group {
            if tab == .all, trimmedQuery.isEmpty, selectedCategory == .strength {
                EditorV2FlowWrap {
                    filterChip(label: "All muscles", isSelected: muscleFilter == nil) { muscleFilter = nil }
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
                    filterChip(label: "All equipment", isSelected: equipmentFilter == nil) { equipmentFilter = nil }
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
            }
        }
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
