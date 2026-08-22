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

## Fix round 1

### Implementation

- Added app/device distribution type, locale, and timezone fields.
- Added Clerk token-expiry and user-ID-hash fields without parsing token bytes, JWT bodies, or raw claims. The current Clerk SDK surface used here does not report token expiry, so the probe reports the stable value `Not reported by SDK`.
- Expanded bounded reachability checks to the configured mobile BFF, mapper, ingestor, calendar, chat, MCP, and Strava API endpoints. Output remains limited to safe service names, hostnames, status outcomes, and latency.
- Added a typed WatchConnectivity last-transfer summary dependency and safe sanitizer. The live default reports a typed `None recorded` state until a safe recorder is wired.
- Added grant capability wire list, simulation state, and a typed support feature override state. The live default reports typed none rather than scanning arbitrary preferences.
- Replaced the correlation-ID stub with a typed injected provider for already-recorded request/Sentry identifiers. The live default reports typed none until safe recorders are wired.
- Added local SQLite schema version through `PRAGMA user_version`; migration health still reads only schema metadata/counts and does not read customer rows.
- Changed the probe runner timeout race so a timeout returns on time even if the probe ignores cancellation, while sibling probes still complete independently.
- Added injected safe correlation IDs for generic probe failures and timeouts.
- Split the 649-line probe implementation into focused files under `AmakaFlow/Services/SupportDiagnostics`:
  - `SupportDiagnosticsProbes.swift` now owns factory wiring, approved contracts, safe summary helpers, and dependency types.
  - `SupportDiagnosticsEnvironmentProbes.swift` owns app/config/session/reachability/watch probes.
  - `SupportDiagnosticsSystemProbes.swift` owns HealthKit, queue, database, grant, and correlation probes.

### Files changed

- `AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsProbeRunner.swift`
- `AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsProbes.swift`
- `AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsEnvironmentProbes.swift`
- `AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsSystemProbes.swift`
- `AmakaFlowCompanion/AmakaFlowCompanionTests/SupportDiagnosticsProbeTests.swift`
- `AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj/project.pbxproj`

### RED evidence

Command:

```bash
SIM_NAME=$(xcrun simctl list devices available | awk '!found && match($0, /iPhone [^(]*/) {name = substr($0, RSTART, RLENGTH); sub(/[[:space:]]+$/, "", name); print name; found = 1}'); xcrun simctl boot "$SIM_NAME" || true; xcrun simctl bootstatus "$SIM_NAME" -b; xcodebuild test -project AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj -scheme AmakaFlowCompanion -configuration Debug -destination "platform=iOS Simulator,name=$SIM_NAME" -derivedDataPath AmakaFlowCompanion/DerivedData -clonedSourcePackagesDirPath AmakaFlowCompanion/.spm -only-testing:AmakaFlowCompanionTests/SupportDiagnosticsProbeTests -enableCodeCoverage NO CLERK_PUBLISHABLE_KEY_DEV="pk_test_c29saWQtY2hpY2tlbi01MC5jbGVyay5hY2NvdW50cy5kZXYk" CLERK_PUBLISHABLE_KEY_STAGING="pk_test_cnVsaW5nLW1pdGUtODQuY2xlcmsuYWNjb3VudHMuZGV2JA" CLERK_PUBLISHABLE_KEY_PRODUCTION="pk_test_cnVsaW5nLW1pdGUtODQuY2xlcmsuYWNjb3VudHMuZGV2JA"
```

Relevant failing output:

```text
SupportDiagnosticsProbeTests.swift: Extra argument 'correlationIDProvider' in call
SupportDiagnosticsProbeTests.swift: Type 'SupportDiagnosticsProbes' has no member 'approvedLiveFieldLabels'
SupportDiagnosticsProbeTests.swift: Type 'SupportDiagnosticsProbes' has no member 'approvedReachabilityServiceNames'
SupportDiagnosticsProbeTests.swift: Cannot find 'SupportDiagnosticsSafeSummaries' in scope
SupportDiagnosticsProbeTests.swift: Cannot infer contextual base in reference to member 'recorded'
Testing cancelled because the build failed.
** TEST FAILED **
```

xcresult:

