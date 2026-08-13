//
//  LogDraftRepository.swift
//  AmakaFlow
//
//  AMA-2426: local-first LogDraft persistence. Pending drafts never become Today cards.
//

import Foundation
import GRDB

enum LogDraftRepositoryError: LocalizedError, Equatable {
    case encodeFailed
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .encodeFailed: return "Could not encode log draft"
        case .decodeFailed: return "Could not decode log draft"
        }
    }
}

final class LogDraftRepository: @unchecked Sendable {
    private let dbQueue: DatabaseQueue
    private let now: () -> Date
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(database: AppDatabase, now: @escaping () -> Date = Date.init) {
        self.dbQueue = database.dbQueue
        self.now = now
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    convenience init(now: @escaping () -> Date = Date.init) {
        self.init(database: .shared, now: now)
    }

    func upsert(_ draft: LogDraft) throws {
        var mutable = draft
        mutable.lastEditedAt = now()
        let data = try encoder.encode(mutable)
        guard let json = String(data: data, encoding: .utf8) else {
            throw LogDraftRepositoryError.encodeFailed
        }
        try dbQueue.write { database in
            var row = LocalLogDraft(
                id: mutable.id,
                workoutId: mutable.workoutId,
                title: mutable.title,
                subtitle: mutable.subtitle,
                startedAt: mutable.startedAt,
                lastEditedAt: mutable.lastEditedAt,
                state: mutable.state.rawValue,
                mode: mutable.mode.rawValue,
                attachedSessionId: mutable.attachedSessionId,
                payloadJson: json,
                note: mutable.note,
                rpe: mutable.rpe,
                reconciledSessionId: nil
            )
            try row.upsert(database)
        }
    }

    func fetch(id: String) throws -> LogDraft? {
        try dbQueue.read { database in
            guard let row = try LocalLogDraft.fetchOne(database, key: id) else { return nil }
            return try decode(row)
        }
    }

    /// Pending / live drafts only — never include committed (those are actuals sessions).
    func fetchOpenDrafts() throws -> [LogDraft] {
        try dbQueue.read { database in
            let rows = try LocalLogDraft
                .filter(LocalLogDraft.Columns.state != LogDraftState.committed.rawValue)
                .order(LocalLogDraft.Columns.lastEditedAt.desc)
                .fetchAll(database)
            return try rows.compactMap { try decode($0) }
        }
    }

    /// Drafts that must not appear on Today (companion-pending / pending state).
    func fetchPendingCompanionDrafts() throws -> [LogDraft] {
        try fetchOpenDrafts().filter {
            $0.mode == .companionPending || $0.state == .pending
        }
    }

    func markReconciled(draftID: String, sessionID: String) throws {
        try dbQueue.write { database in
            guard var row = try LocalLogDraft.fetchOne(database, key: draftID) else { return }
            row.reconciledSessionId = sessionID
            row.state = LogDraftState.committed.rawValue
            row.lastEditedAt = now()
            try row.update(database)
        }
    }

    func markCommitted(draftID: String) throws {
        try dbQueue.write { database in
            guard var row = try LocalLogDraft.fetchOne(database, key: draftID) else { return }
            row.state = LogDraftState.committed.rawValue
            row.lastEditedAt = now()
            try row.update(database)
        }
    }

    func delete(id: String) throws {
        try dbQueue.write { database in
            _ = try LocalLogDraft.deleteOne(database, key: id)
        }
    }

    /// Undo a timeout standalone commit — restore pending.
    func undoCommit(draftID: String) throws {
        try dbQueue.write { database in
            guard var row = try LocalLogDraft.fetchOne(database, key: draftID) else { return }
            row.state = LogDraftState.pending.rawValue
            row.reconciledSessionId = nil
            row.lastEditedAt = now()
            try row.update(database)
        }
    }

    // MARK: - Load plans (target pass)

    func saveLoadPlan(workoutId: String, exerciseKey: String, targets: [SetActual]) throws {
        let data = try encoder.encode(targets)
        guard let json = String(data: data, encoding: .utf8) else {
            throw LogDraftRepositoryError.encodeFailed
        }
        let id = Self.loadPlanID(workoutId: workoutId, exerciseKey: exerciseKey)
        try dbQueue.write { database in
            var row = LocalWorkoutLoadPlan(
                id: id,
                workoutId: workoutId,
                exerciseKey: exerciseKey,
                payloadJson: json,
                updatedAt: now()
            )
            try row.upsert(database)
        }
    }

    func loadPlan(workoutId: String, exerciseKey: String) throws -> [SetActual]? {
        try dbQueue.read { database in
            let id = Self.loadPlanID(workoutId: workoutId, exerciseKey: exerciseKey)
            guard let row = try LocalWorkoutLoadPlan.fetchOne(database, key: id),
                  let data = row.payloadJson.data(using: .utf8) else {
                return nil
            }
            return try decoder.decode([SetActual].self, from: data)
        }
    }

    /// Length-prefixed so `workoutId`/`exerciseKey` cannot collide across pairs.
    private static func loadPlanID(workoutId: String, exerciseKey: String) -> String {
        "\(workoutId.count):\(workoutId):\(exerciseKey)"
    }

    private func decode(_ row: LocalLogDraft) throws -> LogDraft {
        guard let data = row.payloadJson.data(using: .utf8) else {
            throw LogDraftRepositoryError.decodeFailed
        }
        var draft = try decoder.decode(LogDraft.self, from: data)
        // Prefer column state if payload drifted.
        if let state = LogDraftState(rawValue: row.state) {
            draft.state = state
        }
        if let mode = LogbookMode(rawValue: row.mode) {
            draft.mode = mode
        }
        draft.attachedSessionId = row.attachedSessionId ?? draft.attachedSessionId
        draft.rpe = row.rpe ?? draft.rpe
        draft.note = row.note
        return draft
    }
}
