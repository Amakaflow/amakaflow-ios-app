# Critical Journeys — Coverage Map

Source blueprint: `docs/testing/blueprint.md`. Source DoD template:
`docs/testing/feature-dod-template.md`.

This document is the human-readable index of which critical journeys
have which test layers, where the tests live, and what is intentionally
deferred. Update it whenever a layer changes for a journey.

---

## CJ-01 — Sign-in -> Generate -> Save & End -> Verify -> Reopen

**Pilot journey, first release gate. Linear umbrella: AMA-1839.**

User outcome being validated:

> A signed-in user can generate a workout via the AI coach, complete it,
> end the session, see it persisted in the verify step, and reopen the
> app to find the same completed workout.

### Backend routes touched

- `POST /coach/suggest-workout` (chat-api) — Generate
- `POST /workouts/complete` (mapper-api) — Save & End
- `GET  /workouts/completions` (mapper-api) — Verify + Reopen
- `GET  /workouts/completions/{id}` (mapper-api) — Reopen detail

iOS calls the BFF wraparounds at `/v1/...` for all of the above; the
BFF forwards the typed request bodies and response payloads.

### Layer status (as of 2026-05-09)

| Layer | Status | Authoritative location | Notes |
|---|---|---|---|
| L1 | Green | `services/{mapper-api,chat-api,mobile-bff}/tests/integration/test_cj01_*.py` | JUnit artifacts published per service: `cj01-l1-junit-{service}` |
| L2 | Green | `AmakaFlowCompanion/AmakaFlowCompanionTests/CJ01/AMA1839_CJ01_*.swift` | 24 tests, JUnit artifact `cj01-l2-junit` |
| L3 | Selectors landed (AMA-1842); journey blocked on AMA-1843 | `AmakaFlowCompanion/AmakaFlowCompanionUITests/CJ01/AMA1839_CJ01_WorkoutLifecycle_CriticalJourneyTests.swift` | Tests use `ama1842.*` accessibilityIdentifiers end-to-end and currently `XCTSkip` until AMA-1843 (UITest Clerk signin bypass) lands — ClerkKitUI ships zero accessibilityIdentifier values across its vendor SwiftUI signin views, so XCUITest cannot drive the signin step today. Skip is intentional and surfaces AMA-1843 in the test log. |
| L4 | Not yet implemented | `e2e/maestro/flows/workout-lifecycle/` (planned) | Phase 2 step 4 |

### What L1 currently asserts

#### Save & End — `services/mapper-api/tests/integration/test_cj01_save_and_end.py`

- `test_workouts_complete__valid_full_payload__persists_and_returns_summary` —
  full payload (workout_id + health_metrics + execution_log) returns
  `success=True`, the persisted id round-trips, and the iOS-readable
  summary (`duration_formatted`, `avg_heart_rate`, `calories`) is present.
- `test_workouts_complete__missing_workout_id__returns_completion_with_event_id`
  — workout_event_id-only completions succeed (AMA-1825).
- `test_workouts_complete__missing_auth__returns_401` — bare request
  with no Authorization header is rejected by the real
  `backend.auth.get_current_user` (override stripped for this test).

Referenced existing coverage (skipped to keep this file navigable, not
to drop the assertion):

- Idempotency on retry (AMA-1794) — pinned in
  `services/mapper-api/tests/test_complete_idempotency.py`.
- ExecutionLog dict serialization (AMA-1798) — pinned in
  `services/mapper-api/tests/test_workout_completions.py::test_complete_workout_execution_log_serialized_to_dict`.

#### Completions listing — `services/mapper-api/tests/integration/test_cj01_completions_listing.py`

- `test_completions_list__signed_in_user__returns_only_their_completions`
  — verifies the route is scoped to the authenticated user (asserts the
  `user_id` arg passed to the repository).
- `test_completions_list__no_completions__returns_empty_array` — empty
  state is a 200 with `completions=[]` and `total=0`, not a 404 or
  exception.
- `test_completions_list__missing_auth__returns_401` — auth gate.

Referenced existing coverage:

- Pagination cap (limit > 100 -> 422) — pinned in
  `services/mapper-api/tests/test_workout_completions.py::test_list_completions_limit_validation`.

#### Suggest-workout (Generate) — `services/chat-api/tests/integration/test_cj01_suggest_workout.py`

- `test_suggest_workout__valid_request__returns_workout_with_blocks` —
  200 + `blocks` array of `kind`-tagged intervals + `sport == "strength"`.
- `test_suggest_workout__missing_auth__returns_401` — auth gate (uses
  a fresh app instance with no auth override installed).

Referenced existing coverage:

