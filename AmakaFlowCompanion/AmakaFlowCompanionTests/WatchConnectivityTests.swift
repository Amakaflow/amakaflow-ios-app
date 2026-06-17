//
//  WatchConnectivityTests.swift
//  AmakaFlowCompanionTests
//
//  Unit tests for Watch connectivity state models and serialization
//

import XCTest
@testable import AmakaFlowCompanion

final class WatchConnectivityTests: XCTestCase {

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    // MARK: - WorkoutState Tests

    func testWorkoutStateEncodeDecode() throws {
        let state = WorkoutState(
            stateVersion: 42,
            workoutId: "workout-123",
            workoutName: "Morning HIIT",
            phase: .running,
            stepIndex: 2,
            stepCount: 10,
            stepName: "Burpees",
            stepType: .reps,
            remainingMs: 30000,
            roundInfo: "Round 2/3",
            targetReps: 15,
            lastCommandAck: nil
        )

        let data = try encoder.encode(state)
        let decoded = try decoder.decode(WorkoutState.self, from: data)

        XCTAssertEqual(decoded.stateVersion, 42)
        XCTAssertEqual(decoded.workoutId, "workout-123")
        XCTAssertEqual(decoded.workoutName, "Morning HIIT")
        XCTAssertEqual(decoded.phase, .running)
        XCTAssertEqual(decoded.stepIndex, 2)
        XCTAssertEqual(decoded.stepCount, 10)
        XCTAssertEqual(decoded.stepName, "Burpees")
        XCTAssertEqual(decoded.stepType, .reps)
        XCTAssertEqual(decoded.remainingMs, 30000)
        XCTAssertEqual(decoded.roundInfo, "Round 2/3")
        XCTAssertEqual(decoded.targetReps, 15)
        XCTAssertNil(decoded.lastCommandAck)
    }

    func testWorkoutStateWithCommandAck() throws {
        let ack = CommandAck(
            commandId: "cmd-123",
            status: .success,
            errorCode: nil
        )

        let state = WorkoutState(
            stateVersion: 1,
            workoutId: "w1",
            workoutName: "Test",
            phase: .paused,
            stepIndex: 0,
            stepCount: 5,
            stepName: "Warmup",
            stepType: .timed,
            remainingMs: 60000,
            roundInfo: nil,
            targetReps: nil,
            lastCommandAck: ack
        )

        let data = try encoder.encode(state)
        let decoded = try decoder.decode(WorkoutState.self, from: data)

        XCTAssertNotNil(decoded.lastCommandAck)
        XCTAssertEqual(decoded.lastCommandAck?.commandId, "cmd-123")
        XCTAssertEqual(decoded.lastCommandAck?.status, .success)
    }

    func testWorkoutStateMinimalFields() throws {
        let state = WorkoutState(
            stateVersion: 0,
            workoutId: "min",
            workoutName: "Min",
            phase: .idle,
            stepIndex: 0,
            stepCount: 0,
            stepName: "",
            stepType: .timed,
            remainingMs: nil,
            roundInfo: nil,
            targetReps: nil,
            lastCommandAck: nil
        )

        let data = try encoder.encode(state)
        let decoded = try decoder.decode(WorkoutState.self, from: data)

        XCTAssertNil(decoded.remainingMs)
        XCTAssertNil(decoded.roundInfo)
        XCTAssertNil(decoded.targetReps)
    }

    // MARK: - WorkoutPhase Tests

    func testAllWorkoutPhasesEncodeDecode() throws {
        let phases: [WorkoutPhase] = [.idle, .running, .paused, .resting, .ended]

        for phase in phases {
            let data = try encoder.encode(phase)
            let decoded = try decoder.decode(WorkoutPhase.self, from: data)
            XCTAssertEqual(decoded, phase)
        }
    }

