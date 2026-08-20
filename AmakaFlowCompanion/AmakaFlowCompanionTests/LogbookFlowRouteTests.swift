//
//  LogbookFlowRouteTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2473 — deleting the confirm step must not drop the wrapper's contract.
//
//  CodeRabbit caught this before merge: the rewritten `ActualsFillInFlowView`
//  forwarded only onBack/onSaved, so `onUnverify` — which Today and History
//  both pass — went nowhere. Undo would have silently stopped working from
//  this flow, days after AMA-2472 fixed undo.
//

import SwiftUI
import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class LogbookFlowRouteTests: XCTestCase {

    private var db: AppDatabase!
    private var repo: ActualsRepository!

    override func setUp() async throws {
        db = try AppDatabase.makeTestDatabase()
        repo = ActualsRepository(database: db)
    }

    /// The hooks the wrapper accepts must reach `LogbookView`, not be dropped.
    func testTheFlowForwardsItsHooksToTheLogbook() throws {
        var unverified = false
        let flow = ActualsFillInFlowView(
            viewModel: ActualsFillInViewModel(
                session: ActualsFillInSession.lowerBodyPosteriorSample(),
                repository: repo
            ),
            presentsVerifiedOnSave: false,
            onUnverify: { unverified = true }
        )

        XCTAssertNotNil(flow.onUnverify, "the un-verify hook must survive the rewrite")
        flow.onUnverify?()
        XCTAssertTrue(unverified, "and must actually invoke the caller's closure")
        XCTAssertFalse(
            flow.presentsVerifiedOnSave,
            "a caller that shows its own verified screen is still honoured"
        )
    }

    /// `onBack` is optional on purpose: LogbookView falls back to `dismiss()`
    /// when the caller passes none. Wrapping it in a closure made it always
    /// non-nil, which silently disabled that fallback.
    func testBackStaysOptionalSoTheDismissFallbackWorks() throws {
        let flow = ActualsFillInFlowView(
            viewModel: ActualsFillInViewModel(
                session: ActualsFillInSession.lowerBodyPosteriorSample(),
                repository: repo
            )
        )
        XCTAssertNil(
            flow.onBack,
            "no back handler means LogbookView's own dismiss() must take over"
        )
    }

    // Not tested here: anything requiring `LogbookView` to be instantiated.
    // It crashes under XCTest (SwiftUI view + environment). That includes the
    // `presentsVerifiedOnSave` gate — I wrote a test for it, found it could
    // only restate `flag && false == false`, and deleted it: a tautology is
    // not evidence, and a test that cannot run proves less than a build that
    // cannot compile. The gate is a two-condition Binding in LogbookView and
    // is verified by reading it, not by a green tick that means nothing.
}
