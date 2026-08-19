//
//  LogbookViewModel.swift
//  AmakaFlow
//
//  AMA-2426: notebook logbook state — grid edits, wheels, save → RPE pipeline.
//

import Combine
import Foundation

@MainActor
final class LogbookViewModel: ObservableObject { // swiftlint:disable:this type_body_length
    @Published private(set) var draft: LogDraft
    @Published var wheelFocus: LogbookWheelFocus?
    @Published var showRPE: Bool = false
    @Published var showVerifiedPayoff: Bool = false
    @Published var undoToastVisible: Bool = false
    @Published var weightUnit: WeightUnit
    @Published var fineSteps: Bool = false
    /// Filtered checked-sets session published by the last successful verified save.
    @Published private(set) var lastVerifiedSession: ActualsFillInSession?

    private let draftRepository: LogDraftRepository
    private let actualsRepository: ActualsRepository
    private let now: () -> Date
    nonisolated(unsafe) private var elapsedTimer: Timer?

    @Published private(set) var elapsedSeconds: TimeInterval = 0

    init(
        draft: LogDraft,
        draftRepository: LogDraftRepository,
        actualsRepository: ActualsRepository,
        weightUnit: WeightUnit = .kg,
        now: @escaping () -> Date = Date.init
    ) {
        self.draft = draft
        self.draftRepository = draftRepository
        self.actualsRepository = actualsRepository
        self.weightUnit = weightUnit
        self.now = now
        if draft.mode == .live {
            startElapsedTimer()
        }
    }

    var saveCTATitle: String { draft.saveCTATitle }
    var checkedSetCount: Int { draft.checkedSetCount }
    var totalSetCount: Int { draft.totalSetCount }
    var canProceedToRPE: Bool { checkedSetCount > 0 }

    var headerMeta: String {
        switch draft.mode {
        case .live:
            return "LIVE · \(formattedElapsed) · LOGBOOK"
        case .companionPending:
            // HARD CONSTRAINT documented: no live channel into native Workout app.
            return "COMPANION · PENDING · NOT ON TODAY UNTIL RECONCILE"
        case .after:
            return draft.subtitle.isEmpty
                ? "AFTER · SET BY SET"
                : "\(draft.subtitle) · GHOSTS = YOUR LAST TIME"
        }
    }

