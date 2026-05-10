# AMA-1817: Contract-First iOS ↔ Backend — Post-Mortem & Next Steps

**Epic:** AMA-1817
**Window:** May 8–9, 2026 (two-day intensive)
**Author:** Perplexity (architect of record for AMA-1817)

---

## 1. Goals and context

AMA-1817 set out to fix a recurring class of bugs where iOS and backend would silently drift apart until real users hit 500/422/404 failures in critical workout flows.

The core problems we were seeing:

- **Schema drift between iOS and backend:**
  - Backend Pydantic models evolved (Pydantic v2, stricter request models).
  - iOS Codable structs evolved by hand in a different repo.
  - There was no shared, enforced contract, so mismatches surfaced only in live flows.

- **Endpoint drift and stale branches:**
  - Paths renamed or split on the backend (`/workouts/scheduled` → `/workouts/planned`) with no contract test or diff gate.
  - Stale branches threatened to revert just-merged work.

- **Partial "done" signals:**
  - Unit tests and local checks were green while real user flows (Save & End, Quick Start) were broken.
  - No single round-trip flow test was required for merge.

AMA-1817's intent was to move us to a contract-first model:

- A mobile BFF is the front-door contract for iOS.
- The BFF's OpenAPI is the single source of truth.
- The iOS client is generated from that OpenAPI.
- CI enforces schema diffs and user-flow tests as merge gates.

---

## 2. What we shipped

### 2.1. First-wave BFF and domains

We introduced a mobile Backend-for-Frontend and locked the mobile domain split:

- First-wave BFF coverage (mobile-domains.md, AMA-1824):
  - **workout** = planning + active session.
  - **sync** = queued mutation reconciliation (all sync_queue writes).
  - **coach** = AI/chat/media ingestion.

- BFF implementation & deploy:
  - BFF service created and deployed on Render.
  - BFF exposes `/v1/*` endpoints for the first-wave workout/sync/completion routes.
  - iOS now talks to BFF `/v1/*` instead of directly to mapper-api for those endpoints.

This aligns the app with the BFF pattern: iOS talks to a mobile-specific façade; the façade talks to internal services.

### 2.2. OpenAPI and generated client

We wired OpenAPI → Swift client generation:

- **OpenAPI extract (AMA-1822):**
  - Automated OpenAPI extraction for relevant services, including mobile-bff (`openapi/mobile-bff.json`).

- **Swift client generation (AMA-1818, 1820):**
  - Switched iOS to vendor mobile-bff OpenAPI, not mapper-api.
  - Regenerated `Client.swift` with `/v1/*` paths.
  - iOS APIService routes the 5 first-wave endpoints via the generated client to the BFF host.

Result: the host/path/auth contract is now code-generated and BFF-centric for those endpoints, rather than hand-maintained.

### 2.3. Typed schemas and the Pydantic v2 gap

We attempted to make the BFF spec fully typed:

- **Typed schemas in BFF (AMA-1826):**
  - Pydantic models were introduced so BFF OpenAPI would include request/response schemas and `Types.swift` would populate.

- **Observed gap:**
  - Pydantic v2 emits optionals as OpenAPI 3.1 `anyOf: [string, null]`.
  - Current swift-openapi-generator drops fields that use `anyOf` with `null` and some `additionalProperties` maps.
  - Result: `Types.swift.WorkoutCompletionRequest` had 5 fields where the Pydantic model had 21.

We intentionally did not adopt partially generated request models that lose fields. For the Save & End payload, we kept the hand-coded `WorkoutCompletionRequest` as the source of truth for the body while still using the generated client for host/path/auth.

### 2.4. CI gates and flow tests

We added CI enforcement layers:

- **Backend CI (AMA-1821 + 1822):**
  - OpenAPI extract pipeline in backend.
  - Diff-and-block checks wired for key services (mobile-bff, workout ingestor, chat) so breaking schema changes must be acknowledged, not silently merged.

