//
//  WorkoutEditorViewModel.swift
//  AmakaFlow
//
//  ViewModel for creating and editing workouts (AMA-1232)
//

import Foundation
import Combine
import SwiftUI

@MainActor
class WorkoutEditorViewModel: ObservableObject {
    // MARK: - Published State

    @Published var name: String = ""
    @Published var sport: WorkoutSport = .strength
    @Published var intervals: [WorkoutSaveInterval] = []
    @Published var isSaving: Bool = false
    @Published var errorMessage: String?
    @Published var didSave: Bool = false

    // MARK: - Private

    private let dependencies: AppDependencies
    private let existingWorkoutId: String?

    /// All sport types available in the picker
    static let sportOptions: [(WorkoutSport, String)] = [
        (.strength, "Strength"),
        (.running, "Running"),
        (.cycling, "Cycling"),
        (.cardio, "HIIT / Cardio"),
        (.mobility, "Yoga / Mobility"),
        (.swimming, "Swimming"),
        (.other, "Other"),
    ]

    // MARK: - Init

    /// Create mode — empty workout
    init(dependencies: AppDependencies = .live) {
        self.dependencies = dependencies
        self.existingWorkoutId = nil
    }

    /// Edit mode — populate from existing workout
    init(workout: Workout, dependencies: AppDependencies = .live) {
        self.dependencies = dependencies
        self.existingWorkoutId = workout.id
        self.name = workout.name
        self.sport = workout.sport
        self.intervals = workout.intervals.map { interval in
            switch interval {
            case .warmup(let seconds, let target):
                return WorkoutSaveInterval(type: "warmup", seconds: seconds, target: target)
            case .cooldown(let seconds, let target):
                return WorkoutSaveInterval(type: "cooldown", seconds: seconds, target: target)
            case .time(let seconds, let target):
                return WorkoutSaveInterval(type: "time", seconds: seconds, target: target)
            case .reps(let sets, let reps, let name, let load, let restSec, _):
                return WorkoutSaveInterval(type: "reps", name: name, sets: sets, reps: reps, restSeconds: restSec, load: load)
            case .distance(let meters, let target):
                return WorkoutSaveInterval(type: "distance", meters: meters, target: target)
            case .rest(let seconds):
                return WorkoutSaveInterval(type: "rest", seconds: seconds)
            case .repeat(_, _):
                return WorkoutSaveInterval(type: "rest")
            }
        }
    }

    /// Whether we are editing an existing workout vs creating new
    var isEditMode: Bool { existingWorkoutId != nil }

    // MARK: - Interval Management

    /// Add a new blank reps-based interval
    func addInterval() {
        intervals.append(
            WorkoutSaveInterval(
                type: "reps",
                name: "",
                sets: 3,
                reps: 10,
                restSeconds: 60,
                load: nil
            )
        )
    }

    /// Remove interval at the given index
    func removeInterval(at offsets: IndexSet) {
        intervals.remove(atOffsets: offsets)
    }

    // MARK: - Save

    /// Save workout to backend via POST /workouts/save
    func save() async {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Workout name is required"
            return
        }

        isSaving = true
        errorMessage = nil

        let request = WorkoutSaveRequest(
            name: name.trimmingCharacters(in: .whitespaces),
            sport: sport.rawValue,
            intervals: intervals.filter { interval in
                // Remove empty/incomplete intervals
                if interval.type == "reps" {
                    return !(interval.name ?? "").trimmingCharacters(in: .whitespaces).isEmpty
                }
                return true
            }
        )

        do {
            let _ = try await dependencies.apiService.saveWorkout(request)
            print("[WorkoutEditorVM] Workout saved successfully: \(request.name)")
            didSave = true
        } catch {
            print("[WorkoutEditorVM] Save failed: \(error.localizedDescription)")
            errorMessage = "Failed to save workout: \(error.localizedDescription)"
        }

        isSaving = false
    }
}
