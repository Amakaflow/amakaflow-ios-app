# Completion contract check (AMA-1806)

Guards against the **Build-38 class** of bug: the iOS `WorkoutCompletionRequest`
wire payload drifting from mapper-api's strict server schema, producing a 422
in production that all iOS unit tests missed.

Two layers:

| Layer | Workflow | Gating? | Catches |
| -- | -- | -- | -- |
| **B — offline schema gate** | `ios-testflight.yml` → `completion-contract` job | ✅ blocks the archive | missing-required, wrong-type, **extra/misnamed field** (server `_StrictModel` reject) |
| **A — live nightly** | `completion-contract-nightly.yml` | ❌ non-gating (opens an issue on red) | everything B catches **+ runtime** rejections (DB constraints, `200 + success:false`) |

## How it works (B)

`scripts/preflight/validate_completion_contract.py`:
1. Fetches mapper-api's **public** `/openapi.json` from staging (no auth).
2. Extracts `components.schemas.WorkoutCompletionRequest` (+ resolves `$ref`s).
3. **Re-applies `additionalProperties: false`** on every object schema that has a
   `properties` block — because FastAPI does *not* emit it for `_StrictModel`,
   yet the server rejects extra fields at runtime. Free-form `Dict[str, Any]`
   fields (e.g. `heart_rate_samples`, `device_info`) keep `properties`-less /
   permissive schemas and are left untouched.
4. Validates each fixture in `AmakaFlowCompanionTests/Fixtures/CompletionPayloads/`.
   Any violation → exit 1 → the `testflight` archive job is skipped.

Run it locally:

```bash
python3 -m venv /tmp/v && /tmp/v/bin/pip install jsonschema
/tmp/v/bin/python scripts/preflight/validate_completion_contract.py \
  --openapi https://mapper-api.staging.amakaflow.com/openapi.json \
  --fixtures-dir AmakaFlowCompanion/AmakaFlowCompanionTests/Fixtures/CompletionPayloads
```

## Adding / updating a fixture (when iOS adds a field)

1. The fixtures are the **wire** payloads iOS POSTs to `/workouts/complete` —
   snake_case, matching the server model, NOT the iOS display model
   (`AmakaFlow/Models/WorkoutCompletion.swift`). The builder is
   `WorkoutCompletionService.postPhoneWorkoutCompletion`.
2. Add a `NN_<shape>.json` file under `CompletionPayloads/`. Cover a new shape
   when iOS introduces one (currently: local-first accepted suggestion,
   workout_event, follow-along, voice/manual).
3. Use **only fields that exist** on the server model
   (`mapper-api/backend/workout_completions.py` → `WorkoutCompletionRequest`
   + `HealthMetrics`). The gate will reject unknown fields — that's the point.
4. If iOS legitimately adds a field, the **server model must add it first**
   (and it must ship to staging) — otherwise the gate correctly fails, telling
   you iOS is ahead of the contract.
5. Run the local command above; get a clean `N/N valid` before pushing.

## When the gate fails

`❌ <fixture>: Additional properties are not allowed ('x' was unexpected)` →
iOS is sending a field the server doesn't accept (the Build-38 failure mode).
Either remove it from the iOS payload, or land the server field on staging first.
