//
//  VoiceWorkoutViewModel.swift
//  AmakaFlow
//
//  ViewModel for voice-to-workout creation flow (AMA-5)
//

import Foundation
import Combine

/// State machine for voice workout creation flow
enum VoiceWorkoutState: Equatable {
    case idle                   // Initial state, ready to record
    case permissionRequired     // Needs permissions
    case recording              // Recording voice input
    case transcribing           // Processing audio to text
    case reviewingTranscription // User can edit transcription
    case parsing                // Converting text to workout
    case reviewingWorkout       // User can edit parsed workout
    case saving                 // Saving to library
    case completed              // Successfully saved
    case error(String)          // Error occurred

    var displayTitle: String {
        switch self {
        case .idle: return "Create Workout"
        case .permissionRequired: return "Permissions Required"
        case .recording: return "Recording"
        case .transcribing: return "Transcribing"
        case .reviewingTranscription: return "Review Transcription"
        case .parsing: return "Creating Workout"
        case .reviewingWorkout: return "Review Workout"
        case .saving: return "Saving"
        case .completed: return "Saved!"
        case .error: return "Error"
        }
    }

    var isProcessing: Bool {
        switch self {
        case .transcribing, .parsing, .saving: return true
        default: return false
        }
    }

    static func == (lhs: VoiceWorkoutState, rhs: VoiceWorkoutState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.permissionRequired, .permissionRequired),
             (.recording, .recording),
             (.transcribing, .transcribing),
             (.reviewingTranscription, .reviewingTranscription),
             (.parsing, .parsing),
             (.reviewingWorkout, .reviewingWorkout),
             (.saving, .saving),
             (.completed, .completed):
            return true
        case (.error(let lhsMsg), .error(let rhsMsg)):
            return lhsMsg == rhsMsg
        default:
            return false
        }
    }
}

