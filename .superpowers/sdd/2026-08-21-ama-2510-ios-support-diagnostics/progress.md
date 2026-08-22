# SDD ledger — plan: docs/superpowers/plans/2026-08-21-ama-2510-ios-support-diagnostics.md

Task 1: complete (commit 734c02bc, completed before this SDD ledger)
Task 2: complete (commit 92c23205, completed before this SDD ledger)

## Preflight scan

| Producer | Consumer | Shared file or interface | Finding |
| --- | --- | --- | --- |
| Task 1 | Task 3 | `SupportDiagnosticsAuthorization` and session state | Probe output must use the existing typed grant data without duplicating access parsing. |
| Task 2 | Task 3 | Diagnostics center shell | Task 3 creates a status view but its file list omits the center-shell integration needed to render it. |
| Task 3 | Task 5 | Immutable status snapshots | Preserve a Codable, Sendable snapshot model that preview/export can consume without reading live services. |
| Task 3 | Task 6 | Partial probe failures | Each probe must return an isolated safe unavailable result so bundle creation can continue later. |
| Task 3 | Task 7 | Probe and Release verification | Tests must cover timeout isolation and forbidden-data boundaries using behavior, not source-text checks. |
| Task 3 | Task 3 | Listed files and behavior | The requested probe categories agree with the spec; exact presentation fields and timeout duration are intentionally implementation-owned. |
| Task 4 | Task 5 | `DiagnosticEvent` and immutable event snapshots | The viewer and preview must consume already-redacted snapshots without reading persistence from the UI. |
| Task 4 | Task 6 | Redacted event-store snapshots | Bundle generation needs deterministic, serialization-safe events suitable for `logs.ndjson` and a second export-time redaction pass. |
| Task 4 | Task 7 | Store security and lifecycle contracts | File protection, migration, corruption recovery, retention, concurrency, and account separation must be observable in focused tests. |
| Task 4 | Task 3 | `DebugLogService.entries` and correlation metadata | Existing request/Sentry correlation extraction must remain source-compatible while persistence moves behind the protected store. |
| Task 4 | Task 4 | Listed files and approved specification | The task list agrees with the storage work; the specification additionally binds corrupt-record handling and account separation, so those requirements remain in scope. |

Task 3: Ruling: modify `SupportDiagnosticsCenterView.swift` to integrate the new status screen even though the Task 3 file list omits it — the approved spec requires Status to be an actual diagnostics-center surface, and an unreachable view would not satisfy the behavior — cost if wrong: one extra focused integration hunk must be reverted.
Task 3: Ruling: model snapshots as typed Codable and Sendable values with stable probe identifiers, availability variants, safe error codes, optional correlation IDs, and structured display fields — Tasks 5 and 6 need immutable serialization-safe input — cost if wrong: later bundle work may require a model migration.
Task 3: Ruling: run probes concurrently with an independent timeout per probe; one timeout or error becomes that probe's unavailable result and never cancels siblings — this follows the approved failure-isolation requirement — cost if wrong: concurrency ordering may need adjustment for UI expectations.
Task 3: Ruling: fix round 1 may add up to two focused production files to split live data-source adapters and probe construction from `SupportDiagnosticsProbes.swift` — the review fixes grew that file to 649 lines, beyond the project's 300-line guidance — cost if wrong: two extra project references and files must be collapsed later.
Task 3 fix round 2: wired safe live Clerk expiry, Watch transfer, allowlisted overrides, request/Sentry correlation IDs, and default failure/timeout correlation; replaced static-label contract tests with actual probe-output tests; verified focused probes and four-class diagnostics selection pass, strict lint/plutil/diff-check pass.
Task 3 fix round 3: added privacy-safe diagnostics reporting for allowlisted `AMAKAFLOW_STRENGTH_AUTO_CAPTURE` using `StrengthAutoCaptureSettings` semantics; verified focused RED/GREEN, full SupportDiagnosticsProbeTests, line count, strict lint, plutil, and diff-check.
Task 3: complete (commits 392a2595, 5f72564f, b794fe7d, 2043974b; independent review clean; controller verification: `just ios-build` succeeded, 32/32 diagnostics tests passed, strict baseline-aware SwiftLint/plutil/diff-check passed).

Task 4: Ruling: proceed without merging the two new `origin/main` commits discovered at preflight — neither commit touches Task 4 files or its diagnostics interfaces — cost if wrong: later integration may require conflict resolution and repeated verification.
Task 4: Ruling: preserve the public `DebugLogService` logging signatures, entry projection, status metadata, and Task 3 correlation lookup while replacing its persistence internals — existing application and test callers depend on that facade — cost if wrong: a compatibility projection may need removal after all callers migrate.
Task 4: Ruling: treat the approved specification's corrupt-record recovery and account-separation tests as part of Task 4 even though the shorter plan behavior list does not repeat them — the specification is the binding privacy contract — cost if wrong: focused storage APIs or tests may be narrower than a later bundle implementation needs.
Task 4 baseline: `just ios-build` succeeded and 32/32 existing support-diagnostics tests passed. The focused legacy API logging test was already red before Task 4 (`expected serverError(418) ... got unauthorized`), so it is recorded as baseline noise and must not be used to hide any new assertion or logging regression.
