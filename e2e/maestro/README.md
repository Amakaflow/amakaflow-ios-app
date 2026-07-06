# Maestro E2E flows

## Post-TestFlight gating (ios-testflight.yml)

| Flow | Path | Runtime |
|---|---|---|
| Golden-path workout lifecycle | `flows/golden-path.yaml` | ~3–5 min |
| Coach feature-presence | `flows/coach/feature-presence.yaml` | ~1–2 min |

Both run after every TestFlight upload on a Debug sim build of the same commit.
Auth uses `_lib/clerk-signin.yaml` (AMA-1849 programmatic password session +
UI fallback).

## PR-label coach journeys (pr-ios-tests.yml, `run-maestro` label)

Deeper journeys stay **warn-only** on PRs because LLM steps can exceed 60s.
Feature-presence on TestFlight is the regression gate for entry points.

| Flow | Path |
|---|---|
| Coach chat send/receive | `flows/coach/journeys/coach-chat.yaml` |
| Fatigue advisor | `flows/coach/journeys/fatigue-advice.yaml` |
| Generate My Week | `flows/coach/journeys/generate-week.yaml` |
| PendingAction fixture | `flows/coach/journeys/pending-action-fixture.yaml` |
| CKW surface | `flows/coach/journeys/ckw-surface.yaml` |

## Reusable subflows (`_lib/`)

- `_lib/clerk-signin.yaml` — programmatic Clerk password session (AMA-2269) + UI fallback
- `_lib/dismiss-post-auth-onboarding.yaml` — post-auth card dismissal

## Legacy flat flows (warn-only on PR)

| Flow | Notes |
|---|---|
| `save-and-end.yaml` | Requires queued workout + signed-in state |
| `history-check.yaml` | Soft history screen check |
| `coach-message.yaml` | Superseded by `flows/coach/journeys/coach-chat.yaml` |

## Local run

```bash
# Build staging Debug sim (scripts/sim-build.sh)
scripts/sim-build.sh staging

UITEST_CLERK_PASSWORD="$(grep '^UITEST_CLERK_PASSWORD=' ~/.claude/projects/-Users-davidmini/secrets/keys.env | cut -d= -f2-)" \
  maestro test -e UITEST_CLERK_PASSWORD="$UITEST_CLERK_PASSWORD" \
  e2e/maestro/flows/coach/feature-presence.yaml
```

Maestro 2.6.1 is pinned in CI (`.github/workflows/ios-testflight.yml`).
