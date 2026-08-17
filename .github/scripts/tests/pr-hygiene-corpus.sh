#!/usr/bin/env bash
#
# pr-hygiene-corpus.sh — fixture corpus for pr-hygiene.sh (AMA-2444).
# Same pattern as affected-tests-ios-corpus.sh: hermetic, exact expectations,
# run from the repo root; CI runs it in workflow-lint's selection-corpus job.

set -uo pipefail

SCRIPT=".github/scripts/pr-hygiene.sh"
if [ ! -f "$SCRIPT" ]; then
  echo "ERROR: run from the repo root (missing $SCRIPT)" >&2
  exit 2
fi

PASS=0
FAIL=0

# check <name> <expected-exit> [body] [diff]
check() {
  local name="$1" expected="$2" body="${3:-}" diff="${4:-}"
  PR_HYGIENE_BODY="$body" PR_HYGIENE_DIFF="$diff" bash "$SCRIPT" >/dev/null 2>&1
  local actual=$?
  if [ "$actual" = "$expected" ]; then
    PASS=$((PASS + 1))
    echo "  ok   $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL $name (expected exit $expected, got $actual)"
  fi
}

echo "pr-hygiene corpus:"

# --- close-words guard ------------------------------------------------------
check closes_ticket_blocked 1 \
  "Some work.

- Closes: https://linear.app/amakaflow/issue/AMA-2441"

check closes_bare_id_blocked 1 \
  "Fixes AMA-1234 and adds tests"

check resolves_blocked 1 \
  "resolves: AMA-99"

check part_of_allowed 0 \
  "- Part of https://linear.app/amakaflow/issue/AMA-2443
Related: AMA-2441"

check prose_mention_allowed 0 \
  "This closes the gap described in the audit. See AMA-2441 for context."

# --- evidence guard ---------------------------------------------------------
check bare_check_claim_blocked 1 \
  "| L2 (XCTest) | ✅ Pass | Command tests + Property tests |"

check linked_claim_allowed 0 \
  "| L2 (XCTest) | ✅ Pass | https://github.com/Amakaflow/amakaflow-ios-app/actions/runs/123/job/456 |"

check local_output_claim_allowed 0 \
  "| L2 (XCTest) | ✅ Pass | local: output pasted below |"

check non_table_checkmark_allowed 0 \
  "✅ Addressed in commit abc123 — see thread."

check na_row_allowed 0 \
  "| L1 (pytest) | N/A | Server-side |"

# --- XCTExpectFailure guard -------------------------------------------------
check added_xctexpectfailure_blocked 1 "" \
  '+        XCTExpectFailure("known broken", strict: false)'

check removed_xctexpectfailure_allowed 0 "" \
  '-        XCTExpectFailure("UI architecture: sheet @State captures stale copy", strict: false)'

check context_xctexpectfailure_allowed 0 "" \
  '         XCTExpectFailure("unchanged context line")'

# --- combined ---------------------------------------------------------------
check clean_pr_passes 0 \
  "- Part of AMA-2443

| L2 | ✅ | local: see Verify by |" \
  '+    func testNewThing() { XCTAssertTrue(true) }'

check both_violations_fail 1 \
  "Closes AMA-2443
| L2 | ✅ Pass | trust me |" \
  '+    XCTExpectFailure("later")'

echo
echo "corpus: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
