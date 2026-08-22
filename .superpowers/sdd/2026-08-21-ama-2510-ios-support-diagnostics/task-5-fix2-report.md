# AMA-2510 Task 5 Fix 2 Report

## Commits

- Code/tests: `ebd42596a8b26562916d541be5d24cdffabadfc2`

## Issue resolved

`DebugLogService.diagnosticEventsForCurrentAccount()` could still return previous-account diagnostic events if account truth changed while the final awaited account-scoped snapshot read was suspended.

The fix keeps the snapshot result in a local value, then re-reads `accountIdentifierProvider()` after the await and validates both:

- the recomputed account hash from current auth truth; and
- `currentAccountHash`.

If either no longer matches the scope used for the snapshot, the service synchronizes account state with current truth and returns `[]`.

## TDD RED evidence

Added deterministic behavior coverage in `DebugLogServiceDiagnosticScopeTests.testDiagnosticEventsForCurrentAccountFailsClosedWhenAccountChangesDuringSnapshotRead`.

Before the production fix, the focused test failed against the existing implementation:

```text
xcodebuild test -project AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj -scheme AmakaFlowCompanion -destination 'platform=iOS Simulator,id=ADCB2229-907A-4CD5-84F3-4EE185464CF4' -derivedDataPath AmakaFlowCompanion/DerivedData -only-testing:AmakaFlowCompanionTests/DebugLogServiceDiagnosticScopeTests/testDiagnosticEventsForCurrentAccountFailsClosedWhenAccountChangesDuringSnapshotRead
** TEST FAILED **
Test case 'DebugLogServiceDiagnosticScopeTests.testDiagnosticEventsForCurrentAccountFailsClosedWhenAccountChangesDuringSnapshotRead()' failed ... (1.609 seconds)
```

Failure details from the xcresult showed the exact leak:

```text
XCTAssertEqual failed: ("[AmakaFlowCompanion.DiagnosticEvent(... name: "account-a", title: "account-a", message: "account-a-detail", ... accountHash: Optional("sha256:fc164f8250803ea8d41834f1de85821035d27d3747e83610789e0f8e5313b9c3"))]") is not equal to ("[]")
XCTAssertEqual failed: ("Optional("sha256:fc164f8250803ea8d41834f1de85821035d27d3747e83610789e0f8e5313b9c3")") is not equal to ("Optional("sha256:21c2f07264873c61880586ab9ba7227b10e8451d7b028ce0e09402f2e79101ca")")
```

RED xcresult:

```text
AmakaFlowCompanion/DerivedData/Logs/Test/Test-AmakaFlowCompanion-2026.08.22_05-53-31--0500.xcresult
```

I also hit one earlier harness stall before routing the public method through the injected snapshot seam. I terminated only that hung focused `xcodebuild` and then proved RED with the deterministic seam above. The final harness now tears down any outstanding continuation via `cancelOutstandingWaiters()`.

## GREEN and verification evidence

Focused fix2 regression:

```text
xcodebuild test ... -only-testing:AmakaFlowCompanionTests/DebugLogServiceDiagnosticScopeTests/testDiagnosticEventsForCurrentAccountFailsClosedWhenAccountChangesDuringSnapshotRead
** TEST SUCCEEDED **
Test case 'DebugLogServiceDiagnosticScopeTests.testDiagnosticEventsForCurrentAccountFailsClosedWhenAccountChangesDuringSnapshotRead()' passed ... (0.767 seconds)
```

Final focused xcresult:

```text
AmakaFlowCompanion/DerivedData/Logs/Test/Test-AmakaFlowCompanion-2026.08.22_06-00-55--0500.xcresult
```

Task 5 focused suite:

```text
xcodebuild test ... -only-testing:AmakaFlowCompanionTests/DiagnosticLoadAuthorizationTests -only-testing:AmakaFlowCompanionTests/DebugLogServiceDiagnosticScopeTests -only-testing:AmakaFlowCompanionTests/DiagnosticBundlePreviewTests
** TEST SUCCEEDED **
16 selected test cases passed
```

Diagnostics regression selection:

```text
xcodebuild test ... SupportDiagnostics/Diagnostic selected suites
** TEST SUCCEEDED **
66 selected test cases passed
```

The requested 65-test diagnostics selection now reports 66 tests because it includes this new fix2 regression.

Additional checks:

```text
just ios-build
** TEST BUILD SUCCEEDED **

just ios-lint
warning: Found a configuration for 'line_length' rule, but it is disabled in 'disabled_rules'.
Done linting! Found 0 violations, 0 serious in 692 files.
Running SwiftLint (strict mode with baseline)...

plutil -lint AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj/project.pbxproj
AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj/project.pbxproj: OK

git diff --check
# no output
```

Privacy/secret scan over changed Swift files:

```text
rg -n -i 'bearer|cookie|password|api[_-]?key|request body|response body|database dump|health sample|exact location|unscopedForMigrationOnly|unscoped' \
  AmakaFlow/Services/DebugLogService.swift \
  AmakaFlow/Services/DebugLogService+Persistence.swift \
  AmakaFlowCompanion/AmakaFlowCompanionTests/DebugLogServiceDiagnosticScopeTests.swift
# no output
```

## Files changed

- `AmakaFlow/Services/DebugLogService.swift`
- `AmakaFlow/Services/DebugLogService+Persistence.swift`
- `AmakaFlowCompanion/AmakaFlowCompanionTests/DebugLogServiceDiagnosticScopeTests.swift`

Line counts:

```text
298 AmakaFlow/Services/DebugLogService.swift
140 AmakaFlow/Services/DebugLogService+Persistence.swift
111 AmakaFlowCompanion/AmakaFlowCompanionTests/DebugLogServiceDiagnosticScopeTests.swift
```

## Residual risks

- `DebugLogService.swift` is at 298 lines, leaving very little room under the strict 300-line cap for future edits.
- Existing project warnings remain unrelated: duplicate test compile-source warnings, existing actor-isolation warnings, and an extension `CFBundleVersion` warning during build/test packaging.
