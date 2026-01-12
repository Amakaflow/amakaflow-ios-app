//
//  ExecutionLogSection.swift
//  AmakaFlow
//
//  Displays actual workout execution data with sets, reps, time, and weights.
//  Part of AMA-292: Display Execution Log UI
//

import SwiftUI

struct ExecutionLogSection: View {
    let intervals: [ExecutionLogInterval]
    let summary: ExecutionLogSummary?

    /// Group intervals by exercise (filter out rest intervals)
    private var exerciseGroups: [ExerciseGroup] {
        var groups: [ExerciseGroup] = []
        var currentExercise: String?
        var currentSets: [SetDisplayItem] = []
        var exerciseIndex = 0

        for interval in intervals {
            // Skip rest intervals and warmup/cooldown without sets
            guard interval.plannedKind == "reps" || (interval.sets != nil && !interval.sets!.isEmpty) else {
                continue
            }

            let exerciseName = interval.plannedName ?? "Exercise"

            // Check if this is a new exercise
            if exerciseName != currentExercise {
                // Save previous group if exists
                if let name = currentExercise, !currentSets.isEmpty {
                    exerciseIndex += 1
                    groups.append(ExerciseGroup(
                        index: exerciseIndex,
                        name: name,
                        sets: currentSets
                    ))
                }
                currentExercise = exerciseName
                currentSets = []
            }

            // Add sets from this interval
            if let sets = interval.sets {
                for set in sets {
                    currentSets.append(SetDisplayItem(
                        setNumber: currentSets.count + 1,
                        reps: set.repsCompleted,
                        time: formatTime(interval.actualDurationSeconds),
                        weight: set.weight?.displayLabel ?? formatWeight(set.weight),
                        status: set.status,
                        skipReason: interval.skipReason
                    ))
                }
            } else {
                // Interval without sets (skipped or incomplete)
                currentSets.append(SetDisplayItem(
                    setNumber: currentSets.count + 1,
                    reps: nil,
                    time: nil,
                    weight: nil,
                    status: interval.status,
                    skipReason: interval.skipReason
                ))
            }
        }

        // Don't forget the last group
        if let name = currentExercise, !currentSets.isEmpty {
            exerciseIndex += 1
            groups.append(ExerciseGroup(
                index: exerciseIndex,
                name: name,
                sets: currentSets
            ))
        }

        return groups
    }

