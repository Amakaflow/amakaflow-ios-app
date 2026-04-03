# AMA-1412 Part C: Nutrition/Fatigue Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate 7 direct API calls to centralized APIService, extract nutrition response models, add fatigue history view and fatigue settings view.

**Architecture:** Mechanical API migration follows existing APIService patterns (guard URL, authHeaders, 401 handling). New FatigueHistoryViewModel reuses fetchDayStates API. FatigueSettingsView stores prefs in UserDefaults matching NutritionSettingsView pattern.

**Tech Stack:** Swift, SwiftUI, URLSession, XCTest

**Spec:** `docs/superpowers/specs/2026-04-03-nutrition-fatigue-cleanup-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `AmakaFlow/Models/NutritionModels.swift` | Create | All nutrition response types extracted from ViewModels |
| `AmakaFlow/DependencyInjection/APIServiceProviding.swift` | Modify | +7 nutrition/coach protocol methods |
| `AmakaFlow/Services/APIService.swift` | Modify | +7 endpoint implementations |
| `AmakaFlow/DependencyInjection/AppDependencies.swift` | Modify | +7 mock methods with configurable results |
| `AmakaFlow/DependencyInjection/FixtureAPIService.swift` | Modify | +7 fixture stubs |
| `AmakaFlow/ViewModels/FoodLoggingViewModel.swift` | Modify | Remove direct API calls, use dependencies.apiService |
| `AmakaFlow/ViewModels/FuelingViewModel.swift` | Modify | Remove direct API calls, use dependencies.apiService |
| `AmakaFlow/ViewModels/SuggestWorkoutViewModel.swift` | Modify | Remove direct API calls, use dependencies.apiService |
| `AmakaFlow/ViewModels/RPEFeedbackViewModel.swift` | Modify | Remove direct API calls, use dependencies.apiService |
| `AmakaFlow/Services/ProteinNudgeService.swift` | Modify | Use APIService.shared for HTTP only |
| `AmakaFlow/ViewModels/FatigueHistoryViewModel.swift` | Create | Load DayState history with date ranges |
| `AmakaFlow/Views/FatigueHistoryView.swift` | Create | Readiness history list with stats |
| `AmakaFlow/Views/Settings/FatigueSettingsView.swift` | Create | Fatigue tracking preferences |
| `AmakaFlow/Views/CoachChatView.swift` | Modify | Add nav link to fatigue history |
| `AmakaFlow/Views/SettingsView.swift` | Modify | Add fatigue settings row |
| `AmakaFlowCompanionTests/FatigueHistoryViewModelTests.swift` | Create | History loading + date range tests |

---

## Task 1: Extract Nutrition Response Models

**Files:**
- Create: `AmakaFlow/Models/NutritionModels.swift`
- Modify: `AmakaFlow/ViewModels/FoodLoggingViewModel.swift` — remove model definitions
- Modify: `AmakaFlow/ViewModels/FuelingViewModel.swift` — remove FuelingStatusResponse
- Modify: `AmakaFlow/Services/ProteinNudgeService.swift` — remove ProteinNudgeResponse

- [ ] **Step 1: Create NutritionModels.swift with all response types**

Create `AmakaFlow/Models/NutritionModels.swift` — copy all response model structs from FoodLoggingViewModel.swift (lines 15-93), FuelingViewModel.swift (lines 15-29), and ProteinNudgeService.swift (lines 144-149). Keep CodingKeys and all fields exactly as-is.

```swift
//
//  NutritionModels.swift
//  AmakaFlow
//
//  Response models for nutrition API endpoints (AMA-1412)
//

import Foundation

// MARK: - Food Item

struct FoodItemResponse: Codable, Identifiable, Equatable {
    var id: String { name }
    let name: String
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let servingSize: String?
    let confidence: String?

    enum CodingKeys: String, CodingKey {
        case name, calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case servingSize = "serving_size"
        case confidence
    }
}

// MARK: - Macro Totals

