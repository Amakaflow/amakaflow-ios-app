# AMA-2510 Task 5 Fix Round 1 Report

## Commits

- Code/tests: `4159ce682811a33399a1402bc4a6229e5e7dc0b6`
- Report: this file, committed separately from code/tests.

## Scope

Resolved all three findings from `task-5-review.md`:

1. Bound async logs and export-preview loads to a typed authorization/account load token captured before `await`, and discarded results if the active grant, capabilities, account, or authorization state changed before completion.
2. Made `DebugLogService.diagnosticEventsForCurrentAccount()` recompute the current account scope from `accountIdentifierProvider()` on every call, synchronize stale cached account state before reading, and fail closed if the account changes while waiting on pending persistence work.
3. Replaced the live bundle provider's hardcoded empty actions with an injected `DiagnosticActionSnapshotProviding` dependency. The Task 5 default is an explicit `ViewerEmptyActionProvider`; injected providers freeze actions in the same snapshot operation as status and events.

## RED evidence

Added behavior tests before implementation:

- `DiagnosticLoadAuthorizationTests`
  - in-flight logs completion after lock is rejected
  - in-flight preview completion after lock is rejected
  - grant A snapshot rejected under grant B
  - authorized-to-authorized grant transition requires reload
  - authorized-to-authorized account transition requires reload
  - injected action provider contributes frozen actions
- `DebugLogServiceDiagnosticScopeTests`
  - stale cached account hash never selects the old account

Initial focused run failed before implementation as expected:

```text
xcodebuild test ... -only-testing:AmakaFlowCompanionTests/DiagnosticLoadAuthorizationTests -only-testing:AmakaFlowCompanionTests/DebugLogServiceDiagnosticScopeTests
Exit code: 65
Cannot find type 'DiagnosticActionSnapshotProviding' in scope
Result bundle: /Users/davidandrews/dev/amakaflow-workspace/amakaflow-ios-app/.worktrees/ama-2510-support-diagnostics/AmakaFlowCompanion/DerivedData/Logs/Test/Test-AmakaFlowCompanion-2026.08.22_05-04-42--0500.xcresult
```

## GREEN / verification evidence

Focused Task 5 tests:

```text
xcodebuild test ... -only-testing:AmakaFlowCompanionTests/DiagnosticLoadAuthorizationTests -only-testing:AmakaFlowCompanionTests/DebugLogServiceDiagnosticScopeTests
7 tests passed
Result bundle: /Users/davidandrews/dev/amakaflow-workspace/amakaflow-ios-app/.worktrees/ama-2510-support-diagnostics/AmakaFlowCompanion/DerivedData/Logs/Test/Test-AmakaFlowCompanion-2026.08.22_05-21-00--0500.xcresult
```

Support diagnostics regression set after final account-scope hardening:

```text
xcodebuild test ... -only-testing selected support diagnostics suites
65 tests passed
** TEST SUCCEEDED **
Result bundle: /Users/davidandrews/dev/amakaflow-workspace/amakaflow-ios-app/.worktrees/ama-2510-support-diagnostics/AmakaFlowCompanion/DerivedData/Logs/Test/Test-AmakaFlowCompanion-2026.08.22_05-26-06--0500.xcresult
```

Build:

```text
just ios-build
** TEST BUILD SUCCEEDED **
```

Lint:

```text
just ios-lint
Done linting! Found 0 violations, 0 serious in 692 files.
```

Static checks:

```text
plutil -lint AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj/project.pbxproj
AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj/project.pbxproj: OK

git diff --check
clean
```

Line counts:

```text
130 AmakaFlow/Services/DebugLogService+Persistence.swift
277 AmakaFlow/Services/SupportDiagnostics/DiagnosticBundleSnapshot.swift
138 AmakaFlow/ViewModels/SupportDiagnosticsViewModel.swift
160 AmakaFlow/Views/SupportDiagnostics/DiagnosticBundlePreviewView.swift
175 AmakaFlow/Views/SupportDiagnostics/SupportDiagnosticsLogsView.swift
214 AmakaFlowCompanion/AmakaFlowCompanionTests/DiagnosticBundlePreviewTests.swift
156 AmakaFlowCompanion/AmakaFlowCompanionTests/DiagnosticLoadAuthorizationTests.swift
 38 AmakaFlowCompanion/AmakaFlowCompanionTests/DebugLogServiceDiagnosticScopeTests.swift
```

Privacy/secret scan:

```text
rg -n -i 'bearer|cookie|password|api[_-]?key|request body|response body|database dump|health sample|exact location|unscopedForMigrationOnly|unscoped' <changed Swift files>
```

Results were limited to the intentional excluded-category labels in `DiagnosticBundleSnapshot.swift` and `DiagnosticBundlePreviewTests.swift`:

- `Tokens, auth headers, and cookies`
- `Database dumps and rows`
- `Health samples and values`
- `Exact locations`

No SwiftUI persistence-file access or `.unscopedForMigrationOnly` usage was introduced.

## Files changed

- `AmakaFlow/Services/DebugLogService+Persistence.swift`
- `AmakaFlow/Services/SupportDiagnostics/DiagnosticBundleSnapshot.swift`
- `AmakaFlow/ViewModels/SupportDiagnosticsViewModel.swift`
- `AmakaFlow/Views/SupportDiagnostics/DiagnosticBundlePreviewView.swift`
- `AmakaFlow/Views/SupportDiagnostics/SupportDiagnosticsLogsView.swift`
- `AmakaFlowCompanion/AmakaFlowCompanionTests/DiagnosticBundlePreviewTests.swift`
- `AmakaFlowCompanion/AmakaFlowCompanionTests/DiagnosticLoadAuthorizationTests.swift`
- `AmakaFlowCompanion/AmakaFlowCompanionTests/DebugLogServiceDiagnosticScopeTests.swift`

## Residual risks

- `ViewerEmptyActionProvider` intentionally returns no actions for Task 5. Task 6 must inject a real action provider before serializing completed bundles.
- `just ios-build` still emits pre-existing Swift isolation/deprecation warnings and duplicate test build-file warnings unrelated to this task.
- No ZIP/export/audit/share functionality was implemented in this round.
