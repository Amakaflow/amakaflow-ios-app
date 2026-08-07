//
//  WatchItemReplaceCoordinatorTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2386: demo replace success / failure.
//

import XCTest
@testable import AmakaFlowCompanion

final class WatchItemReplaceCoordinatorTests: XCTestCase {
    func testDemoReplaceSucceeds() async {
        let coordinator = WatchItemReplaceCoordinator(
            delayNanoseconds: 0,
            shouldFail: false,
            isDemo: true
        )
        let result = await coordinator.replace(
            WatchItemReplaceRequest(
                device: .apple,
                workoutID: "demo-1",
                title: "Push day",
                applePlanID: "demo-1",
                appleDateComponents: nil
            )
        )
        guard case .success = result else {
            return XCTFail("expected success")
        }
    }

    func testDemoReplaceFailsWhenFlagged() async {
        let coordinator = WatchItemReplaceCoordinator(
            delayNanoseconds: 0,
            shouldFail: true,
            isDemo: true
        )
        let result = await coordinator.replace(
            WatchItemReplaceRequest(
                device: .garmin,
                workoutID: "demo-erg",
                title: "Engine EMOM",
                applePlanID: nil,
                appleDateComponents: nil
            )
        )
        guard case .failure = result else {
            return XCTFail("expected failure")
        }
    }

    func testLiveWithoutWiringFailsHonestly() async {
        let coordinator = WatchItemReplaceCoordinator(
            delayNanoseconds: 0,
            shouldFail: false,
            isDemo: false
        )
        let result = await coordinator.replace(
            WatchItemReplaceRequest(
                device: .apple,
                workoutID: "x",
                title: "x",
                applePlanID: "x",
                appleDateComponents: nil
            )
        )
        guard case .failure(let error) = result else {
            return XCTFail("expected failure")
        }
        XCTAssertTrue(error.errorDescription?.contains("not wired") == true)
    }
}