struct MacroTotalsResponse: Codable, Equatable {
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double

    enum CodingKeys: String, CodingKey {
        case calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
    }
}

// MARK: - Photo Analysis

struct AnalyzePhotoAPIResponse: Codable {
    let items: [FoodItemResponse]
    let totals: MacroTotalsResponse
    let notes: String?
}

// MARK: - Barcode Lookup

struct BarcodeNutritionAPIResponse: Codable {
    let barcode: String
    let productName: String
    let brand: String?
    let servingSize: String?
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let fiberG: Double?
    let sugarG: Double?
    let imageUrl: String?

    enum CodingKeys: String, CodingKey {
        case barcode
        case productName = "product_name"
        case brand
        case servingSize = "serving_size"
        case calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case fiberG = "fiber_g"
        case sugarG = "sugar_g"
        case imageUrl = "image_url"
    }
}

// MARK: - Text Parsing

struct ParseTextAPIResponse: Codable {
    let items: [FoodItemResponse]
    let totals: MacroTotalsResponse
    let rawText: String

    enum CodingKeys: String, CodingKey {
        case items, totals
        case rawText = "raw_text"
    }
}

// MARK: - Fueling Status

struct FuelingStatusResponse: Codable, Equatable {
    let status: String
    let proteinPct: Double
    let caloriesPct: Double
    let hydrationPct: Double
    let message: String

    enum CodingKeys: String, CodingKey {
        case status
        case proteinPct = "protein_pct"
        case caloriesPct = "calories_pct"
        case hydrationPct = "hydration_pct"
        case message
    }
}

// MARK: - Protein Nudge

struct ProteinNudgeResponse: Codable, Equatable {
    let shouldNudge: Bool
    let proteinCurrent: Int
    let proteinTarget: Int
    let message: String
}
```

- [ ] **Step 2: Remove duplicate model definitions from source files**

In `FoodLoggingViewModel.swift`: Delete lines 15-93 (everything from `struct FoodItemResponse` through the closing `}` of `ParseTextAPIResponse`). Keep `FoodLoggingTab` enum and the ViewModel class.

In `FuelingViewModel.swift`: Delete lines 15-29 (the `FuelingStatusResponse` struct and its CodingKeys). Keep `FuelingStatus` enum and the ViewModel.

In `ProteinNudgeService.swift`: Delete lines 142-149 (the `ProteinNudgeResponse` struct). Keep the service class.

- [ ] **Step 3: Build to verify no compilation errors**

Run: `cd /Volumes/SSD1/openclaw/workspace/amakaflow-ios-app && xcodebuild build -project AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj -scheme AmakaFlowCompanion -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -5`

- [ ] **Step 4: Commit**

```bash
git add AmakaFlow/Models/NutritionModels.swift AmakaFlow/ViewModels/FoodLoggingViewModel.swift AmakaFlow/ViewModels/FuelingViewModel.swift AmakaFlow/Services/ProteinNudgeService.swift
git commit -m "refactor(AMA-1412): Extract nutrition response models to NutritionModels.swift"
```

---

## Task 2: Add Nutrition/Coach API Methods to APIService

**Files:**
- Modify: `AmakaFlow/DependencyInjection/APIServiceProviding.swift`
- Modify: `AmakaFlow/Services/APIService.swift`
- Modify: `AmakaFlow/DependencyInjection/AppDependencies.swift` (MockAPIService)
- Modify: `AmakaFlow/DependencyInjection/FixtureAPIService.swift`

- [ ] **Step 1: Add 7 methods to APIServiceProviding protocol**

In `APIServiceProviding.swift`, add after the Coach section:

```swift
// MARK: - Nutrition (AMA-1412)

/// Analyze a food photo and return macro estimates
func analyzePhoto(imageBase64: String) async throws -> AnalyzePhotoAPIResponse

/// Look up nutrition info by barcode
func lookupBarcode(code: String) async throws -> BarcodeNutritionAPIResponse

