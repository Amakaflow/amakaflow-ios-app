#!/usr/bin/env bash
#
# affected-tests-ios.sh
#
# Analyzes git diff to determine which Swift tests to run.
# Used by CI to optimize test execution on pull requests.
#
# Output:
#   FULL  - Run all tests (project config changes)
#   NONE  - Skip tests (no relevant changes)
#   space-separated test targets - Run specific tests
#
# watchOS tests are handled by the separate watchos-tests CI job.
# This script only outputs iOS test targets.
#
# Usage:
#   ./affected-tests-ios.sh [base_ref] [head_ref]
#
# Part of AMA-339: CI Optimization
# Updated for AMA-553: watchOS test coverage

set -euo pipefail

BASE_REF="${1:-origin/${GITHUB_BASE_REF:-main}}"
HEAD_REF="${2:-HEAD}"

# Fetch remote refs for comparison
git fetch --no-tags origin "+refs/heads/*:refs/remotes/origin/*" >/dev/null 2>&1 || true
CHANGED=$(git diff --name-only "${BASE_REF}...${HEAD_REF}" || true)

# If Xcode project or Swift package config changes, safest is full test run
if echo "$CHANGED" | grep -E -q '(\.xcodeproj/|Package\.swift|Package\.resolved|\.xcworkspace/)'; then
  echo "FULL"
  exit 0
fi

# Check for iOS source changes
IOS_CHANGED=false
if echo "$CHANGED" | grep -E -q '^AmakaFlowCompanion/(AmakaFlowCompanion|AmakaFlowCompanionTests)/.*\.swift$'; then
  IOS_CHANGED=true
fi

# Check for watchOS source changes (AMA-553)
WATCH_CHANGED=false
if echo "$CHANGED" | grep -E -q '^AmakaFlowCompanion/(AmakaFlowWatch Watch App|AmakaFlowWatch Watch AppTests|AmakaFlowWatch Watch AppUITests)/'; then
  WATCH_CHANGED=true
fi

# If neither iOS nor watchOS sources changed, skip tests
if [[ "$IOS_CHANGED" == "false" && "$WATCH_CHANGED" == "false" ]]; then
  echo "NONE"
  exit 0
fi

# Map changed Swift source files -> expected test class candidates
TEST_PATTERNS=()

# iOS source -> iOS test mapping
while IFS= read -r f; do
  # Only map main sources (not test files themselves)
  if [[ "$f" =~ ^AmakaFlowCompanion/AmakaFlowCompanion/.*\.swift$ ]]; then
    # Extract filename without path and extension
    filename=$(basename "$f" .swift)

    # Common patterns: Foo.swift -> FooTests.swift
    # Also handle: FooViewModel.swift -> FooViewModelTests.swift
    test_file="AmakaFlowCompanion/AmakaFlowCompanionTests/${filename}Tests.swift"

    if [[ -f "$test_file" ]]; then
      # Format for xcodebuild -only-testing: TARGET/CLASS
      TEST_PATTERNS+=("AmakaFlowCompanionTests/${filename}Tests")
    fi
  fi
done <<< "$CHANGED"

# watchOS tests are handled by the separate watchos-tests CI job (AMA-553).
# This script only outputs iOS test targets for the ios-tests job.
# Watch test target names contain spaces which break shell word-splitting
# in the workflow's for-loop, so they must not be included here.

# Remove duplicates
if [[ ${#TEST_PATTERNS[@]} -gt 0 ]]; then
  UNIQUE_TESTS=($(printf "%s\n" "${TEST_PATTERNS[@]}" | sort -u))
else
  UNIQUE_TESTS=()
fi

if [[ ${#UNIQUE_TESTS[@]} -eq 0 ]]; then
  if [[ "$IOS_CHANGED" == "true" ]]; then
    # iOS sources changed but no mapped test found -> safer fallback
    echo "FULL"
  else
    # Only watchOS sources changed -> no iOS tests needed
    # (watchOS tests are handled by the separate watchos-tests job)
    echo "NONE"
  fi
  exit 0
fi

# Print as space-separated list (for iteration in workflow)
echo "${UNIQUE_TESTS[*]}"
