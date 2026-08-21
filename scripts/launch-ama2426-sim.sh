#!/usr/bin/env bash
#
# Isolated simulator launch for AMA-2426 Logbook mock fill-in.
# Opens the Actuals dogfood hub and (by default) jumps straight into the
# Logbook grid + wheels — no Clerk / live OAuth required.
#
# Usage:
#   ./scripts/launch-ama2426-sim.sh              # build + install + launch → Logbook (after)
#   ./scripts/launch-ama2426-sim.sh --live       # LIVE header + ticking elapsed (phone tracking feel)
#   ./scripts/launch-ama2426-sim.sh --companion  # COMPANION · PENDING banner (beside-watch feel)
#   ./scripts/launch-ama2426-sim.sh --hub        # land on dogfood menu (pick mode yourself)
#   ./scripts/launch-ama2426-sim.sh --today      # Today rail with AMA2387 demo cards → Fill in ›
#   ./scripts/launch-ama2426-sim.sh --boot-watch # also boot paired Watch sim (chrome only — see note)
#   ./scripts/launch-ama2426-sim.sh --no-build   # install existing build/sim app + launch
#
# Watch Simulator note:
#   WorkoutKit / native Workout app custom workouts do NOT run meaningfully on Watch
#   Simulator — Apple requires a physical watch for scheduled sample workouts. --boot-watch
#   only opens a paired watch for chrome/feel; use --companion on phone for the notepad UX.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIM_NAME="AF-2426-Logbook"
BUNDLE_ID="com.myamaka.AmakaFlowCompanion"
DERIVED_APP="$REPO_ROOT/build/sim/Build/Products/Debug-iphonesimulator/AmakaFlowCompanion.app"

MODE="autorun"   # autorun | live | companion | hub | today
NO_BUILD=0
BOOT_WATCH=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hub) MODE="hub"; shift ;;
    --live) MODE="live"; shift ;;
    --companion) MODE="companion"; shift ;;
    --today) MODE="today"; shift ;;
    --boot-watch) BOOT_WATCH=1; shift ;;
    --no-build) NO_BUILD=1; shift ;;
    -h|--help)
      sed -n '3,/^set -/p' "$0" | sed 's/^# \{0,1\}//; /^set -/d'
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Reuse dedicated UDID if set; otherwise find/create AF-2426-Logbook.
SIM_UDID="${AMA2426_SIM_UDID:-}"
if [[ -z "$SIM_UDID" ]]; then
  SIM_UDID=$(xcrun simctl list devices available | grep -F "$SIM_NAME" | grep -oE '\([0-9A-Fa-f-]{36}\)' | tr -d '()' | head -1 || true)
fi

if [[ -z "$SIM_UDID" ]] || ! xcrun simctl list devices available | grep -q "$SIM_UDID"; then
  echo "[ama2426] $SIM_NAME missing — creating…"
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
    echo "[ama2426] ERROR: no available iOS simulator runtime found" >&2
    exit 1
  fi
  DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max"
  if ! xcrun simctl list devicetypes | grep -q "$DEVICE_TYPE"; then
    DEVICE_TYPE=$(xcrun simctl list devicetypes | grep -i "iPhone" | tail -1 | grep -oE 'com\.apple\.CoreSimulator\.SimDeviceType\.[^ ]+' || true)
  fi
  SIM_UDID=$(xcrun simctl create "$SIM_NAME" "$DEVICE_TYPE" "$RUNTIME")
  echo "[ama2426] created $SIM_UDID — export AMA2426_SIM_UDID=$SIM_UDID for next time"
fi

echo "[ama2426] target sim: $SIM_NAME ($SIM_UDID) mode=$MODE"
echo "[ama2426] booting (leaving other sims alone)…"
xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
xcrun simctl bootstatus "$SIM_UDID" -b
open -a Simulator --args -CurrentDeviceUDID "$SIM_UDID"

