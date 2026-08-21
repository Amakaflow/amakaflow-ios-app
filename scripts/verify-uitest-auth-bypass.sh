#!/usr/bin/env bash
#
# AMA-2457 regression gate: the UITEST_CLERK_TEST_SESSION bypass must reach the
# authed shell on every launch, not most launches.
#
# The bug this guards was invisible for three months because it presents as
# flakiness. applyUITestBypass() sets isAuthenticated and deliberately leaves
# cachedToken nil, token()'s no-session path calls refreshFromClerk(), and that
# recomputed isAuthenticated from Clerk — which has no session under the bypass
# — routing the app back to sign-in. Whether you saw it depended on whether
# anything made an authenticated call before you looked. One machine lost that
# race 10 times out of 10; another won it about 2 in 8.
#
# So a single passing launch proves nothing here. Ten do.
#
# Usage: ./scripts/verify-uitest-auth-bypass.sh <app-path> [udid] [runs]
set -euo pipefail

APP_PATH="${1:?usage: verify-uitest-auth-bypass.sh <app-path> [udid] [runs]}"
BUNDLE_ID="com.myamaka.AmakaFlowCompanion"
RUNS="${3:-10}"

UDID="${2:-}"
if [[ -z "$UDID" ]]; then
  UDID=$(xcrun simctl list devices available | grep -oE '[A-F0-9-]{36}' | head -1)
fi
[[ -n "$UDID" ]] || { echo "no available simulator" >&2; exit 1; }

xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP_PATH"

authed() {
  # grep without -q so maestro is never killed by SIGPIPE, which set -o pipefail
  # would then report as "not authed".
  MAESTRO_CLI_NO_ANALYTICS=1 maestro --udid "$UDID" hierarchy 2>/dev/null \
    | grep -F af_tabbar >/dev/null
}

passed=0
for run in $(seq 1 "$RUNS"); do
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  sleep 1
  xcrun simctl launch "$UDID" "$BUNDLE_ID" \
    -UITEST_CLERK_TEST_SESSION "user_id=user_ama2457,email=baseline+clerk_test@amakaflow.dev,name=AMA2457" \
    -UITEST_SKIP_ONBOARDING true \
    -UITEST_SKIP_APPLE_WATCH true \
    -UITEST_USE_FIXTURES true >/dev/null 2>&1
  sleep 8
  if authed; then
    passed=$((passed + 1))
    echo "run $run: authed"
  else
    echo "run $run: SIGN-IN"
  fi
done

echo "$passed/$RUNS reached the authed shell"
[[ "$passed" -eq "$RUNS" ]] || { echo "FAIL: the bypass must be deterministic" >&2; exit 1; }
echo "ok"
