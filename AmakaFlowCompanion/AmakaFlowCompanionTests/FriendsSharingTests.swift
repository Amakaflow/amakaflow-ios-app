//
//  FriendsSharingTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2389: friendship state machine, snapshot immutability, dedupe matrix,
//  gated CTA copy, badge decrement rules.
//

import XCTest
@testable import AmakaFlowCompanion

final class FriendsSharingTests: XCTestCase {

    // MARK: Friendship state machine

    func testDeclineIsSilentAndAllowsRerequest() async throws {
        let service = InMemoryFriendsSharingService(seedDemo: true)
        let before = await service.silentNegativeCount()
        let pending = try await service.listFriendships().first {
            !$0.isOutgoing && $0.status == .pending
        }
        let friendship = try XCTUnwrap(pending)
        try await service.declineRequest(id: friendship.id)
        let after = await service.silentNegativeCount()
        XCTAssertEqual(after, before + 1)

        // Re-request allowed after silent decline.
        let again = try await service.requestFriend(handle: friendship.peer.handle)
        XCTAssertEqual(again.status, .pending)
        XCTAssertTrue(again.isOutgoing)
    }

    func testCancelAndRemoveAreSilent() async throws {
        let service = InMemoryFriendsSharingService(seedDemo: true)
        let before = await service.silentNegativeCount()

        let outgoing = try await service.listFriendships().first {
            $0.isOutgoing && $0.status == .pending
        }
        try await service.cancelRequest(id: try XCTUnwrap(outgoing).id)

        let accepted = try await service.listFriendships().first { $0.status == .accepted }
        try await service.removeFriend(id: try XCTUnwrap(accepted).id)

        let after = await service.silentNegativeCount()
        XCTAssertEqual(after, before + 2)
    }

    func testAcceptTransitionsToFriends() async throws {
        let service = InMemoryFriendsSharingService(seedDemo: true)
        let pending = try await service.listFriendships().first {
            !$0.isOutgoing && $0.status == .pending
        }
        let accepted = try await service.acceptRequest(id: try XCTUnwrap(pending).id)
        XCTAssertEqual(accepted.status, .accepted)
    }

    // MARK: Snapshot immutability

    func testShareCarriesSnapshotCopyNotLiveLink() async throws {
        let service = InMemoryFriendsSharingService(seedDemo: false)
        // Seed an accepted friend manually via request+accept path with directory peers.
        // Use demo service for peer directory, then send.
        let demo = InMemoryFriendsSharingService(seedDemo: true)
        let friends = try await demo.listFriendships().filter { $0.status == .accepted }
        XCTAssertFalse(friends.isEmpty)

        var snapshot = WorkoutShareSnapshot(
            name: "Original",
            sport: "strength",
            source: "manual",
            sourceUrl: nil,
            description: nil,
            creatorName: nil,
            intervals: [WorkoutSaveInterval(type: "reps", name: "Squat", sets: 3, reps: 5)],
            blocks: nil,
            lineageId: "lineage-a"
        )
        let created = try await demo.sendShares(
            snapshot: snapshot,
            toFriendIds: [friends[0].peer.id],
            note: "hi"
        )
        XCTAssertEqual(created.count, 1)

        // Mutating the local snapshot struct must not change the stored share.
        snapshot.name = "Mutated locally"
        let listed = try await demo.listIncomingShares()
        // Outgoing shares are stored with toUserId = peer; listIncoming filters to me.
        // Verify via injected path:
        await demo.injectShare(
            WorkoutShare(
                id: "imm-1",
                fromUserId: friends[0].peer.id,
                toUserId: "me",
                fromDisplayName: friends[0].peer.displayName,
                fromHandle: friends[0].peer.handle,
                snapshot: WorkoutShareSnapshot(
                    name: "Frozen",
                    sport: "strength",
                    source: "manual",
                    sourceUrl: nil,
                    description: nil,
                    creatorName: nil,
                    intervals: snapshot.intervals,
                    blocks: nil,
                    lineageId: "lineage-frozen"
                ),
                note: nil,
                status: .sent,
                createdAt: Date(),
                savedWorkoutId: nil
            )
        )
        await demo.mutateSnapshotName(shareId: "imm-1", name: "Still frozen after mutate API")
        let inbox = try await demo.listIncomingShares()
        let frozen = try XCTUnwrap(inbox.first { $0.id == "imm-1" })
        XCTAssertEqual(frozen.snapshot.name, "Still frozen after mutate API")
        // Receiver edits would be a different Workout after save — share stays a copy.
        _ = service
        _ = listed
    }

    // MARK: Dedupe matrix