```text
AmakaFlowCompanion/DerivedData/Logs/Test/Test-AmakaFlowCompanion-2026.08.21_21-34-56--0500.xcresult
```

### GREEN evidence

Focused probe tests after fixes and file split:

```bash
SIM_NAME=$(xcrun simctl list devices available | awk '!found && match($0, /iPhone [^(]*/) {name = substr($0, RSTART, RLENGTH); sub(/[[:space:]]+$/, "", name); print name; found = 1}'); xcrun simctl boot "$SIM_NAME" || true; xcrun simctl bootstatus "$SIM_NAME" -b; xcodebuild test -project AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj -scheme AmakaFlowCompanion -configuration Debug -destination "platform=iOS Simulator,name=$SIM_NAME" -derivedDataPath AmakaFlowCompanion/DerivedData -clonedSourcePackagesDirPath AmakaFlowCompanion/.spm -only-testing:AmakaFlowCompanionTests/SupportDiagnosticsProbeTests -enableCodeCoverage NO CLERK_PUBLISHABLE_KEY_DEV="pk_test_c29saWQtY2hpY2tlbi01MC5jbGVyay5hY2NvdW50cy5kZXYk" CLERK_PUBLISHABLE_KEY_STAGING="pk_test_cnVsaW5nLW1pdGUtODQuY2xlcmsuYWNjb3VudHMuZGV2JA" CLERK_PUBLISHABLE_KEY_PRODUCTION="pk_test_cnVsaW5nLW1pdGUtODQuY2xlcmsuYWNjb3VudHMuZGV2JA"
```

Relevant output:

```text
** TEST SUCCEEDED **
Test suite 'SupportDiagnosticsProbeTests' started
Test case 'SupportDiagnosticsProbeTests.testApprovedLiveFieldContractCatchesRemovedDistributionLocaleTimezoneAndGrantFields()' passed
Test case 'SupportDiagnosticsProbeTests.testApprovedReachabilityContractCatchesRemovedConfiguredAPIHealthProbeMutation()' passed
Test case 'SupportDiagnosticsProbeTests.testRunnerHardTimeoutCatchesCancellationUnawareProbeMutation()' passed
Test case 'SupportDiagnosticsProbeTests.testRunnerInjectsSafeCorrelationIDForGenericFailuresAndTimeoutsMutation()' passed
Test case 'SupportDiagnosticsProbeTests.testSafeBoundaryContractCatchesRawIdentifierTokenAndMessageFieldsMutation()' passed
... 8 SupportDiagnosticsProbeTests passed
```

xcresult:

```text
AmakaFlowCompanion/DerivedData/Logs/Test/Test-AmakaFlowCompanion-2026.08.21_21-47-44--0500.xcresult
```

Relevant existing diagnostics tests plus probe tests:

```bash
SIM_NAME=$(xcrun simctl list devices available | awk '!found && match($0, /iPhone [^(]*/) {name = substr($0, RSTART, RLENGTH); sub(/[[:space:]]+$/, "", name); print name; found = 1}'); xcrun simctl boot "$SIM_NAME" || true; xcrun simctl bootstatus "$SIM_NAME" -b; xcodebuild test -project AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj -scheme AmakaFlowCompanion -configuration Debug -destination "platform=iOS Simulator,name=$SIM_NAME" -derivedDataPath AmakaFlowCompanion/DerivedData -clonedSourcePackagesDirPath AmakaFlowCompanion/.spm -only-testing:AmakaFlowCompanionTests/SupportDiagnosticsAccessClientTests -only-testing:AmakaFlowCompanionTests/SupportDiagnosticsEntryTests -only-testing:AmakaFlowCompanionTests/SupportDiagnosticsSessionTests -only-testing:AmakaFlowCompanionTests/SupportDiagnosticsProbeTests -enableCodeCoverage NO CLERK_PUBLISHABLE_KEY_DEV="pk_test_c29saWQtY2hpY2tlbi01MC5jbGVyay5hY2NvdW50cy5kZXYk" CLERK_PUBLISHABLE_KEY_STAGING="pk_test_cnVsaW5nLW1pdGUtODQuY2xlcmsuYWNjb3VudHMuZGV2JA" CLERK_PUBLISHABLE_KEY_PRODUCTION="pk_test_cnVsaW5nLW1pdGUtODQuY2xlcmsuYWNjb3VudHMuZGV2JA"
```

