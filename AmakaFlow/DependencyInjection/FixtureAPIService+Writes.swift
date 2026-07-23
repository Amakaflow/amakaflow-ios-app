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
        return PersonalDictionaryResponse(corrections: [:], customTerms: [])
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
        return UserProfile(
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

    func fetchDayStates(from: String, to: String) async throws -> [DayState] { [] }
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
        let sensitiveFact = CoachKnowledgePendingSensitiveFact(
            id: "fixture-knee-review",
            actionId: "pa-fixture-knee-review",
            text: "Possible left knee issue",
            category: "Injury",
            state: "needs_review",
            reviewState: "pending_user",
            heldLabel: "HELD · NOT APPLIED",
            prompt: "Treat this as an active injury to plan around?",
            source: CoachKnowledgeSourceRef(
                kind: "chat",
                sourceId: "fixture-telegram-knee",
                label: "From chat",
                title: "Telegram note",
                uri: "",
                quote: "Knee was a bit sore.",
                confidence: 0.7,
                occurredAt: "2026-04-22"
            ),
            provenance: [],
            detail: "Mentioned knee soreness after a long run. Not accepted coach truth."
        )
        let isReviewed = reviewedCoachKnowledgeActionIDs.contains(sensitiveFact.actionId)
        return CoachKnowledgeSurface(
            mode: "mock",
            readableOrder: ["sections", "provenance"],
            sections: [
                CoachKnowledgeSection(
                    id: "goals",
                    title: "Goals",
                    summary: "",
                    facts: [
                        CoachKnowledgeFact(
                            id: "fixture-goal",
                            text: "HYROX race - May 2026",
                            state: "accepted",
                            category: "goal",
                            confidence: 0.94,
                            sensitivity: "public_or_low",
                            source: CoachKnowledgeSourceRef(
                                kind: "user",
                                sourceId: "fixture-chat-goal",
                                label: "You told me",
                                title: "Goal chat",
                                uri: "",
                                quote: "HYROX in May.",
                                confidence: 0.94,
                                occurredAt: "2026-04-20"
                            ),
                            provenance: []
                        )
                    ]
                ),
                CoachKnowledgeSection(
                    id: "training",
                    title: "Training",
                    summary: "",
                    facts: [
                        CoachKnowledgeFact(
                            id: "fixture-threshold",
                            text: "Threshold pace is about 4:38/km",
                            state: "accepted",
                            category: "training",
                            confidence: 0.82,
                            sensitivity: "public_or_low",
                            source: CoachKnowledgeSourceRef(
                                kind: "inferred",
                                sourceId: "fixture-threshold-inference",
                                label: "Inferred",
                                title: "Threshold inference",
                                uri: "",
                                quote: "Last 6 threshold sessions.",
                                confidence: 0.82,
                                occurredAt: "2026-04-24"
                            ),
                            provenance: [
                                CoachKnowledgeSourceRef(
                                    kind: "device",
                                    sourceId: "fixture-garmin-965",
                                    label: "From device",
                                    title: "Garmin workout",
                                    uri: "",
                                    quote: "4x8 min interval run.",
                                    confidence: 0.8,
                                    occurredAt: "2026-04-18"
                                )
                            ]
                        )
                    ]
                )
            ],
            sensitivePending: isReviewed ? [] : [sensitiveFact],
            contradictions: isReviewed ? [] : [
                CoachKnowledgeContradiction(
                    id: "fixture-knee-contradiction",
                    state: "needs_user_review",
                    claimIdA: "fixture-knee-fine",
                    claimIdB: "fixture-knee-review",
                    options: nil
                )
            ],
            dataGaps: [
                CoachKnowledgeGap(
                    id: "fixture-hrv-gap",
                    title: "No HRV for 3 days",
                    detail: "Planning uses the 14-day baseline until a source reconnects.",
                    mode: "data_gap",
                    actionLabel: "Connect a source"
                )
            ],
            contract: CoachKnowledgeContract(
                readRoute: "GET /coach/wiki/surface",
                reviewQueueRoute: "GET /coach/wiki/review-queue",
                reviewActionRoutes: [
                    "POST /coach/wiki/review-actions/{action_id}/approve",
                    "POST /coach/wiki/review-actions/{action_id}/reject"
                ],
                factStates: ["accepted", "rejected", "superseded", "contradicted", "needs_review"],
                mode: "mock"
            )
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
