//
//  FollowAlongPlayerViewModel.swift
//  AmakaFlow
//
//  AMA-1182: ViewModel for follow-along video playback with step tracking.
//  Manages AVPlayer state, current step progression, elapsed time,
//  and auto-advance when a timed step completes.
//

import Foundation
import AVFoundation
import Combine

/// Represents a single step in a follow-along workout
struct FollowAlongStep: Identifiable, Equatable {
    let id: String
    let name: String
    let durationSeconds: Int?     // nil = reps-based (no auto-advance)
    let reps: Int?
    let videoURL: URL?
    let videoTimestamp: TimeInterval // where in the video this step starts

    var isTimeBased: Bool { durationSeconds != nil }

    var formattedDuration: String {
        guard let seconds = durationSeconds else {
            if let r = reps { return "\(r) reps" }
            return ""
        }
        let m = seconds / 60
        let s = seconds % 60
        return m > 0 ? String(format: "%d:%02d", m, s) : "\(s)s"
    }
}

/// Phase of the follow-along player
enum FollowAlongPhase: Equatable {
    case loading
    case ready
    case playing
    case paused
    case ended
}

@MainActor
class FollowAlongPlayerViewModel: ObservableObject {

    // MARK: - Published State

    @Published var phase: FollowAlongPhase = .loading
    @Published var steps: [FollowAlongStep] = []
    @Published var currentStepIndex: Int = 0
    @Published var elapsedSeconds: Int = 0
    @Published var stepRemainingSeconds: Int = 0
    @Published var errorMessage: String?

    // MARK: - AVPlayer

    @Published var player: AVPlayer?

    // MARK: - Computed

    var currentStep: FollowAlongStep? {
        steps.indices.contains(currentStepIndex) ? steps[currentStepIndex] : nil
    }

    var progress: Float {
        guard !steps.isEmpty else { return 0 }
        return Float(currentStepIndex) / Float(steps.count)
    }

    var formattedElapsed: String {
        let h = elapsedSeconds / 3600
        let m = (elapsedSeconds % 3600) / 60
        let s = elapsedSeconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    var isLastStep: Bool {
        currentStepIndex >= steps.count - 1
    }

    // MARK: - Private

    private var timerCancellable: AnyCancellable?
    private var playerObserver: Any?

    // MARK: - Init

    init() {}

    deinit {
        timerCancellable?.cancel()
        if let obs = playerObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    // MARK: - Load Workout

    /// Load a follow-along workout. Accepts a Workout model and extracts
    /// steps with video URLs from the intervals.
    func loadWorkout(_ workout: Workout) {
        phase = .loading
        errorMessage = nil

        let extracted = extractSteps(from: workout)
        guard !extracted.isEmpty else {
            errorMessage = "No follow-along steps found in this workout."
            phase = .ended
            return
        }

        steps = extracted
        currentStepIndex = 0
        elapsedSeconds = 0

        // Set up AVPlayer with the first video URL found
        if let firstVideoURL = extracted.first(where: { $0.videoURL != nil })?.videoURL {
            // Remove any existing observer before registering a new one (AMA-1358)
            if let existingObserver = playerObserver {
                NotificationCenter.default.removeObserver(existingObserver)
            }

            let playerItem = AVPlayerItem(url: firstVideoURL)
            let avPlayer = AVPlayer(playerItem: playerItem)
            avPlayer.actionAtItemEnd = .pause
            self.player = avPlayer

            // Observe when playback finishes
            playerObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handleVideoEnded()
                }
            }
        } else {
            // If no video URL, clean up any existing observer
            if let existingObserver = playerObserver {
                NotificationCenter.default.removeObserver(existingObserver)
                playerObserver = nil
            }
        }

        setupStep(at: 0)
        phase = .ready
    }

    /// Load from a simple list of steps (for testing or direct construction)
    func loadSteps(_ newSteps: [FollowAlongStep], videoURL: URL? = nil) {
        phase = .loading
        steps = newSteps
        currentStepIndex = 0
        elapsedSeconds = 0

        if let url = videoURL {
            let avPlayer = AVPlayer(playerItem: AVPlayerItem(url: url))
            avPlayer.actionAtItemEnd = .pause
            self.player = avPlayer
        }

        setupStep(at: 0)
        phase = .ready
    }

    // MARK: - Playback Controls

    func play() {
        guard phase == .ready || phase == .paused else { return }
        phase = .playing
        player?.play()
        startTimer()
    }

    func pause() {
        guard phase == .playing else { return }
        phase = .paused
        player?.pause()
        stopTimer()
    }

    func togglePlayPause() {
        switch phase {
        case .playing: pause()
        case .ready, .paused: play()
        default: break
        }
    }

    func skipToNextStep() {
        guard currentStepIndex < steps.count - 1 else {
            endWorkout()
            return
        }
        currentStepIndex += 1
        setupStep(at: currentStepIndex)
        if phase == .playing {
            startTimer()
        }
    }

    func skipToPreviousStep() {
        guard currentStepIndex > 0 else { return }
        currentStepIndex -= 1
        setupStep(at: currentStepIndex)
        if phase == .playing {
            startTimer()
        }
    }

