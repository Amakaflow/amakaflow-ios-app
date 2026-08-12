//
//  WorkRestAssistController.swift
//  AmakaFlowWatch Watch App
//
//  AMA-2420 Phase 4 — Watch-side work/rest assist coordinator.
//  Reuses FormFeedback `MotionCapture` / `IMUSample`. Gated by experimental flag.
//

import Combine
import Foundation
import WatchKit

@MainActor
final class WorkRestAssistController: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var phase: WorkRestPhase = .idleRest
    @Published private(set) var pendingProposal: WorkRestProposal?
    @Published private(set) var lastMotionConfidence: Double = 0
    @Published private(set) var lastActivityScore: Double = 0

    private let motionCapture = MotionCapture(sampleRate: 50.0, maxBufferSize: 300)
    private var machine = WorkRestStateMachine()
    private var cancellables = Set<AnyCancellable>()
    private var heartRateProvider: (() -> Double)?
    private var didPlayPromptHaptic = false

    func start(
        initialPhase: WorkRestPhase,
        heartRateProvider: @escaping () -> Double
    ) {
        stop()
        guard WatchStrengthAutoCaptureSettings.isEnabled else { return }

        self.heartRateProvider = heartRateProvider
        machine = WorkRestStateMachine(phase: initialPhase)
        phase = initialPhase
        pendingProposal = nil
        didPlayPromptHaptic = false
        isRunning = true

        motionCapture.startCapture()
        motionCapture.$buffer
            .throttle(for: .milliseconds(400), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] buffer in
                self?.process(buffer: buffer)
            }
            .store(in: &cancellables)
    }

    func stop() {
        motionCapture.stopCapture()
        cancellables.removeAll()
        machine.clearProposal()
        pendingProposal = nil
        isRunning = false
        didPlayPromptHaptic = false
        heartRateProvider = nil
    }

    /// Keep assist phase aligned when the user manually rests / resumes / logs.
    func syncPhase(_ newPhase: WorkRestPhase) {
        guard isRunning else { return }
        machine.syncPhase(newPhase)
        phase = machine.phase
        pendingProposal = machine.pendingProposal
        didPlayPromptHaptic = pendingProposal != nil
    }

    @discardableResult
    func confirmProposal() -> WorkRestTransition? {
        guard isRunning else { return nil }
        let transition = machine.confirmPendingProposal()
        phase = machine.phase
        pendingProposal = nil
        didPlayPromptHaptic = false
        if transition != nil {
            WKInterfaceDevice.current().play(.success)
        }
        return transition
    }

    func rejectProposal() {
        guard isRunning else { return }
        machine.rejectPendingProposal()
        pendingProposal = nil
        didPlayPromptHaptic = false
        WKInterfaceDevice.current().play(.click)
    }

    // MARK: - Private

    private func process(buffer: [IMUSample]) {
        guard isRunning else { return }

        // Use a trailing window (~2s at 50 Hz) so quiet→work edges resolve quickly.
        let window = Array(buffer.suffix(100))
        let activity = WorkRestMotionMetrics.activityScore(from: window)
        lastActivityScore = activity

        let heartRate = heartRateProvider?() ?? 0
        let observation = WorkRestObservation(
            activityScore: activity,
            sampleCount: window.count,
            heartRateBPM: heartRate > 0 ? heartRate : nil,
            now: Date()
        )
        let result = machine.evaluate(observation)
        phase = result.phase
        lastMotionConfidence = result.motionConfidence
        pendingProposal = result.proposal

        if result.proposal != nil, !didPlayPromptHaptic {
            didPlayPromptHaptic = true
            WKInterfaceDevice.current().play(.notification)
        } else if result.proposal == nil {
            didPlayPromptHaptic = false
        }
    }
}
