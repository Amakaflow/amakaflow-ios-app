//
//  DDEditorBackfillStore.swift
//  AmakaFlow
//
//  Persists profile backfill editor drafts locally until completion API exists.
//

import Foundation

enum DDEditorBackfillStore {
    private static let defaultsKey = "dd_profile_backfill_draft_v1"

    struct Payload: Codable {
        var title: String
        var savedAt: Date
        var blocks: [StoredBlock]
    }

    struct StoredBlock: Codable {
        var id: String
        var structure: String
        var label: String
        var rounds: Int
        var restBetweenRoundsSeconds: Int
        var timeCapSeconds: Int?
        var isOpen: Bool
        var exercises: [StoredExercise]
    }

    struct StoredExercise: Codable {
        var id: String
        var name: String
        var sets: Int?
        var reps: Int?
        var durationSeconds: Int?
        var distanceMeters: Int?
        var weightKg: Double?
        var calories: Int?
        var restSeconds: Int?
        var showsLastTime: Bool
        var swapMessage: String?
        var swapReplacementName: String?
    }

    static func save(title: String, blocks: [DDEditorBlockDraft]) {
        let payload = Payload(
            title: title,
            savedAt: Date(),
            blocks: blocks.map(storedBlock(from:))
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    static func load() -> Payload? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    static func loadBlocks() -> [DDEditorBlockDraft]? {
        load()?.blocks.map(blockDraft(from:))
    }

    private static func storedBlock(from block: DDEditorBlockDraft) -> StoredBlock {
        StoredBlock(
            id: block.id,
            structure: block.structure.rawValue,
            label: block.label,
            rounds: block.rounds,
            restBetweenRoundsSeconds: block.restBetweenRoundsSeconds,
            timeCapSeconds: block.timeCapSeconds,
            isOpen: block.isOpen,
            exercises: block.exercises.map(storedExercise(from:))
        )
    }

    private static func storedExercise(from exercise: DDEditorExerciseDraft) -> StoredExercise {
        StoredExercise(
            id: exercise.id,
            name: exercise.name,
            sets: exercise.sets,
            reps: exercise.reps,
            durationSeconds: exercise.durationSeconds,
            distanceMeters: exercise.distanceMeters,
            weightKg: exercise.weightKg,
            calories: exercise.calories,
            restSeconds: exercise.restSeconds,
            showsLastTime: exercise.showsLastTime,
            swapMessage: exercise.swapMessage,
            swapReplacementName: exercise.swapReplacementName
        )
    }

    private static func blockDraft(from stored: StoredBlock) -> DDEditorBlockDraft {
        DDEditorBlockDraft(
            id: stored.id,
            structure: DDEditorStructureKind(rawValue: stored.structure) ?? .sets,
            label: stored.label,
            rounds: stored.rounds,
            restBetweenRoundsSeconds: stored.restBetweenRoundsSeconds,
            timeCapSeconds: stored.timeCapSeconds,
            isOpen: stored.isOpen,
            exercises: stored.exercises.map(exerciseDraft(from:))
        )
    }

    private static func exerciseDraft(from stored: StoredExercise) -> DDEditorExerciseDraft {
        DDEditorExerciseDraft(
            id: stored.id,
            name: stored.name,
            sets: stored.sets,
            reps: stored.reps,
            durationSeconds: stored.durationSeconds,
            distanceMeters: stored.distanceMeters,
            weightKg: stored.weightKg,
            calories: stored.calories,
            restSeconds: stored.restSeconds,
            showsLastTime: stored.showsLastTime,
            swapMessage: stored.swapMessage,
            swapReplacementName: stored.swapReplacementName
        )
    }
}
