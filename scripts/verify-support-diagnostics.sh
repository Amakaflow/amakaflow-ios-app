#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project="$repo_root/AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj"
project_file="$project/project.pbxproj"
derived_data="${AMAKAFLOW_DERIVED_DATA:-$repo_root/AmakaFlowCompanion/DerivedData}"
destination="${AMAKAFLOW_TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro Max}"

diagnostic_tests=(
  DebugLogServiceDiagnosticScopeTests.swift
  DebugLogServiceDiagnosticsTests.swift
  DiagnosticBundlePreviewTests.swift
  DiagnosticEventStoreTestCase.swift
  DiagnosticEventStoreTests.swift
  DiagnosticLoadAuthorizationTests.swift
  DiagnosticRedactorTests.swift
  SupportDiagnosticsAccessClientTests.swift
  SupportDiagnosticsEntryTests.swift
  SupportDiagnosticsProbeTests.swift
  SupportDiagnosticsSessionTests.swift
)

plutil -lint "$project_file"

for test_file in "${diagnostic_tests[@]}"; do
  if ! grep -Fq "$test_file" "$project_file"; then
    echo "Missing diagnostics test target entry: $test_file" >&2
    exit 1
  fi
done

xcodebuild test -quiet \
  -project "$project" \
  -scheme AmakaFlowCompanion \
  -destination "$destination" \
  -derivedDataPath "$derived_data" \
  -only-testing:AmakaFlowCompanionTests/DebugLogServiceDiagnosticScopeTests \
  -only-testing:AmakaFlowCompanionTests/DebugLogServiceDiagnosticsTests \
  -only-testing:AmakaFlowCompanionTests/DiagnosticBundlePreviewTests \
  -only-testing:AmakaFlowCompanionTests/DiagnosticEventStoreTests \
  -only-testing:AmakaFlowCompanionTests/DiagnosticLoadAuthorizationTests \
  -only-testing:AmakaFlowCompanionTests/DiagnosticRedactorTests \
  -only-testing:AmakaFlowCompanionTests/SupportDiagnosticsAccessClientTests \
  -only-testing:AmakaFlowCompanionTests/SupportDiagnosticsEntryTests \
  -only-testing:AmakaFlowCompanionTests/SupportDiagnosticsProbeTests \
  -only-testing:AmakaFlowCompanionTests/SupportDiagnosticsSessionTests
