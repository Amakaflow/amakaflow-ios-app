# WIRING.md — make the stubs real: Friends backend (AMA-2390) + Strava OAuth (AMA-2391)

> Tickets (full specs + acceptance): [AMA-2390](https://linear.app/amakaflow/issue/AMA-2390/friends-backend-friendship-share-tables-bff-endpoints-swap) · [AMA-2391](https://linear.app/amakaflow/issue/AMA-2391/strava-live-wiring-deploy-strava-sync-api-to-staging-real-oauth-in-ios)
> Scope: **backend + iOS seam swaps.** The UI for both features is already merged (#543/#546/#548) and must not be rebuilt — only the stub services get replaced.
> ⚠ Ticket numbering: PRs #547/#549 used "AMA-2390" for readiness-parity work — that identifier now belongs to the friends-backend ticket in Linear. Linear is authoritative; reference the links above, not old PR titles.

## AMA-2390 — Friends backend (do this first; unblocks two-account dogfood)

The entire iOS friends feature runs on `InMemoryFriendsSharingService` (demo seed). The swap seam exists: `FriendsSharingProviding`.

1. **Repo amakaflow-backend**: staging Supabase migration (Mgmt API only — never prod): `friendships` (requester/addressee/status pending|accepted, unique pair) + `workout_shares` (immutable workout_snapshot jsonb, note, lineage_id, status sent|seen|saved|dismissed). No notification events for decline/cancel/remove — ever.
2. **mobile-bff**: new `friends.py` router — friends CRUD + search-by-handle + shares send/inbox/seen/save/dismiss (save idempotent). Clerk JWT auth; participants-only authorization. BFF-owned camelCase models; **regenerate BOTH OpenAPI snapshots in the same PR** (verify the artifact — the check script exits 0 on failure).
3. **Pre-check (blocker)**: confirm Clerk usernames are enabled on staging (ruling-mite-84) — handle = Clerk username. If not, add a claim-handle step and note it on the ticket.
4. **Repo amakaflow-ios-app**: `BFFFriendsSharingService: FriendsSharingProviding` calling the new endpoints; keep `InMemoryFriendsSharingService` for previews + `UITEST_USE_FIXTURES` only. No UI changes.
5. Gate: L4 harness green; the two-account dogfood path in the ticket.

## AMA-2391 — Strava live wiring (backend exists — deploy + swap)

`services/strava-sync-api` is COMPLETE (OAuth initiate/callback, encrypted tokens + refresh, sync-completed). It was never deployed: `Environment.swift:210`'s staging host doesn't resolve.

1. **Blocked on David**: Strava API app (client id/secret, callback domain). Do steps 2–5 up to the env-var wiring; leave secrets as named placeholders in the Render dashboard notes and mark the ticket blocked-on-secrets rather than inventing values.
2. Deploy strava-sync-api to Render staging + DNS. Check dashboard topology (mixed native/docker — CI-green ≠ deploy-safe).
3. Route via the mobile-bff `UPSTREAM_ROUTES` registry + contract test (#566 pattern) — do not inline upstream URLs.
4. **iOS**: real `ASWebAuthenticationSession` impl of `ActualsProviderAuthProviding` (initiate → authorize → callback; scopes read + profile ONLY — never write/upload). Connected state → `ActualsSourceConnectionStore`. Release must stop honest-failing once live.
5. **iOS**: replace `ActualsTodayDemoFeed` with sync-completed results (30-day backfill on connect) into the existing WorkoutCompletion models.

## Hard rules (both)

- Contract changes = extend models + regen both OpenAPI snapshots in the SAME backend PR.
- Honesty copy stays: no CONNECTED ✓ / Sent ✓ before the API confirms; silent negatives on friends.
- Don't rebuild UI — if a screen needs a change, flag it on the ticket instead.
