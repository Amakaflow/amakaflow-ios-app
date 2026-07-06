#!/usr/bin/env bash
# AMA-2271 / AMA-2276 / AMA-2277 — Run post-TestFlight Maestro smokes with self-diagnosing
# failure artifacts, hard per-flow timeouts, and retry ONLY failed flows (not the suite).
#
# On failure or timeout captures: Maestro debug output, simctl screenshot, view
# hierarchy, and a short simulator screen recording. Never logs secret values.
set -euo pipefail

: "${SIM_UDID:?SIM_UDID required}"
: "${MAESTRO_OUTPUT_DIR:=maestro-output}"
: "${MAESTRO_FLOW_TIMEOUT_SECONDS:=360}"  # 6 min per flow (healthy golden-path ~3.5 min)
: "${SMOKE_FLOW_MAX_ATTEMPTS:=2}"

mkdir -p "$MAESTRO_OUTPUT_DIR"

CURRENT_LABEL=""
VIDEO_PID=""
FAILURE_REASON="assertion"

run_with_timeout() {
  local seconds="$1"
  shift
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout --signal=TERM --kill-after=30 "$seconds" "$@"
  elif command -v timeout >/dev/null 2>&1; then
    timeout --signal=TERM --kill-after=30 "$seconds" "$@"
  else
    echo "::error::GNU timeout (coreutils) required for Maestro hard-kill — install coreutils on the runner."
    "$@"
  fi
}

on_smoke_interrupt() {
  local rc=$?
  if [[ -n "$CURRENT_LABEL" ]]; then
    capture_failure_evidence "$CURRENT_LABEL" || true
    if [[ "$rc" -eq 124 || "$rc" -eq 137 ]]; then
      FAILURE_REASON="timeout"
      echo "failure_reason=timeout" >> "$MAESTRO_OUTPUT_DIR/summary.txt"
    fi
  fi
  if [[ -n "${VIDEO_PID:-}" ]]; then
    kill -INT "$VIDEO_PID" 2>/dev/null || true
    wait "$VIDEO_PID" 2>/dev/null || true
  fi
  return "$rc"
}

trap on_smoke_interrupt EXIT INT TERM

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

stop_failure_recording() {
  if [[ -n "${VIDEO_PID:-}" ]]; then
    kill -INT "$VIDEO_PID" 2>/dev/null || true
    run_with_timeout 15 wait "$VIDEO_PID" 2>/dev/null || kill -9 "$VIDEO_PID" 2>/dev/null || true
    VIDEO_PID=""
  fi
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
    stop_failure_recording
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

warm_simulator_for_retry() {
  echo "Warming simulator before retrying failed flow(s)..."
  open -a Simulator 2>/dev/null || true
  xcrun simctl bootstatus "$SIM_UDID" -b 2>/dev/null || true
  xcrun simctl terminate "$SIM_UDID" com.myamaka.AmakaFlowCompanion 2>/dev/null || true
  sleep 3
}

run_smoke_flow() {
  local flow="$1"
  local label="$2"
  CURRENT_LABEL="$label"

  local flow_debug="$MAESTRO_OUTPUT_DIR/${label}-debug"
  local flow_test_output="$MAESTRO_OUTPUT_DIR/${label}-test-output"
  rm -rf "$flow_debug" "$flow_test_output"
  mkdir -p "$flow_debug" "$flow_test_output"

  local evidence_dir="$MAESTRO_OUTPUT_DIR/${label}-failure-evidence"
  rm -f "$evidence_dir/failure-recording.mp4"
  mkdir -p "$evidence_dir"

  # Short screen recording for the whole flow; stopped on failure/timeout.
  xcrun simctl io "$SIM_UDID" recordVideo --codec=h264 \
    "$evidence_dir/failure-recording.mp4" &
  VIDEO_PID=$!

  local -a maestro_env=(
    -e "UITEST_CLERK_PASSWORD=${UITEST_CLERK_PASSWORD:-}"
  )

  set +e
  run_with_timeout "$MAESTRO_FLOW_TIMEOUT_SECONDS" \
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

  if [[ "$status" -eq 124 || "$status" -eq 137 ]]; then
    echo "::error::Maestro flow '${label}' timed out after ${MAESTRO_FLOW_TIMEOUT_SECONDS}s — hard-killed."
    FAILURE_REASON="timeout"
    stop_failure_recording
    capture_failure_evidence "$label"
    pkill -f "maestro.cli" 2>/dev/null || true
  elif [[ "$status" -ne 0 ]]; then
    stop_failure_recording
    capture_failure_evidence "$label"
    pkill -f "maestro.cli" 2>/dev/null || true
  else
    stop_failure_recording
    rm -f "$evidence_dir/failure-recording.mp4"
  fi
  VIDEO_PID=""
  CURRENT_LABEL=""

  return "$status"
}

log_env_probe
resolve_smoke_flow_specs

OVERALL=0
FAILED_LABELS=()
declare -a pending_specs=("${SMOKE_FLOW_SPECS[@]}")
attempt=1

while [[ ${#pending_specs[@]} -gt 0 && $attempt -le $SMOKE_FLOW_MAX_ATTEMPTS ]]; do
  echo "::group::Smoke attempt ${attempt}/${SMOKE_FLOW_MAX_ATTEMPTS} (${#pending_specs[@]} flow(s))"
  declare -a retry_specs=()

  for spec in "${pending_specs[@]}"; do
    flow="${spec%%:*}"
    label="${spec##*:}"
    echo "::group::maestro test ${flow} (${label})"
    if run_smoke_flow "$flow" "$label"; then
      echo "Flow '${label}' passed on attempt ${attempt}."
    else
      OVERALL=1
      FAILED_LABELS+=("$label")
      retry_specs+=("$spec")
      if [[ "$label" == "golden-path" ]]; then
        echo "golden-path failed — skipping remaining flows this attempt (shared auth/shell precondition)."
        break
      fi
    fi
    echo "::endgroup::"
  done

  echo "::endgroup::"

  if [[ ${#retry_specs[@]} -eq 0 ]]; then
    OVERALL=0
    FAILED_LABELS=()
    break
  fi

  if [[ $attempt -lt $SMOKE_FLOW_MAX_ATTEMPTS ]]; then
    warm_simulator_for_retry
  fi

  pending_specs=("${retry_specs[@]}")
  retry_specs=()
  attempt=$((attempt + 1))
done

if [[ ${#pending_specs[@]} -gt 0 ]]; then
  OVERALL=1
  FAILED_LABELS=()
  for spec in "${pending_specs[@]}"; do
    FAILED_LABELS+=("${spec##*:}")
  done
fi

if [[ ${#FAILED_LABELS[@]} -gt 0 ]]; then
  # De-dupe labels while preserving order.
  failed_flows="$(printf '%s\n' "${FAILED_LABELS[@]}" | awk '!seen[$0]++' | paste -sd, -)"
else
  failed_flows="none"
fi

{
  echo "failed_flows=${failed_flows}"
  echo "failure_reason=${FAILURE_REASON}"
} | tee "$MAESTRO_OUTPUT_DIR/summary.txt"

trap - EXIT INT TERM
exit "$OVERALL"
