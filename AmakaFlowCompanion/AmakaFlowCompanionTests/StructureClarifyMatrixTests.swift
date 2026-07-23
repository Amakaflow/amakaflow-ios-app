//
//  StructureClarifyMatrixTests.swift
//  AmakaFlowCompanionTests
//
//  Breadth gate: every confirmable structure type + every sport survives
//  import → clarify confirm → save (never ships inferred).
//

import XCTest
@testable import AmakaFlowCompanion

final class StructureClarifyMatrixTests: XCTestCase {

    /// User-facing structure types we expect suggest/confirm to round-trip.
    /// Aliases (`fortime`, `rounds`, `regular`) are covered separately via `.canonical`.
    private static let confirmableTypes: [StructureBlockType] = [
        .sets,
        .superset,
        .circuit,
        .emom,
        .amrap,
        .tabata,
        .forTime,
        .warmup
    ]

    private static let sports: [String] = [
        WorkoutSport.strength.rawValue,
        WorkoutSport.running.rawValue,
        WorkoutSport.cycling.rawValue,
        WorkoutSport.cardio.rawValue,
        WorkoutSport.mobility.rawValue,
        WorkoutSport.swimming.rawValue,
        WorkoutSport.other.rawValue
    ]

    // MARK: - Structure types

    func testEveryConfirmableTypePersistsAsUserConfirmedNotInferred() {
        for type in Self.confirmableTypes {
            var session = StructureClarifySession.fromSuggest(Self.suggestResult(for: type))
            XCTAssertEqual(
                session.groups.first?.type.canonical,
                type.canonical,
                "suggest should surface \(type.rawValue)"
            )
            XCTAssertEqual(session.groups.first?.structureSource, .inferred)

            // Without confirm → never persist structured inferred type.
            let unconfirmed = session.blocksForSave(leaveFlat: false)
            XCTAssertTrue(
                unconfirmed.allSatisfy { $0.structureSource != .inferred },
                "\(type.rawValue) unconfirmed must not keep inferred"
            )
            if type != .sets {
                XCTAssertTrue(
                    unconfirmed.allSatisfy { $0.type == .sets },
                    "\(type.rawValue) unconfirmed must flatten to sets"
                )
            }

            session.confirmAll()
            let saved = session.blocksForSave(leaveFlat: false)
            XCTAssertEqual(saved.count, 1, "\(type.rawValue) should save one block")
            XCTAssertEqual(saved.first?.type.canonical, type.canonical)
            XCTAssertEqual(saved.first?.structureSource, .userConfirmed)
            XCTAssertEqual(
                saved.first?.exercises.map(\.name),
                Self.exercises(for: type).map(\.name)
            )
        }
    }

    func testEveryConfirmableTypeMapsIntoWorkoutSaveRequestBlocks() {
        for type in Self.confirmableTypes {
            var session = StructureClarifySession.fromSuggest(Self.suggestResult(for: type))
            session.confirmAll()
            let blocks = session.blocksForSave(leaveFlat: false)

            var draft = SocialImportDraft(
                title: "Matrix \(type.rawValue)",
                sport: WorkoutSport.strength.rawValue,
                platform: .instagram,
                sourceURL: "https://instagram.com/reel/\(type.rawValue)",
                exercises: [],
                blocks: [],
                equipmentNote: nil,
                equipmentEmpty: true
            )
            Self.applyConfirmed(blocks, to: &draft)
            let request = draft.toWorkoutSaveRequest()
            guard let persisted = request.blocks, !persisted.isEmpty else {
                XCTFail("\(type.rawValue) missing save blocks")
                continue
            }
            XCTAssertTrue(
                persisted.allSatisfy { $0.structureSource == StructureSource.userConfirmed.rawValue },
                "\(type.rawValue) save must be user_confirmed"
            )
            XCTAssertEqual(
                persisted.first?.type,
                type.canonical.rawValue,
                "\(type.rawValue) type should survive draft→save request"
            )
        }
    }

    func testAliasTypesCanonicalizeOnConfirmSave() {
        let aliases: [(StructureBlockType, StructureBlockType)] = [
            (.fortime, .forTime),
            (.rounds, .circuit),
            (.regular, .sets)
        ]
        for (alias, expected) in aliases {
            var session = StructureClarifySession.fromSuggest(Self.suggestResult(for: alias))
            session.confirmAll()
            let saved = session.blocksForSave(leaveFlat: false)
            XCTAssertEqual(
                saved.first?.type.canonical,
                expected,
                "\(alias.rawValue) → \(expected.rawValue)"
            )
        }
    }

    // MARK: - Sports

