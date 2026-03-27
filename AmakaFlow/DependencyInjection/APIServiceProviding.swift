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
    func fetchWorkouts(isRetry: Bool) async throws -> [Workout]

    /// Fetch scheduled workouts from backend
    func fetchScheduledWorkouts(isRetry: Bool) async throws -> [ScheduledWorkout]

    /// Fetch workouts that have been pushed to this device
    func fetchPushedWorkouts(isRetry: Bool) async throws -> [Workout]

    /// Fetch pending workouts from sync queue endpoint
    func fetchPendingWorkouts(isRetry: Bool) async throws -> [Workout]

    /// Sync workout to backend
    func syncWorkout(_ workout: Workout) async throws

    /// Get workout export in Apple WorkoutKit format
    func getAppleExport(workoutId: String) async throws -> String

    // MARK: - Voice Workout Parsing

    /// Parse a voice transcription into a structured workout
    func parseVoiceWorkout(transcription: String, sportHint: WorkoutSport?) async throws -> VoiceWorkoutParseResponse

    // MARK: - Instagram Reel Ingestion

    /// Ingest an Instagram Reel URL and return structured workout data
    func ingestInstagramReel(url: String) async throws -> IngestInstagramReelResponse

    // MARK: - Text Ingestion

    /// Ingest workout from plain text
    func ingestText(text: String, source: String?) async throws -> IngestTextResponse

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

    // MARK: - Completion History

    /// Fetch workout completions from backend with pagination
    func fetchCompletions(limit: Int, offset: Int) async throws -> [WorkoutCompletion]

    /// Fetch full workout completion detail
    func fetchCompletionDetail(id: String) async throws -> WorkoutCompletionDetail

    // MARK: - Planning (AMA-1147)

    /// Fetch day states for a date range
    func fetchDayStates(from: String, to: String) async throws -> [DayState]

    /// Generate a proposed training week
    func generateWeek(request: GenerateWeekRequest?) async throws -> ProposedPlan

    /// Detect scheduling conflicts
    func detectConflicts(startDate: String, endDate: String) async throws -> [Conflict]

    /// Parse free-text workout description
    func parseWorkoutText(text: String, context: String?) async throws -> ParsedWorkout

    // MARK: - Actions (AMA-1147)

    /// Fetch pending actions
    func fetchPendingActions() async throws -> [PendingAction]

    /// Approve, reject, or undo a pending action
    func respondToAction(id: String, response: String) async throws -> ActionResponse

    // MARK: - Coach (AMA-1147)

    /// Send a message to the AI coach
    func sendCoachMessage(message: String, context: CoachContext?) async throws -> CoachResponse

    /// Get fatigue advice from the coach
    func getFatigueAdvice(fatigueScore: Double?, loadHistory: [DailyLoad]?) async throws -> FatigueAdvice

    /// Fetch coach memories
    func fetchCoachMemories() async throws -> [CoachMemory]

    // MARK: - Social Feed (AMA-1273)

    /// Fetch paginated community feed
    func fetchSocialFeed(cursor: String?, limit: Int) async throws -> FeedResponse

    /// Add a reaction to a post
    func addSocialReaction(postId: String, emoji: String) async throws

    /// Remove a reaction from a post
    func removeSocialReaction(postId: String, emoji: String) async throws

    /// Fetch comments for a post
    func fetchSocialComments(postId: String) async throws -> CommentsResponse

    /// Post a comment on a feed post
    func postSocialComment(postId: String, text: String) async throws

    /// Fetch social/privacy settings
    func fetchSocialSettings() async throws -> SocialSettings

    /// Update social/privacy settings
    func updateSocialSettings(_ settings: SocialSettings) async throws

    /// Fetch a user's public profile
    func fetchUserPublicProfile(userId: String) async throws -> UserPublicProfile



    // MARK: - Workout Save (AMA-1231)

    /// Save a new or edited workout
    func saveWorkout(_ request: WorkoutSaveRequest) async throws -> Workout

    // MARK: - Calendar Sync (AMA-1238)

    /// Fetch connected calendars
    func fetchConnectedCalendars() async throws -> [ConnectedCalendar]

    /// Connect a calendar provider (returns OAuth URL)
    func connectCalendar(provider: String) async throws -> String

    /// Sync a specific calendar
    func syncCalendar(calendarId: String) async throws -> CalendarSyncResponse

    /// Disconnect a calendar
    func disconnectCalendar(calendarId: String) async throws

    // MARK: - Analytics (AMA-1147)

    /// Fetch shoe comparison stats
    func fetchShoeComparison() async throws -> [ShoeStats]

    // MARK: - Billing (AMA-1147)

    /// Fetch subscription status
    func fetchSubscription() async throws -> Subscription

    // MARK: - Notification Preferences (AMA-1147)

    /// Fetch notification preferences
    func fetchNotificationPreferences() async throws -> NotificationPreferences

    /// Update notification preferences
    func updateNotificationPreferences(_ prefs: NotificationPreferences) async throws -> NotificationPreferences
}

