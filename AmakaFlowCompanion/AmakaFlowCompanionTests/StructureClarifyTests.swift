//
//  StructureClarifyTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2305 / ADR-017 — models, state machine, save guards, Describe round-trip.
//

import XCTest
@testable import AmakaFlowCompanion

final class StructureClarifyTests: XCTestCase {

    // MARK: - A. Decode / encode fixtures

    func testSuggestResultDecodesCamelCase() throws {
        let json = """
        {
          "exercises": [{"name": "Bench Press", "reps": 8, "restSec": 60}],
          "suggestions": [{
            "type": "superset",
            "label": "Superset A",
            "rounds": 4,
            "restSec": 180,
            "exerciseNames": ["Bench Press", "Pull Ups"],
            "exerciseIndices": [0, 1],
            "structureSource": "inferred"
          }],
          "blocks": []
        }
        """.data(using: .utf8)!

        let result = try StructureJSON.decoder.decode(StructureSuggestResult.self, from: json)
        XCTAssertEqual(result.exercises.first?.name, "Bench Press")
        XCTAssertEqual(result.exercises.first?.restSec, 60)
        XCTAssertEqual(result.suggestions.first?.structureSource, .inferred)
        XCTAssertEqual(result.suggestions.first?.exerciseNames, ["Bench Press", "Pull Ups"])
        XCTAssertEqual(result.suggestions.first?.restSec, 180)
    }

    func testApplyResultDecodesCamelCase() throws {
        let json = """
        {
          "blocks": [{
            "type": "superset",
            "label": "Superset A",
            "rounds": 4,
            "restSec": 180,
            "exercises": [
              {"name": "Bench Press", "reps": 8},
              {"name": "Pull Ups", "reps": 8}
            ],
            "structureSource": "user_confirmed"
          }]
        }
        """.data(using: .utf8)!

        let result = try StructureJSON.decoder.decode(ApplyStructureResult.self, from: json)
        XCTAssertEqual(result.blocks.first?.structureSource, .userConfirmed)
        XCTAssertEqual(result.blocks.first?.restSec, 180)
        XCTAssertEqual(result.blocks.first?.exercises.count, 2)
    }