/// Parse free-text food description into macros
func parseText(text: String) async throws -> ParseTextAPIResponse

/// Get current fueling status (green/yellow/red)
func getFuelingStatus() async throws -> FuelingStatusResponse

/// Check if user should receive a protein nudge
func checkProteinNudge() async throws -> ProteinNudgeResponse

// MARK: - Coach Suggestions (AMA-1412)

/// Get AI workout suggestion
func suggestWorkout(request: SuggestWorkoutRequest) async throws -> SuggestWorkoutResponse

/// Submit post-workout RPE feedback
func postRPEFeedback(_ feedback: RPEFeedbackRequest) async throws -> RPEFeedbackResponse
```

- [ ] **Step 2: Implement 7 methods in APIService.swift**

Add to `APIService.swift`. All use `chatAPIURL` as base, `authHeaders` for auth, `JSONDecoder` with `.convertFromSnakeCase`:

```swift
// MARK: - Nutrition (AMA-1412)

func analyzePhoto(imageBase64: String) async throws -> AnalyzePhotoAPIResponse {
    let chatURL = AppEnvironment.current.chatAPIURL
    guard let url = URL(string: "\(chatURL)/nutrition/analyze-photo") else { throw APIError.invalidURL }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.allHTTPHeaderFields = authHeaders
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(["image_base64": imageBase64])
    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
    switch httpResponse.statusCode {
    case 200: break
    case 401: throw APIError.unauthorized
    default: throw APIError.serverError(httpResponse.statusCode)
    }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(AnalyzePhotoAPIResponse.self, from: data)
}

func lookupBarcode(code: String) async throws -> BarcodeNutritionAPIResponse {
    let chatURL = AppEnvironment.current.chatAPIURL
    guard let url = URL(string: "\(chatURL)/nutrition/barcode/\(code)") else { throw APIError.invalidURL }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.allHTTPHeaderFields = authHeaders
    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
    switch httpResponse.statusCode {
    case 200: break
    case 401: throw APIError.unauthorized
    default: throw APIError.serverError(httpResponse.statusCode)
    }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(BarcodeNutritionAPIResponse.self, from: data)
}

func parseText(text: String) async throws -> ParseTextAPIResponse {
    let chatURL = AppEnvironment.current.chatAPIURL
    guard let url = URL(string: "\(chatURL)/nutrition/parse-text") else { throw APIError.invalidURL }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.allHTTPHeaderFields = authHeaders
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(["text": text])
    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
    switch httpResponse.statusCode {
    case 200: break
    case 401: throw APIError.unauthorized
    default: throw APIError.serverError(httpResponse.statusCode)
    }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(ParseTextAPIResponse.self, from: data)
}

func getFuelingStatus() async throws -> FuelingStatusResponse {
    let chatURL = AppEnvironment.current.chatAPIURL
    guard let url = URL(string: "\(chatURL)/nutrition/fueling-status") else { throw APIError.invalidURL }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.allHTTPHeaderFields = authHeaders
    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
    switch httpResponse.statusCode {
    case 200: break
    case 401: throw APIError.unauthorized
    default: throw APIError.serverError(httpResponse.statusCode)
    }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(FuelingStatusResponse.self, from: data)
}

func checkProteinNudge() async throws -> ProteinNudgeResponse {
    let chatURL = AppEnvironment.current.chatAPIURL
    guard let url = URL(string: "\(chatURL)/nutrition/protein-nudge/check") else { throw APIError.invalidURL }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.allHTTPHeaderFields = authHeaders
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
    switch httpResponse.statusCode {
    case 200: break
    case 401: throw APIError.unauthorized
    default: throw APIError.serverError(httpResponse.statusCode)
    }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(ProteinNudgeResponse.self, from: data)
}

// MARK: - Coach Suggestions (AMA-1412)

