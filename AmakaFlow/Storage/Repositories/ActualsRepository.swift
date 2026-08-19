//
//  ActualsRepository.swift
//  AmakaFlow
//
//  AMA-2387: local-first fill-in actuals. Sync enqueue comes later —
//  airplane mode must not lose a verified save.
//

import Foundation
import GRDB

// swiftlint:disable file_length
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

// swiftlint:disable:next type_body_length
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
        // AMA-2472: a session keeps every exercise, including ones the athlete
        // left blank — those are saved as NOT LOGGED rather than deleted, so
        // "unconfirmed" is no longer a reason to refuse the whole session.
        // The requirement is that SOMETHING was logged.
        let unconfirmed = session.exercises.filter { $0.confirmation == nil }.count
        guard session.exercises.contains(where: \.isLogged) else {
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
                createdAt: timestamp,
                stravaActivityId: session.stravaActivityId,
                stravaActivityType: session.stravaActivityType,
                stravaCurrentDescription: session.stravaCurrentDescription,
                stravaRecordingApp: session.stravaRecordingApp,
                stravaIsRace: session.stravaIsRace,
                structureBody: session.structureBody
            )
            if let existing = try LocalActualsSession.fetchOne(database, key: session.id) {
                header.preserveWriteBack(from: existing)
            }
            try header.upsert(database)

            try LocalActualsExerciseRow
                .filter(LocalActualsExerciseRow.Columns.sessionId == session.id)
                .deleteAll(database)

            for (index, exercise) in session.exercises.enumerated() {
                // AMA-2472: an exercise with nothing recorded is stored as
                // notLogged, not dropped and not refused.
                let confirmation = exercise.confirmation
                    ?? (exercise.isLogged ? .adjusted : .notLogged)
                let rowId = "\(session.id)_\(exercise.id)"
                var row = LocalActualsExerciseRow(
                    id: rowId,
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
                    position: index,
                    structureHeader: exercise.structureHeader,
                    structureBlockIndex: exercise.structureBlockIndex
                )
                try row.insert(database)
                try Self.replaceSetRows(exerciseRowId: rowId, sets: exercise.sets, database: database)
            }
        }
    }

    func fetchSession(id: String) throws -> ActualsFillInSession? {
        try dbQueue.read { database in
            try Self.session(id: id, database: database)
        }
    }

    /// AMA-2396: Match/verify overlays keyed by Strava activity id so History + Today
    /// survive sync reloads and tab changes.
    func fetchSessionsKeyedByStravaActivityId() throws -> [String: ActualsFillInSession] {
        try dbQueue.read { database in
            let headers = try LocalActualsSession
                .filter(sql: "strava_activity_id IS NOT NULL")
                .fetchAll(database)
            var result: [String: ActualsFillInSession] = [:]
            for header in headers {
                guard let activityId = header.stravaActivityId,
                      !Self.isDescriptionCacheSession(id: header.id),
                      let session = try Self.session(id: header.id, database: database) else {
                    continue
                }
                // Prefer verified over draft when duplicates exist.
                if let existing = result[activityId], existing.verified, !session.verified {
                    continue
                }
                result[activityId] = session
            }
            return result
        }
    }

    /// Persist a Map match before RPE/Save so "matched" is not lost on History reload.
    func upsertMatchedDraft(_ session: ActualsFillInSession) throws {
        let timestamp = now()
        try dbQueue.write { database in
            var header = LocalActualsSession(
                id: session.id,
                title: session.title,
                subtitle: session.subtitle,
                rpe: session.rpe,
                verified: false,
                savedAt: timestamp,
                createdAt: timestamp,
                stravaActivityId: session.stravaActivityId,
                isDraft: true,
                stravaActivityType: session.stravaActivityType,
                stravaCurrentDescription: session.stravaCurrentDescription,
                stravaRecordingApp: session.stravaRecordingApp,
                stravaIsRace: session.stravaIsRace,
                structureBody: session.structureBody
            )
            if let existing = try LocalActualsSession.fetchOne(database, key: session.id) {
                header.preserveWriteBack(from: existing, includeDraftFields: true)
            }
            try header.upsert(database)

            try LocalActualsExerciseRow
                .filter(LocalActualsExerciseRow.Columns.sessionId == session.id)
                .deleteAll(database)

            for (index, exercise) in session.exercises.enumerated() {
                let rowId = "\(session.id)_\(exercise.id)"
                var row = LocalActualsExerciseRow(
                    id: rowId,
                    sessionId: session.id,
                    exerciseKey: exercise.id,
                    name: exercise.name,
                    plannedSets: exercise.planned.sets,
                    plannedReps: exercise.planned.reps,
                    plannedWeightKg: exercise.planned.weightKg,
                    plannedNote: exercise.planned.note,
                    confirmation: exercise.confirmation?.rawValue ?? "",
                    actualSets: exercise.actualSets,
                    actualReps: exercise.actualReps,
                    actualWeightKg: exercise.actualWeightKg,
                    position: index,
                    structureHeader: exercise.structureHeader,
                    structureBlockIndex: exercise.structureBlockIndex
                )
                try row.insert(database)
                try Self.replaceSetRows(exerciseRowId: rowId, sets: exercise.sets, database: database)
            }
        }
    }

    private static func replaceSetRows(
        exerciseRowId: String,
        sets: [SetActual],
        database: Database
    ) throws {
        try LocalActualsSetRow
            .filter(LocalActualsSetRow.Columns.exerciseRowId == exerciseRowId)
            .deleteAll(database)
        for set in sets where set.checkedAt != nil {
            var row = LocalActualsSetRow(
                id: "\(exerciseRowId)_\(set.isWarmup ? "w" : "s")_\(set.index)",
                exerciseRowId: exerciseRowId,
                setIndex: set.index,
                isWarmup: set.isWarmup,
                weightKg: set.weightKg,
                reps: set.reps,
                durationSeconds: set.durationSeconds,
                calories: set.calories,
                distanceMeters: set.distanceMeters,
                checkedAt: set.checkedAt
            )
            try row.insert(database)
        }
    }

    private static func loadSets(exerciseRowId: String, database: Database) throws -> [SetActual] {
        let rows = try LocalActualsSetRow
            .filter(LocalActualsSetRow.Columns.exerciseRowId == exerciseRowId)
            .order(LocalActualsSetRow.Columns.setIndex.asc)
            .fetchAll(database)
        return rows.map { row in
            SetActual(
                index: row.setIndex,
                isWarmup: row.isWarmup,
                weightKg: row.weightKg,
                reps: row.reps,
                durationSeconds: row.durationSeconds,
                calories: row.calories,
                distanceMeters: row.distanceMeters,
                checkedAt: row.checkedAt
            )
        }
    }

    private static func session(id: String, database: Database) throws -> ActualsFillInSession? {
        guard let header = try LocalActualsSession.fetchOne(database, key: id) else {
            return nil
        }
        let rows = try LocalActualsExerciseRow
            .filter(LocalActualsExerciseRow.Columns.sessionId == id)
            .order(LocalActualsExerciseRow.Columns.position.asc)
            .fetchAll(database)
        let exercises: [ExerciseActual] = try rows.map { row in
            let sets = try loadSets(exerciseRowId: row.id, database: database)
            return ExerciseActual(
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
                actualWeightKg: row.actualWeightKg,
                sets: sets,
                structureHeader: row.structureHeader,
                structureBlockIndex: row.structureBlockIndex
            )
        }
        return ActualsFillInSession(
            id: header.id,
            title: header.title,
            subtitle: header.subtitle,
            exercises: exercises,
            rpe: header.rpe,
            verified: header.verified,
            stravaActivityId: header.stravaActivityId,
            stravaActivityType: header.stravaActivityType,
            stravaCurrentDescription: header.stravaCurrentDescription,
            stravaRecordingApp: header.stravaRecordingApp,
            stravaIsRace: header.stravaIsRace,
            structureBody: header.structureBody
        )
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

    // MARK: - AMA-2396: un-verify + Strava write-back state

    /// Back to "Fill in" — actuals kept as a draft (exercise rows untouched), RPE
    /// cleared, and no longer counted as verified. Never deletes the session.
    func unverifySession(id: String) throws {
        try dbQueue.write { database in
            guard var session = try LocalActualsSession.fetchOne(database, key: id) else { return }
            session.verified = false
            session.rpe = nil
            session.isDraft = true
            try session.update(database)
        }
    }

    /// Persist the badge state (`SZStravaBadge`) so it survives relaunch without
    /// re-deriving from a live Strava fetch.
    func storeDecoration(_ decoration: StravaDecorationState, forSessionID id: String) throws {
        try dbQueue.write { database in
            guard var session = try LocalActualsSession.fetchOne(database, key: id) else { return }
            session.stravaDecoration = decoration.persistedRawValue
            try session.update(database)
        }
    }

    /// AMA-2405: keep a lazy-fetched Strava description across refresh/relaunch.
    func updateStravaCurrentDescription(sessionID: String, description: String) throws {
        try dbQueue.write { database in
            guard var session = try LocalActualsSession.fetchOne(database, key: sessionID) else { return }
            session.stravaCurrentDescription = description
            try session.update(database)
        }
    }

    func clearDecoration(forSessionID id: String) throws {
        try storeDecoration(.none, forSessionID: id)
    }

    func fetchDecoration(forSessionID id: String) throws -> StravaDecorationState {
        try dbQueue.read { database in
            let raw = try String.fetchOne(
                database,
                sql: "SELECT strava_decoration FROM actuals_sessions WHERE id = ?",
                arguments: [id]
            )
            return StravaDecorationState(persistedRawValue: raw)
        }
    }

    /// Snapshot what Strava had before our first write — "Undo our Strava text" and
    /// "Un-verify" restore this instead of guessing.
    func storePreUpdateSnapshot(_ snapshot: StravaPreUpdateSnapshot, forSessionID id: String) throws {
        try dbQueue.write { database in
            guard var session = try LocalActualsSession.fetchOne(database, key: id) else { return }
            session.stravaActivityId = snapshot.activityId
            session.preUpdateTitle = snapshot.preUpdateTitle
            session.preUpdateDescription = snapshot.preUpdateDescription
            try session.update(database)
        }
    }

    func fetchPreUpdateSnapshot(forSessionID id: String) throws -> StravaPreUpdateSnapshot? {
        try dbQueue.read { database in
            guard let session = try LocalActualsSession.fetchOne(database, key: id),
                  let activityId = session.stravaActivityId,
                  let preUpdateTitle = session.preUpdateTitle,
                  let preUpdateDescription = session.preUpdateDescription else {
                return nil
            }
            return StravaPreUpdateSnapshot(
                activityId: activityId,
                preUpdateTitle: preUpdateTitle,
                preUpdateDescription: preUpdateDescription,
                rev: 1
            )
        }
    }

    func clearPreUpdateSnapshot(forSessionID id: String) throws {
        try dbQueue.write { database in
            guard var session = try LocalActualsSession.fetchOne(database, key: id) else { return }
            session.preUpdateTitle = nil
            session.preUpdateDescription = nil
            try session.update(database)
        }
    }
}