- **iOS CI (AMA-1821, CJ-01 pilot):**
  - Maestro flows and iOS test suites wired into CI.
  - Flow tests created for the "CJ-01: full workout" journey:
    - L1 unit/integration (pytest).
    - L2 XCTest.
    - L3 XCUITest (partial, see Clerk note).
    - L4 Maestro (full-journey evidence).
  - CI now runs these as part of merge checks (with known Clerk limitations documented).

This means path/host contracts + user flows now have enforced CI visibility, not just best-effort local tests.

### 2.5. Observability and "memories"

We improved observability around sync and captured recurring root causes:

- **Sync observability (AMA-1823):**
  - `sync_queue` rows now include `status`, `last_error`, and `retry_count`.
  - BFF logs include `request_id`.
  - A follow-up ties iOS-generated IDs through BFF to DB rows for end-to-end correlation.

- **Operational "memories":**
  - Supabase migrations must be applied (no more missing columns in prod).
  - Uvicorn default logging behavior (INFO logs need explicit handlers).
  - Pydantic v2 `anyOf null` behavior and its impact on OpenAPI codegen.
  - Clerk simulator key injection and Info.plist handling.
  - "Maestro evidence is not a validator" (it complements, not replaces, lower layers).

These are documented so future work doesn't have to rediscover the same failures.

---

## 3. What went well

1. **Boundary first, not rewrite first.**
   We resisted the urge to redesign everything and instead:
   - Introduced a BFF as a new entry point.
   - Switched iOS to the BFF via a generated client.
   - Then began tightening the contract and tests.
   This followed proven strangler / BFF migration patterns.

2. **Minimal but high-leverage first wave.**
   First-wave BFF coverage focused on workout, sync, and coach instead of attempting every domain; that matched where drift had real user impact.

3. **CI gates that reflect reality.**
   The merge gates are now aligned with actual risk:
   - schema diffs on backend services that mobile depends on,
   - and flow tests for the full CJ-01 workout journey on iOS.

4. **Honest handling of tooling limits.**
   When we discovered that the generator dropped fields for Pydantic v2's `anyOf null` pattern, we:
   - did not ship partially generated models,
   - documented the gap,
   - and filed a follow-up instead of pretending the epic was "100% done."

5. **Testing blueprint adopted quickly.**
   The 4-layer L1/L2/L3/L4 model got wired into PR templates and DoD immediately, and the CJ-01 pilot now has evidence at each layer.

---

## 4. What surprised us / went poorly

1. **Pydantic v2 ↔ Swift OpenAPI generator mismatch.**
   We expected "BFF OpenAPI → Swift types" to be a straightforward swap. Instead, Pydantic v2's OpenAPI 3.1 style (optionals as `anyOf` with `null`) exposed a support gap in the generator, which silently dropped some fields. That turned what looked like a 30-minute "swap to generated model" into a deeper compatibility problem.

2. **Third-party SDK testability.**
   Clerk's iOS SDK does not expose test-only SPIs or accessibility identifiers for key sign-in fields, making robust XCUITest sign-in flows much harder than expected. We had to fall back to text-based locators, Maestro evidence, and an upstream issue instead of the clean L3 we designed.

3. **Residual complexity in `APIService.swift`.**
   While we routed the critical endpoints through the generated client, `APIService.swift` itself remains large and in need of a domain-level split. That is now sequenced as follow-up work rather than being solved inside this epic.

4. **Tooling instability (CodeRabbit).**
   CodeRabbit CLI OOMs and TRPC errors across multiple PRs added noise and friction to reviews. This is not directly about AMA-1817, but it did impact the development tempo and is now a known infra issue to escalate.

---

## 5. Current state vs. original acceptance criteria

From the original AMA-1817 acceptance criteria:

1. **"Save & End uses generated client; no hand-coded struct."**
   - Path/auth host now go through the generated BFF client.
   - Request body remains hand-coded for `WorkoutCompletionRequest` until we can generate a model that doesn't drop fields.
   - **Status:** partially met; intentionally held at hybrid for safety.

