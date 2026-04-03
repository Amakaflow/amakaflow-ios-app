//
//  ProgramManagementViewModel.swift
//  AmakaFlow
//
//  Program management actions: pause, resume, archive, delete, complete workout (AMA-1413)
//

import Foundation
import Combine

@MainActor
class ProgramManagementViewModel: ObservableObject {
    @Published var isWorking: Bool = false
    @Published var errorMessage: String?

    private let apiService = APIService.shared

    /// Updates the program status and returns `true` on success.
    @discardableResult
    func updateStatus(programId: String, status: String) async -> Bool {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await apiService.updateProgramStatus(id: programId, status: status)
            return true
        } catch {
            errorMessage = "Failed to update status: \(error.localizedDescription)"
            return false
        }
    }

    /// Deletes the program and returns `true` on success.
    func deleteProgram(programId: String) async -> Bool {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await apiService.deleteProgram(id: programId)
            return true
        } catch {
            errorMessage = "Failed to delete program: \(error.localizedDescription)"
            return false
        }
    }

    /// Marks a workout complete and returns `true` on success.
    @discardableResult
    func completeWorkout(workoutId: String) async -> Bool {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await apiService.completeWorkout(workoutId: workoutId)
            return true
        } catch {
            errorMessage = "Failed to mark workout complete: \(error.localizedDescription)"
            return false
        }
    }
}
