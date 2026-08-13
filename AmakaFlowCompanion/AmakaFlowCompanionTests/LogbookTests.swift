//
//  LogbookTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2426: validation gate — ghosts, units, chaining, save count, reconcile, modes, rollup.
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class LogbookTests: XCTestCase {
    private var db: AppDatabase!
    private var draftRepo: LogDraftRepository!
    private var actualsRepo: ActualsRepository!
    private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() async throws {
        db = try AppDatabase.makeTestDatabase()
        draftRepo = LogDraftRepository(database: db, now: { self.fixedNow })
        actualsRepo = ActualsRepository(database: db, now: { self.fixedNow })
    }

    // MARK: - Ghosts

    func testGhostPrecedenceActualsOverPrescription() {
        let planned = ExerciseActualPlanned(sets: 3, reps: 8, weightKg: 35)
        let ghosts = LogbookGhosts.ghosts(
            setCount: 3,
            planned: planned,
            lastSetActuals: nil,
            lastExerciseActual: ActualsGhostActual(sets: 3, reps: 6, weightKg: 37.5)
        )
        XCTAssertEqual(ghosts.count, 3)
        XCTAssertEqual(ghosts[0].source, .lastActual)
        XCTAssertEqual(ghosts[0].weightKg, 37.5)
        XCTAssertEqual(ghosts[0].reps, 6)
    }

    func testGhostFallsBackToPrescription() {
        let planned = ExerciseActualPlanned(sets: 3, reps: 8, weightKg: 35)
        let ghosts = LogbookGhosts.ghosts(
            setCount: 2,
            planned: planned,
            lastSetActuals: nil,
            lastExerciseActual: nil
        )
        XCTAssertEqual(ghosts[0].source, .prescription)
        XCTAssertEqual(ghosts[0].weightKg, 35)
        XCTAssertEqual(ghosts[0].reps, 8)
    }

    func testTapGhostCopiesExactly() {
        var set = SetActual(index: 1)
        let ghost = LogbookGhost(weightKg: 40, reps: 5, source: .lastActual)
        LogbookGhosts.copyGhost(into: &set, ghost: ghost)
        XCTAssertEqual(set.weightKg, 40)
        XCTAssertEqual(set.reps, 5)
        XCTAssertNil(set.checkedAt)
    }

    func testGhostDisplayConvertsWithUnit() {
        let ghost = LogbookGhost(weightKg: 40, reps: 8, source: .lastActual)
        let kgLine = ghost.displayLine(unit: .kg)
        let lbLine = ghost.displayLine(unit: .lbs)
        XCTAssertTrue(kgLine.contains("40"))
        XCTAssertNotEqual(kgLine, lbLine)
        XCTAssertTrue(lbLine.contains("× 8"))
    }

    // MARK: - Units

    func testKgLbKgRoundTripZeroDrift() {
        XCTAssertTrue(WeightUnitMath.kgLbKgRoundTripHolds())
        for kg in WeightUnitMath.wheelValues(unit: .kg, fine: false, min: 0, max: 300) {
            let lb = WeightUnitMath.displayValue(kg: kg, unit: .lbs)
            let back = WeightUnitMath.kilograms(fromDisplay: lb, unit: .lbs)
            XCTAssertEqual(back, kg, accuracy: 1e-9, "drift at \(kg)")
        }
    }

    func testWheelValuesEmptyWhenMinExceedsMax() {
        XCTAssertEqual(WeightUnitMath.wheelValues(unit: .kg, fine: false, min: 10, max: 0), [])
    }

    func testStepsRespectedPerUnit() {
        XCTAssertEqual(WeightUnitMath.coarseStep(for: .kg), 2.5)
        XCTAssertEqual(WeightUnitMath.coarseStep(for: .lbs), 5)
        XCTAssertEqual(WeightUnitMath.fineStep(for: .kg), 1.25)
        XCTAssertEqual(WeightUnitMath.fineStep(for: .lbs), 2.5)
        let kg = WeightUnitMath.wheelValues(unit: .kg, fine: false, min: 0, max: 10)
        XCTAssertEqual(kg, [0, 2.5, 5, 7.5, 10])
        let lb = WeightUnitMath.wheelValues(unit: .lbs, fine: false, min: 0, max: 20)
        XCTAssertEqual(lb, [0, 5, 10, 15, 20])
    }

    // MARK: - Next set chaining

    func testNextSetChainsWithinThenAcrossExercises() {
        let entries = [
            LogbookExerciseEntry(
                id: "a",
                name: "A",
                planned: ExerciseActualPlanned(sets: 2, reps: 5, weightKg: 40),
                sets: [
                    SetActual(index: 1, weightKg: 40, reps: 5, checkedAt: fixedNow),
                    SetActual(index: 2, weightKg: 40, reps: 5)
                ]
            ),
            LogbookExerciseEntry(
                id: "b",
                name: "B",
                planned: ExerciseActualPlanned(sets: 1, reps: 8, weightKg: 20),
                sets: [SetActual(index: 1)]
            )
        ]
        let fromChecked = LogbookWheelFocus(exerciseID: "a", setIndex: 1)
        let next = LogbookWheelNavigation.nextUnchecked(after: fromChecked, in: entries)
        XCTAssertEqual(next?.exerciseID, "a")
        XCTAssertEqual(next?.setIndex, 2)

        let afterLastInA = LogbookWheelNavigation.nextUnchecked(
            after: LogbookWheelFocus(exerciseID: "a", setIndex: 2),
            in: entries
        )
        XCTAssertEqual(afterLastInA?.exerciseID, "b")
        XCTAssertEqual(afterLastInA?.setIndex, 1)

        // Mark B checked → stop.
        var done = entries
        done[1].sets[0].checkedAt = fixedNow
        let stop = LogbookWheelNavigation.nextUnchecked(
            after: LogbookWheelFocus(exerciseID: "b", setIndex: 1),
            in: done
        )
        XCTAssertNil(stop)
    }

    // MARK: - Save count / target pass

    func testSaveCountCheckedOnlyAndTargetsExcludedFromActuals() {
        var draft = sampleDraft()
        draft.entries[0].sets[0].weightKg = 40
        draft.entries[0].sets[0].reps = 8
        draft.entries[0].sets[0].checkedAt = fixedNow
        draft.entries[0].sets[1].weightKg = 42.5
        draft.entries[0].sets[1].reps = 8
        // set 1 unchecked = target pass
        XCTAssertEqual(draft.checkedSetCount, 1)
        XCTAssertEqual(draft.totalSetCount, 2)
        XCTAssertEqual(draft.saveCTATitle, "Save log · 1 of 2 sets")

        let actuals = LogbookRollup.actualsForSave(from: draft.entries[0])
        XCTAssertEqual(actuals.count, 1)
        let targets = LogbookRollup.loadPlanTargets(from: draft.entries[0])
        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets[0].weightKg, 42.5)
        XCTAssertNil(targets[0].checkedAt)
    }

    // MARK: - Reconciliation

    func testReconcileOverlappingDeviceMergesOnce() {
        var draft = sampleDraft()
        draft.mode = .companionPending
        draft.state = .pending
        draft.startedAt = fixedNow
        draft.lastEditedAt = fixedNow

        let device = ActualsSourceRecording(
            id: "hk_1",
            provider: .appleHealth,
            deviceKind: .watch,
            title: "Strength",
            startDate: fixedNow.addingTimeInterval(30),
            durationSeconds: 3600,
            streamRichness: 5
        )
        let outcome = LogbookReconciliation.reconcile(
            draft: draft,
            deviceSessions: [device],
            now: fixedNow
        )
        if case .merged(let id) = outcome {
            XCTAssertEqual(id, "hk_1")
        } else {
            XCTFail("expected merge, got \(outcome)")
        }

        let session = LogbookReconciliation.mergeDraft(draft, onto: device)
        XCTAssertEqual(session.id, "hk_1")
        XCTAssertFalse(LogbookReconciliation.wouldDoubleCount(
            draftID: draft.id,
            deviceSessionID: device.id,
            todayCardIDs: [device.id]
        ))
    }

    func testReconcileNonOverlappingNoMerge() {
        var draft = sampleDraft()
        draft.startedAt = fixedNow
        draft.lastEditedAt = fixedNow
        let device = ActualsSourceRecording(
            id: "hk_2",
            provider: .appleHealth,
            deviceKind: .watch,
            title: "Run",
            startDate: fixedNow.addingTimeInterval(24 * 3600),
            durationSeconds: 1800
        )
        let outcome = LogbookReconciliation.reconcile(
            draft: draft,
            deviceSessions: [device],
            now: fixedNow
        )
        XCTAssertEqual(outcome, .noOverlap)
    }

    func testTimeoutCommitsStandalone() {
        var draft = sampleDraft()
        draft.state = .pending
        draft.lastEditedAt = fixedNow.addingTimeInterval(-7 * 3600)
        let outcome = LogbookReconciliation.reconcile(
            draft: draft,
            deviceSessions: [],
            now: fixedNow
        )
        if case .timeoutCommit(let id) = outcome {
            XCTAssertEqual(id, draft.id)
        } else {
            XCTFail("expected timeout, got \(outcome)")
        }
    }

    func testLateTwinAfterCommitFlagsDuplicateFlow() {
        var draft = sampleDraft()
        draft.state = .committed
        draft.startedAt = fixedNow
        draft.lastEditedAt = fixedNow
        let device = ActualsSourceRecording(
            id: "late",
            provider: .appleHealth,
            deviceKind: .watch,
            title: "Strength",
            startDate: fixedNow,
            durationSeconds: 3600
        )
        let outcome = LogbookReconciliation.reconcile(
            draft: draft,
            deviceSessions: [device],
            now: fixedNow
        )
        XCTAssertEqual(outcome, .lateTwinRequiresDuplicateFlow)
    }

    func testReconciledDraftNeverSecondTodayCardProperty() {
        let draftID = "draft_1"
        let deviceID = "device_1"
        var pending = sampleDraft()
        pending.id = draftID
        pending.mode = .companionPending
        pending.state = .pending

        let cards = LogbookReconciliation.todayCardIDs(
            committedSessionIDs: [deviceID],
            pendingDrafts: [pending],
            reconciledDraftIDs: [draftID]
        )
        XCTAssertFalse(cards.contains(draftID))
        XCTAssertTrue(cards.contains(deviceID))
        XCTAssertFalse(
            LogbookReconciliation.wouldDoubleCount(
                draftID: draftID,
                deviceSessionID: deviceID,
                todayCardIDs: cards
            )
        )
    }

    // MARK: - Mode inference

    func testTodayCardIDsDedupesLiveDraft() {
        var live = sampleDraft()
        live.id = "live_1"
        live.mode = .live
        live.state = .live
        let cards = LogbookReconciliation.todayCardIDs(
            committedSessionIDs: [],
            pendingDrafts: [live],
            reconciledDraftIDs: []
        )
        XCTAssertEqual(cards.filter { $0 == live.id }.count, 1)
    }

    func testModeInference() {
        XCTAssertEqual(
            LogbookModeInference.infer(
                LogbookModeContext(
                    phoneTrackerActive: false,
                    watchPlanActiveWindow: false,
                    existingSessionId: "s1"
                )
            ),
            .after
        )
        XCTAssertEqual(
            LogbookModeInference.infer(
                LogbookModeContext(
                    phoneTrackerActive: true,
                    watchPlanActiveWindow: true,
                    existingSessionId: nil
                )
            ),
            .live
        )
        XCTAssertEqual(
            LogbookModeInference.infer(
                LogbookModeContext(
                    phoneTrackerActive: false,
                    watchPlanActiveWindow: true,
                    existingSessionId: nil
                )
            ),
            .companionPending
        )
    }

    // MARK: - Quick ↔ set-by-set

    func testQuickSetBySetRoundTripNoLoss() {
        var exercise = ExerciseActual(
            id: "squat",
            name: "Squat",
            planned: ExerciseActualPlanned(sets: 3, reps: 5, weightKg: 85),
            confirmation: .adjusted,
            actualSets: 3,
            actualReps: 5,
            actualWeightKg: 90
        )
        let sets = LogbookRollup.expandSets(from: exercise, now: fixedNow)
        XCTAssertEqual(sets.count, 3)
        XCTAssertTrue(sets.allSatisfy(\.isChecked))
        LogbookRollup.applySets(sets, to: &exercise)
        XCTAssertEqual(exercise.actualSets, 3)
        XCTAssertEqual(exercise.actualReps, 5)
        XCTAssertEqual(exercise.actualWeightKg, 90)
        XCTAssertEqual(exercise.sets.count, 3)

        // Back to aggregates-only Quick representation still matches.
        let rolled = LogbookRollup.rollup(from: exercise.sets, planned: exercise.planned)
        XCTAssertEqual(rolled.actualSets, exercise.actualSets)
        XCTAssertEqual(rolled.actualReps, exercise.actualReps)
        XCTAssertEqual(rolled.actualWeightKg, exercise.actualWeightKg)
    }

    // MARK: - Persistence

    func testLogDraftRoundTripAndPendingNotCommitted() throws {
        var draft = sampleDraft()
        draft.mode = .companionPending
        draft.state = .pending
        try draftRepo.upsert(draft)
        let loaded = try draftRepo.fetch(id: draft.id)
        XCTAssertEqual(loaded?.title, draft.title)
        XCTAssertEqual(loaded?.entries.count, 1)
        let pending = try draftRepo.fetchPendingCompanionDrafts()
        XCTAssertTrue(pending.contains(where: { $0.id == draft.id }))
    }

    func testViewModelSaveCountAndCheckDoesNotAutoMark() {
        let draft = sampleDraft()
        let vm = LogbookViewModel(
            draft: draft,
            draftRepository: draftRepo,
            actualsRepository: actualsRepo,
            weightUnit: .kg,
            now: { self.fixedNow }
        )
        XCTAssertEqual(vm.checkedSetCount, 0)
        vm.copyGhost(exerciseID: "bench", setIndex: 1)
        XCTAssertEqual(vm.checkedSetCount, 0, "copy must not auto-check")
        vm.toggleCheck(exerciseID: "bench", setIndex: 1)
        XCTAssertEqual(vm.checkedSetCount, 1)
        XCTAssertEqual(vm.saveCTATitle, "Save log · 1 of 2 sets")
    }

    func testVerifiedSaveWithSetsPersistsRows() throws {
        var draft = sampleDraft()
        draft.entries[0].sets[0].weightKg = 40
        draft.entries[0].sets[0].reps = 8
        draft.entries[0].sets[0].checkedAt = fixedNow
        draft.entries[0].sets[1].weightKg = 40
        draft.entries[0].sets[1].reps = 8
        draft.entries[0].sets[1].checkedAt = fixedNow
        draft.rpe = 8
        let vm = LogbookViewModel(
            draft: draft,
            draftRepository: draftRepo,
            actualsRepository: actualsRepo,
            weightUnit: .kg,
            now: { self.fixedNow }
        )
        try vm.saveVerified()
        let saved = try actualsRepo.fetchSession(id: draft.id)
        XCTAssertEqual(saved?.verified, true)
        XCTAssertEqual(saved?.exercises.first?.sets.count, 2)
        XCTAssertEqual(saved?.exercises.first?.actualSets, 2)
    }

    func testVerifiedSaveExcludesUncheckedEditedSet() throws {
        var draft = sampleDraft()
        draft.entries[0].sets[0].weightKg = 40
        draft.entries[0].sets[0].reps = 8
        draft.entries[0].sets[0].checkedAt = fixedNow
        draft.entries[0].sets[1].weightKg = 42.5
        draft.entries[0].sets[1].reps = 6
        draft.rpe = 8
        let vm = LogbookViewModel(
            draft: draft,
            draftRepository: draftRepo,
            actualsRepository: actualsRepo,
            weightUnit: .kg,
            now: { self.fixedNow }
        )
        vm.beginSave()
        try vm.saveVerified()
        let saved = try actualsRepo.fetchSession(id: draft.id)
        XCTAssertEqual(saved?.exercises.first?.sets.count, 1)
        XCTAssertEqual(saved?.exercises.first?.sets.first?.weightKg, 40)
        XCTAssertEqual(saved?.exercises.first?.actualSets, 1)
        let storedTargets = try draftRepo.loadPlan(workoutId: "w1", exerciseKey: "bench")
        XCTAssertEqual(storedTargets?.count, 1)
        XCTAssertEqual(storedTargets?.first?.weightKg, 42.5)
        XCTAssertNil(storedTargets?.first?.checkedAt)
    }

    func testLoadPlanKeysDoNotCollideAcrossWorkoutExercisePairs() throws {
        try draftRepo.saveLoadPlan(
            workoutId: "ab",
            exerciseKey: "c_d",
            targets: [SetActual(index: 1, weightKg: 40, reps: 8)]
        )
        try draftRepo.saveLoadPlan(
            workoutId: "ab_c",
            exerciseKey: "d",
            targets: [SetActual(index: 1, weightKg: 50, reps: 5)]
        )
        XCTAssertEqual(try draftRepo.loadPlan(workoutId: "ab", exerciseKey: "c_d")?.first?.weightKg, 40)
        XCTAssertEqual(try draftRepo.loadPlan(workoutId: "ab_c", exerciseKey: "d")?.first?.weightKg, 50)
    }

    func testSaveVerifiedThrowsWhenRPEMissing() {
        let vm = LogbookViewModel(
            draft: sampleDraft(),
            draftRepository: draftRepo,
            actualsRepository: actualsRepo,
            weightUnit: .kg,
            now: { self.fixedNow }
        )
        XCTAssertThrowsError(try vm.saveVerified()) { error in
            XCTAssertEqual(error as? ActualsRepositoryError, .missingRPE)
        }
    }

    func testSaveVerifiedThrowsWhenNoCheckedSets() {
        var draft = sampleDraft()
        draft.rpe = 7
        let vm = LogbookViewModel(
            draft: draft,
            draftRepository: draftRepo,
            actualsRepository: actualsRepo,
            weightUnit: .kg,
            now: { self.fixedNow }
        )
        XCTAssertThrowsError(try vm.saveVerified()) { error in
            XCTAssertEqual(error as? ActualsRepositoryError, .unconfirmedRows(0))
        }
    }

    // MARK: - Helpers

    private func sampleDraft() -> LogDraft {
        LogDraft(
            id: "draft_sample",
            workoutId: "w1",
            title: "Chest + triceps",
            subtitle: "WED · 18:10",
            startedAt: fixedNow,
            lastEditedAt: fixedNow,
            state: .pending,
            mode: .after,
            entries: [
                LogbookExerciseEntry(
                    id: "bench",
                    name: "Bench Press",
                    planned: ExerciseActualPlanned(sets: 2, reps: 8, weightKg: 35),
                    sets: [
                        SetActual(index: 1),
                        SetActual(index: 2)
                    ],
                    ghosts: [
                        LogbookGhost(weightKg: 35, reps: 8, source: .prescription),
                        LogbookGhost(weightKg: 35, reps: 8, source: .prescription)
                    ]
                )
            ]
        )
    }
}
