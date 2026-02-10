//
//  FixtureAPIService.swift
//  AmakaFlow
//
//  API service stub for fixture-based E2E testing.
//  Loads workouts from bundled JSON fixtures; returns canned success for all writes.
//  No HTTP calls leave the device.
//

#if DEBUG
import Foundation

/// API service that loads from bundled JSON fixtures and stubs all writes.
/// Conforming to APIServiceProviding allows it to be injected via AppDependencies
/// without changes to ViewModels, Engine, or UI.
class FixtureAPIService: APIServiceProviding {

    // MARK: - Reads (from fixtures)

    func fetchWorkouts() async throws -> [Workout] {
        try FixtureLoader.loadWorkouts()
    }

    func fetchScheduledWorkouts() async throws -> [ScheduledWorkout] {
        // Wrap first two fixture workouts as scheduled for today/tomorrow
        let workouts = try FixtureLoader.loadWorkouts()
        return workouts.prefix(2).enumerated().map { index, workout in
            ScheduledWorkout(
                workout: workout,
                scheduledDate: Calendar.current.date(byAdding: .day, value: index, to: Date()),
                scheduledTime: index == 0 ? "09:00" : "18:00",
                syncedToApple: false
            )
        }
    }

    func fetchPushedWorkouts() async throws -> [Workout] {
        try FixtureLoader.loadWorkouts()
    }

    func fetchPendingWorkouts() async throws -> [Workout] {
        try FixtureLoader.loadWorkouts()
    }

    // MARK: - Writes (canned success)

    func syncWorkout(_ workout: Workout) async throws {
        print("[FixtureAPIService] Stub: syncWorkout(\(workout.name)) -> success")
    }

    func getAppleExport(workoutId: String) async throws -> String {
        print("[FixtureAPIService] Stub: getAppleExport(\(workoutId)) -> empty JSON")
        return "{}"
    }

    func parseVoiceWorkout(transcription: String, sportHint: WorkoutSport?) async throws -> VoiceWorkoutParseResponse {
        throw APIError.notImplemented
    }

    func ingestInstagramReel(url: String) async throws -> IngestInstagramReelResponse {
        throw APIError.notImplemented
    }

    func ingestText(text: String, source: String?) async throws -> IngestTextResponse {
        print("[FixtureAPIService] Stub: ingestText -> canned response")
        return IngestTextResponse(name: "Fixture Workout", sport: "strength", source: source)
    }

    func transcribeAudio(
        audioData: String,
        provider: String,
        language: String,
        keywords: [String],
        includeWordTimings: Bool
    ) async throws -> CloudTranscriptionResponse {
        throw APIError.notImplemented
    }

    func syncPersonalDictionary(
        corrections: [String: String],
        customTerms: [String]
    ) async throws -> PersonalDictionaryResponse {
        print("[FixtureAPIService] Stub: syncPersonalDictionary -> empty")
        return PersonalDictionaryResponse(corrections: [:], customTerms: [])
    }

    func fetchPersonalDictionary() async throws -> PersonalDictionaryResponse {
        return PersonalDictionaryResponse(corrections: [:], customTerms: [])
    }

    func logManualWorkout(_ workout: Workout, startedAt: Date, endedAt: Date, durationSeconds: Int) async throws {
        print("[FixtureAPIService] Stub: logManualWorkout(\(workout.name)) -> success")
    }

    func postWorkoutCompletion(_ completion: WorkoutCompletionRequest, isRetry: Bool) async throws -> WorkoutCompletionResponse {
        print("[FixtureAPIService] Stub: postWorkoutCompletion -> success")
        return WorkoutCompletionResponse(
            completionId: "fixture-completion-001",
            id: "fixture-completion-001",
            status: "completed",
            success: true
        )
    }

    func confirmSync(workoutId: String, deviceType: String, deviceId: String?) async throws {
        print("[FixtureAPIService] Stub: confirmSync(\(workoutId)) -> success")
    }

    func reportSyncFailed(workoutId: String, deviceType: String, error: String, deviceId: String?) async throws {
        print("[FixtureAPIService] Stub: reportSyncFailed(\(workoutId)) -> success")
    }

    func fetchProfile() async throws -> UserProfile {
        return UserProfile(
            id: "fixture-test-user",
            email: "fixture-test@amakaflow.com",
            name: "Fixture Test User",
            avatarUrl: nil
        )
    }
}
#endif
