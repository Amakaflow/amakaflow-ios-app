//
//  FixtureAPIService+ProductStubs.swift
//  AmakaFlow
//
//  Readiness / coach / calendar / social / nutrition stubs — SwiftLint split.
//

#if DEBUG
import Foundation

extension FixtureAPIService {
    // MARK: - Readiness (AMA-2054)

    func readinessToday() async throws -> Components.Schemas.ReadinessToday {
        if let readinessTodayResult {
            return try readinessTodayResult.get()
        }
        if readinessTodayEmpty {
            return Components.Schemas.ReadinessToday(
                date: "2026-05-30",
                hasData: false,
                hrv: nil,
                restingHr: nil,
                sleepHours: nil,
                sleepQuality: nil,
                source: nil
            )
        }
        return Components.Schemas.ReadinessToday(
            date: "2026-05-30",
            hasData: true,
            hrv: 62.4,
            restingHr: 48,
            sleepHours: 7.6,
            sleepQuality: "good",
            source: "apple_health"
        )
    }

    func readinessTrend(metric: String, days: Int) async throws -> Components.Schemas.ReadinessTrend {
        if let readinessTrendResult {
            return try readinessTrendResult.get()
        }
        let points = [
            Components.Schemas.ReadinessTrendPoint(date: "2026-05-24", value: 57.0),
            Components.Schemas.ReadinessTrendPoint(date: "2026-05-25", value: nil),
            Components.Schemas.ReadinessTrendPoint(date: "2026-05-26", value: 59.5),
            Components.Schemas.ReadinessTrendPoint(date: "2026-05-27", value: 61.0),
            Components.Schemas.ReadinessTrendPoint(date: "2026-05-28", value: nil),
            Components.Schemas.ReadinessTrendPoint(date: "2026-05-29", value: 60.2),
            Components.Schemas.ReadinessTrendPoint(date: "2026-05-30", value: 62.4)
        ]
        return Components.Schemas.ReadinessTrend(days: days, metric: metric, points: points)
    }

    func readinessSourcePrefs() async throws -> Components.Schemas.ReadinessSourcePrefs {
        if let readinessSourcePrefsResult {
            return try readinessSourcePrefsResult.get()
        }
        return Components.Schemas.ReadinessSourcePrefs(prefs: readinessSourcePrefsEmpty ? [] : fixtureSourcePrefs)
    }

