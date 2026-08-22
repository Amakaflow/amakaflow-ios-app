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

Task 3: Ruling: modify `SupportDiagnosticsCenterView.swift` to integrate the new status screen even though the Task 3 file list omits it — the approved spec requires Status to be an actual diagnostics-center surface, and an unreachable view would not satisfy the behavior — cost if wrong: one extra focused integration hunk must be reverted.
Task 3: Ruling: model snapshots as typed Codable and Sendable values with stable probe identifiers, availability variants, safe error codes, optional correlation IDs, and structured display fields — Tasks 5 and 6 need immutable serialization-safe input — cost if wrong: later bundle work may require a model migration.
Task 3: Ruling: run probes concurrently with an independent timeout per probe; one timeout or error becomes that probe's unavailable result and never cancels siblings — this follows the approved failure-isolation requirement — cost if wrong: concurrency ordering may need adjustment for UI expectations.
Task 3: Ruling: fix round 1 may add up to two focused production files to split live data-source adapters and probe construction from `SupportDiagnosticsProbes.swift` — the review fixes grew that file to 649 lines, beyond the project's 300-line guidance — cost if wrong: two extra project references and files must be collapsed later.
Task 3 fix round 2: wired safe live Clerk expiry, Watch transfer, allowlisted overrides, request/Sentry correlation IDs, and default failure/timeout correlation; replaced static-label contract tests with actual probe-output tests; verified focused probes and four-class diagnostics selection pass, strict lint/plutil/diff-check pass.
