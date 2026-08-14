//
//  LogbookViewModel.swift
//  AmakaFlow
//
//  AMA-2426: notebook logbook state — grid edits, wheels, save → RPE pipeline.
//

import Foundation
import Combine

@MainActor
final class LogbookViewModel: ObservableObject {
    @Published private(set) var draft: LogDraft
    @Published var wheelFocus: LogbookWheelFocus?
    @Published var showRPE: Bool = false
    @Published var showVerifiedPayoff: Bool = false
    @Published var undoToastVisible: Bool = false
    @Published var weightUnit: WeightUnit
    @Published var fineSteps: Bool = false

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
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Mutations

    func setWeightUnit(_ unit: WeightUnit) {
        weightUnit = unit
    }

    func toggleCheck(exerciseID: String, setIndex: Int) {
        guard let eIdx = draft.entries.firstIndex(where: { $0.id == exerciseID }),
              let sIdx = draft.entries[eIdx].sets.firstIndex(where: { $0.index == setIndex }) else {
            return
        }
        if draft.entries[eIdx].sets[sIdx].isChecked {
            draft.entries[eIdx].sets[sIdx].checkedAt = nil
        } else {
            let entry = draft.entries[eIdx]
            let set = entry.sets[sIdx]
            if entry.isMetric {
                if set.durationSeconds == nil, set.calories == nil, set.distanceMeters == nil {
                    copyGhost(exerciseID: exerciseID, setIndex: setIndex)
                }
            } else if set.weightKg == nil || set.reps == nil {
                // Checking with empty cells copies ghost first.
                copyGhost(exerciseID: exerciseID, setIndex: setIndex)
            }
            draft.entries[eIdx].sets[sIdx].checkedAt = now()
        }
        touch()
        refreshMetricStrip(exerciseID: exerciseID)
    }

    func copyGhost(exerciseID: String, setIndex: Int) {
        guard let eIdx = draft.entries.firstIndex(where: { $0.id == exerciseID }),
              let sIdx = draft.entries[eIdx].sets.firstIndex(where: { $0.index == setIndex }),
              let source = effectiveLastReference(exerciseID: exerciseID, setIndex: setIndex) else {
            return
        }
        LogbookGhosts.copyGhost(into: &draft.entries[eIdx].sets[sIdx], ghost: source)
        touch()
    }

    func openWheel(exerciseID: String, setIndex: Int) {
        let mode: LogbookWheelMode = {
            if let entry = draft.entries.first(where: { $0.id == exerciseID }), entry.isMetric {
                return .metric
            }
            return .weightReps
        }()
        wheelFocus = LogbookWheelFocus(exerciseID: exerciseID, setIndex: setIndex, mode: mode)
        fineSteps = false
    }

    func applyWheel(weightDisplay: Double, reps: Int, advance: Bool) {
        guard let focus = wheelFocus,
              let eIdx = draft.entries.firstIndex(where: { $0.id == focus.exerciseID }),
              let sIdx = draft.entries[eIdx].sets.firstIndex(where: { $0.index == focus.setIndex }) else {
            return
        }
        let kg = WeightUnitMath.kilograms(fromDisplay: weightDisplay, unit: weightUnit)
        let ghost = ghost(for: focus.exerciseID, setIndex: focus.setIndex)
        // Bodyweight / unloaded: wheel sits on 0 but storage stays nil when plan + ghost have no load.
        if kg == 0,
           draft.entries[eIdx].planned.weightKg == nil,
           ghost?.weightKg == nil {
            draft.entries[eIdx].sets[sIdx].weightKg = nil
        } else {
            draft.entries[eIdx].sets[sIdx].weightKg = kg
        }
        draft.entries[eIdx].sets[sIdx].reps = reps
        touch()
        if advance {
            advanceWheel(from: focus)
        }
    }

