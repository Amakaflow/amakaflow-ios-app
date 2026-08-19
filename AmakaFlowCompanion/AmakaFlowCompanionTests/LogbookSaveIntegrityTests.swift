//
//  LogbookSaveIntegrityTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2472 — a saved session must contain every exercise the athlete had.
//
//  Reported from the device: a Hyrox session with six moves saved as
//  "1 OF 1 CONFIRMED" — one exercise. Mechanism: `fillInSession` counts only
//  CHECKED sets, so an exercise whose values were entered but never ticked
//  lands with `actualSets == 0`, and `saveVerified` then compactMaps it out
//  of existence. Entering without ticking silently deleted the work.
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class LogbookSaveIntegrityTests: XCTestCase {

    private var db: AppDatabase!
    private var draftRepo: LogDraftRepository!
    private var actualsRepo: ActualsRepository!
    private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() async throws {
        db = try AppDatabase.makeTestDatabase()
        draftRepo = LogDraftRepository(database: db, now: { self.fixedNow })
        actualsRepo = ActualsRepository(database: db, now: { self.fixedNow })
    }

    private func entry(
        _ id: String, _ name: String, reps: Int = 10, weightKg: Double? = nil,
        checked: Bool, filled: Bool = true, sets: Int = 3
    ) -> LogbookExerciseEntry {
        LogbookExerciseEntry(
            id: id,
            name: name,
            planned: ExerciseActualPlanned(sets: sets, reps: reps, weightKg: weightKg),
            sets: (1...sets).map { index in
                SetActual(
                    index: index,
                    weightKg: filled ? weightKg : nil,
                    reps: filled ? reps : nil,
                    checkedAt: checked ? fixedNow : nil
                )
            },
            ghosts: []
        )
    }

    private func viewModel(_ entries: [LogbookExerciseEntry], rpe: Int? = 7) -> LogbookViewModel {
        var draft = LogDraft(
            workoutId: "w1",
            title: "Steven Collins workout — Hyrox upper strength",
            entries: entries
        )
        draft.rpe = rpe
        return LogbookViewModel(
            draft: draft,
            draftRepository: draftRepo,
            actualsRepository: actualsRepo,
            weightUnit: .lbs,
            now: { self.fixedNow }
        )
    }

    // MARK: - Defect 1: nothing may be dropped

    /// The reported bug, reduced: six moves in, one comes back.
    func testEveryExerciseSurvivesTheSaveEvenWhenOnlyOneWasTicked() throws {
        let viewModel = self.viewModel([
            entry("chin", "Chin-Up", checked: false),
            entry("row", "Dumbbell Gorilla Row", weightKg: 31.75, checked: false),
            entry("ghd", "GHD Sit-Up", checked: false),
            entry("slam", "Medicine Ball Slam", weightKg: 9, checked: false),
            entry("push", "Explosive Push-Up", reps: 8, checked: true),
            entry("ski", "Ski Erg", checked: false)
        ])

        let result = try viewModel.saveVerified()
        guard case .verified(let session) = result else {
            return XCTFail("expected a verified session")
        }

        XCTAssertEqual(
            session.exercises.count, 6,
            "all six moves must reach the saved session — got \(session.exercises.map(\.name))"
        )
        XCTAssertEqual(
            Set(session.exercises.map(\.name)),
            ["Chin-Up", "Dumbbell Gorilla Row", "GHD Sit-Up",
             "Medicine Ball Slam", "Explosive Push-Up", "Ski Erg"]
        )
    }

    /// The entered values were never lost — an unchecked filled set is a
    /// TARGET and goes to the load plan as next time's ghost (a deliberate
    /// rule, covered by testSaveCountCheckedOnlyAndTargetsExcludedFromActuals).
    /// What AMA-2472 fixes is that the EXERCISE vanished with them.
    func testAnEnteredButUntickedExerciseIsKeptAndItsValuesGoToTheLoadPlan() throws {
        let rowEntry = entry("row", "Dumbbell Gorilla Row", weightKg: 31.75, checked: false)
        let viewModel = self.viewModel([
            rowEntry,
            entry("push", "Explosive Push-Up", reps: 8, checked: true)
        ])

        let result = try viewModel.saveVerified()
        guard case .verified(let session) = result else {
            return XCTFail("expected a verified session")
        }
        let row = session.exercises.first { $0.id == "row" }
        XCTAssertNotNil(row, "the exercise must still be in the session")
        XCTAssertEqual(row?.confirmation, .notLogged, "and honestly marked")

        let targets = LogbookRollup.loadPlanTargets(from: rowEntry)
        XCTAssertEqual(targets.count, 3, "the entered values survive as targets")
        XCTAssertEqual(targets.first?.weightKg, 31.75, "nothing was thrown away")
    }

    /// An exercise genuinely left blank stays present and reads as not logged,
    /// rather than vanishing or being invented as done.
    func testAnUntouchedExerciseIsKeptAndReportedAsNotLogged() throws {
        let viewModel = self.viewModel([
            entry("push", "Explosive Push-Up", reps: 8, checked: true),
            entry("ski", "Ski Erg", checked: false, filled: false)
        ])

        let result = try viewModel.saveVerified()
        guard case .verified(let session) = result else {
            return XCTFail("expected a verified session")
        }
        let ski = session.exercises.first { $0.id == "ski" }
        XCTAssertNotNil(ski, "a blank exercise is still part of the session")
        XCTAssertFalse(ski?.isLogged ?? true, "and is honestly marked unlogged")
        XCTAssertEqual(
            ski?.actualDisplayLine, ActualsCopy.notLogged,
            "it must not read as a set of zeroes"
        )
        XCTAssertTrue(
            session.exercises.first { $0.id == "push" }?.isLogged ?? false,
            "the logged one is unaffected"
        )
    }

    /// Saving with nothing logged at all is still refused — the gate moves
    /// from "every exercise" to "at least one".
    func testSavingWithNothingLoggedIsStillRefused() {
        let viewModel = self.viewModel([
            entry("ski", "Ski Erg", checked: false, filled: false)
        ])
        XCTAssertThrowsError(try viewModel.saveVerified())
    }

    // MARK: - Defect 2: the workout keeps its own name

    func testSavingDoesNotRenameTheWorkout() throws {
        let viewModel = self.viewModel([entry("push", "Explosive Push-Up", checked: true)])
        let result = try viewModel.saveVerified()
        guard case .verified(let session) = result else {
            return XCTFail("expected a verified session")
        }
        XCTAssertEqual(
            session.title, "Steven Collins workout — Hyrox upper strength",
            "the plan's name survives the save"
        )
    }

    // MARK: - Defect 3: undo must actually undo

    /// Reported: "when you undo what is done it doesn't work, still stays in
    /// the same state." `applyUnverify` rebuilt the in-memory card but never
    /// told the repository, so the row stayed verified on disk and came back
    /// verified on the next read.
    func testUnverifyingAVerifiedSessionPersists() throws {
        let repo = actualsRepo!
        let sessionID = "undo_\(UUID().uuidString)"
        var session = ActualsFillInSession.lowerBodyPosteriorSample(id: sessionID)
        session.rpe = 7
        session.verified = true
        session.exercises = session.exercises.map { exercise in
            var copy = exercise
            copy.confirmation = .asPlanned
            return copy
        }
        try repo.saveVerifiedSession(session)
        XCTAssertEqual(
            try repo.fetchSession(id: sessionID)?.verified, true,
            "precondition: it is verified on disk"
        )

        let feed = ActualsTodayDemoFeed(repository: repo)
        feed.activateAfterConnect(sync: ActualsSyncProgressStore())

        feed.applyUnverify(sessionID: sessionID)

        XCTAssertEqual(
            try repo.fetchSession(id: sessionID)?.verified, false,
            "and so does the stored session — otherwise undo is cosmetic"
        )
        XCTAssertNil(
            try repo.fetchSession(id: sessionID)?.rpe,
            "the RPE goes with it"
        )
    }

    // MARK: - Defect 4: no load slot on a movement that cannot have one

    /// Reported from the verified card: "Explosive Push-Up — −×12 · −×12".
    /// A push-up has no external load, so the dash marks an empty slot that
    /// does not exist.
    func testBodyweightHistoryReadsAsRepsNotDashTimesReps() {
        let actual = ExerciseActual(
            id: "push",
            name: "Explosive Push-Up",
            planned: ExerciseActualPlanned(sets: 3, reps: 12, weightKg: nil),
            sets: (1...2).map {
                SetActual(index: $0, reps: 12, checkedAt: fixedNow)
            }
        )
        XCTAssertEqual(
            actual.actualDisplayLine, "12 · 12",
            "no load slot on a bodyweight movement"
        )
        XCTAssertFalse(
            actual.actualDisplayLine.contains("−×"),
            "the reported string must not come back"
        )
    }

    /// A loaded movement keeps its load slot, dash and all — the empty slot is
    /// meaningful there.
    func testLoadedHistoryStillShowsItsLoadSlot() {
        let actual = ExerciseActual(
            id: "row",
            name: "Dumbbell Gorilla Row",
            planned: ExerciseActualPlanned(sets: 1, reps: 10, weightKg: 31.75),
            sets: [SetActual(index: 1, weightKg: 31.75, reps: 10, checkedAt: fixedNow)]
        )
        XCTAssertTrue(
            actual.actualDisplayLine.contains("×"),
            "a loaded movement still reads load × reps"
        )
    }
}
