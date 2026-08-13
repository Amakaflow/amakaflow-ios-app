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
    private var elapsedTimer: Timer?

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
            // Checking with empty cells copies ghost first.
            if draft.entries[eIdx].sets[sIdx].weightKg == nil || draft.entries[eIdx].sets[sIdx].reps == nil {
                copyGhost(exerciseID: exerciseID, setIndex: setIndex)
            }
            draft.entries[eIdx].sets[sIdx].checkedAt = now()
        }
        touch()
    }

    func copyGhost(exerciseID: String, setIndex: Int) {
        guard let eIdx = draft.entries.firstIndex(where: { $0.id == exerciseID }),
              let sIdx = draft.entries[eIdx].sets.firstIndex(where: { $0.index == setIndex }) else {
            return
        }
        let ghosts = draft.entries[eIdx].ghosts
        let ghost: LogbookGhost
        if sIdx < ghosts.count {
            ghost = ghosts[sIdx]
        } else if let last = ghosts.last {
            ghost = last
        } else {
            ghost = LogbookGhost(
                weightKg: draft.entries[eIdx].planned.weightKg,
                reps: draft.entries[eIdx].planned.reps,
                source: .prescription
            )
        }
        LogbookGhosts.copyGhost(into: &draft.entries[eIdx].sets[sIdx], ghost: ghost)
        touch()
    }

    func openWheel(exerciseID: String, setIndex: Int) {
        wheelFocus = LogbookWheelFocus(exerciseID: exerciseID, setIndex: setIndex)
        fineSteps = false
    }

    func applyWheel(weightDisplay: Double, reps: Int, advance: Bool) {
        guard let focus = wheelFocus,
              let eIdx = draft.entries.firstIndex(where: { $0.id == focus.exerciseID }),
              let sIdx = draft.entries[eIdx].sets.firstIndex(where: { $0.index == focus.setIndex }) else {
            return
        }
        let kg = WeightUnitMath.kilograms(fromDisplay: weightDisplay, unit: weightUnit)
        draft.entries[eIdx].sets[sIdx].weightKg = kg
        draft.entries[eIdx].sets[sIdx].reps = reps
        touch()

        if advance {
            if let next = LogbookWheelNavigation.nextUnchecked(after: focus, in: draft.entries) {
                wheelFocus = next
            } else {
                wheelFocus = nil
            }
        }
    }

    func sameAsLastTime() {
        guard let focus = wheelFocus else { return }
        copyGhost(exerciseID: focus.exerciseID, setIndex: focus.setIndex)
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
        touch()
    }

    func selectRPE(_ value: Int) {
        draft.rpe = value
        touch()
    }

    func persistDraft() {
        try? draftRepository.upsert(draft)
    }

    /// Persist load-plan targets (unchecked) then open RPE step.
    func beginSave() {
        persistLoadPlans()
        showRPE = true
    }

    /// Commit through the existing verified actuals pipeline.
    func saveVerified() throws {
        guard let rpe = draft.rpe, (1...10).contains(rpe) else { return }
        var session = LogbookRollup.fillInSession(from: draft, verified: false)
        // Ensure every exercise with checked sets is confirmed; drop empty exercises' confirmation.
        session.exercises = session.exercises.map { exercise in
            var copy = exercise
            if copy.actualSets > 0, copy.confirmation == nil {
                copy.confirmation = .adjusted
            }
            // Exclude exercises with zero checked sets from the verified payload.
            return copy
        }.filter { $0.actualSets > 0 || $0.confirmation != nil }

        // If after filtering nothing remains, keep at least rolled rows marked adjusted.
        if session.exercises.isEmpty {
            session = LogbookRollup.fillInSession(from: draft, verified: false)
            session.exercises = session.exercises.map { exercise in
                var copy = exercise
                copy.confirmation = .adjusted
                copy.actualSets = max(copy.actualSets, 0)
                return copy
            }
        }

        session.rpe = rpe
        session.verified = true
        // Mark all confirmed for repository gate.
        session.exercises = session.exercises.map { exercise in
            var copy = exercise
            if copy.confirmation == nil {
                copy.confirmation = .adjusted
            }
            return copy
        }

        try actualsRepository.saveVerifiedSession(session)
        try draftRepository.markCommitted(draftID: draft.id)
        draft.state = .committed
        showVerifiedPayoff = true
        showRPE = false
    }

    /// Timeout path: commit standalone + Undo toast.
    func commitStandaloneFromTimeout() throws {
        draft.mode = .after
        draft.state = .committed
        if draft.rpe == nil {
            draft.rpe = 7
        }
        try saveVerified()
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
        guard let entry = draft.entries.first(where: { $0.id == exerciseID }) else { return nil }
        if let idx = entry.sets.firstIndex(where: { $0.index == setIndex }),
           idx < entry.ghosts.count {
            return entry.ghosts[idx]
        }
        return entry.ghosts.last
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

    private func touch() {
        draft.lastEditedAt = now()
        persistDraft()
    }

    private func persistLoadPlans() {
        guard let workoutId = draft.workoutId else { return }
        for entry in draft.entries {
            let targets = LogbookRollup.loadPlanTargets(from: entry)
            guard !targets.isEmpty else { continue }
            try? draftRepository.saveLoadPlan(
                workoutId: workoutId,
                exerciseKey: entry.id,
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
