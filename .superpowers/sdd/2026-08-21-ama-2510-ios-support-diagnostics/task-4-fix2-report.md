# AMA-2510 Task 4 fix round 2 report

## Summary

Addressed both remaining P1 findings from `task-4-fix1-rereview.md`.

- Diagnostic display, copy, and export paths now fail closed while auth is unresolved or signed out. Account-scoped reads use an explicit `DiagnosticSnapshotScope.account(hash)` value, and the only unscoped store read is named `unscopedForMigrationOnly`.
- `DebugLogService` now observes the production auth source through `AuthViewModel.shared.$userProfile`, clears its in-memory projection immediately when identity becomes nil or changes, and reloads only the resolved account's events.
- Legacy body omission now applies to every legacy category, not only API entries. JSON, body-like, customer, profile, health, location, payload, request, and response content is replaced with the generic omitted-body message before persistence.

## Per-finding resolution

1. Account display/copy/export scoping:
   - Replaced optional `snapshot(accountHash:)` with `snapshot(_ scope: DiagnosticSnapshotScope)`.
   - Production service wiring now uses the existing auth state, `AuthViewModel.shared.userProfile?.id` plus `AuthViewModel.shared.$userProfile`.
   - The service clears `entries` synchronously on unresolved auth, sign-out, and account changes. It loads after pending writes and migration settle, and only applies the load if the account generation still matches.
   - Added production-path behavior coverage that starts unresolved with stored nil, account A, and account B events, resolves to B through the injected auth-state publisher without manual reload, and proves nil/A entries never appear in `entries` or copy text. The same test covers sign-out and A to B transition clearing before B reloads.

2. Legacy body omission across categories:
   - Removed the API-only condition from legacy body detection.
   - Added generic body signals for exact metadata keys and body-like text, including `json`, `payload`, `profile`, `customer`, `health`, and `location`.
   - Changed the persisted omitted message to `Diagnostic body omitted from diagnostics` so the replacement is category-neutral.
   - Added migration coverage for legacy `.general` and `.networkError` entries containing realistic customer, profile, health, location, JSON, and response body data.

## TDD evidence

RED:

- Focused Task 4 tests after adding the fix-round-2 tests and before implementation:
  - Command: `xcodebuild test -project AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj -scheme AmakaFlowCompanion -configuration Debug -destination "platform=iOS Simulator,name=$SIM_NAME" -derivedDataPath AmakaFlowCompanion/DerivedData -clonedSourcePackagesDirPath AmakaFlowCompanion/.spm -only-testing:AmakaFlowCompanionTests/DiagnosticRedactorTests -only-testing:AmakaFlowCompanionTests/DiagnosticEventStoreTests ...`
  - Result: expected failure, exit 65.
  - Representative failures: missing typed snapshot scope, missing `omittedBodyMessage`, and unsupported `accountIdentifierPublisher` injection.
- First implementation run:
  - Result: new fix-round-2 tests passed, but existing service facade tests failed because they still constructed the service with unresolved auth. I updated those tests to inject resolved account auth state instead of relying on the old unscoped behavior.

GREEN:

- Final focused Task 4 tests:
  - Command: same focused `xcodebuild test` command above.
  - Result: `** TEST SUCCEEDED **`
  - Result bundle: `AmakaFlowCompanion/DerivedData/Logs/Test/Test-AmakaFlowCompanion-2026.08.22_01-40-23--0500.xcresult`
  - Passed: 16 focused tests across `DiagnosticEventStoreTests` and `DiagnosticRedactorTests`.

## Verification

- Existing support diagnostics tests:
  - Command: `xcodebuild test ... -only-testing:AmakaFlowCompanionTests/SupportDiagnosticsProbeTests -only-testing:AmakaFlowCompanionTests/SupportDiagnosticsEntryTests -only-testing:AmakaFlowCompanionTests/SupportDiagnosticsSessionTests -only-testing:AmakaFlowCompanionTests/SupportDiagnosticsAccessClientTests ...`
  - Result: `** TEST SUCCEEDED **`
  - Result bundle: `AmakaFlowCompanion/DerivedData/Logs/Test/Test-AmakaFlowCompanion-2026.08.22_01-42-07--0500.xcresult`
- `just ios-build`
  - Result: `** TEST BUILD SUCCEEDED **`
- `just ios-lint`
  - Result: passed, `Found 0 violations, 0 serious in 685 files`.
- `plutil -lint AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj/project.pbxproj`
  - Result: `OK`.
- `git diff --check`
  - Result: passed.
- Changed-file secret scan:
  - Result: matches were synthetic redaction fixtures in tests and denylist/regex terms in `DiagnosticRedactor`. No production secret literals were found.
- Diff inspection:
  - Inspected the full Task 4 diff from base commit `1717a94908001ab9ecb97cf4dcebfc83ff29263a`. The diff is limited to Task 4 diagnostics code, tests, project integration, and Task 4 reports.

## Commit

- `b375fac1c1c3ab7665d46d0e097e1fd799fece83` - `AMA-2510 fail closed diagnostic account scoping`

## Deviations and concerns

- Verification still emits pre-existing project warnings for duplicate test compile-source entries, the Sentry upload script lacking outputs, and a share extension `CFBundleVersion` mismatch. I did not change those because they are outside Task 4 ownership.
