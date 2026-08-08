#!/usr/bin/env bash
# Launch AmakaFlowCompanion on the booted iPhone sim with fixture library +
# friends demo seed (DEBUG InMemoryFriendsSharingService) for manual dogfood.
set -euo pipefail

BUNDLE_ID="com.myamaka.AmakaFlowCompanion"
SIM_UDID="${1:-}"
if [[ -z "$SIM_UDID" ]]; then
  SIM_UDID=$(xcrun simctl list devices booted 2>/dev/null | grep -iE "iPhone" | head -1 | grep -oE '\([0-9A-Fa-f-]{36}\)' | tr -d '()' || true)
fi
if [[ -z "$SIM_UDID" ]]; then
  echo "ERROR: no booted iPhone simulator. Boot one, or pass UDID as arg." >&2
  exit 3
fi

xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true
open -a Simulator --args -CurrentDeviceUDID "$SIM_UDID" 2>/dev/null || true

echo "[ama-2389] launching $BUNDLE_ID on $SIM_UDID with fixtures + friends demo…"
xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID" \
  -UITEST_CLERK_TEST_SESSION "user_id=user_ama2389_dogfood,email=claude+clerk_test@amakaflow.dev,name=AMA2389 Dogfood" \
  -UITEST_SKIP_ONBOARDING true \
  -UITEST_SKIP_APPLE_WATCH true \
  -UITEST_USE_FIXTURES true

cat <<EOF

Manual run-through (demo friends already seeded):
  1. Profile → Friends row (under week dots) → Edit/− remove / + Add friend / requests
  2. Library → open HIIT Follow-Along → Share → pick Marcus → Send (toast)
  3. Library FAB → From friends → Look inside → Save (or HIIT remixed → dup card)
  4. Confirm badges on Profile Friends + ＋ From friends decrement after dismiss/save

EOF
