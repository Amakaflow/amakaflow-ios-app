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

    func testDuplicateExerciseNamesGetUniqueEntryIDsAndNextSetAdvances() {
        let workout = Workout(
            id: "dup_ohp",
            name: "Max Muscle Growth",
            sport: .strength,
            duration: 3600,
            blocks: [
                Block(
                    label: nil,
                    structure: .superset,
                    rounds: 1,
                    exercises: [
                        Exercise(
                            name: "Warm-up · Barbell Overhead Press",
                            canonicalName: nil,
                            sets: 1,
                            reps: "5",
                            durationSeconds: nil,
                            load: nil,
                            restSeconds: nil,
                            distance: nil,
                            notes: nil,
                            focus: nil,
                            supersetGroup: 1
                        ),
                        Exercise(
                            name: "Warm-up · Barbell Overhead Press",
                            canonicalName: nil,
                            sets: 1,
                            reps: "5",
                            durationSeconds: nil,
                            load: nil,
                            restSeconds: nil,
                            distance: nil,
                            notes: nil,
                            focus: nil,
                            supersetGroup: 1
                        )
                    ]
                ),
                Block(
                    label: nil,
                    structure: .straight,
                    rounds: 3,
                    exercises: [
                        Exercise(
                            name: "Barbell Overhead Press",
                            canonicalName: nil,
                            sets: nil,
                            reps: "8",
                            durationSeconds: nil,
                            load: nil,
                            restSeconds: 90,
                            distance: nil,
                            notes: nil,
                            focus: nil,
                            supersetGroup: nil
                        )
                    ]
                )
            ],
            source: .manual
        )
        let entries = LogbookSeeding.entries(from: workout)
        XCTAssertEqual(entries.count, 3)
        XCTAssertNotEqual(entries[0].id, entries[1].id, "duplicate names must not share focus id")
        XCTAssertEqual(Set(entries.map(\.id)).count, 3)

        let focus = LogbookWheelFocus(exerciseID: entries[0].id, setIndex: 1)
        let next = LogbookWheelNavigation.nextUnchecked(after: focus, in: entries)
        XCTAssertEqual(next?.exerciseID, entries[1].id)
        XCTAssertEqual(next?.setIndex, 1)

        let afterSecond = LogbookWheelNavigation.nextUnchecked(
            after: LogbookWheelFocus(exerciseID: entries[1].id, setIndex: 1),
            in: entries
        )
        XCTAssertEqual(afterSecond?.exerciseID, entries[2].id)
    }

    func testCardioStationsSeedMetricTimeCalStrip() {
        let workout = Workout(
            id: "hyrox_lower",
            name: "HYROX - Lower body",
            sport: .strength,
            duration: 3600,
            blocks: [
                Block(
                    label: nil,
                    structure: .straight,
                    rounds: 1,
                    exercises: [
                        Exercise(
                            name: "Jump Rope",
                            canonicalName: nil,
                            sets: nil,
                            reps: "1",
                            durationSeconds: nil,
                            load: nil,
                            restSeconds: nil,
                            distance: nil,
                            notes: nil,
                            focus: nil,
                            supersetGroup: nil
                        )
                    ]
                ),
                Block(
                    label: nil,
                    structure: .straight,
                    rounds: 3,
                    exercises: [
                        Exercise(
                            name: "Back Squat",
                            canonicalName: nil,
                            sets: nil,
                            reps: "5",
                            durationSeconds: nil,
                            load: ExerciseLoad(value: 85, unit: "kg"),
                            restSeconds: 90,
                            distance: nil,
                            notes: nil,
                            focus: nil,
                            supersetGroup: nil
                        )
                    ]
                )
            ],
            source: .manual
        )
        let entries = LogbookSeeding.entries(from: workout)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].loggingKind, .metric)
        XCTAssertEqual(entries[0].sets.count, 1)
        XCTAssertEqual(entries[0].plannedLine, "PLANNED TIME / CAL")
        XCTAssertEqual(entries[1].loggingKind, .strength)
        XCTAssertEqual(entries[1].planned.sets, 3)
    }

    func testTimedStationSeedsDuration() {
        let workout = Workout(
            id: "timed",
            name: "Bike",
            sport: .cycling,
            duration: 600,
            blocks: [
                Block(
                    label: nil,
                    structure: .straight,
                    rounds: 1,
                    exercises: [
                        Exercise(
                            name: "Assault Bike",
                            canonicalName: nil,
                            sets: nil,
                            reps: nil,
                            durationSeconds: 90,
                            load: nil,
                            restSeconds: nil,
                            distance: nil,
                            notes: nil,
                            focus: nil,
                            supersetGroup: nil
                        )
                    ]
                )
            ],
            source: .manual
        )
        let entries = LogbookSeeding.entries(from: workout)
        XCTAssertEqual(entries[0].loggingKind, .metric)
        XCTAssertEqual(entries[0].plannedDurationSeconds, 90)
        XCTAssertEqual(entries[0].plannedLine, "PLANNED 1:30")
    }

    func testRoundsAsSetsSeedsLogbookRows() {
        // Straight block, sets nil, rounds 6 → detail "6 ROUNDS" / "6 × 8".
        let workout = Workout(
            id: "upper_pump",
            name: "Upper Body Pump Workout",
            sport: .strength,
            duration: 2400,
            blocks: [
                Block(
                    label: "Warm-up",
                    structure: .straight,
                    rounds: 1,
                    exercises: [
                        Exercise(
                            name: "Warm Up",
                            canonicalName: nil,
                            sets: nil,
                            reps: nil,
                            durationSeconds: 300,
                            load: nil,
                            restSeconds: nil,
                            distance: nil,
                            notes: nil,
                            focus: nil,
                            supersetGroup: nil
                        )
                    ]
                ),
                Block(
                    label: nil,
                    structure: .straight,
                    rounds: 6,
                    exercises: [
                        Exercise(
                            name: "Dumbbell Bench Press",
                            canonicalName: nil,
                            sets: nil,
                            reps: "8",
                            durationSeconds: nil,
                            load: nil,
                            restSeconds: 60,
                            distance: nil,
                            notes: nil,
                            focus: nil,
                            supersetGroup: nil
                        )
                    ]
                ),
                Block(
                    label: nil,
                    structure: .straight,
                    rounds: 4,
                    exercises: [
                        Exercise(
                            name: "One-Arm Dumbbell Row",
                            canonicalName: nil,
                            sets: nil,
                            reps: "8",
                            durationSeconds: nil,
                            load: nil,
                            restSeconds: 60,
                            distance: nil,
                            notes: nil,
                            focus: nil,
                            supersetGroup: nil
                        )
                    ]
                )
            ],
            source: .manual
        )
        let entries = LogbookSeeding.entries(from: workout)
        XCTAssertEqual(entries.count, 2, "warmup skipped; two lift blocks")
        XCTAssertEqual(entries[0].name, "Dumbbell Bench Press")
        XCTAssertEqual(entries[0].planned.sets, 6)
        XCTAssertEqual(entries[0].sets.count, 6)
        XCTAssertEqual(entries[0].planned.reps, 8)
        XCTAssertEqual(entries[1].planned.sets, 4)
        XCTAssertEqual(entries[1].sets.count, 4)
    }

    func testUnconfirmedExpandLeavesCellsEmpty() {
        let exercise = ExerciseActual(
            id: "rdl",
            name: "Romanian deadlift",
            planned: ExerciseActualPlanned(sets: 3, reps: 8, weightKg: 70)
        )
        let sets = LogbookRollup.expandSets(from: exercise, now: fixedNow)
        XCTAssertEqual(sets.count, 3)
        XCTAssertTrue(sets.allSatisfy { $0.weightKg == nil && $0.reps == nil && !$0.isChecked })
    }

    func testSameAsLastTimeCopiesGhostIntoFocusedSet() {
        var draft = sampleDraft()
        draft.entries[0].ghosts = [
            LogbookGhost(weightKg: 42.5, reps: 6, source: .lastActual),
            LogbookGhost(weightKg: 42.5, reps: 6, source: .lastActual)
        ]
        draft.entries[0].sets[0].weightKg = 100
        draft.entries[0].sets[0].reps = 3
        let vm = LogbookViewModel(
            draft: draft,
            draftRepository: draftRepo,
            actualsRepository: actualsRepo,
            weightUnit: .kg,
            now: { self.fixedNow }
        )
        vm.openWheel(exerciseID: "bench", setIndex: 1)
        let ghost = vm.sameAsLastTime()
        XCTAssertEqual(ghost?.weightKg, 42.5)
        XCTAssertEqual(ghost?.reps, 6)
        XCTAssertEqual(vm.draft.entries[0].sets[0].weightKg, 42.5)
        XCTAssertEqual(vm.draft.entries[0].sets[0].reps, 6)
        XCTAssertNil(vm.draft.entries[0].sets[0].checkedAt, "Same as last must not auto-check")
    }

    func testSameAsLastTimeFallsBackToPreviousSetThisSession() {
        var draft = sampleDraft()
        // Prescription-only ghosts (no real history) — like Machine Pec Deck first log.
        draft.entries[0].ghosts = [
            LogbookGhost(weightKg: nil, reps: 1, source: .prescription),
            LogbookGhost(weightKg: nil, reps: 1, source: .prescription)
        ]
        draft.entries[0].sets[0].weightKg = 7.5
        draft.entries[0].sets[0].reps = 3
        let vm = LogbookViewModel(
            draft: draft,
            draftRepository: draftRepo,
            actualsRepository: actualsRepo,
            weightUnit: .kg,
            now: { self.fixedNow }
        )
        vm.openWheel(exerciseID: "bench", setIndex: 2)
        let copied = vm.sameAsLastTime()
        XCTAssertEqual(copied?.weightKg, 7.5)
        XCTAssertEqual(copied?.reps, 3)
        XCTAssertEqual(vm.draft.entries[0].sets[1].weightKg, 7.5)
        XCTAssertEqual(vm.draft.entries[0].sets[1].reps, 3)
    }

    func testGhostDisplayConvertsWithUnit() {
        let ghost = LogbookGhost(weightKg: 40, reps: 8, source: .lastActual)
        let kgLine = ghost.displayLine(unit: .kg)
        let lbLine = ghost.displayLine(unit: .lbs)
        XCTAssertTrue(kgLine.contains("40"))
        XCTAssertNotEqual(kgLine, lbLine)
        XCTAssertTrue(lbLine.contains("× 8"))
        let expectedPounds = WeightUnitMath.formatWeight(kg: 40, unit: .lbs)
        XCTAssertTrue(lbLine.contains(expectedPounds), "expected \(expectedPounds) in \(lbLine)")
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

    func testReconcileRespectsKeepBothMemory() {
        var draft = sampleDraft()
        draft.mode = .companionPending
        draft.state = .pending
        draft.startedAt = fixedNow
        draft.lastEditedAt = fixedNow
        let device = ActualsSourceRecording(
            id: "hk_keep_both",
            provider: .appleHealth,
            deviceKind: .watch,
            title: "Strength",
            startDate: fixedNow.addingTimeInterval(30),
            durationSeconds: 3600,
            streamRichness: 5
        )
        let draftRecording = LogbookReconciliation.sourceRecording(for: draft)
        var memory = ActualsMergeMemory()
        ActualsMergeClassifier.applyKeepBoth(draftRecording, device, memory: &memory)
        let outcome = LogbookReconciliation.reconcile(
            draft: draft,
            deviceSessions: [device],
            now: fixedNow,
            memory: memory
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

    func testFillInSessionKeepsPerSetWeightsForVerifiedLine() {
        var draft = sampleDraft()
        draft.entries[0].sets[0].weightKg = 100
        draft.entries[0].sets[0].reps = 6
        draft.entries[0].sets[0].checkedAt = fixedNow
        draft.entries[0].sets[1].weightKg = 40
        draft.entries[0].sets[1].reps = 8
        draft.entries[0].sets[1].checkedAt = fixedNow
        let session = LogbookRollup.fillInSession(from: draft, verified: true)
        XCTAssertEqual(session.exercises[0].sets.count, 2)
        XCTAssertEqual(session.exercises[0].actualDisplayLine, "100×6 · 40×8 KG")
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
        // Load plans are name-keyed (shared ghosts across duplicate stations).
        let storedTargets = try draftRepo.loadPlan(
            workoutId: "w1",
            exerciseKey: ActualsGhostFeed.exerciseKey(forName: "Bench Press")
        )
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

    func testCompanionPendingSavePersistsDraftWithoutVerifiedActuals() throws {
        var draft = sampleDraft()
        draft.mode = .companionPending
        draft.state = .pending
        draft.entries[0].sets[0].weightKg = 40
        draft.entries[0].sets[0].reps = 8
        draft.entries[0].sets[0].checkedAt = fixedNow
        draft.rpe = 8
        try draftRepo.upsert(draft)
        let vm = LogbookViewModel(
            draft: draft,
            draftRepository: draftRepo,
            actualsRepository: actualsRepo,
            weightUnit: .kg,
            now: { self.fixedNow }
        )
        let result = try vm.saveVerified()
        XCTAssertEqual(result, .companionPendingPersisted)
        XCTAssertNil(try actualsRepo.fetchSession(id: draft.id))
        let pending = try draftRepo.fetchPendingCompanionDrafts()
        XCTAssertTrue(pending.contains { $0.id == draft.id })
        XCTAssertEqual(vm.draft.state, .pending)
        XCTAssertFalse(vm.showVerifiedPayoff)
    }

    func testOpenRepStationsSeedAsOpenTarget() {
        let workout = Workout(
            id: "amrap_open",
            name: "AMRAP open",
            sport: .strength,
            duration: 1200,
            blocks: [
                Block(
                    label: nil,
                    structure: .straight,
                    rounds: 3,
                    exercises: [
                        Exercise(
                            name: "Pull-ups",
                            canonicalName: nil,
                            sets: 3,
                            reps: nil,
                            durationSeconds: nil,
                            load: nil,
                            restSeconds: nil,
                            distance: nil,
                            notes: nil,
                            focus: nil,
                            supersetGroup: nil
                        )
                    ]
                )
            ],
            source: .manual
        )
        let entries = LogbookSeeding.entries(from: workout)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].planned.reps, 0)
        XCTAssertTrue(entries[0].plannedLine.contains("OPEN"))
        XCTAssertEqual(entries[0].sets.count, 3)
    }

    func testUpsertDoesNotClobberCommittedDraft() throws {
        var draft = sampleDraft()
        draft.state = .pending
        try draftRepo.upsert(draft)
        try draftRepo.markCommitted(draftID: draft.id)
        var stale = draft
        stale.state = .pending
        stale.note = "stale overwrite"
        try draftRepo.upsert(stale)
        let loaded = try draftRepo.fetch(id: draft.id)
        XCTAssertEqual(loaded?.state, .committed)
        XCTAssertNotEqual(loaded?.note, Optional("stale overwrite"))
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
