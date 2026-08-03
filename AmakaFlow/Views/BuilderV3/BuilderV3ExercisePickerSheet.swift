//
//  BuilderV3ExercisePickerSheet.swift
//  AmakaFlow
//
//  AMA-2372 — Hevy-style multi-select exercise picker: muscle + equipment
//  chips, Recent/All tabs, amber "NOT IN YOUR GYM" marking (never hiding),
//  and "Add N exercises" batch commit. Search goes through the thin
//  `BuilderV3ExerciseSearchClient` stub (live when available, fixtures
//  otherwise) — this sheet never talks to the network directly.
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
    @State private var muscleFilter: String?
    @State private var equipmentFilter: String?
    /// Selection order is preserved (tap order → canvas order).
    @State private var selectedNames: [String] = []
    /// Custom names created from no-match search — survive filters until batch add.
    @State private var createdItems: [BuilderV3ExerciseItem] = []
    @State private var searchResults: [BuilderV3ExerciseItem] = BuilderV3ExerciseLibrary.demo
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
        baseItems.filter { item in
            if let muscleFilter, item.muscle != muscleFilter { return false }
            if let equipmentFilter {
                if equipmentFilter == "bodyweight" {
                    if item.equipmentKey != nil { return false }
                } else if item.equipmentKey != equipmentFilter {
                    return false
                }
            }
            return true
        }
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
        .task(id: query) { await runSearch() }
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
        }
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var searchField: some View {
        TextField("Search exercises...", text: $query)
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
        VStack(alignment: .leading, spacing: 6) {
            EditorV2FlowWrap {
                filterChip(label: "All muscles", isSelected: muscleFilter == nil) { muscleFilter = nil }
                ForEach(BuilderV3ExerciseLibrary.muscleFilters, id: \.self) { muscle in
                    filterChip(label: muscle, isSelected: muscleFilter == muscle, id: "builder_v3_muscle_chip_\(muscle)") {
                        muscleFilter = muscleFilter == muscle ? nil : muscle
                    }
                }
            }
            EditorV2FlowWrap {
                filterChip(label: "All equipment", isSelected: equipmentFilter == nil) { equipmentFilter = nil }
                ForEach(BuilderV3ExerciseLibrary.equipmentFilters, id: \.self) { key in
                    filterChip(
                        label: BuilderV3ExerciseLibrary.equipmentFilterLabel(key),
                        isSelected: equipmentFilter == key,
                        id: "builder_v3_equipment_chip_\(key)"
                    ) {
                        equipmentFilter = equipmentFilter == key ? nil : key
                    }
                }
            }
        }
        .padding(.top, 10)
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
                ForEach(filteredItems) { item in
                    exerciseRow(item)
                    Divider().background(DailyDriver.border)
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

    private func runSearch() async {
        guard !trimmedQuery.isEmpty else {
            searchResults = BuilderV3ExerciseLibrary.demo
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(220))
            try Task.checkCancellation()
        } catch {
            return
        }
        let results = await searchClient.search(query: trimmedQuery)
        searchResults = results
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
