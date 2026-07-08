//
//  SuggestionAcceptanceService.swift
//  AmakaFlow
//
//  AMA-1792/1815 (issue #435): Single module that owns the accept→enqueue
//  choreography. Callers ask "accept this suggestion" without knowing that
//  two tables and a sync_queue enqueue must land atomically. The atomicity
//  guarantee lives inside AcceptedSuggestionsRepository (GRDB transaction),
//  and this service seals off the enqueueSync parameter so it can never be
//  accidentally omitted.
//

import Foundation

nonisolated struct SuggestionAcceptanceService {
    private let repository: AcceptedSuggestionsRepository

    init(repository: AcceptedSuggestionsRepository) {
        self.repository = repository
    }

    /// Atomically accept a suggestion: tombstone every prior live accept for
    /// the user, persist the new suggestion+event pair, and enqueue both
    /// sync_queue items — all inside one GRDB write transaction.
    /// Throws if the invariant guard fires (mismatched userId/workoutEventId)
    /// or if the DB write fails; in either case the transaction rolls back and
    /// no row is persisted.
    func accept(userId: String, suggestion: LocalAcceptedSuggestion, event: LocalWorkoutEvent) throws {
        try repository.replacePriorAcceptsAndInsert(userId: userId, suggestion: suggestion, event: event, enqueueSync: true)
    }
}
