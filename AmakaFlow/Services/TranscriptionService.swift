//
//  TranscriptionService.swift
//  AmakaFlow
//
//  On-device speech transcription using SFSpeechRecognizer (AMA-5)
//

import Foundation
import Speech
import Combine

/// Service for transcribing voice recordings to text using on-device speech recognition
@MainActor
class TranscriptionService: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var isTranscribing = false
    @Published private(set) var transcription: String = ""
    @Published private(set) var progress: Double = 0
    @Published private(set) var error: TranscriptionError?

    // MARK: - Properties

    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechRecognitionTask?

    /// Whether on-device recognition is available (more private, no network)
    var supportsOnDeviceRecognition: Bool {
        speechRecognizer?.supportsOnDeviceRecognition ?? false
    }

    /// Whether the service is available for use
    var isAvailable: Bool {
        speechRecognizer?.isAvailable ?? false
    }

    // MARK: - Error Types

    enum TranscriptionError: LocalizedError {
        case notAvailable
        case permissionDenied
        case recognitionFailed(Error)
        case noSpeechDetected
        case cancelled

        var errorDescription: String? {
            switch self {
            case .notAvailable:
                return "Speech recognition is not available on this device"
            case .permissionDenied:
                return "Speech recognition permission is required"
            case .recognitionFailed(let error):
                return "Transcription failed: \(error.localizedDescription)"
            case .noSpeechDetected:
                return "No speech was detected in the recording"
            case .cancelled:
                return "Transcription was cancelled"
            }
        }
    }

    // MARK: - Initialization

    init() {
        // Use US English for fitness terminology
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    // MARK: - Transcription

    /// Transcribe an audio file to text
    /// - Parameter audioURL: URL of the audio file to transcribe
    /// - Returns: The transcribed text
    func transcribe(audioURL: URL) async throws -> String {
        // Check availability
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw TranscriptionError.notAvailable
        }

        // Check permission
        guard PermissionManager.shared.hasSpeechRecognitionPermission else {
            throw TranscriptionError.permissionDenied
        }

        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil

        isTranscribing = true
        transcription = ""
        progress = 0
        error = nil

        defer {
            isTranscribing = false
            progress = 1.0
        }

        // Create recognition request
        let request = SFSpeechURLRecognitionRequest(url: audioURL)

        // Prefer on-device recognition for privacy
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        // Configure for workout descriptions
        request.shouldReportPartialResults = true
        request.addsPunctuation = true

        // Custom context phrases for fitness terminology
        if #available(iOS 17.0, *) {
            request.customizedLanguageModel = self.createWorkoutLanguageModel()
        }

        return try await withCheckedThrowingContinuation { continuation in
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    if let error = error {
                        self?.error = .recognitionFailed(error)
                        continuation.resume(throwing: TranscriptionError.recognitionFailed(error))
                        return
                    }

                    guard let result = result else { return }

                    // Update partial transcription
                    self?.transcription = result.bestTranscription.formattedString
                    self?.progress = 0.5 // Estimate progress

                    // Check if final result
                    if result.isFinal {
                        let finalText = result.bestTranscription.formattedString

                        if finalText.isEmpty {
                            self?.error = .noSpeechDetected
                            continuation.resume(throwing: TranscriptionError.noSpeechDetected)
                        } else {
                            self?.transcription = finalText
                            continuation.resume(returning: finalText)
                        }
                    }
                }
            }
        }
    }

    /// Cancel any in-progress transcription
    func cancel() {
        recognitionTask?.cancel()
        recognitionTask = nil
        isTranscribing = false
        error = .cancelled
    }

    // MARK: - Custom Language Model

    @available(iOS 17.0, *)
    private func createWorkoutLanguageModel() -> SFSpeechLanguageModel.Configuration? {
        // Create custom vocabulary for fitness terms
        let workoutTerms = [
            // Exercises
            "squats", "lunges", "deadlifts", "bench press", "push ups", "pull ups",
            "burpees", "planks", "crunches", "sit ups", "jumping jacks", "mountain climbers",
            "box jumps", "kettlebell swings", "dumbbell curls", "bicep curls", "tricep dips",
            "lat pulldowns", "rows", "shoulder press", "military press", "leg press",
            "calf raises", "hip thrusts", "glute bridges", "Romanian deadlifts", "sumo deadlifts",

            // Running terms
            "tempo run", "interval training", "fartlek", "long run", "easy run",
            "recovery run", "hill repeats", "speed work", "strides", "warm up", "cool down",
            "negative splits", "progressive run",

            // Cardio
            "HIIT", "Tabata", "AMRAP", "EMOM", "circuit training", "cross training",

            // Sets and reps
            "reps", "sets", "rounds", "supersets", "drop sets", "pyramid sets",
            "rest period", "rest for", "seconds", "minutes",

            // Intensity
            "RPE", "max effort", "moderate", "light", "heavy", "bodyweight",

            // Equipment
            "barbell", "dumbbell", "kettlebell", "resistance band", "medicine ball",
            "foam roller", "yoga mat", "pull up bar", "squat rack"
        ]

        // Note: In a production app, you would create a proper SFSpeechLanguageModel.Configuration
        // with these terms. For now, we rely on the built-in recognition which handles
        // common fitness terms reasonably well.
        return nil
    }
}

// MARK: - Real-time Transcription Support

extension TranscriptionService {
    /// Start real-time transcription from audio buffer (for live preview)
    /// This is an alternative approach that transcribes as the user speaks
    func startRealtimeTranscription() async throws {
        // For future enhancement: implement real-time transcription
        // using SFSpeechAudioBufferRecognitionRequest and audio tap
    }
}
