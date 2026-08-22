# AMA-2510 Task 5 Re-review

Result: CHANGES REQUESTED

Reviewed fix range `0349fa15..4159ce68` and full Task 5 production range `33690f92..4159ce68`.

## Findings

1. MUST-FIX: account-scoped diagnostic reads can still return the previous account if the signed-in account changes during the final store snapshot await.

   Evidence: `diagnosticEventsForCurrentAccount()` now recomputes scope from `accountIdentifierProvider()` and rechecks after pending writes at `AmakaFlow/Services/DebugLogService+Persistence.swift:18-42`, but it then directly returns `try await store.snapshot(.account(accountHash))` at `AmakaFlow/Services/DebugLogService+Persistence.swift:43`. `DiagnosticEventStore` is an actor and `snapshot(_:)` is async at `AmakaFlow/Services/SupportDiagnostics/DiagnosticEventStore.swift:8` and `AmakaFlow/Services/SupportDiagnostics/DiagnosticEventStore.swift:55`, so the main actor can process an auth/account change while the store snapshot is in flight. Because there is no post-snapshot provider/current-hash check, the method can return events for `accountHash` even after `accountIdentifierProvider()` has changed.

   Why this matters: this is still the privacy boundary for logs and bundle preview. The SwiftUI load token checks compare against `SupportDiagnosticsViewModel.currentAccountID` at `AmakaFlow/Views/SupportDiagnostics/SupportDiagnosticsLogsView.swift:102-110` and `AmakaFlow/Views/SupportDiagnostics/DiagnosticBundlePreviewView.swift:122-130`, which is useful after the view model observes the account transition. It does not close the lower-level provider/Combine race where `DebugLogService` can see the account truth change before the view model state has caught up. The original review explicitly called out stale account reads during provider/Combine races; the fix closes the race before and across pending writes, but not across the final awaited persistence read.

   Fix: load into a local value, then re-read `accountIdentifierProvider()` and validate both the hash and `currentAccountHash` again after `await store.snapshot(.account(accountHash))`. If either no longer matches, call `accountIdentifierDidChange(latestAccountIdentifier)` as needed and return `[]`. Add a deterministic regression test that changes the provider while the store snapshot await is suspended, not only before entering `diagnosticEventsForCurrentAccount()`.

## Original findings status

- Finding 1, in-flight logs/preview after authorization or account changes: resolved at the view/policy layer. Logs capture a typed token, clear content when the token becomes nil, reload on token changes, and accept results only when the token still matches current state/account at `AmakaFlow/Views/SupportDiagnostics/SupportDiagnosticsLogsView.swift:40-53` and `AmakaFlow/Views/SupportDiagnostics/SupportDiagnosticsLogsView.swift:92-121`. Preview applies the same token gating and also rejects snapshots whose frozen authorization no longer matches current authorization at `AmakaFlow/Views/SupportDiagnostics/DiagnosticBundlePreviewView.swift:40-53`, `AmakaFlow/Views/SupportDiagnostics/DiagnosticBundlePreviewView.swift:110-142`, and `AmakaFlow/Services/SupportDiagnostics/DiagnosticBundleSnapshot.swift:188-199`.
- Finding 2, stale cached account hash: partially resolved. The fix recomputes the current account and rechecks after `writeTail`, `migrationTask`, and `accountLoadTask` at `AmakaFlow/Services/DebugLogService+Persistence.swift:18-42`, and the new test covers stale cached state before the call at `AmakaFlowCompanion/AmakaFlowCompanionTests/DebugLogServiceDiagnosticScopeTests.swift:7-37`. The remaining finding above is the unguarded final store snapshot await.
- Finding 3, hardcoded empty actions: resolved. `DiagnosticActionSnapshotProviding` is explicit and injectable at `AmakaFlow/Services/SupportDiagnostics/DiagnosticBundleSnapshot.swift:233-240`, and `LiveDiagnosticBundleSnapshotProvider` requires an event provider while making the empty action provider an intentionally named default at `AmakaFlow/Services/SupportDiagnostics/DiagnosticBundleSnapshot.swift:247-267`. The action-free Task 5 default is no longer hidden inside the bundle provider implementation.

## Verification performed

- Read the original review, fix report, task brief, progress ledger, and relevant approved spec sections.
- Inspected fix diff `0349fa15..4159ce68` and re-reviewed the full Task 5 production result `33690f92..4159ce68`.
- Ran focused tests with isolated DerivedData after the shared DerivedData build database was locked:
  `xcodebuild test -project AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj -scheme AmakaFlowCompanion -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath /tmp/ama2510-task5-rereview-derived-* -clonedSourcePackagesDirPath AmakaFlowCompanion/.spm -only-testing:AmakaFlowCompanionTests/DiagnosticLoadAuthorizationTests -only-testing:AmakaFlowCompanionTests/DebugLogServiceDiagnosticScopeTests -enableCodeCoverage NO -parallel-testing-enabled NO -quiet`
  Result: exit code 0. The first attempt against `AmakaFlowCompanion/DerivedData` failed before testing because the shared Xcode build database was locked.
- Ran `git diff --check 0349fa15..4159ce68`: pass.
- Ran `plutil -lint AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj/project.pbxproj`: pass.
- Checked changed Swift file lengths: all are under 300 lines.
- Checked sensitive-term matches in changed diagnostics files. Matches were limited to the intentional excluded-category labels in preview code/tests.
- Checked test discovery risk. The project uses `PBXFileSystemSynchronizedRootGroup` for `AmakaFlowCompanionTests`, so the new test files do not require explicit per-file project entries.
