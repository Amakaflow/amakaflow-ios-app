//
//  LogbookReconciliation.swift
//  AmakaFlow
//
//  AMA-2426: companion draft ↔ device session merge via AMA-2387 overlap rules.
//  Pending drafts must never render as a second Today card.
//

import Foundation

enum LogbookReconcileOutcome: Equatable {
    /// Draft attached as actuals onto the device session — ONE session.
    case merged(sessionId: String)
    /// No overlapping device session.
    case noOverlap
    /// 6h after last edit with no twin → commit standalone (caller shows Undo toast).
    case timeoutCommit(sessionId: String)
    /// Standalone already committed; late twin must use duplicate/flag flow — never silent.
    case lateTwinRequiresDuplicateFlow
}

enum LogbookReconciliation {
    /// No-twin timeout: 6 hours from last edit.
    static let noTwinTimeout: TimeInterval = 6 * 60 * 60

    /// Whether a device recording's window overlaps the draft's active window
    /// using AMA-2387 certain/uncertain start windows (not `.separate`).
    static func overlaps(
        draft: LogDraft,
        device: ActualsSourceRecording,
        memory: ActualsMergeMemory = ActualsMergeMemory()
    ) -> Bool {
        let draftRecording = sourceRecording(for: draft)
        let decision = ActualsMergeClassifier.classify(draftRecording, device, memory: memory)
        return decision != .separate
    }

    /// Attempt to attach a pending draft to an overlapping device session.
    static func reconcile(
        draft: LogDraft,
        deviceSessions: [ActualsSourceRecording],
        now: Date = Date(),
        memory: ActualsMergeMemory = ActualsMergeMemory()
    ) -> LogbookReconcileOutcome {
        guard draft.state == .pending || draft.state == .live else {
            // Already committed — late twin must not silent-merge.
            if deviceSessions.contains(where: { overlaps(draft: draft, device: $0, memory: memory) }) {
                return .lateTwinRequiresDuplicateFlow
            }
            return .noOverlap
        }

        let matches = deviceSessions.filter { overlaps(draft: draft, device: $0, memory: memory) }
        if let primary = matches.sorted(by: { $0.startDate < $1.startDate }).first {
            return .merged(sessionId: primary.id)
        }

        if now.timeIntervalSince(draft.lastEditedAt) >= noTwinTimeout {
            return .timeoutCommit(sessionId: draft.id)
        }
        return .noOverlap
    }

    /// Apply merge: device metrics + logged sets → one fill-in session (unverified until RPE).
    static func mergeDraft(
        _ draft: LogDraft,
        onto device: ActualsSourceRecording
    ) -> ActualsFillInSession {
        var session = LogbookRollup.fillInSession(from: draft, verified: false)
        // Prefer device session identity so Today shows ONE card.
        session = ActualsFillInSession(
            id: device.id,
            title: device.title.isEmpty ? draft.title : device.title,
            subtitle: draft.subtitle,
            exercises: session.exercises,
            rpe: draft.rpe,
            verified: false,
            structureBody: nil
        )
        return session
    }

    /// Property-test helper: a reconciled draft id must not appear as a separate Today card.
    static func todayCardIDs(
        committedSessionIDs: [String],
        pendingDrafts: [LogDraft],
        reconciledDraftIDs: Set<String>
    ) -> [String] {
        let pendingVisible = pendingDrafts
            .filter { $0.state != .committed }
            .filter { !reconciledDraftIDs.contains($0.id) }
            // Pending companion drafts never land on Today.
            .filter { $0.mode != .companionPending && $0.state != .pending }
        // Only committed / live phone sessions that are not pending.
        let liveCommitted = pendingDrafts
            .filter { $0.state == .committed || ($0.mode == .live && $0.state == .live) }
            .filter { !reconciledDraftIDs.contains($0.id) }
            .map(\.id)
        // Reconciled drafts contribute only via their attached device session id.
        return Array(Set(committedSessionIDs + liveCommitted)).sorted()
            + pendingVisible.map(\.id)
    }

    /// True when a reconciled draft would incorrectly produce a second Today card.
    static func wouldDoubleCount(
        draftID: String,
        deviceSessionID: String,
        todayCardIDs: [String]
    ) -> Bool {
        todayCardIDs.contains(draftID) && todayCardIDs.contains(deviceSessionID)
    }

    static func sourceRecording(for draft: LogDraft) -> ActualsSourceRecording {
        let duration = max(draft.activeWindow.duration, 60)
        return ActualsSourceRecording(
            id: draft.id,
            provider: .appleHealth,
            deviceKind: .phone,
            title: draft.title,
            startDate: draft.startedAt,
            durationSeconds: duration,
            distanceMeters: draft.deviceMetrics?.distanceMeters,
            externalRef: draft.workoutId,
            streamRichness: 0,
            role: .primary
        )
    }
}
