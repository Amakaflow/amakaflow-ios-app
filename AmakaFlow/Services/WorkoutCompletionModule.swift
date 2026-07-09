//
//  WorkoutCompletionModule.swift
//  AmakaFlow
//
//  Issue #446: owns the save-lifecycle state machine
//  (idle → inFlight → succeeded | failed) previously split across
//  WorkoutEngine and WorkoutCompletionView.
//

import Combine
import Foundation

// MARK: - Protocol

@MainActor
protocol WorkoutCompletionModuleProviding: AnyObject {
    var saveStatus: WorkoutCompletionModule.SaveStatus { get }
    var lastSaveError: CTAError? { get }
    /// Fires just before any state change — subscribe to propagate UI updates.
    var willChange: AnyPublisher<Void, Never> { get }
    func beginSave()
    func succeedSave()
    func failSave(_ error: CTAError)
    func acknowledgeError()
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
            case (.failed(let a), .failed(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    // MARK: - Published state

    @Published private(set) var saveStatus: SaveStatus = .idle
    @Published private(set) var lastSaveError: CTAError?

    var willChange: AnyPublisher<Void, Never> {
        objectWillChange.map { _ in () }.eraseToAnyPublisher()
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
}
