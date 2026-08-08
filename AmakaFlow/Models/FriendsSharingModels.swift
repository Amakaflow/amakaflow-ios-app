//
//  FriendsSharingModels.swift
//  AmakaFlow
//
//  AMA-2389: Friends & workout sharing domain models.
//  Backend BFF endpoints land separately; iOS codes against protocols.
//

import Foundation

// MARK: - Friend identity

nonisolated struct FriendProfile: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: String
    var displayName: String
    var handle: String
    /// Accent for avatar chip (hex or named token key).
    var accentRaw: String

    var handleNormalized: String {
        handle.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^@", with: "", options: .regularExpression)
    }

    var initials: String {
        let parts = displayName.split(separator: " ").map(String.init)
        let letters = parts.prefix(2).compactMap { $0.first.map(String.init) }
        return letters.joined().uppercased()
    }
}

nonisolated enum FriendshipStatus: String, Codable, Sendable, Equatable {
    case pending
    case accepted
}

nonisolated struct Friendship: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let requesterId: String
    let addresseeId: String
    var status: FriendshipStatus
    let createdAt: Date
    /// Profile of the *other* party relative to the current user.
    var peer: FriendProfile
    /// True when the current user is the requester (outgoing pending).
    var isOutgoing: Bool
}

// MARK: - Workout share snapshot (immutable copy)

/// Frozen workout payload carried on a share. Edits never cross either direction.
nonisolated struct WorkoutShareSnapshot: Equatable, Codable, Sendable {
    var name: String
    var sport: String
    var source: String?
    var sourceUrl: String?
    var description: String?
    var creatorName: String?
    var intervals: [WorkoutSaveInterval]
    var blocks: [SocialImportBlock]?
    /// Stable across re-shares; seeded from origin source id / URL / workout id.
    var lineageId: String
}

nonisolated enum WorkoutShareStatus: String, Codable, Sendable, Equatable {
    case sent
    case seen
    case saved
    case dismissed
}

nonisolated struct WorkoutShare: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let fromUserId: String
    let toUserId: String
    var fromDisplayName: String
    var fromHandle: String
    var snapshot: WorkoutShareSnapshot
    var note: String?
    var status: WorkoutShareStatus
    let createdAt: Date
    var savedWorkoutId: String?

    var lineageId: String { snapshot.lineageId }

    var isUnhandled: Bool {
        status == .sent || status == .seen
    }
}

// MARK: - Copy / privacy (verbatim from design)

nonisolated enum FriendsCopy {
    static let privacyContract =
        "Friends can send you workouts — they can't see your history, stats or gym. Remove anyone any time; they aren't notified."

    static let privacyContractMono =
        "FRIENDS CAN SEND YOU WORKOUTS — THEY CAN'T SEE YOUR HISTORY, STATS OR GYM. REMOVE ANYONE ANY TIME; THEY AREN'T NOTIFIED."

    /// List footer when friends exist (mockup manage screen).
    static let privacyRemovingSilentMono =
        "FRIENDS CAN SEND YOU WORKOUTS — THEY CAN'T SEE YOUR HISTORY, STATS OR GYM. REMOVING IS SILENT."

    static let snapshotHonesty =
        "They get a copy — your original stays yours; their edits don't touch it."

    static func removeConfirm(displayName: String) -> String {
        let first = displayName.split(separator: " ").first.map(String.init) ?? displayName
        return "Remove \(first)? They won't be notified. Workouts you saved from them stay yours. You can add them again any time."
    }

    static func profileEntrySubtitle(friendCount: Int, waitingCount: Int) -> String {
        let friendsPart = friendCount == 1 ? "1 FRIEND" : "\(friendCount) FRIENDS"
        if waitingCount >= 1 {
            let waitingPart = waitingCount == 1 ? "1 WORKOUT WAITING" : "\(waitingCount) WORKOUTS WAITING"
            return "\(friendsPart) · \(waitingPart)"
        }
        return "\(friendsPart) · SWAP WORKOUTS"
    }

    static func friendRowMeta(createdAt: Date, now: Date = Date()) -> String {
        let weekAgo = now.addingTimeInterval(-86400 * 7)
        if createdAt >= weekAgo {
            return "ADDED THIS WEEK"
        }
        return "FRIEND · SWAP WORKOUTS"
    }

    static let saveSnapshotRule =
        "Saving makes it yours — your edits never change their copy."

    static let teachHeadline = "Train with your people"
    static let teachBody =
        "Add friends on AmakaFlow and swap workouts — the leg day you built lands straight in their library, theirs in yours."

    static let inviteLinkHint = "ADDS YOU BOTH WHEN THEY JOIN"

    static func sendCTA(selectedFriendCount: Int) -> String {
        guard selectedFriendCount >= 1 else { return "Pick a friend" }
        return selectedFriendCount == 1
            ? "Send to 1 friend"
            : "Send to \(selectedFriendCount) friends"
    }

    static func copySuffix(fromName: String) -> String {
        let first = fromName.split(separator: " ").first.map(String.init) ?? fromName
        return " (from \(first))"
    }

    static func attribution(fromName: String) -> String {
        let first = fromName.split(separator: " ").first.map(String.init) ?? fromName
        return "From \(first)"
    }

    static func fromFriendsSubtitle(names: [String]) -> String {
        guard !names.isEmpty else { return "Workouts friends sent you" }
        let joined = names.joined(separator: ", ")
        return "\(joined) sent you workouts"
    }
}

