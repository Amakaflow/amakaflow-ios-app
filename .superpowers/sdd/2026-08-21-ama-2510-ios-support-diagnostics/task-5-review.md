# AMA-2510 Task 5 Review

Range reviewed: `33690f926441944b2d3b9081707939544ddfbef8..a0e53965df609b17d168007410ccd9e1d4e47452`

Result: CHANGES REQUESTED

## Findings

1. MUST-FIX: Loaded log and preview state is not bound to the authorization that produced it.

   `SupportDiagnosticsLogsView.loadEvents()` assigns `events` after an async provider call without rechecking the current session state, grant, or account (`AmakaFlow/Views/SupportDiagnostics/SupportDiagnosticsLogsView.swift:82-98`). The `.task(id: viewModel.state)` path then keeps any non-empty event array on later authorized states because `clearIfLocked()` only clears when `logs.read` is absent and line 41 skips reload when `events` is not empty (`SupportDiagnosticsLogsView.swift:39-42`, `SupportDiagnosticsLogsView.swift:101-108`).

   The preview view has the same issue for snapshots. `loadSnapshot()` assigns `snapshot` after the await without validating that the current authorization is still the same one (`AmakaFlow/Views/SupportDiagnostics/DiagnosticBundlePreviewView.swift:100-118`). On a later authorized state with `bundle.export`, `.task(id:)` does not clear the old snapshot and line 41 skips reload (`DiagnosticBundlePreviewView.swift:39-42`). The policy also accepts any non-nil snapshot as long as the current state has `bundle.export`; it does not compare `snapshot.authorization.grantID` with the active authorization (`AmakaFlow/Services/SupportDiagnostics/DiagnosticBundleSnapshot.swift:125-131`).

   This matters because the spec requires authorization loss and account change to remove sensitive content immediately, and a new signed-in account must not inherit another account's grant or diagnostics. A plausible failure path is: preview loads under grant A, access refresh moves to grant B with `bundle.export`, and the old snapshot remains visible because the view treats the current capability as sufficient. An in-flight load can also repopulate `events` or `snapshot` after a lock because the assignment happens after the only guard.

   Fix by keying loaded content to the state that created it. Capture the grant ID and account scope before starting the async load, re-read state after the await, and discard the result if the token changed or the capability is gone. Also clear and reload on any authorized-to-authorized transition where the grant, capability set, or account changed. For preview, make `DiagnosticBundlePreviewPolicy.preview` require the snapshot authorization to match the active authorization before deriving metadata.

2. MUST-FIX: `diagnosticEventsForCurrentAccount()` can read using a stale cached account hash.

   The new support-diagnostics boundary prefers `currentAccountHash` over hashing the current account provider (`AmakaFlow/Services/DebugLogService+Persistence.swift:18-25`). That means if `AuthViewModel.shared.userProfile` has changed but `DebugLogService` has not processed its Combine account-change callback yet, the method snapshots the previous account's events. Waiting for `writeTail`, `migrationTask`, and `accountLoadTask` helps once the change has been registered, but it does not prove that `currentAccountHash` matches the current signed-in account at the moment the support surface asks for events.

   This is exactly the boundary that Task 5 adds for Logs and Export Preview, so it should fail closed by deriving the scope from the current signed-in account for each diagnostic read. Either accept the account identifier/hash from the diagnostics session lifecycle, or recompute the provider hash first and force `accountIdentifierDidChange`/reload if the cached hash differs. Do not let a stale `currentAccountHash` decide the store snapshot scope.

3. SHOULD-FIX before Task 6: the live bundle snapshot provider hardcodes an empty action snapshot.

   `DiagnosticBundleSnapshot` has an `actions` field and tests prove manually created action snapshots round-trip (`AmakaFlow/Services/SupportDiagnostics/DiagnosticBundleSnapshot.swift:3-9`, `AmakaFlowCompanion/AmakaFlowCompanionTests/DiagnosticBundlePreviewTests.swift:27-54`). The live provider, however, always returns `actions: []` (`DiagnosticBundleSnapshot.swift:175-187`) and has no injected action snapshot source.

   This is not a current viewer-data leak because Task 5 does not add support actions, but it is a contract gap for the next export slice. If Task 6 builds ZIP creation on this provider, `actions.ndjson` will be deterministically empty even after local troubleshooting actions exist. Add an explicit `DiagnosticActionSnapshotProviding` dependency now, or document and type the empty provider as a temporary viewer-only implementation so Task 6 does not inherit a silent false-empty action file.

## Verified

- Read the task review package, task brief, progress ledger, and approved spec sections for logs, preview, storage, lifecycle, and acceptance criteria.
- Inspected the actual diff and relevant call sites in `SupportDiagnosticsCenterView`, `SupportDiagnosticsLogsView`, `DiagnosticBundlePreviewView`, `DiagnosticBundleSnapshot`, `DebugLogService+Persistence`, `DiagnosticEventStore`, `SupportDiagnosticsViewModel`, and `SupportDiagnosticsSession`.
- `wc -l` confirmed every changed Swift file is under 300 lines.
- `plutil -lint AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj/project.pbxproj` passed.
- `git diff --check 33690f926441944b2d3b9081707939544ddfbef8..a0e53965df609b17d168007410ccd9e1d4e47452` passed.
- I ran `just ios-test-impacted BASE=33690f926441944b2d3b9081707939544ddfbef8`, but the recipe treated the argument as a revision literal and fell back to full-suite mode. The diagnostics tests shown in the emitted output passed, including `DiagnosticBundlePreviewTests`, `DebugLogServiceDiagnosticsTests`, `DiagnosticEventStoreTests`, `SupportDiagnosticsEntryTests`, `SupportDiagnosticsProbeTests`, `SupportDiagnosticsAccessClientTests`, and `SupportDiagnosticsSessionTests`. The full run exited 65 after an unrelated `CoachAPIRepositoryEndpointTests.testGeneratedCoachRoutesUndocumentedStatusLogsAndThrowsServerError` failure and a later simulator launch failure.
