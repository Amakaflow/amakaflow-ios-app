//
//  BuilderV3ExercisePickerSheet+Content.swift
//  AmakaFlow
//
//  AMA-2384 / AMA-2443 slice 2b — results list, rows, and fetch helpers.
//

import SwiftUI

extension BuilderV3ExercisePickerSheet {
    var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if tab == .all, trimmedQuery.isEmpty, selectedCategory == nil {
                    // Show suggestions above category grid (feature 1)
                    if !suggestedExercises.isEmpty, case .add = mode {
                        suggestedSection
                    }
                    categoryGrid
                        .drillInTransition()
                } else {
                    if tab == .all, trimmedQuery.isEmpty, let selectedCategory {
                        categoryHeader(selectedCategory)
                            .drillInTransition()
                    }

                    if isLoading {
                        ProgressView()
                            .tint(DailyDriver.lime)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    } else {
                        ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                            exerciseRow(item)
                                .staggeredReveal(index: index, generation: revealGeneration)
                                .onAppear {
                                    guard item.id == filteredItems.last?.id else { return }
                                    Task { await loadNextPage() }
                                }
                            Divider().background(DailyDriver.border)
                        }

                        if isLoadingNextPage {
                            ProgressView()
                                .tint(DailyDriver.lime)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .accessibilityIdentifier("builder_v3_exercise_loading_more")
                        }

                        if filteredItems.isEmpty, trimmedQuery.isEmpty {
                            Text("No exercises found in this category.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(DailyDriver.foregroundMuted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 28)
                                .accessibilityIdentifier("builder_v3_exercise_empty")
                        }
                        
                        // Did-you-mean empty state (feature 4)
                        if filteredItems.isEmpty, !trimmedQuery.isEmpty, let suggestion = didYouMeanResult {
                            didYouMeanView(suggestion: suggestion)
                        }
                    }
                }

