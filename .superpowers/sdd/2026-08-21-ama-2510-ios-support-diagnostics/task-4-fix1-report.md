# AMA-2510 Task 4 fix round 1 report

## Summary

Addressed all five independent-review findings against Task 4.

- Stable event names can no longer carry free-form user text. `DiagnosticEvent` now has a separate sanitized display title, and `DebugLogEntry` projection uses that title while preserving stable event names.
- Legacy API migration now omits raw API response/body-like content and preserves only safe allowlisted metadata and correlation fields.
- `DebugLogService` now stamps events with the current account from `AuthViewModel.shared.userProfile?.id`, hashes it through the existing redactor, and scopes load/reload/display/copy output to the current account. Signed-in account reads fail closed for nil legacy account hashes.
- `DiagnosticEventStore.snapshot()` and already-migrated initialization paths now enforce age and size retention, not only append.
- `DebugLogService` writes now use one ordered task chain, so `clearLog()` is ordered after earlier pending appends.

## Per-finding resolution

1. Free-form titles and event names:
   - Added immutable `title` to `DiagnosticEvent`.
   - Kept `name` stable, identifier-safe, and independent from display text.
   - Sanitized display titles and messages before projection, persistence, and copy/export.
   - Added copy/projection coverage for email, bearer token, JWT-shaped text, and queried URLs.

2. Legacy API response/body migration:
   - Added `DiagnosticRedactor.omittedAPIResponseMessage`.
   - Legacy API entries with `Response`, body-like metadata, JSON details, token keys, profile content, or customer content now persist the generic omitted message.
   - Preserved safe fields such as `Status`, normalized endpoint, method, and request correlation.

3. Real account separation:
   - Added an injected account identity provider to `DebugLogService`, defaulting to the existing app auth source.
   - New events are stamped with one-way account hashes.
   - Service snapshots, reloads, displayed entries, and copy/export text are scoped to the current account.
   - Added account-switch behavior coverage proving account B cannot see or copy account A entries.

4. Retention on read/init:
   - Added retention cleanup to `snapshot()` and already-migrated `migrateLegacyIfNeeded()`.
   - Added tests for expiry after clock advance with no write and oversized preexisting storage.

5. Clear versus pending appends:
   - Replaced independent detached writes with a single ordered writer chain.
   - Added `waitForPendingWrites()` as a deterministic drain hook for tests.
   - Added clear-after-many-appends race coverage.

## TDD evidence

RED:

- Focused Task 4 tests before implementation:
  - Command: `xcodebuild test -project AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj -scheme AmakaFlowCompanion -configuration Debug -destination "platform=iOS Simulator,name=$SIM_NAME" -derivedDataPath AmakaFlowCompanion/DerivedData -clonedSourcePackagesDirPath AmakaFlowCompanion/.spm -only-testing:AmakaFlowCompanionTests/DiagnosticRedactorTests -only-testing:AmakaFlowCompanionTests/DiagnosticEventStoreTests ...`
  - Result: expected failure, exit 65, `DiagnosticRedactorTests.swift:15:27: error: extra argument 'displayTitle' in call`.
- First GREEN attempt exposed the clear race behavior:
  - Result: `DiagnosticEventStoreTests/testClearLogIsOrderedAfterEarlierPendingAppends()` failed with `XCTAssertTrue failed`.
  - Fix: prevented async initial load from repopulating UI state after local log/clear mutation.

GREEN:

- Final focused Task 4 tests:
  - Command: same focused `xcodebuild test` command above.
  - Result: `** TEST SUCCEEDED **`
  - Result bundle: `AmakaFlowCompanion/DerivedData/Logs/Test/Test-AmakaFlowCompanion-2026.08.22_01-20-30--0500.xcresult`
  - Passed: 14 focused tests across `DiagnosticEventStoreTests` and `DiagnosticRedactorTests`.

## Verification

- Existing support diagnostics tests:
  - Command: `xcodebuild test ... -only-testing:AmakaFlowCompanionTests/SupportDiagnosticsProbeTests -only-testing:AmakaFlowCompanionTests/SupportDiagnosticsEntryTests -only-testing:AmakaFlowCompanionTests/SupportDiagnosticsSessionTests -only-testing:AmakaFlowCompanionTests/SupportDiagnosticsAccessClientTests ...`
  - Result: `** TEST SUCCEEDED **`
  - Result bundle: `AmakaFlowCompanion/DerivedData/Logs/Test/Test-AmakaFlowCompanion-2026.08.22_01-23-27--0500.xcresult`
- `just ios-build`
  - Result: `** TEST BUILD SUCCEEDED **`
- `just ios-lint`
  - First result: failed on `DiagnosticRedactor` type body length.
  - Final result: passed, `Found 0 violations, 0 serious in 685 files`.
- `plutil -lint AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj/project.pbxproj`
  - Result: `OK`.
- `git diff --check`
  - Result: passed.
- Changed-file secret scan:
  - Result: matches were redaction regex terms and synthetic test fixtures only. No real secrets found.
- Diff inspection:
  - Inspected the full 1,663-line diff from base commit `1717a94908001ab9ecb97cf4dcebfc83ff29263a`.

## Commit

- `431630f43bcfe5995570263b5d63e718727e152f` - `AMA-2510 harden diagnostic event logging`

## Deviations and concerns

- I did not edit `DebugLogView`; the safety boundary is enforced in `DebugLogService` and the typed store, and the view already consumes the redacted/scoped projection and copy text.
- Verification still emits pre-existing project warnings for duplicate test compile-source entries, the Sentry upload script lacking outputs, and a share extension `CFBundleVersion` mismatch. These were not introduced by this fix.
