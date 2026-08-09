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

    func testAcceptRejectsOutgoingPendingRequest() async throws {
        let service = InMemoryFriendsSharingService(seedDemo: true)
        let outgoing = try await service.listFriendships().first {
            $0.isOutgoing && $0.status == .pending
        }
        let id = try XCTUnwrap(outgoing).id
        do {
            _ = try await service.acceptRequest(id: id)
            XCTFail("Expected accept of outgoing request to fail")
        } catch FriendsSharingError.notFound {
            // Expected — only incoming pending may be accepted.
        }
    }

    // MARK: Snapshot immutability

    func testShareCarriesSnapshotCopyNotLiveLink() async throws {
        let sender = InMemoryFriendsSharingService(
            currentUserId: "me",
            seedDemo: true
        )
        let friends = try await sender.listFriendships().filter { $0.status == .accepted }
        let peer = try XCTUnwrap(friends.first?.peer)

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
        let created = try await sender.sendShares(
            snapshot: snapshot,
            toFriendIds: [peer.id],
            note: "hi"
        )
        let sent = try XCTUnwrap(created.first)
        XCTAssertEqual(sent.snapshot.name, "Original")

        // Mutating the caller's local snapshot must not change the stored share copy.
        snapshot.name = "Mutated locally"
        XCTAssertEqual(sent.snapshot.name, "Original")

        // Peer inbox sees the frozen name (separate service instance simulating the friend).
        let peerInbox = InMemoryFriendsSharingService(
            currentUserId: peer.id,
            currentHandle: peer.handle,
            currentDisplayName: peer.displayName,
            seedDemo: false
        )
        peerInbox.injectShare(
            WorkoutShare(
                id: sent.id,
                fromUserId: "me",
                toUserId: peer.id,
                fromDisplayName: "David A.",
                fromHandle: "david",
                snapshot: sent.snapshot,
                note: "hi",
                status: .sent,
                createdAt: sent.createdAt,
                savedWorkoutId: nil
            )
        )
        let listed = try await peerInbox.listIncomingShares()
        let received = try XCTUnwrap(listed.first { $0.id == sent.id })
        XCTAssertEqual(received.snapshot.name, "Original")
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

final class BFFFriendsSharingServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testListFriendshipsDecodesCamelCaseAndUsesAuthenticatedBFFRoute() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/friends")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"),
                "Bearer test-token"
            )
            return (
                Self.response(for: request, statusCode: 200),
                Data(
                    """
                    {
                      "friendships": [{
                        "id": "friendship-1",
                        "requesterId": "user-me",
                        "addresseeId": "user-alex",
                        "status": "accepted",
                        "createdAt": "2026-08-01T12:00:00Z",
                        "acceptedAt": "2026-08-02T12:00:00Z",
                        "peer": {
                          "id": "user-alex",
                          "displayName": "Alex Rivera",
                          "handle": "alex.runs",
                          "accentRaw": "blue"
                        },
                        "isOutgoing": true
                      }],
                      "total": 1
                    }
                    """.utf8
                )
            )
        }

        let friendships = try await makeService().listFriendships()

        XCTAssertEqual(friendships.count, 1)
        XCTAssertEqual(friendships.first?.peer.displayName, "Alex Rivera")
        XCTAssertEqual(friendships.first?.createdAt, Self.date("2026-08-01T12:00:00Z"))
    }

    func testSearchAndRequestUseContractPathsAndCamelCaseBody() async throws {
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/v1/friends/search" {
                let components = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
                XCTAssertEqual(
                    components?.queryItems?.first(where: { $0.name == "handle" })?.value,
                    "@alex"
                )
                return (
                    Self.response(for: request, statusCode: 200),
                    Data(
                        """
                        {
                          "profiles": [{
                            "id": "user-alex",
                            "displayName": "Alex Rivera",
                            "handle": "alex.runs",
                            "accentRaw": "blue"
                          }],
                          "total": 1
                        }
                        """.utf8
                    )
                )
            }

            XCTAssertEqual(request.url?.path, "/v1/friends/requests")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try Self.httpBodyData(from: request)
            let json = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            XCTAssertEqual(json["handle"] as? String, "alex.runs")
            return (
                Self.response(for: request, statusCode: 201),
                Self.friendshipJSON
            )
        }

        let service = makeService()
        let profiles = try await service.searchUsers(query: "@alex")
        let friendship = try await service.requestFriend(handle: "alex.runs")

        XCTAssertEqual(profiles.map(\.handle), ["alex.runs"])
        XCTAssertEqual(friendship.status, .pending)
        XCTAssertTrue(friendship.isOutgoing)
    }

    func testSendSharesEncodesCamelCaseSnapshotAndReturnsOnlyServerCreatedShares() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/shares")
            let body = try Self.httpBodyData(from: request)
            let json = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            XCTAssertEqual(json["toFriendIds"] as? [String], ["user-alex"])
            XCTAssertNil(json["to_friend_ids"])
            let snapshot = try XCTUnwrap(json["snapshot"] as? [String: Any])
            XCTAssertEqual(snapshot["lineageId"] as? String, "workout:42")

            return (
                Self.response(for: request, statusCode: 201),
                Data(
                    """
                    {
                      "shares": [{
                        "id": "share-server",
                        "fromUserId": "user-me",
                        "toUserId": "user-alex",
                        "fromDisplayName": "David A.",
                        "fromHandle": "david",
                        "snapshot": {
                          "name": "Threshold Builder",
                          "sport": "running",
                          "source": "manual",
                          "sourceUrl": null,
                          "description": null,
                          "creatorName": null,
                          "intervals": [],
                          "blocks": null,
                          "lineageId": "workout:42"
                        },
                        "note": "Tuesday",
                        "status": "sent",
                        "createdAt": "2026-08-09T02:00:00Z",
                        "savedWorkoutId": null
                      }],
                      "total": 1,
                      "unhandledCount": 1
                    }
                    """.utf8
                )
            )
        }

        let created = try await makeService().sendShares(
            snapshot: Self.snapshot,
            toFriendIds: ["user-alex"],
            note: "Tuesday"
        )

        XCTAssertEqual(created.map(\.id), ["share-server"])
        XCTAssertEqual(created.first?.status, .sent)
    }

    func testHTTPFailureSurfacesBackendDetailInsteadOfReturningFixtureData() async throws {
        MockURLProtocol.requestHandler = { request in
            (
                Self.response(for: request, statusCode: 502),
                Data(#"{"detail":"Friends database is unavailable"}"#.utf8)
            )
        }

        do {
            _ = try await makeService().listFriendships()
            XCTFail("Expected the BFF failure to surface")
        } catch BFFFriendsSharingServiceError.httpError(let statusCode, let detail) {
            XCTAssertEqual(statusCode, 502)
            XCTAssertEqual(detail, "Friends database is unavailable")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testShareTransitionsUseBFFContractAndSaveBody() async throws {
        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path
            if path == "/v1/shares/share-1/save" {
                let body = try Self.httpBodyData(from: request)
                let json = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: body) as? [String: Any]
                )
                XCTAssertEqual(json["savedWorkoutId"] as? String, "workout-saved")
            }
            XCTAssertEqual(request.httpMethod, "POST")
            return (
                Self.response(for: request, statusCode: 200),
                Data(
                    """
                    {
                      "id": "share-1",
                      "status": "seen",
                      "savedWorkoutId": null,
                      "updatedAt": "2026-08-09T02:10:00Z"
                    }
                    """.utf8
                )
            )
        }

        let service = makeService()
        try await service.markSeen(id: "share-1")
        try await service.dismiss(id: "share-1")
        try await service.markSaved(id: "share-1", workoutId: "workout-saved")

        XCTAssertEqual(
            MockURLProtocol.interceptedRequests.compactMap(\.url?.path),
            [
                "/v1/shares/share-1/seen",
                "/v1/shares/share-1/dismiss",
                "/v1/shares/share-1/save"
            ]
        )
    }

    private func makeService() -> BFFFriendsSharingService {
        BFFFriendsSharingService(
            baseURL: "https://bff.test/v1",
            session: MockURLProtocol.mockSession(),
            bearerTokenProvider: { "test-token" }
        )
    }

    private static func response(
        for request: URLRequest,
        statusCode: Int
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
    }

    private static func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private static func httpBodyData(from request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return Data()
        }

        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 {
                throw stream.streamError ?? URLError(.cannotDecodeContentData)
            }
            if count == 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }

    private static let snapshot = WorkoutShareSnapshot(
        name: "Threshold Builder",
        sport: "running",
        source: "manual",
        sourceUrl: nil,
        description: nil,
        creatorName: nil,
        intervals: [],
        blocks: nil,
        lineageId: "workout:42"
    )

    private static let friendshipJSON = Data(
        """
        {
          "id": "friendship-1",
          "requesterId": "user-me",
          "addresseeId": "user-alex",
          "status": "pending",
          "createdAt": "2026-08-09T01:00:00Z",
          "acceptedAt": null,
          "peer": {
            "id": "user-alex",
            "displayName": "Alex Rivera",
            "handle": "alex.runs",
            "accentRaw": "blue"
          },
          "isOutgoing": true
        }
        """.utf8
    )
}