func suggestWorkout(request: SuggestWorkoutRequest) async throws -> SuggestWorkoutResponse {
    let chatURL = AppEnvironment.current.chatAPIURL
    guard let url = URL(string: "\(chatURL)/api/v1/coach/suggest-workout") else { throw APIError.invalidURL }
    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = "POST"
    urlRequest.allHTTPHeaderFields = authHeaders
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.httpBody = try JSONEncoder().encode(request)
    let (data, response) = try await session.data(for: urlRequest)
    guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
    switch httpResponse.statusCode {
    case 200: break
    case 401: throw APIError.unauthorized
    default: throw APIError.serverError(httpResponse.statusCode)
    }
    return try APIService.makeDecoder().decode(SuggestWorkoutResponse.self, from: data)
}

func postRPEFeedback(_ feedback: RPEFeedbackRequest) async throws -> RPEFeedbackResponse {
    let chatURL = AppEnvironment.current.chatAPIURL
    guard let url = URL(string: "\(chatURL)/coach/rpe-feedback") else { throw APIError.invalidURL }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.allHTTPHeaderFields = authHeaders
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(feedback)
    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
    switch httpResponse.statusCode {
    case 200: break
    case 401: throw APIError.unauthorized
    default: throw APIError.serverError(httpResponse.statusCode)
    }
    return try APIService.makeDecoder().decode(RPEFeedbackResponse.self, from: data)
}
```

- [ ] **Step 3: Add mock and fixture implementations**

In `MockAPIService` (AppDependencies.swift), add configurable Result properties and call tracking for all 7 methods. In `FixtureAPIService`, add canned return values.

- [ ] **Step 4: Build to verify**

Run build command. Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(AMA-1412): Add 7 nutrition/coach API methods to APIService"
```

---

## Task 3: Migrate ViewModels to Use APIService

**Files:**
- Modify: `AmakaFlow/ViewModels/FoodLoggingViewModel.swift`
- Modify: `AmakaFlow/ViewModels/FuelingViewModel.swift`
- Modify: `AmakaFlow/ViewModels/SuggestWorkoutViewModel.swift`
- Modify: `AmakaFlow/ViewModels/RPEFeedbackViewModel.swift`
- Modify: `AmakaFlow/Services/ProteinNudgeService.swift`

- [ ] **Step 1: Update FoodLoggingViewModel**

Add `dependencies: AppDependencies` parameter to init (default `.live`). Remove the `makeAuthenticatedRequest`, `postAnalyzePhoto`, `getBarcode`, `postParseText` private methods entirely. Replace the calls in `analyzePhoto()`, `lookupBarcode()`, `parseText()` with `dependencies.apiService.analyzePhoto(imageBase64:)`, etc.

- [ ] **Step 2: Update FuelingViewModel**

Add `dependencies: AppDependencies` parameter. Remove the private `getFuelingStatus()` method. In `fetchFuelingStatus()`, call `dependencies.apiService.getFuelingStatus()`.

- [ ] **Step 3: Update SuggestWorkoutViewModel**

Read the file first. Add `dependencies` parameter. Remove direct URLSession call. Use `dependencies.apiService.suggestWorkout(request:)`.

- [ ] **Step 4: Update RPEFeedbackViewModel**

Read the file first. Add `dependencies` parameter. Remove direct URLSession call. Use `dependencies.apiService.postRPEFeedback(_:)`.

- [ ] **Step 5: Update ProteinNudgeService**

