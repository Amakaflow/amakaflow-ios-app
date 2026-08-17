#!/usr/bin/env bash
#
# app-changed-ios-corpus.sh — fixture corpus for app-changed-ios.sh
# (AMA-2445). Hermetic; run from the repo root; CI runs it in
# workflow-lint's selection-corpus job.

set -uo pipefail

SCRIPT=".github/scripts/app-changed-ios.sh"
if [ ! -f "$SCRIPT" ]; then
  echo "ERROR: run from the repo root (missing $SCRIPT)" >&2
  exit 2
fi

PASS=0
FAIL=0

# check <name> <expected true|false> <changed-file>...
check() {
  local name="$1" expected="$2"
  shift 2
  local changed actual
  changed=$(printf '%s\n' "$@")
  actual=$(APP_CHANGED_FILES="$changed" bash "$SCRIPT" 2>/dev/null)
  if [ "$actual" = "$expected" ]; then
    PASS=$((PASS + 1))
    echo "  ok   $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL $name (expected $expected, got $actual)"
  fi
}

echo "app-changed corpus:"

# --- must BUILD -------------------------------------------------------------
check app_source_builds true "AmakaFlow/Models/Block.swift"
check companion_source_builds true "AmakaFlowCompanion/AmakaFlowCompanion/Thing.swift"
check xcodeproj_builds true "AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj/project.pbxproj"
check companion_app_builds true "AmakaFlowCompanion/AmakaFlowCompanionApp/App.swift"
check cold_launch_script_builds true "scripts/cold-launch-check.sh"
check pipeline_workflow_builds true ".github/workflows/pr-ios-tests.yml"
check ci_helper_script_builds true ".github/scripts/ci/select-xcode.sh"
check selection_script_builds true ".github/scripts/affected-tests-ios.sh"
check mixed_docs_and_source_builds true "README.md" "AmakaFlow/Models/Block.swift"

# --- must NOT build (the AMA-2445 fix) --------------------------------------
check unrelated_workflow_skips false ".github/workflows/claude-fix-reviews.yml"
check workflow_lint_skips false ".github/workflows/workflow-lint.yml"
check pr_hygiene_workflow_skips false ".github/workflows/pr-hygiene.yml"
check testflight_workflow_skips false ".github/workflows/ios-testflight.yml"
check hygiene_script_skips false ".github/scripts/pr-hygiene.sh"
check corpus_test_skips false ".github/scripts/tests/pr-hygiene-corpus.sh"
check cursor_rule_skips false ".cursor/rules/verify-before-done.mdc"
check docs_only_skips false "README.md" "docs/notes.md"
check tests_only_skips false "AmakaFlowCompanion/AmakaFlowCompanionTests/FooTests.swift"

echo
echo "corpus: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