    @MainActor
    func testEverySportSurvivesImportConfirmSavePayload() async {
        let mockAPI = MockAPIService()
        let pairing = MockPairingService()
        pairing.isPaired = true
        pairing.userProfile = UserProfile(
            id: "user-1",
            email: "david@amakaflow.com",
            name: "David",
            avatarUrl: nil
        )
        let deps = AppDependencies(
            apiService: mockAPI,
            pairingService: pairing,
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: MockChatStreamService()
        )
        let sut = SocialImportViewModel(dependencies: deps)

        for sport in Self.sports {
            mockAPI.saveWorkoutCalled = false
            mockAPI.lastSaveWorkoutRequest = nil
            mockAPI.ingestSocialURLResult = .success(Self.ingestJSON(sport: sport, type: .emom))
            mockAPI.suggestStructureResult = .success(Self.suggestResult(for: .emom))
            mockAPI.saveWorkoutResult = .success(
                Workout(
                    id: "wk-\(sport)",
                    name: "Sport \(sport)",
                    sport: WorkoutSport(rawValue: sport) ?? .other,
                    duration: 600,
                    intervals: [],
                    source: .instagram
                )
            )

            await sut.importURL("https://instagram.com/reel/sport-\(sport)", platformHint: .instagram)
            guard case .clarify = sut.phase else {
                XCTFail("\(sport): expected clarify, got \(sut.phase)")
                continue
            }
            sut.confirmAllClarifyGroups()
            await sut.saveFromClarify(leaveFlat: false)

            let request = mockAPI.lastSaveWorkoutRequest
            XCTAssertEqual(request?.sport, sport, "\(sport) must survive save payload")
            XCTAssertEqual(request?.blocks?.first?.type, "emom", "\(sport) EMOM block type")
            XCTAssertEqual(
                request?.blocks?.first?.structureSource,
                StructureSource.userConfirmed.rawValue,
                "\(sport) must be user_confirmed"
            )
            guard case .saved = sut.phase else {
                XCTFail("\(sport): expected saved, got \(sut.phase)")
                continue
            }
        }
    }

    /// Strength / running / cardio with representative structures (not only EMOM).
    @MainActor
    func testRepresentativeSportStructureCombosPersist() async {
        let combos: [(sport: String, type: StructureBlockType)] = [
            (WorkoutSport.strength.rawValue, .superset),
            (WorkoutSport.strength.rawValue, .emom),
            (WorkoutSport.running.rawValue, .forTime),
            (WorkoutSport.running.rawValue, .sets),
            (WorkoutSport.cardio.rawValue, .amrap),
            (WorkoutSport.cardio.rawValue, .tabata),
            (WorkoutSport.cycling.rawValue, .circuit),
            (WorkoutSport.mobility.rawValue, .warmup)
        ]

        let mockAPI = MockAPIService()
        let pairing = MockPairingService()
        pairing.isPaired = true
        pairing.userProfile = UserProfile(
            id: "user-1",
            email: "david@amakaflow.com",
            name: "David",
            avatarUrl: nil
        )
        let deps = AppDependencies(
            apiService: mockAPI,
            pairingService: pairing,
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: MockChatStreamService()
        )
        let sut = SocialImportViewModel(dependencies: deps)

        for combo in combos {
            mockAPI.ingestSocialURLResult = .success(
                Self.ingestJSON(sport: combo.sport, type: combo.type)
            )
            mockAPI.suggestStructureResult = .success(Self.suggestResult(for: combo.type))
            mockAPI.saveWorkoutResult = .success(
                Workout(
                    id: "combo-\(combo.sport)-\(combo.type.rawValue)",
                    name: "Combo",
                    sport: WorkoutSport(rawValue: combo.sport) ?? .other,
                    duration: 900,
                    intervals: [],
                    source: .instagram
                )
            )

            await sut.importURL(
                "https://instagram.com/reel/\(combo.sport)-\(combo.type.rawValue)",
                platformHint: .instagram
            )
            sut.confirmAllClarifyGroups()
            await sut.saveFromClarify(leaveFlat: false)

            let blocks = mockAPI.lastSaveWorkoutRequest?.blocks ?? []
            XCTAssertEqual(mockAPI.lastSaveWorkoutRequest?.sport, combo.sport)
            XCTAssertEqual(blocks.first?.type, combo.type.canonical.rawValue)
            XCTAssertEqual(blocks.first?.structureSource, StructureSource.userConfirmed.rawValue)
        }
    }

    // MARK: - Editor reopen after clarify save

