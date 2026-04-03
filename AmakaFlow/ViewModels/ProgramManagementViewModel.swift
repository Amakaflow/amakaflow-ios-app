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

    func updateStatus(programId: String, status: String) async {
        isWorking = true
        errorMessage = nil
        do {
            try await apiService.updateProgramStatus(id: programId, status: status)
        } catch {
            errorMessage = "Failed to update status: \(error.localizedDescription)"
        }
        isWorking = false
    }

    func deleteProgram(programId: String) async {
        isWorking = true
        errorMessage = nil
        do {
            try await apiService.deleteProgram(id: programId)
        } catch {
            errorMessage = "Failed to delete program: \(error.localizedDescription)"
        }
        isWorking = false
    }

    func completeWorkout(workoutId: String) async {
        isWorking = true
        errorMessage = nil
        do {
            try await apiService.completeWorkout(workoutId: workoutId)
        } catch {
            errorMessage = "Failed to mark workout complete: \(error.localizedDescription)"
        }
        isWorking = false
    }
}
