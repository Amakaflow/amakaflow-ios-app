#!/usr/bin/env bash
#
# check-singleton-escape.sh — enforce the AppDependencies seam (issue #314)
#
# Rule: services managed by AppDependencies must only be accessed via .shared
# inside AppDependencies.swift and the @main entry point. View and ViewModel
# files must go through the injected dependency container, not grab singletons
# directly.
#
# This script starts narrow — it enforces the services that have been fully
# migrated. Expand MANAGED_SERVICES as each service completes its migration.
#
# Usage: ./scripts/preflight/check-singleton-escape.sh [--root <dir>]

set -euo pipefail

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT"

# Services fully managed by AppDependencies — .shared must not appear outside
# the allowlisted files.
MANAGED_SERVICES=(
    "SyncEngine"
)

# Files allowed to reference these .shared singletons (the seam itself + @main).
ALLOWLIST_PATHS=(
    "AmakaFlow/DependencyInjection/AppDependencies.swift"
    "AmakaFlowCompanion/AmakaFlowCompanion/AmakaFlowApp.swift"
    "AmakaFlowCompanion/AmakaFlowCompanionTests/"
)

VIOLATIONS=0

for service in "${MANAGED_SERVICES[@]}"; do
    pattern="${service}\\.shared"

    # Search all Swift files, then filter out the allowlisted paths.
    while IFS= read -r line; do
        file="${line%%:*}"
        allowed=false
        for allow in "${ALLOWLIST_PATHS[@]}"; do
            if [[ "$file" == *"$allow"* ]]; then
                allowed=true
                break
            fi
        done
        if ! $allowed; then
            echo "::error file=${file}::Singleton escape: ${service}.shared used outside the AppDependencies seam"
            echo "  $line"
            VIOLATIONS=$((VIOLATIONS + 1))
        fi
    done < <(grep -rn --include="*.swift" -E "$pattern" . 2>/dev/null || true)
done

if [ "$VIOLATIONS" -gt 0 ]; then
    echo ""
    echo "Found $VIOLATIONS singleton escape violation(s)."
    echo "Fix: route access through AppDependencies instead of using .shared directly."
    echo "Add new services to this script's MANAGED_SERVICES list as they are migrated."
    exit 1
fi

echo "Singleton escape check passed — no violations found."
