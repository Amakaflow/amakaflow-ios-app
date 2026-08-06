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

    /// Current format label ("EMOM", "Superset", …) shown in the footer hint.
    var formatLabel: String?
    /// `nil` = no coaching profile loaded — never mark anything missing.
    var availableEquipmentKeys: Set<String>?
    var onAddExercises: ([String]) -> Void
    var onDone: () -> Void

    @State private var query = ""
    @State private var tab: Tab = .all
    @State private var selectedCategory: BuilderV3BrowseCategory?
    @State private var muscleFilter: String?
    @State private var equipmentFilter: String?
    /// Selection order is preserved (tap order → canvas order).
    @State private var selectedNames: [String] = []
    /// Custom names created from no-match search — survive filters until batch add.
    @State private var createdItems: [BuilderV3ExerciseItem] = []
    @State private var searchResults: [BuilderV3ExerciseItem] = []
    @State private var fetchMode: BuilderV3ExerciseFetchMode?
    @State private var isLoading = false
    private let searchClient = BuilderV3ExerciseSearchClient()

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var baseItems: [BuilderV3ExerciseItem] {
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

    private var filteredItems: [BuilderV3ExerciseItem] {
        baseItems
    }

    private var loadKey: String {
        [
            tab.rawValue,
            trimmedQuery,
            selectedCategory?.rawValue ?? "",
            muscleFilter ?? "",
            equipmentFilter ?? ""
        ].joined(separator: "|")
    }

    private var hasExactMatch: Bool {
        let needle = trimmedQuery.lowercased()
        guard !needle.isEmpty else { return false }
        return filteredItems.contains { $0.name.lowercased() == needle }
            || searchResults.contains { $0.name.lowercased() == needle }
            || BuilderV3ExerciseLibrary.demo.contains { $0.name.lowercased() == needle }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
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

    private var header: some View {
        HStack {
            Text("Add exercises")
                .ddDisplayText(18, weight: .bold)
                .foregroundColor(DailyDriver.foreground)
            Spacer()
            if !selectedNames.isEmpty {
                Text("\(selectedNames.count) selected")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(DailyDriver.lime)
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

    private var resultsList: some View {
        ScrollView {
            VStack(spacing: 0) {
                if tab == .all, trimmedQuery.isEmpty, selectedCategory == nil {
                    categoryGrid
                } else {
                    if tab == .all, trimmedQuery.isEmpty, let selectedCategory {
                        categoryHeader(selectedCategory)
                    }

                    if isLoading {
                        ProgressView()
                            .tint(DailyDriver.lime)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    } else {
                        ForEach(filteredItems) { item in
                            exerciseRow(item)
                            Divider().background(DailyDriver.border)
                        }

                        if filteredItems.isEmpty, trimmedQuery.isEmpty {
                            Text("No exercises found in this category.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(DailyDriver.foregroundMuted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 28)
                                .accessibilityIdentifier("builder_v3_exercise_empty")
                        }
                    }
                }

                if !trimmedQuery.isEmpty, !hasExactMatch {
                    Button {
                        // Select only — batch footer commits via onAddExercises (no double-add).
                        if !selectedNames.contains(trimmedQuery) {
                            selectedNames.append(trimmedQuery)
                        }
                        if !createdItems.contains(where: { $0.name == trimmedQuery }) {
                            createdItems.append(
                                BuilderV3ExerciseItem(
                                    name: trimmedQuery,
                                    muscle: "Custom",
                                    equipmentKey: nil,
                                    equipmentLabel: "Bodyweight"
                                )
                            )
                        }
                        query = ""
                    } label: {
                        Text("＋ Create “\(trimmedQuery)”")
                            .ddDisplayText(12.5, weight: .bold)
                            .foregroundColor(DailyDriver.lime)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("builder_v3_create_exercise")
                }
            }
        }
        .frame(maxHeight: 360)
    }

    private var categoryGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            ForEach(BuilderV3BrowseCategory.allCases) { category in
                Button {
                    selectedCategory = category
                    muscleFilter = nil
                    equipmentFilter = nil
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: category.systemImage)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(DailyDriver.lime)
                        Text(category.displayName)
                            .ddDisplayText(12.5, weight: .bold)
                            .foregroundColor(DailyDriver.foreground)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(DailyDriver.card2)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("builder_v3_category_\(category.rawValue)")
            }
        }
        .padding(.vertical, 12)
    }

    private func categoryHeader(_ category: BuilderV3BrowseCategory) -> some View {
        Button {
            selectedCategory = nil
            muscleFilter = nil
            equipmentFilter = nil
            fetchMode = nil
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                Text(category.displayName)
                    .ddDisplayText(12.5, weight: .bold)
                Spacer()
                Text("Categories")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(DailyDriver.foregroundMuted)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("builder_v3_category_back")
    }

    private func exerciseRow(_ item: BuilderV3ExerciseItem) -> some View {
        let isSelected = selectedNames.contains(item.name)
        let inGym = BuilderV3GymOverlay.isInGym(equipmentKey: item.equipmentKey, availableKeys: availableEquipmentKeys)
        return Button {
            if let index = selectedNames.firstIndex(of: item.name) {
                selectedNames.remove(at: index)
            } else {
                selectedNames.append(item.name)
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? DailyDriver.lime : DailyDriver.foregroundDim)
                    .accessibilityIdentifier("builder_v3_exercise_checkbox_\(item.name)")
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(DailyDriver.foreground)
                    Text(exerciseMetaLine(item, inGym: inGym))
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundColor(inGym ? DailyDriver.foregroundDim : DailyDriver.amber)
                }
                Spacer()
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("builder_v3_exercise_row_\(item.name)")
    }

    private func exerciseMetaLine(_ item: BuilderV3ExerciseItem, inGym: Bool) -> String {
        let base = "\(item.muscle.uppercased()) · \(item.equipmentLabel.uppercased())"
        return inGym ? base : "\(base) — NOT IN YOUR GYM"
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Text(
                formatLabel.map { "Selected exercises land straight into the \($0)." }
                    ?? "Added as 3 × 10 · 60s rest — tap the card after to change anything."
            )
            .font(.system(size: 10))
            .foregroundColor(DailyDriver.foregroundDim)
            .frame(maxWidth: .infinity)

            Button {
                let names = selectedNames
                onAddExercises(names)
                selectedNames.removeAll()
                createdItems.removeAll()
                onDone()
            } label: {
                Text(selectedNames.isEmpty ? "Add exercises" : "Add \(selectedNames.count) exercise\(selectedNames.count == 1 ? "" : "s")")
                    .ddDisplayText(14, weight: .bold)
                    .foregroundColor(DailyDriver.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(selectedNames.isEmpty ? DailyDriver.card2 : DailyDriver.lime)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(selectedNames.isEmpty)
            .accessibilityIdentifier("builder_v3_add_exercises_button")
        }
        .padding(.top, 10)
    }

    private func loadExercises() async {
        let requestedKey = loadKey
        guard tab == .all else {
            fetchMode = nil
            isLoading = false
            return
        }

        if !trimmedQuery.isEmpty {
            do {
                try await Task.sleep(for: .milliseconds(220))
                try Task.checkCancellation()
            } catch {
                return
            }
        } else if selectedCategory == nil {
            searchResults = []
            fetchMode = nil
            isLoading = false
            return
        }

        fetchMode = nil
        isLoading = true
        let result: BuilderV3ExerciseFetchResult
        if !trimmedQuery.isEmpty {
            result = await searchClient.search(query: trimmedQuery)
        } else if let selectedCategory {
            result = await searchClient.list(
                category: selectedCategory.queryValue,
                muscle: selectedCategory == .strength ? muscleFilter : nil,
                equipment: selectedCategory == .cardio ? equipmentFilter : nil,
                limit: 40,
                offset: 0
            )
        } else {
            return
        }

        guard !Task.isCancelled, requestedKey == loadKey else { return }
        searchResults = result.items
        fetchMode = result.mode
        isLoading = false
    }
}

/// Applies an accessibility identifier only when one is provided — keeps the
/// "All muscles" / "All equipment" reset chips un-tagged without branching views.
private struct OptionalAccessibilityId: ViewModifier {
    let id: String?

    func body(content: Content) -> some View {
        if let id {
            content.accessibilityIdentifier(id)
        } else {
            content
        }
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
