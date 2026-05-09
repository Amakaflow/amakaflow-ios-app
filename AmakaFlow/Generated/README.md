# Generated Swift OpenAPI client (AMA-1818)

These files are **auto-generated** by `swift-openapi-generator` from
`Specs/mapper-api.json`, filtered to the 5 first-wave mobile-facing
endpoints (per [AMA-1824 mobile-domains
doc](../../docs/architecture/mobile-domains.md)):

- `POST /workouts/complete`
- `GET /workouts/planned`
- `GET /sync/pending`
- `POST /sync/confirm`
- `POST /sync/failed`

## DO NOT EDIT

Regenerate via:

```bash
./scripts/regen-openapi-client.sh
```

The script auto-discovers the generator binary; if it's not installed:

```bash
git clone --depth 1 https://github.com/apple/swift-openapi-generator /tmp/swift-openapi-generator
cd /tmp/swift-openapi-generator && swift build -c release --product swift-openapi-generator
```

Then re-run the regen script.

## Setup needed before these compile

The generated code imports `OpenAPIRuntime` and `HTTPTypes`. Add these
SPM dependencies to `AmakaFlowCompanion.xcodeproj`:

1. Open Xcode → File → Add Package Dependencies
2. Add **`https://github.com/apple/swift-openapi-runtime`** (latest 1.x)
3. Add **`https://github.com/apple/swift-openapi-urlsession`** (latest 1.x)
4. Add this `Generated/` folder to the AmakaFlow target (drag into
   Project Navigator → Add to AmakaFlow target only)

Once added, the call-site swap can land:

- `WorkoutCompletionService.WorkoutCompletionRequest` → use
  `Components.Schemas.WorkoutCompletionRequest` from `Types.swift`
- `APIService.fetchScheduledWorkouts` → use
  `Client.listPlannedWorkoutsEndpointWorkoutsPlannedGet(...)` from
  `Client.swift`

That's the AMA-1820 (Phase 3 — split APIService) work.

## Source

- Spec: `Specs/mapper-api.json` (vendored from
  amakaflow-backend's `openapi/mapper-api.json` artifact, refreshed via
  AMA-1822 CI workflow)
- Config: `Specs/openapi-generator-config.yaml`
- Backed by:
  - [AMA-1817](https://linear.app/amakaflow/issue/AMA-1817) epic
  - [AMA-1818](https://linear.app/amakaflow/issue/AMA-1818) Phase 1
  - [AMA-1822](https://linear.app/amakaflow/issue/AMA-1822) backend OpenAPI persistence
  - [AMA-1824](https://linear.app/amakaflow/issue/AMA-1824) mobile-domains
