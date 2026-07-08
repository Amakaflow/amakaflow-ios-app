//
//  WatchConnectivityManagerBehaviorTests.swift
//  AmakaFlowCompanionTests
//
//  Behavioral tests for WatchConnectivityManager via MockWatchSession (issue #431).
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class WatchConnectivityManagerBehaviorTests: XCTestCase {

    // MARK: - Helpers

    private func makeIdleState(version: Int) -> WorkoutState {
        WorkoutState(
            stateVersion: version,
            workoutId: "w-behavior",
            workoutName: "Behavior Test",
            phase: .idle,
            stepIndex: 0,
            stepCount: 1,
            stepName: "Idle",
            stepType: .timed,
            remainingMs: nil,
            roundInfo: nil,
            targetReps: nil,
            lastCommandAck: nil
        )
    }

    private func makeRunningState(version: Int) -> WorkoutState {
        WorkoutState(
            stateVersion: version,
            workoutId: "w-behavior",
            workoutName: "Behavior Test",
            phase: .running,
            stepIndex: 0,
            stepCount: 3,
            stepName: "Burpees",
            stepType: .reps,
            remainingMs: nil,
            roundInfo: nil,
            targetReps: 10,
            lastCommandAck: nil
        )
    }

    // MARK: - Test 1: Command-ack round-trip

    /// When the phone sends an ACK back to a reachable watch, the correct
    /// commandAck message is delivered via sendMessage.
    func testSendAck_whenReachable_deliversCommandAckMessage() throws {
        let mock = MockWatchSession()
        mock.isReachable = true
        let manager = WatchConnectivityManager(session: mock)

        let ack = CommandAck(commandId: "cmd-007", status: .success, errorCode: nil)
        manager.sendAck(ack)

        XCTAssertTrue(mock.sendMessageCalled, "sendAck must call sendMessage when watch is reachable")
        XCTAssertEqual(mock.sentMessages.count, 1)
        let msg = try XCTUnwrap(mock.sentMessages.first, "sentMessages must contain exactly one entry")
        XCTAssertEqual(msg["action"] as? String, "commandAck")
        XCTAssertEqual(msg["commandId"] as? String, "cmd-007")
        XCTAssertEqual(msg["status"] as? String, CommandStatus.success.rawValue)
    }

    /// ACK for an error command carries the error code to the watch.
    func testSendAck_errorStatus_includesErrorCode() throws {
        let mock = MockWatchSession()
        mock.isReachable = true
        let manager = WatchConnectivityManager(session: mock)

        let ack = CommandAck(commandId: "cmd-fail", status: .error, errorCode: "INVALID_STATE")
        manager.sendAck(ack)

        let msg = try XCTUnwrap(mock.sentMessages.first)
        XCTAssertEqual(msg["action"] as? String, "commandAck")
        XCTAssertEqual(msg["status"] as? String, CommandStatus.error.rawValue)
        XCTAssertEqual(msg["errorCode"] as? String, "INVALID_STATE")
    }

    // MARK: - Test 2: State-version supersession

    /// Running-phase state clears applicationContext to prevent the phantom
    /// "Open on iPhone" watch card (AMA-223). The stateVersion of the running
    /// state is superseded — it is NOT persisted.
    func testSendState_runningPhase_clearsApplicationContext() throws {
        let mock = MockWatchSession()
        mock.isReachable = false
        let manager = WatchConnectivityManager(session: mock)

        manager.sendState(makeRunningState(version: 5))

        XCTAssertTrue(mock.updateApplicationContextCalled)
        XCTAssertEqual(
            mock.lastApplicationContext?["action"] as? String, "cleared",
            "Running state must clear applicationContext (AMA-223 phantom card prevention)"
        )
    }

    /// Idle-phase state is persisted in applicationContext so the watch can
    /// display it even after a reconnect. stateVersion must survive the trip.
    func testSendState_idlePhase_writesStateVersionToContext() throws {
        let mock = MockWatchSession()
        mock.isReachable = false
        let manager = WatchConnectivityManager(session: mock)

        manager.sendState(makeIdleState(version: 7))

        XCTAssertTrue(mock.updateApplicationContextCalled)
        let context = try XCTUnwrap(mock.lastApplicationContext)
        XCTAssertEqual(context["action"] as? String, "stateUpdate")
        let stateDict = try XCTUnwrap(context["state"] as? [String: Any])
        XCTAssertEqual(
            stateDict["stateVersion"] as? Int, 7,
            "Idle state must persist stateVersion in applicationContext"
        )
    }

    /// Each sendState call overwrites applicationContext. A later call with a
    /// higher version supersedes the earlier one.
    func testSendState_higherVersionSupersedes_inApplicationContext() throws {
        let mock = MockWatchSession()
        mock.isReachable = false
        let manager = WatchConnectivityManager(session: mock)

        manager.sendState(makeIdleState(version: 3))
        manager.sendState(makeIdleState(version: 9))

        let context = try XCTUnwrap(mock.lastApplicationContext)
        let stateDict = try XCTUnwrap(context["state"] as? [String: Any])
        XCTAssertEqual(
            stateDict["stateVersion"] as? Int, 9,
            "Later sendState call must supersede the earlier version in applicationContext"
        )
    }

    // MARK: - Test 3: Unreachable queuing

    /// When the watch is unreachable, idle state is queued via applicationContext
    /// so it is delivered automatically when the watch reconnects — but no
    /// immediate sendMessage is attempted.
    func testSendState_idleWhenNotReachable_queuesViaContextSkipsMessage() {
        let mock = MockWatchSession()
        mock.isReachable = false
        let manager = WatchConnectivityManager(session: mock)

        manager.sendState(makeIdleState(version: 1))

        XCTAssertTrue(
            mock.updateApplicationContextCalled,
            "applicationContext must be updated even when unreachable (queued for reconnect)"
        )
        XCTAssertFalse(
            mock.sendMessageCalled,
            "sendMessage must not be called when watch is unreachable"
        )
    }

    /// ACK is silently dropped when the watch is not reachable — there is no
    /// queue for ACKs (the command will time out on the watch side anyway).
    func testSendAck_whenNotReachable_doesNotSendMessage() {
        let mock = MockWatchSession()
        mock.isReachable = false
        let manager = WatchConnectivityManager(session: mock)

        manager.sendAck(CommandAck(commandId: "cmd-lost", status: .success, errorCode: nil))

        XCTAssertFalse(mock.sendMessageCalled, "sendAck must not deliver when watch is unreachable")
    }
}