    func setReadinessSourcePref(metric: String, source: String, deviceId: String?) async throws -> Components.Schemas.ReadinessSourcePref {
        setReadinessSourcePrefCallCount += 1
        if setReadinessSourcePrefDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: setReadinessSourcePrefDelayNanoseconds)
        }
        if let setReadinessSourcePrefResult {
            return try setReadinessSourcePrefResult.get()
        }
        let updated = Components.Schemas.ReadinessSourcePref(deviceId: deviceId, metric: metric, source: source)
        if let index = fixtureSourcePrefs.firstIndex(where: { $0.metric == metric }) {
            fixtureSourcePrefs[index] = updated
        } else {
            fixtureSourcePrefs.append(updated)
        }
        print("[FixtureAPIService] Stub: setReadinessSourcePref(\(metric), \(source)) -> success")
        return updated
    }

    // MARK: - Coach (AMA-1147)

    func sendCoachMessage(message: String, context: CoachContext?) async throws -> CoachResponse {
        CoachResponse(id: "fixture", message: "Fixture coach response", suggestions: nil, actionItems: nil)
    }
    func getFatigueAdvice(fatigueScore: Double?, loadHistory: [DailyLoad]?) async throws -> FatigueAdvice {
        FatigueAdvice(level: .low, message: "You're recovering well", recommendations: ["Rest"], suggestedRestDays: 1, recoveryActivities: nil)
    }
    func fetchCoachMemories() async throws -> [CoachMemory] { [] }

    // MARK: - Analytics (AMA-1147)

    func fetchShoeComparison() async throws -> [ShoeStats] { [] }

    // MARK: - Billing (AMA-1147)

    func fetchSubscription() async throws -> Subscription {
        Subscription(plan: "free", status: .active, currentPeriodEnd: nil, cancelAtPeriodEnd: nil, features: [])
    }

    // MARK: - Notification Preferences (AMA-1147)

    func fetchNotificationPreferences() async throws -> NotificationPreferences { NotificationPreferences() }
    func updateNotificationPreferences(_ prefs: NotificationPreferences) async throws -> NotificationPreferences { prefs }

    // MARK: - Calendar Sync (AMA-1238)

    func fetchConnectedCalendars() async throws -> [ConnectedCalendar] { [] }
    func connectCalendar(provider: String) async throws -> String { "https://example.com/auth" }
    func syncCalendar(calendarId: String) async throws -> CalendarSyncResponse { CalendarSyncResponse(syncedEvents: 0) }
    func disconnectCalendar(calendarId: String) async throws {}

    // MARK: - Social Feed (AMA-1273)

    func fetchSocialFeed(cursor: String?, limit: Int) async throws -> FeedResponse {
        FeedResponse(posts: [], nextCursor: nil, hasMore: false)
    }
    func addSocialReaction(postId: String, emoji: String) async throws {}
    func removeSocialReaction(postId: String, emoji: String) async throws {}
    func fetchSocialComments(postId: String) async throws -> CommentsResponse {
        CommentsResponse(comments: [])
    }
    func postSocialComment(postId: String, text: String) async throws {}
    func fetchSocialSettings() async throws -> SocialSettings {
        SocialSettings(discoverable: true, shareWorkouts: true, hideWeights: false)
    }
    func updateSocialSettings(_ settings: SocialSettings) async throws {}
    func fetchUserPublicProfile(userId: String) async throws -> UserPublicProfile {
        UserPublicProfile(userId: userId, userName: "Fixture User", avatarUrl: nil, workoutCount: 0, totalVolume: 0, streakDays: 0, isFollowing: followedUserIds.contains(userId), recentWorkouts: [])
    }
    func followUser(userId: String) async throws { followedUserIds.insert(userId) }
    func unfollowUser(userId: String) async throws { followedUserIds.remove(userId) }

    // MARK: - Challenges (AMA-1276)

    func fetchChallenges() async throws -> ChallengesResponse {
        ChallengesResponse(challenges: [])
    }
    func fetchChallengeDetail(id: String) async throws -> ChallengeDetailResponse {
        ChallengeDetailResponse(
            challenge: Challenge(id: id, title: "Fixture", type: .volume, status: .active, description: nil, target: 1000, targetUnit: "kg", startDate: Date(), endDate: Date(), creatorId: "fix", creatorName: "Fixture", participantCount: 0, isTeamMode: false, isJoined: false, myProgress: nil, myProgressPercentage: nil),
            leaderboard: [],
            myProgress: nil
        )
    }
    func createChallenge(_ request: CreateChallengeRequest) async throws {}
    func joinChallenge(id: String) async throws {}

    // MARK: - Training Crews (AMA-1277)

    func fetchMyCrews() async throws -> CrewListResponse {
        return CrewListResponse(crews: [], count: 0)
    }

    func fetchCrewDetail(id: String) async throws -> CrewDetail {
        throw APIError.notFound
    }

    func fetchCrewFeed(crewId: String) async throws -> CrewFeedResponse {
        return CrewFeedResponse(posts: [], nextCursor: nil)
    }

    func createCrew(_ request: CreateCrewRequest) async throws {}

    func joinCrew(crewId: String, request: JoinCrewRequest) async throws {}

    func leaveCrew(crewId: String) async throws {}

    // MARK: - Leaderboards (AMA-1278)

    func fetchFriendsLeaderboard(dimension: String, period: String) async throws -> LeaderboardAPIResponse {
        LeaderboardAPIResponse(dimension: dimension, period: period, entries: [])
    }

    func fetchCrewLeaderboard(crewId: String, dimension: String, period: String) async throws -> LeaderboardAPIResponse {
        LeaderboardAPIResponse(dimension: dimension, period: period, entries: [])
    }

    // MARK: - Nutrition (AMA-1412)

    func analyzePhoto(imageBase64: String) async throws -> AnalyzePhotoAPIResponse {
        AnalyzePhotoAPIResponse(items: [], totals: MacroTotalsResponse(calories: 0, proteinG: 0, carbsG: 0, fatG: 0), notes: nil)
    }

    func lookupBarcode(code: String) async throws -> BarcodeNutritionAPIResponse {
        throw APIError.notImplemented
    }

    func parseText(text: String) async throws -> ParseTextAPIResponse {
        ParseTextAPIResponse(items: [], totals: MacroTotalsResponse(calories: 0, proteinG: 0, carbsG: 0, fatG: 0), rawText: text)
    }

    func getFuelingStatus() async throws -> FuelingStatusResponse {
        FuelingStatusResponse(status: "green", proteinPct: 0.75, caloriesPct: 0.8, hydrationPct: 0.6, message: "You're fueling well")
    }

    func checkProteinNudge() async throws -> ProteinNudgeResponse {
        ProteinNudgeResponse(shouldNudge: false, proteinCurrent: 100, proteinTarget: 150, message: "Protein on track")
    }

    // MARK: - Coach Suggestions (AMA-1412)

    func suggestWorkout(request: SuggestWorkoutRequest) async throws -> SuggestWorkoutResponse {
        throw APIError.notImplemented
    }

    func postRPEFeedback(_ feedback: RPEFeedbackRequest) async throws -> RPEFeedbackResponse {
        RPEFeedbackResponse(success: true, message: "Feedback recorded", deloadRecommended: false)
    }

    // MARK: - Program Generation (AMA-1413)

    func generateProgram(request: ProgramGenerationRequest) async throws -> ProgramGenerationResponse {
        print("[FixtureAPIService] Stub: generateProgram -> fixture job")
        return ProgramGenerationResponse(jobId: "fixture-job-001", status: "queued", programId: nil, error: nil)
    }

    func fetchGenerationStatus(jobId: String) async throws -> ProgramGenerationStatus {
        print("[FixtureAPIService] Stub: fetchGenerationStatus(\(jobId)) -> completed")
        return ProgramGenerationStatus(jobId: jobId, status: "completed", progress: 100, programId: "fixture-program-001", error: nil)
    }

    func updateProgramStatus(id: String, status: String) async throws {
        print("[FixtureAPIService] Stub: updateProgramStatus(\(id), \(status)) -> success")
    }

    func updateProgramProgress(id: String, currentWeek: Int) async throws {
        print("[FixtureAPIService] Stub: updateProgramProgress(\(id), week \(currentWeek)) -> success")
    }

    func deleteProgram(id: String) async throws {
        print("[FixtureAPIService] Stub: deleteProgram(\(id)) -> success")
    }

    func completeWorkout(workoutId: String) async throws {
        print("[FixtureAPIService] Stub: completeWorkout(\(workoutId)) -> success")
    }

    // MARK: - Volume Analytics (AMA-1414)

    func fetchVolumeAnalytics(startDate: String, endDate: String, granularity: String) async throws -> VolumeAnalyticsResponse {
        VolumeAnalyticsResponse(
            data: [],
            summary: VolumeSummary(totalVolume: 0, totalSets: 0, totalReps: 0, muscleGroupBreakdown: [:]),
            period: VolumePeriod(startDate: startDate, endDate: endDate),
            granularity: granularity
        )
    }

    // MARK: - Bulk Import (AMA-1415)

    func detectImport(request: BulkDetectRequest) async throws -> BulkDetectResponse {
        print("[FixtureAPIService] Stub: detectImport -> canned response")
        return BulkDetectResponse(
            success: true,
            jobId: "fixture-job-001",
            items: [
                DetectedItem(
                    id: "item-001",
                    sourceRef: request.sources.first ?? "fixture-source",
                    parsedTitle: "Fixture Workout A",
                    parsedExerciseCount: 6,
                    confidence: 90,
                    errors: nil,
                    warnings: nil
                )
            ],
            total: 1,
            successCount: 1,
            errorCount: 0
        )
    }

    func matchExercises(request: BulkMatchRequest) async throws -> BulkMatchResponse {
        print("[FixtureAPIService] Stub: matchExercises -> canned response")
        return BulkMatchResponse(
            success: true,
            jobId: request.jobId,
            exercises: [
                ExerciseMatch(
                    id: "ex-001",
                    originalName: "Bench Press",
                    matchedGarminName: "Bench Press",
                    confidence: 95,
                    suggestions: nil,
                    status: "matched",
                    userSelection: nil
                )
            ],
            totalExercises: 1,
            matched: 1,
            needsReview: 0
        )
    }

    func previewImport(request: BulkPreviewRequest) async throws -> BulkPreviewResponse {
        print("[FixtureAPIService] Stub: previewImport -> canned response")
        return BulkPreviewResponse(
            success: true,
            jobId: request.jobId,
            workouts: [
                PreviewWorkout(
                    id: "workout-preview-001",
                    title: "Fixture Workout A",
                    exerciseCount: 6,
                    blockCount: 2,
                    validationIssues: nil,
                    selected: true,
                    isDuplicate: false
                )
            ],
            stats: ImportStats(
                totalDetected: 1,
                totalSelected: 1,
                exercisesMatched: 1,
                exercisesNeedingReview: 0,
                duplicatesFound: 0,
                validationErrors: 0,
                validationWarnings: 0
            )
        )
    }

    func executeImport(request: BulkExecuteRequest) async throws -> BulkExecuteResponse {
        print("[FixtureAPIService] Stub: executeImport -> canned response")
        return BulkExecuteResponse(
            success: true,
            jobId: request.jobId,
            status: "running",
            message: "Import started"
        )
    }

    func fetchImportStatus(jobId: String, profileId: String) async throws -> BulkImportStatus {
        print("[FixtureAPIService] Stub: fetchImportStatus -> complete")
        return BulkImportStatus(
            success: true,
            jobId: jobId,
            status: "complete",
            progress: 100,
            results: [
                ImportResult(
                    workoutId: "workout-preview-001",
                    title: "Fixture Workout A",
                    status: "success",
                    error: nil,
                    savedWorkoutId: "saved-001"
                )
            ],
            error: nil
        )
    }

    func cancelImport(jobId: String, profileId: String) async throws {
        print("[FixtureAPIService] Stub: cancelImport(\(jobId)) -> success")
    }

    func exportUserData() async throws -> Data {
        Data("{}".utf8)
    }

    func deleteAccount() async throws {
        print("[FixtureAPIService] Stub: deleteAccount -> success")
    }

}
#endif