// MARK: - AMA-2407 Verify as-is (no durable "Counted" state)

extension ActualsRepository {
    /// Mark verified without RPE or confirmed exercise rows. Strava's own
    /// metrics stand as the record; there is nothing to confirm per-exercise,
    /// but the product rule is still "Verified or Fill in" — never a separate
    /// durable "Counted" state.
    func upsertVerifiedAsIs(_ session: ActualsFillInSession) throws {
        let timestamp = now()
        try dbQueue.write { database in
            var header = LocalActualsSession(
                id: session.id,
                title: session.title,
                subtitle: session.subtitle,
                rpe: session.rpe,
                verified: true,
                savedAt: timestamp,
                createdAt: timestamp,
                stravaActivityId: session.stravaActivityId,
                stravaActivityType: session.stravaActivityType,
                stravaCurrentDescription: session.stravaCurrentDescription,
                stravaRecordingApp: session.stravaRecordingApp,
                stravaIsRace: session.stravaIsRace,
                structureBody: session.structureBody
            )
            if let existing = try LocalActualsSession.fetchOne(database, key: session.id) {
                header.preserveWriteBack(from: existing)
            }
            try header.upsert(database)

            // Verify as-is carries no exercises — never delete actuals the athlete
            // already filled in for this session id.
            guard !session.exercises.isEmpty else { return }

            try LocalActualsExerciseRow
                .filter(LocalActualsExerciseRow.Columns.sessionId == session.id)
                .deleteAll(database)

            for (index, exercise) in session.exercises.enumerated() {
                let rowId = "\(session.id)_\(exercise.id)"
                var row = LocalActualsExerciseRow(
                    id: rowId,
                    sessionId: session.id,
                    exerciseKey: exercise.id,
                    name: exercise.name,
                    plannedSets: exercise.planned.sets,
                    plannedReps: exercise.planned.reps,
                    plannedWeightKg: exercise.planned.weightKg,
                    plannedNote: exercise.planned.note,
                    confirmation: exercise.confirmation?.rawValue ?? "",
                    actualSets: exercise.actualSets,
                    actualReps: exercise.actualReps,
                    actualWeightKg: exercise.actualWeightKg,
                    position: index,
                    structureHeader: exercise.structureHeader,
                    structureBlockIndex: exercise.structureBlockIndex
                )
                try row.insert(database)
                try Self.replaceSetRows(exerciseRowId: rowId, sets: exercise.sets, database: database)
            }
        }
    }
}