    func testApplyRequestEncodesNoteAndBlocks() throws {
        let request = ApplyStructureRequest(
            blocks: [
                StructureBlockModel(
                    type: .sets,
                    exercises: [StructureExerciseModel(name: "Bench Press", reps: 8)],
                    structureSource: .unknown
                )
            ],
            ops: [["op": "group", "type": "superset"]],
            note: "bench and pull ups are a superset"
        )
        let data = try request.jsonData()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["note"] as? String, "bench and pull ups are a superset")
        let blocks = try XCTUnwrap(object["blocks"] as? [[String: Any]])
        XCTAssertEqual(blocks.first?["structureSource"] as? String, "unknown")
        XCTAssertNotNil(object["ops"])
    }

    func testStructureSourceProvenanceTagsExhaustive() {
        for source in StructureSource.allCases {
            let tag = source.clarifyTag(typeLabel: "Superset")
            switch source {
            case .userConfirmed:
                XCTAssertEqual(tag, "SUPERSET ✓")
            case .userNote:
                XCTAssertTrue(tag.contains("FROM YOUR NOTE"))
            case .explicit, .inferred, .unknown:
                XCTAssertTrue(tag.hasPrefix("SUGGESTED"))
            }
        }
    }

    // MARK: - State machine

    func testDMqSuggestBuildsTwoSupersetsWarmupCircuitCurlsFlat() {
        var session = StructureClarifySession.fromSuggest(StructureClarifyFixtures.dmqSuggestResult)
        let types = session.groups.map(\.type.canonical)
        XCTAssertEqual(types.filter { $0 == .superset }.count, 2)
        XCTAssertTrue(types.contains(.warmup))
        XCTAssertTrue(types.contains(.circuit))
        XCTAssertEqual(session.units.filter {
            if case .row(let row) = $0 { return row.exercise.name.contains("Curl") }
            return false
        }.count, 1)
        XCTAssertEqual(session.pendingGroupCount, 4)

        session.confirmAll()
        let saved = session.blocksForSave(leaveFlat: false)
        XCTAssertEqual(saved.filter { $0.type.canonical == .superset }.count, 2)
        XCTAssertTrue(saved.contains { $0.type.canonical == .warmup })
        XCTAssertTrue(saved.contains { $0.type.canonical == .circuit && $0.rounds == 5 })
        XCTAssertTrue(saved.contains { $0.exercises.contains(where: { $0.name.contains("Curl") }) && $0.type == .sets })
        XCTAssertTrue(saved.allSatisfy { $0.structureSource != .inferred })
    }

    func testConfirmUndoConfirmAll() throws {
        var session = StructureClarifySession.fromSuggest(StructureClarifyFixtures.dmqSuggestResult)
        let groupID = try XCTUnwrap(session.groups.first?.id)
        session.confirm(groupID: groupID)
        XCTAssertEqual(session.confirmedGroupCount, 1)
        session.undo(groupID: groupID)
        XCTAssertFalse(session.groups.contains { $0.id == groupID })
        session = StructureClarifySession.fromSuggest(StructureClarifyFixtures.dmqSuggestResult)
        session.confirmAll()
        XCTAssertEqual(session.pendingGroupCount, 0)
        XCTAssertEqual(session.confirmedGroupCount, session.groups.count)
    }

    func testLeaveFlatAllUserConfirmed() {
        let session = StructureClarifySession.fromSuggest(StructureClarifyFixtures.dmqSuggestResult)
        let flat = session.blocksForSave(leaveFlat: true)
        XCTAssertFalse(flat.isEmpty)
        XCTAssertTrue(flat.allSatisfy { $0.type == .sets })
        XCTAssertTrue(flat.allSatisfy { $0.structureSource == .userConfirmed })
        XCTAssertTrue(flat.allSatisfy { $0.exercises.count == 1 })
    }

    func testUnconfirmedGroupsSaveFlatNeverInferred() {
        let session = StructureClarifySession.fromSuggest(StructureClarifyFixtures.dmqSuggestResult)
        let saved = session.blocksForSave(leaveFlat: false)
        XCTAssertTrue(saved.allSatisfy { $0.structureSource != .inferred })
        XCTAssertTrue(saved.allSatisfy { $0.type == .sets })
    }

    func testBlocksForPersistenceFlattensInferredAndExplicit() {
        let curl = SocialImportExercise(name: "Curl", sets: 3, reps: 12)
        let bench = SocialImportExercise(name: "Bench", reps: 8)
        let pull = SocialImportExercise(name: "Pull", reps: 8)
        let draft = SocialImportDraft(
            title: "Guard",
            sport: "strength",
            platform: .instagram,
            sourceURL: nil,
            exercises: [bench, pull, curl],
            blocks: [
                SocialImportBlock(
                    label: "Superset",
                    rounds: 4,
                    exercises: [bench, pull],
                    type: "superset",
                    restSec: 180,
                    structureSource: StructureSource.inferred.rawValue
                ),
                SocialImportBlock(
                    label: "Explicit pair",
                    rounds: 3,
                    exercises: [curl],
                    type: "sets",
                    structureSource: StructureSource.explicit.rawValue
                )
            ],
            equipmentNote: nil,
            equipmentEmpty: true
        )
        let persisted = draft.blocksForPersistence()
        XCTAssertTrue(persisted.allSatisfy { $0.structureSource != StructureSource.inferred.rawValue })
        XCTAssertTrue(persisted.allSatisfy { $0.structureSource != StructureSource.explicit.rawValue })
        XCTAssertTrue(persisted.allSatisfy { ($0.type ?? "sets") == "sets" })
        XCTAssertEqual(persisted.count, 3)
    }

    func testChipGroupSelectedRows() {
        var session = StructureClarifySession.fromSuggest(StructureClarifyFixtures.dmqSuggestResult)
        let benchGroup = session.groups.first { $0.label.contains("Bench") }!
        session.undo(groupID: benchGroup.id)
        let rows = session.units.compactMap { unit -> UUID? in
            if case .row(let row) = unit { return row.id }
            return nil
        }
        XCTAssertGreaterThanOrEqual(rows.count, 2)
        session.toggleRowSelection(rows[0])
        session.toggleRowSelection(rows[1])
        session.groupSelected(as: .superset)
        XCTAssertTrue(session.groups.contains { $0.status == .confirmed && $0.type.canonical == .superset })
    }

    func testIdempotentReApplyReplacesNeverStacks() {
        var session = StructureClarifySession.fromSuggest(StructureClarifyFixtures.dmqSuggestResult)
        let applied = StructureClarifyFixtures.dmqNoteAppliedBlocks
        session.replace(withAppliedBlocks: applied)
        let count1 = session.groups.count
        session.replace(withAppliedBlocks: applied)
        XCTAssertEqual(session.groups.count, count1)
        XCTAssertEqual(session.units.count, StructureClarifySession.fromAppliedBlocks(applied).units.count)
        XCTAssertTrue(session.groups.contains { $0.structureSource == .userNote })
    }

    func testNoteAppliedShowsUserNoteProvenance() {
        let session = StructureClarifySession.fromAppliedBlocks(StructureClarifyFixtures.dmqNoteAppliedBlocks)
        let noted = session.groups.filter { $0.structureSource == .userNote }
        XCTAssertFalse(noted.isEmpty)
        XCTAssertTrue(noted.allSatisfy { $0.provenanceTag.contains("FROM YOUR NOTE") })
        XCTAssertTrue(noted.allSatisfy { $0.status == .pending })
    }
}

@MainActor
final class StructureClarifyViewModelTests: XCTestCase {
    private var mockAPI: MockAPIService!
    private var mockPairing: MockPairingService!
    private var sut: SocialImportViewModel!

