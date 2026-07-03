#!/usr/bin/env bash
# AMA-2271 — Run post-TestFlight Maestro smokes with self-diagnosing failure artifacts.
#
# On failure captures: Maestro debug output, simctl screenshot, view hierarchy,
# and a short simulator screen recording. Never logs secret values.
set -euo pipefail

: "${SIM_UDID:?SIM_UDID required}"
: "${MAESTRO_OUTPUT_DIR:=maestro-output}"

mkdir -p "$MAESTRO_OUTPUT_DIR"

log_env_probe() {
  if [[ -n "${UITEST_CLERK_PASSWORD:-}" ]]; then
    echo "UITEST_CLERK_PASSWORD: SET (length=${#UITEST_CLERK_PASSWORD})"
  else
    echo "::error::UITEST_CLERK_PASSWORD is not set — programmatic + UI Clerk sign-in will fail."
  fi
}

# Space-separated `flow.yaml:label` pairs. Bash arrays are not inherited by child
# scripts, so callers must pass a string env var (not `export arr=(...)`).
resolve_smoke_flow_specs() {
  local -a specs=()
  if [[ -n "${SMOKE_FLOW_SPECS:-}" ]]; then
    # shellcheck disable=SC2206
    specs=(${SMOKE_FLOW_SPECS})
  else
    specs=(
      "e2e/maestro/flows/golden-path.yaml:golden-path"
      "e2e/maestro/flows/coach/feature-presence.yaml:feature-presence"
    )
  fi
  SMOKE_FLOW_SPECS=("${specs[@]}")
}

capture_failure_evidence() {
  local label="$1"
  local evidence_dir="$MAESTRO_OUTPUT_DIR/${label}-failure-evidence"
  mkdir -p "$evidence_dir"

  echo "::group::Capture failure evidence for ${label}"
  xcrun simctl io "$SIM_UDID" screenshot "$evidence_dir/simctl-screenshot.png" \
    2>&1 | tee "$evidence_dir/simctl-screenshot.log" || true

  maestro hierarchy \
    > "$evidence_dir/view-hierarchy.txt" 2>&1 || true
  maestro hierarchy --compact \
    > "$evidence_dir/view-hierarchy.csv" 2>&1 || true

  # Last ~90s of simulator logs (auth / Clerk prints are NSLog/print).
  xcrun simctl spawn "$SIM_UDID" log show --style compact --last 90s \
    > "$evidence_dir/simulator-last-90s.log" 2>&1 || true

  if [[ -n "${VIDEO_PID:-}" ]]; then
    kill -INT "$VIDEO_PID" 2>/dev/null || true
    wait "$VIDEO_PID" 2>/dev/null || true
    if [[ -f "$evidence_dir/failure-recording.mp4" ]]; then
      echo "Saved screen recording: $evidence_dir/failure-recording.mp4"
    fi
  fi

  # Consolidate Maestro's default debug tree if present.
  if [[ -d "$HOME/.maestro/tests" ]]; then
    cp -R "$HOME/.maestro/tests/." "$evidence_dir/maestro-tests-mirror/" 2>/dev/null || true
  fi
  echo "::endgroup::"
}

run_smoke_flow() {
  local flow="$1"
  local label="$2"

  local flow_debug="$MAESTRO_OUTPUT_DIR/${label}-debug"
  local flow_test_output="$MAESTRO_OUTPUT_DIR/${label}-test-output"
  rm -rf "$flow_debug" "$flow_test_output"
  mkdir -p "$flow_debug" "$flow_test_output"

  local evidence_dir="$MAESTRO_OUTPUT_DIR/${label}-failure-evidence"
  rm -f "$evidence_dir/failure-recording.mp4"
  mkdir -p "$evidence_dir"

  # Short screen recording for the whole flow; stopped on failure.
  xcrun simctl io "$SIM_UDID" recordVideo --codec=h264 \
    "$evidence_dir/failure-recording.mp4" &
  VIDEO_PID=$!

  local -a maestro_env=(
    -e "UITEST_CLERK_PASSWORD=${UITEST_CLERK_PASSWORD:-}"
  )
  if [[ -n "${TODAY:-}" ]]; then
    maestro_env+=(-e "TODAY=$TODAY")
  fi

  set +e
  maestro test \
    --device "$SIM_UDID" \
    "${maestro_env[@]}" \
    --debug-output "$flow_debug" \
    --flatten-debug-output \
    --test-output-dir "$flow_test_output" \
    --format junit \
    --output "$MAESTRO_OUTPUT_DIR/${label}-junit.xml" \
    "$flow" 2>&1 | tee "$MAESTRO_OUTPUT_DIR/${label}.log"
  local status=${PIPESTATUS[0]}
  set -e

  if [[ "$status" -ne 0 ]]; then
    capture_failure_evidence "$label"
  else
    if [[ -n "${VIDEO_PID:-}" ]]; then
      kill -INT "$VIDEO_PID" 2>/dev/null || true
      wait "$VIDEO_PID" 2>/dev/null || true
      rm -f "$evidence_dir/failure-recording.mp4"
    fi
  fi
  VIDEO_PID=""

  return "$status"
}

log_env_probe
resolve_smoke_flow_specs

OVERALL=0
FAILED_LABELS=()

for spec in "${SMOKE_FLOW_SPECS[@]}"; do
  flow="${spec%%:*}"
  label="${spec##*:}"
  echo "::group::maestro test ${flow} (${label})"
  if ! run_smoke_flow "$flow" "$label"; then
    OVERALL=1
    FAILED_LABELS+=("$label")
  fi
  echo "::endgroup::"
done

if [[ ${#FAILED_LABELS[@]} -gt 0 ]]; then
  failed_flows="$(IFS=,; echo "${FAILED_LABELS[*]}")"
else
  failed_flows="none"
fi
echo "failed_flows=${failed_flows}" | tee "$MAESTRO_OUTPUT_DIR/summary.txt"

exit "$OVERALL"
