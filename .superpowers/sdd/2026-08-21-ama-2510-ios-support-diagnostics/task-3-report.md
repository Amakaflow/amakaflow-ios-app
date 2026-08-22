# AMA-2510 Task 3 Report: Typed support-diagnostics status probes

## Implementation

- Added typed, immutable, serialization-safe diagnostics domain values:
  - stable `SupportDiagnosticsProbeID` values;
  - stable `SupportDiagnosticsSafeErrorCode` values;
  - `Codable`, `Equatable`, `Sendable` display fields, probe results, availability variants, and snapshots;
  - `SupportDiagnosticsProbeError` for per-probe safe failure reporting.
- Added `SupportDiagnosticsProbeRunner` with concurrent probe execution and independent per-probe timeouts. A probe timeout or failure becomes only that probe's `.unavailable` result and does not cancel sibling probes.
- Added live status probes for the Task 3 categories:
  - app/build/device;
  - configured hostnames;
  - Clerk session summary without token material;
  - bounded reachability/health HEAD probe;
  - WatchConnectivity state;
  - HealthKit authorization by category;
  - sync/completion queue counts, oldest age, and last safe error marker;
  - database schema/migration health;
  - effective grant state;
  - existing correlation IDs.
- Added `SupportDiagnosticsStatusView` to render snapshots, availability states, display fields, safe error codes, and optional correlation IDs.
- Wired the Status row in `SupportDiagnosticsCenterView` to navigate to the Status screen when `.statusRead` is authorized; unauthorized sessions continue to show the locked capability state.
- Added production file references/build entries to `project.pbxproj` only for new production sources. The new test file remains filesystem-synchronized and was not manually added to the test build phase.

## Files

- `AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsProbe.swift`
- `AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsProbeRunner.swift`
- `AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsProbes.swift`
- `AmakaFlow/Views/SupportDiagnostics/SupportDiagnosticsStatusView.swift`
- `AmakaFlow/Views/SupportDiagnostics/SupportDiagnosticsCenterView.swift`
- `AmakaFlowCompanion/AmakaFlowCompanionTests/SupportDiagnosticsProbeTests.swift`
- `AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj/project.pbxproj`

## Tests and verification

### RED

Command:

```bash
SIM_NAME=$(xcrun simctl list devices available | awk '!found && match($0, /iPhone [^(]*/) {name = substr($0, RSTART, RLENGTH); sub(/[[:space:]]+$/, "", name); print name; found = 1}'); xcrun simctl boot "$SIM_NAME" || true; xcrun simctl bootstatus "$SIM_NAME" -b; xcodebuild test -project AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj -scheme AmakaFlowCompanion -configuration Debug -destination "platform=iOS Simulator,name=$SIM_NAME" -derivedDataPath AmakaFlowCompanion/DerivedData -clonedSourcePackagesDirPath AmakaFlowCompanion/.spm -only-testing:AmakaFlowCompanionTests/SupportDiagnosticsProbeTests -enableCodeCoverage NO CLERK_PUBLISHABLE_KEY_DEV="pk_test_c29saWQtY2hpY2tlbi01MC5jbGVyay5hY2NvdW50cy5kZXYk" CLERK_PUBLISHABLE_KEY_STAGING="pk_test_cnVsaW5nLW1pdGUtODQuY2xlcmsuYWNjb3VudHMuZGV2JA" CLERK_PUBLISHABLE_KEY_PRODUCTION="pk_test_cnVsaW5nLW1pdGUtODQuY2xlcmsuYWNjb3VudHMuZGV2JA"
```

Relevant output:

```text
Testing failed:
    Cannot find type 'SupportDiagnosticsDisplayField' in scope
    Cannot find type 'SupportDiagnosticsProbeError' in scope
    Cannot find type 'SupportDiagnosticsProbeID' in scope
    Cannot find type 'SupportDiagnosticsProbe' in scope
    Cannot find 'SupportDiagnosticsProbeRunner' in scope
    Cannot find 'SupportDiagnosticsSnapshot' in scope
    Cannot find 'SupportDiagnosticsProbeResult' in scope
    Testing cancelled because the build failed.

** TEST FAILED **
```

xcresult:

```text
AmakaFlowCompanion/DerivedData/Logs/Test/Test-AmakaFlowCompanion-2026.08.21_20-58-28--0500.xcresult
```

### GREEN before final safety adjustment

Focused probe tests passed after the first implementation.

Relevant output:

```text
** TEST SUCCEEDED **
Test suite 'SupportDiagnosticsProbeTests' started
Test case 'SupportDiagnosticsProbeTests.testRunnerKeepsSiblingResultWhenOneProbeThrowsSafeError()' passed
Test case 'SupportDiagnosticsProbeTests.testRunnerTurnsOnlyTimedOutProbeUnavailable()' passed
Test case 'SupportDiagnosticsProbeTests.testSnapshotCodableRoundTripPreservesAvailabilityVariants()' passed
```

xcresult:

```text
AmakaFlowCompanion/DerivedData/Logs/Test/Test-AmakaFlowCompanion-2026.08.21_21-03-45--0500.xcresult
```

Relevant existing diagnostics tests plus probe tests also passed.

Command:

