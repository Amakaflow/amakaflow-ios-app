# AMA-1414: Advanced Analytics — Volume, Balance, Muscle Breakdown

**Ticket:** AMA-1414
**Date:** 2026-04-03
**Status:** Design approved, ready for implementation

## Summary

Add volume analytics to the iOS AnalyticsView matching the web app: stacked bar chart by muscle group, push/pull and upper/lower balance indicators, muscle group breakdown with drill-down, configurable time periods, and period-over-period comparison. Uses SwiftUI Charts (iOS 16+) and the existing mapper-api `/progression/volume` endpoint.

## Goals

1. Volume stacked bar chart by muscle group with period selector
2. Push/Pull and Upper/Lower balance ratio indicators
3. Muscle group breakdown sorted by volume
4. Exercise drill-down per muscle group
5. Period-over-period summary comparison cards

## Non-Goals

- Replacing existing analytics sections (weekly summary, sport distribution, fatigue — keep as-is)
- 1RM estimation charts (separate ticket)
- Custom date range picker (use preset periods)

## Architecture

### API Endpoint (Already Exists)

```
GET {mapperAPIURL}/progression/volume
  ?start_date=YYYY-MM-DD
  &end_date=YYYY-MM-DD
  &granularity=daily|weekly|monthly

Response:
{
  "data": [
    { "period": "2026-03-24", "muscle_group": "chest", "total_volume": 5000, "total_sets": 12, "total_reps": 96 }
  ],
  "summary": {
    "total_volume": 45000,
    "total_sets": 120,
    "total_reps": 960,
    "muscle_group_breakdown": { "chest": 5000, "back": 4500, ... }
  },
  "period": { "start_date": "...", "end_date": "..." },
  "granularity": "weekly"
}
```

### New Models

```swift
// VolumeAnalyticsResponse
struct VolumeAnalyticsResponse: Codable {
    let data: [VolumeDataPoint]
    let summary: VolumeSummary
    let period: VolumePeriod
    let granularity: String
}

struct VolumeDataPoint: Codable, Identifiable {
    var id: String { "\(period)-\(muscleGroup)" }
    let period: String
    let muscleGroup: String
    let totalVolume: Double
    let totalSets: Int
    let totalReps: Int
}

struct VolumeSummary: Codable {
    let totalVolume: Double
    let totalSets: Int
    let totalReps: Int
    let muscleGroupBreakdown: [String: Double]
}

struct VolumePeriod: Codable {
    let startDate: String
    let endDate: String
}
```

### Balance Logic

```
Push muscles: chest, shoulders, triceps
Pull muscles: back, biceps
Upper muscles: chest, back, shoulders, biceps, triceps
Lower muscles: legs, glutes, hamstrings, calves

Ratio = groupA / groupB
Balanced: 0.8–1.2 (green)
Slight imbalance: 0.5–0.8 or 1.2–1.5 (yellow/orange)
Imbalanced: <0.5 or >1.5 (red)
```

### New ViewModel: VolumeAnalyticsViewModel

```swift
@MainActor class VolumeAnalyticsViewModel: ObservableObject {
    enum AnalyticsPeriod: String, CaseIterable {
        case week = "1W", month = "1M", quarter = "3M"
    }

    @Published var selectedPeriod: AnalyticsPeriod = .month
    @Published var currentData: VolumeAnalyticsResponse?
    @Published var previousData: VolumeAnalyticsResponse?
    @Published var isLoading = false
    @Published var errorMessage: String?

    // Computed: balance ratios, muscle breakdown sorted, period comparison
    func loadVolume() async  // fetches current + previous period in parallel
    func changePeriod(_ period: AnalyticsPeriod)
}
```

### New View Components

1. **VolumeAnalyticsSection** — Container added to AnalyticsView below existing sections
2. **VolumeBarChart** — SwiftUI Charts stacked BarMark by muscle group per period
3. **BalanceIndicatorsView** — Push/Pull + Upper/Lower horizontal gauges
4. **MuscleGroupBreakdown** — Sorted list with volume bars and percentages
5. **ExerciseDrillDownSheet** — Modal showing exercise-level detail for a muscle group (future — use what data is available)

### Integration

Add volume section to existing `AnalyticsView.swift` after the current sport distribution section. Period selector at top of new section.

## Files

| File | Action |
|------|--------|
| `Models/VolumeAnalyticsModels.swift` | Create — response types |
| `ViewModels/VolumeAnalyticsViewModel.swift` | Create — data loading, balance computation |
| `Views/Analytics/VolumeBarChart.swift` | Create — SwiftUI Charts stacked bar |
| `Views/Analytics/BalanceIndicatorsView.swift` | Create — ratio gauges |
| `Views/Analytics/MuscleGroupBreakdown.swift` | Create — sorted volume list |
| `Views/Analytics/VolumeAnalyticsSection.swift` | Create — container for all volume components |
| `DependencyInjection/APIServiceProviding.swift` | Modify — add fetchVolumeAnalytics |
| `Services/APIService.swift` | Modify — implement endpoint |
| `DependencyInjection/AppDependencies.swift` | Modify — add mock |
| `DependencyInjection/FixtureAPIService.swift` | Modify — add fixture |
| `Views/AnalyticsView.swift` | Modify — add VolumeAnalyticsSection |
| `Tests/VolumeAnalyticsViewModelTests.swift` | Create — ViewModel tests |

## Testing

- VolumeAnalyticsViewModel: load, period change, balance computation, error handling
- VolumeDataPoint/Summary decoding tests
- Balance ratio edge cases (zero volume, single muscle group)
