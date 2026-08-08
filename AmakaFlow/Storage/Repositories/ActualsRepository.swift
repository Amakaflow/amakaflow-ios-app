//
//  ActualsRepository.swift
//  AmakaFlow
//
//  AMA-2387: local-first fill-in actuals. Sync enqueue comes later —
//  airplane mode must not lose a verified save.
//

import Foundation
import GRDB

enum ActualsRepositoryError: LocalizedError, Equatable {
    case notReadyForVerifiedSave
    case missingRPE
    case unconfirmedRows(Int)

    var errorDescription: String? {
        switch self {
        case .notReadyForVerifiedSave:
            return "Session is not ready to verify"
        case .missingRPE:
            return "RPE required"
        case .unconfirmedRows(let count):
            return "\(count) exercises unconfirmed"
        }
    }
}

final class ActualsRepository: @unchecked Sendable {
    private let dbQueue: DatabaseQueue
    private let now: () -> Date

    init(database: AppDatabase, now: @escaping () -> Date = Date.init) {
        self.dbQueue = database.dbQueue
        self.now = now
    }

    convenience init(now: @escaping () -> Date = Date.init) {
        self.init(database: .shared, now: now)
    }

    /// Persists a fully confirmed session with RPE. Sets `verified` only for
    /// that complete payload — callers must pass `session.verified == true`.
    func saveVerifiedSession(_ session: ActualsFillInSession) throws {
        guard session.verified else {
            throw ActualsRepositoryError.notReadyForVerifiedSave
        }
        guard let rpe = session.rpe, (1...10).contains(rpe) else {
            throw ActualsRepositoryError.missingRPE
        }
        let unconfirmed = session.exercises.filter { $0.confirmation == nil }.count
        guard unconfirmed == 0, !session.exercises.isEmpty else {
            throw ActualsRepositoryError.unconfirmedRows(unconfirmed)
        }

        let timestamp = now()
        try dbQueue.write { database in
            var header = LocalActualsSession(
                id: session.id,
                title: session.title,
                subtitle: session.subtitle,
                rpe: rpe,
                verified: true,
                savedAt: timestamp,
                createdAt: timestamp
            )
            if let existing = try LocalActualsSession.fetchOne(database, key: session.id) {
                header.createdAt = existing.createdAt
            }
            try header.upsert(database)

            try LocalActualsExerciseRow
                .filter(LocalActualsExerciseRow.Columns.sessionId == session.id)
                .deleteAll(database)

            for (index, exercise) in session.exercises.enumerated() {
                guard let confirmation = exercise.confirmation else {
                    throw ActualsRepositoryError.unconfirmedRows(1)
                }
                var row = LocalActualsExerciseRow(
                    id: "\(session.id)_\(exercise.id)",
                    sessionId: session.id,
                    exerciseKey: exercise.id,
                    name: exercise.name,
                    plannedSets: exercise.planned.sets,
                    plannedReps: exercise.planned.reps,
                    plannedWeightKg: exercise.planned.weightKg,
                    plannedNote: exercise.planned.note,
                    confirmation: confirmation.rawValue,
                    actualSets: exercise.actualSets,
                    actualReps: exercise.actualReps,
                    actualWeightKg: exercise.actualWeightKg,
                    position: index
                )
                try row.insert(database)
            }
        }
    }

    func fetchSession(id: String) throws -> ActualsFillInSession? {
        try dbQueue.read { database in
            guard let header = try LocalActualsSession.fetchOne(database, key: id) else {
                return nil
            }
            let rows = try LocalActualsExerciseRow
                .filter(LocalActualsExerciseRow.Columns.sessionId == id)
                .order(LocalActualsExerciseRow.Columns.position.asc)
                .fetchAll(database)
            let exercises: [ExerciseActual] = rows.map { row in
                ExerciseActual(
                    id: row.exerciseKey,
                    name: row.name,
                    planned: ExerciseActualPlanned(
                        sets: row.plannedSets,
                        reps: row.plannedReps,
                        weightKg: row.plannedWeightKg,
                        note: row.plannedNote
                    ),
                    confirmation: ExerciseActualConfirmation(rawValue: row.confirmation),
                    actualSets: row.actualSets,
                    actualReps: row.actualReps,
                    actualWeightKg: row.actualWeightKg
                )
            }
            return ActualsFillInSession(
                id: header.id,
                title: header.title,
                subtitle: header.subtitle,
                exercises: exercises,
                rpe: header.rpe,
                verified: header.verified
            )
        }
    }

    func isVerified(id: String) throws -> Bool {
        try dbQueue.read { database in
            try Bool.fetchOne(
                database,
                sql: "SELECT verified FROM actuals_sessions WHERE id = ?",
                arguments: [id]
            ) ?? false
        }
    }
}

extension ActualsRepository: ActualsGhostLookingUp {
    func latestActual(exerciseKey: String) throws -> ActualsGhostActual? {
        let nameGuess = exerciseKey.replacingOccurrences(of: "_", with: " ")
        return try dbQueue.read { database in
            let row = try Row.fetchOne(
                database,
                sql: """
                SELECT r.actual_sets, r.actual_reps, r.actual_weight_kg
                FROM actuals_exercise_rows r
                INNER JOIN actuals_sessions s ON s.id = r.session_id
                WHERE s.verified = 1
                  AND (r.exercise_key = ? OR lower(r.name) = lower(?))
                ORDER BY s.saved_at DESC
                LIMIT 1
                """,
                arguments: [exerciseKey, nameGuess]
            )
            guard let row else { return nil }
            return ActualsGhostActual(
                sets: row["actual_sets"],
                reps: row["actual_reps"],
                weightKg: row["actual_weight_kg"]
            )
        }
    }
}
