//
//  WorkoutTypePresetPicker.swift
//  AmakaFlow
//
//  Create-with-AI entry point backed by the canonical ai_preset subset.
//

import SwiftUI

struct WorkoutTypePresetPicker: View {
    let apiService: any APIServiceProviding
    let onPick: (WorkoutTypeItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var presets: [WorkoutTypeItem] = []
    @State private var isLoading = true
    @State private var loadFailed = false

    private var categories: [PresetCategory] {
        let grouped = Dictionary(grouping: presets, by: \.category)
        return grouped.map { category, items in
            PresetCategory(
                category: category,
                items: items.sorted {
                    $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
            )
        }
        .sorted {
            $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading workout ideas…")
                        .tint(DailyDriver.foregroundMuted)
                        .foregroundStyle(DailyDriver.foregroundMuted)
                } else if loadFailed {
                    unavailableState
                } else if categories.isEmpty {
                    emptyState
                } else {
                    presetList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DailyDriver.screenBackground.ignoresSafeArea())
            .navigationTitle("Create with AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DailyDriver.foregroundMuted)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await loadPresets() }
        .accessibilityIdentifier("workout_type_preset_picker")
    }

    private var presetList: some View {
        List {
            ForEach(categories) { category in
                Section(category.label) {
                    ForEach(category.items, id: \.id) { preset in
                        Button {
                            onPick(preset)
                        } label: {
                            HStack {
                                Text(preset.displayName)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(DailyDriver.foreground)
                                Spacer()
                                Image(systemName: "sparkles")
                                    .foregroundStyle(DailyDriver.lime)
                            }
                        }
                        .accessibilityIdentifier("workout_type_preset_\(preset.id)")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
    }

    private var unavailableState: some View {
        VStack(spacing: 12) {
            Text("Workout ideas are unavailable right now.")
                .foregroundStyle(DailyDriver.foregroundMuted)
            Button("Try again") {
                Task { await loadPresets() }
            }
            .buttonStyle(.borderedProminent)
            .tint(DailyDriver.lime)
        }
        .padding(24)
    }

    private var emptyState: some View {
        Text("No AI workout presets are available.")
            .foregroundStyle(DailyDriver.foregroundMuted)
            .padding(24)
    }

    private func loadPresets() async {
        isLoading = true
        loadFailed = false
        do {
            presets = try await apiService.fetchWorkoutTypes(aiPresetOnly: true)
                .filter(\.aiPreset)
            loadFailed = false
        } catch {
            loadFailed = true
        }
        isLoading = false
    }
}

private struct PresetCategory: Identifiable {
    let category: String
    let items: [WorkoutTypeItem]

    var id: String { category }

    var label: String {
        switch category.lowercased() {
        case "run", "running":
            return "Run"
        case "strength":
            return "Strength"
        case "mobility":
            return "Mobility"
        case "cycle", "cycling":
            return "Cycling"
        case "swim", "swimming":
            return "Swimming"
        default:
            return category.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
