#!/usr/bin/env python3
"""AMA-1806 — offline completion-contract gate.

Validates the canonical iOS `WorkoutCompletionRequest` fixtures against
mapper-api's published OpenAPI schema BEFORE a TestFlight archive. Catches
the Build-38 class (iOS wire payload vs server Pydantic schema mismatch)
deterministically, with no auth and no live network call to a protected
endpoint — it only reads the public `/openapi.json`.

Why we re-enforce strictness: the server models are pydantic `_StrictModel`
(extra fields forbidden), but FastAPI does NOT emit `additionalProperties:
false` in the published schema. So we re-apply it on every object schema
that defines a `properties` block (the typed/strict models) while leaving
free-form `Dict[str, Any]` fields (heart_rate_samples, device_info, the
execution log) permissive. Without this, an extra/misnamed field — exactly
what 422'd Build 38 — would slip through.

Usage:
  validate_completion_contract.py \
      --openapi https://mapper-api.staging.amakaflow.com/openapi.json \
      --fixtures-dir AmakaFlowCompanion/AmakaFlowCompanionTests/Fixtures/CompletionPayloads \
      --schema WorkoutCompletionRequest

Exit code 0 = all fixtures valid; 1 = at least one violation (fail the build).
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.request
from pathlib import Path

try:
    import jsonschema
except ImportError:
    sys.stderr.write("ERROR: pip install jsonschema (>=4)\n")
    sys.exit(2)


def load_openapi(src: str) -> dict:
    if src.startswith("http://") or src.startswith("https://"):
        with urllib.request.urlopen(src, timeout=30) as r:  # noqa: S310 (public openapi)
            return json.loads(r.read().decode())
    return json.loads(Path(src).read_text())


def enforce_strict(node):
    """Recursively set additionalProperties:false on object schemas that
    declare a `properties` block and don't already pin additionalProperties.
    Leaves free-form objects (no properties / explicit additionalProperties)
    untouched so Dict[str, Any] fields stay permissive."""
    if isinstance(node, dict):
        if node.get("type") == "object" and node.get("properties") and "additionalProperties" not in node:
            node["additionalProperties"] = False
        for v in node.values():
            enforce_strict(v)
    elif isinstance(node, list):
        for v in node:
            enforce_strict(v)
    return node


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--openapi", default="https://mapper-api.staging.amakaflow.com/openapi.json")
    ap.add_argument("--fixtures-dir", required=True)
    ap.add_argument("--schema", default="WorkoutCompletionRequest")
    args = ap.parse_args()

    spec = load_openapi(args.openapi)
    schemas = spec.get("components", {}).get("schemas", {})
    if args.schema not in schemas:
        sys.stderr.write(f"ERROR: {args.schema} not in published openapi components.schemas\n")
        return 2

    # Build a self-contained schema: the target + all sibling defs so $refs
    # (#/components/schemas/...) resolve, then re-apply server strictness.
    root = dict(schemas[args.schema])
    root["$defs"] = enforce_strict({k: dict(v) for k, v in schemas.items()})
    enforce_strict(root)
    # Rewrite $ref to point at the local $defs we just built.
    payload_text = json.dumps(root).replace("#/components/schemas/", "#/$defs/")
    schema = json.loads(payload_text)
    validator = jsonschema.Draft202012Validator(schema)

    fixtures = sorted(Path(args.fixtures_dir).glob("*.json"))
    if not fixtures:
        sys.stderr.write(f"ERROR: no fixtures in {args.fixtures_dir}\n")
        return 2

    failures = 0
    for fx in fixtures:
        data = json.loads(fx.read_text())
        errors = sorted(validator.iter_errors(data), key=lambda e: e.path)
        if errors:
            failures += 1
            print(f"❌ {fx.name}")
            for e in errors:
                loc = "/".join(str(p) for p in e.path) or "(root)"
                print(f"     · {loc}: {e.message}")
        else:
            print(f"✅ {fx.name}")

    print(f"\n{len(fixtures) - failures}/{len(fixtures)} fixtures valid against {args.schema}.")
    if failures:
        print("Build-38 guard: a fixture no longer matches the server schema. "
              "Either iOS drifted from the contract, or update the fixture (see "
              "docs/testing/completion-contract.md).")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