    func applyMetric(durationSeconds: Int?, calories: Int?, distanceMeters: Double?, advance: Bool) {
        guard let focus = wheelFocus,
              let eIdx = draft.entries.firstIndex(where: { $0.id == focus.exerciseID }),
              let sIdx = draft.entries[eIdx].sets.firstIndex(where: { $0.index == focus.setIndex }) else {
            return
        }
        draft.entries[eIdx].sets[sIdx].durationSeconds = durationSeconds.flatMap { $0 > 0 ? $0 : nil }
        draft.entries[eIdx].sets[sIdx].calories = calories.flatMap { $0 > 0 ? $0 : nil }
        draft.entries[eIdx].sets[sIdx].distanceMeters = distanceMeters.flatMap { $0 > 0 ? $0 : nil }
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
              let sIdx = draft.entries[eIdx].sets.firstIndex(where: { $0.index == focus.setIndex }) else {
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
        if let historical = storedGhost(for: entry, setIndex: setIndex),
           historical.source == .lastActual,
           !historical.isEmpty {
            return historical
        }
        if let previous = previousFilledSet(in: entry, before: setIndex) {
            return LogbookGhost(
                weightKg: previous.weightKg,
                reps: previous.reps,
                durationSeconds: previous.durationSeconds,
                calories: previous.calories,
                distanceMeters: previous.distanceMeters,
                source: .lastActual
            )
        }
        if let historical = storedGhost(for: entry, setIndex: setIndex), !historical.isEmpty {
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

    func addSet(exerciseID: String) {
        guard let eIdx = draft.entries.firstIndex(where: { $0.id == exerciseID }) else { return }
        let previous = draft.entries[eIdx].sets.filter { !$0.isWarmup }.max(by: { $0.index < $1.index })
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
    func saveVerified() throws {
        guard let rpe = draft.rpe, (1...10).contains(rpe) else {
            throw ActualsRepositoryError.missingRPE
        }
        var session = LogbookRollup.fillInSession(from: draft, verified: false)
        session.exercises = session.exercises.compactMap { exercise in
            guard exercise.actualSets > 0 else { return nil }
            var copy = exercise
            if copy.confirmation == nil {
                copy.confirmation = .adjusted
            }
            copy.sets = copy.sets.filter(\.isChecked)
            return copy
        }

        guard !session.exercises.isEmpty else {
            throw ActualsRepositoryError.unconfirmedRows(0)
        }

        session.rpe = rpe
        session.verified = true

        try actualsRepository.saveVerifiedSession(session)
        try draftRepository.markCommitted(draftID: draft.id)
        draft.state = .committed
        showVerifiedPayoff = true
        showRPE = false
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

    private func storedGhost(for entry: LogbookExerciseEntry, setIndex: Int) -> LogbookGhost? {
        if let idx = entry.sets.firstIndex(where: { $0.index == setIndex }),
           idx < entry.ghosts.count {
            return entry.ghosts[idx]
        }
        return entry.ghosts.last
    }

    private func previousFilledSet(in entry: LogbookExerciseEntry, before setIndex: Int) -> SetActual? {
        entry.sets
            .filter { set in
                set.index < setIndex
                    && (
                        set.weightKg != nil
                            || set.reps != nil
                            || set.durationSeconds != nil
                            || set.calories != nil
                            || set.distanceMeters != nil
                    )
            }
            .sorted { $0.index < $1.index }
            .last
    }

    func focusedSet() -> (entry: LogbookExerciseEntry, set: SetActual)? {
        guard let focus = wheelFocus,
              let entry = draft.entries.first(where: { $0.id == focus.exerciseID }),
              let set = entry.sets.first(where: { $0.index == focus.setIndex }) else {
            return nil
        }
        return (entry, set)
    }

    // MARK: - Private

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
                mode: mode
            )
        } else {
            wheelFocus = nil
        }
    }

    private func refreshMetricStrip(exerciseID: String) {
        guard let eIdx = draft.entries.firstIndex(where: { $0.id == exerciseID }),
              draft.entries[eIdx].isMetric,
              let set = draft.entries[eIdx].sets.first else {
            return
        }
        let ghost = draft.entries[eIdx].ghosts.first
        let duration = set.durationSeconds ?? ghost?.durationSeconds ?? draft.entries[eIdx].plannedDurationSeconds
        let calories = set.calories ?? ghost?.calories ?? draft.entries[eIdx].plannedCalories
        let distance = set.distanceMeters
            ?? ghost?.distanceMeters
            ?? draft.entries[eIdx].plannedDistanceMeters.map(Double.init)
        let existingNote = draft.entries[eIdx].cardioStrip?.sourceNote
        draft.entries[eIdx].cardioStrip = LogbookCardioStrip(
            timeText: duration.map(LogbookMetricFormat.duration),
            distanceText: distance.map(LogbookMetricFormat.distanceKm),
            caloriesText: calories.map { "\($0)" },
            heartRateText: draft.entries[eIdx].cardioStrip?.heartRateText,
            sourceNote: existingNote
        )
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
