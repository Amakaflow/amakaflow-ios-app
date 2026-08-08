//
//  FriendsSharingProviding.swift
//  AmakaFlow
//
//  AMA-2389: Protocol seams for friendship + workout share.
//  Real BFF clients plug in later without blocking iOS UI work.
//

import Foundation

nonisolated enum FriendsSharingError: LocalizedError, Equatable {
    case notFound
    case alreadyFriends
    case alreadyPending
    case cannotFriendSelf
    case handleUnavailable
    case emptySelection
    case shareFailed(String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .notFound: return "Not found."
        case .alreadyFriends: return "You're already friends."
        case .alreadyPending: return "Request already pending."
        case .cannotFriendSelf: return "That's you."
        case .handleUnavailable: return "That handle isn't available."
        case .emptySelection: return "Pick a friend."
        case .shareFailed(let message): return message
        case .saveFailed(let message): return message
        }
    }
}

/// Friendship lifecycle. Decline / cancel / remove are SILENT (no notify event).
nonisolated protocol FriendshipProviding: Sendable {
    func listFriendships() async throws -> [Friendship]
    func searchUsers(query: String) async throws -> [FriendProfile]
    func requestFriend(handle: String) async throws -> Friendship
    func acceptRequest(id: String) async throws -> Friendship
    /// Silent — peer is not notified.
    func declineRequest(id: String) async throws
    /// Silent — peer is not notified.
    func cancelRequest(id: String) async throws
    /// Silent — peer is not notified.
    func removeFriend(id: String) async throws
    func inviteLink(forHandle handle: String) -> URL
}

/// Workout share lifecycle. Shares carry an immutable snapshot + lineageId.
nonisolated protocol WorkoutShareProviding: Sendable {
    func listIncomingShares() async throws -> [WorkoutShare]
    func unhandledShareCount() async throws -> Int
    func sendShares(
        snapshot: WorkoutShareSnapshot,
        toFriendIds: [String],
        note: String?
    ) async throws -> [WorkoutShare]
    func markSeen(id: String) async throws
    /// Silent dismiss — sender is not notified.
    func dismiss(id: String) async throws
    /// Build a library save request from the immutable snapshot (idempotent).
    func saveRequest(id: String, titleOverride: String?) async throws -> WorkoutSaveRequest
    /// Mark share saved after API confirms; stores resulting workout id.
    func markSaved(id: String, workoutId: String) async throws
}

nonisolated protocol FriendsSharingProviding: FriendshipProviding, WorkoutShareProviding {}
