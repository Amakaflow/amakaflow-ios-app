# Maestro E2E flows

Flows wired into the AMA-1821 merge gate (`.github/workflows/maestro-flows.yml`).

| Flow | Status | Notes |
|---|---|---|
| `save-and-end.yaml` | wired (smoke) | Adapted from `/tmp/maestro-full-workout.yaml`. Requires a queued workout + signed-in state. |
| `history-check.yaml` | wired (smoke) | Adapted from `/tmp/maestro-history-check.yaml`. Soft assertion — confirms history screen renders. |
| `coach-message.yaml` | scaffold | Selectors are best-effort; flow is `continue-on-error` in CI until selectors are confirmed. |

## Local run

```bash
xcrun simctl boot "iPhone 17 Pro" || true
maestro test e2e/maestro/save-and-end.yaml
maestro test e2e/maestro/history-check.yaml
maestro test e2e/maestro/coach-message.yaml
```

## CI

Runs as the `maestro-flow-tests` job in `.github/workflows/maestro-flows.yml`,
gated on `main`. The job reuses the iOS build/sim setup from `ios-tests.yml`
and only runs after the unit-test step passes.
