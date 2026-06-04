//
//  RPEFeedbackViewModel.swift
//  AmakaFlow
//
//  ViewModel for post-workout RPE feedback (AMA-1266)
//  Calls POST /coach/rpe-feedback on chat-api
//

import Foundation
import Combine

/// RPE difficulty option for quick selection
enum RPEOption: CaseIterable, Identifiable {
    case easy       // RPE 3-4
    case moderate   // RPE 5-6
    case hard       // RPE 7-8
    case crushed    // RPE 9-10

    var id: String { label }

    var emoji: String {
        switch self {
        case .easy: return "\u{1F60A}"
        case .moderate: return "\u{1F4AA}"
        case .hard: return "\u{1F525}"
        case .crushed: return "\u{1F480}"
        }
    }

    var label: String {
        switch self {
        case .easy: return "Easy"
        case .moderate: return "Moderate"
        case .hard: return "Hard"
        case .crushed: return "Crushed"
        }
    }

    var rpeValue: Int {
        switch self {
        case .easy: return 4
        case .moderate: return 6
        case .hard: return 8
        case .crushed: return 10
        }
    }
}

/// Muscle group for soreness reporting
enum MuscleGroup: String, CaseIterable, Identifiable {
    case chest
    case back
    case legs
    case shoulders
    case arms
    case core

    var id: String { rawValue }

    var displayName: String { rawValue.capitalized }
}

/// Request body for RPE feedback API.
/// AMA-2086: generated BFF schema so iOS can only send fields accepted by
/// POST /v1/coach/rpe-feedback after mobile-bff request validation deploys.
typealias RPEFeedbackRequest = Components.Schemas.RPEFeedbackRequest

extension Components.Schemas.RPEFeedbackRequest {
    init(workoutId: String, rpe: Int, muscleSoreness: [String]?, notes: String?) {
        self.init(muscleSoreness: muscleSoreness, notes: notes, rpe: rpe, workoutId: workoutId)
    }
}

/// Response from RPE feedback API.
/// Kept as a UI-facing projection because the typed BFF nests deload advice
/// under `advice.deload_recommended` while the existing sheet only needs this
/// convenience flag.
struct RPEFeedbackResponse: Codable {
    let success: Bool
    let message: String
    let deloadRecommended: Bool?

    init(success: Bool, message: String, deloadRecommended: Bool?) {
        self.success = success
        self.message = message
        self.deloadRecommended = deloadRecommended
    }

    init(_ generated: Components.Schemas.RPEFeedbackResponse) {
        self.success = generated.success ?? true
        self.message = generated.message ?? "Feedback recorded"
        self.deloadRecommended = generated.advice?.deloadRecommended
    }

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case deloadRecommended = "deload_recommended"
    }
}

@MainActor
class RPEFeedbackViewModel: ObservableObject {
    // MARK: - State

    @Published var selectedOption: RPEOption?
    @Published var selectedRPE: Int?
    @Published var injuryNotes: String = ""
    @Published var selectedMuscles: Set<MuscleGroup> = []
    @Published var isSubmitting = false
    @Published var isSubmitted = false
    @Published var deloadRecommended = false
    @Published var errorMessage: String?

    // MARK: - Config

    let workoutId: String?
    var onComplete: (() -> Void)?

    // MARK: - Dependencies

    private let dependencies: AppDependencies

    // MARK: - Init

    init(workoutId: String?, onComplete: (() -> Void)? = nil, dependencies: AppDependencies = .live) {
        self.workoutId = workoutId
        self.onComplete = onComplete
        self.dependencies = dependencies
    }

    // MARK: - Actions

    func selectOption(_ option: RPEOption) {
        selectedOption = option
        selectedRPE = option.rpeValue
    }

    func toggleMuscle(_ muscle: MuscleGroup) {
        if selectedMuscles.contains(muscle) {
            selectedMuscles.remove(muscle)
        } else {
            selectedMuscles.insert(muscle)
        }
    }

    func submit() async {
        let rpe = selectedRPE ?? selectedOption?.rpeValue
        guard let rpe else { return }

        isSubmitting = true
        errorMessage = nil

        let trimmedNotes = injuryNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = RPEFeedbackRequest(
            workoutId: workoutId ?? "unknown",
            rpe: rpe,
            muscleSoreness: selectedMuscles.isEmpty ? nil : selectedMuscles.map { $0.rawValue },
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes
        )

        do {
            let response = try await dependencies.apiService.postRPEFeedback(request)
            deloadRecommended = response.deloadRecommended ?? false
            isSubmitted = true

            // Auto-dismiss after brief pause
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            onComplete?()
        } catch {
            print("[RPEFeedbackViewModel] submit failed: \(error)")
            errorMessage = "Could not save feedback"
            // Still allow dismissal on error
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            onComplete?()
        }

        isSubmitting = false
    }

    func skip() {
        onComplete?()
    }

}
