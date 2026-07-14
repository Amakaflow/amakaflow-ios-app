# AMA-2289 visual evidence — Today completed diary

Simulator / UITEST fixtures prove the diary without live Garmin/Strava hardware.

| File | What it shows |
| --- | --- |
| `01-today-empty.png` | Honest empty — no schedule/plan chrome |
| `02-today-populated.png` | Garmin + phone completions on Today rail |
| `03-completion-detail-no-edit.png` | Detail with verify/map/enrich; no Edit structure |
| `04-verify-action.png` | Verify action surface |

## How to capture

```bash
# Empty
maestro test e2e/maestro/ama-2289-visual-today-diary-empty.yaml

# Populated + detail
maestro test e2e/maestro/ama-2289-visual-today-diary-populated.yaml
```

Auth: `UITEST_CLERK_TEST_SESSION` + `UITEST_SKIP_ONBOARDING` + `UITEST_USE_FIXTURES`.

## Deferred

- Live FR965 / Fenix Garmin run verify → final TestFlight (same as AMA-2286).
- Amazfit pull → out of scope.
- Strava pull into completions: backend exists (`POST /strava/sync`); not yet exposed on mobile-BFF — diary reads `GET /workouts/completions` once synced.
