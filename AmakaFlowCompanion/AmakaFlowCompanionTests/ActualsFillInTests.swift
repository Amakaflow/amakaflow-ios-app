//
//  ActualsFillInTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2387: fill-in actuals — as-planned / adjust / gated CTA / RPE / local write.
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class ActualsFillInTests: XCTestCase {
    private var db: AppDatabase!
    private var repo: ActualsRepository!

    override func setUp() async throws {
        db = try AppDatabase.makeTestDatabase()
        repo = ActualsRepository(database: db, now: { Date(timeIntervalSince1970: 1_700_000_000) })
    }

    func testMarkAsPlannedConfirmsAndResetsToPlan() {
        var session = ActualsFillInSession.lowerBodyPosteriorSample()
        session.exercises[0].actualWeightKg = 90
        let vm = ActualsFillInViewModel(session: session, repository: repo)

        vm.markAsPlanned(exerciseID: "back_squat")

        let squat = vm.session.exercises.first { $0.id == "back_squat" }
        XCTAssertEqual(squat?.confirmation, .asPlanned)
        XCTAssertEqual(squat?.actualSets, 3)
        XCTAssertEqual(squat?.actualReps, 5)
        XCTAssertEqual(squat?.actualWeightKg, 85)
        XCTAssertEqual(vm.confirmedCount, 1)
        XCTAssertEqual(vm.unconfirmedCount, 3)
    }

    func testAdjustAndSteppersMarkAdjusted() {
        let vm = ActualsFillInViewModel(
            session: ActualsFillInSession.lowerBodyPosteriorSample(),
            repository: repo
        )
        vm.markAdjust(exerciseID: "back_squat")
        vm.setActualWeightKg(exerciseID: "back_squat", kilograms: 90)

        let squat = vm.session.exercises.first { $0.id == "back_squat" }
        XCTAssertEqual(squat?.confirmation, .adjusted)
        XCTAssertEqual(squat?.actualWeightKg, 90)
    }

    func testAllAsPlannedConfirmsEveryRow() {
        let vm = ActualsFillInViewModel(
            session: ActualsFillInSession.lowerBodyPosteriorSample(),
            repository: repo
        )
        vm.markAllAsPlanned()
        XCTAssertEqual(vm.unconfirmedCount, 0)
        XCTAssertTrue(vm.session.exercises.allSatisfy { $0.confirmation == .asPlanned })
    }

    func testGatedCTATitles() {
        let vm = ActualsFillInViewModel(
            session: ActualsFillInSession.lowerBodyPosteriorSample(),
            repository: repo
        )
        XCTAssertEqual(vm.saveCTATitle, "Confirm 4 more to save")
        XCTAssertFalse(vm.canSave)

        vm.markAllAsPlanned()
        XCTAssertEqual(vm.saveCTATitle, "Pick RPE to save")
        XCTAssertFalse(vm.canSave)

        vm.selectRPE(8)
        XCTAssertEqual(vm.saveCTATitle, "Save session · RPE 8")
        XCTAssertTrue(vm.canSave)
    }

    func testInvalidPreloadedRPEDoesNotEnableSave() {
        var session = ActualsFillInSession.lowerBodyPosteriorSample()
        session.exercises = session.exercises.map { exercise in
            var copy = exercise
            copy.confirmation = .asPlanned
            return copy
        }
        session.rpe = 11
        let viewModel = ActualsFillInViewModel(session: session, repository: repo)
        XCTAssertFalse(viewModel.canSave)
        session.rpe = 0
        let zeroRPE = ActualsFillInViewModel(session: session, repository: repo)
        XCTAssertFalse(zeroRPE.canSave)
    }

    func testSaveRequiresRPEEvenWhenAllConfirmed() throws {
        let vm = ActualsFillInViewModel(
            session: ActualsFillInSession.lowerBodyPosteriorSample(),
            repository: repo
        )
        vm.markAllAsPlanned()
        XCTAssertFalse(try vm.save())
        XCTAssertEqual(vm.lastSaveError, "RPE required")
        XCTAssertFalse(vm.verified)
        XCTAssertFalse(try repo.isVerified(id: vm.session.id))
    }

    func testSaveRequiresAllRowsConfirmed() throws {
        let vm = ActualsFillInViewModel(
            session: ActualsFillInSession.lowerBodyPosteriorSample(),
            repository: repo
        )
        vm.markAsPlanned(exerciseID: "back_squat")
        vm.selectRPE(7)
        XCTAssertFalse(try vm.save())
        XCTAssertEqual(vm.lastSaveError, "3 exercises unconfirmed")
        XCTAssertFalse(vm.verified)
    }

    func testAirplaneModeLocalWritePersistsVerifiedSession() throws {
        let sessionID = "airplane_\(UUID().uuidString)"
        let vm = ActualsFillInViewModel(
            session: ActualsFillInSession.lowerBodyPosteriorSample(id: sessionID),
            repository: repo
        )
        vm.markAllAsPlanned()
        vm.markAdjust(exerciseID: "back_squat")
        vm.setActualWeightKg(exerciseID: "back_squat", kilograms: 90)
        vm.selectRPE(8)

        XCTAssertTrue(try vm.save())
        XCTAssertTrue(vm.verified)

        let loaded = try repo.fetchSession(id: sessionID)
        XCTAssertNotNil(loaded)
        XCTAssertTrue(loaded?.verified == true)
        XCTAssertEqual(loaded?.rpe, 8)
        XCTAssertEqual(loaded?.exercises.count, 4)

        let squat = loaded?.exercises.first { $0.id == "back_squat" }
        XCTAssertEqual(squat?.confirmation, .adjusted)
        XCTAssertEqual(squat?.actualWeightKg, 90)

        let rdl = loaded?.exercises.first { $0.id == "rdl" }
        XCTAssertEqual(rdl?.confirmation, .asPlanned)
        XCTAssertEqual(rdl?.actualWeightKg, 70)
    }

    func testAccessibilityIDsMatchHandoff() {
        let squat = ExerciseActual(
            id: "back_squat",
            name: "Back squat",
            planned: ExerciseActualPlanned(sets: 3, reps: 5, weightKg: 85)
        )
        XCTAssertEqual(squat.accessibilityRowID, "af_actuals_row_back_squat")
        XCTAssertEqual(squat.accessibilityAsPlannedID, "af_actuals_row_back_squat_asplanned")
        XCTAssertEqual(squat.accessibilityAdjustID, "af_actuals_row_back_squat_adjust")
        XCTAssertEqual(ActualsCopy.fillInAllAsPlannedAccessibilityID, "af_actuals_all_asplanned")
        XCTAssertEqual(ActualsCopy.fillInSaveAccessibilityID, "af_actuals_save")
        XCTAssertEqual(ActualsCopy.fillInRPEAccessibilityID(8), "af_actuals_rpe_8")
    }

    func testV4MigrationCreatesActualsTables() throws {
        let tables = try db.tableNames()
        XCTAssertTrue(tables.contains("actuals_sessions"))
        XCTAssertTrue(tables.contains("actuals_exercise_rows"))
    }
}