    func testWorkoutPhaseRawValues() {
        XCTAssertEqual(WorkoutPhase.idle.rawValue, "idle")
        XCTAssertEqual(WorkoutPhase.running.rawValue, "running")
        XCTAssertEqual(WorkoutPhase.paused.rawValue, "paused")
        XCTAssertEqual(WorkoutPhase.resting.rawValue, "resting")
        XCTAssertEqual(WorkoutPhase.ended.rawValue, "ended")
    }

    // MARK: - StepType Tests

    func testAllStepTypesEncodeDecode() throws {
        let types: [StepType] = [.timed, .reps, .distance]

        for type in types {
            let data = try encoder.encode(type)
            let decoded = try decoder.decode(StepType.self, from: data)
            XCTAssertEqual(decoded, type)
        }
    }

    func testStepTypeRawValues() {
        XCTAssertEqual(StepType.timed.rawValue, "timed")
        XCTAssertEqual(StepType.reps.rawValue, "reps")
        XCTAssertEqual(StepType.distance.rawValue, "distance")
    }

    // MARK: - EndReason Tests

    func testAllEndReasonsEncodeDecode() throws {
        let reasons: [EndReason] = [.completed, .userEnded, .error]

        for reason in reasons {
            let data = try encoder.encode(reason)
            let decoded = try decoder.decode(EndReason.self, from: data)
            XCTAssertEqual(decoded, reason)
        }
    }

    func testEndReasonRawValues() {
        XCTAssertEqual(EndReason.completed.rawValue, "completed")
        XCTAssertEqual(EndReason.userEnded.rawValue, "userEnded")
        XCTAssertEqual(EndReason.error.rawValue, "error")
    }

    // MARK: - CommandAck Tests

    func testCommandAckSuccess() throws {
        let ack = CommandAck(
            commandId: "cmd-456",
            status: .success,
            errorCode: nil
        )

        let data = try encoder.encode(ack)
        let decoded = try decoder.decode(CommandAck.self, from: data)

        XCTAssertEqual(decoded.commandId, "cmd-456")
        XCTAssertEqual(decoded.status, .success)
        XCTAssertNil(decoded.errorCode)
    }

    func testCommandAckError() throws {
        let ack = CommandAck(
            commandId: "cmd-789",
            status: .error,
            errorCode: "INVALID_STATE"
        )

        let data = try encoder.encode(ack)
        let decoded = try decoder.decode(CommandAck.self, from: data)

        XCTAssertEqual(decoded.commandId, "cmd-789")
        XCTAssertEqual(decoded.status, .error)
        XCTAssertEqual(decoded.errorCode, "INVALID_STATE")
    }

    // MARK: - CommandStatus Tests

    func testCommandStatusEncodeDecode() throws {
        let statuses: [CommandStatus] = [.success, .error]

        for status in statuses {
            let data = try encoder.encode(status)
            let decoded = try decoder.decode(CommandStatus.self, from: data)
            XCTAssertEqual(decoded, status)
        }
    }

    // MARK: - RemoteCommand Tests

    func testAllRemoteCommandsEncodeDecode() throws {
        let commands: [RemoteCommand] = [.pause, .resume, .nextStep, .previousStep, .skipRest, .end]

        for command in commands {
            let data = try encoder.encode(command)
            let decoded = try decoder.decode(RemoteCommand.self, from: data)
            XCTAssertEqual(decoded, command)
        }
    }

    func testRemoteCommandRawValues() {
        XCTAssertEqual(RemoteCommand.pause.rawValue, "PAUSE")
        XCTAssertEqual(RemoteCommand.resume.rawValue, "RESUME")
        XCTAssertEqual(RemoteCommand.nextStep.rawValue, "NEXT_STEP")
        XCTAssertEqual(RemoteCommand.previousStep.rawValue, "PREV_STEP")
        XCTAssertEqual(RemoteCommand.skipRest.rawValue, "SKIP_REST")
        XCTAssertEqual(RemoteCommand.end.rawValue, "END")
    }

