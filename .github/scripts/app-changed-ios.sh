#!/usr/bin/env bash
#
# app-changed-ios.sh — should the iOS PR pipeline BUILD the simulator app?
#
# AMA-2445: previously any file under .github/workflows/ counted as an
# app/entrypoint change, so a one-line edit to an unrelated workflow
# (e.g. claude-fix-reviews.yml, PR #602) paid a ~15-min macOS build.
# Only files that participate in the build path can affect the build:
#   - app sources / project file / companion app target
#   - the cold-launch consumer script
#   - the iOS pipeline workflow itself + its CI helper scripts + the
#     affected-tests selection script
# Everything else under .github/ builds nothing.
#
# Output: "true" or "false" on stdout. Fails CLOSED ("true") if the diff
# cannot be computed (AMA-2283 lesson: a silent empty diff skipped builds).
#
# Test seam (used by .github/scripts/tests/app-changed-ios-corpus.sh):
#   APP_CHANGED_FILES  newline-separated changed files (skips git)
#
# Usage: ./app-changed-ios.sh [base_ref] [head_ref]

set -uo pipefail

BASE_REF="${1:-origin/${GITHUB_BASE_REF:-main}}"
HEAD_REF="${2:-HEAD}"

if [[ -n "${APP_CHANGED_FILES:-}" ]]; then
  CHANGED="$APP_CHANGED_FILES"
else
  # Two-dot diff against the base tip (depth-1 clones lack a merge base
  # for three-dot). If the diff fails outright, fail CLOSED — build.
  if ! CHANGED=$(git diff --name-only "${BASE_REF}" "${HEAD_REF}"); then
    echo "::warning::git diff failed — failing closed (app_changed=true)" >&2
    echo "true"
    exit 0
  fi
fi

if echo "$CHANGED" | grep -qE '^(AmakaFlow/|AmakaFlowCompanion/AmakaFlowCompanion/|AmakaFlowCompanion/AmakaFlowCompanion\.xcodeproj/|AmakaFlowCompanion/AmakaFlowCompanionApp/|scripts/cold-launch-check\.sh|\.github/workflows/pr-ios-tests\.yml$|\.github/scripts/ci/|\.github/scripts/affected-tests-ios\.sh$)'; then
  echo "true"
else
  echo "false"
fi
