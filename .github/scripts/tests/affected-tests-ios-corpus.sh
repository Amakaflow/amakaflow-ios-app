#!/usr/bin/env bash
#
# affected-tests-ios-corpus.sh — fixture corpus for affected-tests-ios.sh.
#
# AMA-2442: the selection script is a required-check input; regressions in it
# silently skip tests. This corpus pins the exact NONE / FULL / pattern
# output for representative diffs, hermetically:
#   - AFFECTED_TESTS_CHANGED_FILES injects the changed-file list (no git)
#   - AFFECTED_TESTS_TEST_DIR points at a fixture test dir (no repo layout)
#
# Run from the repo root:  bash .github/scripts/tests/affected-tests-ios-corpus.sh
# CI: the `selection-corpus` job in workflow-lint.yml runs this on every
# .github/** PR.

set -uo pipefail

SCRIPT=".github/scripts/affected-tests-ios.sh"
if [ ! -f "$SCRIPT" ]; then
  echo "ERROR: run from the repo root (missing $SCRIPT)" >&2
  exit 2
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FIXDIR="$TMP/FixtureTests"
mkdir -p "$FIXDIR"
touch "$FIXDIR/EditorV2SessionTests.swift" \
      "$FIXDIR/EditorV2CommandTests.swift" \
      "$FIXDIR/EditorV2Tests.swift" \
      "$FIXDIR/BlockTests.swift"

PASS=0
FAIL=0

# check <name> <expected> <changed-file>...
# Pattern-list outputs are compared order-insensitively.
check() {
  local name="$1" expected="$2"
  shift 2
  local changed actual norm_a norm_e
  changed=$(printf '%s\n' "$@")
  actual=$(AFFECTED_TESTS_CHANGED_FILES="$changed" \
           AFFECTED_TESTS_TEST_DIR="$FIXDIR" \
           bash "$SCRIPT" 2>/dev/null)
  norm_a=$(echo "$actual" | tr ' ' '\n' | sort | xargs)
  norm_e=$(echo "$expected" | tr ' ' '\n' | sort | xargs)
  if [ "$norm_a" = "$norm_e" ]; then
    PASS=$((PASS + 1))
    echo "  ok   $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL $name"
    echo "       expected: $norm_e"
    echo "       actual:   $norm_a"
  fi
}

echo "affected-tests-ios corpus:"

# --- baseline behaviors that must not regress -------------------------------
check docs_only "NONE" \
  "README.md" "docs/notes.md"

check package_resolved_full "FULL" \
  "AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

check xcscheme_full "FULL" \
  "AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj/xcshareddata/xcschemes/AmakaFlowCompanion.xcscheme"

check source_exact_match "AmakaFlowCompanionTests/BlockTests" \
  "AmakaFlow/Models/Block.swift"

check source_plus_extension "AmakaFlowCompanionTests/EditorV2SessionTests" \
  "AmakaFlow/Models/EditorV2Session+Persistence.swift"

check source_stem_match "AmakaFlowCompanionTests/EditorV2CommandTests" \
  "AmakaFlow/Models/EditorV2CommandFoo.swift"

check source_unmapped_full "FULL" \
  "AmakaFlow/Services/ZzzUnmappable.swift"

check mixed_docs_and_source "AmakaFlowCompanionTests/BlockTests" \
  "README.md" "AmakaFlow/Models/Block.swift"

check watch_only_none "NONE" \
  "AmakaFlowCompanion/AmakaFlowWatch Watch App/WatchThing.swift"

# --- AMA-2442 Bug 1: test files select themselves ---------------------------
check test_file_only_selects_itself "AmakaFlowCompanionTests/EditorV2CommandTests" \
  "AmakaFlowCompanion/AmakaFlowCompanionTests/EditorV2CommandTests.swift"

check test_file_never_dropped_beside_mapped_source \
  "AmakaFlowCompanionTests/BlockTests AmakaFlowCompanionTests/EditorV2CommandTests" \
  "AmakaFlow/Models/Block.swift" \
  "AmakaFlowCompanion/AmakaFlowCompanionTests/EditorV2CommandTests.swift"

check test_file_deleted_or_renamed_full "FULL" \
  "AmakaFlowCompanion/AmakaFlowCompanionTests/EditorV2ZzzTests.swift"

check test_helper_full "FULL" \
  "AmakaFlowCompanion/AmakaFlowCompanionTests/TestHelpers.swift"

check test_fixture_resource_full "FULL" \
  "AmakaFlowCompanion/AmakaFlowCompanionTests/Fixtures/workout.json"

# --- AMA-2442 Bug 2: non-Swift risk files promote to FULL, not NONE ---------
check entitlements_full "FULL" \
  "AmakaFlowCompanion/AmakaFlowCompanion/AmakaFlowCompanion.entitlements"

check info_plist_full "FULL" \
  "AmakaFlowCompanion/AmakaFlowCompanion/Info.plist"

check xcconfig_full "FULL" \
  "AmakaFlowCompanion/Config/Debug.xcconfig"

check asset_catalog_full "FULL" \
  "AmakaFlow/Assets.xcassets/AppIcon.appiconset/Contents.json"

check app_resource_full "FULL" \
  "AmakaFlow/Resources/Localizable.xcstrings"

# --- AMA-2442: pbxproj-only must not silently skip tests --------------------
check pbxproj_only_full "FULL" \
  "AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj/project.pbxproj"

check pbxproj_plus_mapped_source_stays_mapped "AmakaFlowCompanionTests/BlockTests" \
  "AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj/project.pbxproj" \
  "AmakaFlow/Models/Block.swift"

echo
echo "corpus: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
