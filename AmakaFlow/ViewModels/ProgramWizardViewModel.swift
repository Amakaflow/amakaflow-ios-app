//
//  ProgramWizardViewModel.swift
//  AmakaFlow
//
//  Wizard state management and program generation (AMA-1413 / AMA-2096)
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

    // MARK: - Generation / Save State
    @Published var isGenerating: Bool = false
    @Published var isSaving: Bool = false
    @Published var generationProgress: Int = 0
    @Published var stageMessage: String?
    @Published var generatedProgramId: String?
    @Published var designPreviewId: String?
    @Published var generatePreviewId: String?
    @Published var proposedProgram: ProposedProgram?
    @Published var scheduledCount: Int = 0
    @Published var errorMessage: String?
    @Published var isErrorRecoverable: Bool = false

    private let dependencies: AppDependencies
    // nonisolated(unsafe): accessed in deinit, which can run off MainActor (Swift-6 actor-deinit crash class, #306).
    nonisolated(unsafe) private var streamTask: Task<Void, Never>?

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
    static let preferredDayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    static let timeOptions = [30, 45, 60, 90]

    init(dependencies: AppDependencies = .current) {
        self.dependencies = dependencies
    }

    deinit {
        streamTask?.cancel()
    }

    // MARK: - Navigation

    var canAdvance: Bool {
        switch currentStep {
        case .goal: return goal != nil
        case .experience: return experienceLevel != nil
        case .schedule: return !preferredDays.isEmpty
        case .equipment: return equipmentPreset != nil || !customEquipment.isEmpty
        case .preferences: return true
        case .review: return !isGenerating && !isSaving
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
            return Array(customEquipment).sorted()
        }
        if let preset = equipmentPreset,
           let match = Self.equipmentPresets.first(where: { $0.id == preset }) {
            return match.items
        }
        return []
    }

    // MARK: - Requests

    func makeDesignProgramRequest() throws -> DesignProgramRequest {
        let equipment = resolvedEquipment
        guard !equipment.isEmpty else {
            throw ProgramWizardValidationError.missingEquipment
        }

        return DesignProgramRequest(
            goal: goal ?? "general_fitness",
            experienceLevel: experienceLevel ?? "intermediate",
            durationWeeks: min(16, max(2, Int(durationWeeks.rounded()))),
            sessionsPerWeek: min(7, max(1, Int(sessionsPerWeek.rounded()))),
            equipment: equipment,
            timePerSession: timePerSession,
            preferredDays: preferredDays.sorted().compactMap { day in
                guard day >= 0, day < Self.preferredDayNames.count else { return nil }
                return Self.preferredDayNames[day]
            },
            injuries: injuries.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            focusAreas: focusAreas.isEmpty ? nil : Array(focusAreas).sorted(),
            avoidExercises: avoidExercises.isEmpty ? nil : avoidExercises
        )
    }

    // MARK: - Generation

    func generateProgram() async {
        streamTask?.cancel()
        let task = Task { @MainActor in
            await self.runGenerateProgram()
        }
        streamTask = task
        await task.value
        streamTask = nil
    }

    private func runGenerateProgram() async {
        isGenerating = true
        isSaving = false
        generationProgress = 0
        stageMessage = "Starting program design..."
        errorMessage = nil
        isErrorRecoverable = false
        generatedProgramId = nil
        designPreviewId = nil
        generatePreviewId = nil
        proposedProgram = nil
        scheduledCount = 0

        guard let token = dependencies.pairingService.getToken() else {
            fail("Not authenticated. Please sign in and try again.", recoverable: true)
            isGenerating = false
            return
        }

        do {
            let request = try makeDesignProgramRequest()
            var outlinePreviewId: String?

            for try await event in dependencies.programStreamService.designProgram(request: request, token: token) {
                try handleDesignEvent(event, previewId: &outlinePreviewId)
            }

            guard !Task.isCancelled else {
                isGenerating = false
                return
            }

            guard let outlinePreviewId else {
                throw ProgramStreamError.missingPreviewId(phase: "design")
            }
            designPreviewId = outlinePreviewId
            generationProgress = max(generationProgress, 33)

            var fullPreviewId: String?
            var generatedProgram: ProposedProgram?

            for try await event in dependencies.programStreamService.generateProgram(previewId: outlinePreviewId, token: token) {
                try handleGenerateEvent(event, previewId: &fullPreviewId, program: &generatedProgram)
            }

            guard !Task.isCancelled else {
                isGenerating = false
                return
            }

            guard let fullPreviewId else {
                throw ProgramStreamError.missingPreviewId(phase: "generate")
            }
            guard let generatedProgram else {
                throw ProgramStreamError.missingProgramPreview
            }

            generatePreviewId = fullPreviewId
            proposedProgram = generatedProgram
            generationProgress = 100
            stageMessage = "Program ready for review."
            currentStep = .review
            isGenerating = false
        } catch {
            if Task.isCancelled {
                isGenerating = false
                return
            }
            fail(error.localizedDescription, recoverable: (error as? ProgramStreamError)?.isRecoverable ?? true)
            isGenerating = false
        }
    }

    func saveProgram(startDate: Date) async {
        streamTask?.cancel()
        let task = Task { @MainActor in
            await self.runSaveProgram(startDate: startDate)
        }
        streamTask = task
        await task.value
        streamTask = nil
    }

    private func runSaveProgram(startDate: Date) async {
        guard let previewId = generatePreviewId else {
            fail("Generate a program before saving.", recoverable: true)
            return
        }
        guard let token = dependencies.pairingService.getToken() else {
            fail("Not authenticated. Please sign in and try again.", recoverable: true)
            return
        }

        isSaving = true
        errorMessage = nil
        isErrorRecoverable = false
        generationProgress = max(generationProgress, 80)
        stageMessage = "Saving program..."

        do {
            var completedWorkoutIds: [String] = []
            var completedScheduledCount = 0
            let dateString = Self.apiDateString(from: startDate)

            for try await event in dependencies.programStreamService.saveProgram(previewId: previewId, scheduleStartDate: dateString, token: token) {
                try handleSaveEvent(event, workoutIds: &completedWorkoutIds, scheduledCount: &completedScheduledCount)
            }

            guard !Task.isCancelled else {
                isSaving = false
                return
            }

            guard let savedProgramId = proposedProgram?.id ?? completedWorkoutIds.first else {
                throw ProgramStreamError.streamError(message: "Program saved without returned workout IDs.", recoverable: true)
            }

            generatedProgramId = savedProgramId
            scheduledCount = completedScheduledCount
            generationProgress = 100
            stageMessage = "Program saved!"
            isSaving = false
        } catch {
            if Task.isCancelled {
                isSaving = false
                return
            }
            fail(error.localizedDescription, recoverable: (error as? ProgramStreamError)?.isRecoverable ?? true)
            isSaving = false
        }
    }

    func cancelGeneration() {
        streamTask?.cancel()
        streamTask = nil
        isGenerating = false
        isSaving = false
        stageMessage = nil
    }

    // MARK: - Event Handling

    private func handleDesignEvent(_ event: ProgramStreamEvent, previewId: inout String?) throws {
        switch event {
        case .stage(let stage, let message, _):
            stageMessage = message
            generationProgress = stage == "complete" ? 33 : max(generationProgress, 15)
        case .preview(let id, _):
            previewId = id
            generationProgress = max(generationProgress, 33)
        case .error(let message, let recoverable):
            throw ProgramStreamError.streamError(message: message, recoverable: recoverable)
        case .complete:
            break
        }
    }

    private func handleGenerateEvent(_ event: ProgramStreamEvent, previewId: inout String?, program: inout ProposedProgram?) throws {
        switch event {
        case .stage(let stage, let message, let subProgress):
            stageMessage = message
            switch stage {
            case "generating":
                if let subProgress, subProgress.total > 0 {
                    let fraction = Double(subProgress.current) / Double(subProgress.total)
                    generationProgress = max(generationProgress, 33 + Int((fraction * 50).rounded()))
                } else {
                    generationProgress = max(generationProgress, 45)
                }
            case "mapping":
                generationProgress = max(generationProgress, 90)
            case "complete":
                generationProgress = max(generationProgress, 100)
            default:
                generationProgress = max(generationProgress, 40)
            }
        case .preview(let id, let payload):
            previewId = id
            program = payload.program
            generationProgress = 100
        case .error(let message, let recoverable):
            throw ProgramStreamError.streamError(message: message, recoverable: recoverable)
        case .complete:
            break
        }
    }

    private func handleSaveEvent(_ event: ProgramStreamEvent, workoutIds: inout [String], scheduledCount: inout Int) throws {
        switch event {
        case .stage(let stage, let message, _):
            stageMessage = message
            switch stage {
            case "saving": generationProgress = max(generationProgress, 85)
            case "scheduling": generationProgress = max(generationProgress, 92)
            case "pushing": generationProgress = max(generationProgress, 96)
            case "complete": generationProgress = 100
            default: break
            }
        case .complete(let ids, let count, _):
            workoutIds = ids
            scheduledCount = count
        case .error(let message, let recoverable):
            throw ProgramStreamError.streamError(message: message, recoverable: recoverable)
        case .preview:
            break
        }
    }

    private func fail(_ message: String, recoverable: Bool) {
        errorMessage = message
        isErrorRecoverable = recoverable
        stageMessage = nil
    }

    private static func apiDateString(from date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return ""
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}

enum ProgramWizardValidationError: LocalizedError, Equatable {
    case missingEquipment

    var errorDescription: String? {
        switch self {
        case .missingEquipment:
            return "Choose at least one piece of equipment before generating your program."
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
