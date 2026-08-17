#!/usr/bin/env bash
#
# pr-hygiene.sh — agent-integrity guards for PR bodies and diffs (AMA-2444).
#
# Two real incidents: a ticket auto-closed by a merge with scope unshipped
# (AMA-2438), and a PR validation table claiming tests passed that didn't
# compile (PR #600). These guards make both unmergeable.
#
# Checks:
#   body-close-words   PR body must not contain Closes/Fixes/Resolves AMA-…
#                      (tickets are closed by humans after acceptance)
#   body-evidence      any validation-table row (a `|`-delimited line)
#                      containing ✅ must carry evidence: an http(s) link
#                      or an explicit "local:" output reference
#   diff-xctexpect     the diff must not ADD XCTExpectFailure lines
#
# Inputs (env):
#   PR_HYGIENE_BODY        the PR body text (required for body checks)
#   PR_HYGIENE_DIFF        unified diff text (required for the diff check)
#   PR_HYGIENE_BODY_FILE   path to a file holding the PR body text
#   PR_HYGIENE_DIFF_FILE   path to a file holding the unified diff
#                          Use the *_FILE forms when the text is too large for
#                          an env string — a 169KB diff on PR #607 overflowed
#                          exec's per-string limit (E2BIG). A *_FILE form wins
#                          over its env-string counterpart when both are set.
# Either input may be omitted; only the checks with input run. CI passes both.
#
# Exit: 0 clean, 1 violations (each printed as ::error).

set -uo pipefail

FAIL=0

body="${PR_HYGIENE_BODY:-}"
diff="${PR_HYGIENE_DIFF:-}"
if [[ -n "${PR_HYGIENE_BODY_FILE:-}" ]]; then
  body="$(cat "$PR_HYGIENE_BODY_FILE")"
fi
if [[ -n "${PR_HYGIENE_DIFF_FILE:-}" ]]; then
  diff="$(cat "$PR_HYGIENE_DIFF_FILE")"
fi

if [[ -n "$body" ]]; then
  # --- close-words guard ----------------------------------------------------
  # GitHub closing keywords + a Linear "magic word" style reference.
  if echo "$body" | grep -qiE '(close[sd]?|fix(e[sd])?|resolve[sd]?)[[:space:]:]+([^ ]*linear\.app[^ ]*(AMA|ama)-[0-9]+|AMA-[0-9]+)'; then
    echo "::error::PR body uses a closing keyword with a ticket (Closes/Fixes/Resolves AMA-…). Use 'Part of AMA-…' — tickets are closed by a human after acceptance, never by a merge."
    FAIL=1
  fi

  # --- evidence guard -------------------------------------------------------
  # Validation-table rows that claim ✅ must link evidence. A row is any
  # markdown table line (starts with |). Accepted evidence: an http(s) URL
  # in the row, or the literal marker "local:" (pasted command output
  # elsewhere in the body, referenced explicitly).
  while IFS= read -r line; do
    case "$line" in
      \|*✅*)
        if ! echo "$line" | grep -qE 'https?://|local:'; then
          echo "::error::Unevidenced ✅ claim in validation table: '${line}'. Every ✅ row needs a link to the green CI job on the head SHA, or a 'local:' reference to pasted command output."
          FAIL=1
        fi
        ;;
    esac
  done <<< "$body"
fi

if [[ -n "$diff" ]]; then
  # --- XCTExpectFailure guard ----------------------------------------------
  # Only ADDED lines in .swift files count; removing one is progress, and
  # mentions in docs/scripts (including THIS guard's own corpus) are fine —
  # the guard's first live run flagged its own fixtures (PR #601).
  if echo "$diff" | awk '
      /^\+\+\+ / { file = $2; sub(/^b\//, "", file); next }
      /^\+/ && file ~ /\.swift$/ && /XCTExpectFailure/ { found = 1 }
      END { exit found ? 0 : 1 }
    '; then
    echo "::error::Diff ADDS XCTExpectFailure in a .swift file. Broken behavior must be fixed or flagged in the PR — not shipped green-washed. (Removals are fine.)"
    FAIL=1
  fi
fi

if [[ "$FAIL" -eq 0 ]]; then
  echo "pr-hygiene: clean"
fi
exit "$FAIL"
