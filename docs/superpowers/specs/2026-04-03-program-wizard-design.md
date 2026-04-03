# AMA-1413: Programs — Creation Wizard + Management

**Ticket:** AMA-1413
**Date:** 2026-04-03

## Summary

Add AI-powered program creation wizard (6-step form), async generation with polling, program management (pause/archive/delete, mark workouts complete), and integrate programs into the More tab navigation.

## Wizard Steps

1. **Goal** — Select: strength, hypertrophy, fat_loss, endurance, general_fitness
2. **Experience** — Select: beginner, intermediate, advanced
3. **Schedule** — Duration (4-52 weeks), sessions/week (1-7), preferred days, time per session (30/45/60/90 min)
4. **Equipment** — Preset (full_gym, home_advanced, home_basic, bodyweight) or custom multi-select from 14 items
5. **Preferences** — Injuries (text), focus areas (10 muscle groups), exercises to avoid (tags)
6. **Review** — Summary of all selections, "Generate Program" button, async polling with progress

## API Endpoints

All on mapper-api (`mapperAPIURL`):

| Method | Endpoint | Purpose |
|--------|----------|---------|
| POST | `/programs/generate` | Start async generation job |
| GET | `/programs/generate/{jobId}/status` | Poll generation progress |
| PATCH | `/training-programs/{id}/status` | Update status (active/paused/archived) |
| PATCH | `/training-programs/{id}/progress` | Update current week |
| DELETE | `/training-programs/{id}` | Delete program |
| PATCH | `/training-programs/workouts/{id}/complete` | Mark workout complete |

Existing (already implemented):
| GET | `/programs?status={status}` | List programs |
| GET | `/programs/{id}` | Program detail |

## New Models

```swift
struct ProgramGenerationRequest: Codable {
    let goal: String
    let experienceLevel: String
    let durationWeeks: Int
    let sessionsPerWeek: Int
    let preferredDays: [Int]
    let timePerSession: Int
    let equipment: [String]
    let injuries: String?
    let focusAreas: [String]?
    let avoidExercises: [String]?
}

struct ProgramGenerationResponse: Codable {
    let jobId: String
    let status: String
    let programId: String?
    let error: String?
}

struct ProgramGenerationStatus: Codable {
    let jobId: String
    let status: String  // pending, processing, completed, failed
    let progress: Int   // 0-100
    let programId: String?
    let error: String?
}
```

## Wizard State

```swift
class ProgramWizardViewModel: ObservableObject {
    enum Step: Int, CaseIterable { case goal, experience, schedule, equipment, preferences, review }
    
    @Published var currentStep: Step = .goal
    @Published var goal: String?
    @Published var experienceLevel: String?
    @Published var durationWeeks: Int = 8
    @Published var sessionsPerWeek: Int = 3
    @Published var preferredDays: Set<Int> = [1, 3, 5]  // Mon, Wed, Fri
    @Published var timePerSession: Int = 60
    @Published var equipmentPreset: String?
    @Published var customEquipment: Set<String> = []
    @Published var injuries: String = ""
    @Published var focusAreas: Set<String> = []
    @Published var avoidExercises: [String] = []
    @Published var isGenerating: Bool = false
    @Published var generationProgress: Int = 0
    @Published var generatedProgramId: String?
    @Published var errorMessage: String?
}
```

## Files

| File | Action |
|------|--------|
| `Models/ProgramGenerationModels.swift` | Create — request/response types |
| `ViewModels/ProgramWizardViewModel.swift` | Create — wizard state + generation + polling |
| `Views/Programs/ProgramWizardView.swift` | Create — main wizard container with step navigation |
| `Views/Programs/GoalStepView.swift` | Create — goal selection |
| `Views/Programs/ExperienceStepView.swift` | Create — experience level |
| `Views/Programs/ScheduleStepView.swift` | Create — duration, frequency, days, time |
| `Views/Programs/EquipmentStepView.swift` | Create — presets + custom |
| `Views/Programs/PreferencesStepView.swift` | Create — injuries, focus, avoid |
| `Views/Programs/ReviewStepView.swift` | Create — summary + generate button + progress |
| `DependencyInjection/APIServiceProviding.swift` | Modify — +6 program methods |
| `Services/APIService.swift` | Modify — +6 implementations |
| `DependencyInjection/AppDependencies.swift` | Modify — +6 mocks |
| `DependencyInjection/FixtureAPIService.swift` | Modify — +6 fixtures |
| `Views/ProgramDetailView.swift` | Modify — add management actions (pause/archive/delete) |
| `Views/ProgramsListView.swift` | Modify — add "Create Program" button |
| `Views/MoreView.swift` | Modify — add Programs navigation link |
| `Tests/ProgramWizardViewModelTests.swift` | Create — wizard state + generation tests |