    func testConfirmedBlocksSeedEditorV2ForStrengthRunningCardio() {
        let cases: [(StructureBlockType, String)] = [
            (.emom, WorkoutSport.strength.rawValue),
            (.sets, WorkoutSport.running.rawValue),
            (.amrap, WorkoutSport.cardio.rawValue)
        ]
        for (type, sport) in cases {
            var session = StructureClarifySession.fromSuggest(Self.suggestResult(for: type))
            session.confirmAll()
            let blocks = session.blocksForSave(leaveFlat: false)
            var draft = SocialImportDraft(
                title: "Editor \(type.rawValue)",
                sport: sport,
                platform: .instagram,
                sourceURL: nil,
                exercises: [],
                blocks: [],
                equipmentNote: nil,
                equipmentEmpty: true
            )
            Self.applyConfirmed(blocks, to: &draft)
            let workout = draft.toPreviewWorkout()
            let editor = EditorV2Session.from(mode: .edit, workout: workout)
            XCTAssertFalse(editor.exercises.isEmpty, "\(type.rawValue)/\(sport) editor empty")
            XCTAssertEqual(
                editor.exercises.map(\.name),
                Self.exercises(for: type).map(\.name),
                "\(type.rawValue)/\(sport) exercise order"
            )
        }
    }

    // MARK: - Helpers

    /// Mirror `SocialImportViewModel.applyConfirmedStructure` without needing a live VM.
    private static func applyConfirmed(_ blocks: [StructureBlockModel], to draft: inout SocialImportDraft) {
        let socialBlocks: [SocialImportBlock] = blocks.map { block in
            SocialImportBlock(
                label: block.label,
                rounds: max(1, block.rounds ?? 1),
                exercises: block.exercises.map { model in
                    SocialImportExercise(
                        name: model.name,
                        sets: model.sets,
                        reps: model.reps,
                        distanceMeters: model.distanceM,
                        notes: model.notes
                    )
                },
                type: block.type.canonical.rawValue,
                restSec: block.restSec,
                structureSource: block.structureSource.rawValue
            )
        }
        draft.blocks = socialBlocks
        draft.exercises = socialBlocks.flatMap(\.exercises)
    }

    private static func exercises(for type: StructureBlockType) -> [StructureExerciseModel] {
        switch type.canonical {
        case .emom:
            return [
                .init(name: "Power Clean", reps: 5),
                .init(name: "Push Press", reps: 8)
            ]
        case .amrap:
            return [
                .init(name: "Wall Balls", reps: 20),
                .init(name: "Burpees", reps: 10)
            ]
        case .tabata:
            return [
                .init(name: "Assault Bike", notes: "all out"),
                .init(name: "Rest", notes: "10s")
            ]
        case .forTime:
            return [
                .init(name: "Run", distanceM: 400),
                .init(name: "Run", distanceM: 400)
            ]
        case .warmup:
            return [
                .init(name: "Easy Ski", distanceM: 500),
                .init(name: "Air Squats", reps: 10)
            ]
        case .superset:
            return [
                .init(name: "Bench Press", reps: 8),
                .init(name: "Pull Ups", reps: 8)
            ]
        case .circuit:
            return [
                .init(name: "Ski", distanceM: 300),
                .init(name: "Farmers Walk", distanceM: 40)
            ]
        case .sets, .regular:
            return [
                .init(name: "Easy Run", distanceM: 1600),
                .init(name: "Strides", reps: 4)
            ]
        case .fortime, .rounds:
            // Canonicalized above — unreachable, but keep switch exhaustive.
            return [
                .init(name: "Move A", reps: 10),
                .init(name: "Move B", reps: 10)
            ]
        }
    }

    private static func suggestResult(for type: StructureBlockType) -> StructureSuggestResult {
        let exercises = exercises(for: type)
        let rounds: Int? = {
            switch type.canonical {
            case .emom: return 10
            case .amrap, .forTime: return 12
            case .tabata: return 8
            case .superset, .circuit, .warmup: return 4
            default: return 1
            }
        }()
        return StructureSuggestResult(
            exercises: exercises,
            suggestions: [
                .init(
                    type: type,
                    label: type.displayLabel,
                    rounds: rounds,
                    restSec: type.canonical == .superset ? 90 : nil,
                    exerciseNames: exercises.map(\.name),
                    exerciseIndices: Array(exercises.indices),
                    structureSource: .inferred
                )
            ],
            blocks: []
        )
    }

    private static func ingestJSON(sport: String, type: StructureBlockType) -> Data {
        let exercises = exercises(for: type)
        let payload: [String: Any] = [
            "title": "\(sport) \(type.rawValue)",
            "sport": sport,
            "creator": "matrix_coach",
            "caption": "matrix fixture for \(type.rawValue)",
            "blocks": [
                ["exercises": exercises.map { ex -> [String: Any] in
                    var row: [String: Any] = ["name": ex.name]
                    if let reps = ex.reps { row["reps"] = reps }
                    if let sets = ex.sets { row["sets"] = sets }
                    if let distance = ex.distanceM { row["distance_m"] = distance }
                    return row
                }]
            ]
        ]
        // swiftlint:disable:next force_try
        return try! JSONSerialization.data(withJSONObject: payload)
    }
}