- `duration_minutes` schema validation -> 422 — pinned in
  `services/chat-api/tests/test_suggest_workout.py::test_suggest_workout_invalid_duration`.
- Empty body uses defaults — pinned in
  `services/chat-api/tests/test_suggest_workout.py::test_suggest_workout_empty_body`.

#### BFF wraparound — `services/mobile-bff/tests/integration/test_cj01_pilot_paths.py`

- `test_bff_proxies_workouts_complete__forwards_typed_body__upstream_receives_full_fields`
  — every required field reaches mapper-api; Authorization is passed
  through verbatim.
- `test_bff_proxies_suggest_workout__forwards_body__upstream_receives_request`
  — Generate proxy forwards body + auth and pipes the iOS-shaped
  response back.

Referenced existing coverage:

- Typed-body rejection at the BFF boundary (AMA-1826) — pinned in
  `services/mobile-bff/tests/test_proxy.py::test_workouts_complete_rejects_invalid_body_before_upstream`.
- Typed response model parses — pinned in
  `services/mobile-bff/tests/test_proxy.py::test_workouts_complete_response_parses_against_response_model`.

### Edge cases / blockers deferred to later layers

- `GET /v1/workouts/completions` BFF proxy — **not yet wired** in
  `services/mobile-bff/app/main.py`. Per the task hard rule "Don't
  alter app/router code; new tests only", the CJ-01 BFF test
  `test_bff_proxies_completions_list__forwards_query_and_auth` asserts
  the current 404 behaviour and is `pytest.skip`-marked with a clear
  follow-up note. The test self-reactivates the moment the route
  lands. **Follow-up ticket required** before CJ-01 can claim a
  full-stack green pass for the Verify + Reopen steps.
- Sign-in itself is Clerk-managed and intentionally not covered at
  L1. The blueprint puts sign-in interruption handling at L3.
- Persistence reload after app cold-start is L2 (Swift persistence
  store) and L3 (XCUITest reopen flow). L1 asserts the read API
  contract only.

### CI artifacts

Per-service JUnit files are uploaded with `if: always()` so they
appear even on a failing run:

- `cj01-l1-junit-chat-api` -> `services/chat-api/junit-cj01-l1.xml`
- `cj01-l1-junit-mapper-api` -> `services/mapper-api/junit-cj01-l1.xml`
- `cj01-l1-junit-mobile-bff` -> `services/mobile-bff/junit-cj01-l1.xml`
- `cj01-l2-junit` -> generated from the iOS Tests workflow via xcpretty
  -> `AmakaFlowCompanion/cj01-l2-junit.xml`

### What L2 currently asserts

Test files live under
`AmakaFlowCompanion/AmakaFlowCompanionTests/CJ01/`:

- `AMA1839_CJ01_WorkoutCompletionRequest_EncodingTests.swift` — Save & End
  request encoding: snake_case keys, ISO8601 millis, empty
  heart_rate_samples preserved as `[]`, executionLog round-trips through
  `AnyCodable`, source channel emission (phone vs apple_watch).
- `AMA1839_CJ01_GeneratedSchemas_DecodingTests.swift` — Verify-step
  response mapping: `Components.Schemas.PlannedListResponse`,
  `WorkoutCompletionResponse`, `WorkoutCompletionSummary`. Pins
  hand-coded `WorkoutCompletionResponse.resolvedCompletionId`
  fallback (completion_id -> id -> "unknown" sentinel).
- `AMA1839_CJ01_SyncEngine_RequestIdTests.swift` — local state
  transition: handler-arg `request_id` matches the persisted
  `sync_queue.request_id` row, three retry attempts each get a fresh
  valid UUID. Complements existing `SyncQueueRequestIdTests` (AMA-1823).
- `AMA1839_CJ01_AcceptedSuggestions_ReplaceOnAcceptTests.swift` — replace-
  on-accept (AMA-1815): atomic prior-pair tombstone in the same
  transaction as the new accept; sync_queue gets a delete per superseded
  row + an upsert for the new pair; `userId` invariant rejects cross-user
  writes.
- `AMA1839_CJ01_HydrateIncoming_PersistenceReloadTests.swift` — Reopen
  step: write the accepted pair to a file-backed GRDB DB, drop the
  AppDatabase, re-open a fresh AppDatabase against the same path,
  re-query `WorkoutEventsRepository.todayPlan` (the same query
  `WorkoutsViewModel.hydrateIncoming` wraps) and assert the workout
  hydrates exactly once. Tombstoned rows do NOT resurface.

---

## CJ-02 / CJ-03 / CJ-04

Not yet implemented at any layer. Per the blueprint:

> Do not expand beyond one pilot critical journey until CJ-01 has
> produced two consecutive trustworthy CI runs and one trustworthy
> local developer run under the new model.
