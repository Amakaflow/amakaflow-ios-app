//
//  WorkoutTypeMatchSheet.swift
//  AmakaFlow
//
//  Candidate and full-catalog picker for canonical workout types.
//

import SwiftUI

struct WorkoutTypeMatchSheet: View {
    let candidates: [WorkoutTypeCandidate]
    let apiService: any APIServiceProviding
    let onPick: (String, String) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var catalog: [WorkoutTypeItem] = []
    @State private var isLoading = true
    @State private var catalogUnavailable = false

    private var searchResults: [WorkoutTypeItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return catalog }
        return catalog.filter { item in
            item.displayName.lowercased().contains(needle)
                || item.category.lowercased().contains(needle)
                || item.aliases.contains { $0.lowercased().contains(needle) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            editorV2SheetTitle("Workout type")

            TextField("Search workout types...", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(DailyDriver.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundColor(DailyDriver.foreground)
                .accessibilityIdentifier("workout_type_search")

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       !candidates.isEmpty {
                        sectionLabel("TOP MATCHES")
                        ForEach(candidates, id: \.canonicalId) { candidate in
                            choiceRow(
                                id: candidate.canonicalId,
                                displayName: candidate.displayName
                            )
                        }
                    }

                    sectionLabel(query.isEmpty ? "ALL TYPES" : "SEARCH RESULTS")

                    if isLoading {
                        ProgressView()
                            .tint(DailyDriver.foregroundMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    } else if catalogUnavailable {
                        Text("Workout types are unavailable right now.")
                            .font(.system(size: 12))
                            .foregroundColor(DailyDriver.foregroundDim)
                            .padding(.vertical, 18)
                    } else if searchResults.isEmpty {
                        Text("No workout types found.")
                            .font(.system(size: 12))
                            .foregroundColor(DailyDriver.foregroundDim)
                            .padding(.vertical, 18)
                    } else {
                        ForEach(searchResults, id: \.id) { item in
                            choiceRow(id: item.id, displayName: item.displayName)
                        }
                    }
                }
            }

            Button {
                onClear()
                dismiss()
            } label: {
                Text("Clear match")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DailyDriver.amber)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("workout_type_clear_match")
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 24)
        .background(DailyDriver.backgroundElevated)
        .preferredColorScheme(.dark)
        .task { await loadCatalog() }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(DailyDriver.foregroundDim)
            .padding(.top, 16)
            .padding(.bottom, 6)
    }

    private func choiceRow(id: String, displayName: String) -> some View {
        Button {
            onPick(id, displayName)
            dismiss()
        } label: {
            HStack {
                Text(displayName)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(DailyDriver.foreground)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(DailyDriver.foregroundDim)
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Divider().background(DailyDriver.border)
        }
        .accessibilityIdentifier("workout_type_choice_\(id)")
    }

    private func loadCatalog() async {
        do {
            catalog = try await apiService.fetchWorkoutTypes(aiPresetOnly: false)
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            catalogUnavailable = false
        } catch {
            catalogUnavailable = true
        }
        isLoading = false
    }
}
