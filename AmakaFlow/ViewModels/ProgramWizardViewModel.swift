//
//  ProgramWizardViewModel.swift
//  AmakaFlow
//
//  Wizard state management and program generation (AMA-1413)
//

import Foundation
import Combine

@MainActor
class ProgramWizardViewModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case goal, experience, schedule, equipment, preferences, review

        var title: String {
            switch self {
            case .goal: return "Goal"
            case .experience: return "Experience"
            case .schedule: return "Schedule"
            case .equipment: return "Equipment"
            case .preferences: return "Preferences"
            case .review: return "Review"
            }
        }
    }

    // MARK: - Wizard State
    @Published var currentStep: Step = .goal
    @Published var goal: String?
    @Published var experienceLevel: String?
    @Published var durationWeeks: Double = 8
    @Published var sessionsPerWeek: Double = 3
    @Published var preferredDays: Set<Int> = [1, 3, 5]
    @Published var timePerSession: Int = 60
    @Published var equipmentPreset: String?
    @Published var useCustomEquipment: Bool = false
    @Published var customEquipment: Set<String> = []
    @Published var injuries: String = ""
    @Published var focusAreas: Set<String> = []
    @Published var avoidExercises: [String] = []

    // MARK: - Generation State
    @Published var isGenerating: Bool = false
    @Published var generationProgress: Int = 0
    @Published var generatedProgramId: String?
    @Published var errorMessage: String?

    private let dependencies: AppDependencies
    private var pollingTask: Task<Void, Never>?

    static let availableEquipment = [
        "barbell", "dumbbells", "kettlebells", "cable machine", "leg press",
        "lat pulldown", "bench", "squat rack", "pull-up bar", "machines",
        "resistance bands", "trx", "medicine ball", "foam roller"
    ]

    static let equipmentPresets: [(id: String, name: String, items: [String])] = [
        ("full_gym", "Full Gym", ["barbell", "dumbbells", "cable machine", "leg press", "lat pulldown", "bench", "squat rack", "pull-up bar", "machines"]),
        ("home_advanced", "Home Advanced", ["barbell", "dumbbells", "bench", "squat rack", "pull-up bar", "resistance bands"]),
        ("home_basic", "Home Basic", ["dumbbells", "resistance bands", "pull-up bar", "bench"]),
        ("bodyweight", "Bodyweight", ["pull-up bar", "resistance bands"])
    ]

    static let muscleGroups = ["chest", "back", "shoulders", "biceps", "triceps", "core", "glutes", "quads", "hamstrings", "calves"]

    static let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    static let timeOptions = [30, 45, 60, 90]

    init(dependencies: AppDependencies = .live) {
        self.dependencies = dependencies
    }

    // MARK: - Navigation

    var canAdvance: Bool {
        switch currentStep {
        case .goal: return goal != nil
        case .experience: return experienceLevel != nil
        case .schedule: return !preferredDays.isEmpty
        case .equipment: return equipmentPreset != nil || !customEquipment.isEmpty
        case .preferences: return true
        case .review: return !isGenerating
        }
    }

    func nextStep() {
        guard let next = Step(rawValue: currentStep.rawValue + 1) else { return }
        currentStep = next
    }

    func previousStep() {
        guard let prev = Step(rawValue: currentStep.rawValue - 1) else { return }
        currentStep = prev
    }

    func goToStep(_ step: Step) {
        currentStep = step
    }

    // MARK: - Equipment Resolution

    var resolvedEquipment: [String] {
        if useCustomEquipment {
            return Array(customEquipment)
        }
        if let preset = equipmentPreset,
           let match = Self.equipmentPresets.first(where: { $0.id == preset }) {
            return match.items
        }
        return []
    }

    // MARK: - Generation

    func generateProgram() async {
        isGenerating = true
        generationProgress = 0
        errorMessage = nil
        generatedProgramId = nil

        let request = ProgramGenerationRequest(
            goal: goal ?? "general_fitness",
            experienceLevel: experienceLevel ?? "intermediate",
            durationWeeks: Int(durationWeeks),
            sessionsPerWeek: Int(sessionsPerWeek),
            preferredDays: Array(preferredDays).sorted(),
            timePerSession: timePerSession,
            equipment: resolvedEquipment,
            injuries: injuries.isEmpty ? nil : injuries,
            focusAreas: focusAreas.isEmpty ? nil : Array(focusAreas),
            avoidExercises: avoidExercises.isEmpty ? nil : avoidExercises
        )

        do {
            let response = try await dependencies.apiService.generateProgram(request: request)
            // Store polling task so it can be cancelled via cancelGeneration()
            pollingTask = Task { await pollGeneration(jobId: response.jobId) }
            await pollingTask?.value
        } catch {
            errorMessage = "Failed to start generation: \(error.localizedDescription)"
            isGenerating = false
        }
    }

    private func pollGeneration(jobId: String) async {
        while !Task.isCancelled {
            do {
                let status = try await dependencies.apiService.fetchGenerationStatus(jobId: jobId)
                generationProgress = status.progress

                switch status.status {
                case "completed":
                    generatedProgramId = status.programId
                    isGenerating = false
                    return
                case "failed":
                    errorMessage = status.error ?? "Generation failed"
                    isGenerating = false
                    return
                default:
                    try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                }
            } catch {
                errorMessage = "Lost connection during generation"
                isGenerating = false
                return
            }
        }
    }

    func cancelGeneration() {
        pollingTask?.cancel()
        pollingTask = nil
        isGenerating = false
    }
}
