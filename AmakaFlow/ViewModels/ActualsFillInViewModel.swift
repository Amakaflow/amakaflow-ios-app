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

    var confirmedCount: Int { session.confirmedCount }
    var unconfirmedCount: Int { session.unconfirmedCount }
    var rpe: Int? { session.rpe }
    var verified: Bool { session.verified }

    /// All rows confirmed and RPE chosen — only then may we set `verified`.
    var canSave: Bool {
        unconfirmedCount == 0 && session.rpe != nil && !session.exercises.isEmpty
    }

    var saveCTATitle: String {
        if unconfirmedCount > 0 {
            return "Confirm \(unconfirmedCount) more to save"
        }
        if let rpe = session.rpe {
            return "Save session · RPE \(rpe)"
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

    func setActualWeightKg(exerciseID: String, kg: Double) {
        guard let index = session.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        session.exercises[index].actualWeightKg = max(0, kg)
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
            lastSaveError = unconfirmedCount > 0
                ? "\(unconfirmedCount) exercises unconfirmed"
                : "RPE required"
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
}
