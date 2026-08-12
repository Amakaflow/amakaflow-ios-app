//
//  NarrowRepAssistController.swift
//  AmakaFlowWatch Watch App
//
//  AMA-2420 Phase 5 — Watch-side narrow rep assist coordinator.
//  Ingests IMU from WorkRest's MotionCapture (no second CMMotionManager).
//

import Combine
import Foundation
import WatchKit

@MainActor
final class NarrowRepAssistController: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var pendingProposal: NarrowRepProposal?
    @Published private(set) var detectedRepCount: Int = 0
    @Published private(set) var lastConfidence: Double = 0

    private var machine = NarrowRepAssistStateMachine()
    private let segmenter = RepSegmenter()
    private var setBuffer: [IMUSample] = []
    private var family: NarrowRepExerciseFamily?
    private var plannedReps: Int?
    private var isWorkContext = false
    private var didPlayPromptHaptic = false
    private let maxSetBufferSize = 2_000

    func start(exerciseName: String?, plannedReps: Int?) {
        stop()
        guard WatchStrengthAutoCaptureSettings.isEnabled else { return }

        family = exerciseName.flatMap { NarrowRepExerciseFamily.resolve(exerciseName: $0) }
        self.plannedReps = plannedReps
        isWorkContext = true
        setBuffer = []
        machine = NarrowRepAssistStateMachine()
        machine.beginSet()
        pendingProposal = nil
        detectedRepCount = 0
        lastConfidence = 0
        didPlayPromptHaptic = false
        isRunning = true
    }

    func stop() {
        setBuffer = []
        machine.clearProposal()
        pendingProposal = nil
        isRunning = false
        didPlayPromptHaptic = false
        family = nil
        plannedReps = nil
        isWorkContext = false
    }

    /// Begin a new set window (clears IMU accumulation for this set).
    func beginSet(exerciseName: String?, plannedReps: Int?) {
        guard isRunning else {
            start(exerciseName: exerciseName, plannedReps: plannedReps)
            return
        }
        family = exerciseName.flatMap { NarrowRepExerciseFamily.resolve(exerciseName: $0) }
        self.plannedReps = plannedReps
        isWorkContext = true
        setBuffer = []
        machine.beginSet()
        pendingProposal = nil
        detectedRepCount = 0
        lastConfidence = 0
        didPlayPromptHaptic = false
    }

    func setWorkContext(_ working: Bool, finalize: Bool = false) {
        guard isRunning else { return }
        isWorkContext = working
        if finalize {
            evaluate(finalizePass: true)
        }
    }

    /// Append / replace from shared WorkRest motion buffer.
    func ingest(buffer: [IMUSample]) {
        guard isRunning, isWorkContext || pendingProposal != nil else { return }
        guard family != nil else { return }

        // Keep the longest trailing window available from the shared capture.
        if buffer.count >= setBuffer.count {
            setBuffer = Array(buffer.suffix(maxSetBufferSize))
        } else if !buffer.isEmpty {
            // Capture was cleared mid-set — continue accumulating.
            setBuffer.append(contentsOf: buffer)
            if setBuffer.count > maxSetBufferSize {
                setBuffer.removeFirst(setBuffer.count - maxSetBufferSize)
            }
        }
        evaluate(finalizePass: false)
    }

    @discardableResult
    func confirmProposal() -> NarrowRepProposal? {
        guard isRunning else { return nil }
        let confirmed = machine.confirmPendingProposal()
        pendingProposal = nil
        didPlayPromptHaptic = false
        if confirmed != nil {
            WKInterfaceDevice.current().play(.success)
        }
        return confirmed
    }

    func rejectProposal() {
        guard isRunning, pendingProposal != nil else { return }
        machine.rejectPendingProposal()
        pendingProposal = nil
        didPlayPromptHaptic = false
        WKInterfaceDevice.current().play(.click)
    }

    // MARK: - Private

    private func evaluate(finalizePass: Bool) {
        guard isRunning else { return }
        let reps = segmenter.extractReps(from: setBuffer).count
        detectedRepCount = reps

        let observation = NarrowRepObservation(
            family: family,
            plannedReps: plannedReps,
            detectedRepCount: reps,
            sampleCount: setBuffer.count,
            isWorkContext: isWorkContext || finalizePass,
            finalizePass: finalizePass,
            now: Date()
        )
        let result = machine.evaluate(observation)
        lastConfidence = result.confidence
        pendingProposal = result.proposal

        if result.proposal != nil, !didPlayPromptHaptic {
            didPlayPromptHaptic = true
            WKInterfaceDevice.current().play(.notification)
        } else if result.proposal == nil {
            didPlayPromptHaptic = false
        }
    }
}
