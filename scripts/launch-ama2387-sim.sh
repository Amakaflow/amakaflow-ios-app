#!/usr/bin/env bash
#
# Isolated simulator launch for AMA-2387 only.
# Uses the dedicated "AF-2387-Test" device — does not shutdown other sims.
#
# Usage:
#   ./scripts/launch-ama2387-sim.sh           # build + install + launch
#   ./scripts/launch-ama2387-sim.sh --no-build  # install existing DerivedData app + launch
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Dedicated device — do not reuse shared iPhone 17 Pro Max / Air used by other worktrees.
SIM_UDID="${AMA2387_SIM_UDID:-2382D6CA-5A73-47CF-9E0B-C8B13FEBCC74}"
SIM_NAME="AF-2387-Test"
BUNDLE_ID="com.myamaka.AmakaFlowCompanion"
APP_DEFAULT="$HOME/Library/Developer/Xcode/DerivedData/AmakaFlowCompanion-aqlpxfldidfrqyeuduzltlulabol/Build/Products/Debug-iphonesimulator/AmakaFlowCompanion.app"

NO_BUILD=0
if [[ "${1:-}" == "--no-build" ]]; then
  NO_BUILD=1
fi

# Ensure dedicated sim still exists; recreate if deleted.
if ! xcrun simctl list devices available | grep -q "$SIM_UDID"; then
  echo "[ama2387] $SIM_NAME ($SIM_UDID) missing — recreating…"
  RUNTIME=$(
    xcrun simctl list runtimes |
      awk '/com\.apple\.CoreSimulator\.SimRuntime\.iOS-/ && $0 !~ /unavailable/ {
        match($0, /com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]+/)
        print substr($0, RSTART, RLENGTH)
      }' |
      sort -V |
      tail -1
  )
  if [[ -z "$RUNTIME" ]]; then
    echo "[ama2387] ERROR: no available iOS simulator runtime found" >&2
    exit 1
  fi
  SIM_UDID=$(xcrun simctl create "$SIM_NAME" \
    com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max \
    "$RUNTIME")
  echo "[ama2387] created $SIM_UDID — export AMA2387_SIM_UDID=$SIM_UDID for next time"
fi

echo "[ama2387] target sim: $SIM_NAME ($SIM_UDID)"
echo "[ama2387] booting (leaving other sims alone)…"
xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
xcrun simctl bootstatus "$SIM_UDID" -b
open -a Simulator --args -CurrentDeviceUDID "$SIM_UDID"

if [[ "$NO_BUILD" != "1" ]]; then
  echo "[ama2387] building for this UDID only…"
  "$REPO_ROOT/scripts/sim-build.sh" --sim "$SIM_UDID"
fi

APP="${AMA2387_APP:-$APP_DEFAULT}"
if [[ ! -d "$APP" ]]; then
  echo "[ama2387] ERROR: app not found at $APP" >&2
  echo "         Run without --no-build, or set AMA2387_APP=/path/to/AmakaFlowCompanion.app" >&2
  exit 1
fi

echo "[ama2387] installing…"
xcrun simctl install "$SIM_UDID" "$APP"

xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true

echo "[ama2387] launching with Today Actuals demo flags…"
SIMCTL_CHILD_AF_SESSION_IDENTITY='user_id=user_ama2387,email=ama2387@example.test,name=AMA2387' \
SIMCTL_CHILD_AF_SKIP_ONBOARDING=true \
SIMCTL_CHILD_AF_SKIP_APPLE_WATCH=true \
SIMCTL_CHILD_AF_USE_FIXTURES=true \
SIMCTL_CHILD_AF_FIXTURE_STATE=empty \
SIMCTL_CHILD_AF_DEMO_ACTUALS_TODAY=true \
xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID"

echo "[ama2387] running on $SIM_NAME only."
echo "[ama2387] In Simulator: Window → this device, or Device → $SIM_NAME"
echo "[ama2387] UDID=$SIM_UDID"
