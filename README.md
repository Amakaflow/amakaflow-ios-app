# AmakaFlow Companion iOS App

iOS companion app for syncing workouts to Apple Watch and Calendar.

## Features

- ✅ Sync workouts to Apple Watch via WorkoutKit
- ✅ Schedule workouts to Calendar with reminders
- ✅ Receive workouts from backend (API integration coming soon)
- ✅ View workout details and intervals
- 🚧 Authentication via Clerk (coming soon)
- 🚧 Full workout workflow (coming soon)

## Project Structure

```
amakaflow-ios/
├── AmakaFlow/              # iOS App
│   ├── AmakaFlowApp.swift  # Main app entry
│   ├── Models/
│   │   └── Workout.swift
│   ├── ViewModels/
│   │   └── WorkoutsViewModel.swift
│   ├── Views/
│   │   ├── WorkoutsView.swift
│   │   ├── WorkoutDetailView.swift
│   │   ├── SettingsView.swift
│   │   └── Components/
│   ├── Services/
│   │   ├── WatchConnectivityManager.swift
│   │   ├── CalendarManager.swift
│   │   ├── WorkoutKitConverter.swift
│   │   ├── APIService.swift (placeholder)
│   │   └── AuthService.swift (placeholder)
│   └── Theme/
│       └── Theme.swift
│
└── AmakaFlowWatch/         # watchOS App
    ├── AmakaFlowWatchApp.swift
    ├── WatchWorkoutManager.swift
    └── WorkoutListView.swift
```

## Documentation

Documentation is organized by subject in the `docs/` folder:

- **[Setup Guides](./docs/setup/)** - Initial project setup and configuration
  - `XCODE_SETUP_GUIDE.md` - Detailed Xcode setup instructions
  - `PROJECT_NAME.md` - Project naming conventions
  - `HOW_TO_SELECT_TARGET.md` - Target selection guide

- **[HealthKit](./docs/healthkit/)** - HealthKit integration and configuration
  - `HEALTHKIT_SETUP.md` - HealthKit capability setup
  - `WATCHOS_HEALTHKIT_SETUP.md` - WatchOS HealthKit configuration
  - `ADD_HEALTHKIT_USAGE_DESCRIPTIONS.md` - Usage description setup
  - Various fix guides for HealthKit issues

- **[Entitlements](./docs/entitlements/)** - Entitlements configuration and fixes
  - `ADD_ENTITLEMENT_KEY.md` - Adding entitlement keys
  - `FIX_ENTITLEMENTS_PATH.md` - Fixing entitlements paths
  - Various entitlements troubleshooting guides

- **[WatchOS](./docs/watchos/)** - WatchOS-specific documentation
  - `ADD_FRAMEWORKS_WATCHOS.md` - Adding frameworks to WatchOS
  - `ADD_WORKOUT_TO_WATCHOS.md` - Adding workouts to WatchOS
  - `FIX_WATCHOS_DEPLOYMENT_TARGET.md` - Deployment target fixes

- **[WorkoutKit](./docs/workoutkit/)** - WorkoutKit integration guides
  - `ADD_WORKOUT_STEP_BY_STEP.md` - Step-by-step workout addition
  - `FIX_WORKOUTKIT_ERRORS.md` - WorkoutKit error fixes
  - `FIXED_WORKOUTKIT_USAGE.md` - WorkoutKit usage examples

- **[Troubleshooting](./docs/troubleshooting/)** - Debugging and issue resolution
  - `DEBUG_BLANK_SCREEN.md` - Debugging blank screens
  - `FIX_BUILD_ERRORS.md` - Build error solutions
  - `FIX_UNRESPONSIVE_UI.md` - UI responsiveness fixes
  - Various other troubleshooting guides

- **[Build Configuration](./docs/build-config/)** - Build settings and configuration
  - `ADD_INFO_PLIST_KEYS.md` - Info.plist key management
  - `FIX_DEPLOYMENT_TARGET.md` - Deployment target configuration
  - `CHECK_SDK_STATUS.md` - SDK status verification

- **[Target Membership](./docs/target-membership/)** - File target membership guides
  - `ADD_SWIFT_FILES.md` - Adding Swift files to targets
  - `CHECK_TARGET_MEMBERSHIP.md` - Verifying target membership
  - `FIX_TARGET_MEMBERSHIP.md` - Fixing membership issues

- **[Implementation](./docs/implementation/)** - Implementation status and samples
  - `IMPLEMENTATION_STATUS.md` - Current implementation status
  - `SAMPLE_WORKOUTS.md` - Sample workout data
  - `VERIFY_FILE_SETUP.md` - File setup verification

