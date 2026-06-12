#!/usr/bin/env bash
set -euo pipefail

SIMCTL_OUTPUT=$(xcrun simctl list devices available)
NAME=$(printf '%s\n' "$SIMCTL_OUTPUT" | awk '
  !found && match($0, /iPhone [^(]*/) {
    name = substr($0, RSTART, RLENGTH)
    sub(/[[:space:]]+$/, "", name)
    print name
    found = 1
  }
')
if [ -z "$NAME" ]; then
  echo "No available iPhone simulator found" >&2
  printf '%s\n' "$SIMCTL_OUTPUT"
  exit 1
fi

echo "Using simulator: $NAME"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "name=$NAME" >> "$GITHUB_OUTPUT"
fi