    override func setUp() async throws {
        try await super.setUp()
        mockAPI = await MockAPIService()
        mockPairing = await MockPairingService()
        mockPairing.isPaired = true
        mockPairing.userProfile = UserProfile(id: "user-1", email: "david@amakaflow.com", name: "David", avatarUrl: nil)
        let deps = await AppDependencies(
            apiService: mockAPI,
            pairingService: mockPairing,
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: MockChatStreamService()
        )
        sut = SocialImportViewModel(dependencies: deps)
    }

    override func tearDown() async throws {
        sut = nil
        mockAPI = nil
        mockPairing = nil
        try await super.tearDown()
    }

    func testImportLandsOnClarifyNotPreview() async {
        mockAPI.ingestSocialURLResult = .success(sampleIngestJSON())
        mockAPI.suggestStructureResult = .success(StructureClarifyFixtures.dmqSuggestResult)

        await sut.importURL("https://instagram.com/reel/DMqEsenN6Dl", platformHint: .instagram)

        guard case .clarify = sut.phase else {
            return XCTFail("Expected clarify, got \(sut.phase)")
        }
        XCTAssertTrue(mockAPI.suggestStructureCalled)
        XCTAssertEqual(sut.clarifySession?.groups.filter { $0.type.canonical == .superset }.count, 2)
    }

    func testDescribeRoundTripsApplyAndShowsUserNote() async {
        mockAPI.ingestSocialURLResult = .success(sampleIngestJSON())
        mockAPI.suggestStructureResult = .success(StructureClarifyFixtures.dmqSuggestResult)
        mockAPI.applyStructureResult = .success(
            ApplyStructureResult(blocks: StructureClarifyFixtures.dmqNoteAppliedBlocks)
        )

        await sut.importURL("https://instagram.com/reel/DMqEsenN6Dl", platformHint: .instagram)
        sut.describeNote = "curls go after the incline pair, finisher is a circuit x5"
        await sut.applyDescribeNote()

        XCTAssertTrue(mockAPI.applyStructureCalled)
        XCTAssertEqual(mockAPI.lastApplyStructureRequest?.note, sut.describeNote)
        XCTAssertTrue(sut.clarifySession?.groups.contains { $0.structureSource == .userNote } == true)
        guard case .clarify = sut.phase else {
            return XCTFail("Expected clarify after describe, got \(sut.phase)")
        }
    }

    func testLeaveFlatSavePayloadUserConfirmed() async {
        mockAPI.ingestSocialURLResult = .success(sampleIngestJSON())
        mockAPI.suggestStructureResult = .success(StructureClarifyFixtures.dmqSuggestResult)
        mockAPI.saveWorkoutResult = .success(
            Workout(id: "flat-1", name: "Hyrox", sport: .strength, duration: 2400, intervals: [], source: .instagram)
        )

        await sut.importURL("https://instagram.com/reel/DMqEsenN6Dl", platformHint: .instagram)
        await sut.saveFromClarify(leaveFlat: true)

        let blocks = mockAPI.lastSaveWorkoutRequest?.blocks ?? []
        XCTAssertFalse(blocks.isEmpty)
        XCTAssertTrue(blocks.allSatisfy { $0.structureSource == StructureSource.userConfirmed.rawValue })
        XCTAssertTrue(blocks.allSatisfy { ($0.type ?? "sets") == "sets" })
        guard case .saved = sut.phase else {
            return XCTFail("Expected saved, got \(sut.phase)")
        }
    }

    func testConfirmThenSaveNeverIncludesInferred() async {
        mockAPI.ingestSocialURLResult = .success(sampleIngestJSON())
        mockAPI.suggestStructureResult = .success(StructureClarifyFixtures.dmqSuggestResult)
        mockAPI.saveWorkoutResult = .success(
            Workout(id: "ok-1", name: "Hyrox", sport: .strength, duration: 2400, intervals: [], source: .instagram)
        )

        await sut.importURL("https://instagram.com/reel/DMqEsenN6Dl", platformHint: .instagram)
        sut.confirmAllClarifyGroups()
        await sut.saveFromClarify(leaveFlat: false)

        let blocks = mockAPI.lastSaveWorkoutRequest?.blocks ?? []
        XCTAssertTrue(blocks.allSatisfy { $0.structureSource != StructureSource.inferred.rawValue })
        XCTAssertTrue(blocks.contains { $0.type == "superset" && $0.structureSource == "user_confirmed" })
    }

    private func sampleIngestJSON() -> Data {
        let payload: [String: Any] = [
            "title": "Hyrox Upper Body",
            "sport": "strength",
            "creator": "trainwithsmee",
            "caption": StructureClarifyFixtures.dmqCaption,
            "blocks": [
                ["exercises": StructureClarifyFixtures.dmqExercises.map { ["name": $0.name, "reps": $0.reps as Any] }]
            ]
        ]
        // swiftlint:disable:next force_try
        return try! JSONSerialization.data(withJSONObject: payload)
    }
}