    func skipToStep(_ index: Int) {
        guard steps.indices.contains(index) else { return }
        currentStepIndex = index
        setupStep(at: index)
        if phase == .playing {
            startTimer()
        }
    }

    func endWorkout() {
        stopTimer()
        player?.pause()
        phase = .ended
    }

    // MARK: - Private Helpers

    private func setupStep(at index: Int) {
        stopTimer()
        guard let step = steps[safe: index] else { return }

        if step.isTimeBased {
            stepRemainingSeconds = step.durationSeconds ?? 0
        } else {
            stepRemainingSeconds = 0
        }

        // Seek player to the step's video timestamp if applicable
        if step.videoURL != nil {
            let time = CMTime(seconds: step.videoTimestamp, preferredTimescale: 600)
            player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    private func startTimer() {
        stopTimer()
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.tick()
                }
            }
    }

    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    private func tick() {
        elapsedSeconds += 1

        guard let step = currentStep, step.isTimeBased else { return }

        if stepRemainingSeconds > 0 {
            stepRemainingSeconds -= 1
        }

        if stepRemainingSeconds == 0 {
            // Auto-advance to next step
            if isLastStep {
                endWorkout()
            } else {
                skipToNextStep()
            }
        }
    }

    private func handleVideoEnded() {
        // Video ended naturally; if still on last step, end the workout
        if isLastStep {
            endWorkout()
        }
    }

    // MARK: - Step Extraction

    /// Convert Workout intervals into FollowAlongSteps.
    /// Supports both follow-along video workouts (with URLs) and standard workouts.
    private func extractSteps(from workout: Workout) -> [FollowAlongStep] {
        var result: [FollowAlongStep] = []
        var timeOffset: TimeInterval = 0

        func process(_ intervals: [WorkoutInterval], roundPrefix: String? = nil) {
            for interval in intervals {
                switch interval {
                case .warmup(let seconds, let target):
                    let name = target ?? "Warm Up"
                    result.append(FollowAlongStep(
                        id: UUID().uuidString,
                        name: name,
                        durationSeconds: seconds,
                        reps: nil,
                        videoURL: nil,
                        videoTimestamp: timeOffset
                    ))
                    timeOffset += Double(seconds)

                case .cooldown(let seconds, let target):
                    let name = target ?? "Cool Down"
                    result.append(FollowAlongStep(
                        id: UUID().uuidString,
                        name: name,
                        durationSeconds: seconds,
                        reps: nil,
                        videoURL: nil,
                        videoTimestamp: timeOffset
                    ))
                    timeOffset += Double(seconds)

                case .time(let seconds, let target):
                    let name = target ?? "Work"
                    result.append(FollowAlongStep(
                        id: UUID().uuidString,
                        name: name,
                        durationSeconds: seconds,
                        reps: nil,
                        videoURL: nil,
                        videoTimestamp: timeOffset
                    ))
                    timeOffset += Double(seconds)

                case .reps(_, let reps, let name, _, let restSec, let followAlongUrl):
                    let prefix = roundPrefix.map { "\($0) - " } ?? ""
                    let url = followAlongUrl.flatMap { URL(string: $0) }
                    result.append(FollowAlongStep(
                        id: UUID().uuidString,
                        name: "\(prefix)\(name)",
                        durationSeconds: nil,
                        reps: reps,
                        videoURL: url,
                        videoTimestamp: timeOffset
                    ))
                    // Estimate ~3s per rep for time offset
                    timeOffset += Double(reps) * 3.0

                    // Add rest step if specified
                    if let rest = restSec, rest > 0 {
                        result.append(FollowAlongStep(
                            id: UUID().uuidString,
                            name: "Rest",
                            durationSeconds: rest,
                            reps: nil,
                            videoURL: nil,
                            videoTimestamp: timeOffset
                        ))
                        timeOffset += Double(rest)
                    }

                case .repeat(let reps, let nested):
                    for round in 1...reps {
                        process(nested, roundPrefix: "Round \(round)/\(reps)")
                    }

                case .rest(let seconds):
                    let dur = seconds ?? 30
                    result.append(FollowAlongStep(
                        id: UUID().uuidString,
                        name: "Rest",
                        durationSeconds: seconds,
                        reps: nil,
                        videoURL: nil,
                        videoTimestamp: timeOffset
                    ))
                    timeOffset += Double(dur)

                case .distance(let meters, let target):
                    let name = target ?? "\(meters)m"
                    // Estimate ~6 min/km pace
                    let estimatedSeconds = Int(Double(meters) / 1000.0 * 360)
                    result.append(FollowAlongStep(
                        id: UUID().uuidString,
                        name: name,
                        durationSeconds: estimatedSeconds > 0 ? estimatedSeconds : nil,
                        reps: nil,
                        videoURL: nil,
                        videoTimestamp: timeOffset
                    ))
                    timeOffset += Double(estimatedSeconds)
                }
            }
        }

        process(workout.intervals)
        return result
    }
}

// MARK: - Safe Array Access

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