Only replace the HTTP call. Change `checkProteinNudge()` to call `APIService.shared.checkProteinNudge()`. Keep scheduling/notification logic unchanged. Keep error handling best-effort (log, don't surface).

- [ ] **Step 6: Build and run existing tests**

Run full build + existing nutrition tests to verify no regressions.

- [ ] **Step 7: Commit**

```bash
git commit -am "refactor(AMA-1412): Migrate ViewModels from direct URLSession to APIService"
```

---

## Task 4: Fatigue History View + ViewModel

**Files:**
- Create: `AmakaFlow/ViewModels/FatigueHistoryViewModel.swift`
- Create: `AmakaFlow/Views/FatigueHistoryView.swift`
- Modify: `AmakaFlow/Views/CoachChatView.swift` — add nav link
- Test: `AmakaFlowCompanionTests/FatigueHistoryViewModelTests.swift`

- [ ] **Step 1: Create FatigueHistoryViewModel**

```swift
//
//  FatigueHistoryViewModel.swift
//  AmakaFlow
//
//  ViewModel for fatigue/readiness history display (AMA-1412)
//

import Foundation

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

        var days: Int {
            switch self {
            case .oneWeek: return 7
            case .twoWeeks: return 14
            case .oneMonth: return 30
            }
        }
    }

    private let dependencies: AppDependencies

    init(dependencies: AppDependencies = .live) {
        self.dependencies = dependencies
    }

    func loadHistory() async {
        isLoading = true
        errorMessage = nil

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -selectedRange.days, to: today) ?? today

        do {
            let states = try await dependencies.apiService.fetchDayStates(
                from: formatter.string(from: startDate),
                to: formatter.string(from: today)
            )
            dayStates = states.sorted { $0.date > $1.date }
        } catch {
            print("[FatigueHistoryVM] loadHistory failed: \(error)")
            errorMessage = "Could not load readiness history"
        }

        isLoading = false
    }

    func changeRange(_ range: DateRange) {
        selectedRange = range
        Task { await loadHistory() }
    }

    // MARK: - Computed Stats

    var averageFatigueScore: Double? {
        let scores = dayStates.compactMap { $0.fatigueScore }
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }

    var greenDays: Int { dayStates.filter { $0.readiness == .green }.count }
    var yellowDays: Int { dayStates.filter { $0.readiness == .yellow }.count }
    var redDays: Int { dayStates.filter { $0.readiness == .red }.count }
}
```

- [ ] **Step 2: Create FatigueHistoryView**

```swift
//
//  FatigueHistoryView.swift
//  AmakaFlow
//
//  Readiness history view with date range selection (AMA-1412)
//

import SwiftUI

struct FatigueHistoryView: View {
    @StateObject private var viewModel = FatigueHistoryViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Date range picker
            Picker("Range", selection: $viewModel.selectedRange) {
                ForEach(FatigueHistoryViewModel.DateRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .padding(Theme.Spacing.md)
            .onChange(of: viewModel.selectedRange) { newRange in
                viewModel.changeRange(newRange)
            }

            // Stats summary
            if !viewModel.dayStates.isEmpty {
                HStack(spacing: Theme.Spacing.lg) {
                    if let avg = viewModel.averageFatigueScore {
                        statPill("Avg", value: "\(Int(avg))")
                    }
                    statPill("🟢", value: "\(viewModel.greenDays)")
                    statPill("🟡", value: "\(viewModel.yellowDays)")
                    statPill("🔴", value: "\(viewModel.redDays)")
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.sm)
            }

            // Day list
            if viewModel.isLoading {
                ProgressView("Loading history...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorMessage {
                Text(error)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.accentRed)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.dayStates.isEmpty {
                Text("No readiness data available yet.")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.dayStates) { dayState in
                    dayRow(dayState)
                        .listRowBackground(Theme.Colors.surface)
                }
                .listStyle(.plain)
            }
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationTitle("Readiness History")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadHistory()
        }
    }

    private func statPill(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Theme.Typography.bodyBold)
                .foregroundColor(Theme.Colors.textPrimary)
            Text(label)
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.surface)
        .cornerRadius(Theme.CornerRadius.md)
    }

    private func dayRow(_ dayState: DayState) -> some View {
        HStack {
            Text(dayState.date)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textPrimary)

            Spacer()

            readinessBadge(dayState.readiness)

            if let score = dayState.fatigueScore {
                Text("\(Int(score))")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private func readinessBadge(_ level: ReadinessLevel) -> some View {
        Text(level.rawValue.capitalized)
            .font(Theme.Typography.captionBold)
            .foregroundColor(readinessColor(level))
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 2)
            .background(readinessColor(level).opacity(0.15))
            .cornerRadius(Theme.CornerRadius.sm)
    }

    private func readinessColor(_ level: ReadinessLevel) -> Color {
        switch level {
        case .green: return Theme.Colors.accentGreen
        case .yellow: return Theme.Colors.accentOrange
        case .red: return Theme.Colors.accentRed
        case .rest: return Theme.Colors.accentBlue
        case .unknown: return Theme.Colors.textTertiary
        }
    }
}
```

- [ ] **Step 3: Add nav link in CoachChatView toolbar**

In `CoachChatView.swift`, add a toolbar item for fatigue history. Add a NavigationLink to FatigueHistoryView next to the existing fatigue advisor link, or replace the heart icon with a menu that has both options.

Simplest approach: add it to the trailing toolbar as a second item, using a clock icon:

```swift
ToolbarItem(placement: .topBarTrailing) {
    HStack(spacing: Theme.Spacing.sm) {
        NavigationLink(destination: FatigueHistoryView()) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundColor(Theme.Colors.accentBlue)
                .accessibilityLabel("Readiness history")
        }
        NavigationLink(destination: FatigueAdvisorView(viewModel: viewModel)) {
            Image(systemName: "heart.text.square")
                .foregroundColor(Theme.Colors.accentBlue)
                .accessibilityLabel("Open fatigue advisor")
        }
    }
}
```

- [ ] **Step 4: Write FatigueHistoryViewModel tests**

Create `AmakaFlowCompanionTests/FatigueHistoryViewModelTests.swift`:

```swift
import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class FatigueHistoryViewModelTests: XCTestCase {
    var viewModel: FatigueHistoryViewModel!
    var mockAPIService: MockAPIService!

    override func setUp() async throws {
        mockAPIService = MockAPIService()
        let dependencies = AppDependencies(
            apiService: mockAPIService,
            pairingService: MockPairingService(),
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: MockChatStreamService()
        )
        viewModel = FatigueHistoryViewModel(dependencies: dependencies)
    }

    func testLoadHistory() async {
        mockAPIService.fetchDayStatesResult = .success([
            DayState(date: "2026-04-02", readiness: .green, plannedWorkouts: [], completedWorkouts: [], fatigueScore: 80, notes: nil),
            DayState(date: "2026-04-01", readiness: .yellow, plannedWorkouts: [], completedWorkouts: [], fatigueScore: 55, notes: nil)
        ])

        await viewModel.loadHistory()

        XCTAssertEqual(viewModel.dayStates.count, 2)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testAverageFatigueScore() async {
        mockAPIService.fetchDayStatesResult = .success([
            DayState(date: "2026-04-02", readiness: .green, plannedWorkouts: [], completedWorkouts: [], fatigueScore: 80, notes: nil),
            DayState(date: "2026-04-01", readiness: .red, plannedWorkouts: [], completedWorkouts: [], fatigueScore: 40, notes: nil)
        ])

        await viewModel.loadHistory()

        XCTAssertEqual(viewModel.averageFatigueScore, 60)
    }

    func testReadinessCounts() async {
        mockAPIService.fetchDayStatesResult = .success([
            DayState(date: "2026-04-03", readiness: .green, plannedWorkouts: [], completedWorkouts: [], fatigueScore: nil, notes: nil),
            DayState(date: "2026-04-02", readiness: .green, plannedWorkouts: [], completedWorkouts: [], fatigueScore: nil, notes: nil),
            DayState(date: "2026-04-01", readiness: .red, plannedWorkouts: [], completedWorkouts: [], fatigueScore: nil, notes: nil)
        ])

        await viewModel.loadHistory()

        XCTAssertEqual(viewModel.greenDays, 2)
        XCTAssertEqual(viewModel.redDays, 1)
        XCTAssertEqual(viewModel.yellowDays, 0)
    }

    func testLoadHistoryError() async {
        mockAPIService.fetchDayStatesResult = .failure(APIError.serverError(500))

        await viewModel.loadHistory()

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.dayStates.isEmpty)
    }

    func testChangeRange() async {
        mockAPIService.fetchDayStatesResult = .success([])

        viewModel.changeRange(.oneMonth)

        XCTAssertEqual(viewModel.selectedRange, .oneMonth)
    }
}
```

- [ ] **Step 5: Build and run tests**

- [ ] **Step 6: Commit**

```bash
git commit -am "feat(AMA-1412): Add FatigueHistoryView with readiness stats, date ranges, and tests"
```

---

## Task 5: Fatigue Settings View

**Files:**
- Create: `AmakaFlow/Views/Settings/FatigueSettingsView.swift`
- Modify: `AmakaFlow/Views/SettingsView.swift` — add row

- [ ] **Step 1: Create FatigueSettingsView**

```swift
//
//  FatigueSettingsView.swift
//  AmakaFlow
//
//  Fatigue and readiness tracking preferences (AMA-1412)
//

import SwiftUI

struct FatigueSettingsView: View {
    @AppStorage("fatigue_tracking_enabled") private var isEnabled = true
    @AppStorage("fatigue_readiness_threshold") private var readinessThreshold = 40.0
    @AppStorage("fatigue_show_in_calendar") private var showInCalendar = true
    @AppStorage("fatigue_recovery_reminder") private var recoveryReminder = false

    var body: some View {
        List {
            Section {
                Toggle("Enable fatigue tracking", isOn: $isEnabled)
            } header: {
                Text("General")
            } footer: {
                Text("Track your daily readiness and fatigue levels based on training load.")
            }

            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack {
                        Text("Warning threshold")
                        Spacer()
                        Text("\(Int(readinessThreshold))")
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    Slider(value: $readinessThreshold, in: 20...80, step: 5)
                        .tint(Theme.Colors.accentBlue)
                }
            } header: {
                Text("Readiness")
            } footer: {
                Text("Show a warning when your readiness score drops below this level.")
            }

            Section {
                Toggle("Show readiness in calendar", isOn: $showInCalendar)
                Toggle("Recovery reminders", isOn: $recoveryReminder)
            } header: {
                Text("Display")
            } footer: {
                Text("Recovery reminders notify you when consecutive red days suggest you need rest.")
            }
        }
        .navigationTitle("Fatigue Tracking")
        .navigationBarTitleDisplayMode(.inline)
    }
}
```

- [ ] **Step 2: Add row in SettingsView**

Read `SettingsView.swift` to find where to add the fatigue settings NavigationLink. Add it near the nutrition settings link:

```swift
NavigationLink(destination: FatigueSettingsView()) {
    Label("Fatigue Tracking", systemImage: "heart.text.square")
}
```

- [ ] **Step 3: Build to verify**

- [ ] **Step 4: Commit**

```bash
git commit -am "feat(AMA-1412): Add FatigueSettingsView with tracking preferences"
```

---

## Task 6: Final Integration Verification

- [ ] **Step 1: Run full test suite**

Run: `xcodebuild test -project AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj -scheme AmakaFlowCompanion -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -30`

- [ ] **Step 2: Verify build for device**

Run: `xcodebuild build -project AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj -scheme AmakaFlowCompanion -destination generic/platform=iOS 2>&1 | tail -5`

- [ ] **Step 3: Review git log**

Expected commits:
```
refactor(AMA-1412): Extract nutrition response models to NutritionModels.swift
feat(AMA-1412): Add 7 nutrition/coach API methods to APIService
refactor(AMA-1412): Migrate ViewModels from direct URLSession to APIService
feat(AMA-1412): Add FatigueHistoryView with readiness stats, date ranges, and tests
feat(AMA-1412): Add FatigueSettingsView with tracking preferences
```