## Setup

See [docs/setup/XCODE_SETUP_GUIDE.md](./docs/setup/XCODE_SETUP_GUIDE.md) for detailed Xcode setup instructions.

### Quick Start

1. **Create Xcode Project**
   - iOS App: `AmakaFlow Companion` (iOS 17.0+)
   - watchOS App: `AmakaFlowWatch` (watchOS 10.0+)

2. **Add Package Dependency**
   - Local package: `/Users/davidandrews/dev/workoutkit-sync`

3. **Configure Capabilities**
   - HealthKit (iOS & watchOS)
   - Calendar (iOS only)
   - Watch Connectivity (iOS & watchOS)

4. **Add Files**
   - Copy all Swift files from `AmakaFlow/` to iOS target
   - Copy all Swift files from `AmakaFlowWatch/` to watchOS target

5. **Build and Run**
   - Connect iPhone and Apple Watch
   - Run on physical devices (HealthKit doesn't work in Simulator)

## Dependencies

- **WorkoutKitSync**: Local Swift package at `/Users/davidandrews/dev/workoutkit-sync`
  - Converts workout JSON to Apple WorkoutKit format
  - Handles WorkoutKit API integration

## Services

### WorkoutKitConverter
Converts `Workout` model to `WKPlanDTO` format for WorkoutKitSync.

```swift
let converter = WorkoutKitConverter()
try await converter.saveToWorkoutKit(workout)
```

### WatchConnectivityManager
Manages communication between iPhone and Apple Watch.

```swift
let manager = WatchConnectivityManager.shared
await manager.sendWorkout(workout)
```

### CalendarManager
Schedules workouts to the user's calendar.

```swift
let manager = CalendarManager()
try await manager.scheduleWorkout(
    workout: workout,
    date: scheduledDate,
    time: "14:00"
)
```

## Usage

### Adding a Workout

Currently, the app uses sample data. To add a workout:

1. Open the app
2. Tap **"Add Sample Workout"** (when implemented)
3. View workout details
4. Sync to Watch or Calendar

### Syncing to Apple Watch

1. Open a workout
2. Tap **"Sync to Watch"**
3. Open the Watch app to see the workout
4. Start the workout from the Watch

### Scheduling to Calendar

1. Open a workout
2. Tap **"Schedule to Calendar"**
3. Select date and time
4. Workout is added to Calendar with a 15-minute reminder

## API Integration (Coming Soon)

The app is structured to integrate with the backend APIs:

- **Mapper API**: `http://localhost:8001`
  - `GET /workouts` - Fetch user's workouts
  - `GET /export/apple/{workoutId}` - Get workout in WorkoutKit format

- **Clerk Authentication**: Will be added in future phase

## Development

### Code Quality & Linting

This project uses SwiftLint to enforce code style and catch errors. See [LINTING.md](./LINTING.md) for setup instructions.

**Quick setup:**
```bash
./scripts/setup-linting.sh
```

**Run linting:**
```bash
./scripts/lint.sh
```

### Testing on Device

1. Connect iPhone via USB
2. Select device in Xcode
3. Build and run (Cmd+R)
4. Trust developer certificate on device if prompted

### Testing Watch Connectivity

1. Install iOS app on iPhone
2. Install watchOS app on paired Apple Watch
3. Open both apps
4. Sync a workout from iPhone
5. Verify workout appears in Watch app

### Adding Sample Workouts

See [docs/implementation/SAMPLE_WORKOUTS.md](./docs/implementation/SAMPLE_WORKOUTS.md) for sample workout data in various formats.

## Requirements

- **iOS**: 17.0+ (18.0+ for WorkoutKit)
- **watchOS**: 10.0+ (11.0+ for WorkoutKit)
- **Xcode**: 15.0+
- **Swift**: 5.9+
- **Physical Device**: Required for HealthKit testing

## Troubleshooting

See the [troubleshooting documentation](./docs/troubleshooting/) for common issues and solutions. For setup-related issues, see [docs/setup/XCODE_SETUP_GUIDE.md](./docs/setup/XCODE_SETUP_GUIDE.md).

## Next Steps

1. ✅ Project setup
2. ✅ Basic sync functionality
3. 🚧 Add sample workout data
4. 🚧 API integration
5. 🚧 Clerk authentication
6. 🚧 Full workflow UI

## Resources

- [WorkoutKit Documentation](https://developer.apple.com/documentation/workoutkit)
- [EventKit Guide](https://developer.apple.com/documentation/eventkit)
- [WatchConnectivity](https://developer.apple.com/documentation/watchconnectivity)
- [HealthKit](https://developer.apple.com/documentation/healthkit)

