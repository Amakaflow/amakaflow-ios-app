# Generated Swift OpenAPI client (AMA-1818)

These files are **auto-generated** by `swift-openapi-generator` from
`Specs/mobile-bff.json`, filtered to the first-wave mobile-facing BFF
endpoints (per [AMA-1824 mobile-domains
doc](../../docs/architecture/mobile-domains.md)). Current generated routes:

- `POST /v1/chat/stream` (typed request model only; SSE stays in `ChatStreamService`)
- `POST /v1/coach/message`
- `POST /v1/coach/fatigue-advice`
- `GET /v1/coach/memories`
- `POST /v1/coach/suggest-workout`
- `POST /v1/coach/rpe-feedback`
- `GET /v1/coaching/profile`
- `PUT /v1/coaching/profile`
- `GET /v1/devices`
- `POST /v1/devices/pair`
- `DELETE /v1/devices/{device_id}`
- `PUT /v1/devices/{device_id}/roles`
- `GET /v1/devices/watch-delivery/{workout_id}`
- `POST /v1/devices/watch-delivery/{workout_id}/resend`
- `GET /v1/library/items`
- `GET /v1/library/items/{item_id}`
- `GET /v1/messaging/channels`
- `PUT /v1/messaging/channels/{channel_id}/prefs`
- `POST /v1/messaging/telegram/setup`
- `GET /v1/messaging/telegram/status`
- `PUT /v1/readiness/sample`
- `GET /v1/readiness/source-prefs`
- `PUT /v1/readiness/source-prefs`
- `GET /v1/readiness/today`
- `GET /v1/readiness/trend`
- `GET /v1/sync/pending`
- `POST /v1/sync/confirm`
- `POST /v1/sync/failed`
- `POST /v1/workouts/complete`
- `GET /v1/workouts/planned`
- `GET /v1/workouts/{workout_id}/follow-along`

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
