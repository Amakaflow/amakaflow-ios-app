# watchOS Tests CI job is broken (TEST EXECUTE FAILED)

> **Filed:** 2026-05-06 during AMA-1751 PR #170 review.
> **Severity:** medium (CI gate hides a class of regressions but doesn't block local dev).
> **Suggested ticket:** AMA-CI-watchos-broken.

---

## Symptom

The PR-only workflow `PR iOS & watchOS Tests (Impacted)` watchOS job consistently fails with:

```
** TEST EXECUTE FAILED **
```

…and ~13 tests reporting `failed in 0.000 seconds`:

- `MotionCaptureTests.*` (7 tests)
- `FormInferenceTests.*` (3 tests)
- `HapticCoachTests.*` (3 tests)
- Sometimes `DayStateViewModelTests.handleDayStateUpdateClearsLoadingAndError` (passes on retry within the same run)

The pattern is the test runner crashing before the test method body executes — not real assertion failures.

## Confirmed not caused by recent code

PR #170 (`fix(AMA-1751): Watch completions persist via transferUserInfo`) is the surface that re-exposed this. Its only Watch-side change is `StandaloneWorkoutEngine.swift` (swap `sendMessage` → `transferUserInfo`). The failing tests live in `AmakaFlowWatch Watch AppTests/` and exercise CoreMotion / form-feedback code that #170 doesn't touch.

The failing tests were last modified in AMA-525 (PR #85, "Wearable form feedback spike"). The watchOS Tests workflow runs **only on PRs that touch Watch code**, so the broken state has been hiding for any PR that didn't trigger the path. Most MVP PRs don't touch the Watch app, so the broken state went unnoticed.

## Probable causes (rank-ordered)

1. **`@MainActor` test classes + sync XCTest lifecycle** — Several failing test classes are declared `@MainActor final class XCTestCase`. Under newer Xcode/Swift toolchains, the implicit MainActor isolation on `setUp()` / per-test methods can interact badly with the test runner's process lifecycle, causing the runner to abort before the body executes. This matches the "0.000 seconds, no assertion message" fingerprint exactly.
2. **CMMotionManager allocation in CI sim sandbox** — `MotionCapture.init` allocates a `CMMotionManager`. In the watchOS simulator inside GH Actions, CoreMotion authorization may abort. Less likely (would still produce some assertion text).
3. **Watch test bundle / target deployment target drift** — If the Watch test target has a different deployment target than the watch app target, the test bundle may fail to load on the runner.

## Recommended investigation path

1. Reproduce locally on a developer's Mac with `xcodebuild test -destination 'generic/platform=watchOS Simulator'`. If broken locally, it's not a CI-only flake.
2. Convert one failing test class (`MotionCaptureTests`) to drop `@MainActor` and use `func setUp() async throws` style. Re-run. If it passes, the @MainActor + sync setUp interaction is the culprit and the fix is mechanical (apply across all watchOS tests).
3. If still broken, capture the runner's crash log from the xcresult bundle (CI archives `WatchTestResults` per the workflow log).

## What this means for current work

- **PR #170 (Bug 2 fix)** is unblocked from a code-correctness perspective: iOS Tests pass, the failing watchOS tests don't exercise the changed file, and the fix has a real-device test plan documented.
- Recommend admin-merge #170 once #169 goes green, plus filing this ticket so a sweep can fix the infra without conflating it with feature work.
- Watch app itself is unaffected — local builds work, the Watch app runs on TestFlight, only the CI test runner is sad.

## Out of scope

- Whether the Watch app should ship in MVP at all (separate scope conversation).
- Replacing watchOS Tests with manual smoke testing (long-term, but doesn't help today).
