# E2E UI Tests for AmakaFlow Companion

End-to-end UI tests for the AmakaFlow iOS Companion app (AMA-232).

## Overview

This test suite provides comprehensive E2E testing for:
- App launch and authentication bypass
- Workout selection and navigation
- Workout execution flow
- Watch connectivity verification
- App lifecycle handling

## Test Structure

```
AmakaFlowCompanionUITests/
├── AmakaFlowCompanionUITests.swift    # Main E2E test classes
├── WatchConnectivityE2ETests.swift     # Watch-specific tests
├── TestAuthHelper.swift                # Clerk test-user launch configuration
├── HealthDataSimulator.swift           # HealthKit data simulation
└── README.md                           # This file
```

## Test Classes

| Class | Purpose |
|-------|---------|
| `AppLaunchE2ETests` | App launch, Clerk test auth, tab bar verification |
| `NavigationE2ETests` | Tab navigation, screen transitions |
| `WorkoutFlowE2ETests` | Workout list, selection, detail view |
| `StrengthWorkoutE2ETests` | Strength workout-specific tests |
| `WorkoutControlE2ETests` | Pause/resume, workout controls |
| `AppLifecycleE2ETests` | Background/foreground, state preservation |
| `RefreshE2ETests` | Pull to refresh functionality |
| `WatchConnectivityE2ETests` | Watch sync and communication |

## Setup

### 1. Test Credentials

Provide a real Clerk test user through environment variables before running UI tests:

```bash
export UITEST_CLERK_EMAIL="ios-e2e@example.com"
export UITEST_CLERK_PASSWORD="..."
export UITEST_CLERK_PUBLISHABLE_KEY="pk_test_..."
export TEST_API_BASE_URL="http://localhost:8001"
```

Tests sign in through Clerk instead of using backend auth-header bypasses.

### 2. Simulator Setup

For Watch connectivity tests, you need paired simulators:

```bash
# Create and boot paired simulators
./scripts/setup-paired-simulators.sh --create --boot

# List available simulators
./scripts/setup-paired-simulators.sh --list

# Check pairing status
./scripts/setup-paired-simulators.sh --status
```

## Running Tests

### From Xcode

1. Open the project in Xcode
2. Select `AmakaFlowCompanion` scheme
3. Select an iPhone simulator destination
4. Press `Cmd + U` to run all tests
5. Or click the diamond next to a specific test

### From Command Line

```bash
cd AmakaFlowCompanion

# Run all UI tests
xcodebuild test \
    -project AmakaFlowCompanion.xcodeproj \
    -scheme AmakaFlowCompanion \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -only-testing:AmakaFlowCompanionUITests

# Run specific test class
xcodebuild test \
    -project AmakaFlowCompanion.xcodeproj \
    -scheme AmakaFlowCompanion \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -only-testing:AmakaFlowCompanionUITests/AppLaunchE2ETests

# Disable parallel testing for more reliable results
xcodebuild test \
    -project AmakaFlowCompanion.xcodeproj \
    -scheme AmakaFlowCompanion \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -only-testing:AmakaFlowCompanionUITests \
    -parallel-testing-enabled NO
```

## Clerk Test Auth

The tests use launch arguments and environment values to drive the Clerk sign-in flow:

```swift
// In tests
TestAuthHelper.configureApp(app)
app.launch()
```

This sets:
- `--uitesting` - Indicates UI test mode
- `UITEST_CLERK_EMAIL` / `UITEST_CLERK_PASSWORD` - real Clerk test user
- `UITEST_CLERK_PUBLISHABLE_KEY` - Clerk publishable key for the test environment

The app checks for these in `AmakaFlowCompanionApp.swift`:

```swift
#if DEBUG
if CommandLine.arguments.contains("--uitesting") {
    // Drive the Clerk AuthView using UITEST_CLERK_EMAIL and UITEST_CLERK_PASSWORD.
}
#endif
```

## HealthKit Data Simulation

The `HealthDataSimulator` provides helpers for injecting health data:

```swift
// Generate mock heart rate samples
let samples = HealthDataSimulator.generateHeartRateSamples(
    baseHR: 140,
    durationMinutes: 30
)

// Verify health data appears in UI
XCTAssertTrue(HealthDataSimulator.verifyHeartRateDisplayed(app))
```

Uses [XCTHealthKit](https://github.com/StanfordBDHG/XCTHealthKit) from Stanford BioDesign.

## WatchConnectivity Notes

### Simulator Behavior

| Method | Simulator | Notes |
|--------|-----------|-------|
| `updateApplicationContext()` | Works | Reliable for state sync |
| `transferUserInfo()` | Works | Reliable for data transfer |
| `sendMessage()` | Unreliable | Often fails/timeouts |
| `isReachable` | Unreliable | Often returns false |

### Testing Strategy

- Focus on iPhone-side behavior verification
- Use `transferUserInfo` and `updateApplicationContext` for data sync tests
- Skip `sendMessage` tests in simulator (use real devices)
- Don't assert on `isReachable` in simulator tests

## Troubleshooting

### Tests fail with "App not paired"

Ensure `UITEST_CLERK_EMAIL`, `UITEST_CLERK_PASSWORD`, and `UITEST_CLERK_PUBLISHABLE_KEY` are set for a valid Clerk test user.

### Watch tests are skipped

Run with paired simulators:
```bash
./scripts/setup-paired-simulators.sh --create --boot
```

### Timeouts during workout loading

The test user needs workouts in the staging environment. Create test workouts via the web app or API.

### HealthKit authorization dialogs

Tests attempt to dismiss system dialogs automatically. If issues persist, reset the simulator:
```bash
xcrun simctl erase "iPhone 17 Pro"
```

## Adding New Tests

1. Create tests in the appropriate class or add a new class
2. Extend `BaseE2ETestCase` for consistent setup/teardown
3. Use `TestAuthHelper.configureApp(app)` for Clerk test auth
4. Use `TestAuthHelper.waitForMainContent(app)` to wait for app load
5. Use `XCTSkip` for conditional tests (e.g., Watch connectivity)

Example:

```swift
final class MyNewE2ETests: BaseE2ETestCase {

    func testMyFeature() throws {
        XCTAssertTrue(TestAuthHelper.waitForMainContent(app, timeout: 15),
                     "App should load main content")

        // Navigate and interact
        let myButton = app.buttons["My Button"]
        XCTAssertTrue(myButton.waitForExistence(timeout: 5))
        myButton.tap()

        // Verify result
        let result = app.staticTexts["Expected Result"]
        XCTAssertTrue(result.waitForExistence(timeout: 3))
    }
}
```

## CI/CD Integration

For GitHub Actions or similar:

```yaml
- name: Run E2E Tests
  run: |
    xcodebuild test \
      -project AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj \
      -scheme AmakaFlowCompanion \
      -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
      -only-testing:AmakaFlowCompanionUITests \
      -parallel-testing-enabled NO \
      -resultBundlePath TestResults.xcresult
```
