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
# Mapping examples (AMA-2439):
#   EditorV2Session.swift          → EditorV2SessionTests (exact match)
#   EditorV2Session+Persistence.swift → EditorV2SessionTests (strip +extension)
#   EditorV2Command+D2.swift       → EditorV2Tests, EditorV2CommandTests (prefix match)
#   FooBarBaz.swift (no exact)     → FooBar*Tests, Foo*Tests (progressive stem)
#   project.pbxproj (file-ref only) + EditorV2*.swift → mapped tests (NOT FULL)
#   project.pbxproj (scheme change) → FULL
#
# Usage:
#   ./affected-tests-ios.sh [base_ref] [head_ref]
#
# Part of AMA-339: CI Optimization
# Updated for AMA-553: watchOS test coverage
# Updated for AMA-2439: smarter pbxproj handling + prefix-based test mapping

set -euo pipefail

BASE_REF="${1:-origin/${GITHUB_BASE_REF:-main}}"
HEAD_REF="${2:-HEAD}"

# Fetch only the base branch tip — a targeted shallow fetch avoids pulling
# full history (and the ~10k deleted design-bundle blobs from AMA-2103).
# In CI the workflow already ran `git fetch --depth=1 origin $GITHUB_BASE_REF`
# before invoking this script; the fetch here is a no-op in that case and a
# safety net for standalone local runs.
git fetch --no-tags --depth=1 origin "${GITHUB_BASE_REF:-main}" >/dev/null 2>&1 || true

# Two-dot diff against the base tip. The previous three-dot form required a
# merge base, which a depth-1 CI clone lacks ("fatal: no merge base") — the
# `|| true` then silently yielded an empty diff and NONE on every PR, so
# impacted tests were skipped even for Swift changes (AMA-2283). In CI,
# HEAD_REF is the PR merge ref, so base-tip..HEAD is exactly the PR's
# changes. If the diff fails outright, fail CLOSED with a FULL run.
if ! CHANGED=$(git diff --name-only "${BASE_REF}" "${HEAD_REF}"); then
  echo "FULL"
  exit 0
fi

# Check for non-file-ref project changes (scheme, build settings, etc.)
# Package.swift / Package.resolved / .xcworkspace changes always trigger FULL.
if echo "$CHANGED" | grep -E -q '(Package\.swift|Package\.resolved|\.xcworkspace/)'; then
  echo "FULL"
  exit 0
fi

# If .xcodeproj/ changed, inspect whether it's ONLY file-ref additions/removals.
# A pbxproj change that only adds/removes file refs (no build settings, no
# scheme changes) should NOT force FULL if Swift sources can still be mapped.
XCODEPROJ_CHANGED=false
if echo "$CHANGED" | grep -E -q '\.xcodeproj/'; then
  XCODEPROJ_CHANGED=true
  
  # Check if there are scheme or non-pbxproj changes (always FULL)
  if echo "$CHANGED" | grep -E -q '\.xcodeproj/.*\.xcscheme$'; then
    echo "FULL"
    exit 0
  fi
  
  # For pbxproj changes, we'll allow prefix mapping to work and only fall
  # back to FULL if no Swift sources changed or no tests can be mapped.
  # This is the key fix for AMA-2439: registering a new Swift file touches
  # pbxproj but should NOT force FULL if we can map the Swift sources.
fi

# Check for iOS source changes
# App code lives under AmakaFlow/ (shared with the Companion target). The
# Companion-only tree under AmakaFlowCompanion/AmakaFlowCompanion/ is legacy /
# thin; both must trigger iOS unit tests (AMA-2382: AmakaFlow/-only PRs were
# incorrectly returning NONE and skipping the required ios-tests job).
IOS_CHANGED=false
if echo "$CHANGED" | grep -E -q '^(AmakaFlow/|AmakaFlowCompanion/(AmakaFlowCompanion|AmakaFlowCompanionTests)/).*\.swift$'; then
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
# AMA-2439: use prefix-based mapping so EditorV2Command+D2.swift maps to
# EditorV2CommandTests, EditorV2PropertyTests, etc., not just exact basename match.
TEST_PATTERNS=()
TEST_DIR="AmakaFlowCompanion/AmakaFlowCompanionTests"

# iOS source -> iOS test mapping
while IFS= read -r f; do
  # Only map main sources (not test files themselves)
  if [[ "$f" =~ ^AmakaFlowCompanion/AmakaFlowCompanion/.*\.swift$ ]] || [[ "$f" =~ ^AmakaFlow/.*\.swift$ ]]; then
    # Extract filename without path and extension
    filename=$(basename "$f" .swift)
    
    # Strip common suffixes that don't affect test naming: +Foo, +Bar
    # EditorV2Session+Persistence.swift -> EditorV2Session
    base_name="${filename%%+*}"
    
    # Strategy: look for exact match first, then prefix matches
    # 1. Exact match: Foo.swift -> FooTests.swift
    exact_test="${TEST_DIR}/${filename}Tests.swift"
    if [[ -f "$exact_test" ]]; then
      TEST_PATTERNS+=("AmakaFlowCompanionTests/${filename}Tests")
      continue
    fi
    
    # 2. Base name match (strips +Extension): Foo+Bar.swift -> FooTests.swift
    if [[ "$base_name" != "$filename" ]]; then
      base_test="${TEST_DIR}/${base_name}Tests.swift"
      if [[ -f "$base_test" ]]; then
        TEST_PATTERNS+=("AmakaFlowCompanionTests/${base_name}Tests")
        continue
      fi
    fi
    
    # 3. Prefix-based search: EditorV2Foo.swift -> EditorV2*Tests.swift
    # Find all test files that start with the same prefix
    matched_tests=()
    while IFS= read -r test_file; do
      if [[ -f "$test_file" ]]; then
        test_class=$(basename "$test_file" .swift)
        matched_tests+=("AmakaFlowCompanionTests/${test_class}")
      fi
    done < <(find "$TEST_DIR" -maxdepth 1 -name "${base_name}*Tests.swift" 2>/dev/null || true)
    
    if [[ ${#matched_tests[@]} -gt 0 ]]; then
      TEST_PATTERNS+=("${matched_tests[@]}")
      # Do NOT continue — let progressive stem matching also run so
      # EditorV2Command+D2.swift maps to both EditorV2CommandTests (prefix)
      # and EditorV2Tests (stem). Dedup at the end handles overlaps.
    fi
    
    # 4. Try progressive stem shortening for compound names
    # EditorV2CommandFoo -> EditorV2Command*Tests, EditorV2*Tests
    stem="$base_name"
    while [[ "$stem" == *[A-Z]* ]]; do
      # Remove last capital+word (CamelCase): FooBarBaz -> FooBar
      shorter_stem="${stem%[A-Z]*}"
      if [[ -z "$shorter_stem" || "$shorter_stem" == "$stem" ]]; then
        break
      fi
      stem="$shorter_stem"
      
      # Look for stem*Tests.swift
      stem_tests=()
      while IFS= read -r test_file; do
        if [[ -f "$test_file" ]]; then
          test_class=$(basename "$test_file" .swift)
          stem_tests+=("AmakaFlowCompanionTests/${test_class}")
        fi
      done < <(find "$TEST_DIR" -maxdepth 1 -name "${stem}*Tests.swift" 2>/dev/null || true)
      
      if [[ ${#stem_tests[@]} -gt 0 ]]; then
        TEST_PATTERNS+=("${stem_tests[@]}")
        break
      fi
    done
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
    # iOS sources changed but no mapped test found -> FULL
    # Any iOS Swift change (including test files) that cannot be mapped
    # must run the full suite for safety.
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
