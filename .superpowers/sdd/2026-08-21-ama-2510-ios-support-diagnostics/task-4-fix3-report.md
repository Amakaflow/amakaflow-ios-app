# AMA-2510 Task 4 fix round 3 report

## Summary

Fixed the remaining P1 from `task-4-fix2-rereview.md`.

Current string-based `DebugLogService` facade messages now use the same body-like omission classifier as legacy migration. That closes the drift where legacy `.general` and `.networkError` bodies were omitted, but current `.general`, `.network`, and `.auth` facade messages could still persist copied response bodies, customer/profile content, health data, or locations.

## Finding resolution

- Replaced the current API-only body omission gate with `shouldOmitDiagnosticBody(_:metadata:)`.
- Routed both `redact(...)` for current events and `redactLegacyEntry(_:)` through that one classifier.
- Kept stable event names unchanged.
- Preserved safe ordinary non-API messages by allowing them through `sanitizeText` when they do not match body-like content.
- Added real facade/account-scoped store tests for:
  - current `.general` log with JSON customer/profile/health/location content;
  - current `.network` log with response-body-like localized error text;
  - current `.auth` log with request/body/profile/health/location content;
  - a safe `.general` operational message that must survive sanitization.

## TDD evidence

RED:

- Initial focused run after adding the new tests:
  - Command: `xcodebuild test -project AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj -scheme AmakaFlowCompanion -configuration Debug -destination "platform=iOS Simulator,name=$SIM_NAME" -derivedDataPath AmakaFlowCompanion/DerivedData -clonedSourcePackagesDirPath AmakaFlowCompanion/.spm -only-testing:AmakaFlowCompanionTests/DiagnosticRedactorTests -only-testing:AmakaFlowCompanionTests/DiagnosticEventStoreTests ...`
  - Result: expected failure, exit 65. The new non-API body-like facade test failed.
- I then corrected one ordering assertion in the test and reran the single test with body omission temporarily disabled to verify the intended failure mode:
  - Command: `xcodebuild test ... -only-testing:AmakaFlowCompanionTests/DiagnosticEventStoreTests/testDebugLogServiceCurrentNonAPIBodyLikeMessagesAreOmittedAcrossFacades ...`
  - Result: expected failure, exit 65.
  - Failure text showed raw current facade messages persisted instead of `Diagnostic body omitted from diagnostics`.

GREEN:

- Final focused Task 4 tests:
  - Command: same focused `xcodebuild test` command above.
  - Result: `** TEST SUCCEEDED **`
  - Result bundle: `AmakaFlowCompanion/DerivedData/Logs/Test/Test-AmakaFlowCompanion-2026.08.22_01-58-24--0500.xcresult`
  - Passed: 18 focused tests across `DiagnosticEventStoreTests` and `DiagnosticRedactorTests`.

## Verification

- Existing support diagnostics tests:
  - Command: `xcodebuild test ... -only-testing:AmakaFlowCompanionTests/SupportDiagnosticsProbeTests -only-testing:AmakaFlowCompanionTests/SupportDiagnosticsEntryTests -only-testing:AmakaFlowCompanionTests/SupportDiagnosticsSessionTests -only-testing:AmakaFlowCompanionTests/SupportDiagnosticsAccessClientTests ...`
  - Result: `** TEST SUCCEEDED **`
  - Result bundle: `AmakaFlowCompanion/DerivedData/Logs/Test/Test-AmakaFlowCompanion-2026.08.22_02-00-05--0500.xcresult`
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
  - Inspected the final delta and the full Task 4 diff from base commit `1717a94908001ab9ecb97cf4dcebfc83ff29263a`. The relevant final delta is limited to `DiagnosticRedactor.swift` and `DiagnosticEventStoreTests.swift`.

## Commit

- `3f3f14129a5eded7ab6739fbaa46f2f6b51f77d8` - `AMA-2510 omit body-like diagnostic facade messages`

## Concerns

- Verification still emits pre-existing project warnings for duplicate test compile-source entries, the Sentry upload script lacking outputs, and a share extension `CFBundleVersion` mismatch. I did not change those because they are outside Task 4.
