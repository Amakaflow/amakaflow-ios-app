//
//  APIServiceProviding.swift
//  AmakaFlow
//
//  Protocol abstraction for APIService to enable dependency injection and testing.
//

import Foundation

/// Protocol defining the API service interface for dependency injection
protocol APIServiceProviding {
    // MARK: - Workouts

    /// Fetch workouts from backend
    func fetchWorkouts() async throws -> [Workout]

    /// Fetch scheduled workouts from backend
    func fetchScheduledWorkouts() async throws -> [ScheduledWorkout]

    /// Fetch workouts that have been pushed to this device
    func fetchPushedWorkouts() async throws -> [Workout]

    /// Fetch pending workouts from sync queue endpoint
    func fetchPendingWorkouts() async throws -> [Workout]

    /// Sync workout to backend
    func syncWorkout(_ workout: Workout) async throws

    /// Get workout export in Apple WorkoutKit format
    func getAppleExport(workoutId: String) async throws -> String

    // MARK: - Voice Workout Parsing

    /// Parse a voice transcription into a structured workout
    func parseVoiceWorkout(transcription: String, sportHint: WorkoutSport?) async throws -> VoiceWorkoutParseResponse

    // MARK: - Cloud Transcription

    /// Request cloud transcription using specified provider
    func transcribeAudio(
        audioData: String,
        provider: String,
        language: String,
        keywords: [String],
        includeWordTimings: Bool
    ) async throws -> CloudTranscriptionResponse

    // MARK: - Personal Dictionary

    /// Sync personal dictionary with backend
    func syncPersonalDictionary(
        corrections: [String: String],
        customTerms: [String]
    ) async throws -> PersonalDictionaryResponse

    /// Fetch personal dictionary from backend
    func fetchPersonalDictionary() async throws -> PersonalDictionaryResponse

    // MARK: - Manual Workout Logging

    /// Log a manually-recorded workout completion to activity history
    func logManualWorkout(_ workout: Workout, startedAt: Date, endedAt: Date, durationSeconds: Int) async throws

    // MARK: - Workout Completion

    /// Post workout completion to backend
    func postWorkoutCompletion(_ completion: WorkoutCompletionRequest, isRetry: Bool) async throws -> WorkoutCompletionResponse

    // MARK: - Sync Confirmation

    /// Confirm that a workout was successfully synced/downloaded to this device
    func confirmSync(workoutId: String, deviceType: String, deviceId: String?) async throws

    /// Report that a workout sync/download failed
    func reportSyncFailed(workoutId: String, deviceType: String, error: String, deviceId: String?) async throws

    // MARK: - User Profile

    /// Fetch user profile from backend
    func fetchProfile() async throws -> UserProfile
}

// MARK: - Default Parameter Extensions

extension APIServiceProviding {
    /// Convenience method with default sportHint
    func parseVoiceWorkout(transcription: String) async throws -> VoiceWorkoutParseResponse {
        try await parseVoiceWorkout(transcription: transcription, sportHint: nil)
    }

    /// Convenience method with default isRetry
    func postWorkoutCompletion(_ completion: WorkoutCompletionRequest) async throws -> WorkoutCompletionResponse {
        try await postWorkoutCompletion(completion, isRetry: false)
    }

    /// Convenience method with default deviceType and deviceId
    func confirmSync(workoutId: String) async throws {
        try await confirmSync(workoutId: workoutId, deviceType: "ios", deviceId: nil)
    }

    /// Convenience method with default deviceType and deviceId
    func reportSyncFailed(workoutId: String, error: String) async throws {
        try await reportSyncFailed(workoutId: workoutId, deviceType: "ios", error: error, deviceId: nil)
    }
}

// MARK: - APIService Conformance

extension APIService: APIServiceProviding {}
