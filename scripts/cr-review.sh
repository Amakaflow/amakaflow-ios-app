#!/usr/bin/env bash
#
# AMA-1845: CodeRabbit CLI wrapper that stashes Xcode build artifacts
# before invoking `coderabbit review` and restores them after.
#
# Why this exists:
#   The CodeRabbit CLI (v0.4.5+) walks the working tree to send context
#   to its server-side review service and ignores .gitignore. On
#   amakaflow-ios-app the working tree can balloon to ~10 GB because:
#
#     - build/                          (CI-cached Xcode build output)
#     - AmakaFlowCompanion/DerivedData/ (CI-cached Xcode DerivedData)
#     - AmakaFlowCompanion/.spm/        (CI-cached SPM checkouts)
#
#   These paths are CI-cached on purpose (see .github/workflows/*.yml +
#   docs/architecture/ci-vs-local-build-paths.md) and must NOT be moved
#   permanently. But locally they cause the CR review service to OOM
#   with `TRPCClientError: Out of memory`. See memory:
#   coderabbit-cli-oom-root-cause.md.
#
# What this script does:
#   1. mv each artifact dir to a unique /tmp staging path.
#   2. Run `coderabbit review` with whatever args the user passed.
#   3. mv each dir back, even on failure / Ctrl-C.
#
# Usage:
#   scripts/cr-review.sh                    # plain review against base branch
#   scripts/cr-review.sh --agent            # agent-mode JSON output
#   scripts/cr-review.sh --type uncommitted # only uncommitted changes
#   scripts/cr-review.sh --base develop     # any other coderabbit flags
#
# Requires: `coderabbit` on PATH (Homebrew: `brew install coderabbit`).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

if ! command -v coderabbit >/dev/null 2>&1; then
  echo "ERROR: coderabbit CLI not on PATH. Install via 'brew install coderabbit'." >&2
  exit 127
fi

# Paths to stash. Edit only if a new CI-cached artifact dir is added to
# the workspace (and update the memory + AMA-1845 doc when you do).
ARTIFACT_DIRS=(
  "build"
  "AmakaFlowCompanion/DerivedData"
  "AmakaFlowCompanion/.spm"
)

STASH_ROOT="$(mktemp -d -t cr-review-stash-XXXXXX)"
RESTORED=0

restore() {
  if [[ "$RESTORED" == "1" ]]; then
    return
  fi
  RESTORED=1
  for dir in "${ARTIFACT_DIRS[@]}"; do
    src="$STASH_ROOT/$(echo "$dir" | tr '/' '_')"
    if [[ -e "$src" ]]; then
      mkdir -p "$(dirname "$dir")"
      mv "$src" "$dir"
    fi
  done
  rmdir "$STASH_ROOT" 2>/dev/null || true
  echo "[cr-review] restored Xcode artifact dirs from $STASH_ROOT"
}

trap restore EXIT INT TERM HUP

echo "[cr-review] stashing Xcode artifact dirs to $STASH_ROOT"
for dir in "${ARTIFACT_DIRS[@]}"; do
  if [[ -e "$dir" ]]; then
    dst="$STASH_ROOT/$(echo "$dir" | tr '/' '_')"
    mv "$dir" "$dst"
    echo "[cr-review]   moved $dir → $dst"
  fi
done

echo "[cr-review] running: coderabbit review $*"
set +e
coderabbit review "$@"
STATUS=$?
set -e

# `restore` runs via the EXIT trap.
exit "$STATUS"
