# AMA-1415: Bulk Import — URL, Image, and File Import

**Ticket:** AMA-1415
**Date:** 2026-04-03

## Summary

Add multi-step bulk import wizard for iOS matching the web's 5-step workflow: detect sources → map columns (files only) → match exercises → preview workouts → execute import. Supports URL import (YouTube/Instagram/TikTok/Pinterest), image import (workout screenshots), and file import (CSV/Excel).

## Scope

All on ingestor-api (`ingestorAPIURL`).

### Steps
1. **Source Selection** — Choose input type (URL, Image, File), enter/select sources
2. **Detection** — POST /import/detect or /import/detect/file → show detected workouts with confidence
3. **Exercise Matching** — POST /import/match → show matched/unmatched exercises, allow corrections
4. **Preview** — POST /import/preview → show workout cards with validation issues
5. **Import** — POST /import/execute → progress polling → results

Column mapping (Step 2.5 for files) is complex and uncommon on mobile — include it but simplify the UI.

## New Models

```swift
// BulkImportModels.swift
struct BulkDetectRequest: Codable { profileId, sourceType, sources }
struct BulkDetectResponse: Codable { success, jobId, items, metadata, total }
struct DetectedItem: Codable, Identifiable { id, sourceRef, parsedTitle, parsedExerciseCount, confidence, errors, warnings }
struct BulkMatchRequest: Codable { jobId, profileId, userMappings }
struct BulkMatchResponse: Codable { success, jobId, exercises, totalExercises, matched, needsReview }
struct ExerciseMatch: Codable, Identifiable { id, originalName, matchedGarminName, confidence, suggestions, status }
struct BulkPreviewRequest: Codable { jobId, profileId, selectedIds }
struct BulkPreviewResponse: Codable { success, jobId, workouts, stats }
struct PreviewWorkout: Codable, Identifiable { id, title, exerciseCount, blockCount, validationIssues, selected, isDuplicate }
struct BulkExecuteRequest: Codable { jobId, profileId, workoutIds, device }
struct BulkExecuteResponse: Codable { success, jobId, status, message }
struct BulkImportStatus: Codable { success, jobId, status, progress, results, error }
struct ImportResult: Codable { workoutId, title, status, error, savedWorkoutId }
```

## New Files

| File | Action |
|------|--------|
| `Models/BulkImportModels.swift` | Create — all request/response types |
| `ViewModels/BulkImportViewModel.swift` | Create — wizard state, API calls, polling |
| `Views/BulkImport/BulkImportWizardView.swift` | Create — main container with step navigation |
| `Views/BulkImport/SourceSelectionView.swift` | Create — URL input, image picker, file picker |
| `Views/BulkImport/DetectionResultsView.swift` | Create — detected items with confidence |
| `Views/BulkImport/ExerciseMatchingView.swift` | Create — match review with corrections |
| `Views/BulkImport/ImportPreviewView.swift` | Create — workout cards with validation |
| `Views/BulkImport/ImportProgressView.swift` | Create — execution progress + results |
| `DependencyInjection/APIServiceProviding.swift` | Modify — +6 bulk import methods |
| `Services/APIService.swift` | Modify — +6 implementations |
| `DependencyInjection/AppDependencies.swift` | Modify — +6 mocks |
| `DependencyInjection/FixtureAPIService.swift` | Modify — +6 fixtures |
| `Views/MoreView.swift` | Modify — add Bulk Import link |
| `Tests/BulkImportViewModelTests.swift` | Create — state management tests |

## API Endpoints (on ingestorAPIURL)

| Method | Endpoint | Purpose |
|--------|----------|---------|
| POST | `/import/detect` | Detect workouts from URLs/images |
| POST | `/import/detect/file` | Detect from file upload (multipart) |
| POST | `/import/match` | Match exercises to Garmin DB |
| POST | `/import/preview` | Generate preview with validation |
| POST | `/import/execute` | Execute async import |
| GET | `/import/status/{jobId}` | Poll import progress |
