# Generated Swift OpenAPI client (AMA-1818)

These files are **auto-generated** by `swift-openapi-generator` from
`Specs/mobile-bff.json`, filtered to the first-wave mobile-facing BFF
endpoints (per [AMA-1824 mobile-domains
doc](../../docs/architecture/mobile-domains.md)):

- `POST /workouts/complete`
- `GET /workouts/planned`
- `GET /sync/pending`
- `POST /sync/confirm`
- `POST /sync/failed`

## DO NOT EDIT

Regenerate from the repo root:

```bash
./scripts/regen-openapi-client.sh
```

The script auto-discovers the generator binary; if it's not installed:

```bash
git clone --depth 1 https://github.com/apple/swift-openapi-generator /tmp/swift-openapi-generator
cd /tmp/swift-openapi-generator && swift build -c release --product swift-openapi-generator
```

Then re-run the regen script.

## Project integration

The generated code imports `OpenAPIRuntime`, `HTTPTypes`, and the URLSession
transport package. Those dependencies are managed by
`AmakaFlowCompanion.xcodeproj` and locked in the workspace `Package.resolved`.

When the BFF contract changes, refresh `Specs/mobile-bff.json` from the backend
artifact, run the regen script, and review both generated files together.

## Source

- Spec: `Specs/mobile-bff.json` (vendored from
  amakaflow-backend's `openapi/mobile-bff.json` artifact, refreshed via
  AMA-1822 CI workflow)
- Config: `Specs/openapi-generator-config.yaml`
- Backed by:
  - [AMA-1817](https://linear.app/amakaflow/issue/AMA-1817) epic
  - [AMA-1818](https://linear.app/amakaflow/issue/AMA-1818) Phase 1
  - [AMA-1822](https://linear.app/amakaflow/issue/AMA-1822) backend OpenAPI persistence
  - [AMA-1824](https://linear.app/amakaflow/issue/AMA-1824) mobile-domains