                if !trimmedQuery.isEmpty, !hasExactMatch {
                    Button {
                        // Select only — batch footer commits via onAddExercises (no double-add).
                        // Keep the query so the new row stays visible with a checkmark; chips also pin it.
                        toggleSelection(trimmedQuery)
                        if !createdItems.contains(where: {
                            $0.name.caseInsensitiveCompare(trimmedQuery) == .orderedSame
                        }) {
                            createdItems.append(
                                BuilderV3ExerciseItem(
                                    name: trimmedQuery,
                                    muscle: "Custom",
                                    equipmentKey: nil,
                                    equipmentLabel: "Custom"
                                )
                            )
                        }
                        // In replace mode, auto-commit on create
                        if case .replace = mode {
                            onAddExercises([trimmedQuery])
                            selectedNames.removeAll()
                            createdItems.removeAll()
                            onDone()
                        }
                    } label: {
                        Text(
                            isSelected(trimmedQuery)
                                ? "✓ “\(trimmedQuery)” selected"
                                : "＋ Create “\(trimmedQuery)”"
                        )
                            .ddDisplayText(12.5, weight: .bold)
                            .foregroundColor(DailyDriver.lime)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("builder_v3_create_exercise")
                }
                
                // Ask Amaka button in empty state (feature 5)
                if !trimmedQuery.isEmpty, filteredItems.isEmpty, onAskAmaka != nil {
                    Button {
                        onAskAmaka?(trimmedQuery)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Ask Amaka")
                                .ddDisplayText(12.5, weight: .bold)
                        }
                        .foregroundColor(DailyDriver.foreground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("builder_v3_ask_amaka")
                }
            }
        }
        .frame(maxHeight: 360)
    }
    
    @ViewBuilder
    private var suggestedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggested for this workout")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(DailyDriver.foregroundMuted)
                .padding(.horizontal, 2)
            
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                ForEach(Array(suggestedExercises.enumerated()), id: \.element.id) { index, item in
                    Button {
                        toggleSelection(item.name)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: isSelected(item.name) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(isSelected(item.name) ? DailyDriver.lime : DailyDriver.foregroundDim)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundColor(DailyDriver.foreground)
                                    .lineLimit(1)
                                Text(item.equipmentLabel.uppercased())
                                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                                    .foregroundColor(DailyDriver.foregroundDim)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(DailyDriver.card2)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("builder_v3_suggested_\(item.name)")
                    .staggeredReveal(index: index, generation: revealGeneration)
                }
            }
        }
        .padding(.vertical, 12)
        .accessibilityIdentifier("builder_v3_suggested_section")
        
        Divider().background(DailyDriver.border)
    }
    
    private func didYouMeanView(suggestion: String) -> some View {
        Button {
            query = suggestion
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 12, weight: .semibold))
                Text("Did you mean ")
                    .font(.system(size: 11.5, weight: .medium))
                    + Text(suggestion)
                    .font(.system(size: 11.5, weight: .bold))
                    + Text("?")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundColor(DailyDriver.amber)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("builder_v3_did_you_mean")
    }

    var categoryGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            ForEach(BuilderV3BrowseCategory.allCases) { category in
                Button {
                    withAnimation(MotionTokens.easeOutQuart(duration: MotionTokens.base)) {
                        selectedCategory = category
                        muscleFilter = nil
                        equipmentFilter = nil
                    }
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

    func categoryHeader(_ category: BuilderV3BrowseCategory) -> some View {
        Button {
            withAnimation(MotionTokens.easeOutQuart(duration: MotionTokens.base)) {
                selectedCategory = nil
                muscleFilter = nil
                equipmentFilter = nil
                fetchMode = nil
            }
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

    func exerciseRow(_ item: BuilderV3ExerciseItem) -> some View {
        let selected = isSelected(item.name)
        let inGym = BuilderV3GymOverlay.isInGym(equipmentKey: item.equipmentKey, availableKeys: availableEquipmentKeys)
        return Button {
            toggleSelection(item.name)
            // In replace mode, auto-commit on new selection (not deselection)
            if case .replace = mode, !selected {
                onAddExercises([item.name])
                selectedNames.removeAll()
                createdItems.removeAll()
                onDone()
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(selected ? DailyDriver.lime : DailyDriver.foregroundDim)
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

    func exerciseMetaLine(_ item: BuilderV3ExerciseItem, inGym: Bool) -> String {
        let base = "\(item.muscle.uppercased()) · \(item.equipmentLabel.uppercased())"
        return inGym ? base : "\(base) — NOT IN YOUR GYM"
    }

    var footer: some View {
        VStack(spacing: 10) {
            Text(footerHintText)
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
                Text(footerButtonText)
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
    
    private var footerHintText: String {
        switch mode {
        case .add:
            return formatLabel.map { "Selected exercises land straight into the \($0)." }
                ?? "Added as 3 × 10 · 60s rest — tap the card after to change anything."
        case .replace:
            return "Numbers and prescription carry over — only the name changes."
        }
    }
    
    private var footerButtonText: String {
        switch mode {
        case .add:
            return selectedNames.isEmpty ? "Add exercises" : "Add \(selectedNames.count) exercise\(selectedNames.count == 1 ? "" : "s")"
        case .replace:
            return selectedNames.isEmpty ? "Replace exercise" : "Replace with \(selectedNames.first ?? "")"
        }
    }

    func loadExercises() async {
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
        isLoadingNextPage = false
        canLoadMore = false
        nextOffset = 0
        let result: BuilderV3ExerciseFetchResult
        if !trimmedQuery.isEmpty {
            result = await searchClient.search(query: trimmedQuery)
        } else if let selectedCategory {
            result = await searchClient.list(
                category: selectedCategory.queryValue,
                muscle: selectedCategory == .strength ? muscleFilter : nil,
                equipment: selectedCategory == .cardio ? equipmentFilter : nil,
                limit: Self.browsePageSize,
                offset: 0
            )
        } else {
            return
        }

        guard !Task.isCancelled, requestedKey == loadKey else { return }
        searchResults = result.items
        fetchMode = result.mode
        canLoadMore = (
            trimmedQuery.isEmpty
                && result.mode == .live
                && result.receivedRowCount == Self.browsePageSize
        )
        nextOffset = result.receivedRowCount
        isLoading = false
    }

    func loadNextPage() async {
        guard
            tab == .all,
            trimmedQuery.isEmpty,
            let selectedCategory,
            fetchMode == .live,
            canLoadMore,
            !isLoadingNextPage
        else {
            return
        }

        let requestedKey = loadKey
        let requestedOffset = nextOffset
        isLoadingNextPage = true
        defer { isLoadingNextPage = false }

        let result = await searchClient.list(
            category: selectedCategory.queryValue,
            muscle: selectedCategory == .strength ? muscleFilter : nil,
            equipment: selectedCategory == .cardio ? equipmentFilter : nil,
            limit: Self.browsePageSize,
            offset: requestedOffset
        )
        guard !Task.isCancelled, requestedKey == loadKey else { return }
        guard result.mode == .live else {
            // Keep existing LIVE rows; stop paging instead of flipping the badge to MOCK.
            canLoadMore = false
            return
        }

        let existingIDs = Set(searchResults.map(\.id))
        searchResults.append(contentsOf: result.items.filter { !existingIDs.contains($0.id) })
        nextOffset = requestedOffset + result.receivedRowCount
        canLoadMore = result.receivedRowCount == Self.browsePageSize
    }
}

/// Applies an accessibility identifier only when one is provided — keeps the
/// "All muscles" / "All equipment" reset chips un-tagged without branching views.
struct OptionalAccessibilityId: ViewModifier {
    let id: String?

    func body(content: Content) -> some View {
        if let id {
            content.accessibilityIdentifier(id)
        } else {
            content
        }
    }
}