    func testRemoteCommandFromString() {
        XCTAssertEqual(RemoteCommand(rawValue: "PAUSE"), .pause)
        XCTAssertEqual(RemoteCommand(rawValue: "RESUME"), .resume)
        XCTAssertEqual(RemoteCommand(rawValue: "NEXT_STEP"), .nextStep)
        XCTAssertEqual(RemoteCommand(rawValue: "PREV_STEP"), .previousStep)
        XCTAssertEqual(RemoteCommand(rawValue: "SKIP_REST"), .skipRest)
        XCTAssertEqual(RemoteCommand(rawValue: "END"), .end)
        XCTAssertNil(RemoteCommand(rawValue: "INVALID"))
    }

    // MARK: - WatchConnectivityError Tests

    func testWatchNotReachableError() {
        let error = WatchConnectivityError.watchNotReachable

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("reachable"))
    }

    func testEncodingFailedError() {
        let error = WatchConnectivityError.encodingFailed

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("encode"))
    }

    func testSessionNotAvailableError() {
        let error = WatchConnectivityError.sessionNotAvailable

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("available"))
    }

    // MARK: - JSON Format Compatibility Tests

    func testWorkoutStateFromExternalJSON() throws {
        // Test decoding from JSON format that matches watch communication
        let json = """
        {
            "stateVersion": 10,
            "workoutId": "ext-workout",
            "workoutName": "External Workout",
            "phase": "running",
            "stepIndex": 3,
            "stepCount": 8,
            "stepName": "Push-ups",
            "stepType": "reps",
            "remainingMs": null,
            "roundInfo": "Round 1/2",
            "targetReps": 20
        }
        """

        let state = try decoder.decode(WorkoutState.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(state.stateVersion, 10)
        XCTAssertEqual(state.phase, .running)
        XCTAssertEqual(state.stepType, .reps)
        XCTAssertEqual(state.targetReps, 20)
        XCTAssertNil(state.remainingMs)
    }

    func testCommandAckFromExternalJSON() throws {
        let json = """
        {
            "commandId": "watch-cmd-1",
            "status": "success",
            "errorCode": null
        }
        """

        let ack = try decoder.decode(CommandAck.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(ack.commandId, "watch-cmd-1")
        XCTAssertEqual(ack.status, .success)
        XCTAssertNil(ack.errorCode)
    }

    // MARK: - State Transitions

    func testPhaseTransitionSequence() {
        // Test typical workout phase progression
        let sequence: [WorkoutPhase] = [.idle, .running, .paused, .running, .ended]

        for (index, phase) in sequence.enumerated() {
            let state = WorkoutState(
                stateVersion: index,
                workoutId: "seq-test",
                workoutName: "Sequence Test",
                phase: phase,
                stepIndex: 0,
                stepCount: 1,
                stepName: "Test",
                stepType: .timed,
                remainingMs: nil,
                roundInfo: nil,
                lastCommandAck: nil
            )

            XCTAssertEqual(state.phase, phase)
            XCTAssertEqual(state.stateVersion, index)
        }
    }

    // MARK: - Edge Cases

    func testWorkoutStateWithEmptyStrings() throws {
        let state = WorkoutState(
            stateVersion: 0,
            workoutId: "",
            workoutName: "",
            phase: .idle,
            stepIndex: 0,
            stepCount: 0,
            stepName: "",
            stepType: .timed,
            remainingMs: nil,
            roundInfo: "",
            lastCommandAck: nil
        )

        let data = try encoder.encode(state)
        let decoded = try decoder.decode(WorkoutState.self, from: data)

        XCTAssertEqual(decoded.workoutId, "")
        XCTAssertEqual(decoded.workoutName, "")
        XCTAssertEqual(decoded.stepName, "")
        XCTAssertEqual(decoded.roundInfo, "")
    }

    func testWorkoutStateWithLargeValues() throws {
        let state = WorkoutState(
            stateVersion: Int.max,
            workoutId: String(repeating: "a", count: 1000),
            workoutName: String(repeating: "b", count: 500),
            phase: .running,
            stepIndex: 999,
            stepCount: 1000,
            stepName: "Long Step Name That Goes On And On",
            stepType: .timed,
            remainingMs: 3600000, // 1 hour in ms
            roundInfo: "Round 100/100",
            targetReps: 1000,
            lastCommandAck: nil
        )

        let data = try encoder.encode(state)
        let decoded = try decoder.decode(WorkoutState.self, from: data)

        XCTAssertEqual(decoded.stateVersion, Int.max)
        XCTAssertEqual(decoded.stepIndex, 999)
        XCTAssertEqual(decoded.remainingMs, 3600000)
    }

    // MARK: - StandaloneWorkoutSummary Round-Trip Tests (JSON-pinning)

    func testStandaloneWorkoutSummaryRoundTrip() throws {
        let iso8601Encoder = JSONEncoder()
        iso8601Encoder.dateEncodingStrategy = .iso8601
        let iso8601Decoder = JSONDecoder()
        iso8601Decoder.dateDecodingStrategy = .iso8601

        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = Date(timeIntervalSince1970: 1_700_003_600)
        let summary = StandaloneWorkoutSummary(
            workoutId: "standalone-abc",
            workoutName: "Morning Run",
            startDate: start,
            endDate: end,
            durationSeconds: 3600,
            totalCalories: 420.5,
            averageHeartRate: 145.0,
            completedSteps: 5,
            totalSteps: 6
        )

        let data = try iso8601Encoder.encode(summary)
        let decoded = try iso8601Decoder.decode(StandaloneWorkoutSummary.self, from: data)

        XCTAssertEqual(decoded.workoutId, "standalone-abc")
        XCTAssertEqual(decoded.workoutName, "Morning Run")
        XCTAssertEqual(decoded.startDate.timeIntervalSince1970, start.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(decoded.endDate.timeIntervalSince1970, end.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(decoded.durationSeconds, 3600)
        XCTAssertEqual(decoded.totalCalories, 420.5, accuracy: 0.001)
        XCTAssertEqual(decoded.averageHeartRate, 145.0)
        XCTAssertEqual(decoded.completedSteps, 5)
        XCTAssertEqual(decoded.totalSteps, 6)
    }

    func testStandaloneWorkoutSummaryNilHeartRate() throws {
        let iso8601Encoder = JSONEncoder()
        iso8601Encoder.dateEncodingStrategy = .iso8601
        let iso8601Decoder = JSONDecoder()
        iso8601Decoder.dateDecodingStrategy = .iso8601

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let summary = StandaloneWorkoutSummary(
            workoutId: "w-no-hr",
            workoutName: "Strength",
            startDate: now,
            endDate: now,
            durationSeconds: 1800,
            totalCalories: 200.0,
            averageHeartRate: nil,
            completedSteps: 3,
            totalSteps: 3
        )

        let data = try iso8601Encoder.encode(summary)
        let decoded = try iso8601Decoder.decode(StandaloneWorkoutSummary.self, from: data)

        XCTAssertNil(decoded.averageHeartRate)
        XCTAssertEqual(decoded.completedSteps, 3)
        XCTAssertEqual(decoded.totalSteps, 3)
    }

    /// Pins the exact JSON keys the watch encodes — any rename breaks this test,
    /// making key drift a compile-time-equivalent failure rather than a silent mismatch.
    func testStandaloneWorkoutSummaryJSONKeysArePinned() throws {
        let iso8601Encoder = JSONEncoder()
        iso8601Encoder.dateEncodingStrategy = .iso8601

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let summary = StandaloneWorkoutSummary(
            workoutId: "key-test",
            workoutName: "Key Test",
            startDate: now,
            endDate: now,
            durationSeconds: 60,
            totalCalories: 10.0,
            averageHeartRate: 130.0,
            completedSteps: 1,
            totalSteps: 1
        )

        let data = try iso8601Encoder.encode(summary)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let expectedKeys: Set<String> = [
            "workoutId", "workoutName", "startDate", "endDate",
            "durationSeconds", "totalCalories", "averageHeartRate",
            "completedSteps", "totalSteps"
        ]
        XCTAssertEqual(Set(json.keys), expectedKeys, "JSON key set changed — update watch/phone decoders together")
    }

    /// Legacy compatibility: JSON arriving from an older watch build that omits averageHeartRate
    /// must decode without error (field is optional).
    func testStandaloneWorkoutSummaryLegacyPayloadMissingHeartRate() throws {
        let iso8601Decoder = JSONDecoder()
        iso8601Decoder.dateDecodingStrategy = .iso8601

        let json = """
        {
            "workoutId": "legacy-001",
            "workoutName": "Legacy Workout",
            "startDate": "2023-11-14T22:13:20Z",
            "endDate": "2023-11-14T23:13:20Z",
            "durationSeconds": 3600,
            "totalCalories": 350.0,
            "completedSteps": 4,
            "totalSteps": 5
        }
        """

        let decoded = try iso8601Decoder.decode(StandaloneWorkoutSummary.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(decoded.workoutId, "legacy-001")
        XCTAssertNil(decoded.averageHeartRate)
        XCTAssertEqual(decoded.durationSeconds, 3600)
    }

    // MARK: - Workout Delivery Routing Tests (AMA-297)

    /// Proves that a workout payload sent by the phone's sendWorkout() can be decoded
    /// by the watch-side bridge routing logic via decodeFromReceiveWorkoutMessage.
    func testReceiveWorkoutPayloadDecodesCorrectly() throws {
        let workout = Workout(
            id: "test-297-abc",
            name: "Strength A",
            sport: .strength,
            duration: 2700,
            source: .manual
        )
        let workoutData = try JSONEncoder().encode(workout)
        let workoutDict = try XCTUnwrap(try JSONSerialization.jsonObject(with: workoutData) as? [String: Any])
        let message: [String: Any] = ["action": "receiveWorkout", "workout": workoutDict]

        let decoded = Workout.decodeFromReceiveWorkoutMessage(message)

        XCTAssertNotNil(decoded, "receiveWorkout payload must decode to a Workout")
        XCTAssertEqual(decoded?.id, "test-297-abc")
        XCTAssertEqual(decoded?.name, "Strength A")
        XCTAssertEqual(decoded?.sport, .strength)
    }

    func testReceiveWorkoutPayloadMissingWorkoutKeyReturnsNil() {
        let message: [String: Any] = ["action": "receiveWorkout"]
        XCTAssertNil(Workout.decodeFromReceiveWorkoutMessage(message),
                     "Missing 'workout' key must return nil, not crash")
    }

    func testReceiveWorkoutPayloadMalformedWorkoutReturnsNil() {
        let message: [String: Any] = ["action": "receiveWorkout", "workout": "not-a-dict"]
        XCTAssertNil(Workout.decodeFromReceiveWorkoutMessage(message),
                     "Non-dict 'workout' value must return nil, not crash")
    }

    func testSyncWorkoutsUserInfoDecodesMultipleWorkouts() throws {
        let workouts = [
            Workout(id: "w1", name: "Run", sport: .running, duration: 1800, source: .manual),
            Workout(id: "w2", name: "Lift", sport: .strength, duration: 3600, source: .manual)
        ]
        let workoutsData = try JSONEncoder().encode(workouts)
        let workoutsArray = try XCTUnwrap(try JSONSerialization.jsonObject(with: workoutsData) as? [[String: Any]])
        let userInfo: [String: Any] = ["action": "syncWorkouts", "workouts": workoutsArray]

        let decoded = Workout.decodeFromSyncWorkoutsUserInfo(userInfo)

        XCTAssertEqual(decoded?.count, 2)
        XCTAssertEqual(decoded?[0].id, "w1")
        XCTAssertEqual(decoded?[1].id, "w2")
    }

    func testSyncWorkoutsUserInfoMissingKeyReturnsNil() {
        let userInfo: [String: Any] = ["action": "syncWorkouts"]
        XCTAssertNil(Workout.decodeFromSyncWorkoutsUserInfo(userInfo),
                     "Missing 'workouts' key must return nil, not crash")
    }
}
