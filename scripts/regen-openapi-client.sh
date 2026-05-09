#!/usr/bin/env bash
# AMA-1818: regenerate the Swift OpenAPI client for the mapper-api
# first-wave endpoints (workouts/complete, workouts/planned,
# sync/{pending,confirm,failed}). Source of truth: Specs/mapper-api.json
# (vendored from Amakaflow/amakaflow-backend's openapi/mapper-api.json
# artifact — refresh first if backend changed).
#
# Run from repo root.
#
#   ./scripts/regen-openapi-client.sh
#
# Or pass a path to a freshly-extracted spec:
#
#   ./scripts/regen-openapi-client.sh ~/amakaflow-backend/openapi/mapper-api.json
#
# Output: AmakaFlow/Generated/Client.swift, Types.swift (overwritten).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPEC="${1:-$REPO_ROOT/Specs/mapper-api.json}"
CONFIG="$REPO_ROOT/Specs/openapi-generator-config.yaml"
OUT_DIR="$REPO_ROOT/AmakaFlow/Generated"

if [ ! -f "$SPEC" ]; then
  echo "ERROR: spec not found at $SPEC" >&2
  exit 1
fi

# Refresh the vendored copy if a different source was passed.
if [ "$SPEC" != "$REPO_ROOT/Specs/mapper-api.json" ]; then
  cp "$SPEC" "$REPO_ROOT/Specs/mapper-api.json"
  SPEC="$REPO_ROOT/Specs/mapper-api.json"
  echo "Refreshed Specs/mapper-api.json from $1"
fi

# Find the generator binary. Falls back to building from source under /tmp.
GEN="${SWIFT_OPENAPI_GENERATOR:-}"
if [ -z "$GEN" ]; then
  for candidate in \
    "/tmp/swift-openapi-generator/.build/release/swift-openapi-generator" \
    "$(command -v swift-openapi-generator || true)"
  do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
      GEN="$candidate"
      break
    fi
  done
fi
if [ -z "$GEN" ]; then
  echo "ERROR: swift-openapi-generator binary not found." >&2
  echo "  Either set SWIFT_OPENAPI_GENERATOR=/path/to/binary or build from source:" >&2
  echo "    git clone --depth 1 https://github.com/apple/swift-openapi-generator /tmp/swift-openapi-generator" >&2
  echo "    cd /tmp/swift-openapi-generator && swift build -c release --product swift-openapi-generator" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

echo "Generating from $(basename "$SPEC") → AmakaFlow/Generated/"
"$GEN" generate "$SPEC" --config "$CONFIG" --output-directory "$OUT_DIR"

# The generator emits Client.swift, Types.swift, plus a Server.swift we
# don't need (iOS is client-only).
rm -f "$OUT_DIR/Server.swift"

echo "Done. Files:"
ls -1 "$OUT_DIR"
