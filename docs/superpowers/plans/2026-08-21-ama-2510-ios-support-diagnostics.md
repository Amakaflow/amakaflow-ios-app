# AMA-2510 iOS support diagnostics implementation plan

> Implement the approved `Authorized Support Diagnostics Design` in reviewable slices. Keep production access fail-closed and never expose developer-only token tools in Release builds.

**Goal:** Ship the viewer role on iPhone with server-granted entry, sanitized status and logs, protected bounded persistence, previewed ZIP creation, and explicit Share Sheet export.

**Architecture:** A typed access client parses the mobile-BFF contract at the network boundary. An observable session state machine owns grant lifecycle and supplies authorization state to SwiftUI. Independent probes produce status snapshots. A redactor runs before a serialized event actor writes protected NDJSON segments. Bundle creation consumes immutable snapshots, redacts them again, builds a manifest with SHA-256 hashes, and hands one temporary ZIP to the system Share Sheet after a fresh audited authorization.

**Tech stack:** Swift 5, SwiftUI, XCTest, Foundation networking and crypto, iOS file protection, the existing Xcode project and `just` verification commands.

## Delivery slices

### Task 1: Add the access contract and fail-closed session

**Files:**
- Create: `AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsModels.swift`
- Create: `AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsAccessClient.swift`
- Create: `AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsSession.swift`
- Create: `AmakaFlowCompanion/AmakaFlowCompanionTests/SupportDiagnosticsAccessClientTests.swift`
- Create: `AmakaFlowCompanion/AmakaFlowCompanionTests/SupportDiagnosticsSessionTests.swift`
- Modify: `AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj/project.pbxproj`

**Interfaces:**
- `SupportDiagnosticsAccessProviding.fetchAccess() async throws -> SupportDiagnosticsAccess`
- `SupportDiagnosticsAccessProviding.startSession(idempotencyKey:requestID:) async throws -> SupportDiagnosticsAuditEvent`
- `SupportDiagnosticsSessionState`: `locked`, `checking`, `authorized`, `failed`
- `SupportDiagnosticsSession.checkAndStart()` checks access, uses server time for expiry, records the session-start audit, and authorizes only after both calls succeed.
- `SupportDiagnosticsSession.refreshAccess()` locks on denial, malformed data, authentication failure, offline state, or any transport/server error.
- Unknown capability strings decode but do not become executable capabilities.

**TDD sequence:**
1. Write decoder and request tests against literal payloads and `MockURLProtocol`. Verify failures because the types and client do not exist.
2. Implement the transport boundary with the exact headers and paths merged in backend PR #859.
3. Write state-machine tests for authorized entry, disabled access, server-time expiry, failed session audit, refresh denial, sign-out reset, account change, foreground refresh, and the 60-second policy.
4. Implement the minimal state machine and injected clock/scheduler hooks needed by those tests.
5. Run the two test classes and `git diff --check`.

### Task 2: Wire the Release-safe hidden entry and center shell

**Files:**
- Create: `AmakaFlow/Views/SupportDiagnostics/SupportDiagnosticsCenterView.swift`
- Create: `AmakaFlow/ViewModels/SupportDiagnosticsViewModel.swift`
- Modify: `AmakaFlow/Views/SettingsView.swift`
- Modify: `AmakaFlowCompanion/AmakaFlowCompanion/AmakaFlowCompanionApp.swift`
- Create: `AmakaFlowCompanion/AmakaFlowCompanionTests/SupportDiagnosticsEntryTests.swift`
- Modify: `AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj/project.pbxproj`

**Behavior:**
- Compile the seven-tap version-row gesture into every build.
- Count seven taps inside a fixed two-second window with no visible progress hint.
- Check access and record the session audit before presenting the center.
- Poll every 60 seconds while open and refresh on foreground.
- Dismiss sensitive sheets and reset the session on lock, sign-out, or account change.
- Keep `DebugSettingsView` and raw JWT capture behind `#if DEBUG`.

### Task 3: Build typed status probes

**Files:**
- Create: `AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsProbe.swift`
- Create: `AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsProbeRunner.swift`
- Create: `AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsProbes.swift`
- Create: `AmakaFlow/Views/SupportDiagnostics/SupportDiagnosticsStatusView.swift`
- Create: `AmakaFlowCompanion/AmakaFlowCompanionTests/SupportDiagnosticsProbeTests.swift`
- Modify: `AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj/project.pbxproj`

**Behavior:**
- Run independent probes with bounded timeouts.
- Report unavailable probes with stable safe error codes instead of failing the screen.
- Expose app/build/device, configured hosts, Clerk session summary, reachability, WatchConnectivity, HealthKit authorization, queue counts, database migration health, grant state, and existing correlation IDs.
- Never read raw health samples, JWT bodies, database rows, or URL query values.

### Task 4: Replace legacy log persistence with redacted protected storage

