//
//  WorkoutCompletionModule.swift
//  AmakaFlow
//
//  Issue #446: owns the save-lifecycle state machine
//  (idle → inFlight → succeeded | failed) previously split across
//  WorkoutEngine and WorkoutCompletionView.
//
//  Issue #448: also owns the save round-trip (savePhoneCompletion),
//  removing that logic from WorkoutEngine.
//

import Combine
import Foundation

// MARK: - Protocol

@MainActor
protocol WorkoutCompletionModuleProviding: AnyObject {
    var saveStatus: WorkoutCompletionModule.SaveStatus { get }
    var lastSaveError: CTAError? { get }
    /// Current count of completions waiting for a retry. Published so UI can observe.
    var pendingCount: Int { get }
    /// Fires just before any state change — subscribe to propagate UI updates.
    var willChange: AnyPublisher<Void, Never> { get }
    func beginSave()
    func succeedSave()
    func failSave(_ error: CTAError)
    func acknowledgeError()
    /// Drain the offline retry queue. No-op if network is unavailable or auth is invalid.
    func retryPending() async
    /// Execute the full save round-trip: beginSave → network POST → succeedSave/failSave.
    /// Callers (WorkoutEngine) assemble the payload and hand off; this method owns all
    /// completion semantics including the success:false guard and notification posting.
    func savePhoneCompletion(
        workoutId: String,
        workoutName: String,
        startedAt: Date,
        endedAt: Date,
        durationSeconds: Int,
        avgHeartRate: Int?,
        activeCalories: Int?,
        heartRateSamples: [HRSample]?,
        workoutStructure: [WorkoutInterval]?,
        isSimulated: Bool,
        setLogs: [SetLog]?,
        executionLog: [String: Any]?
    ) async
}

// MARK: - Live implementation

@MainActor
final class WorkoutCompletionModule: ObservableObject, WorkoutCompletionModuleProviding {
    // MARK: - SaveStatus

    enum SaveStatus: Equatable {
        /// No save attempted, or the engine has been reset.
        case idle
        /// Save fired; awaiting the network round-trip.
        case inFlight
        /// Save round-tripped and the backend confirmed success.
        case succeeded
        /// Save round-tripped (or threw locally) and failed.
        case failed(CTAError)

        static func == (lhs: SaveStatus, rhs: SaveStatus) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.inFlight, .inFlight), (.succeeded, .succeeded):
                return true
            case (.failed(let lhsError), .failed(let rhsError)):
                return lhsError == rhsError
            default:
                return false
            }
        }
    }

    // MARK: - Published state

    @Published private(set) var saveStatus: SaveStatus = .idle
    @Published private(set) var lastSaveError: CTAError?

    /// Live count of completions waiting for retry — reads directly from the
    /// queue service so there is no Combine timing gap.
    var pendingCount: Int { queueService.pendingCount }

    /// Fires before any state change in this module OR when the queue service's
    /// pendingCount changes, so SwiftUI observers on WorkoutEngine re-render.
    var willChange: AnyPublisher<Void, Never> {
        Publishers.Merge(
            objectWillChange.map { _ in () },
            queueService.pendingCountPublisher.map { _ in () }
        )
        .eraseToAnyPublisher()
    }

    // MARK: - Dependencies

    private let queueService: WorkoutCompletionQueueProviding
    private let completionService: WorkoutCompletionServiceProviding
    private var cancellables = Set<AnyCancellable>()

    init(
        queueService: WorkoutCompletionQueueProviding = WorkoutCompletionService.shared,
        completionService: WorkoutCompletionServiceProviding = WorkoutCompletionService.shared
    ) {
        self.queueService = queueService
        self.completionService = completionService
    }

    // MARK: - Transitions

    func beginSave() {
        lastSaveError = nil
        saveStatus = .inFlight
    }

    func succeedSave() {
        saveStatus = .succeeded
    }

    func failSave(_ error: CTAError) {
        lastSaveError = error
        saveStatus = .failed(error)
    }

    func acknowledgeError() {
        lastSaveError = nil
        if case .failed = saveStatus {
            saveStatus = .idle
        }
    }

    func retryPending() async {
        await queueService.retryPendingCompletions()
    }

    // MARK: - Save round-trip

    func savePhoneCompletion(
        workoutId: String,
        workoutName: String,
        startedAt: Date,
        endedAt: Date,
        durationSeconds: Int,
        avgHeartRate: Int?,
        activeCalories: Int?,
        heartRateSamples: [HRSample]?,
        workoutStructure: [WorkoutInterval]?,
        isSimulated: Bool,
        setLogs: [SetLog]?,
        executionLog: [String: Any]?
    ) async {
        beginSave()
        do {
            let response = try await completionService.postPhoneWorkoutCompletion(
                workoutId: workoutId,
                workoutName: workoutName,
                startedAt: startedAt,
                endedAt: endedAt,
                durationSeconds: durationSeconds,
                avgHeartRate: avgHeartRate,
                activeCalories: activeCalories,
                heartRateSamples: heartRateSamples,
                workoutStructure: workoutStructure,
                isSimulated: isSimulated,
                setLogs: setLogs,
                executionLog: executionLog
            )
            if response?.success == false {
                throw APIError.serverErrorWithBody(
                    200,
                    "{\"success\":false,\"message\":\"Workout completion failed\",\"error_code\":\"WORKOUT_COMPLETION_FAILED\"}"
                )
            }
            succeedSave()
            NotificationCenter.default.post(
                name: .workoutCompleted,
                object: nil,
                userInfo: ["workoutId": workoutId]
            )
        } catch {
            failSave(CTAError.map(error))
        }
    }
}
