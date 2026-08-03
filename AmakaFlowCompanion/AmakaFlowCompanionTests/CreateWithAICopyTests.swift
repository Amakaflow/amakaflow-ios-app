//
//  CreateWithAICopyTests.swift
//  AmakaFlowCompanionTests
//

import XCTest

@testable import AmakaFlowCompanion

final class CreateWithAICopyTests: XCTestCase {
    func testDetachedGymSetsIncludeContextGymFalse() {
        let flags = CreateWithAIPromptBuilder.includeContext(
            attached: [.profile, .memories]
        )

        XCTAssertEqual(flags.gym, false)
        XCTAssertEqual(flags.profile, true)
        XCTAssertEqual(flags.memories, true)
        XCTAssertEqual(flags.readiness, false)
        XCTAssertEqual(flags.history, false)
    }

    func testComposeNotesTrimsAndCapsAskAtOneThousandCharacters() {
        let notes = CreateWithAIPromptBuilder.composeNotes(
            ask: "  \(String(repeating: "a", count: 1_100))  "
        )

        XCTAssertEqual(notes.count, 1_000)
        XCTAssertEqual(notes, String(repeating: "a", count: 1_000))
    }

    func testDraftBadge() {
        XCTAssertEqual(CreateWithAICopy.draftBadge, "DRAFT · NOT SAVED")
    }

    func testFlowCopyMatchesApprovedLanguage() {
        XCTAssertEqual(CreateWithAICopy.composeTitle, "What do you want to do?")
        XCTAssertEqual(CreateWithAICopy.refineApplying, "applying…")
        XCTAssertEqual(
            CreateWithAICopy.failureFinePrint,
            "If it fails you'll see exactly why — we never swap in a canned workout."
        )
        XCTAssertEqual(
            CreateWithAICopy.rateLimited,
            "You’re refining too quickly. Wait a moment, then try again."
        )
    }

    func testWhyThisPrefersServerList() {
        let bullets = CreateWithAIDraftPresentation.whyThisBullets(
            whyThis: ["one", "two", "three", "four"],
            description: "ignored"
        )

        XCTAssertEqual(bullets, ["one", "two", "three"])
    }

    func testWhyThisFallsBackToDescriptionWithoutInventingSignals() {
        let bullets = CreateWithAIDraftPresentation.whyThisBullets(
            whyThis: nil,
            description: "Fits your request. Keeps the session focused.\nUses simple movements."
        )

        XCTAssertEqual(
            bullets,
            ["Fits your request", "Keeps the session focused", "Uses simple movements"]
        )
    }

    func testCollapseRestsDoesNotEmitRestSteps() {
        let rows = CreateWithAIDraftPresentation.collapseRests(intervals: [
            .reps(
                sets: 3,
                reps: 8,
                name: "Bench",
                load: nil,
                restSec: 90,
                followAlongUrl: nil
            ),
            .rest(seconds: 60),
        ])

        XCTAssertFalse(rows.contains { $0.isNumberedRest })
        XCTAssertEqual(rows.first?.restChipSeconds, 90)
    }

    func testCollapseRestsAttachesStandaloneRestToPreviousWorkRow() {
        let rows = CreateWithAIDraftPresentation.collapseRests(intervals: [
            .time(seconds: 45, target: "Hard"),
            .rest(seconds: 30),
        ])

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.restChipSeconds, 30)
    }

    func testBandRowsEmitOneSummaryForWarmUpAndCooldown() {
        let rows = CreateWithAIDraftPresentation.bandRows(
            warmUp: .warmup(seconds: 300, target: "Band pull-aparts, arm circles"),
            blocks: [.time(seconds: 600, target: "Main work")],
            cooldown: .cooldown(seconds: 180, target: "Chest opener")
        )

        XCTAssertEqual(rows.filter { $0.band == .warmUp }.count, 1)
        XCTAssertEqual(rows.filter { $0.band == .cooldown }.count, 1)
        XCTAssertEqual(rows.filter { $0.band == .main }.count, 1)
    }
}
