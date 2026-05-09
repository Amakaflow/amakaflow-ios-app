# Maestro E2E flows

Flows wired into the AMA-1821 merge gate (`.github/workflows/maestro-flows.yml`).

| Flow | Status | Notes |
|---|---|---|
| `_lib/clerk-signin.yaml` | shared subflow | Real Clerk staging sign-in via the `+clerk_test` test mode (AMA-1837). Idempotent: no-op if already signed in. |
| `save-and-end.yaml` | wired (smoke) | Adapted from `/tmp/maestro-full-workout.yaml`. Calls `_lib/clerk-signin.yaml`, then drives the workout journey. |
| `history-check.yaml` | wired (smoke) | Adapted from `/tmp/maestro-history-check.yaml`. Soft assertion — confirms history screen renders. |
| `coach-message.yaml` | scaffold | Selectors are best-effort; flow is `continue-on-error` in CI until selectors are confirmed. |

## Shared sign-in subflow (AMA-1837)

`_lib/clerk-signin.yaml` performs a real Clerk staging sign-in so the three
flows above can graduate from "assume already signed in" to gated, end-to-end
authenticated runs (AMA-1830 will own the actual gating switch).

**How it works**

1. Launches the app with `notifications: deny` (only `launchApp` step in the
   chain — callers must not relaunch).
2. Fast-path: if the `Coach` tab is already visible (signed-in Home), it is
   a no-op.
3. Otherwise: enters `claude+clerk_test@amakaflow.dev`, taps Continue, and
   submits Clerk's universal test-mode code `424242`.
4. Asserts the `Coach` tab becomes visible within 30s; fails loudly if not.

**Preconditions**

- Build must point at the staging backend (Release config, or Debug with
  `CLERK_PUBLISHABLE_KEY_STAGING=pk_test_cnVsaW5nLW1pdGUtODQuY2xlcmsuYWNjb3VudHMuZGV2JA`).
  See `clerk-instances-by-environment.md` in session memory.
- The test account `claude+clerk_test@amakaflow.dev` must exist on the
  `ruling-mite-84` Clerk instance. Provision via Clerk Backend API:

  ```bash
  curl -sS -X POST https://api.clerk.com/v1/users \
    -H "Authorization: Bearer $CLERK_STAGING_SECRET_KEY" \
    -H "Content-Type: application/json" \
    -d '{"email_address":["claude+clerk_test@amakaflow.dev"],"first_name":"Claude","last_name":"Test"}'
  ```

  The `+clerk_test` subaddress is the documented Clerk pattern that pins
  the verification code to `424242` regardless of dashboard config.

**Caller contract**

Use as the FIRST step. Do NOT add your own `launchApp`:

```yaml
appId: com.myamaka.AmakaFlowCompanion
---
- runFlow: _lib/clerk-signin.yaml
- waitForAnimationToEnd:
    timeout: 3000
# ... your flow steps ...
```

## Local run

```bash
# Boot a sim (any iPhone 16/17). The recipe-default sim is
# 87AA26D0-39FA-4A1B-A34E-D5C7BA8062DD; if absent, use any booted iPhone.
xcrun simctl boot "iPhone 17 Pro" || true

# Build with the staging Clerk key (see ios-sim-test-loop-recipe.md).
SIM_ID=$(xcrun simctl list devices booted -j | python3 -c \
  "import sys,json;print(next(d['udid'] for r in json.load(sys.stdin)['devices'].values() for d in r if d['state']=='Booted'))")
CLERK_KEY="pk_test_cnVsaW5nLW1pdGUtODQuY2xlcmsuYWNjb3VudHMuZGV2JA"
xcodebuild build \
  -project AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj \
  -scheme AmakaFlowCompanion \
  -configuration Debug \
  -destination "id=$SIM_ID" \
  -derivedDataPath build/sim \
  CLERK_PUBLISHABLE_KEY_PRODUCTION="$CLERK_KEY" \
  CLERK_PUBLISHABLE_KEY_STAGING="$CLERK_KEY"

# Install + run
xcrun simctl install "$SIM_ID" \
  build/sim/Build/Products/Debug-iphonesimulator/AmakaFlowCompanion.app

maestro --device="$SIM_ID" test e2e/maestro/_lib/clerk-signin.yaml
maestro --device="$SIM_ID" test e2e/maestro/save-and-end.yaml
maestro --device="$SIM_ID" test e2e/maestro/history-check.yaml
maestro --device="$SIM_ID" test e2e/maestro/coach-message.yaml
```

## CI

Runs as the `maestro-flow-tests` job in `.github/workflows/maestro-flows.yml`,
gated on `main`. The job reuses the iOS build/sim setup from `ios-tests.yml`
and only runs after the unit-test step passes.
