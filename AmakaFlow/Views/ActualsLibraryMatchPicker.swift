//
//  ActualsLibraryMatchPicker.swift
//  AmakaFlow
//
//  AMA-2396: "Search all workouts" — pick any Library workout as the Map match.
//

import SwiftUI

struct ActualsLibraryMatchPicker: View {
    let candidates: [ActualsPlanCandidate]
    var onPick: (ActualsPlanCandidate) -> Void
    var onCancel: () -> Void

    @State private var query = ""

    private var filtered: [ActualsPlanCandidate] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return candidates }
        return candidates.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if filtered.isEmpty {
                    Text("No workouts match")
                        .foregroundColor(DailyDriver.foregroundMuted)
                } else {
                    ForEach(filtered) { candidate in
                        Button {
                            onPick(candidate)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(candidate.title)
                                    .ddDisplayText(14, weight: .bold)
                                    .foregroundColor(DailyDriver.foreground)
                                Text(metaLine(for: candidate))
                                    .font(.system(size: 8.5, design: .monospaced))
                                    .foregroundColor(DailyDriver.foregroundDim)
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(DailyDriver.card)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(DailyDriver.screenBackground.ignoresSafeArea())
            .searchable(text: $query, prompt: "Search Library")
            .navigationTitle("Match a workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .foregroundColor(DailyDriver.lime)
                }
            }
            .preferredColorScheme(.dark)
        }
        .accessibilityIdentifier("af_actuals_library_match_picker")
    }

    private func metaLine(for candidate: ActualsPlanCandidate) -> String {
        let minutes: String = {
            guard let seconds = candidate.durationSeconds, seconds > 0 else { return "—" }
            return "\(max(1, Int((seconds / 60).rounded()))) MIN"
        }()
        return "\(candidate.sourceLabel) · \(minutes) · \(candidate.type.rawValue.uppercased())"
    }
}
