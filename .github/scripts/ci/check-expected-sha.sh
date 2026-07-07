#!/usr/bin/env bash
# AMA-2281 — Abort stale workflow_dispatch when main HEAD != expected_sha.
# Prevents hour-burn uploads from dispatches queued against an old main commit.
set -euo pipefail

EXPECTED="${1:-}"
if [ -z "$EXPECTED" ]; then
  echo "No expected_sha provided — SHA guard skipped."
  exit 0
fi

git fetch origin main --depth=1
MAIN_HEAD="$(git rev-parse origin/main)"
EXPECTED_NORM="${EXPECTED:0:40}"
MAIN_NORM="${MAIN_HEAD:0:40}"

echo "main HEAD:  $MAIN_HEAD"
echo "expected:   $EXPECTED"

if [ "$MAIN_NORM" != "$EXPECTED_NORM" ]; then
  echo "::error::Stale dispatch — origin/main ($MAIN_HEAD) != expected_sha ($EXPECTED). Aborting before archive."
  exit 1
fi

echo "✅ SHA guard passed — main matches expected_sha."
