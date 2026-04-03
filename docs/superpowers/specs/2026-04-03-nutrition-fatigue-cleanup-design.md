# AMA-1412 Part C: Nutrition/Fatigue Cleanup — API Migration, Fatigue History & Settings

**Ticket:** AMA-1412
**Date:** 2026-04-03
**Status:** Design approved, ready for implementation planning

## Summary

Centralize all direct URLSession calls into APIService, extract response models to dedicated files, add a fatigue history view, and add fatigue settings. This brings the nutrition and fatigue features in line with the codebase's established DI and API patterns.

## Goals

1. Migrate 7 direct API calls from ViewModels/Services to APIService
2. Extract nutrition response models to a dedicated NutritionModels.swift
3. Add fatigue history view showing readiness over time
4. Add fatigue settings view for tracking preferences

## Non-Goals

- KnowledgeService migration (separate follow-up)
- New nutrition API endpoints (what exists stays)
- HealthKit changes
- Offline support for food logging

## Part 1: API Migration

### Endpoints to Migrate

All endpoints use `AppEnvironment.current.chatAPIURL` as base URL with Bearer token auth.

| Source | Method | HTTP | Endpoint | Request | Response |
|--------|--------|------|----------|---------|----------|
| FoodLoggingViewModel | postAnalyzePhoto | POST | `/nutrition/analyze-photo` | `{"image_base64": String}` | AnalyzePhotoAPIResponse |
| FoodLoggingViewModel | getBarcode | GET | `/nutrition/barcode/{code}` | — | BarcodeNutritionAPIResponse |
| FoodLoggingViewModel | postParseText | POST | `/nutrition/parse-text` | `{"text": String}` | ParseTextAPIResponse |
| FuelingViewModel | getFuelingStatus | GET | `/nutrition/fueling-status` | — | FuelingStatusResponse |
| ProteinNudgeService | checkProteinNudge | POST | `/nutrition/protein-nudge/check` | — | ProteinNudgeResponse |
| SuggestWorkoutViewModel | suggestWorkout | POST | `/api/v1/coach/suggest-workout` | SuggestWorkoutRequest | SuggestWorkoutResponse |
| RPEFeedbackViewModel | postRPEFeedback | POST | `/coach/rpe-feedback` | RPEFeedbackRequest | RPEFeedbackResponse |

### New File: NutritionModels.swift

Extract from ViewModels to `AmakaFlow/Models/NutritionModels.swift`:

```swift
// Response types
struct AnalyzePhotoAPIResponse: Codable { ... }
struct FoodItemResponse: Codable { ... }
struct MacroTotalsResponse: Codable { ... }
struct BarcodeNutritionAPIResponse: Codable { ... }
struct ParseTextAPIResponse: Codable { ... }
struct FuelingStatusResponse: Codable { ... }
struct ProteinNudgeResponse: Codable { ... }
```

Keep the existing model definitions but move them. No field changes.

### APIServiceProviding Protocol Additions

```swift
// MARK: - Nutrition (AMA-1412)
func analyzePhoto(imageBase64: String) async throws -> AnalyzePhotoAPIResponse
func lookupBarcode(code: String) async throws -> BarcodeNutritionAPIResponse
func parseText(text: String) async throws -> ParseTextAPIResponse
func getFuelingStatus() async throws -> FuelingStatusResponse
func checkProteinNudge() async throws -> ProteinNudgeResponse

// MARK: - Coach Suggestions (AMA-1412)
func suggestWorkout(request: SuggestWorkoutRequest) async throws -> SuggestWorkoutResponse
func postRPEFeedback(_ feedback: RPEFeedbackRequest) async throws -> RPEFeedbackResponse
```

### APIService Implementation

Follow existing patterns:
- `guard let url` with `APIError.invalidURL`
- `authHeaders` for authentication
- Explicit 401 → `.unauthorized` handling
- `chatAPIURL` as base (not `mapperAPIURL`)
- `JSONDecoder` with `.convertFromSnakeCase`

### ViewModel Updates

Each ViewModel removes its direct URLSession code and calls `dependencies.apiService.methodName()` instead:

- **FoodLoggingViewModel**: Remove `makeAuthenticatedRequest`, `postAnalyzePhoto`, `getBarcode`, `postParseText`. Add `dependencies` parameter to init. Call APIService methods.
- **FuelingViewModel**: Remove `getFuelingStatus` direct call. Add `dependencies` parameter. Call `dependencies.apiService.getFuelingStatus()`.
- **SuggestWorkoutViewModel**: Remove direct call. Use `dependencies.apiService.suggestWorkout()`.
- **RPEFeedbackViewModel**: Remove direct call. Use `dependencies.apiService.postRPEFeedback()`.

