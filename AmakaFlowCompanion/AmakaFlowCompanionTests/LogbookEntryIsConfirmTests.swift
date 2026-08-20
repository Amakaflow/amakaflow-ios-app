//
//  LogbookEntryIsConfirmTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2473 — entering a value IS logging it.
//
//  David: "when I try to enter weights and then confirm that I did it, that
//  was like a double step. It should be just entered the way and confirm like
//  right away." Today `applyWheel`/`applyMetric` write the numbers and leave
//  the row unchecked, so the athlete must then tick every row — and the saved
//  session only counts ticks.
//
//  Design of record: hifi/rig-logbook2.html (Claude Design).
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class LogbookEntryIsConfirmTests: XCTestCase {

    private var db: AppDatabase!
    private var draftRepo: LogDraftRepository!
    private var actualsRepo: ActualsRepository!
    private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() async throws {
        db = try AppDatabase.makeTestDatabase()
        draftRepo = LogDraftRepository(database: db, now: { self.fixedNow })
        actualsRepo = ActualsRepository(database: db, now: { self.fixedNow })
    }

    private func strengthEntry() -> LogbookExerciseEntry {
        LogbookExerciseEntry(
            id: "row",
            name: "Dumbbell Gorilla Row",
            planned: ExerciseActualPlanned(sets: 3, reps: 10, weightKg: 31.75),
            sets: (1...3).map { SetActual(index: $0) },
            ghosts: (1...3).map { _ in
                LogbookGhost(weightKg: 31.75, reps: 10, source: .lastActual)
            }
        )
    }

    private func metricEntry() -> LogbookExerciseEntry {
        LogbookExerciseEntry(
            id: "ski",
            name: "Ski Erg",
            planned: ExerciseActualPlanned(sets: 1, reps: 1, weightKg: nil),
            sets: [SetActual(index: 1)],
            ghosts: [],
            loggingKind: .metric,
            plannedDurationSeconds: 120
        )
    }

    private func viewModel(_ entries: [LogbookExerciseEntry]) -> LogbookViewModel {
        LogbookViewModel(
            draft: LogDraft(workoutId: "w1", title: "Hyrox upper strength", entries: entries),
            draftRepository: draftRepo,
            actualsRepository: actualsRepo,
            weightUnit: .lbs,
            now: { self.fixedNow }
        )
    }

    private func set(_ viewModel: LogbookViewModel, _ index: Int = 0) -> SetActual? {
        viewModel.draft.entries.first?.sets[index]
    }

    // MARK: - Committing the wheel logs the set

    func testCommittingTheWheelLogsTheSet() {
        let viewModel = self.viewModel([strengthEntry()])
        viewModel.openWheel(exerciseID: "row", setIndex: 1)

        viewModel.applyWheel(weightDisplay: 70, reps: 10, advance: false)

        XCTAssertEqual(set(viewModel)?.reps, 10, "the value lands")
        XCTAssertTrue(
            set(viewModel)?.isChecked ?? false,
            "and the set is logged — there is no separate tick to press"
        )
        XCTAssertEqual(
            set(viewModel)?.checkedAt, fixedNow,
            "logged at the moment it was committed"
        )
    }

    func testCommittingAMetricBoutLogsIt() {
        let viewModel = self.viewModel([metricEntry()])
        viewModel.openWheel(exerciseID: "ski", setIndex: 1)

        viewModel.applyMetric(durationSeconds: 118, calories: nil, distanceMeters: nil, advance: false)

        XCTAssertEqual(
            set(viewModel)?.durationSeconds, 118,
            "the bout time lands"
        )
        XCTAssertTrue(set(viewModel)?.isChecked ?? false, "a machine bout logs on commit too")
    }

    /// Committing nothing must not claim the set was done.
    func testCommittingAnEmptyMetricBoutDoesNotLogIt() {
        let viewModel = self.viewModel([metricEntry()])
        viewModel.openWheel(exerciseID: "ski", setIndex: 1)

        viewModel.applyMetric(durationSeconds: nil, calories: nil, distanceMeters: nil, advance: false)

        XCTAssertFalse(
            set(viewModel)?.isChecked ?? true,
            "no value means nothing was logged"
        )
    }

    // MARK: - One tap on a proposal

    /// David's other case: "you set up the workout and entered in pre-weights
    /// before and then you just click confirm."
    func testConfirmingAProposedRowLogsItAsWritten() {
        let viewModel = self.viewModel([strengthEntry()])

        viewModel.confirmProposedRow(exerciseID: "row", setIndex: 1)

        XCTAssertEqual(set(viewModel)?.weightKg, 31.75, "the proposal becomes the record")
        XCTAssertEqual(
            set(viewModel)?.reps, 10,
            "reps come from the proposal too"
        )
        XCTAssertTrue(set(viewModel)?.isChecked ?? false, "one tap, logged")
    }

    func testConfirmingIsIdempotentAndLeavesOtherSetsAlone() {
        let viewModel = self.viewModel([strengthEntry()])

        viewModel.confirmProposedRow(exerciseID: "row", setIndex: 1)
        viewModel.confirmProposedRow(exerciseID: "row", setIndex: 1)

        XCTAssertTrue(
            set(viewModel, 0)?.isChecked ?? false,
            "confirming twice leaves it logged, not toggled off"
        )
        XCTAssertFalse(set(viewModel, 1)?.isChecked ?? true, "set 2 is untouched")
        XCTAssertFalse(set(viewModel, 2)?.isChecked ?? true, "set 3 is untouched")
    }

    func testConfirmingAnUnknownRowIsANoOp() {
        let viewModel = self.viewModel([strengthEntry()])
        viewModel.confirmProposedRow(exerciseID: "nope", setIndex: 1)
        XCTAssertFalse(
            set(viewModel)?.isChecked ?? true,
            "an unknown id must not log a real row"
        )
    }

    // MARK: - It reaches the saved session

    /// The point of the change: entering values is enough to be saved, with no
    /// second confirm screen and no ticking.
    func testEnteredValuesAloneProduceASavedSession() throws {
        let viewModel = self.viewModel([strengthEntry()])
        viewModel.openWheel(exerciseID: "row", setIndex: 1)
        viewModel.applyWheel(weightDisplay: 70, reps: 10, advance: false)
        viewModel.selectRPE(7)

        let result = try viewModel.saveVerified()
        guard case .verified(let session) = result else {
            return XCTFail("expected a verified session")
        }
        let row = session.exercises.first { $0.id == "row" }
        XCTAssertEqual(row?.actualSets, 1, "the entered set counts as logged")
        XCTAssertTrue(
            row?.isLogged ?? false,
            "no ticking and no confirm screen was needed to save it"
        )
    }

    // MARK: - One tap for the whole session

    /// "Did it as written — log": the common case should not cost a walk
    /// through every row.
    func testLoggingTheSessionAsWrittenLogsEverySet() throws {
        let viewModel = self.viewModel([strengthEntry(), metricEntry()])

        let logged = viewModel.logSessionAsWritten()

        XCTAssertEqual(logged, 4, "3 strength sets + 1 machine bout")
        XCTAssertTrue(
            viewModel.draft.entries.allSatisfy { $0.sets.allSatisfy(\.isChecked) },
            "every set is logged in one action"
        )
        XCTAssertEqual(
            viewModel.draft.entries.first?.sets.first?.weightKg, 31.75,
            "each set takes its proposal as the record"
        )
    }

    func testLoggingAsWrittenLeavesAlreadyLoggedSetsAlone() {
        let viewModel = self.viewModel([strengthEntry()])
        viewModel.openWheel(exerciseID: "row", setIndex: 1)
        viewModel.applyWheel(weightDisplay: 95, reps: 6, advance: false)

        viewModel.logSessionAsWritten()

        XCTAssertEqual(
            set(viewModel)?.reps, 6,
            "a set the athlete actually entered is not overwritten by the plan"
        )
        XCTAssertTrue(
            set(viewModel, 1)?.isChecked ?? false,
            "the untouched ones still get logged"
        )
    }

    // MARK: - Finish is never gated on RPE

    func testASessionSavesWithoutAnRPE() throws {
        let viewModel = self.viewModel([strengthEntry()])
        viewModel.logSessionAsWritten()

        let result = try viewModel.saveVerified()

        guard case .verified(let session) = result else {
            return XCTFail("expected a verified session")
        }
        XCTAssertNil(session.rpe, "RPE is a question, not a toll")
        XCTAssertTrue(session.verified, "the session still saved")
    }

    func testAnRPEStillSavesWhenGiven() throws {
        let viewModel = self.viewModel([strengthEntry()])
        viewModel.logSessionAsWritten()
        viewModel.selectRPE(7)

        let result = try viewModel.saveVerified()

        guard case .verified(let session) = result else {
            return XCTFail("expected a verified session")
        }
        XCTAssertEqual(session.rpe, 7, "an answer given is an answer kept")
    }
}
