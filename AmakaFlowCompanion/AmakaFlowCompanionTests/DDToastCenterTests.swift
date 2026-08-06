//
//  DDToastCenterTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2383 — toast queue, pending morph, honest-progress reveal.
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class DDToastCenterTests: XCTestCase {

    private var center: DDToastCenter!

    override func setUp() {
        super.setUp()
        center = DDToastCenter()
    }

    override func tearDown() {
        center.dismissCurrent()
        center = nil
        super.tearDown()
    }

    func testQueueSecondToastWaits() {
        center.success("First")
        center.success("Second", sub: "SUB")
        XCTAssertEqual(center.current?.text, "First")
        center.dismissCurrent()
        XCTAssertEqual(center.current?.text, "Second")
        XCTAssertEqual(center.current?.sub, "SUB")
    }

    func testPendingNeverAutoClaimsSuccess() {
        let id = center.beginPending(text: DDToastCopy.sendingToGarmin)
        XCTAssertEqual(center.current?.id, id)
        XCTAssertEqual(center.current?.pending, true)
        XCTAssertEqual(center.current?.text, DDToastCopy.sendingToGarmin)
        center.resolve(
            id: id,
            kind: .device,
            text: DDToastCopy.sentToGarmin,
            sub: DDToastCopy.garminWidgetSub
        )
        XCTAssertEqual(center.current?.id, id)
        XCTAssertEqual(center.current?.pending, false)
        XCTAssertEqual(center.current?.text, DDToastCopy.sentToGarmin)
        XCTAssertEqual(center.current?.kind, .device)
    }

    func testUndoCarriesAction() {
        var tapped = false
        center.undo(DDToastCopy.removedFromWatch, sub: DDToastCopy.libraryUntouched) {
            tapped = true
        }
        XCTAssertEqual(center.current?.action, DDToastCopy.undoAction)
        XCTAssertEqual(center.current?.kind, .undo)
        center.current?.onAction?()
        XCTAssertTrue(tapped)
    }

    func testProgressTotalCountsRowsAndBulletsOnly() {
        let config = BuildRevealConfig(
            title: "T",
            verb: "COMPOSING",
            doneNote: "DONE",
            cta: "Go",
            building: "…",
            beats: [
                BuildBeat(kind: .row, name: "R1", detail: "D1"),
                BuildBeat(kind: .row, name: "R2", detail: "D2"),
                BuildBeat(kind: .bullet, detail: "why"),
                BuildBeat(kind: .pills, pills: ["A", "B"]),
            ]
        )
        // bands/pills/credit don't count; rows + bullets do.
        XCTAssertEqual(config.progressTotal, 3)
    }

    func testRevealNextIsHonestProgress() async {
        let config = BuildRevealConfig(
            title: "T",
            verb: "DRAFTING",
            doneNote: "DONE",
            cta: "Save",
            building: "…",
            beats: [
                BuildBeat(kind: .bullet, detail: "why"),
                BuildBeat(kind: .row, name: "Bench", detail: "3×8"),
            ]
        )
        let controller = BuildRevealController(config: config)
        XCTAssertEqual(controller.visibleCount, 0)
        controller.revealNext()
        XCTAssertEqual(controller.visibleCount, 1)
        XCTAssertFalse(controller.isDone)
        controller.revealNext()
        try? await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertTrue(controller.isDone)
    }
}