// MARK: - Default Parameter Extensions

extension APIServiceProviding {
    /// Convenience method with default isRetry
    func fetchWorkouts() async throws -> [Workout] {
        try await fetchWorkouts(isRetry: false)
    }

    /// Convenience method with default isRetry
    func fetchScheduledWorkouts() async throws -> [ScheduledWorkout] {
        try await fetchScheduledWorkouts(isRetry: false)
    }

    /// Convenience method with default isRetry
    func fetchPushedWorkouts() async throws -> [Workout] {
        try await fetchPushedWorkouts(isRetry: false)
    }

    /// Convenience method with default isRetry
    func fetchPendingWorkouts() async throws -> [Workout] {
        try await fetchPendingWorkouts(isRetry: false)
    }

    /// Convenience method with default sportHint
    func parseVoiceWorkout(transcription: String) async throws -> VoiceWorkoutParseResponse {
        try await parseVoiceWorkout(transcription: transcription, sportHint: nil)
    }

    /// Convenience method with default source
    func ingestText(text: String) async throws -> IngestTextResponse {
        try await ingestText(text: text, source: nil)
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

    /// Convenience method with default pagination
    func fetchCompletions() async throws -> [WorkoutCompletion] {
        try await fetchCompletions(limit: 50, offset: 0)
    }

    /// Convenience method with default generate-week request
    func generateWeek() async throws -> ProposedPlan {
        try await generateWeek(request: nil)
    }

    /// Convenience method with default coach context
    func sendCoachMessage(message: String) async throws -> CoachResponse {
        try await sendCoachMessage(message: message, context: nil)
    }

    /// Convenience method with default parse context
    func parseWorkoutText(text: String) async throws -> ParsedWorkout {
        try await parseWorkoutText(text: text, context: nil)
    }

    /// Convenience method with default fatigue params
    func getFatigueAdvice() async throws -> FatigueAdvice {
        try await getFatigueAdvice(fatigueScore: nil, loadHistory: nil)
    }
}

// MARK: - APIService Conformance

extension APIService: APIServiceProviding {
    // Swift default-parameter methods do not automatically satisfy protocol requirements
    // for the no-argument variant, so we provide explicit forwarding stubs here.
    func fetchWorkouts() async throws -> [Workout] {
        try await fetchWorkouts(isRetry: false)
    }

    func fetchScheduledWorkouts() async throws -> [ScheduledWorkout] {
        try await fetchScheduledWorkouts(isRetry: false)
    }

    func fetchPushedWorkouts() async throws -> [Workout] {
        try await fetchPushedWorkouts(isRetry: false)
    }

    func fetchPendingWorkouts() async throws -> [Workout] {
        try await fetchPendingWorkouts(isRetry: false)
    }
}
