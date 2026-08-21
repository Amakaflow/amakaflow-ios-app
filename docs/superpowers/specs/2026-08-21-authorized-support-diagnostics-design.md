# Authorized Support Diagnostics Design

- **Date:** 2026-08-21
- **Status:** Approved design
- **Implementation status:** Not started
- **Release status:** Unavailable
- **Operational readiness:** Not ready
- **Canonical repository:** `Amakaflow/amakaflow-ios-app`
- **Participating backend:** `Amakaflow/amakaflow-backend`
  (`services/mobile-bff` and Supabase migrations)
- **Participating documentation:** `Amakaflow/amakaflow-docs`
- **Tracking:** [Linear project: Authorized Support Diagnostics](https://linear.app/amakaflow/project/authorized-support-diagnostics-517d55a482a4)

## Summary

AmakaFlow will ship a hidden Support Diagnostics center in App Store and
TestFlight builds. Access is not controlled by a static PIN, a compile-time
`DEBUG` flag, or user-editable local state. It is controlled by a revocable,
time-limited backend grant tied to the signed-in Clerk account.

Authorized viewers can inspect sanitized status and logs and explicitly share
a diagnostic ZIP through the iOS Share Sheet. Authorized operators can also run
an allowlisted set of troubleshooting commands. Every command is capability
checked immediately before execution, requires confirmation when risky, and is
audited. Nothing is uploaded automatically.

The initial grant-management interface is an internal backend command. Its
service boundary must be reusable by a future admin dashboard without changing
the authorization model.

## Existing Context

The iOS app already has useful pieces, but they do not form a safe support
system:

- `AmakaFlow/Services/DebugLogService.swift` records API, authentication,
  Watch, network, sync, and completion events. It currently retains 100 entries
  in `UserDefaults`, accepts unstructured strings, and can retain a prefix of an
  API response.
- `AmakaFlow/Views/DebugLogView.swift` provides log viewing, copying, and
  clearing.
- `AmakaFlow/Views/Settings/DebugSettingsView.swift` contains workout
  simulation controls and a raw Clerk JWT capture tool.
- `AmakaFlow/Views/SettingsView.swift` has a seven-tap version gesture and
  developer diagnostic rows, but those entry points are inside `#if DEBUG`.
- TestFlight is archived with the Xcode Release configuration, so the existing
  developer interface cannot be used by TestFlight testers.
- The mobile BFF already validates Clerk bearer tokens and derives the caller's
  Clerk `sub`. It also uses the Supabase service role for server-owned data.

Developer-only tools may remain behind `#if DEBUG`, but the Support Diagnostics
center is a separate Release-safe surface. In particular, raw JWT display,
printing, or clipboard capture must never move into Support Diagnostics.

## Goals

1. Let approved staff, testers, and support participants diagnose problems on a
   physical iPhone without connecting Xcode.
2. Make the Support Diagnostics entry point available in App Store and
   TestFlight binaries while keeping it inaccessible to ordinary accounts.
3. Tie access to the authenticated Clerk account with server-side grant,
   expiry, revocation, and audit records.
4. Provide actionable status for API, authentication, network, sync,
   WatchConnectivity, HealthKit authorization, local storage, and feature
   state.
5. Provide safe, allowlisted troubleshooting controls for authorized
   operators.
6. Sanitize diagnostics before persistence and make sharing an explicit,
   previewed user action.
7. Reuse existing iOS logging and simulation work where safe, without expanding
   the current singleton into a god object.
8. Establish a backend service interface that a future admin dashboard can use
   for grant management.

## Non-goals

- Remote shell access, arbitrary command execution, or arbitrary UserDefaults
  editing.
- Direct database browsing or mutation from the iPhone.
- Capturing raw Clerk JWTs, authorization headers, cookies, health samples,
  exact locations, or full customer-generated content.
- Automatic diagnostic uploads, background screen recording, or live remote
  control.
- Reading arbitrary iOS crash files. Support Diagnostics may expose Sentry event
  identifiers and app-recorded failure context, but iOS does not provide an app
  unrestricted access to system crash reports.
- Building the graphical admin dashboard in this project. The first release
  provides an internal command and a dashboard-ready service boundary.
- Making every existing developer-only bypass available in Release builds.

## Considered Approaches

### 1. Server-granted capability — selected

Supabase stores grants tied to Clerk user IDs. The mobile BFF validates the
signed-in user and returns the effective role, capabilities, and expiry. This
supports immediate revocation checks, automatic expiry, audit history, and a
future admin dashboard.

### 2. Clerk private metadata

This would reduce schema work, but expiry and audit history would be weaker,
and changed claims could remain stale until the Clerk token is refreshed.

### 3. Static PIN or local hidden flag

This is easy to build but unacceptable for an App Store binary. A reusable
secret can be extracted or shared and cannot be reliably tied to an account,
revoked, or audited.

## Roles and Durations

The backend maps roles to a fixed capability set. The iOS app renders only the
capabilities returned by the server; it does not infer additional permissions
from the role name.

| Role | Eligible account | Default duration | Capabilities | Grant authority |
| --- | --- | --- | --- | --- |
| `viewer` | Customer with an active support case or approved tester | 24 hours for support or 30 days for testing | Status, sanitized logs, and explicit bundle export | Designated Support admin or Engineering owner |
| `operator` | Named support engineer or tester who needs remediation controls | 24 hours for support or 30 days for testing | Viewer capabilities plus allowlisted troubleshooting commands | Engineering owner |
| `staff` | Named internal engineer with ongoing support duties | No automatic expiry by exception | Operator capabilities | Engineering owner plus a second designated admin |

Only `staff` grants may have a null `expires_at`. The admin command requires an
explicit duration for `viewer` and `operator` grants. Revocation takes
precedence over expiry and role.

Initial capability identifiers are stable wire values:

- `status.read`
- `logs.read`
- `bundle.export`
- `auth.refresh`
- `watch.reconnect`
- `health.authorization.refresh`
- `sync.retry`
- `completion.retry`
- `queue.clear.local_pending`
- `cache.clear.safe`
- `environment.override.allowed`
- `simulation.enable.isolated`
- `feature_override.allowlisted`

Adding a capability requires backend mapping, iOS command implementation, and
tests on both sides. Unknown capabilities are ignored by the app.

## System Architecture

### Backend components

1. **Grant repository** reads and writes grants and audit events through the
   Supabase service role.
2. **Grant service** resolves active grants, maps roles to capabilities, applies
   duration rules, and creates grant/revoke audit records. The internal command
   and future dashboard route depend on this service rather than duplicating
   authorization logic.
3. **Authenticated mobile routes** expose only the current caller's effective
   access and authorize/audit troubleshooting actions. They use the existing
   Clerk JWT dependency and never accept a caller-supplied user ID.
4. **Internal admin command** resolves a Clerk user by email or Clerk user ID,
   then grants, revokes, or lists access through the grant service. It requires
   backend credentials and never ships in the iOS app.
5. **Global access switch** is a server-controlled configuration checked before
   grant resolution and action authorization. When disabled, access responses
   are locked and action-start requests are denied without requiring an iOS
   release.

### iOS components

1. **`SupportDiagnosticsAccessClient`** calls the BFF and decodes effective
   access. It conforms to a small protocol so tests can inject deterministic
   access responses.
2. **`SupportDiagnosticsSession`** is the observable authorization state
   machine: `locked`, `checking`, `authorized`, or `failed`. It owns expiry and
   foreground refresh behavior, but it does not execute commands.
3. **`SupportDiagnosticsCommandRunner`** is the single authorization proxy for
   troubleshooting commands. It starts a backend audit record, obtains a fresh
   capability decision, requests any required confirmation, executes the local
   command, and completes the audit record. Screens cannot invoke command
   implementations directly.
4. **`SupportDiagnosticsCommand` implementations** encapsulate individual
   troubleshooting actions. The Command pattern fits because actions need
   common metadata, confirmation, authorization, execution, and audit behavior
   while remaining independently testable.
5. **`SupportDiagnosticsProbe` implementations** produce structured status for
   one subsystem each. A probe failure is data rendered as unavailable, not a
   failure of the entire screen.
6. **`DiagnosticRedactor`** sanitizes structured fields and fallback text before
   an event reaches persistent storage. Export applies the same redactor again
   as defense in depth.
7. **`DiagnosticEventStore`** replaces debug-log persistence in UserDefaults
   with bounded, file-protected storage while preserving a compatibility facade
   for existing call sites.
8. **`DiagnosticBundleBuilder`** creates the preview model and ZIP contents from
   immutable snapshots of status, events, and actions.
9. **SwiftUI views** provide Status, Logs, Tools, and Export sections. They only
   depend on view models and the interfaces above.

## Authorization Data Model

Two service-role-only tables live in the Supabase `public` schema because the
existing backend accesses Supabase through PostgREST. Both tables must enable
RLS, revoke `anon` and `authenticated` privileges, grant only `service_role`,
and define policies with `TO service_role`. No mobile client receives a
Supabase service-role key.

### `support_diagnostic_grants`

| Column | Type | Rules |
| --- | --- | --- |
| `id` | UUID | Primary key, generated by the database |
| `clerk_user_id` | TEXT | Required; taken from Clerk, never from an access request body |
| `role` | TEXT | Check constraint: `viewer`, `operator`, or `staff` |
| `reason` | TEXT | Required, non-blank support or testing reason |
| `case_reference` | TEXT | Required support case or Linear reference; contains no email or health data |
| `granted_by` | TEXT | Required internal actor identifier derived from authenticated admin credentials |
| `approved_by` | TEXT[] | Required approval actors; staff requires two distinct authorized actors |
| `created_at` | TIMESTAMPTZ | Required, database default `now()` |
| `expires_at` | TIMESTAMPTZ | Required for viewer/operator; null only for staff |
| `revoked_at` | TIMESTAMPTZ | Null until revoked |
| `revoked_by` | TEXT | Required when revoked |
| `revoke_reason` | TEXT | Required when revoked |
| `retention_hold_until` | TIMESTAMPTZ | Optional incident hold that delays scheduled deletion |

An index begins with `clerk_user_id` and supports filtering by revocation and
expiry. Multiple historical grants are retained. Effective access is the
highest active role; a grant is active only when `revoked_at` is null and
`expires_at` is either null for staff or later than the database time.

Database constraints require at least one authorized approver for every grant
and two distinct approvers for `staff`. The grant service also verifies that
each approver has authority for the requested role. `case_reference` accepts a
bounded support case or Linear identifier, not free-form customer data.

### `support_diagnostic_audit_events`

| Column | Type | Rules |
| --- | --- | --- |
| `id` | UUID | Primary key |
| `grant_id` | UUID | Foreign key to the grant; null only for an access denial when no grant exists |
| `clerk_user_id` | TEXT | Required and copied for efficient account history |
| `actor` | TEXT | Account ID for device actions; authenticated internal actor for grant changes |
| `event_type` | TEXT | Allowlisted grant, revoke, revoke-all, access-denial, command, and export values |
| `capability` | TEXT | Present for command/export events |
| `outcome` | TEXT | `started`, `succeeded`, `failed`, `cancelled`, `presented`, or `denied` |
| `correlation_id` | TEXT | Optional request/Sentry correlation identifier |
| `idempotency_key` | TEXT | Required for mutating admin and action requests; protected by a scoped unique index |
| `safe_context` | JSONB | Sanitized allowlisted context only |
| `app_version` | TEXT | Optional for grant events; required for device events |
| `created_at` | TIMESTAMPTZ | Required, database default `now()` |
| `retention_hold_until` | TIMESTAMPTZ | Optional incident hold that delays scheduled deletion |

The audit table never stores tokens, raw logs, raw request/response bodies, ZIP
contents, emails, or health data. Grant changes, revoke-all operations,
diagnostics-center opens, rate-limited access denials, protected-operation
denials, troubleshooting actions, and exports are audited. Routine successful
access polling is not audited. Audit and historical grant records expire 180
days after grant expiry or revocation unless an incident hold applies.

Schema changes must be created with the repository's Supabase migration
workflow, reviewed with database advisors, and verified with direct tests of
table privileges and RLS behavior before deployment.

## Mobile BFF Contracts

All routes use the existing Clerk bearer-token validation and derive
`clerk_user_id` from the verified token.

### `GET /v1/support-diagnostics/access`

Returns HTTP 200 for authenticated accounts whether or not a grant exists.

Authorized response:

```json
{
  "enabled": true,
  "grantId": "3b48344d-3d70-4e36-8750-e3caa43f97dc",
  "role": "operator",
  "capabilities": ["status.read", "logs.read", "bundle.export", "sync.retry"],
  "expiresAt": "2026-08-22T20:00:00Z",
  "serverTime": "2026-08-21T20:00:00Z"
}
```

Unauthorized response:

```json
{
  "enabled": false,
  "grantId": null,
  "role": null,
  "capabilities": [],
  "expiresAt": null,
  "serverTime": "2026-08-21T20:00:00Z"
}
```

The client uses `serverTime` to avoid trusting a manipulated device clock for
expiry. Authentication failures remain 401. Backend or database failures are
5xx and fail closed in the app.

The BFF rate-limits audit records for disabled access responses. An access
denial without a historical grant uses a null `grant_id`. Routine successful
polling creates no audit record.

### `POST /v1/support-diagnostics/sessions/start`

After a fresh authorized access response, the app calls this route before it
shows the diagnostics center. The BFF re-resolves the grant and records one
view event for the session. A denial keeps the center locked. Retrying with the
same idempotency key returns the existing session-audit ID.

### `POST /v1/support-diagnostics/actions/start`

The request contains only a capability identifier and sanitized, schema-bound
context. The BFF re-resolves the active grant and verifies the capability. On
success it creates a `started` audit event and returns its action ID. A missing
grant or capability returns 403. The iOS app must not execute the command when
this call fails.

### `POST /v1/support-diagnostics/actions/{action_id}/finish`

The BFF verifies that the action belongs to the caller and records
`succeeded`, `failed`, `cancelled`, or `presented` with sanitized error and
correlation fields. If the finish request cannot be delivered, the original
`started` event remains visible as incomplete; the iOS event store records the
delivery failure for the explicit bundle.

Bundle sharing uses capability `bundle.export`. The backend records that a
share sheet was presented or completed based on iOS completion callbacks. It
does not claim that a recipient received the file.

## Authorization Lifecycle and Entry

1. The app continues collecting a minimal sanitized rolling log for all
   accounts so a grant can diagnose an issue that happened before activation.
2. The version row in Settings is compiled into every build. Seven taps within
   two seconds trigger an access check; no progress hint is shown to ordinary
   users.
3. An authorized response opens Support Diagnostics and displays role and
   expiry. An unauthorized response may show “Support access is not enabled for
   this account” without exposing controls.
4. The open center checks access every 60 seconds, on app foreground, before
   export, and through the action-start route before every command.
5. Any denied, expired, revoked, authentication-failed, offline, or 5xx result
   locks the center. Offline access fails closed.
6. Locking dismisses sensitive sheets, blocks commands and export, and resets
   all temporary overrides.
7. Sign-out immediately clears the diagnostics session and overrides. A new
   signed-in account cannot inherit another account's grant or overrides.
8. Disabling the backend global access switch locks all sessions at their next
   poll and denies every new command or export immediately.

The 60-second poll bounds ordinary revocation latency while the screen remains
open. Sensitive actions and export always get a fresh server decision, so a
revoked grant cannot start new work during that window.

## Diagnostics Center

### Status

Status is composed from independent probes:

- App version, build number, bundle identifier, distribution type, iOS version,
  device model, locale, and timezone.
- Current environment and configured hostnames, without query strings or
  credentials.
- Clerk session presence, token expiry summary, and user-ID hash. The token
  itself and its raw claims are excluded.
- Network reachability and bounded health checks for the mobile BFF and
  currently used APIs.
- WatchConnectivity activation, pairing, installation, reachability, and last
  sanitized transfer result.
- HealthKit authorization states by data category, without samples or values.
- Pending local sync/completion queue counts, oldest age, and last error.
- Local database schema version and migration health, without table contents.
- Effective diagnostics role, expiry, capability list, simulation state, and
  allowlisted feature overrides.
- Recent Sentry event IDs or request IDs already recorded by the app.

Each probe has a timeout. A failure yields `unavailable` with a safe error code
and correlation ID; it does not prevent other probes from rendering or export.

### Logs

Events use structured categories for API, auth, network, sync, completion,
Watch, HealthKit, storage, app lifecycle, and operator actions. Every event has
an ID, timestamp, severity, category, stable event name, safe message,
structured metadata, and optional request/Sentry correlation IDs.

Minimal collection is always on and excludes bodies. An authorized operator
may enable verbose collection for at most 30 minutes. Verbose mode adds safe
timing, status, retry, and state-transition metadata; it does not relax
redaction or enable body/token/health-sample capture.

### Tools

The initial Release-safe commands are:

- Refresh the Clerk session through the normal Clerk API.
- Reinitialize or reconnect WatchConnectivity through the existing manager.
- Re-request or refresh HealthKit authorization state through existing system
  flows. It cannot silently grant permission.
- Retry pending sync and workout-completion work through existing repositories
  and authenticated API routes.
- Clear only the signed-in account's local pending queue after showing item
  count, age, and irreversibility. This does not delete server records.
- Clear allowlisted caches and diagnostic logs. Authentication and durable
  workout data are excluded from the generic cache command.
- Override the environment only to build-configured `staging` or `production`.
  Release builds never accept development hosts or arbitrary URLs. Changing
  Clerk environment signs the account out and requires normal reauthentication.
- Run workout simulation in an isolated local session. Release support
  simulation cannot write fake HealthKit data or publish simulated completions
  to production services.
- Toggle only feature flags registered in a dedicated support allowlist.
  Arbitrary UserDefaults keys cannot be edited.

Risky commands show a specific confirmation that names the effect. Temporary
environment, simulation, and feature overrides are scoped to the Clerk user
and grant ID and reset on expiry, revocation, lock, or sign-out.

Developer-only tools may remain available in Debug builds alongside Support
Diagnostics, but they do not use a Release capability. The raw Clerk JWT tool
stays Debug-only and is not exposed through the command registry.

## Redaction and Persistent Storage

Redaction occurs before persistence and again during export.

1. Structured metadata is allowlisted by event type. Unknown keys are dropped.
2. Sensitive key names such as authorization, token, secret, cookie, password,
   email, location, and health-sample fields are removed.
3. Fallback text sanitization detects bearer headers, JWT-shaped values, email
   addresses, URLs with query strings, and known secret formats.
4. Account identifiers are hashed for display/export. Request IDs, Sentry event
   IDs, and workout IDs may remain because they are necessary for correlation
   and are not authentication credentials.
5. API logs store method, normalized path template, status, duration, retry
   count, response size, and correlation IDs. They do not store raw bodies.

The persistent event store lives under Application Support with iOS file
protection `completeUntilFirstUserAuthentication`. It retains at most seven
days and 5 MiB, rotating oldest events first. Writes are serialized off the
main actor and expose immutable snapshots to UI/export callers.

On first launch after migration, the app reads the legacy
`DebugLogEntries` value once, redacts valid entries into the new store, deletes
the legacy value, and safely discards malformed data. New call sites use
structured events. A compatibility facade keeps existing logging calls working
while they are migrated incrementally.

## Explicit Bundle Export

Export has three steps: preview, create, and share.

The preview lists each included file, time range, event count, and excluded
data categories. Creating the bundle takes immutable snapshots and produces a
ZIP containing:

- `manifest.json`: schema version, app/build, OS/device model, environment,
  role, grant expiry, creation time, and redaction-policy version.
- `status.json`: structured probe results.
- `logs.ndjson`: redacted structured events.
- `actions.ndjson`: local troubleshooting actions and results.
- `errors.json`: probes, audit deliveries, or files that could not be included.

The archive never contains raw tokens, request/response bodies, database dumps,
health samples, exact locations, or unrelated customer content. No archive is
uploaded by the app. After a fresh `bundle.export` authorization, the standard
iOS Share Sheet lets the user choose Mail, Messages, AirDrop, Files, or another
installed destination.

The first release does not add application-level ZIP encryption. iOS file
protection protects the archive before sharing. The destination controls its
protection after sharing, so the preview warns the user to choose a private
support destination. `manifest.json` records each payload file's byte count and
SHA-256 value, along with the bundle schema and redaction-policy versions.
Support retains a received archive for at most 30 days unless an incident hold
applies.

Temporary archive directories use file protection and are removed after the
share completion callback, cancellation, authorization lock, or the next app
launch if cleanup was interrupted. Share auditing records only presentation or
completion, never the chosen recipient or destination content.

## Failure Handling

- Missing, expired, revoked, offline, malformed, or failed access responses
  lock Support Diagnostics.
- A status-probe failure is isolated and included as a safe error result.
- A command cannot execute unless its action-start request succeeds.
- Command failures are shown with a stable error code and correlation ID and
  are written to both the local event store and backend audit completion.
- If audit completion fails after a local command ran, the app keeps the action
  as locally incomplete and retries only the audit delivery; it does not repeat
  the troubleshooting command.
- Export continues with remaining safe files when one probe or snapshot fails
  and records omissions in `errors.json`.
- Corrupt legacy logs or event-store segments are quarantined or discarded
  without blocking app launch.

## Admin Command and Future Dashboard

The internal command supports:

- Grant by Clerk user ID or account email.
- Explicit role, duration, reason, case reference, and approvers.
- Revoke by grant ID or account with a required reason. The authenticated
  identity supplies the actor.
- List active and historical grants for an account.
- Revoke all active grants for an account or environment.
- Find audit records by grant ID, account, time range, event type, or
  correlation ID.

Email is used only to resolve the Clerk user ID and is not copied into the
grant or audit tables. The command runs only with authenticated internal admin
credentials in an explicitly selected environment. It derives the actor from
those credentials and requires the approval defined for the requested role.
Before mutation, it confirms the environment, Clerk user ID, role, expiry,
case reference, and approvers. Production operator and staff grants require an
Engineering owner. A staff grant also requires a distinct designated admin.

Grant, revoke, and revoke-all operations accept an idempotency key. Retrying a
completed command returns the existing result without creating another grant
or duplicate audit event. Revoke and revoke-all converge on the revoked state,
including when a prior attempt stops after the database mutation but before
the command returns. A daily retention command deletes eligible audit records
before unreferenced grants. It works in batches, skips active incident holds,
and produces the same final state after retries.

The future dashboard must call an authenticated admin route backed by the same
grant service. It must not write Supabase rows directly from browser code or
reimplement duration/capability rules.

## Documentation and Delivery Tracking

This file is the canonical architecture and security design. The
`amakaflow-docs` repository contains the cross-repository support runbook at
`ops/authorized-support-diagnostics.md`. The runbook records operational
policy, grant durations, privacy boundaries, the explicit-send support flow,
rollout gates, incident response, and links to shipped implementation evidence.

The [Authorized Support Diagnostics Linear project](https://linear.app/amakaflow/project/authorized-support-diagnostics-517d55a482a4)
tracks delivery through these issues:

- [AMA-2509](https://linear.app/amakaflow/issue/AMA-2509) — backend authorization
  and audit foundation.
- [AMA-2510](https://linear.app/amakaflow/issue/AMA-2510) — iOS viewer,
  protected diagnostics, and explicit export.
- [AMA-2511](https://linear.app/amakaflow/issue/AMA-2511) — authorized operator
  controls.
- [AMA-2512](https://linear.app/amakaflow/issue/AMA-2512) — engineering and
  support documentation.
- [AMA-2513](https://linear.app/amakaflow/issue/AMA-2513) — Release and physical
  device verification.

Each implementation stage must update the runbook with merged PRs, deployed
schema/API versions, actual command syntax, supported app versions, verification
evidence, and rollback notes. Until that evidence is present, the runbook must
label the feature as designed rather than shipped.

Use Poteto's pstack architecture, boundary, idempotency, blast-radius, and proof
skills throughout implementation. The current Codex plugin exposes these
skills directly rather than through `/poteto-mode`. pstack is a development
workflow only. It adds no runtime dependency and does not change the
authorization or privacy model.

## Operational Ownership

David Andrews is the Engineering owner because he leads the Linear project.
The Support operations owner and the security and privacy escalation owner are
not assigned. Production enablement is blocked until both owners are named in
the runbook. The runbook also records the current grant-authority roster before
the backend global access switch is enabled in production.

## Verification Strategy

### Backend

- Grant-service unit tests cover missing, active, expired, revoked, overlapping,
  viewer, operator, and non-expiring staff grants.
- Tests prove viewer/operator grants require expiry and staff is the only role
  allowed a null expiry.
- Route tests prove the Clerk token determines the account and request bodies
  cannot select another user.
- Capability tests cover every known command and reject unknown or insufficient
  capabilities.
- Action tests prove start-before-execute semantics, ownership of finish calls,
  sanitized audit context, and incomplete started actions.
- Admin-command tests cover email resolution, grant, revoke, list, required
  reason/actor, and failures without partial writes.
- Migration tests verify constraints, indexes, foreign keys, RLS enabled,
  revoked client privileges, service-role-only policies, and database-advisor
  results.
- Retention tests prove that expired grant and audit records are removed after
  180 days unless an incident hold applies.
- Admin tests prove actor identity comes from authenticated credentials and
  staff access requires two distinct authorized approvers.
- Idempotency tests retry grant, revoke, revoke-all, action finish, and
  retention cleanup after each durable write and prove that no duplicate state
  or audit event remains.

### iOS

- Access-session tests cover all states, server-time expiry, 60-second refresh,
  foreground checks, offline fail-closed behavior, sign-out, and account change.
- Entry UI tests prove seven taps open the center only for authorized accounts
  and expose no progress hint to ordinary users.
- Command-runner tests prove direct commands cannot bypass fresh capability
  authorization, confirmation, start audit, or finish audit.
- Each command has behavior tests for success, cancellation, failure, and
  automatic reset.
- Redactor tests use representative JWTs, bearer headers, cookies, emails,
  query strings, health values, nested JSON, and malformed text.
- Event-store tests cover migration, corruption, seven-day retention, 5 MiB
  rotation, concurrency, file protection attributes, and account separation.
- Bundle tests assert the exact file manifest, schema versions, sanitized
  contents, per-file byte counts and SHA-256 values, partial-error behavior,
  and temporary-file deletion.
- Release-configuration checks search the built product for embedded support
  PINs/secrets and ensure raw-JWT UI is absent. Release UI tests cover granted
  and ungranted accounts.
- The repository's required `just ios-build`, targeted tests, and relevant full
  suites run before completion claims.

## Deployment Sequence

### Stage 1: Authorization foundation

Deploy the Supabase migration, grant repository/service, BFF access and action
audit routes, and internal admin command. No released iOS version depends on
them yet. Verify RLS, privileges, grant expiry, and revocation in staging.

### Stage 2: Viewer diagnostics

Ship Release-safe entry authorization, Status, sanitized structured logging,
protected retention, preview, and explicit ZIP sharing. Grant viewer access to
staff/test accounts and validate on a physical TestFlight device.

### Stage 3: Operator controls

Ship the command runner and commands incrementally. Each command lands with its
capability mapping, backend audit behavior, tests, and physical-device evidence.
Do not ship a generic command executor.

Backend changes deploy before their iOS consumer. Old iOS versions ignore the
new endpoints and tables. Unknown capabilities are forward compatible because
the app ignores them.

## Acceptance Criteria

1. An ordinary App Store/TestFlight account cannot open Support Diagnostics or
   invoke a troubleshooting command.
2. A valid viewer, operator, or staff grant opens the correct surface for the
   signed-in Clerk account.
3. Viewer/operator grants expire automatically at the approved time; staff
   grants remain until revoked.
4. Revocation prevents export and new commands no later than the next 60-second
   poll, and immediately when either operation is attempted.
5. No static support PIN, service-role key, raw Clerk JWT tool, or arbitrary
   command interface exists in the Release product.
6. Every troubleshooting command is allowlisted, freshly authorized,
   confirmed when risky, and audited before execution.
7. Temporary overrides reset on lock, expiry, revocation, account change, and
   sign-out.
8. Diagnostic events are sanitized before persistence, retained for no more
   than seven days or 5 MiB, and protected on disk.
9. Export requires an explicit user action, previews its contents, creates the
   documented ZIP, and never uploads automatically.
10. Automated backend, iOS, migration, Release, and physical-device checks pass
    with executable evidence.
11. The cross-repository runbook and Linear project link the final PRs, deployed
    versions, verification evidence, operational commands, and rollback notes.
12. A tested backend global access switch denies new access, commands, and
    exports without requiring a new iOS release.
13. Production remains disabled until Support operations and security and
    privacy owners are assigned and the grant-authority roster is recorded.
14. Audit and historical grant records expire after 180 days, and received
    diagnostic reports expire after 30 days, unless an incident hold applies.

## Implementation Boundaries

The work spans three repositories and must use isolated worktrees because the
primary local checkouts contain unrelated changes.

- `amakaflow-backend`: Supabase migration, mobile-BFF repository/service/routes,
  internal command, and backend tests.
- `amakaflow-ios-app`: access client/session, logging/redaction/store, probes,
  SwiftUI center, command runner and commands, bundle export, project wiring,
  and iOS tests.
- `amakaflow-docs`: indexed support runbook, shipped-state record, operational
  workflow, incident response, and release evidence.

The canonical implementation plan will reference all three repositories and
order backend work before iOS consumers. Commits remain repository-local and
stage only the files owned by this feature.
