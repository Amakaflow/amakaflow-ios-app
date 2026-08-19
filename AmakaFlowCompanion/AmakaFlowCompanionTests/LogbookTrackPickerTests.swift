//
//  LogbookTrackPickerTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2462 slice 3 — the athlete's control over what each exercise logs.
//  Turning a field off must remove it everywhere, stick across a reopen, and
//  never leave a row with nowhere to log.
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class LogbookTrackPickerTests: XCTestCase {

    private var db: AppDatabase!
    private var draftRepo: LogDraftRepository!
    private var actualsRepo: ActualsRepository!
    private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() async throws {
        db = try AppDatabase.makeTestDatabase()
        draftRepo = LogDraftRepository(database: db, now: { self.fixedNow })
        actualsRepo = ActualsRepository(database: db, now: { self.fixedNow })
    }

    private func makeViewModel(_ entries: [LogbookExerciseEntry]) -> LogbookViewModel {
        LogbookViewModel(
            draft: LogDraft(title: "Hyrox upper", entries: entries),
            draftRepository: draftRepo,
            actualsRepository: actualsRepo,
            weightUnit: .lbs,
            now: { self.fixedNow }
        )
    }

    private func skiErg() -> LogbookExerciseEntry {
        LogbookExerciseEntry(
            id: "ski_erg",
            name: "Ski Erg",
            planned: ExerciseActualPlanned(sets: 3, reps: 1, weightKg: nil),
            sets: [SetActual(index: 1)],
            ghosts: [],
            loggingKind: .metric,
            plannedDurationSeconds: 120,
            plannedDistanceMeters: 500
        )
    }

    private func chinUp() -> LogbookExerciseEntry {
        LogbookExerciseEntry(
            id: "chin_up",
            name: "Chin-Up",
            planned: ExerciseActualPlanned(sets: 3, reps: 10, weightKg: nil),
            sets: [SetActual(index: 1)],
            ghosts: []
        )
    }

    private func entry(_ viewModel: LogbookViewModel, _ id: String) -> LogbookExerciseEntry? {
        viewModel.draft.entries.first { $0.id == id }
    }

    // MARK: - Turning a field off

    /// David's case: distance is not wanted on the ski, so it goes.
    func testTurningDistanceOffRemovesItFromTheSkiErg() {
        let viewModel = makeViewModel([skiErg()])
        XCTAssertEqual(entry(viewModel, "ski_erg")?.trackedFields, [.time, .distance])

        viewModel.toggleTrackedField(exerciseID: "ski_erg", field: .distance)

        XCTAssertEqual(
            entry(viewModel, "ski_erg")?.trackedFields, [.time],
            "distance must be gone even though the plan proposed it"
        )
        XCTAssertFalse(entry(viewModel, "ski_erg")?.tracks(.distance) ?? true)
    }

    func testTurningAFieldOnAddsIt() {
        let viewModel = makeViewModel([chinUp()])
        XCTAssertEqual(entry(viewModel, "chin_up")?.trackedFields, [.reps])

        viewModel.toggleTrackedField(exerciseID: "chin_up", field: .weight)

        XCTAssertEqual(
            entry(viewModel, "chin_up")?.trackedFields, [.weight, .reps],
            "＋ Weight promotes the chin-up, in canonical column order"
        )
        XCTAssertTrue(
            entry(viewModel, "chin_up")?.showsAddedLoad ?? false,
            "the load added this way is ADDED load — +25, not 200"
        )
    }

    func testTogglingIsReversible() {
        let viewModel = makeViewModel([skiErg()])
        viewModel.toggleTrackedField(exerciseID: "ski_erg", field: .distance)
        viewModel.toggleTrackedField(exerciseID: "ski_erg", field: .distance)
        XCTAssertEqual(entry(viewModel, "ski_erg")?.trackedFields, [.time, .distance])
    }

    // MARK: - A row always has somewhere to log

    /// Written so it can only pass because of the guard. Turning off the only
    /// field must leave THAT field on — not fall back to the plan's defaults,
    /// which is what an unguarded toggle does (empty override → nil → defaults)
    /// and which would look identical on a chin-up whose default is [.reps].
    func testTheLastFieldCannotBeRemoved() {
        let viewModel = makeViewModel([chinUp()])
        viewModel.toggleTrackedField(exerciseID: "chin_up", field: .weight)
        viewModel.toggleTrackedField(exerciseID: "chin_up", field: .reps)
        XCTAssertEqual(
            entry(viewModel, "chin_up")?.trackedFields, [.weight],
            "precondition: weight alone"
        )

        viewModel.toggleTrackedField(exerciseID: "chin_up", field: .weight)

        XCTAssertEqual(
            entry(viewModel, "chin_up")?.trackedFields, [.weight],
            "the only remaining field stays — falling back to [.reps] here would "
                + "mean the guard is gone and the athlete's choice was discarded"
        )
    }

    func testARowNeverEndsUpWithNothingToLog() {
        let viewModel = makeViewModel([chinUp()])
        for field in LogbookTrackedField.allCases {
            viewModel.toggleTrackedField(exerciseID: "chin_up", field: field)
            viewModel.toggleTrackedField(exerciseID: "chin_up", field: field)
        }
        XCTAssertFalse(
            entry(viewModel, "chin_up")?.trackedFields.isEmpty ?? true,
            "however the chips are mashed, something remains loggable"
        )
    }

    func testAFieldCanBeRemovedOnceAnotherIsOn() {
        let viewModel = makeViewModel([chinUp()])
        viewModel.toggleTrackedField(exerciseID: "chin_up", field: .weight)
        viewModel.toggleTrackedField(exerciseID: "chin_up", field: .reps)
        XCTAssertEqual(
            entry(viewModel, "chin_up")?.trackedFields, [.weight],
            "with two on, either may go"
        )
    }

    // MARK: - Which chips are offered

    func testChipsOfferedMatchTheKindOfStation() {
        XCTAssertEqual(
            LogbookTrackedField.offered(for: .metric, tracking: [.time]),
            [.time, .distance, .calories],
            "a machine offers time, distance and calories — never a load"
        )
        XCTAssertEqual(
            LogbookTrackedField.offered(for: .strength, tracking: [.reps]),
            [.weight, .reps, .time],
            "a lift offers reps, load, and time for holds"
        )
    }

    func testAnActiveFieldIsAlwaysOfferedEvenIfUnusualForTheKind() {
        XCTAssertEqual(
            LogbookTrackedField.offered(for: .strength, tracking: [.reps, .calories]),
            [.weight, .reps, .time, .calories],
            "a field already in use must never vanish from the control"
        )
    }

    // MARK: - Unknown exercise

    func testTogglingAnUnknownExerciseIsANoOp() {
        let viewModel = makeViewModel([chinUp()])
        viewModel.toggleTrackedField(exerciseID: "not_here", field: .weight)
        XCTAssertEqual(entry(viewModel, "chin_up")?.trackedFields, [.reps])
    }

    // MARK: - The choice sticks

    /// Persisted through `touch()`, so reopening the draft next week shows the
    /// exercise the way it was left.
    func testTheChoiceSurvivesReloadingTheDraft() throws {
        let viewModel = makeViewModel([skiErg()])
        viewModel.toggleTrackedField(exerciseID: "ski_erg", field: .distance)

        let reloaded = try draftRepo.fetch(id: viewModel.draft.id)
        XCTAssertEqual(
            reloaded?.entries.first?.trackedFields, [.time],
            "the athlete's choice must be on disk, not just in memory"
        )
    }
}
