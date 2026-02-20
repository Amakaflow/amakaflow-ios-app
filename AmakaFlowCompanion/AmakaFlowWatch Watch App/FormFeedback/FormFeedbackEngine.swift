import Foundation
import Combine

/// Coordinates MotionCapture → RepSegmenter → FormInference → HapticCoach.
/// Throttles buffer observations to avoid per-sample overhead.
@MainActor
final class FormFeedbackEngine: ObservableObject {
    @Published private(set) var lastResult: FormResult?
    @Published private(set) var repCount: Int = 0
    @Published private(set) var isRunning = false

    private let motionCapture = MotionCapture()
    private let segmenter = RepSegmenter()
    private let hapticCoach = HapticCoach()
    private var inference: FormInference?
    private var cancellables = Set<AnyCancellable>()
    private var processedRepCount = 0

    init() {
        inference = try? FormInference()
    }

    func start() {
        motionCapture.startCapture()
        isRunning = true
        processedRepCount = 0

        motionCapture.$buffer
            .throttle(for: .milliseconds(200), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] buffer in
                self?.process(buffer: buffer)
            }
            .store(in: &cancellables)
    }

    func stop() {
        motionCapture.stopCapture()
        cancellables.removeAll()
        isRunning = false
    }

    // MARK: - Private

    private func process(buffer: [IMUSample]) {
        let reps = segmenter.extractReps(from: buffer)
        guard reps.count > processedRepCount else { return }

        let newRep = reps[processedRepCount]
        processedRepCount = reps.count
        repCount = processedRepCount

        guard let result = try? inference?.classify(window: newRep) else { return }
        lastResult = result

        if hapticCoach.shouldCue(for: result) {
            hapticCoach.play(hapticCoach.cueType(for: result))
        } else {
            hapticCoach.play(.goodRep)
        }
    }
}