    private var totalSetsCount: Int {
        summary?.totalSets ?? exerciseGroups.reduce(0) { $0 + $1.sets.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with total sets
            HStack {
                Text("EXERCISES")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(totalSetsCount) sets total")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Column headers
            columnHeaders

            if exerciseGroups.isEmpty {
                emptyState
            } else {
                // Exercise rows
                VStack(spacing: 0) {
                    ForEach(exerciseGroups, id: \.index) { group in
                        exerciseSection(group)
                    }
                }
            }
        }
        .padding()
        .background(Theme.Colors.surface)
        .cornerRadius(12)
    }

    // MARK: - Column Headers

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            Text("SET")
                .frame(width: 36, alignment: .leading)

            Text("REPS")
                .frame(width: 60, alignment: .leading)

            Text("TIME")
                .frame(width: 50, alignment: .leading)

            Spacer()

            Text("WEIGHT")
                .frame(width: 70, alignment: .trailing)
        }
        .font(.caption2)
        .fontWeight(.semibold)
        .foregroundColor(.secondary.opacity(0.7))
        .padding(.bottom, 8)
    }

    // MARK: - Exercise Section

    private func exerciseSection(_ group: ExerciseGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Exercise header with number badge
            HStack(spacing: 8) {
                // Numbered badge
                Text("\(group.index)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(width: 22, height: 22)
                    .background(exerciseBadgeColor(for: group.index))
                    .clipShape(Circle())

                Text(group.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Spacer()
            }
            .padding(.top, 12)

            // Set rows
            ForEach(group.sets, id: \.setNumber) { set in
                setRow(set)
            }
        }
    }

    // MARK: - Set Row

    private func setRow(_ set: SetDisplayItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                // Set number
                Text("Set \(set.setNumber)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 36, alignment: .leading)

                // Reps
                if let reps = set.reps {
                    Text("\(reps) reps")
                        .font(.caption)
                        .foregroundColor(.primary)
                        .frame(width: 60, alignment: .leading)
                } else {
                    Text("— reps")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 60, alignment: .leading)
                }

                // Time
                if let time = set.time {
                    Text(time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .leading)
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .leading)
                }

                Spacer()

                // Weight
                if let weight = set.weight, !weight.isEmpty {
                    Text(weight)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(Theme.Colors.accentGreen)
                } else if set.status == "skipped" {
                    Text("—")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else {
                    Text("Body")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Status icon
                statusIcon(set.status)
                    .padding(.leading, 8)
            }

            // Skip reason if applicable
            if set.status == "skipped", let reason = set.skipReason {
                Text(formatSkipReason(reason))
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .padding(.leading, 36)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Status Icon

    private func statusIcon(_ status: String) -> some View {
        Group {
            switch status {
            case "completed":
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case "skipped":
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.orange)
            default:
                Image(systemName: "minus.circle")
                    .foregroundColor(.gray)
            }
        }
        .font(.caption)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.bullet.clipboard")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("No exercise data recorded")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Helpers

    private func exerciseBadgeColor(for index: Int) -> Color {
        let colors: [Color] = [
            Theme.Colors.accentGreen,
            Theme.Colors.accentBlue,
            .orange,
            .purple,
            .pink,
            .cyan
        ]
        return colors[(index - 1) % colors.count]
    }

    private func formatTime(_ seconds: Int?) -> String? {
        guard let seconds = seconds, seconds > 0 else { return nil }
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func formatWeight(_ weight: ExecutionLogWeight?) -> String? {
        guard let weight = weight,
              let components = weight.components,
              let first = components.first else {
            return nil
        }
        return "\(Int(first.value)) \(first.unit)"
    }

    private func formatSkipReason(_ reason: String) -> String {
        switch reason {
        case "fatigue": return "Too tired"
        case "time_constraint": return "Running out of time"
        case "equipment_unavailable": return "Equipment unavailable"
        case "pain": return "Pain/discomfort"
        default: return reason.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

// MARK: - Supporting Types

private struct ExerciseGroup {
    let index: Int
    let name: String
    let sets: [SetDisplayItem]
}

private struct SetDisplayItem {
    let setNumber: Int
    let reps: Int?
    let time: String?
    let weight: String?
    let status: String
    let skipReason: String?
}

// MARK: - Sample Data (for when no real execution log exists)

extension ExecutionLogSection {
    /// Sample intervals matching the target design
    static var sampleIntervals: [ExecutionLogInterval] {
        [
            // Incline Smith Machine Press - 4 sets
            ExecutionLogInterval(intervalIndex: 0, plannedKind: "reps", plannedName: "Incline Smith Machine Press", status: "completed", plannedDurationSeconds: nil, actualDurationSeconds: 69, startedAt: nil, endedAt: nil, skipReason: nil,
                sets: [ExecutionLogSet(setNumber: 1, status: "completed", repsPlanned: 12, repsCompleted: 12, weight: ExecutionLogWeight(components: [ExecutionLogWeightComponent(source: "machine", value: 35, unit: "lbs")], displayLabel: "35 lbs"), durationSeconds: 69, rpe: nil)]),
            ExecutionLogInterval(intervalIndex: 1, plannedKind: "reps", plannedName: "Incline Smith Machine Press", status: "completed", plannedDurationSeconds: nil, actualDurationSeconds: 51, startedAt: nil, endedAt: nil, skipReason: nil,
                sets: [ExecutionLogSet(setNumber: 2, status: "completed", repsPlanned: 12, repsCompleted: 12, weight: ExecutionLogWeight(components: [ExecutionLogWeightComponent(source: "machine", value: 45, unit: "lbs")], displayLabel: "45 lbs"), durationSeconds: 51, rpe: nil)]),
            ExecutionLogInterval(intervalIndex: 2, plannedKind: "reps", plannedName: "Incline Smith Machine Press", status: "completed", plannedDurationSeconds: nil, actualDurationSeconds: 88, startedAt: nil, endedAt: nil, skipReason: nil,
                sets: [ExecutionLogSet(setNumber: 3, status: "completed", repsPlanned: 10, repsCompleted: 10, weight: ExecutionLogWeight(components: [ExecutionLogWeightComponent(source: "machine", value: 55, unit: "lbs")], displayLabel: "55 lbs"), durationSeconds: 88, rpe: nil)]),
            ExecutionLogInterval(intervalIndex: 3, plannedKind: "reps", plannedName: "Incline Smith Machine Press", status: "completed", plannedDurationSeconds: nil, actualDurationSeconds: 36, startedAt: nil, endedAt: nil, skipReason: nil,
                sets: [ExecutionLogSet(setNumber: 4, status: "completed", repsPlanned: 8, repsCompleted: 8, weight: ExecutionLogWeight(components: [ExecutionLogWeightComponent(source: "machine", value: 55, unit: "lbs")], displayLabel: "55 lbs"), durationSeconds: 36, rpe: nil)]),
            // Dumbbell Lateral Raise - 3 sets
            ExecutionLogInterval(intervalIndex: 4, plannedKind: "reps", plannedName: "Dumbbell Lateral Raise", status: "completed", plannedDurationSeconds: nil, actualDurationSeconds: 45, startedAt: nil, endedAt: nil, skipReason: nil,
                sets: [ExecutionLogSet(setNumber: 1, status: "completed", repsPlanned: 15, repsCompleted: 15, weight: ExecutionLogWeight(components: [ExecutionLogWeightComponent(source: "dumbbell", value: 10, unit: "lbs")], displayLabel: "10 lbs"), durationSeconds: 45, rpe: nil)]),
            ExecutionLogInterval(intervalIndex: 5, plannedKind: "reps", plannedName: "Dumbbell Lateral Raise", status: "completed", plannedDurationSeconds: nil, actualDurationSeconds: 42, startedAt: nil, endedAt: nil, skipReason: nil,
                sets: [ExecutionLogSet(setNumber: 2, status: "completed", repsPlanned: 15, repsCompleted: 15, weight: ExecutionLogWeight(components: [ExecutionLogWeightComponent(source: "dumbbell", value: 15, unit: "lbs")], displayLabel: "15 lbs"), durationSeconds: 42, rpe: nil)]),
            ExecutionLogInterval(intervalIndex: 6, plannedKind: "reps", plannedName: "Dumbbell Lateral Raise", status: "completed", plannedDurationSeconds: nil, actualDurationSeconds: 38, startedAt: nil, endedAt: nil, skipReason: nil,
                sets: [ExecutionLogSet(setNumber: 3, status: "completed", repsPlanned: 12, repsCompleted: 12, weight: ExecutionLogWeight(components: [ExecutionLogWeightComponent(source: "dumbbell", value: 15, unit: "lbs")], displayLabel: "15 lbs"), durationSeconds: 38, rpe: nil)]),
            // Cable Fly - 1 set skipped
            ExecutionLogInterval(intervalIndex: 7, plannedKind: "reps", plannedName: "Cable Fly", status: "skipped", plannedDurationSeconds: nil, actualDurationSeconds: nil, startedAt: nil, endedAt: nil, skipReason: "equipment_unavailable", sets: nil),
            // Bench Dip - 2 sets (bodyweight)
            ExecutionLogInterval(intervalIndex: 8, plannedKind: "reps", plannedName: "Bench Dip", status: "completed", plannedDurationSeconds: nil, actualDurationSeconds: 45, startedAt: nil, endedAt: nil, skipReason: nil,
                sets: [ExecutionLogSet(setNumber: 1, status: "completed", repsPlanned: 10, repsCompleted: 7, weight: nil, durationSeconds: 45, rpe: nil)]),
            ExecutionLogInterval(intervalIndex: 9, plannedKind: "reps", plannedName: "Bench Dip", status: "completed", plannedDurationSeconds: nil, actualDurationSeconds: 44, startedAt: nil, endedAt: nil, skipReason: nil,
                sets: [ExecutionLogSet(setNumber: 2, status: "completed", repsPlanned: 10, repsCompleted: 8, weight: nil, durationSeconds: 44, rpe: nil)]),
            // Tricep Pushdown - 3 sets not reached
            ExecutionLogInterval(intervalIndex: 10, plannedKind: "reps", plannedName: "Tricep Pushdown", status: "not_reached", plannedDurationSeconds: nil, actualDurationSeconds: nil, startedAt: nil, endedAt: nil, skipReason: nil,
                sets: [ExecutionLogSet(setNumber: 1, status: "not_reached", repsPlanned: 12, repsCompleted: nil, weight: nil, durationSeconds: nil, rpe: nil)]),
            ExecutionLogInterval(intervalIndex: 11, plannedKind: "reps", plannedName: "Tricep Pushdown", status: "not_reached", plannedDurationSeconds: nil, actualDurationSeconds: nil, startedAt: nil, endedAt: nil, skipReason: nil,
                sets: [ExecutionLogSet(setNumber: 2, status: "not_reached", repsPlanned: 12, repsCompleted: nil, weight: nil, durationSeconds: nil, rpe: nil)]),
            ExecutionLogInterval(intervalIndex: 12, plannedKind: "reps", plannedName: "Tricep Pushdown", status: "not_reached", plannedDurationSeconds: nil, actualDurationSeconds: nil, startedAt: nil, endedAt: nil, skipReason: nil,
                sets: [ExecutionLogSet(setNumber: 3, status: "not_reached", repsPlanned: 12, repsCompleted: nil, weight: nil, durationSeconds: nil, rpe: nil)])
        ]
    }

    /// Sample summary matching the target design
    static var sampleSummary: ExecutionLogSummary {
        ExecutionLogSummary(
            totalIntervals: 13,
            completed: 10,
            skipped: 1,
            notReached: 3,
            completionPercentage: 75.0,
            totalSets: 22,
            setsCompleted: 18,
            setsSkipped: 4,
            totalDurationSeconds: 468,
            activeDurationSeconds: 468
        )
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            // Sample with data matching the design
            ExecutionLogSection(
                intervals: [
                    ExecutionLogInterval(
                        intervalIndex: 0,
                        plannedKind: "reps",
                        plannedName: "Incline Smith Machine Press",
                        status: "completed",
                        plannedDurationSeconds: nil,
                        actualDurationSeconds: 69,
                        startedAt: nil,
                        endedAt: nil,
                        skipReason: nil,
                        sets: [
                            ExecutionLogSet(setNumber: 1, status: "completed", repsPlanned: 12, repsCompleted: 12,
                                          weight: ExecutionLogWeight(components: [ExecutionLogWeightComponent(source: "machine", value: 35, unit: "lbs")], displayLabel: "35 lbs"),
                                          durationSeconds: 69, rpe: nil)
                        ]
                    ),
                    ExecutionLogInterval(
                        intervalIndex: 1,
                        plannedKind: "reps",
                        plannedName: "Incline Smith Machine Press",
                        status: "completed",
                        plannedDurationSeconds: nil,
                        actualDurationSeconds: 51,
                        startedAt: nil,
                        endedAt: nil,
                        skipReason: nil,
                        sets: [
                            ExecutionLogSet(setNumber: 2, status: "completed", repsPlanned: 12, repsCompleted: 12,
                                          weight: ExecutionLogWeight(components: [ExecutionLogWeightComponent(source: "machine", value: 45, unit: "lbs")], displayLabel: "45 lbs"),
                                          durationSeconds: 51, rpe: nil)
                        ]
                    ),
                    ExecutionLogInterval(
                        intervalIndex: 2,
                        plannedKind: "reps",
                        plannedName: "Incline Smith Machine Press",
                        status: "completed",
                        plannedDurationSeconds: nil,
                        actualDurationSeconds: 88,
                        startedAt: nil,
                        endedAt: nil,
                        skipReason: nil,
                        sets: [
                            ExecutionLogSet(setNumber: 3, status: "completed", repsPlanned: 10, repsCompleted: 10,
                                          weight: ExecutionLogWeight(components: [ExecutionLogWeightComponent(source: "machine", value: 55, unit: "lbs")], displayLabel: "55 lbs"),
                                          durationSeconds: 88, rpe: nil)
                        ]
                    ),
                    ExecutionLogInterval(
                        intervalIndex: 3,
                        plannedKind: "reps",
                        plannedName: "Incline Smith Machine Press",
                        status: "completed",
                        plannedDurationSeconds: nil,
                        actualDurationSeconds: 36,
                        startedAt: nil,
                        endedAt: nil,
                        skipReason: nil,
                        sets: [
                            ExecutionLogSet(setNumber: 4, status: "completed", repsPlanned: 8, repsCompleted: 8,
                                          weight: ExecutionLogWeight(components: [ExecutionLogWeightComponent(source: "machine", value: 55, unit: "lbs")], displayLabel: "55 lbs"),
                                          durationSeconds: 36, rpe: nil)
                        ]
                    ),
                    ExecutionLogInterval(
                        intervalIndex: 4,
                        plannedKind: "reps",
                        plannedName: "Dumbbell Lateral Raise",
                        status: "completed",
                        plannedDurationSeconds: nil,
                        actualDurationSeconds: 45,
                        startedAt: nil,
                        endedAt: nil,
                        skipReason: nil,
                        sets: [
                            ExecutionLogSet(setNumber: 1, status: "completed", repsPlanned: 15, repsCompleted: 15,
                                          weight: ExecutionLogWeight(components: [ExecutionLogWeightComponent(source: "dumbbell", value: 10, unit: "lbs")], displayLabel: "10 lbs"),
                                          durationSeconds: 45, rpe: nil)
                        ]
                    ),
                    ExecutionLogInterval(
                        intervalIndex: 5,
                        plannedKind: "reps",
                        plannedName: "Dumbbell Lateral Raise",
                        status: "completed",
                        plannedDurationSeconds: nil,
                        actualDurationSeconds: 45,
                        startedAt: nil,
                        endedAt: nil,
                        skipReason: nil,
                        sets: [
                            ExecutionLogSet(setNumber: 2, status: "completed", repsPlanned: 15, repsCompleted: 15,
                                          weight: ExecutionLogWeight(components: [ExecutionLogWeightComponent(source: "dumbbell", value: 15, unit: "lbs")], displayLabel: "15 lbs"),
                                          durationSeconds: 45, rpe: nil)
                        ]
                    ),
                    ExecutionLogInterval(
                        intervalIndex: 6,
                        plannedKind: "reps",
                        plannedName: "Cable Fly",
                        status: "skipped",
                        plannedDurationSeconds: nil,
                        actualDurationSeconds: nil,
                        startedAt: nil,
                        endedAt: nil,
                        skipReason: "equipment_unavailable",
                        sets: nil
                    ),
                    ExecutionLogInterval(
                        intervalIndex: 7,
                        plannedKind: "reps",
                        plannedName: "Bench Dip",
                        status: "completed",
                        plannedDurationSeconds: nil,
                        actualDurationSeconds: 45,
                        startedAt: nil,
                        endedAt: nil,
                        skipReason: nil,
                        sets: [
                            ExecutionLogSet(setNumber: 1, status: "completed", repsPlanned: 10, repsCompleted: 7,
                                          weight: nil,
                                          durationSeconds: 45, rpe: nil)
                        ]
                    ),
                    ExecutionLogInterval(
                        intervalIndex: 8,
                        plannedKind: "reps",
                        plannedName: "Bench Dip",
                        status: "completed",
                        plannedDurationSeconds: nil,
                        actualDurationSeconds: 44,
                        startedAt: nil,
                        endedAt: nil,
                        skipReason: nil,
                        sets: [
                            ExecutionLogSet(setNumber: 2, status: "completed", repsPlanned: 10, repsCompleted: 8,
                                          weight: nil,
                                          durationSeconds: 44, rpe: nil)
                        ]
                    )
                ],
                summary: ExecutionLogSummary(
                    totalIntervals: 9,
                    completed: 8,
                    skipped: 1,
                    notReached: 0,
                    completionPercentage: 89.0,
                    totalSets: 8,
                    setsCompleted: 8,
                    setsSkipped: 0,
                    totalDurationSeconds: 468,
                    activeDurationSeconds: 468
                )
            )

            // Empty state
            ExecutionLogSection(intervals: [], summary: nil)
        }
        .padding()
    }
    .background(Theme.Colors.background)
}
