//
//  PRDetectionService.swift
//  AmakaFlow
//
//  Detects personal records by comparing logged sets against stored PRs.
//  Tracks: heaviest weight (1RM), most reps at a given weight, most volume per exercise.
//  AMA-1282
//

import Foundation

// MARK: - PR Models

/// A single personal record entry
struct PersonalRecord: Codable, Identifiable, Hashable {
    let id: String
    let exerciseName: String
    let type: PRType
    let value: Double          // Weight in kg/lbs, reps count, or volume
    let reps: Int?             // Reps at which the PR was set
    let weight: Double?        // Weight at which reps PR was achieved
    let date: Date
    let workoutName: String?

    enum PRType: String, Codable, Hashable {
        case heaviestWeight   // Heaviest single lift
        case mostReps         // Most reps at a given weight
        case mostVolume       // Most total volume for an exercise in one session
    }

    var formattedValue: String {
        switch type {
        case .heaviestWeight:
            return String(format: "%.1f kg", value)
        case .mostReps:
            if let w = weight {
                return "\(Int(value)) reps @ \(String(format: "%.1f", w)) kg"
            }
            return "\(Int(value)) reps"
        case .mostVolume:
            return String(format: "%.0f kg vol", value)
        }
    }

    var typeLabel: String {
        switch type {
        case .heaviestWeight: return "Max Weight"
        case .mostReps: return "Max Reps"
        case .mostVolume: return "Max Volume"
        }
    }
}

/// Result of PR detection after a workout
struct PRDetectionResult {
    let newPRs: [NewPR]

    struct NewPR {
        let exerciseName: String
        let type: PersonalRecord.PRType
        let oldValue: Double?
        let newValue: Double
        let reps: Int?
        let weight: Double?
    }

    var hasPRs: Bool { !newPRs.isEmpty }
}

/// Represents a logged set for PR comparison
struct ExerciseSetData {
    let exerciseName: String
    let setNumber: Int
    let repsCompleted: Int
    let weightKg: Double
}

// MARK: - PR Detection Service

class PRDetectionService {

    private let storageKey = "amakaflow_personal_records"

    // MARK: - Public API

    /// Detect PRs from workout set data and persist any new records
    func detectPRs(from sets: [ExerciseSetData], workoutName: String?) -> PRDetectionResult {
        let storedPRs = loadPRs()
        var newPRs: [PRDetectionResult.NewPR] = []

        // Group sets by exercise
        let grouped = Dictionary(grouping: sets, by: { $0.exerciseName })

        for (exerciseName, exerciseSets) in grouped {
            let exercisePRs = storedPRs.filter { $0.exerciseName == exerciseName }

            // 1. Check heaviest weight
            if let heaviest = exerciseSets.max(by: { $0.weightKg < $1.weightKg }), heaviest.weightKg > 0 {
                let currentMax = exercisePRs
                    .filter { $0.type == .heaviestWeight }
                    .map { $0.value }
                    .max() ?? 0

                if heaviest.weightKg > currentMax {
                    newPRs.append(PRDetectionResult.NewPR(
                        exerciseName: exerciseName,
                        type: .heaviestWeight,
                        oldValue: currentMax > 0 ? currentMax : nil,
                        newValue: heaviest.weightKg,
                        reps: heaviest.repsCompleted,
                        weight: nil
                    ))
                }
            }

            // 2. Check most reps at heaviest weight used
            if let heaviestWeight = exerciseSets.max(by: { $0.weightKg < $1.weightKg })?.weightKg,
               heaviestWeight > 0 {
                let repsAtWeight = exerciseSets
                    .filter { $0.weightKg == heaviestWeight }
                    .map { $0.repsCompleted }
                    .max() ?? 0

                let currentMaxReps = exercisePRs
                    .filter { $0.type == .mostReps && $0.weight == heaviestWeight }
                    .map { $0.value }
                    .max() ?? 0

                if Double(repsAtWeight) > currentMaxReps && repsAtWeight > 0 {
                    newPRs.append(PRDetectionResult.NewPR(
                        exerciseName: exerciseName,
                        type: .mostReps,
                        oldValue: currentMaxReps > 0 ? currentMaxReps : nil,
                        newValue: Double(repsAtWeight),
                        reps: repsAtWeight,
                        weight: heaviestWeight
                    ))
                }
            }

            // 3. Check most volume (total reps x weight for this exercise)
            let totalVolume = exerciseSets.reduce(0.0) { $0 + Double($1.repsCompleted) * $1.weightKg }
            if totalVolume > 0 {
                let currentMaxVolume = exercisePRs
                    .filter { $0.type == .mostVolume }
                    .map { $0.value }
                    .max() ?? 0

                if totalVolume > currentMaxVolume {
                    newPRs.append(PRDetectionResult.NewPR(
                        exerciseName: exerciseName,
                        type: .mostVolume,
                        oldValue: currentMaxVolume > 0 ? currentMaxVolume : nil,
                        newValue: totalVolume,
                        reps: nil,
                        weight: nil
                    ))
                }
            }
        }

        // Persist new PRs
        if !newPRs.isEmpty {
            savePRs(newPRs: newPRs, existing: storedPRs, workoutName: workoutName)
        }

        return PRDetectionResult(newPRs: newPRs)
    }

    /// Load all stored PRs
    func loadPRs() -> [PersonalRecord] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([PersonalRecord].self, from: data)) ?? []
    }

    /// Get PRs grouped by exercise name
    func prsByExercise() -> [(exerciseName: String, records: [PersonalRecord])] {
        let prs = loadPRs()
        let grouped = Dictionary(grouping: prs, by: { $0.exerciseName })
        return grouped
            .map { (exerciseName: $0.key, records: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.exerciseName < $1.exerciseName }
    }

    // MARK: - Private

    private func savePRs(newPRs: [PRDetectionResult.NewPR], existing: [PersonalRecord], workoutName: String?) {
        var updated = existing
        let now = Date()

        for pr in newPRs {
            // Remove old PR of same type/exercise (and same weight for reps PRs)
            updated.removeAll { record in
                record.exerciseName == pr.exerciseName &&
                record.type == pr.type &&
                (pr.type != .mostReps || record.weight == pr.weight)
            }

            // Add new PR
            updated.append(PersonalRecord(
                id: UUID().uuidString,
                exerciseName: pr.exerciseName,
                type: pr.type,
                value: pr.newValue,
                reps: pr.reps,
                weight: pr.weight,
                date: now,
                workoutName: workoutName
            ))
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(updated) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
