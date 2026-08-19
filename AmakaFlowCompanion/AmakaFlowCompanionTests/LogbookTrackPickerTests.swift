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
        XCTAssertEqual(
            entry(viewModel, "ski_erg")?.trackedFields, [.time, .distance],
            "precondition: the plan proposes both"
        )

        viewModel.toggleTrackedField(exerciseID: "ski_erg", field: .distance)

        XCTAssertEqual(
            entry(viewModel, "ski_erg")?.trackedFields, [.time],
            "distance must be gone even though the plan proposed it"
        )
        XCTAssertFalse(entry(viewModel, "ski_erg")?.tracks(.distance) ?? true)
    }

    func testTurningAFieldOnAddsIt() {
        let viewModel = makeViewModel([chinUp()])
        XCTAssertEqual(
            entry(viewModel, "chin_up")?.trackedFields, [.reps],
            "precondition: bodyweight, so reps only"
        )

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
        XCTAssertEqual(
            entry(viewModel, "ski_erg")?.trackedFields, [.time, .distance],
            "toggling twice returns to where it started"
        )
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
            [.weight, .reps],
            "a lift offers only what the strength grid can render — never a "
                + "chip that leads to a field with no wheel behind it"
        )
    }

    func testAnActiveFieldIsAlwaysOfferedEvenIfUnusualForTheKind() {
        XCTAssertEqual(
            LogbookTrackedField.offered(for: .strength, tracking: [.reps, .calories]),
            [.weight, .reps, .calories],
            "a field already in use must never vanish from the control"
        )
    }

    // MARK: - Unknown exercise

    func testTogglingAnUnknownExerciseIsANoOp() {
        let viewModel = makeViewModel([chinUp()])
        viewModel.toggleTrackedField(exerciseID: "not_here", field: .weight)
        XCTAssertEqual(
            entry(viewModel, "chin_up")?.trackedFields, [.reps],
            "an unknown id must not disturb a real entry"
        )
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

    // MARK: - No chip may lead nowhere

    /// CodeRabbit's finding: a chip the athlete can turn on must be a field
    /// they can then enter. The strength grid renders load and reps; the
    /// machine sheet renders time, metres and calories. Offering anything else
    /// creates a control that appears to work and silently does not.
    func testEveryOfferedChipHasSomewhereToEnterIt() {
        let strengthEditable: Set<LogbookTrackedField> = [.weight, .reps]
        let metricEditable: Set<LogbookTrackedField> = [.time, .distance, .calories]

        for tracking in [[LogbookTrackedField.reps], [.weight, .reps]] {
            for field in LogbookTrackedField.offered(for: .strength, tracking: tracking) {
                XCTAssertTrue(
                    strengthEditable.contains(field),
                    "\(field) is offered on a lift but the grid cannot enter it"
                )
            }
        }
        for tracking in [[LogbookTrackedField.time], [.time, .distance], [.calories]] {
            for field in LogbookTrackedField.offered(for: .metric, tracking: tracking) {
                XCTAssertTrue(
                    metricEditable.contains(field),
                    "\(field) is offered on a machine but the sheet cannot enter it"
                )
            }
        }
    }

    /// A rower bout must be loggable, not merely displayable.
    func testDistanceOnARowerRoundTripsThroughTheSet() {
        let viewModel = makeViewModel([skiErg()])
        viewModel.openWheel(exerciseID: "ski_erg", setIndex: 1)
        viewModel.applyMetric(
            durationSeconds: 112, calories: nil, distanceMeters: 500, advance: false
        )
        XCTAssertEqual(
            entry(viewModel, "ski_erg")?.sets.first?.distanceMeters, 500,
            "metres entered on a machine must persist onto the set"
        )
    }
}
