//
//  ActualsSessionModels.swift
//  AmakaFlow
//
//  AMA-2387: local Actuals domain — sessions, source recordings, merge roles.
//  Named ActualsSession* to avoid clashing with PlanningModels.CompletedSession.
//

import Foundation

/// Role of a source recording inside a (possibly merged) session.
enum ActualsRecordingRole: String, Equatable, Codable {
    /// Richest / highest-precedence recording — drives the card.
    case primary
    /// Contributes unique streams (laps, route, etc.); still disclosed.
    case attached
    /// Duplicate kept for provenance; contributes zero to totals.
    case hidden
}

enum ActualsDeviceKind: String, Equatable, Codable {
    case watch
    case phone
    case unknown
}

/// One provider ingest of a finished workout.
struct ActualsSourceRecording: Identifiable, Equatable, Codable {
    let id: String
    let provider: ActualsSourceProvider
    let deviceKind: ActualsDeviceKind
    let title: String
    let startDate: Date
    let durationSeconds: TimeInterval
    /// Meters when known (nil = unknown — not used against the other side).
    let distanceMeters: Double?
    /// Cross-provider activity id when available (certain-merge shortcut).
    let externalRef: String?
    /// Higher = richer streams (HR, GPS, laps…). Used for primary selection.
    let streamRichness: Int
    var role: ActualsRecordingRole

    init(
        id: String,
        provider: ActualsSourceProvider,
        deviceKind: ActualsDeviceKind,
        title: String,
        startDate: Date,
        durationSeconds: TimeInterval,
        distanceMeters: Double? = nil,
        externalRef: String? = nil,
        streamRichness: Int = 0,
        role: ActualsRecordingRole = .primary
    ) {
        self.id = id
        self.provider = provider
        self.deviceKind = deviceKind
        self.title = title
        self.startDate = startDate
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.externalRef = externalRef
        self.streamRichness = streamRichness
        self.role = role
    }

    var endDate: Date {
        startDate.addingTimeInterval(durationSeconds)
    }
}

/// A Today card — one logical session, possibly backed by many recordings.
struct ActualsSession: Identifiable, Equatable, Codable {
    let id: String
    var title: String
    var recordings: [ActualsSourceRecording]

    /// Recordings that count toward totals (primary + attached).
    var countingRecordings: [ActualsSourceRecording] {
        recordings.filter { $0.role != .hidden }
    }

    var sourceCount: Int { recordings.count }

    /// Locked badge copy — always disclose merge provenance.
    var mergeBadge: String {
        "MERGED · \(sourceCount) SOURCES"
    }

    var isMerged: Bool { sourceCount > 1 }

    var primaryRecording: ActualsSourceRecording? {
        recordings.first(where: { $0.role == .primary }) ?? recordings.first
    }
}

/// Sticky Keep-both decisions — survive re-sync (never re-ask / auto-merge).
struct ActualsMergeMemory: Equatable, Codable {
    private(set) var keepBothPairKeys: Set<String>

    init(keepBothPairKeys: Set<String> = []) {
        self.keepBothPairKeys = keepBothPairKeys
    }

    mutating func rememberKeepBoth(idA: String, idB: String) {
        keepBothPairKeys.insert(Self.pairKey(idA, idB))
    }

    func shouldKeepSeparate(idA: String, idB: String) -> Bool {
        keepBothPairKeys.contains(Self.pairKey(idA, idB))
    }

    static func pairKey(_ idA: String, _ idB: String) -> String {
        [idA, idB].sorted().joined(separator: "|")
    }
}

enum ActualsMergeDecision: Equatable {
    /// Silent auto-merge (start ±2 min + shape, or matching external refs).
    case certain
    /// Show "Same session?" ask card.
    case uncertain
    /// Distinct sessions, or sticky Keep-both.
    case separate
}
