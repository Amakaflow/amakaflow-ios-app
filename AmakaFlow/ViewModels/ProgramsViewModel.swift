//
//  ProgramsViewModel.swift
//  AmakaFlow
//
//  ViewModel for Training Programs list and detail (AMA-1231)
//

import Foundation
import Combine

@MainActor
class ProgramsViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var programs: [TrainingProgram] = []
    @Published var selectedProgram: TrainingProgram?
    @Published var isLoading = false
    @Published var isLoadingDetail = false
    @Published var errorMessage: String?

    private let apiService = APIService.shared

    // MARK: - Load Programs

    func loadPrograms() async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await apiService.fetchPrograms(status: "active")
            programs = response.programs
        } catch let error as APIError {
            if error.errorDescription != APIError.unauthorized.errorDescription {
                errorMessage = error.localizedDescription
                print("[ProgramsViewModel] Failed to load programs: \(error)")
            }
        } catch {
            errorMessage = error.localizedDescription
            print("[ProgramsViewModel] Unexpected error: \(error)")
        }

        isLoading = false
    }

    // MARK: - Load Program Detail

    func loadProgramDetail(id: String) async {
        isLoadingDetail = true
        errorMessage = nil

        do {
            selectedProgram = try await apiService.fetchProgramDetail(id: id)
        } catch let error as APIError {
            if error.errorDescription != APIError.unauthorized.errorDescription {
                errorMessage = error.localizedDescription
                print("[ProgramsViewModel] Failed to load program detail: \(error)")
            }
        } catch {
            errorMessage = error.localizedDescription
            print("[ProgramsViewModel] Unexpected error: \(error)")
        }

        isLoadingDetail = false
    }
}
