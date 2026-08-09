//
//  FriendsSharingStore.swift
//  AmakaFlow
//
//  AMA-2389: Shared observable state for badge parity (Settings ↔ ＋ sheet)
//  and friends / inbox screens.
//

import Combine
import Foundation

@MainActor
final class FriendsSharingStore: ObservableObject {
    static let shared = FriendsSharingStore()

    @Published private(set) var friendships: [Friendship] = []
    @Published private(set) var incomingShares: [WorkoutShare] = []
    @Published private(set) var unhandledShareCount: Int = 0
    @Published private(set) var isLoading = false
    @Published var lastErrorMessage: String?

    private let service: FriendsSharingProviding
    private let lineageStore: WorkoutLineageStoring

    init(
        service: FriendsSharingProviding? = nil,
        lineageStore: WorkoutLineageStoring? = nil
    ) {
        self.service = service ?? Self.makeDefaultService()
        self.lineageStore = lineageStore ?? UserDefaultsWorkoutLineageStore()
    }

    private static func makeDefaultService() -> FriendsSharingProviding {
        #if DEBUG
        let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        if isPreview || UITestEnvironment.shared.useFixtures {
            return InMemoryFriendsSharingService()
        }
        #endif
        return BFFFriendsSharingService.live()
    }

    var acceptedFriends: [Friendship] {
        friendships.filter { $0.status == .accepted }
    }

    var incomingRequests: [Friendship] {
        friendships.filter { $0.status == .pending && !$0.isOutgoing }
    }

    var outgoingRequests: [Friendship] {
        friendships.filter { $0.status == .pending && $0.isOutgoing }
    }

    var unhandledShares: [WorkoutShare] {
        incomingShares.filter(\.isUnhandled)
    }

    var senderNamesForBadge: [String] {
        let names = unhandledShares.map {
            $0.fromDisplayName.split(separator: " ").first.map(String.init) ?? $0.fromDisplayName
        }
        // Preserve order, unique
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let friendsTask = service.listFriendships()
            async let sharesTask = service.listIncomingShares()
            async let countTask = service.unhandledShareCount()
            let friends = try await friendsTask
            let shares = try await sharesTask
            let count = try await countTask
            friendships = friends
            incomingShares = shares
            unhandledShareCount = count
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func searchUsers(query: String) async -> [FriendProfile] {
        (try? await service.searchUsers(query: query)) ?? []
    }

    func requestFriend(handle: String) async throws {
        _ = try await service.requestFriend(handle: handle)
        await reload()
    }

    func accept(_ friendship: Friendship) async throws {
        _ = try await service.acceptRequest(id: friendship.id)
        await reload()
    }

    func decline(_ friendship: Friendship) async throws {
        try await service.declineRequest(id: friendship.id)
        await reload()
    }

    func cancel(_ friendship: Friendship) async throws {
        try await service.cancelRequest(id: friendship.id)
        await reload()
    }

    func remove(_ friendship: Friendship) async throws {
        try await service.removeFriend(id: friendship.id)
        await reload()
    }

    /// Public invite URL from the account handle only — never derived from email.
    func inviteURL() async throws -> URL {
        try await service.inviteLink()
    }

    func send(
        workout: Workout,
        toFriendIds: [String],
        note: String?
    ) async throws -> Int {
        let snapshot = WorkoutShareLineage.snapshot(from: workout)
        let created = try await service.sendShares(
            snapshot: snapshot,
            toFriendIds: toFriendIds,
            note: note
        )
        return created.count
    }

    func dismissShare(_ share: WorkoutShare) async throws {
        try await service.dismiss(id: share.id)
        await reload()
    }

    func markSeen(_ share: WorkoutShare) async throws {
        try await service.markSeen(id: share.id)
        await reload()
    }

    func saveShare(
        _ share: WorkoutShare,
        titleOverride: String?,
        api: APIServiceProviding
    ) async throws -> Workout {
        let request = try await service.saveRequest(id: share.id, titleOverride: titleOverride)
        let saved = try await api.saveWorkout(request)
        try await service.markSaved(id: share.id, workoutId: saved.id)
        lineageStore.setLineageId(share.lineageId, forWorkoutId: saved.id)
        lineageStore.setFingerprint(
            WorkoutShareDedupe.fingerprint(from: share.snapshot),
            forWorkoutId: saved.id
        )
        await reload()
        return saved
    }

    func dedupeMatch(
        for share: WorkoutShare,
        library: [Workout]
    ) -> WorkoutShareDedupeMatch {
        let indexed: [LibraryDedupeEntry] = library.map { workout in
            let lineage = lineageStore.lineageId(forWorkoutId: workout.id)
                ?? WorkoutShareLineage.seed(from: workout)
            let fingerprint = lineageStore.fingerprint(forWorkoutId: workout.id)
                ?? WorkoutShareDedupe.fingerprint(
                    from: WorkoutShareLineage.snapshot(from: workout)
                )
            return LibraryDedupeEntry(
                id: workout.id,
                title: workout.name,
                lineageId: lineage,
                fingerprint: fingerprint
            )
        }
        return WorkoutShareDedupe.match(snapshot: share.snapshot, against: indexed)
    }
}