// MARK: - AMA-2405 Strava description cache (activity-id keyed)

extension ActualsRepository {
    static func descriptionCacheSessionID(for activityId: String) -> String {
        "strava_desc_\(activityId)"
    }

    static let descriptionCacheSubtitle = "__strava_description_cache__"

    static func isDescriptionCacheSession(id: String) -> Bool {
        id.hasPrefix("strava_desc_")
    }

    /// Persist by Strava activity id — counted / keep-as-is cards often have no
    /// `fillInSession` row, so session-id updates alone drop the text on re-sync.
    func upsertStravaActivityDescription(activityId: String, description: String) throws {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !activityId.isEmpty, !trimmed.isEmpty else { return }
        let timestamp = now()
        try dbQueue.write { database in
            let existing = try LocalActualsSession
                .filter(sql: "strava_activity_id = ?", arguments: [activityId])
                .fetchAll(database)
            if existing.isEmpty {
                var stub = LocalActualsSession(
                    id: Self.descriptionCacheSessionID(for: activityId),
                    title: "",
                    subtitle: Self.descriptionCacheSubtitle,
                    verified: false,
                    savedAt: timestamp,
                    createdAt: timestamp,
                    stravaActivityId: activityId,
                    isDraft: true,
                    stravaCurrentDescription: trimmed
                )
                try stub.upsert(database)
                return
            }
            for var session in existing {
                session.stravaCurrentDescription = trimmed
                try session.update(database)
            }
        }
    }

    /// Activity-id → cached Strava description (session rows + desc-only stubs).
    func fetchCachedStravaDescriptions() throws -> [String: String] {
        try dbQueue.read { database in
            let headers = try LocalActualsSession
                .filter(sql: """
                    strava_activity_id IS NOT NULL
                    AND strava_current_description IS NOT NULL
                    AND TRIM(strava_current_description) != ''
                    """)
                .fetchAll(database)
            var result: [String: String] = [:]
            for header in headers {
                guard let activityId = header.stravaActivityId,
                      let description = header.stravaCurrentDescription?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                      !description.isEmpty else { continue }
                result[activityId] = description
            }
            return result
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
                  -- AMA-2472: an exercise the athlete left blank is stored now
                  -- (it used to be dropped). Excluded here so an empty row can
                  -- never become a "last time" ghost. Defence-in-depth: with
                  -- these two conditions removed the guard test still passes,
                  -- so the ordering appears to favour real rows already — but
                  -- relying on that is not something to leave to chance.
                  AND r.confirmation <> 'notLogged'
                  AND r.actual_sets > 0
                  AND (r.exercise_key = ? OR lower(r.name) = lower(?))
                ORDER BY s.saved_at DESC, s.rowid DESC
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
