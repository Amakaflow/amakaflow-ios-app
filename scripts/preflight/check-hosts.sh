#!/usr/bin/env bash
# AMA-1777: pre-deploy validation that URLs in Environment.swift resolve.
#
# Background: on 2026-05-06 a TestFlight build defaulted to .production and
# crashed at the first API call because https://chat-api.amakaflow.com (and
# every sibling production host) doesn't exist in DNS. This script is the
# CI gate that prevents that class of bug from shipping again.
#
# Behaviour:
#   * Hard-fails on .staging URLs that don't resolve (CI must block).
#   * Soft-fails on .production URLs that don't resolve (CI logs warning
#     but exits 0). Production hostnames are a future deployment concern
#     and shouldn't block all staging PRs today. Flip with --strict-production
#     once those CNAMEs are stood up.
#
# Usage:
#   ./scripts/preflight/check-hosts.sh [path/to/Environment.swift]
#   ./scripts/preflight/check-hosts.sh --strict-production [path]
#
# Exit codes:
#   0 — all .staging hosts resolved (production warnings allowed unless --strict-production)
#   1 — at least one .staging host did not resolve, or --strict-production + any failure
#   2 — bad arguments / file missing

set -uo pipefail

strict_production=0
env_file=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --strict-production) strict_production=1 ;;
        -h|--help)
            sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *) env_file="$1" ;;
    esac
    shift
done

env_file="${env_file:-AmakaFlow/Models/Environment.swift}"
allowlist_file="$(dirname "${BASH_SOURCE[0]}")/.host-allowlist"

if [[ ! -f "$env_file" ]]; then
    echo "ERROR: $env_file not found (run from repo root, or pass the file path)" >&2
    exit 2
fi

# Load known-broken hosts that are tracked elsewhere. Anything in this file
# is silently skipped. New entries must reference a Linear ticket.
allowlist=()
if [[ -f "$allowlist_file" ]]; then
    while IFS= read -r raw_line; do
        # Strip comments and surrounding whitespace
        line="${raw_line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" ]] && continue
        allowlist+=("$line")
    done < "$allowlist_file"
fi

is_allowlisted() {
    local h="$1"
    for entry in "${allowlist[@]+"${allowlist[@]}"}"; do
        [[ "$h" == "$entry" ]] && return 0
    done
    return 1
}

# Pull every `case .staging: ... "https://..."` and `case .production: ... "https://..."`
# line. The file's actual format puts the case keyword and the URL on the same
# line, so we don't need block-context tracking. Two passes with grep + grep -o
# is portable across macOS BSD and Linux GNU userlands (BSD sed's regex
# alternation differs from GNU sed's, so we avoid sed altogether).
extract_urls() {
    local arm="$1"
    grep -E "case \\.${arm}:[[:space:]]*return[[:space:]]+\"https://" "$env_file" \
        | grep -oE '"https://[^"]+"' \
        | tr -d '"' \
        | sort -u
}

entries=()
while IFS= read -r url; do
    [[ -n "$url" ]] && entries+=("staging	$url")
done < <(extract_urls staging)
while IFS= read -r url; do
    [[ -n "$url" ]] && entries+=("production	$url")
done < <(extract_urls production)

if [[ ${#entries[@]} -eq 0 ]]; then
    echo "ERROR: no staging/production URLs extracted from $env_file" >&2
    exit 2
fi

staging_failed=0
production_failed=0
staging_total=0
production_total=0
echo "Resolving hosts from $env_file …"
echo

for entry in "${entries[@]}"; do
    arm="${entry%%$'\t'*}"
    url="${entry#*$'\t'}"
    host=$(echo "$url" | sed -E 's|^https?://([^/]+).*|\1|')

    if is_allowlisted "$host"; then
        printf '  ⊘ [%-10s] %-60s → allowlisted (see .host-allowlist)\n' "$arm" "$host"
        continue
    fi

    answer=$(dig +short +time=3 +tries=1 "$host" 2>/dev/null | head -1)

    if [[ "$arm" == "staging" ]]; then
        staging_total=$((staging_total + 1))
    else
        production_total=$((production_total + 1))
    fi

    if [[ -n "$answer" ]]; then
        printf '  ✓ [%-10s] %-60s → %s\n' "$arm" "$host" "$answer"
    else
        printf '  ✗ [%-10s] %-60s → (no DNS answer)\n' "$arm" "$host"
        if [[ "$arm" == "staging" ]]; then
            staging_failed=$((staging_failed + 1))
        else
            production_failed=$((production_failed + 1))
        fi
    fi
done

echo
echo "Summary: staging $((staging_total - staging_failed))/$staging_total OK, production $((production_total - production_failed))/$production_total OK"

if [[ "$staging_failed" -gt 0 ]]; then
    echo
    echo "FAIL: $staging_failed staging host(s) did not resolve."
    echo "      Staging gaps are merge-blocking. Fix the URLs in $env_file or"
    echo "      stand up the missing CNAMEs before shipping."
    exit 1
fi

if [[ "$production_failed" -gt 0 ]]; then
    echo
    echo "WARN: $production_failed production host(s) did not resolve."
    echo "      Today this is informational — production *.amakaflow.com CNAMEs"
    echo "      are a separate deployment concern. Flip --strict-production once"
    echo "      those records exist."
    if [[ "$strict_production" -eq 1 ]]; then
        exit 1
    fi
fi

echo
echo "OK"
