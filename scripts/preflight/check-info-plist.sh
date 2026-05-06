#!/usr/bin/env bash
# AMA-1777: pre-deploy validation that the built .app's Info.plist contains
# no unresolved Xcode build-setting placeholders like $(CLERK_PUBLISHABLE_KEY_STAGING).
#
# Background: on 2026-05-06 a TestFlight build shipped with literal "" values
# for Clerk keys because the project's build settings were empty placeholders
# but the substitution succeeded silently into empty strings. Worse than that
# scenario is when the substitution doesn't happen at all — Info.plist ships
# with `$(SOME_VAR)` strings, which `Bundle.main.object(forInfoDictionaryKey:)`
# happily returns as-is. Either way, the app crashes at first use.
#
# This script greps the built Info.plist for `$(...)` patterns. Run it after
# a Release build, pointing at the .app's Info.plist:
#
#   ./scripts/preflight/check-info-plist.sh path/to/AmakaFlowCompanion.app/Info.plist
#
# It also flags empty <string></string> values for keys that look like secrets
# (heuristic: keys ending in _KEY or _SECRET) since those are the most common
# silent-fail cases.
#
# Exit codes:
#   0 — clean
#   1 — at least one unresolved placeholder OR empty secret
#   2 — bad arguments / file missing

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <path/to/Info.plist>" >&2
    exit 2
fi

plist="$1"

if [[ ! -f "$plist" ]]; then
    echo "ERROR: $plist not found" >&2
    exit 2
fi

failed=0
echo "Linting $plist …"

# 1. Unresolved $(VAR) placeholders. Two forms appear in plists:
#    <string>$(VAR_NAME)</string>   (substitution didn't happen)
#    <string>literal-$(SUFFIX)</string>  (partial substitution)
unresolved=$(grep -nE '\$\(' "$plist" || true)
if [[ -n "$unresolved" ]]; then
    echo
    echo "Unresolved Xcode build-setting placeholders:"
    echo "$unresolved" | sed 's/^/  /'
    failed=1
fi

# 2. Empty values for keys that look like secrets/credentials. Use a portable
#    awk pass: track the most recent <key>…</key>, then if the next non-key
#    line is <string></string>, emit a finding.
empty_secrets=$(awk '
    /<key>/ {
        match($0, /<key>[^<]+<\/key>/)
        if (RSTART > 0) {
            k = substr($0, RSTART + 5, RLENGTH - 11)
            if (k ~ /(_KEY|_SECRET|_TOKEN|_DSN)$/) {
                last_key = k
                last_lineno = NR
                next
            }
        }
        last_key = ""
    }
    last_key != "" && /<string><\/string>/ {
        print last_lineno ": <key>" last_key "</key> has empty <string></string>"
        last_key = ""
    }
    last_key != "" && /<string>/ { last_key = "" }
' "$plist")
if [[ -n "$empty_secrets" ]]; then
    echo
    echo "Empty values for keys that look like secrets:"
    echo "$empty_secrets" | sed 's/^/  /'
    failed=1
fi

if [[ "$failed" -eq 1 ]]; then
    echo
    echo "FAIL: Info.plist has unresolved placeholders or empty secret values."
    echo "      Common cause: archive built without env vars set, or build settings"
    echo "      contain empty placeholders. Fix in Xcode → Target → Build Settings"
    echo "      → search for the missing key, or set the env var before xcodebuild."
    exit 1
fi

echo "OK: no unresolved placeholders, no empty secrets."
