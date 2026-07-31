//
//  WorkoutEditorViewModel.swift
//  AmakaFlow
//
//  ViewModel for creating and editing workouts (AMA-1232)
//

import Combine
import Foundation
import SwiftUI

@MainActor
class WorkoutEditorViewModel: ObservableObject {
    // MARK: - Published State

    @Published var name: String = ""
    @Published var sport: WorkoutSport = .strength
    @Published var intervals: [WorkoutSaveInterval] = []
    /// ADR-017 blocks (+ structure_source) when saving from Editor v2 / clarify.
    @Published var saveBlocks: [SocialImportBlock]?
    /// AMA-2336 — enrichment deletes from the editor, persisted with the workout.
    /// `nil` = omit (don't rewrite server tombstones); `[]` = clear them.
    @Published var saveEnrichmentTombstones: [EnrichmentTombstone]?
    @Published var canonicalId: String?
    @Published var canonicalSource: CanonicalSource?
    @Published var isSaving: Bool = false
    @Published var errorMessage: String?
    @Published var didSave: Bool = false

    // MARK: - Private

    private let dependencies: AppDependencies
    private let existingWorkoutId: String?
    private let preservedSource: String?
    private let preservedSourceUrl: String?
    private let preservedDescription: String?
    private let preservedCreatorName: String?

    /// All sport types available in the picker
    static let sportOptions: [(WorkoutSport, String)] = [
        (.strength, "Strength"),
        (.running, "Running"),
        (.cycling, "Cycling"),
        (.cardio, "HIIT / Cardio"),
        (.mobility, "Yoga / Mobility"),
        (.swimming, "Swimming"),
        (.other, "Other")
    ]

    // MARK: - Init

    /// Create mode — empty workout
    init(dependencies: AppDependencies = .current) {
        self.dependencies = dependencies
        self.existingWorkoutId = nil
        self.preservedSource = nil
        self.preservedSourceUrl = nil
        self.preservedDescription = nil
        self.preservedCreatorName = nil
    }

    /// Edit mode — populate from existing workout
    init(workout: Workout, dependencies: AppDependencies = .current) {
        self.dependencies = dependencies
        self.existingWorkoutId = workout.id
        self.preservedSource = workout.source.rawValue
        self.preservedSourceUrl = workout.sourceUrl
        self.preservedDescription = workout.description
        self.preservedCreatorName = workout.creatorName
        self.name = workout.name
        self.sport = workout.sport
        self.canonicalId = workout.canonicalId
        self.canonicalSource = workout.canonicalSource
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
            case .repeat:
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

    /// Save workout to backend via POST /workouts/save (mapper body + workout_id on edit).
    func save() async {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Workout name is required"
            return
        }

        isSaving = true
        errorMessage = nil

        let source = (preservedSource?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
            $0.isEmpty ? nil : $0
        } ?? WorkoutSource.manual.rawValue

        let request = WorkoutSaveRequest(
            name: name.trimmingCharacters(in: .whitespaces),
            sport: sport.rawValue,
            intervals: intervals.filter { interval in
                // Remove empty/incomplete intervals
                if interval.type == "reps" {
                    return !(interval.name ?? "").trimmingCharacters(in: .whitespaces).isEmpty
                }
                return true
            },
            source: source,
            sourceUrl: preservedSourceUrl,
            description: preservedDescription,
            creatorName: preservedCreatorName,
            blocks: saveBlocks,
            workoutId: existingWorkoutId,
            enrichmentTombstones: saveEnrichmentTombstones,
            canonicalId: canonicalId,
            canonicalSource: canonicalSource
        )

        do {
            let saved = try await dependencies.apiService.saveWorkout(request)
            // Library detail merges a local block cache over interval-only GET payloads.
            // Without this, reorder/edit saves look like they "didn't stick".
            switch WorkoutLibraryDetailStore.saveAfterEditor(saved: saved, request: request) {
            case .success:
                break
            case .failure(let error):
                print("[WorkoutEditorVM] Detail cache update failed: \(error)")
            }
            print("[WorkoutEditorVM] Workout saved successfully: \(request.name) id=\(saved.id)")
            // AMA-2359 — Library list only refreshes via `.libraryContentDidChange`
            // (on `.task`/onReceive, not a shared store). Post here so a create/edit
            // save is visible immediately without tabbing away and back.
            NotificationCenter.default.post(name: .libraryContentDidChange, object: nil)
            didSave = true
        } catch {
            print("[WorkoutEditorVM] Save failed: \(error.localizedDescription)")
            errorMessage = "Failed to save workout: \(error.localizedDescription)"
        }

        isSaving = false
    }
}
