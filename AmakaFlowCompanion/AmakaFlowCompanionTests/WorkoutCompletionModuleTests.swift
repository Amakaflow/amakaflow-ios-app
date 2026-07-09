//
//  WorkoutCompletionModuleTests.swift
//  AmakaFlowCompanionTests
//
//  Issue #446: state-machine tests for WorkoutCompletionModule.
//  No WorkoutEngine spy — tests drive the module directly.
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class WorkoutCompletionModuleTests: XCTestCase {

    private var module: WorkoutCompletionModule!

    override func setUp() async throws {
        try await super.setUp()
        module = WorkoutCompletionModule()
    }

    override func tearDown() async throws {
        module = nil
        try await super.tearDown()
    }

    func test_initialState_isIdle() {
        XCTAssertEqual(module.saveStatus, .idle)
        XCTAssertNil(module.lastSaveError)
    }

    func test_idle_inFlight_succeeded() {
        module.beginSave()
        XCTAssertEqual(module.saveStatus, .inFlight)
        XCTAssertNil(module.lastSaveError)

        module.succeedSave()
        XCTAssertEqual(module.saveStatus, .succeeded)
        XCTAssertNil(module.lastSaveError)
    }

    func test_idle_inFlight_failed() {
        let error = CTAError.network(code: .notConnectedToInternet)

        module.beginSave()
        XCTAssertEqual(module.saveStatus, .inFlight)
        XCTAssertNil(module.lastSaveError)

        module.failSave(error)
        XCTAssertEqual(module.saveStatus, .failed(error))
        XCTAssertEqual(module.lastSaveError, error)
    }

    func test_acknowledgeError_resetsToIdle() {
        let error = CTAError.network(code: .timedOut)
        module.beginSave()
        module.failSave(error)

        module.acknowledgeError()
        XCTAssertEqual(module.saveStatus, .idle)
        XCTAssertNil(module.lastSaveError)
    }

    func test_beginSave_clearsPriorSaveError() {
        let error = CTAError.network(code: .timedOut)
        module.beginSave()
        module.failSave(error)

        module.beginSave()
        XCTAssertNil(module.lastSaveError)
        XCTAssertEqual(module.saveStatus, .inFlight)
    }
}