Relevant output:

```text
** TEST SUCCEEDED **
Test suite 'SupportDiagnosticsEntryTests' started
... 9 Entry tests passed
Test suite 'SupportDiagnosticsProbeTests' started
... 8 Probe tests passed
Test suite 'SupportDiagnosticsAccessClientTests' started
... 4 AccessClient tests passed
Test suite 'SupportDiagnosticsSessionTests' started
... 7 Session tests passed
```

xcresult:

```text
AmakaFlowCompanion/DerivedData/Logs/Test/Test-AmakaFlowCompanion-2026.08.21_21-50-51--0500.xcresult
```

### Static verification

Line-count split check:

```bash
wc -l AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsProbes.swift AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsEnvironmentProbes.swift AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsSystemProbes.swift
```

Output:

```text
     212 AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsProbes.swift
     233 AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsEnvironmentProbes.swift
     218 AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsSystemProbes.swift
     663 total
```

Strict baseline-aware SwiftLint:

```bash
swiftlint lint --strict --baseline .swiftlint-baseline.yml --use-alternative-excluding --quiet AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsProbe.swift AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsProbeRunner.swift AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsProbes.swift AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsEnvironmentProbes.swift AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsSystemProbes.swift AmakaFlow/Views/SupportDiagnostics/SupportDiagnosticsStatusView.swift AmakaFlow/Views/SupportDiagnostics/SupportDiagnosticsCenterView.swift
```

Output:

```text
warning: Found a configuration for 'line_length' rule, but it is disabled in 'disabled_rules'.
```

Exit code: 0.

Project file:

```bash
plutil -lint AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj/project.pbxproj
```

Output:

```text
AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj/project.pbxproj: OK
```

Whitespace check:

```bash
git diff --check
```

Output: none. Exit code: 0.

### Self-review

- Confirmed the approved live field/category contract includes only Task 3 categories and safe labels.
- Confirmed the new contract tests name the production mutation they catch for app/device fields, reachability services, cancellation-unaware timeout behavior, generic correlation injection, and raw data boundary regressions.
- Confirmed live probes expose safe summaries at the framework/service edge and keep runner/result modeling framework-free.
- Confirmed no raw health samples, JWT bodies, raw claims, authorization headers, cookies, request/response bodies, URL query values, exact locations, or customer table contents are rendered by the new probes.
- Confirmed generic timeout and failure results receive an injected safe correlation ID when available.
- Confirmed `project.pbxproj` adds only production source references/build entries for the two split files; no explicit synchronized test build entry was added.

### Concerns

- Clerk token expiry is reported as `Not reported by SDK` because the safe SDK/session metadata used here does not expose expiry; the implementation intentionally does not parse JWT bytes.
- Live correlation IDs, Watch last transfer result, and allowlisted feature overrides default to typed none states until safe recorders/providers are wired outside these owned Task 3 files.
- xcodebuild still emits existing duplicate synchronized test build-file warnings. They are outside this fix scope and were not introduced by the new test file.

## Fix round 2

### Implementation

- Replaced the Clerk token-expiry placeholder with a safe SDK metadata read from `Clerk.shared.session?.expireAt`; no JWT body, token bytes, or raw claims are parsed or rendered.
- Added a thread-safe `SupportDiagnosticsRuntimeState` for privacy-safe request ID, Sentry event ID, Sentry trace ID, fallback correlation ID, and sanitized Watch transfer action/outcome summaries.
- Wired live correlation state from API transport, DebugLogService request IDs, Sentry capture/transaction IDs, and existing DebugLog metadata keys; generic runner failures/timeouts now use the same safe fallback by default and the Status view passes it explicitly.
- Wired WatchConnectivity lifecycle points to record only safe action/outcome states such as `syncWorkouts: queued`; no message payloads, health values, or bodies are stored.
- Added an allowlisted feature override reader that reports only approved override keys from explicit settings/UserDefaults-backed strength auto-capture state and allowlisted process environment names.
- Removed the static approved live field labels map and replaced tests with actual probe execution assertions.
- Kept the probe split under the 300-line guidance after round 2: `SupportDiagnosticsProbes.swift` 297 lines, `SupportDiagnosticsEnvironmentProbes.swift` 268 lines, `SupportDiagnosticsSystemProbes.swift` 229 lines.

