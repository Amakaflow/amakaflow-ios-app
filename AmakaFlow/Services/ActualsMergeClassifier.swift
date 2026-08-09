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
        _ left: ActualsSourceRecording,
        _ right: ActualsSourceRecording,
        memory: ActualsMergeMemory = ActualsMergeMemory()
    ) -> ActualsMergeDecision {
        if memory.shouldKeepSeparate(idA: left.id, idB: right.id) {
            return .separate
        }
        if left.id == right.id { return .certain }

        let startDelta = abs(left.startDate.timeIntervalSince(right.startDate))
        let shapeOK = shapeAgrees(left, right)

        // External ref is a confidence signal only — still require ±2 min + shape.
        if externalRefsMatch(left, right), startDelta <= certainStartWindow, shapeOK {
            return .certain
        }

        if startDelta <= certainStartWindow, shapeOK {
            return .certain
        }
        if startDelta <= uncertainStartWindow, looselyOverlaps(left, right) {
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
        let title = withRoles.first { $0.role == .primary }?.title
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
        _ left: ActualsSourceRecording,
        _ right: ActualsSourceRecording
    ) -> ActualsSession {
        merge([left, right])
    }

    /// User chose Keep both — sticky across re-syncs.
    static func applyKeepBoth(
        _ left: ActualsSourceRecording,
        _ right: ActualsSourceRecording,
        memory: inout ActualsMergeMemory
    ) {
        memory.rememberKeepBoth(idA: left.id, idB: right.id)
    }

    // MARK: - Internals

    private static func externalRefsMatch(
        _ left: ActualsSourceRecording,
        _ right: ActualsSourceRecording
    ) -> Bool {
        guard let refA = left.externalRef, let refB = right.externalRef, !refA.isEmpty else {
            return false
        }
        return refA == refB
    }

    private static func shapeAgrees(
        _ left: ActualsSourceRecording,
        _ right: ActualsSourceRecording
    ) -> Bool {
        let longer = max(left.durationSeconds, right.durationSeconds)
        guard longer > 0 else { return true }
        let durationRatio = abs(left.durationSeconds - right.durationSeconds) / longer
        guard durationRatio <= durationTolerance else { return false }

        if let leftDistance = left.distanceMeters, let rightDistance = right.distanceMeters {
            let farther = max(leftDistance, rightDistance)
            guard farther > 0 else { return true }
            return abs(leftDistance - rightDistance) / farther <= distanceTolerance
        }
        return true
    }

    private static func looselyOverlaps(
        _ left: ActualsSourceRecording,
        _ right: ActualsSourceRecording
    ) -> Bool {
        // Time ranges overlap or abut within a few minutes.
        let start = max(left.startDate, right.startDate)
        let end = min(left.endDate, right.endDate)
        if end >= start { return true }
        return abs(left.startDate.timeIntervalSince(right.startDate)) <= uncertainStartWindow
            && shapeAgrees(left, right)
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