2. **"iOS reads from BFF for the 3 mobile-facing domains; backend services no longer directly addressed by iOS."**
   - BFF covers the workout/sync/completion routes.
   - Chat/coach domain BFF coverage has begun, but some chat endpoints are still direct calls.
   - **Status:** partially met; full BFF coverage for coach is tracked as follow-up.

3. **"APIService.swift below 500 lines (or removed)."**
   - Critical paths now use the generated client.
   - File is still large; type-level split is planned.
   - **Status:** not yet met.

4. **"Backend CI blocks merges that break OpenAPI without compatibility annotation."**
   - OpenAPI extract and diff pipeline exists.
   - Diff checks have been added as required gates for key services.
   - **Status:** functionally met for the targeted services; may extend over time.

5. **"iOS CI runs the 3 flow tests as merge gate."**
   - Maestro and test suites are wired into CI and run per PR.
   - Known Clerk limitation documented for sign-in L3.
   - **Status:** met with caveats documented in the testing blueprint.

6. **"Sync queue rows carry status + last_error + retry_count + request_id."**
   - status, last_error, retry_count implemented.
   - request_id logs at BFF; end-to-end correlation is partially implemented and tracked in follow-up.
   - **Status:** partially met.

In short: AMA-1817 is substantively shipped — the architecture and CI behavior have changed — but there are a few honest, well-documented gaps that follow-up tickets will close.

---

## 6. Follow-ups and next steps

These items remain to fully realize the epic's intent:

1. **Pydantic v2 ↔ Swift OpenAPI generator compatibility (AMA-1831).**
   - Investigate newer swift-openapi-generator versions and their OpenAPI 3.1 / `anyOf null` support.
   - If needed, add an OpenAPI transform or post-processing step so the BFF spec uses generator-friendly patterns (e.g., 3.0-style nullable or explicit wrapper types).
   - Goal: safely swap `WorkoutCompletionRequest` and similar models to generated types without field loss.

2. **Full BFF coverage for coach/chat domain.**
   - Complete BFF fronts for chat-api endpoints.
   - Update generated client and route iOS through BFF for all three domains (`workout`, `sync`, `coach`).
   - Update mobile-domains doc to reflect full coverage.

3. **APIService.swift domain split (AMA-1820-bis, AMA-1829).**
   - Split the monolithic `APIService.swift` into domain-specific repositories/adapters.
   - Drive towards the <500-line target and clearer abstraction boundaries.

4. **Sync queue request_id correlation (AMA-1823).**
   - Ensure iOS generates a request_id per queued mutation.
   - Propagate via BFF to downstream services and into `sync_queue`.
   - Make failures diagnosable by request id across logs, db, and Sentry.

5. **E2E coverage expansion (AMA-1834, 1835, 1836, 1838).**
   - AMA-1834: full-workout HR sim (L1/L2 done; L3/L4 follow-up).
   - AMA-1835: offline replay E2E.
   - AMA-1836: coach domain E2E.
   - AMA-1838: residual workout E2E cases.

6. **Clerk testability gap (upstream + blueprint).**
   - Track the opened Clerk upstream issue (clerk-ios#413) asking for test SPIs or accessibility identifiers on sign-in UI.
   - Until resolved, keep CJ-01 L3 sign-in in place with documented fragility and rely on L1/L2 + Maestro as supporting evidence.

7. **Code review tooling stability.**
   - File a support ticket with CodeRabbit describing the CLI OOM/TRPC errors.
   - If needed, adjust CI to degrade gracefully when the reviewer fails, so core tests/gates remain authoritative.

---

## 7. How to use this doc

- **For new contributors:** this is the story of how we got from "iOS talks directly to many services with hand-coded types" to "iOS talks to a BFF with a generated contract and enforced flow tests," and what remains.
- **For future architecture work:** treat the practices here (BFF contract, OpenAPI generation, CI gates, 4-layer testing) as defaults when we add new domains or refactor old ones.
- **For post-incident reviews:** check whether new bugs fall into categories we've already tried to address (schema drift, missing migrations, opaque logs, third-party testability), and update the "memories" section as needed.
