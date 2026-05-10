# Maestro E2E flows

Flows wired into the AMA-1821 merge gate (`.github/workflows/maestro-flows.yml`).

| Flow | Status | Notes |
|---|---|---|
| `save-and-end.yaml` | wired (smoke) | Adapted from `/tmp/maestro-full-workout.yaml`. Requires a queued workout + signed-in state. |
| `history-check.yaml` | wired (smoke) | Adapted from `/tmp/maestro-history-check.yaml`. Soft assertion — confirms history screen renders. |
| `coach-message.yaml` | scaffold | Selectors are best-effort; flow is `continue-on-error` in CI until selectors are confirmed. |
| `flows/workout-lifecycle/ama1839-cj01-signin-generate-saveend-evidence.yaml` | wired (evidence-only) | AMA-1839 CJ-01 L4. Full journey sign-in -> Generate -> Save & End -> Verify -> Reopen with 9 screenshot checkpoints. `continue-on-error: true` in CI per blueprint (L4 = evidence, not validator). |

## Reusable subflows (`_lib/`)

- `_lib/clerk-signin.yaml` — real Clerk staging sign-in via the documented
  `+clerk_test` subaddress + universal code `424242`. Idempotent; no-op if
  the Coach tab is already visible. Vendored from PR #200 (AMA-1837).

## Layout

The blueprint specifies `e2e/maestro/flows/<journey>/` for journey flows
and `e2e/maestro/_lib/` for reusable subflows. New flows follow this
layout starting with the AMA-1839 CJ-01 evidence flow. Migrating the
legacy flat flows (`save-and-end.yaml`, `history-check.yaml`,
`coach-message.yaml`) into the blueprint structure is an intentional
follow-up — out of scope for this PR to keep the diff focused on L4.

## Local run

```bash
xcrun simctl boot "iPhone 17 Pro" || true

# Legacy flat flows
maestro test e2e/maestro/save-and-end.yaml
maestro test e2e/maestro/history-check.yaml
maestro test e2e/maestro/coach-message.yaml

# CJ-01 L4 evidence flow (AMA-1839). Requires the staging-pointed build
# from scripts/sim-build.sh — Release config or Debug with all three
# CLERK_PUBLISHABLE_KEY_* values injected (see clerk-instances-by-environment.md).
maestro test e2e/maestro/flows/workout-lifecycle/ama1839-cj01-signin-generate-saveend-evidence.yaml
```

## CI

Runs as the `maestro-flow-tests` job in `.github/workflows/maestro-flows.yml`,
gated on `main`. The job reuses the iOS build/sim setup from `ios-tests.yml`
and only runs after the unit-test step passes.
