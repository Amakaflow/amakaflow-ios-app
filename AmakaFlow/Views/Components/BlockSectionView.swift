//
//  BlockSectionView.swift
//  AmakaFlow
//
//  Block section showing header, exercises, and rest info
//

import SwiftUI

struct BlockSectionView: View {
    let block: Block
    let blockIndex: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: Theme.Spacing.sm) {
                Text({
                    if let trimmed = block.label?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !trimmed.isEmpty {
                        return trimmed
                    }
                    return "Block \(blockIndex + 1)"
                }())
                    .font(.headline)
                    .foregroundColor(Theme.Colors.textPrimary)

                // Structure badge
                Text(block.structure.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(badgeColor)
                    .clipShape(Capsule())

                if block.rounds > 1 {
                    Text("\(block.rounds) rounds")
                        .font(.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)

            Divider()
                .background(Theme.Colors.borderLight)

            // Exercises
            let showSuperset = block.structure == .superset
            ForEach(Array(block.exercises.enumerated()), id: \.element.id) { index, exercise in
                ExerciseRowView(exercise: exercise, showSupersetIndicator: showSuperset)

                if index < block.exercises.count - 1 {
                    Divider()
                        .background(Theme.Colors.borderLight)
                        .padding(.leading, showSuperset ? (Theme.Spacing.md + 3 + Theme.Spacing.sm) : Theme.Spacing.md)
                }
            }

            // Footer: rest info
            if let restSec = block.restBetweenSeconds, restSec > 0 {
                Divider()
                    .background(Theme.Colors.borderLight)

                HStack(spacing: 4) {
                    Image(systemName: "pause.circle")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.Colors.textSecondary)
                    Text(block.rounds > 1
                         ? "\(restSec)s rest between rounds"
                         : "\(restSec)s rest between exercises")
                        .font(.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
            }
        }
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.lg)
    }

    private var badgeColor: Color {
        switch block.structure {
        case .straight: return .green
        case .superset: return .blue
        case .circuit: return .orange
        case .amrap: return .red
        case .emom: return .purple
        case .tabata: return .pink
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 12) {
            BlockSectionView(
                block: Block(
                    label: "Upper Body",
                    structure: .superset,
                    rounds: 3,
                    exercises: [
                        Exercise(name: "Bench Press", canonicalName: nil, sets: 3, reps: "8",
                                 durationSeconds: nil, load: ExerciseLoad(value: 80, unit: "kg"),
                                 restSeconds: nil, distance: nil, notes: nil, supersetGroup: 1),
                        Exercise(name: "Bent-Over Row", canonicalName: nil, sets: 3, reps: "8",
                                 durationSeconds: nil, load: ExerciseLoad(value: 70, unit: "kg"),
                                 restSeconds: 60, distance: nil, notes: nil, supersetGroup: 1)
                    ],
                    restBetweenSeconds: 90
                ),
                blockIndex: 0
            )

            BlockSectionView(
                block: Block(
                    label: nil,
                    structure: .amrap,
                    rounds: 1,
                    exercises: [
                        Exercise(name: "Air Squat", canonicalName: nil, sets: nil, reps: "20",
                                 durationSeconds: nil, load: nil, restSeconds: nil, distance: nil, notes: nil, supersetGroup: nil),
                        Exercise(name: "Push-Up", canonicalName: nil, sets: nil, reps: "15",
                                 durationSeconds: nil, load: nil, restSeconds: nil, distance: nil, notes: nil, supersetGroup: nil),
                        Exercise(name: "Sit-Up", canonicalName: nil, sets: nil, reps: "20",
                                 durationSeconds: nil, load: nil, restSeconds: nil, distance: nil, notes: nil, supersetGroup: nil)
                    ],
                    restBetweenSeconds: nil
                ),
                blockIndex: 1
            )
        }
        .padding()
    }
    .background(Theme.Colors.background)
    .preferredColorScheme(.dark)
}