    private var formattedElapsed: String {
        let total = Int(elapsedSeconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Mutations

    func setWeightUnit(_ unit: WeightUnit) {
        weightUnit = unit
    }

    func toggleCheck(exerciseID: String, setIndex: Int, isWarmup: Bool = false) {
        guard let eIdx = draft.entries.firstIndex(where: { $0.id == exerciseID }),
              let sIdx = setRowIndex(in: draft.entries[eIdx], setIndex: setIndex, isWarmup: isWarmup) else {
            return
        }
        if draft.entries[eIdx].sets[sIdx].isChecked {
            draft.entries[eIdx].sets[sIdx].checkedAt = nil
        } else {
            let entry = draft.entries[eIdx]
            let set = entry.sets[sIdx]
            if entry.isMetric {
                if set.durationSeconds == nil, set.calories == nil, set.distanceMeters == nil {
                    copyGhost(exerciseID: exerciseID, setIndex: setIndex, isWarmup: isWarmup)
                }
            } else if set.weightKg == nil || set.reps == nil {
                // Checking with empty cells copies ghost first.
                copyGhost(exerciseID: exerciseID, setIndex: setIndex, isWarmup: isWarmup)
            }
            draft.entries[eIdx].sets[sIdx].checkedAt = now()
        }
        touch()
        refreshMetricStrip(exerciseID: exerciseID)
    }

    func copyGhost(exerciseID: String, setIndex: Int, isWarmup: Bool = false) {
        guard let eIdx = draft.entries.firstIndex(where: { $0.id == exerciseID }),
              let sIdx = setRowIndex(in: draft.entries[eIdx], setIndex: setIndex, isWarmup: isWarmup),
              let source = effectiveLastReference(exerciseID: exerciseID, setIndex: setIndex) else {
            return
        }
        LogbookGhosts.copyGhost(into: &draft.entries[eIdx].sets[sIdx], ghost: source)
        touch()
    }

    /// AMA-2473 — the athlete taps the dim proposal (plan / last time) and it
    /// is logged as written. This is the "entered pre-weights before, just
    /// click confirm" case; the wheel is only for when the number differed.
    func confirmProposedRow(exerciseID: String, setIndex: Int, isWarmup: Bool = false) {
        guard let eIdx = draft.entries.firstIndex(where: { $0.id == exerciseID }),
              let sIdx = setRowIndex(
                in: draft.entries[eIdx], setIndex: setIndex, isWarmup: isWarmup
              ) else {
            return
        }
        copyGhost(exerciseID: exerciseID, setIndex: setIndex, isWarmup: isWarmup)
        draft.entries[eIdx].sets[sIdx].checkedAt = now()
        touch()
        refreshMetricStrip(exerciseID: exerciseID)
    }

    func openWheel(exerciseID: String, setIndex: Int, isWarmup: Bool = false) {
        let mode: LogbookWheelMode = {
            if let entry = draft.entries.first(where: { $0.id == exerciseID }), entry.isMetric {
                return .metric
            }
            return .weightReps
        }()
        wheelFocus = LogbookWheelFocus(
            exerciseID: exerciseID,
            setIndex: setIndex,
            isWarmup: isWarmup,
            mode: mode
        )
        fineSteps = false
    }

    func applyWheel(weightDisplay: Double, reps: Int, advance: Bool) {
        guard let focus = wheelFocus,
              let eIdx = draft.entries.firstIndex(where: { $0.id == focus.exerciseID }),
              let sIdx = setRowIndex(
                in: draft.entries[eIdx],
                setIndex: focus.setIndex,
                isWarmup: focus.isWarmup
              ) else {
            return
        }
        let kilograms = WeightUnitMath.kilograms(fromDisplay: weightDisplay, unit: weightUnit)
        let ghost = ghost(for: focus.exerciseID, setIndex: focus.setIndex)
        // Bodyweight / unloaded: wheel sits on 0 but storage stays nil when plan + ghost have no load.
        if kilograms == 0,
           draft.entries[eIdx].planned.weightKg == nil,
           ghost?.weightKg == nil {
            draft.entries[eIdx].sets[sIdx].weightKg = nil
        } else {
            draft.entries[eIdx].sets[sIdx].weightKg = kilograms
        }
        draft.entries[eIdx].sets[sIdx].reps = reps
        // AMA-2473: entering a value IS logging it. This used to leave the row
        // unchecked, so the athlete entered the numbers and then had to tick
        // every row — the double step David reported.
        draft.entries[eIdx].sets[sIdx].checkedAt = now()
        touch()
        if advance {
            advanceWheel(from: focus)
        }
    }

    func applyMetric(durationSeconds: Int?, calories: Int?, distanceMeters: Double?, advance: Bool) {
        guard let focus = wheelFocus,
              let eIdx = draft.entries.firstIndex(where: { $0.id == focus.exerciseID }),
              let sIdx = setRowIndex(
                in: draft.entries[eIdx],
                setIndex: focus.setIndex,
                isWarmup: focus.isWarmup
              ) else {
            return
        }
        draft.entries[eIdx].sets[sIdx].durationSeconds = durationSeconds.flatMap { $0 > 0 ? $0 : nil }
        draft.entries[eIdx].sets[sIdx].calories = calories.flatMap { $0 > 0 ? $0 : nil }
        draft.entries[eIdx].sets[sIdx].distanceMeters = distanceMeters.flatMap { $0 > 0 ? $0 : nil }
        // AMA-2473: committing logs the bout — unless nothing was entered, in
        // which case there is nothing to claim.
        let bout = draft.entries[eIdx].sets[sIdx]
        let entered = bout.durationSeconds != nil || bout.calories != nil || bout.distanceMeters != nil
        draft.entries[eIdx].sets[sIdx].checkedAt = entered ? now() : nil
        touch()
        refreshMetricStrip(exerciseID: focus.exerciseID)
        if advance {
            advanceWheel(from: focus)
        }
    }

    /// Copies LAST TIME into the focused set. Returns the values applied (for wheel sync).
    /// Prefer real history → previous filled set this session → prescription ghost.
    @discardableResult
    func sameAsLastTime() -> LogbookGhost? {
        guard let focus = wheelFocus else { return nil }
        guard let source = effectiveLastReference(
            exerciseID: focus.exerciseID,
            setIndex: focus.setIndex
        ) else { return nil }
        guard let eIdx = draft.entries.firstIndex(where: { $0.id == focus.exerciseID }),
              let sIdx = setRowIndex(
                in: draft.entries[eIdx],
                setIndex: focus.setIndex,
                isWarmup: focus.isWarmup
              ) else {
            return nil
        }
        LogbookGhosts.copyGhost(into: &draft.entries[eIdx].sets[sIdx], ghost: source)
        touch()
        refreshMetricStrip(exerciseID: focus.exerciseID)
        return source
    }

    /// What "Same as last time" / LAST TIME should copy.
    /// 1) Last verified actual  2) previous filled set in this exercise  3) prescription
    func effectiveLastReference(exerciseID: String, setIndex: Int) -> LogbookGhost? {
        guard let entry = draft.entries.first(where: { $0.id == exerciseID }) else { return nil }
        if let historical = LogbookGhostLookup.stored(for: entry, setIndex: setIndex),
           historical.source == .lastActual,
           !historical.isEmpty {
            return historical
        }
        if let previous = LogbookGhostLookup.previousFilledSet(in: entry, before: setIndex) {
            return LogbookGhost(
                weightKg: previous.weightKg,
                reps: previous.reps,
                durationSeconds: previous.durationSeconds,
                calories: previous.calories,
                distanceMeters: previous.distanceMeters,
                source: .lastActual
            )
        }
        if let historical = LogbookGhostLookup.stored(for: entry, setIndex: setIndex), !historical.isEmpty {
            return historical
        }
        return LogbookGhost(
            weightKg: entry.planned.weightKg,
            reps: entry.isMetric ? nil : entry.planned.reps,
            durationSeconds: entry.plannedDurationSeconds,
            calories: entry.plannedCalories,
            distanceMeters: entry.plannedDistanceMeters.map(Double.init),
            source: .prescription
        )
    }

    /// AMA-2462 — turn a field on or off for this exercise. `touch` persists,
    /// so the choice survives a reopen. The last remaining field cannot be
    /// removed: a row must always have somewhere to log.
    func toggleTrackedField(exerciseID: String, field: LogbookTrackedField) {
        guard let eIdx = draft.entries.firstIndex(where: { $0.id == exerciseID }) else { return }
        var fields = draft.entries[eIdx].trackedFields
        if fields.contains(field) {
            guard fields.count > 1 else { return }
            fields.removeAll { $0 == field }
        } else {
            fields.append(field)
        }
        draft.entries[eIdx].trackedFieldsOverride = fields
        touch()
        refreshMetricStrip(exerciseID: exerciseID)
    }

    func addSet(exerciseID: String) {
        guard let eIdx = draft.entries.firstIndex(where: { $0.id == exerciseID }) else { return }
        let previous = draft.entries[eIdx].sets.filter { !$0.isWarmup }.max { $0.index < $1.index }
        let nextIndex = (previous?.index ?? 0) + 1
        var newSet = SetActual(
            index: nextIndex,
            weightKg: previous?.weightKg,
            reps: previous?.reps
        )
        if previous == nil, let ghost = draft.entries[eIdx].ghosts.last {
            LogbookGhosts.copyGhost(into: &newSet, ghost: ghost)
        }
        draft.entries[eIdx].sets.append(newSet)
        if let ghost = draft.entries[eIdx].ghosts.last {
            draft.entries[eIdx].ghosts.append(ghost)
        }
        touch()
    }

    func setNote(_ note: String) {
        draft.note = note
        draft.lastEditedAt = now()
    }

    func selectRPE(_ value: Int) {
        draft.rpe = min(10, max(1, value))
        touch()
    }

    func persistDraft() {
        try? draftRepository.upsert(draft)
    }

    /// Persist load-plan targets (unchecked) then open RPE step.
    func beginSave() {
        persistDraft()
        persistLoadPlans()
        showRPE = true
    }

    /// Commit through the existing verified actuals pipeline.
    /// Companion-pending drafts persist only — reconcile / timeout create actuals.
    @discardableResult
    func saveVerified() throws -> LogbookSaveResult {
        guard let rpe = draft.rpe, (1...10).contains(rpe) else {
            throw ActualsRepositoryError.missingRPE
        }

        // Companion notepad beside watch: keep draft pending for merge.
        if draft.mode == .companionPending {
            persistDraft()
            persistLoadPlans()
            showRPE = false
            return .companionPendingPersisted
        }

        var session = LogbookRollup.fillInSession(from: draft, verified: false)
        // AMA-2472: NOTHING is dropped. This used to compactMap away every
        // exercise with no checked sets, so entering values without ticking
        // each row silently deleted the exercise from the saved session —
        // the reported "1 OF 1 CONFIRMED" on a six-move workout.
        session.exercises = session.exercises.map { exercise in
            var copy = exercise
            if copy.confirmation == nil {
                copy.confirmation = copy.isLogged ? .adjusted : .notLogged
            }
            return copy
        }

        // The gate moves from "every exercise logged" to "at least one" —
        // a session with nothing in it is still refused.
        guard session.exercises.contains(where: \.isLogged) else {
            throw ActualsRepositoryError.nothingLogged
        }

        session.rpe = rpe
        session.verified = true

        try actualsRepository.saveVerifiedSession(session)
        try draftRepository.markCommitted(draftID: draft.id)
        draft.state = .committed
        lastVerifiedSession = session
        showVerifiedPayoff = true
        showRPE = false
        return .verified(session)
    }

    /// Timeout path: commit standalone + Undo toast.
    func commitStandaloneFromTimeout() throws {
        if draft.rpe == nil {
            draft.rpe = 7
        }
        try saveVerified()
        draft.mode = .after
        undoToastVisible = true
    }

    func undoTimeoutCommit() throws {
        try draftRepository.undoCommit(draftID: draft.id)
        try actualsRepository.unverifySession(id: draft.attachedSessionId ?? draft.id)
        draft.state = .pending
        undoToastVisible = false
    }

    /// Reconcile against device recordings (AMA-2387 overlap).
    func reconcile(deviceSessions: [ActualsSourceRecording]) throws -> LogbookReconcileOutcome {
        let outcome = LogbookReconciliation.reconcile(
            draft: draft,
            deviceSessions: deviceSessions,
            now: now()
        )
        switch outcome {
        case .merged(let sessionId):
            if let device = deviceSessions.first(where: { $0.id == sessionId }) {
                let session = LogbookReconciliation.mergeDraft(draft, onto: device)
                try actualsRepository.upsertMatchedDraft(session)
                try draftRepository.markReconciled(draftID: draft.id, sessionID: sessionId)
                draft.attachedSessionId = sessionId
                draft.state = .committed
            }
        case .timeoutCommit:
            try commitStandaloneFromTimeout()
        case .noOverlap, .lateTwinRequiresDuplicateFlow:
            break
        }
        return outcome
    }

    func ghost(for exerciseID: String, setIndex: Int) -> LogbookGhost? {
        effectiveLastReference(exerciseID: exerciseID, setIndex: setIndex)
    }

    func focusedSet() -> (entry: LogbookExerciseEntry, set: SetActual)? {
        guard let focus = wheelFocus,
              let entry = draft.entries.first(where: { $0.id == focus.exerciseID }),
              let set = entry.sets.first(where: {
                  $0.index == focus.setIndex && $0.isWarmup == focus.isWarmup
              }) else {
            return nil
        }
        return (entry, set)
    }

    // MARK: - Private

    private func setRowIndex(
        in entry: LogbookExerciseEntry,
        setIndex: Int,
        isWarmup: Bool
    ) -> Int? {
        entry.sets.firstIndex { $0.index == setIndex && $0.isWarmup == isWarmup }
    }

    private func advanceWheel(from focus: LogbookWheelFocus) {
        if let next = LogbookWheelNavigation.nextUnchecked(after: focus, in: draft.entries) {
            let mode: LogbookWheelMode = {
                if let entry = draft.entries.first(where: { $0.id == next.exerciseID }), entry.isMetric {
                    return .metric
                }
                return .weightReps
            }()
            wheelFocus = LogbookWheelFocus(
                exerciseID: next.exerciseID,
                setIndex: next.setIndex,
                isWarmup: next.isWarmup,
                mode: mode
            )
        } else {
            wheelFocus = nil
        }
    }

    private func refreshMetricStrip(exerciseID: String) {
        guard let eIdx = draft.entries.firstIndex(where: { $0.id == exerciseID }) else { return }
        LogbookMetricStrip.refresh(&draft.entries[eIdx])
    }

    private func touch() {
        draft.lastEditedAt = now()
        persistDraft()
    }

    private func persistLoadPlans() {
        guard let workoutId = draft.workoutId else { return }
        for entry in draft.entries {
            let targets = LogbookRollup.loadPlanTargets(from: entry)
            guard !targets.isEmpty else { continue }
            // Name-based key so duplicate stations (two warm-up OHPs) share ghosts/plans.
            let exerciseKey = ActualsGhostFeed.exerciseKey(forName: entry.name)
            try? draftRepository.saveLoadPlan(
                workoutId: workoutId,
                exerciseKey: exerciseKey,
                targets: targets
            )
        }
    }

    private func startElapsedTimer() {
        elapsedSeconds = max(0, now().timeIntervalSince(draft.startedAt))
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.elapsedSeconds = max(0, self.now().timeIntervalSince(self.draft.startedAt))
            }
        }
    }

    deinit {
        elapsedTimer?.invalidate()
    }
}