**Files:**
- Create: `AmakaFlow/Services/SupportDiagnostics/DiagnosticEvent.swift`
- Create: `AmakaFlow/Services/SupportDiagnostics/DiagnosticRedactor.swift`
- Create: `AmakaFlow/Services/SupportDiagnostics/DiagnosticEventStore.swift`
- Modify: `AmakaFlow/Services/DebugLogService.swift`
- Modify: `AmakaFlow/Views/DebugLogView.swift`
- Create: `AmakaFlowCompanion/AmakaFlowCompanionTests/DiagnosticRedactorTests.swift`
- Create: `AmakaFlowCompanion/AmakaFlowCompanionTests/DiagnosticEventStoreTests.swift`
- Modify: `AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj/project.pbxproj`

**Behavior:**
- Allowlist metadata per event family, drop unknown keys, and redact fallback text before persistence.
- Detect bearer headers, JWT-shaped strings, cookies, emails, URL query values, and configured secret formats.
- Store serialized events under Application Support with `completeUntilFirstUserAuthentication`.
- Serialize writes away from the main actor and return immutable snapshots.
- Retain at most seven days and 5 MiB, oldest first.
- Migrate `DebugLogEntries` once, redact valid records, delete the legacy key, and discard malformed records.
- Preserve existing `DebugLogService` call sites through a small compatibility facade.

### Task 5: Add authorized logs and export preview

**Files:**
- Create: `AmakaFlow/Views/SupportDiagnostics/SupportDiagnosticsLogsView.swift`
- Create: `AmakaFlow/Views/SupportDiagnostics/DiagnosticBundlePreviewView.swift`
- Create: `AmakaFlow/Services/SupportDiagnostics/DiagnosticBundleSnapshot.swift`
- Create: `AmakaFlowCompanion/AmakaFlowCompanionTests/DiagnosticBundlePreviewTests.swift`
- Modify: `AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj/project.pbxproj`

**Behavior:**
- Render sanitized structured events only when `logs.read` is present.
- Preview exact files, time range, event count, and excluded data categories.
- Take immutable status, event, and action snapshots before bundle creation.
- Lock the preview immediately when session authorization disappears.

### Task 6: Build, audit, and explicitly share the diagnostic ZIP

**Files:**
- Create: `AmakaFlow/Services/SupportDiagnostics/DiagnosticBundleBuilder.swift`
- Create: `AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsActionClient.swift`
- Create: `AmakaFlow/Services/SupportDiagnostics/SupportDiagnosticsExportCoordinator.swift`
- Create: `AmakaFlow/Views/SupportDiagnostics/SupportDiagnosticsExportView.swift`
- Create: `AmakaFlowCompanion/AmakaFlowCompanionTests/DiagnosticBundleBuilderTests.swift`
- Create: `AmakaFlowCompanion/AmakaFlowCompanionTests/SupportDiagnosticsExportTests.swift`
- Modify: `AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj/project.pbxproj`

**Behavior:**
- Recheck access, then start a `bundle.export` audit before creating or presenting an archive.
- Write `manifest.json`, `status.json`, `logs.ndjson`, `actions.ndjson`, and `errors.json`.
- Record byte count and SHA-256 for each payload file.
- Continue safely when one probe or snapshot fails and record the omission in `errors.json`.
- Show the standard iOS Share Sheet only after explicit user confirmation.
- Finish the audit as `presented`, `cancelled`, `succeeded`, or `failed` without storing recipient data.
- Remove temporary files after completion, cancellation, lock, or next-launch reconciliation. Repeating cleanup must converge to an empty diagnostics temp directory.

### Task 7: Verify Release safety and update delivery evidence

**Files:**
- Create: `.github/scripts/verify-support-diagnostics-ios.sh`
- Create: `AmakaFlowCompanion/AmakaFlowCompanionTests/SupportDiagnosticsReleaseSafetyTests.swift`
- Modify: `docs/superpowers/specs/2026-08-21-authorized-support-diagnostics-design.md`
- Update in docs repository: `ops/authorized-support-diagnostics.md`

**Verification:**
1. Run targeted access, session, probe, redactor, store, bundle, and export tests.
2. Run `just ios-build`, `just ios-test-impacted origin/main`, `just ios-lint`, and the relevant full suite.
3. Build Release and scan the product for support PINs, service-role credentials, raw-JWT labels, and development URLs.
4. Exercise granted, denied, revoked, expired, offline, and interrupted-share flows on a physical TestFlight device under AMA-2513.
5. Record PR links, supported app/backend versions, commands, evidence, and rollback notes in the runbook. Keep production disabled until the missing operational owners and grant-authority roster are recorded.

## Blast-radius facts to preserve

- `DebugLogService.shared` has many call sites. Keep its source-compatible logging methods until incremental migration is complete.
- `SettingsView` already owns Debug-only sheets and a seven-tap gesture. Release support entry must not remove developer tools or make them reachable outside `#if DEBUG`.
- The iOS OpenAPI snapshot does not yet contain backend PR #859. The client for this slice is hand-written against the merged contract and must have literal boundary tests to catch drift.
- App Store/TestFlight archives use Release configuration. Release checks must inspect the built product, not infer safety from source conditionals.
- Session authorization crosses app lifecycle, account lifecycle, network timing, and Share Sheet presentation. One state machine owns lock and cleanup notifications so those rules do not drift between screens.