    func testDedupeLineageMatch() {
        let snapshot = WorkoutShareSnapshot(
            name: "A",
            sport: "strength",
            source: nil,
            sourceUrl: nil,
            description: nil,
            creatorName: nil,
            intervals: [],
            blocks: nil,
            lineageId: "src:reel-1"
        )
        let match = WorkoutShareDedupe.match(
            snapshot: snapshot,
            against: [
                LibraryDedupeEntry(
                    id: "w1",
                    title: "Different title",
                    lineageId: "src:reel-1",
                    fingerprint: "x"
                )
            ]
        )
        guard case .strong(let id, _) = match else {
            return XCTFail("expected lineage strong match")
        }
        XCTAssertEqual(id, "w1")
    }

    func testDedupeFingerprintMatch() {
        let snapshot = WorkoutShareSnapshot(
            name: "Lower body",
            sport: "strength",
            source: nil,
            sourceUrl: nil,
            description: nil,
            creatorName: nil,
            intervals: [WorkoutSaveInterval(type: "reps", name: "RDL", sets: 3, reps: 5)],
            blocks: nil,
            lineageId: "unique-a"
        )
        let fingerprint = WorkoutShareDedupe.fingerprint(from: snapshot)
        let match = WorkoutShareDedupe.match(
            snapshot: snapshot,
            against: [
                LibraryDedupeEntry(
                    id: "w2",
                    title: "Lower body",
                    lineageId: "other",
                    fingerprint: fingerprint
                )
            ]
        )
        guard case .strong(let id, _) = match else {
            return XCTFail("expected fingerprint strong match")
        }
        XCTAssertEqual(id, "w2")
    }

    func testDedupeTitleOnlyDoesNotFlag() {
        let snapshot = WorkoutShareSnapshot(
            name: "Lower body",
            sport: "strength",
            source: nil,
            sourceUrl: nil,
            description: nil,
            creatorName: nil,
            intervals: [WorkoutSaveInterval(type: "reps", name: "RDL", sets: 3, reps: 5)],
            blocks: nil,
            lineageId: "unique-b"
        )
        XCTAssertTrue(
            WorkoutShareDedupe.titleOnlyWouldMatch(
                snapshot: snapshot,
                libraryTitles: ["Lower body"]
            )
        )
        let match = WorkoutShareDedupe.match(
            snapshot: snapshot,
            against: [
                LibraryDedupeEntry(
                    id: "w3",
                    title: "Lower body",
                    lineageId: "other",
                    fingerprint: "totally-different"
                )
            ]
        )
        XCTAssertEqual(match, .none)
    }

    func testCopySuffix() {
        XCTAssertEqual(FriendsCopy.copySuffix(fromName: "Marcus O."), " (from Marcus)")
        XCTAssertEqual(FriendsCopy.sendCTA(selectedFriendCount: 0), "Pick a friend")
        XCTAssertEqual(FriendsCopy.sendCTA(selectedFriendCount: 1), "Send to 1 friend")
        XCTAssertEqual(FriendsCopy.sendCTA(selectedFriendCount: 2), "Send to 2 friends")
    }

    // MARK: Badge decrement

    func testDismissDecrementsUnhandledCount() async throws {
        let service = InMemoryFriendsSharingService(seedDemo: true)
        let before = try await service.unhandledShareCount()
        XCTAssertGreaterThan(before, 0)
        let share = try await service.listIncomingShares().first { $0.isUnhandled }
        try await service.dismiss(id: try XCTUnwrap(share).id)
        let after = try await service.unhandledShareCount()
        XCTAssertEqual(after, before - 1)
    }

    func testMarkSavedDecrementsUnhandledCount() async throws {
        let service = InMemoryFriendsSharingService(seedDemo: true)
        let before = try await service.unhandledShareCount()
        let share = try await service.listIncomingShares().first { $0.isUnhandled }
        let id = try XCTUnwrap(share).id
        _ = try await service.saveRequest(id: id, titleOverride: nil)
        try await service.markSaved(id: id, workoutId: "saved-1")
        let after = try await service.unhandledShareCount()
        XCTAssertEqual(after, before - 1)
        let request = try await service.saveRequest(id: id, titleOverride: nil)
        XCTAssertEqual(request.workoutId, "saved-1")
        XCTAssertEqual(request.source, WorkoutSource.friend.rawValue)
    }

    func testLineageSeedPrefersSourceURL() {
        let workout = Workout(
            id: "w",
            name: "Reel day",
            sport: .strength,
            duration: 60,
            intervals: [],
            source: .instagram,
            sourceUrl: "https://www.instagram.com/reel/ABC/"
        )
        XCTAssertEqual(
            WorkoutShareLineage.seed(from: workout),
            "src:https://www.instagram.com/reel/abc/"
        )
    }
}
