//
//  DayStateViewModel.swift
//  AmakaFlowWatch Watch App
//
//  ViewModel for DayState features — coordinates watch-to-phone communication (AMA-1150)
//

import Combine
import Foundation
import WatchKit

@MainActor
final class DayStateViewModel: ObservableObject {
    // MARK: - Published State

    @Published private(set) var dayState: DayState?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    @Published private(set) var coachResponse: CoachResponse?
    @Published private(set) var isCoachLoading = false
    @Published private(set) var coachError: String?

    @Published private(set) var activeConflict: ConflictAlert?

    // Phone connectivity
    var isPhoneReachable: Bool {
        bridge.isPhoneReachable
    }

    private let bridge: WatchConnectivityBridge

    // MARK: - Init

    init(bridge: WatchConnectivityBridge = .shared) {
        self.bridge = bridge
    }

    // MARK: - DayState Request

    func requestDayState() {
        guard bridge.isConnected else {
            errorMessage = "iPhone not connected"
            return
        }

        isLoading = true
        errorMessage = nil

        bridge.sendDayStateRequest { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }
                self.isLoading = false

                switch result {
                case .success(let dayState):
                    self.dayState = dayState
                    self.errorMessage = nil
                    // Check for conflict alert
                    if let conflict = dayState.conflictAlert {
                        self.activeConflict = conflict
                    }
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Coach Q&A

    func askCoach(_ question: QuickCoachQuestion) {
        guard bridge.isConnected else {
            coachError = "iPhone not connected"
            return
        }

        isCoachLoading = true
        coachError = nil
        coachResponse = nil

        bridge.sendCoachRequest(question: question.rawValue) { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }
                self.isCoachLoading = false

                switch result {
                case .success(let response):
                    self.coachResponse = response
                    self.coachError = nil
                    WKInterfaceDevice.current().play(.success)
                case .failure(let error):
                    self.coachError = error.localizedDescription
                    WKInterfaceDevice.current().play(.failure)
                }
            }
        }
    }

    func clearCoachResponse() {
        coachResponse = nil
        coachError = nil
    }

    // MARK: - Conflict Actions

    func handleConflictAdjust() {
        guard let conflict = activeConflict else { return }
        bridge.sendConflictAction(action: "adjust", message: conflict.message)
        activeConflict = nil
        WKInterfaceDevice.current().play(.success)
        // Refresh day state after adjustment
        requestDayState()
    }

    func handleConflictKeep() {
        guard let conflict = activeConflict else { return }
        bridge.sendConflictAction(action: "keep", message: conflict.message)
        activeConflict = nil
        WKInterfaceDevice.current().play(.click)
    }

    func dismissConflict() {
        activeConflict = nil
    }

    // MARK: - Update from Bridge

    /// Called by the bridge when a dayState push arrives from the phone
    func handleDayStateUpdate(_ dayState: DayState) {
        self.dayState = dayState
        self.isLoading = false
        self.errorMessage = nil

        if let conflict = dayState.conflictAlert {
            self.activeConflict = conflict
            WKInterfaceDevice.current().play(.notification)
        }
    }

    /// Called by the bridge when a coach response arrives
    func handleCoachResponse(_ response: CoachResponse) {
        self.coachResponse = response
        self.isCoachLoading = false
        self.coachError = nil
    }
}