// MARK: - Dedupe

nonisolated enum WorkoutShareDedupeMatch: Equatable, Sendable {
    case none
    /// Same lineageId or same normalized title + structure fingerprint.
    case strong(existingWorkoutId: String, existingTitle: String)
}

/// Library row used for share dedupe (avoids large tuples for SwiftLint).
nonisolated struct LibraryDedupeEntry: Equatable, Sendable {
    let id: String
    let title: String
    let lineageId: String?
    let fingerprint: String
}

nonisolated enum WorkoutShareDedupe {
    static func normalizeTitle(_ title: String) -> String {
        title
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    /// Structure fingerprint: block count + exercise name sequence + set scheme hash.
    static func fingerprint(from snapshot: WorkoutShareSnapshot) -> String {
        let intervalKey = snapshot.intervals.map { interval in
            [
                interval.type,
                interval.name ?? "",
                String(interval.sets ?? 0),
                String(interval.reps ?? 0),
                String(interval.seconds ?? 0),
                String(interval.meters ?? 0)
            ].joined(separator: ":")
        }.joined(separator: "|")

        let blockCount: Int
        let exerciseSequence: String
        if let blocks = snapshot.blocks, !blocks.isEmpty {
            blockCount = blocks.count
            exerciseSequence = blocks.flatMap { block in
                block.exercises.map { $0.name.lowercased() }
            }.joined(separator: ">")
        } else {
            blockCount = 0
            exerciseSequence = snapshot.intervals.compactMap { $0.name?.lowercased() }.joined(separator: ">")
        }
        return "b\(blockCount)#\(exerciseSequence)#\(stableHash(intervalKey))"
    }

    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 5381
        for byte in value.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }

    static func match(
        snapshot: WorkoutShareSnapshot,
        against library: [LibraryDedupeEntry]
    ) -> WorkoutShareDedupeMatch {
        for item in library {
            if let lineage = item.lineageId, !lineage.isEmpty, lineage == snapshot.lineageId {
                return .strong(existingWorkoutId: item.id, existingTitle: item.title)
            }
        }

        let title = normalizeTitle(snapshot.name)
        let snapshotFingerprint = fingerprint(from: snapshot)
        for item in library {
            if normalizeTitle(item.title) == title, item.fingerprint == snapshotFingerprint {
                return .strong(existingWorkoutId: item.id, existingTitle: item.title)
            }
        }
        return .none
    }

    /// Title-only similarity must NOT flag (spec).
    static func titleOnlyWouldMatch(
        snapshot: WorkoutShareSnapshot,
        libraryTitles: [String]
    ) -> Bool {
        let title = normalizeTitle(snapshot.name)
        return libraryTitles.contains { normalizeTitle($0) == title }
    }
}

nonisolated enum WorkoutShareLineage {
    /// Seed lineage from origin source URL / id, else workout id.
    static func seed(from workout: Workout) -> String {
        if let url = workout.sourceUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
           !url.isEmpty {
            return "src:\(url.lowercased())"
        }
        if let canonical = workout.canonicalId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !canonical.isEmpty {
            return "canonical:\(canonical)"
        }
        return "workout:\(workout.id)"
    }

    static func snapshot(from workout: Workout) -> WorkoutShareSnapshot {
        let request = WorkoutSaveRequest.from(workout: workout)
        return WorkoutShareSnapshot(
            name: workout.name,
            sport: workout.sport.rawValue,
            source: workout.source.rawValue,
            sourceUrl: workout.sourceUrl,
            description: workout.description,
            creatorName: workout.creatorName,
            intervals: request.intervals,
            blocks: request.blocks,
            lineageId: seed(from: workout)
        )
    }
}
