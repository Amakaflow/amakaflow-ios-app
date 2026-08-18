#!/usr/bin/env bash
#
# App-baseline screenshot capture for the design-parity audit.
# Boots the AF-Baseline sim, installs the current Debug-iphonesimulator
# build, launches with the AMA-1843 mock session + fixtures via simctl
# (Maestro 2.6.1 launchApp arguments do not reach UITestEnvironment —
# simctl args do), then runs e2e/maestro/baseline-capture.yaml which
# attaches to the running app and screenshots each surface.
#
# Usage:
#   ./scripts/capture-baseline.sh [output-dir]
# Output: <output-dir default docs/app-baseline>/<YYYY-MM-DD>/*.png
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIM_NAME="AF-Baseline"
BUNDLE_ID="com.myamaka.AmakaFlowCompanion"
APP_PATH="$REPO_ROOT/AmakaFlowCompanion/build/sim/Build/Products/Debug-iphonesimulator/AmakaFlowCompanion.app"
OUT_ROOT="${1:-$REPO_ROOT/docs/app-baseline}"
OUT_DIR="$OUT_ROOT/$(date +%F)"

UDID=$(xcrun simctl list devices available | grep "$SIM_NAME" | grep -oE '[A-F0-9-]{36}' | head -1 || true)
if [[ -z "$UDID" ]]; then
  RUNTIME=$(xcrun simctl list runtimes | awk '/SimRuntime\.iOS-/ && $0 !~ /unavailable/ {match($0,/com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]+/); print substr($0,RSTART,RLENGTH)}' | sort -V | tail -1)
  UDID=$(xcrun simctl create "$SIM_NAME" "iPhone 17 Pro" "$RUNTIME")
fi
echo "[baseline] sim $SIM_NAME ($UDID)"

xcrun simctl boot "$UDID" 2>/dev/null || true
[[ -d "$APP_PATH" ]] || { echo "[baseline] ERROR: no sim build at $APP_PATH — build first" >&2; exit 1; }
xcrun simctl install "$UDID" "$APP_PATH"
# Auth (AMA-2457: the AMA-1843 mock bypass is launch-flaky — do NOT use it
# here). The baseline sim has a dedicated REAL Clerk user with a PERSISTED
# session: baseline+clerk_test@amakaflow.dev (created 2026-08-17 via the
# in-app signup UI, Clerk test-mode code 424242; password in the macOS
# login keychain under service "amakaflow-baseline-sim"). A plain launch
# restores that session — no bypass flags needed. If the session is ever
# lost (sim erased / app data cleared), re-run the one-time signup:
# see e2e/maestro/ signup notes in AMA-2457, or sign in manually with
#   security find-generic-password -s amakaflow-baseline-sim -w
authed() {
  MAESTRO_CLI_NO_ANALYTICS=1 maestro --udid "$UDID" hierarchy 2>/dev/null | grep -q af_tabbar
}

launched=0
for attempt in 1 2 3; do
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  sleep 2
  xcrun simctl launch "$UDID" "$BUNDLE_ID" \
    -UITEST_SKIP_ONBOARDING true \
    -UITEST_SKIP_APPLE_WATCH true \
    -UITEST_USE_FIXTURES true
  sleep 12
  if authed; then
    echo "[baseline] authed shell up (attempt $attempt)"
    launched=1
    break
  fi
  echo "[baseline] attempt $attempt: no authed shell — retrying"
done
if [[ "$launched" != "1" ]]; then
  echo "[baseline] ERROR: no authed shell after 3 attempts." >&2
  echo "[baseline] The persisted baseline session may be gone — re-run the one-time" >&2
  echo "[baseline] signup for baseline+clerk_test@amakaflow.dev (password in keychain:" >&2
  echo "[baseline]   security find-generic-password -s amakaflow-baseline-sim -w )" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
cd "$REPO_ROOT"
MAESTRO_CLI_NO_ANALYTICS=1 maestro --udid "$UDID" test e2e/maestro/baseline-capture.yaml

# Maestro writes to docs/app-baseline/<name>.png (flow-relative); move into dated dir.
shopt -s nullglob
for f in "$REPO_ROOT"/docs/app-baseline/*.png; do
  mv "$f" "$OUT_DIR/"
done
echo "[baseline] captured:"
ls -1 "$OUT_DIR"
