# AMA-2387 — Task 3 report: Apple Health primer + HealthKit stub

**Status: CODE DONE** (XCTest blocked by CoreSimulator hang; arm64 compile succeeded)

## Built
- `ActualsCopy` primer strings + WHY tags (JSX lock)
- `ActualsHealthKitConnecting` + `LiveActualsHealthKitConnector` + `MockActualsHealthKitConnector`
- `ActualsAppleHealthConnectAction` (grant → markConnected; deny → noop; needsSettings → open Settings)
- `ActualsAppleHealthPrimerView` — Continue → HK requestAuthorization (read: workouts/HR/activeEnergy)
- Connect Sources Apple row → primer; denied retry → `UIApplication.openSettingsURLString`
- Tests: `ActualsAppleHealthConnectTests`

## Verify
- arm64 `.o` for primer + connector + tests under `/tmp/ama-2387-dd` (16:33–16:39)
- `xcodebuild test` hung on sim install / UITests codesign — not a product failure