```bash
SIM_NAME=$(xcrun simctl list devices available | awk '!found && match($0, /iPhone [^(]*/) {name = substr($0, RSTART, RLENGTH); sub(/[[:space:]]+$/, "", name); print name; found = 1}'); xcrun simctl boot "$SIM_NAME" || true; xcrun simctl bootstatus "$SIM_NAME" -b; xcodebuild test -project AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj -scheme AmakaFlowCompanion -configuration Debug -destination "platform=iOS Simulator,name=$SIM_NAME" -derivedDataPath AmakaFlowCompanion/DerivedData -clonedSourcePackagesDirPath AmakaFlowCompanion/.spm -only-testing:AmakaFlowCompanionTests/SupportDiagnosticsAccessClientTests -only-testing:AmakaFlowCompanionTests/SupportDiagnosticsEntryTests -only-testing:AmakaFlowCompanionTests/SupportDiagnosticsSessionTests -only-testing:AmakaFlowCompanionTests/SupportDiagnosticsProbeTests -enableCodeCoverage NO CLERK_PUBLISHABLE_KEY_DEV="pk_test_c29saWQtY2hpY2tlbi01MC5jbGVyay5hY2NvdW50cy5kZXYk" CLERK_PUBLISHABLE_KEY_STAGING="pk_test_cnVsaW5nLW1pdGUtODQuY2xlcmsuYWNjb3VudHMuZGV2JA" CLERK_PUBLISHABLE_KEY_PRODUCTION="pk_test_cnVsaW5nLW1pdGUtODQuY2xlcmsuYWNjb3VudHMuZGV2JA"
```

Relevant output:

```text
** TEST SUCCEEDED **
Test suite 'SupportDiagnosticsEntryTests' started
... 9 Entry tests passed
Test suite 'SupportDiagnosticsProbeTests' started
... 3 Probe tests passed
Test suite 'SupportDiagnosticsAccessClientTests' started
... 4 AccessClient tests passed
Test suite 'SupportDiagnosticsSessionTests' started
... 7 Session tests passed
```

xcresult:

```text
AmakaFlowCompanion/DerivedData/Logs/Test/Test-AmakaFlowCompanion-2026.08.21_21-06-28--0500.xcresult
```

### Final source-state verification

After self-review, the Clerk probe was tightened to avoid even checking bearer-token cache presence. Post-change simulator test execution twice reached build/signing and then stalled during app launch, so those interrupted runs are not counted as green test evidence.

Interrupted focused test result:

```text
** TEST INTERRUPTED **
Failed to launch app with identifier: com.myamaka.AmakaFlowCompanion
error = Error Domain=NSMachErrorDomain Code=-308 "(ipc/mig) server died"
```

xcresult:

```text
AmakaFlowCompanion/DerivedData/Logs/Test/Test-AmakaFlowCompanion-2026.08.21_21-22-32--0500.xcresult
```

Final source-state build-for-testing passed:

Command:

```bash
SIM_NAME=$(xcrun simctl list devices available | awk '!found && match($0, /iPhone [^(]*/) {name = substr($0, RSTART, RLENGTH); sub(/[[:space:]]+$/, "", name); print name; found = 1}'); xcodebuild build-for-testing -project AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj -scheme AmakaFlowCompanion -configuration Debug -destination "platform=iOS Simulator,name=$SIM_NAME" -derivedDataPath AmakaFlowCompanion/DerivedData -clonedSourcePackagesDirPath AmakaFlowCompanion/.spm -enableCodeCoverage NO CLERK_PUBLISHABLE_KEY_DEV="pk_test_c29saWQtY2hpY2tlbi01MC5jbGVyay5hY2NvdW50cy5kZXYk" CLERK_PUBLISHABLE_KEY_STAGING="pk_test_cnVsaW5nLW1pdGUtODQuY2xlcmsuYWNjb3VudHMuZGV2JA" CLERK_PUBLISHABLE_KEY_PRODUCTION="pk_test_cnVsaW5nLW1pdGUtODQuY2xlcmsuYWNjb3VudHMuZGV2JA"
```

Relevant output:

```text
** TEST BUILD SUCCEEDED **
```

Static checks on final source state:

```bash
swiftlint lint --strict --baseline .swiftlint-baseline.yml --use-alternative-excluding --quiet AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsProbe.swift AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsProbeRunner.swift AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsProbes.swift AmakaFlow/Views/SupportDiagnostics/SupportDiagnosticsStatusView.swift AmakaFlow/Views/SupportDiagnostics/SupportDiagnosticsCenterView.swift
```

Output:

```text
warning: Found a configuration for 'line_length' rule, but it is disabled in 'disabled_rules'.
```

Exit code: 0.

```bash
plutil -lint AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj/project.pbxproj
```

Output:

```text
AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj/project.pbxproj: OK
```

```bash
git diff --check
```

Output: none. Exit code: 0.

## Self-review

- Confirmed all new status output is typed and `Codable`/`Sendable`; no `[String: Any]` or contradictory optional bags were introduced.
- Confirmed probe errors/timeouts are modeled as per-probe unavailable results and do not cancel sibling probes.
- Confirmed live framework/service adapters summarize at the edge and the runner/result model is framework-free.
- Confirmed status categories stay within the Task 3 list.
- Confirmed no raw HealthKit samples, JWT bodies, claims, database rows, authorization headers, cookies, exact locations, URL query values, or request/response bodies are exposed.
- Removed the initial "Cached bearer token" boolean because it touched token-cache state unnecessarily.
- Confirmed `project.pbxproj` changes add only new production source references/build entries.
- Confirmed the new test file is not explicitly added to the synchronized test build phase.

## Concerns

- Final post-adjustment test execution is blocked by a simulator launch failure (`NSMachErrorDomain Code=-308`, `waiting for workers to materialize`). The final source builds for testing successfully, and the same focused plus diagnostics test selection passed before the final one-line Clerk safety tightening.
- xcodebuild still emits existing project warnings, including generated Swift concurrency warnings and duplicate synchronized test build-file warnings. These are outside Task 3 scope and were not changed.
