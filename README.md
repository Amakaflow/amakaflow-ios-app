# AmakaFlow Companion iOS App

Native iOS + watchOS companion app for AmakaFlow workout planning, follow-along execution, Apple Watch delivery, HealthKit-backed completion, and activity history.

## Current capabilities

- Sync planned workouts and completion state through the mobile BFF/OpenAPI client.
- Deliver and run workouts on Apple Watch with WorkoutKit/WatchConnectivity support.
- Persist local-first workout state with GRDB-backed storage.
- Support Clerk-authenticated staging/dev/prod environments.
- Run unit, UI, and Maestro smoke/evidence flows from CI.

## Repository layout

```text
amakaflow-ios-app/
├── AmakaFlow/                         # Shared app source used by the iOS target
│   ├── Core/                          # App configuration, feature flags, shared utilities
│   ├── DependencyInjection/           # Runtime service wiring
│   ├── Engine/                        # Workout execution/state machine code
│   ├── Generated/                     # Swift OpenAPI client/types generated from Specs/mobile-bff.json
│   ├── Models/                        # App/domain models
│   ├── Services/                      # API, auth, HealthKit, WatchConnectivity, import/transcription services
│   ├── Storage/                       # GRDB migrations and repositories
│   ├── ViewModels/                    # Presentation logic
│   └── Views/                         # SwiftUI screens/components
├── AmakaFlowCompanion/
│   ├── AmakaFlowCompanion.xcodeproj   # Canonical Xcode project entry point
│   ├── AmakaFlowCompanion/            # iOS target app assets/config
│   ├── AmakaFlowCompanionTests/       # Unit/integration tests
│   ├── AmakaFlowCompanionUITests/     # XCUITest critical journeys
│   ├── AmakaFlowShare/                # Share extension target
│   ├── AmakaFlowWatch Watch App/      # watchOS target source/assets
│   ├── AmakaFlowWatch Watch AppTests/ # watchOS tests
│   └── WorkoutLiveActivity/           # Live Activity extension target
├── Specs/                             # Vendored OpenAPI specs and generator config
├── Vendor/ConnectIQ/                  # Vendored Garmin ConnectIQ binary package wrapper
├── e2e/maestro/                       # Maestro flows and reusable subflows
├── docs/                              # Architecture, setup, CI, troubleshooting, and domain docs
└── scripts/                           # Build/test/regeneration helpers
```

> Note: the Xcode project currently lives under `AmakaFlowCompanion/` and references shared source in sibling `../AmakaFlow/...` paths. Open the checked-in project from this repository layout rather than moving the `.xcodeproj` independently.

## Quick start

1. Open the checked-in project:
   ```bash
   open AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj
   ```
2. Let Xcode resolve Swift Package dependencies from the workspace `Package.resolved`.
3. Select the `AmakaFlowCompanion` scheme for iOS or `AmakaFlowWatch Watch App` for watchOS.
4. Build/run on simulator for most UI and model work. Use a physical iPhone/Apple Watch pair for full HealthKit + watch execution validation.

## Dependency management

- Remote Swift Package dependencies are declared in `AmakaFlowCompanion.xcodeproj` and locked at `AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
- Local binary packages such as `Vendor/ConnectIQ` are vendored in-repo.
- Do **not** commit local SwiftPM/Xcode caches such as `AmakaFlowCompanion/.spm/` or `AmakaFlowCompanion/DerivedData/`.
- The generated OpenAPI client in `AmakaFlow/Generated/` is regenerated from `Specs/mobile-bff.json` via:
  ```bash
  ./scripts/regen-openapi-client.sh
  ```

## Testing

Common local commands are run from `AmakaFlowCompanion/`:

```bash
xcodebuild test \
  -project AmakaFlowCompanion.xcodeproj \
  -scheme AmakaFlowCompanion \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Maestro flows live under `e2e/maestro/`; see `e2e/maestro/README.md` for the current smoke/evidence flow layout.

## Documentation

Documentation is organized by subject in `docs/`, including architecture, CI, setup, HealthKit, watchOS, target membership, troubleshooting, and implementation notes. Some historical setup docs are retained for context; prefer this README, CI workflows, and the checked-in Xcode project as the current source of truth.

For staging TestFlight releases (founder/device validation), see `docs/ci/STAGING_TESTFLIGHT_RELEASE.md`.

## Requirements

- iOS 17.0+
- watchOS 10.0+
- Current Xcode toolchain used by CI
- Physical device pair for complete HealthKit/watch validation

## Resources

- [WorkoutKit Documentation](https://developer.apple.com/documentation/workoutkit)
- [EventKit](https://developer.apple.com/documentation/eventkit)
- [WatchConnectivity](https://developer.apple.com/documentation/watchconnectivity)
- [HealthKit](https://developer.apple.com/documentation/healthkit)
