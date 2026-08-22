# AMA-2510 Task 4 Report

## Summary

Implemented the redacted support diagnostic event pipeline:

- Added typed immutable `DiagnosticEvent` storage model with severity, category, stable name, safe message, allowlisted metadata, request/Sentry correlation fields, and one-way hashed account identifiers.
- Added `DiagnosticRedactor` boundary logic for metadata allowlisting, API path normalization, account hashing, and redaction of bearer/auth headers, JWT-shaped values, cookies, emails, URL query values, and known secret formats.
- Added `DiagnosticEventStore` actor backed by Application Support NDJSON storage with serialized writes, immutable redacted snapshots, complete-until-first-user-authentication protection, 7-day / 5 MiB retention, legacy UserDefaults migration, and corrupt-line recovery.
- Reworked `DebugLogService` to preserve existing public logging signatures and `DebugLogEntry` projections while persisting only redacted typed events and no longer storing raw response/body text.
- Confirmed `DebugLogView` already displays/copies through `DebugLogService` redacted projections (`entries`, `getAllEntriesAsText()`, and `entry.copyableText`), so no direct view change was needed.

## Files

- `AmakaFlow/Services/SupportDiagnostics/DiagnosticEvent.swift`
- `AmakaFlow/Services/SupportDiagnostics/DiagnosticRedactor.swift`
- `AmakaFlow/Services/SupportDiagnostics/DiagnosticEventStore.swift`
- `AmakaFlow/Services/DebugLogService.swift`
- `AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj/project.pbxproj`
- `AmakaFlowCompanion/AmakaFlowCompanionTests/DiagnosticRedactorTests.swift`
- `AmakaFlowCompanion/AmakaFlowCompanionTests/DiagnosticEventStoreTests.swift`
- `.superpowers/sdd/2026-08-21-ama-2510-ios-support-diagnostics/task-4-report.md`

## TDD evidence

RED:

- Ran focused new tests before implementation:
  - `xcodebuild test ... -only-testing:AmakaFlowCompanionTests/DiagnosticRedactorTests -only-testing:AmakaFlowCompanionTests/DiagnosticEventStoreTests ...`
  - Result: expected failure, exit 65, missing Task 4 types/symbols such as `DiagnosticRedactor`, `DiagnosticEventStore`, and diagnostic category cases.

GREEN:

- Re-ran focused new tests after implementation and final hardening:
  - `xcodebuild test ... -only-testing:AmakaFlowCompanionTests/DiagnosticRedactorTests -only-testing:AmakaFlowCompanionTests/DiagnosticEventStoreTests ...`
  - Result: `** TEST SUCCEEDED **`
  - Result bundle: `AmakaFlowCompanion/DerivedData/Logs/Test/Test-AmakaFlowCompanion-2026.08.22_00-44-46--0500.xcresult`
  - Passed: 9/9 focused Task 4 tests.

## Verification

- Existing support diagnostics tests:
  - `xcodebuild test ... -only-testing:AmakaFlowCompanionTests/SupportDiagnosticsAccessClientTests -only-testing:AmakaFlowCompanionTests/SupportDiagnosticsSessionTests -only-testing:AmakaFlowCompanionTests/SupportDiagnosticsEntryTests -only-testing:AmakaFlowCompanionTests/SupportDiagnosticsProbeTests ...`
  - Result: `** TEST SUCCEEDED **`
  - Result bundle: `AmakaFlowCompanion/DerivedData/Logs/Test/Test-AmakaFlowCompanion-2026.08.22_00-46-35--0500.xcresult`
  - Passed: 32/32 support diagnostics tests.
- `just ios-build`
  - Result: `** TEST BUILD SUCCEEDED **`
- `git diff --check`
  - Result: passed.
- `plutil -lint AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj/project.pbxproj`
  - Result: `OK`.
- `just ios-lint`
  - Result: passed, `Found 0 violations, 0 serious in 685 files`.
- Changed-file secret scan:
  - Result: only matched synthetic redaction fixtures in tests and the redaction regex itself; no real secrets found in changed files.

## Deviations / concerns

- `DebugLogView.swift` was inspected but not modified. It already consumes the redacted `DebugLogService` projection for display and copy/export paths, so changing it would not improve the safety boundary.
- Simulator file protection attributes can be unavailable on temporary directories, so the store records the successfully applied protection value after setting `.completeUntilFirstUserAuthentication`; production writes still use `.completeFileProtectionUntilFirstUserAuthentication` and set the file attribute explicitly.
- Verification still emits pre-existing project warnings for duplicate test compile-source entries, the Sentry upload script missing outputs, and an app extension `CFBundleVersion` mismatch. These were not introduced by Task 4.

## Commit

- Pending.
