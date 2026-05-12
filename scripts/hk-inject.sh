#!/usr/bin/env bash
#
# AMA-1834 — HealthKit heart-rate injection for iOS Simulator
#
# Seeds the running simulator's HealthKit store with realistic heart-rate
# samples for the full-workout Maestro E2E flow. Work intervals ramp
# 60→160 BPM; rest intervals ramp 160→90 BPM.
#
# Mechanism:
#   Invokes `xcodebuild test-without-building` against the
#   AMA1834_HKInjectionHelper XCUITest, which uses HKHealthStore.save()
#   from within the test process (the only documented API for writing HK
#   samples to a sim without a running app or private entitlements).
#   `healthd_write` does NOT exist in Xcode 26 / CoreSimulator 1051.
#
# Usage (standalone):
#   ./scripts/hk-inject.sh \
#       --sim 87AA26D0-39FA-4A1B-A34E-D5C7BA8062DD \
#       --work-seconds 15 \
#       --rest-seconds 10 \
#       --intervals 3
#
# Usage (via Maestro runScript — env vars):
#   HK_PHASE=work_and_rest SIM_UDID=87AA... WORK_SECONDS=15 REST_SECONDS=10 INTERVALS=3 ./scripts/hk-inject.sh
#
# Output:
#   Stdout from xcodebuild (one [AMA1834-HKInject] line per sample).
#   Script exits 0 on success, non-zero on build/test failure.
#
# Notes:
#   - Requires a pre-built AmakaFlowCompanionUITests product (from
#     scripts/sim-build.sh or prior CI build). Runs test-without-building
#     to avoid a redundant compile during Maestro flow execution.
#   - Runs in the background when called from the Maestro runScript step
#     so that HK samples are written concurrently with the workout UI.
#   - -parallel-testing-enabled NO per memory coresimulator-disable-parallel-on-mini.md.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ── Defaults (overridable via env vars for Maestro runScript) ──────────────────
SIM_UDID="${SIM_UDID:-87AA26D0-39FA-4A1B-A34E-D5C7BA8062DD}"
WORK_SECONDS="${WORK_SECONDS:-15}"
REST_SECONDS="${REST_SECONDS:-10}"
INTERVALS="${INTERVALS:-3}"

# ── CLI arg parsing (for standalone use) ──────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sim)           SIM_UDID="$2";       shift 2 ;;
    --work-seconds)  WORK_SECONDS="$2";   shift 2 ;;
    --rest-seconds)  REST_SECONDS="$2";   shift 2 ;;
    --intervals)     INTERVALS="$2";      shift 2 ;;
    -h|--help)
      sed -n '4,/^set -/p' "$0" | sed 's/^# \{0,1\}//; /^set -/d'
      exit 0
      ;;
    *) echo "[hk-inject] Unknown arg: $1" >&2; exit 2 ;;
  esac
done

echo "[hk-inject] Starting HR injection via XCUITest: sim=$SIM_UDID work=${WORK_SECONDS}s rest=${REST_SECONDS}s intervals=$INTERVALS"

# ── Validate sim is booted ────────────────────────────────────────────────────
SIM_STATE=$(xcrun simctl list devices 2>/dev/null | grep "$SIM_UDID" | grep -oE "Booted|Shutdown" | head -1 || echo "Unknown")
if [[ "$SIM_STATE" != "Booted" ]]; then
  echo "[hk-inject] ERROR: sim $SIM_UDID is not booted (state=$SIM_STATE). Boot it first." >&2
  exit 3
fi

# ── Run the injection XCUITest ────────────────────────────────────────────────
# test-without-building: the UITests product must already be built.
# If not built, fall back to `test` (slower but self-contained).
DERIVED_DATA="$REPO_ROOT/AmakaFlowCompanion/DerivedData"

if [[ -d "$DERIVED_DATA/Build/Products/Debug-iphonesimulator/AmakaFlowCompanionTests-Runner.app" ]] || \
   [[ -d "$DERIVED_DATA/Build/Products/Debug-iphonesimulator/AmakaFlowCompanion.app" ]]; then
  TEST_CMD="test-without-building"
else
  echo "[hk-inject] WARN: UITests not pre-built; falling back to 'test' (slower)" >&2
  TEST_CMD="test"
fi

xcodebuild "$TEST_CMD" \
  -scheme AmakaFlowCompanion \
  -project "$REPO_ROOT/AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj" \
  -destination "platform=iOS Simulator,id=$SIM_UDID" \
  -derivedDataPath "$DERIVED_DATA" \
  -only-testing:AmakaFlowCompanionTests/AMA1834_HKInjectionHelper/testInjectWorkoutHeartRateSamples \
  -parallel-testing-enabled NO \
  HK_WORK_SECONDS="$WORK_SECONDS" \
  HK_REST_SECONDS="$REST_SECONDS" \
  HK_INTERVALS="$INTERVALS" \
  2>&1 | grep -E "\[AMA1834-HKInject\]|TEST SUCCEEDED|TEST FAILED|error:|warning:" | head -200

STATUS=${PIPESTATUS[0]}

if [[ "$STATUS" != "0" ]]; then
  echo "[hk-inject] HK injection FAILED (xcodebuild exit=$STATUS)" >&2
  exit "$STATUS"
fi

echo "[hk-inject] HK injection complete."
