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

    /// Longer buffer so Phase 5 rep assist can share this single CMMotionManager stream.
    private let motionCapture = MotionCapture(sampleRate: 50.0, maxBufferSize: 1_500)
    private var machine = WorkRestStateMachine()
    private var cancellables = Set<AnyCancellable>()
    private var heartRateProvider: (() -> Double)?
    private var didPlayPromptHaptic = false
    /// AMA-2420 Phase 5 — optional consumer of the shared IMU buffer (no second capture).
    private var motionBufferHandler: (([IMUSample]) -> Void)?

    func start(
        initialPhase: WorkRestPhase,
        heartRateProvider: @escaping () -> Double,
        motionBufferHandler: (([IMUSample]) -> Void)? = nil
    ) {
        stop()
        guard WatchStrengthAutoCaptureSettings.isEnabled else { return }

        self.heartRateProvider = heartRateProvider
        self.motionBufferHandler = motionBufferHandler
        machine = WorkRestStateMachine(phase: initialPhase)
        phase = initialPhase
        pendingProposal = nil
        didPlayPromptHaptic = false
        isRunning = true

        motionCapture.clearBuffer()
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
        motionBufferHandler = nil
    }

    /// Reset IMU window when a new work set begins (rep assist set boundary).
    func clearMotionBufferForNewSet() {
        guard isRunning else { return }
        motionCapture.clearBuffer()
    }

    /// Pause IMU sampling without tearing down the assist session (workout pause).
    func pauseCapture() {
        guard isRunning else { return }
        motionCapture.stopCapture()
        machine.clearProposal()
        pendingProposal = nil
        didPlayPromptHaptic = false
    }

    /// Resume IMU sampling after workout resume.
    func resumeCapture() {
        guard isRunning, !motionCapture.isCapturing else { return }
        motionCapture.startCapture()
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
        guard isRunning, pendingProposal != nil else { return }
        machine.rejectPendingProposal()
        pendingProposal = nil
        didPlayPromptHaptic = false
        WKInterfaceDevice.current().play(.click)
    }

    // MARK: - Private

    private func process(buffer: [IMUSample]) {
        guard isRunning else { return }

        motionBufferHandler?(buffer)

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
