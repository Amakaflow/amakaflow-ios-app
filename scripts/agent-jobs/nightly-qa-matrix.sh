#!/usr/bin/env bash
#
# nightly-qa-matrix.sh — nightly full-suite QA run on a Mac (AMA-2447/AMA-2446).
#
# v1 runs everything that EXISTS today and packages the evidence; the
# AMA-2446 scenario matrix grows into it (each new suite/flow is picked up
# automatically). Deterministic — no model involved. Hermes (or any
# scheduler) invokes it nightly and hands the digest to whatever triages
# (MiniMax volume triage, Claude escalation) — triage reads OUTPUT_DIR,
# it never re-runs the app itself.
#
# Stages:
#   1. just ios-build            (build-for-testing, persistent DerivedData)
#   2. just ios-test-full        (entire AmakaFlowCompanionTests suite)
#   3. maestro test e2e/maestro/ (all flows; skipped if maestro missing)
# Artifacts per run under $OUTPUT_DIR/<UTC timestamp>/:
#   build.log, tests.log, TestResults.xcresult, maestro.log,
#   maestro-output/, summary.md  (the digest — verdict per stage,
#   failing test identifiers, log tails)
#
# Guardrails (JOB.md): reads/writes ONLY the repo checkout, DerivedData,
# and OUTPUT_DIR. Fixture/staging accounts only — this script must never
# be given production credentials. Exit 0 = all green, 1 = failures
# (digest still written), 2 = setup error.
#
# Usage: nightly-qa-matrix.sh [--dry-run]
# Env:
#   AMAKAFLOW_IOS_REPO  repo checkout root  (default: script's repo)
#   OUTPUT_DIR          artifact root       (default: ~/.amakaflow/qa-runs)

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO="${AMAKAFLOW_IOS_REPO:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
OUTPUT_ROOT="${OUTPUT_DIR:-$HOME/.amakaflow/qa-runs}"
DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

cd "$REPO" || { echo "ERROR: repo not found: $REPO" >&2; exit 2; }

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
RUN_DIR="$OUTPUT_ROOT/$STAMP"

if $DRY_RUN; then
  echo "DRY nightly-qa-matrix"
  echo "  repo:      $REPO @ $(git rev-parse --short HEAD) ($(git rev-parse --abbrev-ref HEAD))"
  echo "  artifacts: $RUN_DIR"
  echo "  stage 1:   just ios-build"
  echo "  stage 2:   just ios-test-full"
  if command -v maestro >/dev/null && [ -d e2e/maestro ]; then
    echo "  stage 3:   maestro test e2e/maestro/ ($(find e2e/maestro -name '*.yaml' | wc -l | tr -d ' ') flows)"
  else
    echo "  stage 3:   SKIPPED (maestro or e2e/maestro missing)"
  fi
  exit 0
fi

mkdir -p "$RUN_DIR"
FAIL=0
declare -a SUMMARY

run_stage() { # <name> <logfile> <cmd...>
  local name="$1" log="$2"
  shift 2
  echo "stage ${name}..."
  if "$@" > "$log" 2>&1; then
    SUMMARY+=("✅ ${name}")
  else
    SUMMARY+=("❌ ${name}")
    FAIL=1
  fi
}

run_stage "build" "$RUN_DIR/build.log" just ios-build

if [ "$FAIL" -eq 0 ]; then
  run_stage "unit-full" "$RUN_DIR/tests.log" just ios-test-full
  # Preserve the result bundle regardless of outcome.
  if [ -d "AmakaFlowCompanion/TestResults" ]; then
    cp -R "AmakaFlowCompanion/TestResults" "$RUN_DIR/TestResults.xcresult" 2>/dev/null || true
  fi
else
  SUMMARY+=("⏭️ unit-full (build failed)")
fi

if command -v maestro >/dev/null && [ -d e2e/maestro ] && [ "$FAIL" -eq 0 ]; then
  run_stage "maestro" "$RUN_DIR/maestro.log" \
    maestro test e2e/maestro/ --format junit --output "$RUN_DIR/maestro-output"
elif [ "$FAIL" -ne 0 ]; then
  SUMMARY+=("⏭️ maestro (build failed)")
else
  SUMMARY+=("⏭️ maestro (not installed or no flows)")
fi

# ---- digest -----------------------------------------------------------------
{
  echo "# Nightly QA — ${STAMP}"
  echo
  echo "repo: \`$(git rev-parse --short HEAD)\` on \`$(git rev-parse --abbrev-ref HEAD)\`"
  echo
  for line in "${SUMMARY[@]}"; do echo "- ${line}"; done
  echo
  for log in tests.log maestro.log build.log; do
    [ -f "$RUN_DIR/$log" ] || continue
    FAILS=$(grep -E "error:|Test case .* failed|\[Failed\]" "$RUN_DIR/$log" | sort -u | head -20)
    if [ -n "$FAILS" ]; then
      echo "## ${log}"
      echo '```'
      echo "$FAILS"
      echo '```'
    fi
  done
  echo
  echo "_artifacts: ${RUN_DIR}_"
} > "$RUN_DIR/summary.md"

echo
cat "$RUN_DIR/summary.md"
exit "$FAIL"