@MainActor
class VoiceWorkoutViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var state: VoiceWorkoutState = .idle
    @Published var transcription: String = ""
    @Published var selectedSport: WorkoutSport = .cardio
    @Published private(set) var workout: Workout?
    @Published private(set) var confidence: Double = 0
    @Published private(set) var suggestions: [String] = []

    // Recording properties
    @Published private(set) var recordingDuration: TimeInterval = 0
    @Published private(set) var audioLevel: Float = 0

    // MARK: - Services

    private let permissionManager = PermissionManager.shared
    private let recordingService = VoiceRecordingService()
    private let transcriptionService = TranscriptionService()
    private let parsingService = WorkoutParsingService()
    private let apiService = APIService.shared

    private var cancellables = Set<AnyCancellable>()
    private var audioURL: URL?

    // MARK: - Initialization

    init() {
        setupBindings()
        checkPermissions()
    }

    private func setupBindings() {
        // Bind recording service properties
        recordingService.$recordingDuration
            .receive(on: DispatchQueue.main)
            .assign(to: &$recordingDuration)

        recordingService.$audioLevel
            .receive(on: DispatchQueue.main)
            .assign(to: &$audioLevel)
    }

    // MARK: - Permission Handling

    private func checkPermissions() {
        permissionManager.refreshPermissionStatus()
        if !permissionManager.hasAllPermissions {
            state = .permissionRequired
        }
    }

    func requestPermissions() async {
        let granted = await permissionManager.requestPermissions()
        if granted {
            state = .idle
        } else {
            state = .permissionRequired
        }
    }

    func openSettings() {
        permissionManager.openSettings()
    }

    // MARK: - Recording Flow

    /// Start recording voice input
    func startRecording() async {
        guard permissionManager.hasAllPermissions else {
            state = .permissionRequired
            return
        }

        do {
            audioURL = try await recordingService.startRecording()
            state = .recording
        } catch {
            state = .error("Failed to start recording: \(error.localizedDescription)")
        }
    }

    /// Stop recording and begin transcription
    func stopRecording() async {
        guard state == .recording else { return }

        do {
            audioURL = try await recordingService.stopRecording()
            await transcribeRecording()
        } catch let error as VoiceRecordingService.RecordingError {
            if case .recordingCancelled = error {
                state = .idle
            } else {
                state = .error(error.localizedDescription)
            }
        } catch {
            state = .error("Recording failed: \(error.localizedDescription)")
        }
    }

    /// Cancel current recording
    func cancelRecording() {
        recordingService.cancelRecording()
        state = .idle
        audioURL = nil
    }

    // MARK: - Transcription Flow

    private func transcribeRecording() async {
        guard let url = audioURL else {
            state = .error("No recording to transcribe")
            return
        }

        state = .transcribing

        do {
            transcription = try await transcriptionService.transcribe(audioURL: url)
            state = .reviewingTranscription
        } catch {
            state = .error("Transcription failed: \(error.localizedDescription)")
        }
    }

    /// Re-transcribe with updated audio (if needed)
    func retryTranscription() async {
        await transcribeRecording()
    }

    /// User confirmed transcription, proceed to parsing
    func confirmTranscription() async {
        await parseTranscription()
    }

    // MARK: - Parsing Flow

    private func parseTranscription() async {
        guard !transcription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .error("Please enter a workout description")
            return
        }

        state = .parsing

        do {
            workout = try await parsingService.parse(
                transcription: transcription,
                sportHint: selectedSport
            )
            confidence = parsingService.confidence
            suggestions = parsingService.suggestions
            state = .reviewingWorkout
        } catch {
            state = .error("Could not create workout: \(error.localizedDescription)")
        }
    }

    /// Re-parse with current transcription
    func retryParsing() async {
        await parseTranscription()
    }

    // MARK: - Workout Editing

    /// Update the workout name
    func updateWorkoutName(_ name: String) {
        guard var currentWorkout = workout else { return }
        workout = Workout(
            id: currentWorkout.id,
            name: name,
            sport: currentWorkout.sport,
            duration: currentWorkout.duration,
            intervals: currentWorkout.intervals,
            description: currentWorkout.description,
            source: .ai,
            sourceUrl: nil
        )
    }

    /// Update the workout sport
    func updateWorkoutSport(_ sport: WorkoutSport) {
        guard var currentWorkout = workout else { return }
        workout = Workout(
            id: currentWorkout.id,
            name: currentWorkout.name,
            sport: sport,
            duration: currentWorkout.duration,
            intervals: currentWorkout.intervals,
            description: currentWorkout.description,
            source: .ai,
            sourceUrl: nil
        )
    }

    /// Update workout intervals
    func updateIntervals(_ intervals: [WorkoutInterval]) {
        guard var currentWorkout = workout else { return }
        // Recalculate duration based on intervals
        let duration = calculateDuration(intervals)
        workout = Workout(
            id: currentWorkout.id,
            name: currentWorkout.name,
            sport: currentWorkout.sport,
            duration: duration,
            intervals: intervals,
            description: currentWorkout.description,
            source: .ai,
            sourceUrl: nil
        )
    }

    private func calculateDuration(_ intervals: [WorkoutInterval]) -> Int {
        var total = 0
        for interval in intervals {
            switch interval {
            case .warmup(let seconds, _), .cooldown(let seconds, _), .time(let seconds, _):
                total += seconds
            case .reps(let sets, _, _, _, let restSec, _):
                // Estimate 30 seconds per set plus rest
                let setCount = sets ?? 3
                total += setCount * (30 + (restSec ?? 0))
            case .distance(let meters, _):
                // Rough estimate: 5 min/km pace
                total += Int(Double(meters) / 1000.0 * 300.0)
            case .repeat(let reps, let subIntervals):
                total += reps * calculateDuration(subIntervals)
            }
        }
        return total
    }

    // MARK: - Save Flow

    /// Save the workout to the user's library
    func saveWorkout() async {
        guard let workoutToSave = workout else {
            state = .error("No workout to save")
            return
        }

        state = .saving

        do {
            try await apiService.syncWorkout(workoutToSave)
            state = .completed
        } catch {
            state = .error("Failed to save: \(error.localizedDescription)")
        }
    }

    // MARK: - Navigation

    /// Start over with a new recording
    func startOver() {
        transcription = ""
        workout = nil
        confidence = 0
        suggestions = []
        audioURL = nil
        recordingService.cleanupTempFiles()
        checkPermissions()
        if state != .permissionRequired {
            state = .idle
        }
    }

    /// Go back to previous step
    func goBack() {
        switch state {
        case .reviewingTranscription:
            state = .idle
        case .reviewingWorkout:
            state = .reviewingTranscription
        case .error:
            // Return to last valid state
            if workout != nil {
                state = .reviewingWorkout
            } else if !transcription.isEmpty {
                state = .reviewingTranscription
            } else {
                state = .idle
            }
        default:
            break
        }
    }

    /// Dismiss error and return to previous state
    func dismissError() {
        goBack()
    }
}

// MARK: - Formatting Helpers

extension VoiceWorkoutViewModel {
    /// Format recording duration for display
    var formattedDuration: String {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Confidence level as descriptive text
    var confidenceDescription: String {
        switch confidence {
        case 0.9...1.0: return "High confidence"
        case 0.7..<0.9: return "Good match"
        case 0.5..<0.7: return "Moderate confidence"
        default: return "Low confidence - please review"
        }
    }
}