### Files changed

- `AmakaFlow/Services/APITransport.swift`
- `AmakaFlow/Services/DebugLogService.swift`
- `AmakaFlow/Services/SentryService.swift`
- `AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsEnvironmentProbes.swift`
- `AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsProbeRunner.swift`
- `AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsProbes.swift`
- `AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsSystemProbes.swift`
- `AmakaFlow/Services/WatchConnectivityManager.swift`
- `AmakaFlow/Views/SupportDiagnostics/SupportDiagnosticsStatusView.swift`
- `AmakaFlowCompanion/AmakaFlowCompanionTests/SupportDiagnosticsProbeTests.swift`

### RED evidence

Focused probe tests failed before production implementation with the new round 2 tests in place:

```bash
SIM_NAME=$(xcrun simctl list devices available | awk '!found && match($0, /iPhone [^(]*/) {name = substr($0, RSTART, RLENGTH); sub(/[[:space:]]+$/, "", name); print name; found = 1}'); xcrun simctl boot "$SIM_NAME" || true; xcrun simctl bootstatus "$SIM_NAME" -b; xcodebuild test -project AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj -scheme AmakaFlowCompanion -configuration Debug -destination "platform=iOS Simulator,name=$SIM_NAME" -derivedDataPath AmakaFlowCompanion/DerivedData -clonedSourcePackagesDirPath AmakaFlowCompanion/.spm -only-testing:AmakaFlowCompanionTests/SupportDiagnosticsProbeTests -enableCodeCoverage NO CLERK_PUBLISHABLE_KEY_DEV="..." CLERK_PUBLISHABLE_KEY_STAGING="..." CLERK_PUBLISHABLE_KEY_PRODUCTION="..."
```

Relevant output:

```text
Cannot find 'SupportDiagnosticsRuntimeState' in scope
Cannot find 'SupportDiagnosticsClerkSessionState' in scope
Extra argument 'simulationState' in call
Cannot find 'SupportDiagnosticsFeatureOverrideReader' in scope
Testing cancelled because the build failed.
** TEST FAILED **
```

After the first implementation pass, focused tests compiled but two formatter assertions failed, proving the live probe assertions were executing actual output rather than a static label dictionary:

```text
Test case 'SupportDiagnosticsProbeTests.testActualProbeOutputsCatchStaticContractOnlyMutation()' failed
XCTAssertEqual failed: ("Optional("program_wizard_enabled")") is not equal to ("Optional("program_wizard=enabled")")
Test case 'SupportDiagnosticsProbeTests.testAllowlistedFeatureOverrideReaderCatchesArbitraryDefaultsScanMutation()' failed
XCTAssertEqual failed: ("non_mvp_disabled, program_wizard_enabled, strength_auto_capture_enabled") is not equal to ("non_mvp=disabled, program_wizard=enabled, strength_auto_capture=enabled")
** TEST FAILED **
```

### GREEN evidence

Focused probe tests:

```bash
SIM_NAME=$(xcrun simctl list devices available | awk '!found && match($0, /iPhone [^(]*/) {name = substr($0, RSTART, RLENGTH); sub(/[[:space:]]+$/, "", name); print name; found = 1}'); xcrun simctl boot "$SIM_NAME" || true; xcrun simctl bootstatus "$SIM_NAME" -b; xcodebuild test -project AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj -scheme AmakaFlowCompanion -configuration Debug -destination "platform=iOS Simulator,name=$SIM_NAME" -derivedDataPath AmakaFlowCompanion/DerivedData -clonedSourcePackagesDirPath AmakaFlowCompanion/.spm -only-testing:AmakaFlowCompanionTests/SupportDiagnosticsProbeTests -enableCodeCoverage NO CLERK_PUBLISHABLE_KEY_DEV="..." CLERK_PUBLISHABLE_KEY_STAGING="..." CLERK_PUBLISHABLE_KEY_PRODUCTION="..."
```

Output:

```text
** TEST SUCCEEDED **
Test suite 'SupportDiagnosticsProbeTests' started
... 11 Probe tests passed
```

