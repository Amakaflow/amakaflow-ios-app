//
//  FixtureAPIService+CoachKnowledge.swift
//  AmakaFlow
//
//  Coach knowledge surface fixture — split for SwiftLint function_body_length.
//

#if DEBUG
import Foundation

extension FixtureAPIService {
    static func fixtureCoachKnowledgeSurface(
        reviewedActionIDs: Set<String>
    ) -> CoachKnowledgeSurface {
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
        let isReviewed = reviewedActionIDs.contains(sensitiveFact.actionId)
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
}
#endif
