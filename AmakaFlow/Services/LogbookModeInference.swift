//
//  LogbookModeInference.swift
//  AmakaFlow
//
//  AMA-2426: infer live / companion-pending / after — never user-picked.
//

import Foundation

struct LogbookModeContext: Equatable {
    /// Phone workout timer / follow-along is actively tracking.
    var phoneTrackerActive: Bool
    /// Native watch Workout app is running (or scheduled plan window is active).
    /// We cannot observe step progress — this flag only means "companion likely".
    var watchPlanActiveWindow: Bool
    /// Editing an existing synced/manual session.
    var existingSessionId: String?
}

enum LogbookModeInference {
    /// Precedence: after (existing session) > live (phone tracker) > companion-pending fallback.
    static func infer(_ context: LogbookModeContext) -> LogbookMode {
        if let existing = context.existingSessionId, !existing.isEmpty {
            return .after
        }
        if context.phoneTrackerActive {
            return .live
        }
        if context.watchPlanActiveWindow {
            return .companionPending
        }
        // Manual "Log a session" / past session with no device twin yet → pending
        // until saved (phone-only) or reconciled. Opening without a timer still
        // starts as pending so Today is not double-counted before commit.
        return .companionPending
    }

    static func draftState(for mode: LogbookMode) -> LogDraftState {
        switch mode {
        case .live: return .live
        case .companionPending: return .pending
        case .after: return .pending
        }
    }
}
