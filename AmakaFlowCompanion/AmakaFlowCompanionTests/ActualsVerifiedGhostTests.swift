//
//  ActualsVerifiedGhostTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2387: verified deltas + editor ghost precedence.
//

import XCTest
@testable import AmakaFlowCompanion

final class ActualsVerifiedGhostTests: XCTestCase {
    private var db: AppDatabase!
    private var repo: ActualsRepository!

    override func setUp() async throws {
        db = try AppDatabase.makeTestDatabase()
        repo = ActualsRepository(database: db)
    }

    override func tearDown() async throws {
        repo = nil
        db = nil
    }

    // MARK: - Deltas

    func testWeightIncreaseDeltaVsPlan() {
        let squat = ExerciseActual(
            id: "back_squat",
            name: "Back squat",
            planned: ExerciseActualPlanned(sets: 3, reps: 5, weightKg: 85),
            confirmation: .adjusted,
            actualSets: 3,
            actualReps: 5,
            actualWeightKg: 90
        )
        XCTAssertEqual(squat.planDelta.label, "+5 KG VS PLAN")
        XCTAssertFalse(squat.planDelta.isAsPlanned)
        XCTAssertEqual(squat.actualDisplayLine, "3 × 5 · 90 KG")
    }

    func testAsPlannedDelta() {
        let rdl = ExerciseActual(
            id: "rdl",
            name: "Romanian deadlift",
            planned: ExerciseActualPlanned(sets: 3, reps: 8, weightKg: 70),
            confirmation: .asPlanned
        )
        XCTAssertEqual(rdl.planDelta.label, "AS PLANNED")
        XCTAssertTrue(rdl.planDelta.isAsPlanned)
    }

    func testSetsChangeWithSameLoadIsAdjusted() {
        let squat = ExerciseActual(
            id: "back_squat",
            name: "Back squat",
            planned: ExerciseActualPlanned(sets: 4, reps: 8, weightKg: 85),
            confirmation: .adjusted,
            actualSets: 3,
            actualReps: 8,
            actualWeightKg: 85
        )
        XCTAssertEqual(squat.planDelta.label, ActualsCopy.verifiedAdjustedDelta)
        XCTAssertFalse(squat.planDelta.isAsPlanned)
    }

    func testVerifiedRowsMatchHandoffSample() {
        var session = ActualsFillInSession.lowerBodyPosteriorSample()
        session.exercises[0].confirmation = .adjusted
        session.exercises[0].actualWeightKg = 90
        for index in 1..<session.exercises.count {
            session.exercises[index].confirmation = .asPlanned
        }
        let rows = ActualsVerifiedDeltas.rows(from: session.exercises)
        XCTAssertEqual(rows[0].deltaLabel, "+5 KG VS PLAN")
        XCTAssertEqual(rows[1].deltaLabel, "AS PLANNED")
        XCTAssertEqual(
            ActualsVerifiedDeltas.calloutBody(sourceName: "Strava", rpe: 8),
            "Strava metrics + your actuals + RPE 8 — counted once in Progress."
        )
        XCTAssertEqual(ActualsCopy.verifiedVsPlanHeader, "WHAT YOU DID · VS PLAN")
    }

    // MARK: - Ghost feed

    func testGhostPrefersLastActualOverPrescription() {
        let resolved = ActualsGhostFeed.resolve(
            prescription: ActualsGhostPrescription(sets: 3, reps: 5, weightKg: 85),
            lastActual: ActualsGhostActual(sets: 3, reps: 5, weightKg: 90)
        )
        XCTAssertEqual(resolved.weightKg, 90)
        XCTAssertEqual(resolved.source, .lastActual)
        XCTAssertTrue(resolved.showsLastTime)
    }

    func testGhostFallsBackToPrescriptionWhenNoActual() {
        let resolved = ActualsGhostFeed.resolve(
            prescription: ActualsGhostPrescription(sets: 3, reps: 8, weightKg: 70),
            lastActual: nil
        )
        XCTAssertEqual(resolved.weightKg, 70)
        XCTAssertEqual(resolved.source, .prescription)
        XCTAssertFalse(resolved.showsLastTime)
    }

    func testApplyGhostsToEditorDraft() {
        var draft = DDEditorExerciseDraft(
            name: "Back squat",
            sets: 3,
            reps: 5,
            weightKg: 85
        )
        ActualsGhostFeed.apply(
            to: &draft,
            lastActual: ActualsGhostActual(sets: 3, reps: 5, weightKg: 90)
        )
        XCTAssertEqual(draft.weightKg, 90)
        XCTAssertTrue(draft.showsLastTime)
        XCTAssertTrue(draft.summaryLine.contains("LAST TIME"))
    }

    func testEditorSeedAppliesGhostLookup() {
        final class Lookup: ActualsGhostLookingUp {
            func latestActual(exerciseKey: String) throws -> ActualsGhostActual? {
                if exerciseKey == "back_squat" {
                    return ActualsGhostActual(sets: 3, reps: 5, weightKg: 90)
                }
                return nil
            }
        }
        let previous = DDEditorSeed.ghostLookup
        DDEditorSeed.ghostLookup = Lookup()
        defer { DDEditorSeed.ghostLookup = previous }

        let seed = DDEditorSeed.initialState(mode: .backfill, workout: nil)
        let squat = seed.blocks.flatMap(\.exercises).first { $0.name == "Back squat" }
        XCTAssertEqual(squat?.weightKg, 90)
        XCTAssertEqual(squat?.showsLastTime, true)

        let rdl = seed.blocks.flatMap(\.exercises).first { $0.name == "Romanian deadlift" }
        XCTAssertEqual(rdl?.weightKg, 70)
        XCTAssertEqual(rdl?.showsLastTime, false)
    }

    func testRepositoryLatestActualFromVerifiedSession() throws {
        var session = ActualsFillInSession.lowerBodyPosteriorSample(id: "ghost_sess")
        session.exercises[0].confirmation = .adjusted
        session.exercises[0].actualWeightKg = 90
        for index in 1..<session.exercises.count {
            session.exercises[index].confirmation = .asPlanned
        }
        session.rpe = 8
        session.verified = true
        try repo.saveVerifiedSession(session)

        let last = try repo.latestActual(exerciseKey: "back_squat")
        XCTAssertEqual(last?.weightKg, 90)
        XCTAssertNil(try repo.latestActual(exerciseKey: "unknown_move"))
    }

    func testExerciseKeyNormalization() {
        XCTAssertEqual(ActualsGhostFeed.exerciseKey(forName: "Back squat"), "back_squat")
        XCTAssertEqual(ActualsGhostFeed.exerciseKey(forName: "Romanian deadlift"), "romanian_deadlift")
    }

    func testMarkingVerifiedPreservesSourceProvider() {
        var fill = ActualsFillInSession.lowerBodyPosteriorSample(id: "provider_card")
        fill.rpe = 8
        let card = ActualsTodayDemoCard(
            id: fill.id,
            kind: .fillInDebt,
            timeLabel: "07:52",
            title: fill.title,
            stats: [("clock", "48m")],
            sourceLabel: "Apple Watch session",
            sourceProvider: .appleHealth,
            session: nil,
            activity: nil,
            fillInSession: fill
        )
        let verified = card.markingVerified(with: fill)
        XCTAssertEqual(verified.kind, .verified)
        XCTAssertEqual(verified.sourceProvider, .appleHealth)
        XCTAssertEqual(verified.sourceLabel, "Verified · RPE 8")
        XCTAssertEqual(
            ActualsCopy.sourceDisplayName(verified.sourceProvider ?? .garmin),
            "Apple Health"
        )
    }
}
