#!/usr/bin/env bash
#
# AMA-1840: reliable Debug-sim build wrapper for AmakaFlowCompanion.
#
# Bakes in the correct CLERK_PUBLISHABLE_KEY_* per environment so the
# resulting .app/Info.plist is fully populated. Without this, ad-hoc
# `xcodebuild build` invocations frequently miss the build-setting
# overrides and produce an .app that crashes at launch with
# `Fatal error: Missing CLERK_PUBLISHABLE_KEY_STAGING` (Environment.swift).
#
# Usage:
#   scripts/sim-build.sh                    # defaults: staging env, default sim
#   scripts/sim-build.sh staging            # explicit staging
#   scripts/sim-build.sh dev                # uses dev (solid-chicken-50) Clerk
#   scripts/sim-build.sh --sim <UDID>       # override the sim destination
#   scripts/sim-build.sh --print            # dry-run; print what would be built
#
# Env requirements: an iOS Simulator must be available. Default UDID is
# the iPhone 16 Pro Max sim (87AA26D0...) per ios-sim-test-loop-recipe.md.
# If that's unavailable, the script falls back to any booted iPhone sim,
# then any available iPhone sim (model-agnostic — don't assume iPhone 16),
# rather than creating one (creating sims has been flaky on this Mini per
# session-2026-05-07-ios-debugging-recap.md memory).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_SIM_UDID="87AA26D0-39FA-4A1B-A34E-D5C7BA8062DD"

# Per `clerk-instances-by-environment.md` memory.
CLERK_KEY_DEV='pk_test_c29saWQtY2hpY2tlbi01MC5jbGVyay5hY2NvdW50cy5kZXYk'
CLERK_KEY_STAGING='pk_test_cnVsaW5nLW1pdGUtODQuY2xlcmsuYWNjb3VudHMuZGV2JA'

ENV="staging"
SIM_UDID="$DEFAULT_SIM_UDID"
PRINT_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    dev|staging) ENV="$1"; shift ;;
    --sim) SIM_UDID="$2"; shift 2 ;;
    --print) PRINT_ONLY=1; shift ;;
    -h|--help)
      sed -n '3,/^set -/p' "$0" | sed 's/^# \{0,1\}//; /^set -/d'
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Pick the right key per env. Both DEV and STAGING are baked in even
# when only one env is the active runtime — the Info.plist holds both
# entries and Environment.swift picks at runtime based on AppEnvironment.
case "$ENV" in
  dev) PUB_KEY_STAGING="$CLERK_KEY_DEV" ;;  # dev runtime reads STAGING key per Environment.swift line 151
  staging) PUB_KEY_STAGING="$CLERK_KEY_STAGING" ;;
  *) echo "Unknown env: $ENV (expected dev|staging)" >&2; exit 2 ;;
esac

# Verify the requested sim exists. If not, fall back model-agnostically:
# any booted iPhone sim first, then any available iPhone sim. (AMA-2029: was
# iPhone-16-only, which dead-ended on Macs whose newest sim is e.g. iPhone 17.)
if ! xcrun simctl list devices available 2>/dev/null | grep -qi "$SIM_UDID"; then
  ALT=$(xcrun simctl list devices booted 2>/dev/null | grep -iE "iPhone" | head -1 | grep -oE '\([0-9A-Fa-f-]{36}\)' | tr -d '()' || true)
  if [[ -z "$ALT" ]]; then
    ALT=$(xcrun simctl list devices available 2>/dev/null | grep -iE "iPhone" | head -1 | grep -oE '\([0-9A-Fa-f-]{36}\)' | tr -d '()' || true)
  fi
  if [[ -n "$ALT" ]]; then
    echo "WARN: requested sim $SIM_UDID not found; falling back to iPhone sim $ALT" >&2
    SIM_UDID="$ALT"
  else
    echo "ERROR: sim $SIM_UDID not available + no iPhone simulator to fall back to." >&2
    echo "       Create/boot one in Simulator.app or pass --sim <UDID>." >&2
    exit 3
  fi
fi

CMD=(xcodebuild build
  -scheme AmakaFlowCompanion
  -project "$REPO_ROOT/AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj"
  -configuration Debug
  -destination "platform=iOS Simulator,id=$SIM_UDID"
  CLERK_PUBLISHABLE_KEY_STAGING="$PUB_KEY_STAGING"
  CLERK_PUBLISHABLE_KEY_PRODUCTION="$PUB_KEY_STAGING"
  CLERK_PUBLISHABLE_KEY_DEV="$CLERK_KEY_DEV"
  -allowProvisioningUpdates
)

if [[ "$PRINT_ONLY" == "1" ]]; then
  printf '%s\n' "${CMD[@]}"
  exit 0
fi

echo "[sim-build] env=$ENV sim=$SIM_UDID — building Debug AmakaFlowCompanion…"
"${CMD[@]}" 2>&1 | tee /tmp/sim-build.log | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:" | tail -5
STATUS=${PIPESTATUS[0]}

if [[ "$STATUS" != "0" ]]; then
  echo "[sim-build] FAILED — see /tmp/sim-build.log for details" >&2
  exit "$STATUS"
fi

# Locate the produced .app and verify the Clerk keys are non-empty.
DERIVED=$(xcodebuild -showBuildSettings \
  -scheme AmakaFlowCompanion \
  -project "$REPO_ROOT/AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj" \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" 2>/dev/null \
  | grep "    CONFIGURATION_BUILD_DIR " | head -1 | awk -F= '{print $2}' | xargs)

PLIST="$DERIVED/AmakaFlowCompanion.app/Info.plist"
if [[ ! -f "$PLIST" ]]; then
  echo "[sim-build] WARN: built .app's Info.plist not found at $PLIST" >&2
  exit 0
fi

echo "[sim-build] verifying Clerk keys in $PLIST"
for k in CLERK_PUBLISHABLE_KEY_DEV CLERK_PUBLISHABLE_KEY_STAGING CLERK_PUBLISHABLE_KEY_PRODUCTION; do
  v=$(/usr/libexec/PlistBuddy -c "Print :$k" "$PLIST" 2>/dev/null || echo "<MISSING>")
  if [[ -z "$v" || "$v" == "<MISSING>" || "$v" == \$\(* ]]; then
    echo "[sim-build] ✘ $k is empty/unsubstituted in Info.plist — Clerk auth WILL crash" >&2
    exit 4
  fi
  echo "[sim-build] ✓ $k = ${v:0:30}..."
done

echo "[sim-build] DONE. App at: $DERIVED/AmakaFlowCompanion.app"
echo "[sim-build] Install on sim: xcrun simctl install $SIM_UDID '$DERIVED/AmakaFlowCompanion.app'"
echo "[sim-build] Launch:        xcrun simctl launch $SIM_UDID com.amakaflow.AmakaFlowCompanion"
