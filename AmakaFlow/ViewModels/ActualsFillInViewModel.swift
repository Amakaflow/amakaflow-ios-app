//
//  ActualsFillInViewModel.swift
//  AmakaFlow
//
//  AMA-2387: fill-in actuals — gated save, RPE required, local-first write.
//

import Combine
import Foundation

@MainActor
final class ActualsFillInViewModel: ObservableObject {
    @Published private(set) var session: ActualsFillInSession
    @Published private(set) var lastSaveError: String?
    /// Survives view recreation so the verified payoff can present after save.
    @Published var showVerifiedPayoff = false

    private let repository: ActualsRepository

    init(session: ActualsFillInSession, repository: ActualsRepository) {
        self.session = session
        self.repository = repository
    }

    /// Avoid MainActor-isolated deinit + TaskLocal teardown crash under XCTest (Swift 6).
    nonisolated deinit {}

    var confirmedCount: Int { session.confirmedCount }
    var unconfirmedCount: Int { session.unconfirmedCount }
    var rpe: Int? { session.rpe }
    var verified: Bool { session.verified }

    /// All rows confirmed and RPE chosen — only then may we set `verified`.
    var canSave: Bool {
        guard unconfirmedCount == 0, !session.exercises.isEmpty, let rpe = session.rpe else {
            return false
        }
        return (1...10).contains(rpe)
    }

    var saveCTATitle: String {
        if unconfirmedCount > 0 {
            return "Confirm \(unconfirmedCount) more to save"
        }
        if let rpe = session.rpe {
            if (1...10).contains(rpe) {
                return "Save session · RPE \(rpe)"
            }
            return "Pick RPE to save"
        }
        return "Pick RPE to save"
    }

    var progressLine: String {
        "\(session.subtitle) · \(confirmedCount) OF \(session.exercises.count) CONFIRMED"
    }

    // MARK: - Mutations

    func markAsPlanned(exerciseID: String) {
        guard let index = session.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        session.exercises[index].confirmation = .asPlanned
        session.exercises[index].actualSets = session.exercises[index].planned.sets
        session.exercises[index].actualReps = session.exercises[index].planned.reps
        session.exercises[index].actualWeightKg = session.exercises[index].planned.weightKg
    }

    func markAdjust(exerciseID: String) {
        guard let index = session.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        session.exercises[index].confirmation = .adjusted
    }

    func markAllAsPlanned() {
        for exercise in session.exercises {
            markAsPlanned(exerciseID: exercise.id)
        }
    }

    func setActualSets(exerciseID: String, sets: Int) {
        guard let index = session.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        session.exercises[index].actualSets = max(0, sets)
        session.exercises[index].confirmation = .adjusted
    }

    func setActualReps(exerciseID: String, reps: Int) {
        guard let index = session.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        session.exercises[index].actualReps = max(0, reps)
        session.exercises[index].confirmation = .adjusted
    }

    func setActualWeightKg(exerciseID: String, kilograms: Double) {
        guard let index = session.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        session.exercises[index].actualWeightKg = max(0, kilograms)
        session.exercises[index].confirmation = .adjusted
    }

    func selectRPE(_ value: Int) {
        guard (1...10).contains(value) else { return }
        session.rpe = value
    }

    /// Local-first save. Sets `verified` only when all rows + RPE are present.
    @discardableResult
    func save() throws -> Bool {
        lastSaveError = nil
        guard canSave else {
            if unconfirmedCount > 0 {
                lastSaveError = "\(unconfirmedCount) exercises unconfirmed"
            } else if let rpe = session.rpe, !(1...10).contains(rpe) {
                lastSaveError = "RPE must be between 1 and 10"
            } else {
                lastSaveError = "RPE required"
            }
            return false
        }
        do {
            session.verified = true
            try repository.saveVerifiedSession(session)
            return true
        } catch {
            session.verified = false
            showVerifiedPayoff = false
            lastSaveError = error.localizedDescription
            throw error
        }
    }

    /// AMA-2396: toast Undo — back to "Fill in", RPE cleared, draft kept.
    func unverify() {
        session.verified = false
        session.rpe = nil
        showVerifiedPayoff = false
        try? repository.unverifySession(id: session.id)
    }
}
