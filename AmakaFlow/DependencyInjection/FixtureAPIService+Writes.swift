//
//  FixtureAPIService+Writes.swift
//  AmakaFlow
//
//  Writes / planning / agent stubs — SwiftLint split.
//

#if DEBUG
import Foundation

extension FixtureAPIService {
    // MARK: - Writes (canned success)

    func syncWorkout(_ workout: Workout) async throws {
        print("[FixtureAPIService] Stub: syncWorkout(\(workout.name)) -> success")
    }

    func getAppleExport(workoutId: String) async throws -> String {
        print("[FixtureAPIService] Stub: getAppleExport(\(workoutId)) -> empty JSON")
        return "{}"
    }

    func mintTelegramLinkToken() async throws -> TelegramLinkTokenResponse {
        TelegramLinkTokenResponse(
            token: "fixture-telegram-token",
            deepLink: "https://t.me/amakaflow_userbot?start=fixture-telegram-token",
            nativeLink: "tg://resolve?domain=amakaflow_userbot&start=fixture-telegram-token",
            expiresInSeconds: 900
        )
    }

    func getTelegramLinkStatus(token: String) async throws -> TelegramLinkStatusResponse {
        TelegramLinkStatusResponse(
            linked: true,
            telegramId: 123_456_789,
            telegramIdHash: "fixture-telegram-hash",
            usedAt: Date()
        )
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
        PersonalDictionaryResponse(corrections: [:], customTerms: [])
    }

    func logManualWorkout(_ workout: Workout, startedAt: Date, endedAt: Date, durationSeconds: Int) async throws {
        print("[FixtureAPIService] Stub: logManualWorkout(\(workout.name)) -> success")
    }

    func postWorkoutCompletion(_ completion: WorkoutCompletionRequest, isRetry: Bool, requestID: String?) async throws -> WorkoutCompletionResponse {
        print("[FixtureAPIService] Stub: postWorkoutCompletion source=\(completion.source) (requestID=\(requestID ?? "nil"))")
        // AMA-2290: phone completions land on Today diary for fixture e2e.
        if completion.source == "phone" {
            return Self.recordPhoneCompletion(request: completion)
        }
        return WorkoutCompletionResponse(
            completionId: "fixture-completion-001",
            id: "fixture-completion-001",
            status: "completed",
            success: true
        )
    }

    func confirmSync(workoutId: String, deviceType: String, deviceId: String?, requestID: String?) async throws {
        print("[FixtureAPIService] Stub: confirmSync(\(workoutId)) -> success (requestID=\(requestID ?? "nil"))")
    }

    func reportSyncFailed(workoutId: String, deviceType: String, error: String, deviceId: String?, requestID: String?) async throws {
        print("[FixtureAPIService] Stub: reportSyncFailed(\(workoutId)) -> success (requestID=\(requestID ?? "nil"))")
    }

    func fetchProfile() async throws -> UserProfile {
        UserProfile(
            id: "fixture-test-user",
            email: "fixture-test@amakaflow.com",
            name: "Fixture Test User",
            avatarUrl: nil
        )
    }

    func fetchCompletions(limit: Int, offset: Int) async throws -> [WorkoutCompletion] {
        Self.diaryCompletions(limit: limit, offset: offset)
    }

    func fetchCompletionDetail(id: String) async throws -> WorkoutCompletionDetail {
        Self.diaryCompletionDetail(id: id)
    }

    // MARK: - Planning (AMA-1147)

    func fetchDayStates(from: String, to toDate: String) async throws -> [DayState] { [] }
    func generateWeek(request: GenerateWeekRequest?) async throws -> ProposedPlan {
        ProposedPlan(weekStartDate: "2026-03-21", days: [], rationale: "Fixture plan", totalLoadScore: nil)
    }
    func detectConflicts(startDate: String, endDate: String) async throws -> [Conflict] { [] }
    func parseWorkoutText(text: String, context: String?) async throws -> ParseTextResult {
        ParseTextResult(
            success: true,
            exercises: [ParsedExercise(rawName: "Fixture Exercise", sets: 3, reps: "10", order: 1)],
            detectedFormat: "free_text",
            confidence: 0.9,
            source: context
        )
    }

    // MARK: - Agent Actions (AMA-1956)

    func fetchAgentActions(status: String?) async throws -> [AgentAction] { [] }
    func respondToAction(id: String, decision: String) async throws -> AgentAction { .samplePending }
    func undoAction(id: String) async throws -> AgentAction { .sampleApplied }

    func fetchCoachKnowledgeSurface() async throws -> CoachKnowledgeSurface {
        Self.fixtureCoachKnowledgeSurface(
            reviewedActionIDs: reviewedCoachKnowledgeActionIDs
        )
    }

    func reviewCoachKnowledge(
        actionId: String,
        decision: CoachKnowledgeReviewDecision,
        reason: String
    ) async throws -> CoachKnowledgeReviewResponse {
        reviewedCoachKnowledgeActionIDs.insert(actionId)
        return CoachKnowledgeReviewResponse(
            operation: decision.rawValue,
            claim: ["id": .string("fixture-knee-review")],
            pendingAction: ["id": .string(actionId), "status": .string(decision == .approve ? "approved" : "rejected")],
            audit: ["boundary": .string("coach_wiki_review")],
            cacheInvalidated: true
        )
    }
}
#endif
