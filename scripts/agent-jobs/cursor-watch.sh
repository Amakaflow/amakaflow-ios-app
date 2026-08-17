#!/usr/bin/env bash
#
# cursor-watch.sh — the compiler loop Cursor cloud agents don't have (AMA-2447).
#
# Cursor's Linux cloud cannot compile Swift or run XCTest, which caused every
# compile-level miss in PRs #600/#604 (invented signatures, access-level
# violations). This job runs on a Mac (the mini, under Hermes/launchd/cron),
# builds every NEW push to a cursor/* branch, runs the impacted tests, and
# comments the verdict on the PR — closing the agent's feedback loop within
# minutes instead of a 25-minute GitHub CI round.
#
# Runner-agnostic and idempotent: single-shot invocation, per-branch SHA
# state in $STATE_DIR means an unchanged branch is a no-op. Any scheduler
# (Hermes, launchd, cron, by hand) just calls it repeatedly.
#
# Guardrails (JOB.md): comment-only — NEVER pushes, merges, labels, or
# closes anything. Requires: git, gh (authed), just, Xcode, a booted-able
# simulator. Deterministic — no model involved; Hermes may READ the
# comments to triage, but this script is pure toolchain.
#
# Usage:
#   cursor-watch.sh [--dry-run] [branch...]
#     branch...  specific cursor/* branches; default = all with new SHAs
#
# Env:
#   AMAKAFLOW_IOS_REPO  repo checkout root   (default: script's repo)
#   STATE_DIR           SHA memory           (default: ~/.amakaflow/cursor-watch)

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO="${AMAKAFLOW_IOS_REPO:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
STATE_DIR="${STATE_DIR:-$HOME/.amakaflow/cursor-watch}"
DRY_RUN=false

BRANCH_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    *) BRANCH_ARGS+=("$arg") ;;
  esac
done

mkdir -p "$STATE_DIR"
cd "$REPO" || { echo "ERROR: repo not found: $REPO" >&2; exit 2; }

git fetch --prune origin '+refs/heads/cursor/*:refs/remotes/origin/cursor/*' \
  >/dev/null 2>&1 || { echo "ERROR: git fetch failed" >&2; exit 2; }

# Which branches to look at
if [ ${#BRANCH_ARGS[@]} -gt 0 ]; then
  BRANCHES=("${BRANCH_ARGS[@]}")
else
  mapfile -t BRANCHES < <(git for-each-ref --format='%(refname:short)' \
    'refs/remotes/origin/cursor/*' | sed 's|^origin/||')
fi

if [ ${#BRANCHES[@]} -eq 0 ]; then
  echo "cursor-watch: no cursor/* branches"
  exit 0
fi

EXIT=0
for BRANCH in "${BRANCHES[@]}"; do
  SHA=$(git rev-parse "origin/${BRANCH}" 2>/dev/null) || {
    echo "skip ${BRANCH}: unknown branch"; continue; }
  STATE_FILE="$STATE_DIR/$(echo "$BRANCH" | tr '/' '_').sha"
  LAST=$(cat "$STATE_FILE" 2>/dev/null || echo "")

  if [ "$SHA" = "$LAST" ]; then
    echo "ok   ${BRANCH}: unchanged (${SHA:0:8})"
    continue
  fi

  # Only branches with an OPEN PR get built — no PR, no audience.
  PR=$(gh pr list --repo "$(gh repo view --json nameWithOwner -q .nameWithOwner)" \
    --head "$BRANCH" --state open --json number -q '.[0].number' 2>/dev/null || echo "")
  if [ -z "$PR" ]; then
    echo "skip ${BRANCH}: no open PR"
    echo "$SHA" > "$STATE_FILE"
    continue
  fi

  if $DRY_RUN; then
    echo "DRY  ${BRANCH}@${SHA:0:8} → would build+test, comment on PR #${PR}"
    continue
  fi

  echo "run  ${BRANCH}@${SHA:0:8} → PR #${PR}"
  WT=$(mktemp -d "${TMPDIR:-/tmp}/cursor-watch.XXXXXX")
  LOG="$WT/run.log"
  git worktree add --detach "$WT/repo" "$SHA" >/dev/null 2>&1 || {
    echo "ERROR: worktree add failed for ${BRANCH}" >&2; rm -rf "$WT"; EXIT=1; continue; }

  VERDICT="✅ build + impacted tests PASSED"
  if ! ( cd "$WT/repo" && just ios-build && just ios-test-impacted BASE=origin/main ) \
      > "$LOG" 2>&1; then
    VERDICT="❌ FAILED"
  fi

  # Compose the comment: verdict + failing tests / first errors + log tail.
  DETAILS=$(grep -E "error:|Test case .* failed" "$LOG" | sort -u | head -12)
  [ -z "$DETAILS" ] && DETAILS=$(tail -8 "$LOG")
  {
    echo "<!-- cursor-watch -->"
    echo "🤖 **cursor-watch** (Mac mini) — \`${SHA:0:8}\`: ${VERDICT}"
    echo
    echo '```'
    echo "$DETAILS"
    echo '```'
    echo "_local: \`just ios-build && just ios-test-impacted\` on macOS — full log retained on the runner._"
  } > "$WT/comment.md"

  if gh pr comment "$PR" --body-file "$WT/comment.md" >/dev/null 2>&1; then
    echo "     commented on PR #${PR}: ${VERDICT}"
    echo "$SHA" > "$STATE_FILE"
  else
    echo "ERROR: comment failed for PR #${PR} (state NOT advanced — will retry)" >&2
    EXIT=1
  fi

  git worktree remove --force "$WT/repo" >/dev/null 2>&1 || true
  rm -rf "$WT"
done

exit "$EXIT"