### ProteinNudgeService Update

Only the HTTP call moves to APIService. The notification scheduling, UserDefaults tracking, and 30-minute delay logic stays in ProteinNudgeService. It calls `APIService.shared.checkProteinNudge()` (acceptable for a singleton service — DI injection is a separate concern).

Errors remain best-effort logged (don't surface to user).

### Mock/Fixture Updates

- **MockAPIService**: Add configurable Result properties + call tracking for all 7 new methods
- **FixtureAPIService**: Add canned responses returning reasonable fixture data

## Part 2: Fatigue History View

### FatigueHistoryViewModel

New file: `AmakaFlow/ViewModels/FatigueHistoryViewModel.swift`

```swift
@MainActor
class FatigueHistoryViewModel: ObservableObject {
    @Published var dayStates: [DayState] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedRange: DateRange = .twoWeeks

    enum DateRange: String, CaseIterable {
        case oneWeek = "1W"
        case twoWeeks = "2W"
        case oneMonth = "1M"
    }

    func loadHistory() async { ... }  // calls apiService.fetchDayStates
    func changeRange(_ range: DateRange) { ... }
}
```

Reuses the existing `fetchDayStates(from:to:)` API already in APIService. Different time windows than CalendarViewModel — looks back 1-4 weeks instead of current week.

### FatigueHistoryView

New file: `AmakaFlow/Views/FatigueHistoryView.swift`

- Date range selector (1W / 2W / 1M)
- List of days with readiness pills (green/yellow/red), fatigue score, and workout count
- Summary stats at top: average readiness, days in each tier, trend indicator
- Accessible from Coach tab toolbar or Settings

Layout:
```
┌──────────────────────────────┐
│ Readiness History            │
│ [1W] [2W] [1M]              │
│ ─────────────────────────── │
│ Avg: 72  │ 🟢 8  🟡 4  🔴 2 │
│ ─────────────────────────── │
│ Today       🟢 Green    85   │
│ Yesterday   🟡 Yellow   62   │
│ Apr 1       🟢 Green    78   │
│ Mar 31      🔴 Red      35   │
│ ...                          │
└──────────────────────────────┘
```

## Part 3: Fatigue Settings View

New file: `AmakaFlow/Views/Settings/FatigueSettingsView.swift`

Simple settings following the NutritionSettingsView pattern:

- **Enable fatigue tracking** toggle (UserDefaults)
- **Readiness threshold** — when to show warnings (slider: 0-100, default 40)
- **Show in calendar** toggle — show/hide readiness pills in calendar
- **Recovery reminder** toggle — notify when readiness is red

All settings stored in UserDefaults (matching NutritionViewModel's approach). No backend persistence needed.

Accessible from Settings tab (add a row in SettingsView).

## Files Changed Summary

| File | Action | Description |
|------|--------|-------------|
| `Models/NutritionModels.swift` | Create | Extracted response types |
| `ViewModels/FatigueHistoryViewModel.swift` | Create | History data loading + date ranges |
| `Views/FatigueHistoryView.swift` | Create | Readiness history list view |
| `Views/Settings/FatigueSettingsView.swift` | Create | Fatigue preferences |
| `DependencyInjection/APIServiceProviding.swift` | Modify | +7 protocol methods |
| `Services/APIService.swift` | Modify | +7 implementations |
| `DependencyInjection/AppDependencies.swift` | Modify | +7 mock methods |
| `DependencyInjection/FixtureAPIService.swift` | Modify | +7 fixture stubs |
| `ViewModels/FoodLoggingViewModel.swift` | Modify | Use APIService, remove URLSession |
| `ViewModels/FuelingViewModel.swift` | Modify | Use APIService, remove URLSession |
| `ViewModels/SuggestWorkoutViewModel.swift` | Modify | Use APIService, remove URLSession |
| `ViewModels/RPEFeedbackViewModel.swift` | Modify | Use APIService, remove URLSession |
| `Services/ProteinNudgeService.swift` | Modify | Use APIService for HTTP only |
| `Views/CoachChatView.swift` | Modify | Add nav link to fatigue history |
| `Views/SettingsView.swift` | Modify | Add fatigue settings row |

## Testing Strategy

### Unit Tests
- `FatigueHistoryViewModelTests` — load history, change range, error handling
- Update existing `FoodLoggingViewModelTests` / `FuelingViewModelTests` to use mock APIService
- `FatigueSettingsTests` — settings persistence

### Existing Tests
- Existing nutrition/fueling tests may need updates for DI injection changes
