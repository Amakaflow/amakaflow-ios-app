//
//  InMemoryFriendsSharingService.swift
//  AmakaFlow
//
//  AMA-2389: Local fixture / dogfood seam until BFF friendship + share
//  endpoints land. Mutual-accept + silent negatives + snapshot copies.
//

import Foundation

/// Local seam until BFF lands. `nonisolated` so tests / actors can use it under
/// the app's default MainActor isolation.
nonisolated final class InMemoryFriendsSharingService: FriendsSharingProviding, @unchecked Sendable {
    private let lock = NSLock()
    private let currentUserId: String
    private let currentHandle: String
    private let currentDisplayName: String

    private var directory: [FriendProfile]
    private var friendships: [Friendship]
    private var shares: [WorkoutShare]
    /// Tracks silent removals so we never emit notify events (testable).
    private var silentNegativeEventCount: Int = 0

    init(
        currentUserId: String = "me",
        currentHandle: String = "david",
        currentDisplayName: String = "David A.",
        seedDemo: Bool = true
    ) {
        self.currentUserId = currentUserId
        self.currentHandle = currentHandle
        self.currentDisplayName = currentDisplayName
        let seed = InMemoryFriendsDemoSeed.make(
            currentUserId: currentUserId,
            seedDemo: seedDemo
        )
        self.directory = seed.directory
        self.friendships = seed.friendships
        self.shares = seed.shares
    }

    // MARK: FriendshipProviding

    func listFriendships() async throws -> [Friendship] {
        lock.lock(); defer { lock.unlock() }
        return friendships.sorted { $0.createdAt > $1.createdAt }
    }

    func searchUsers(query: String) async throws -> [FriendProfile] {
        lock.lock(); defer { lock.unlock() }
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^@", with: "", options: .regularExpression)
            .lowercased()
        guard !normalizedQuery.isEmpty else { return [] }
        let friendIds = Set(friendships.filter { $0.status == .accepted }.map(\.peer.id))
        return directory.filter { profile in
            profile.id != currentUserId
                && !friendIds.contains(profile.id)
                && (profile.handleNormalized.contains(normalizedQuery)
                    || profile.displayName.lowercased().contains(normalizedQuery))
        }
    }

    func requestFriend(handle: String) async throws -> Friendship {
        lock.lock(); defer { lock.unlock() }
        let normalized = handle.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^@", with: "", options: .regularExpression)
            .lowercased()
        guard normalized != currentHandle.lowercased() else {
            throw FriendsSharingError.cannotFriendSelf
        }
        guard let peer = directory.first(where: { $0.handleNormalized == normalized }) else {
            throw FriendsSharingError.notFound
        }
        if friendships.contains(where: {
            $0.peer.id == peer.id && $0.status == .accepted
        }) {
            throw FriendsSharingError.alreadyFriends
        }
        if friendships.contains(where: {
            $0.peer.id == peer.id && $0.status == .pending
        }) {
            throw FriendsSharingError.alreadyPending
        }

        let friendship = Friendship(
            id: "f-\(UUID().uuidString)",
            requesterId: currentUserId,
            addresseeId: peer.id,
            status: .pending,
            createdAt: Date(),
            peer: peer,
            isOutgoing: true
        )
        friendships.append(friendship)
        return friendship
    }

    func acceptRequest(id: String) async throws -> Friendship {
        lock.lock(); defer { lock.unlock() }
        guard let index = friendships.firstIndex(where: { $0.id == id }) else {
            throw FriendsSharingError.notFound
        }
        friendships[index].status = .accepted
        return friendships[index]
    }

    func declineRequest(id: String) async throws {
        lock.lock(); defer { lock.unlock() }
        guard let index = friendships.firstIndex(where: { $0.id == id && !$0.isOutgoing }) else {
            throw FriendsSharingError.notFound
        }
        friendships.remove(at: index)
        silentNegativeEventCount += 1
        // No notification event by design.
    }

    func cancelRequest(id: String) async throws {
        lock.lock(); defer { lock.unlock() }
        guard let index = friendships.firstIndex(where: {
            $0.id == id && $0.isOutgoing && $0.status == .pending
        }) else {
            throw FriendsSharingError.notFound
        }
        friendships.remove(at: index)
        silentNegativeEventCount += 1
    }

    func removeFriend(id: String) async throws {
        lock.lock(); defer { lock.unlock() }
        guard let index = friendships.firstIndex(where: { $0.id == id && $0.status == .accepted }) else {
            throw FriendsSharingError.notFound
        }
        friendships.remove(at: index)
        silentNegativeEventCount += 1
    }

    func inviteLink(forHandle handle: String) -> URL {
        let cleaned = handle.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^@", with: "", options: .regularExpression)
            .lowercased()
        var components = URLComponents()
        components.scheme = "https"
        components.host = "amakaflow.com"
        components.path = "/add/\(cleaned)"
        return components.url ?? URL(fileURLWithPath: "/")
    }

    // MARK: WorkoutShareProviding

    func listIncomingShares() async throws -> [WorkoutShare] {
        lock.lock(); defer { lock.unlock() }
        return shares
            .filter { $0.toUserId == currentUserId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func unhandledShareCount() async throws -> Int {
        lock.lock(); defer { lock.unlock() }
        return shares.filter { $0.toUserId == currentUserId && $0.isUnhandled }.count
    }

    func sendShares(
        snapshot: WorkoutShareSnapshot,
        toFriendIds: [String],
        note: String?
    ) async throws -> [WorkoutShare] {
        lock.lock(); defer { lock.unlock() }
        guard !toFriendIds.isEmpty else { throw FriendsSharingError.emptySelection }
        var created: [WorkoutShare] = []
        for friendId in toFriendIds {
            guard let friendship = friendships.first(where: {
                $0.peer.id == friendId && $0.status == .accepted
            }) else { continue }
            // Snapshot is value-copied — mutations to local workout never touch this.
            let share = WorkoutShare(
                id: "share-\(UUID().uuidString)",
                fromUserId: currentUserId,
                toUserId: friendship.peer.id,
                fromDisplayName: currentDisplayName,
                fromHandle: currentHandle,
                snapshot: snapshot,
                note: note,
                status: .sent,
                createdAt: Date(),
                savedWorkoutId: nil
            )
            shares.append(share)
            created.append(share)
        }
        guard !created.isEmpty else {
            throw FriendsSharingError.shareFailed("No accepted friends in selection.")
        }
        return created
    }

    func markSeen(id: String) async throws {
        lock.lock(); defer { lock.unlock() }
        guard let index = shares.firstIndex(where: { $0.id == id }) else {
            throw FriendsSharingError.notFound
        }
        if shares[index].status == .sent {
            shares[index].status = .seen
        }
    }

    func dismiss(id: String) async throws {
        lock.lock(); defer { lock.unlock() }
        guard let index = shares.firstIndex(where: { $0.id == id }) else {
            throw FriendsSharingError.notFound
        }
        shares[index].status = .dismissed
        silentNegativeEventCount += 1
    }

    func saveRequest(id: String, titleOverride: String?) async throws -> WorkoutSaveRequest {
        lock.lock(); defer { lock.unlock() }
        guard let share = shares.first(where: { $0.id == id }) else {
            throw FriendsSharingError.notFound
        }
        // Idempotent: already saved → return same provenance request keyed by saved id.
        return WorkoutSaveRequest(
            name: titleOverride ?? share.snapshot.name,
            sport: share.snapshot.sport,
            intervals: share.snapshot.intervals,
            source: WorkoutSource.friend.rawValue,
            sourceUrl: share.snapshot.sourceUrl,
            description: share.snapshot.description,
            creatorName: share.fromDisplayName,
            blocks: share.snapshot.blocks,
            workoutId: share.savedWorkoutId
        )
    }

    func markSaved(id: String, workoutId: String) async throws {
        lock.lock(); defer { lock.unlock() }
        guard let index = shares.firstIndex(where: { $0.id == id }) else {
            throw FriendsSharingError.notFound
        }
        shares[index].status = .saved
        shares[index].savedWorkoutId = workoutId
    }

    // MARK: Test helpers

    func silentNegativeCount() -> Int {
        lock.lock(); defer { lock.unlock() }
        return silentNegativeEventCount
    }

    func mutateSnapshotName(shareId: String, name: String) {
        lock.lock(); defer { lock.unlock() }
        guard let index = shares.firstIndex(where: { $0.id == shareId }) else { return }
        shares[index].snapshot.name = name
    }

    func injectShare(_ share: WorkoutShare) {
        lock.lock(); defer { lock.unlock() }
        shares.append(share)
    }
}