if [[ "$BOOT_WATCH" == "1" ]]; then
  # Prefer the first Watch UDID listed under an active pair; else any available Watch.
  WATCH_UDID=$(
    xcrun simctl list pairs |
      awk '
        /\(active/ { want=1; next }
        want && /Watch:/ {
          if (match($0, /\([0-9A-Fa-f-]{36}\)/)) {
            print substr($0, RSTART+1, RLENGTH-2)
            exit
          }
        }
      ' || true
  )
  if [[ -z "$WATCH_UDID" ]]; then
    WATCH_UDID=$(
      xcrun simctl list devices available |
        grep -F "Apple Watch" |
        head -1 |
        grep -oE '[0-9A-Fa-f-]{36}' |
        head -1 || true
    )
  fi
  if [[ -n "$WATCH_UDID" ]]; then
    echo "[ama2426] booting Watch sim $WATCH_UDID (chrome only — no native WorkoutKit sample on sim)…"
    xcrun simctl boot "$WATCH_UDID" 2>/dev/null || true
    xcrun simctl bootstatus "$WATCH_UDID" -b || true
  else
    echo "[ama2426] WARN: no Watch simulator found to boot" >&2
  fi
fi

if [[ "$NO_BUILD" != "1" ]]; then
  echo "[ama2426] building into build/sim…"
  cd "$REPO_ROOT/AmakaFlowCompanion"
  BUILD_LOG="$(mktemp "${TMPDIR:-/tmp}/ama2426-sim-build.XXXXXX.log")"
  set +e
  set +o pipefail
  xcodebuild build \
    -project AmakaFlowCompanion.xcodeproj \
    -scheme AmakaFlowCompanion \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=$SIM_UDID" \
    -derivedDataPath "$REPO_ROOT/build/sim" \
    CLERK_PUBLISHABLE_KEY_STAGING='pk_test_cnVsaW5nLW1pdGUtODQuY2xlcmsuYWNjb3VudHMuZGV2JA' \
    CLERK_PUBLISHABLE_KEY_PRODUCTION='pk_test_cnVsaW5nLW1pdGUtODQuY2xlcmsuYWNjb3VudHMuZGV2JA' \
    CLERK_PUBLISHABLE_KEY_DEV='pk_test_c29saWQtY2hpY2tlbi01MC5jbGVyay5hY2NvdW50cy5kZXYk' \
    2>&1 | tee "$BUILD_LOG" | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:" | tail -20
  set -o pipefail
  set -e
  if ! grep -q "BUILD SUCCEEDED" "$BUILD_LOG"; then
    echo "[ama2426] BUILD FAILED — see $BUILD_LOG" >&2
    exit 1
  fi
fi

APP="${AMA2426_APP:-$DERIVED_APP}"
if [[ ! -d "$APP" ]]; then
  echo "[ama2426] ERROR: app not found at $APP" >&2
  echo "         Run without --no-build, or set AMA2426_APP=/path/to/AmakaFlowCompanion.app" >&2
  exit 1
fi

echo "[ama2426] installing…"
xcrun simctl install "$SIM_UDID" "$APP"
xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true

case "$MODE" in
  autorun|live|companion)
    EXTRA_ENV=()
    case "$MODE" in
      live)
        echo "[ama2426] launching dogfood → LIVE logbook…"
        EXTRA_ENV+=(SIMCTL_CHILD_AMA2426_LIVE=true)
        ;;
      companion)
        echo "[ama2426] launching dogfood → COMPANION logbook…"
        EXTRA_ENV+=(SIMCTL_CHILD_AMA2426_COMPANION=true)
        ;;
      *)
        echo "[ama2426] launching dogfood hub → Logbook (AMA2426_AUTORUN)…"
        ;;
    esac
    env \
      SIMCTL_CHILD_AMA2426_DEMO=true \
      SIMCTL_CHILD_AMA2426_AUTORUN=true \
      "${EXTRA_ENV[@]+"${EXTRA_ENV[@]}"}" \
      SIMCTL_CHILD_UITEST_SKIP_ONBOARDING=true \
      SIMCTL_CHILD_UITEST_SKIP_APPLE_WATCH=true \
      xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID"
    echo "[ama2426] You should see the Logbook grid (lower-body sample)."
    echo "         Tap KG/REPS → wheels · ✓ sets · Save log → RPE → Verified."
    if [[ "$MODE" == "companion" ]]; then
      echo "         Header: COMPANION · PENDING (watch notepad — not on Today until reconcile)."
      echo "         Native WorkoutKit sample workouts require a physical Apple Watch."
    elif [[ "$MODE" == "live" ]]; then
      echo "         Header: LIVE · mm:ss · LOGBOOK (phone tracking feel)."
    fi
    ;;
  hub)
    echo "[ama2426] launching dogfood hub menu…"
    SIMCTL_CHILD_AMA2426_DEMO=true \
    SIMCTL_CHILD_UITEST_SKIP_ONBOARDING=true \
    SIMCTL_CHILD_UITEST_SKIP_APPLE_WATCH=true \
    xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID"
    echo "[ama2426] Pick Live / Companion / Mock Logbook from the hub."
    ;;
  today)
    echo "[ama2426] launching Today with Actuals demo cards…"
    SIMCTL_CHILD_UITEST_CLERK_TEST_SESSION='user_id=user_ama2426,email=ama2426@example.test,name=AMA2426' \
    SIMCTL_CHILD_UITEST_SKIP_ONBOARDING=true \
    SIMCTL_CHILD_UITEST_SKIP_APPLE_WATCH=true \
    SIMCTL_CHILD_UITEST_USE_FIXTURES=true \
    SIMCTL_CHILD_UITEST_FIXTURE_STATE=empty \
    SIMCTL_CHILD_AMA2387_TODAY_DEMO=true \
    xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID"
    echo "[ama2426] Today → Fill in › → Set by set — the logbook."
    ;;
esac

echo "[ama2426] UDID=$SIM_UDID"
echo "[ama2426] Simulator: Window → $SIM_NAME (or Device → $SIM_NAME)"