Final focused rerun after SwiftLint fixes:

```text
Test session results:
AmakaFlowCompanion/DerivedData/Logs/Test/Test-AmakaFlowCompanion-2026.08.21_22-15-47--0500.xcresult
** TEST SUCCEEDED **
... 11 Probe tests passed
```

Four-class diagnostics selection:

```bash
SIM_NAME=$(xcrun simctl list devices available | awk '!found && match($0, /iPhone [^(]*/) {name = substr($0, RSTART, RLENGTH); sub(/[[:space:]]+$/, "", name); print name; found = 1}'); xcrun simctl boot "$SIM_NAME" || true; xcrun simctl bootstatus "$SIM_NAME" -b; xcodebuild test -project AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj -scheme AmakaFlowCompanion -configuration Debug -destination "platform=iOS Simulator,name=$SIM_NAME" -derivedDataPath AmakaFlowCompanion/DerivedData -clonedSourcePackagesDirPath AmakaFlowCompanion/.spm -only-testing:AmakaFlowCompanionTests/SupportDiagnosticsAccessClientTests -only-testing:AmakaFlowCompanionTests/SupportDiagnosticsEntryTests -only-testing:AmakaFlowCompanionTests/SupportDiagnosticsSessionTests -only-testing:AmakaFlowCompanionTests/SupportDiagnosticsProbeTests -enableCodeCoverage NO CLERK_PUBLISHABLE_KEY_DEV="..." CLERK_PUBLISHABLE_KEY_STAGING="..." CLERK_PUBLISHABLE_KEY_PRODUCTION="..."
```

Output:

```text
** TEST SUCCEEDED **
... 9 Entry tests passed
... 11 Probe tests passed
... 4 AccessClient tests passed
... 7 Session tests passed
```

xcresult:

```text
AmakaFlowCompanion/DerivedData/Logs/Test/Test-AmakaFlowCompanion-2026.08.21_22-12-59--0500.xcresult
```

### Static verification

Line-count split check:

```bash
wc -l AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsProbes.swift AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsEnvironmentProbes.swift AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsSystemProbes.swift
```

Output:

```text
     297 AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsProbes.swift
     268 AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsEnvironmentProbes.swift
     229 AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsSystemProbes.swift
     794 total
```

Strict baseline-aware SwiftLint:

```bash
swiftlint lint --strict --baseline .swiftlint-baseline.yml --use-alternative-excluding --quiet AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsProbe.swift AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsProbeRunner.swift AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsProbes.swift AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsEnvironmentProbes.swift AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsSystemProbes.swift AmakaFlow/Views/SupportDiagnostics/SupportDiagnosticsStatusView.swift AmakaFlow/Views/SupportDiagnostics/SupportDiagnosticsCenterView.swift AmakaFlow/Services/APITransport.swift AmakaFlow/Services/DebugLogService.swift AmakaFlow/Services/SentryService.swift AmakaFlow/Services/WatchConnectivityManager.swift
```

Output:

```text
warning: Found a configuration for 'line_length' rule, but it is disabled in 'disabled_rules'.
```

Exit code: 0.

Project file:

```bash
plutil -lint AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj/project.pbxproj
```

Output:

```text
AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj/project.pbxproj: OK
```

Whitespace check:

```bash
git diff --check
```

Output: none. Exit code: 0.

### Self-review

- Confirmed Clerk expiry uses SDK `Session.expireAt` metadata and does not parse JWT bytes or claims.
- Confirmed only request IDs, Sentry IDs, and sanitized Watch action/outcome strings are recorded for diagnostics.
- Confirmed generic probe failures/timeouts receive a safe default correlation ID in both direct runner use and the live Status view.
- Confirmed the allowlisted override reader does not scan arbitrary UserDefaults keys.
- Confirmed actual probe-output tests cover app/device fields, Clerk expiry/hash, Watch last transfer, grant capability/simulation/override state, correlation IDs, and forbidden-content absence.
- Confirmed integration changes do not render raw health samples, token bodies, claims, database rows, URL query values, authorization headers, cookies, exact locations, request bodies, response bodies, or log messages.

### Concerns

- xcodebuild still emits existing generated-code actor-isolation warnings and duplicate synchronized test build-file warnings outside this task scope.
