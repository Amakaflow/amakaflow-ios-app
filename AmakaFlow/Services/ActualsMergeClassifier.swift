//
//  ActualsMergeClassifier.swift
//  AmakaFlow
//
//  AMA-2387: certain / uncertain merge tiers + roles + Split restore.
//  Merge is a relation, not a delete (design-handoff/ACTUALS.md §6).
//

import Foundation

enum ActualsMergeClassifier {
    /// Certain-merge start window (±2 minutes).
    static let certainStartWindow: TimeInterval = 2 * 60
    /// Uncertain ask window when shape is close but not certain.
    static let uncertainStartWindow: TimeInterval = 8 * 60
    /// Duration must agree within this fraction for "same shape".
    static let durationTolerance: Double = 0.12
    /// Distance must agree within this fraction when both sides have it.
    static let distanceTolerance: Double = 0.12

    // MARK: - Classify

    static func classify(
        _ a: ActualsSourceRecording,
        _ b: ActualsSourceRecording,
        memory: ActualsMergeMemory = ActualsMergeMemory()
    ) -> ActualsMergeDecision {
        if memory.shouldKeepSeparate(idA: a.id, idB: b.id) {
            return .separate
        }
        if a.id == b.id { return .certain }

        if externalRefsMatch(a, b) {
            return .certain
        }

        let startDelta = abs(a.startDate.timeIntervalSince(b.startDate))
        let shapeOK = shapeAgrees(a, b)

        if startDelta <= certainStartWindow, shapeOK {
            return .certain
        }
        if startDelta <= uncertainStartWindow, looselyOverlaps(a, b) {
            return .uncertain
        }
        return .separate
    }

    // MARK: - Merge / roles

    /// Build a merged session with precedence-assigned roles.
    static func merge(
        _ recordings: [ActualsSourceRecording],
        sessionID: String = UUID().uuidString
    ) -> ActualsSession {
        let withRoles = assignRoles(recordings)
        let title = withRoles.first(where: { $0.role == .primary })?.title
            ?? withRoles.first?.title
            ?? "Session"
        return ActualsSession(id: sessionID, title: title, recordings: withRoles)
    }

    /// watch > phone; then richest streams = primary; next = attached; rest = hidden.
    static func assignRoles(
        _ recordings: [ActualsSourceRecording]
    ) -> [ActualsSourceRecording] {
        guard !recordings.isEmpty else { return [] }
        let sorted = recordings.sorted(by: precedes)
        return sorted.enumerated().map { index, recording in
            var copy = recording
            switch index {
            case 0: copy.role = .primary
            case 1: copy.role = .attached
            default: copy.role = .hidden
            }
            return copy
        }
    }

    /// Split restores every recording as its own primary session (full restore).
    static func split(_ session: ActualsSession) -> [ActualsSourceRecording] {
        session.recordings.map { recording in
            var copy = recording
            copy.role = .primary
            return copy
        }
    }

    /// User chose Merge on an uncertain ask.
    static func applyUserMerge(
        _ a: ActualsSourceRecording,
        _ b: ActualsSourceRecording
    ) -> ActualsSession {
        merge([a, b])
    }

    /// User chose Keep both — sticky across re-syncs.
    static func applyKeepBoth(
        _ a: ActualsSourceRecording,
        _ b: ActualsSourceRecording,
        memory: inout ActualsMergeMemory
    ) {
        memory.rememberKeepBoth(idA: a.id, idB: b.id)
    }

    // MARK: - Internals

    private static func externalRefsMatch(
        _ a: ActualsSourceRecording,
        _ b: ActualsSourceRecording
    ) -> Bool {
        guard let refA = a.externalRef, let refB = b.externalRef, !refA.isEmpty else {
            return false
        }
        return refA == refB
    }

    private static func shapeAgrees(
        _ a: ActualsSourceRecording,
        _ b: ActualsSourceRecording
    ) -> Bool {
        let longer = max(a.durationSeconds, b.durationSeconds)
        guard longer > 0 else { return true }
        let durationRatio = abs(a.durationSeconds - b.durationSeconds) / longer
        guard durationRatio <= durationTolerance else { return false }

        if let da = a.distanceMeters, let db = b.distanceMeters {
            let farther = max(da, db)
            guard farther > 0 else { return true }
            return abs(da - db) / farther <= distanceTolerance
        }
        return true
    }

    private static func looselyOverlaps(
        _ a: ActualsSourceRecording,
        _ b: ActualsSourceRecording
    ) -> Bool {
        // Time ranges overlap or abut within a few minutes.
        let start = max(a.startDate, b.startDate)
        let end = min(a.endDate, b.endDate)
        if end >= start { return true }
        return abs(a.startDate.timeIntervalSince(b.startDate)) <= uncertainStartWindow
            && shapeAgrees(a, b)
    }

    private static func precedes(
        _ lhs: ActualsSourceRecording,
        _ rhs: ActualsSourceRecording
    ) -> Bool {
        let leftWatch = lhs.deviceKind == .watch
        let rightWatch = rhs.deviceKind == .watch
        if leftWatch != rightWatch { return leftWatch }
        if lhs.streamRichness != rhs.streamRichness {
            return lhs.streamRichness > rhs.streamRichness
        }
        return lhs.id < rhs.id
    }
}

// MARK: - Badge helper

enum ActualsMergeBadge {
    static func text(sourceCount: Int) -> String {
        "MERGED · \(sourceCount) SOURCES"
    }
}
