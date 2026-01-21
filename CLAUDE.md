# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture Overview

AmakaFlow Companion is a SwiftUI iOS app with a watchOS companion for syncing and executing workouts. It connects to the AmakaFlow backend (mapper-api) for workout data and uses Apple's WorkoutKit for native fitness integration.

```
┌─────────────────────────────────────────┐
│           AmakaFlowCompanion            │
│  (iOS App - SwiftUI, iOS 17+/18+ WK)    │
└─────────────────────────────────────────┘
         │                    │
         ▼                    ▼
┌─────────────────┐  ┌─────────────────────┐
│ AmakaFlowWatch  │  │   Backend APIs      │
│ (watchOS 10+)   │  │ mapper-api :8001    │
│ WatchConnectivity  │ calendar-api :8003  │
└─────────────────┘  └─────────────────────┘
         │
         ▼
┌─────────────────┐
│ Apple Fitness   │
│ (WorkoutKit)    │
└─────────────────┘
```

## Build & Run Commands

### Xcode Project
```bash
# Open project
open AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj

# Build from command line
xcodebuild build -scheme AmakaFlowCompanion \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# Run tests
xcodebuild test -scheme AmakaFlowCompanion \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# Run single test class
xcodebuild test -scheme AmakaFlowCompanion \
  -only-testing:AmakaFlowCompanionTests/WorkoutEngineTests

# Run single test
xcodebuild test -scheme AmakaFlowCompanion \
  -only-testing:AmakaFlowCompanionTests/WorkoutEngineTests/testProgressingThroughIntervals

# Clean build
xcodebuild clean -project AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj
rm -rf ~/Library/Developer/Xcode/DerivedData/AmakaFlowCompanion-*
```

### Linting (SwiftLint)
```bash
./scripts/setup-linting.sh   # One-time setup
./scripts/lint.sh            # Run linter
swiftlint autocorrect        # Auto-fix issues
```

### E2E Testing with Local Backend
```bash
SIMCTL_CHILD_TEST_AUTH_SECRET="e2e-test-secret-dev-only" \
SIMCTL_CHILD_TEST_USER_ID="user_37lZCcU9AJ9b7MX2H71dZ2CuX2u" \
SIMCTL_CHILD_TEST_API_BASE_URL="http://localhost:8001" \
xcodebuild test -scheme AmakaFlowCompanion \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

## Project Structure

```
amakaflow-ios-app/
├── AmakaFlow/                    # Shared iOS code
│   ├── AmakaFlowApp.swift       # App entry point (@main)
│   ├── DependencyInjection/     # DI container & protocols
│   ├── Services/                # Business logic (API, Auth, Pairing, etc.)
│   ├── ViewModels/              # MVVM state management
│   ├── Views/                   # SwiftUI components
│   ├── Models/                  # Data models (Workout, Completion, etc.)
│   ├── Engine/                  # WorkoutEngine state machine
│   └── LiveActivity/            # Dynamic Island/Lock Screen
├── AmakaFlowCompanion/          # Xcode project
│   ├── AmakaFlowCompanion/      # iOS app target
│   ├── AmakaFlowWatch Watch App/# watchOS target
│   └── AmakaFlowCompanionTests/ # Test target
├── docs/                        # Setup guides by topic
└── scripts/                     # Linting, build scripts
```

## Key Patterns

### MVVM + Dependency Injection
All services have protocol abstractions (`*Providing` suffix) for testability:

```swift
// AppDependencies.swift - Main DI Container
@MainActor
struct AppDependencies {
    let apiService: APIServiceProviding
    let pairingService: PairingServiceProviding
    let audioService: AudioProviding
    // ...
    static let live = AppDependencies(...)   // Production
    static let mock = AppDependencies(...)   // Testing
}

// ViewModels receive dependencies
@MainActor
class WorkoutsViewModel: ObservableObject {
    init(dependencies: AppDependencies = .live) { ... }
}
```

### WorkoutEngine State Machine
Core workout execution in `Engine/WorkoutEngine.swift`:
- Phases: idle → ready → running → paused → completed
- Handles intervals: warmup, cooldown, time, reps, distance, repeat, rest
- Execution logging with timestamps
- Heart rate zone tracking via HealthKit

### Authentication
- **Production**: JWT Bearer token via `PairingService`
- **E2E Testing**: `X-Test-Auth` / `X-Test-User-Id` headers bypass
- Credentials stored in Keychain via `KeychainHelper`

### Environment Configuration
```swift
enum AppEnvironment {
    case development    // localhost:8001
    case staging        // mapper-api.staging.amakaflow.com
    case production     // mapper-api.amakaflow.com
}
```

## Key Services

| Service | Purpose |
|---------|---------|
| `APIService` | HTTP client for mapper-api, retry logic, auth headers |
| `PairingService` | JWT token management, profile caching, auth state |
| `WorkoutEngine` | State machine for workout playback |
| `WatchConnectivityManager` | iPhone ↔ Watch bidirectional communication |
| `WorkoutKitConverter` | Convert to Apple WorkoutKit format (iOS 18+) |
| `TranscriptionService` | Voice workout transcription |
| `WorkoutCompletionService` | Completion tracking and sync |

## Data Models

**Workout** (`Models/Workout.swift`):
- Intervals: warmup, cooldown, time, reps, distance, repeat, rest
- Sport types, equipment, difficulty

**WorkoutInterval** (enum with associated values):
```swift
case warmup(seconds: Int, target: String?)
case reps(sets: Int?, reps: Int, name: String, load: String?, restSec: Int?)
case repeat(reps: Int, intervals: [WorkoutInterval])
// etc.
```

## API Endpoints (mapper-api)

```
GET  /workouts/incoming           # Pending workouts
GET  /workouts/scheduled          # Scheduled workouts
POST /workouts/{id}/confirm-sync  # Report successful sync
POST /workouts/completions        # Submit completion data
GET  /profile                     # User profile
POST /voice-workout/parse         # Parse voice to workout
```

## Testing

**Test Files** in `AmakaFlowCompanion/AmakaFlowCompanionTests/`:
- `WorkoutEngineTests.swift` - Core state machine
- `WorkoutsViewModelTests.swift` - ViewModel logic
- `WatchConnectivityTests.swift` - Watch communication
- `PairingTests.swift` - Auth flow
- `TranscriptionTests.swift` - Voice features

**CI Optimization** (`.github/workflows/`):
- `affected-tests-ios.sh` detects changed test files
- Only runs affected tests for faster feedback

## Requirements

- **iOS**: 17.0+ (18.0+ for WorkoutKit)
- **watchOS**: 10.0+ (11.0+ for WorkoutKit)
- **Xcode**: 15.0+
- **Swift**: 5.9+
- **Physical device** required for HealthKit testing

## Dependencies (SPM)

- **sentry-cocoa** - Error tracking
- **XCTHealthKit** - Test utilities for HealthKit
- **workoutkit-sync** - Local package at `../../workoutkit-sync`
