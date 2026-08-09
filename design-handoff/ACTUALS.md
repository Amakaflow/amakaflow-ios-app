# ACTUALS.md — Completed-workout sync & fill-in actuals (AMA-2387)

> Ticket (full spec + validation): [AMA-2387](https://linear.app/amakaflow/issue/AMA-2387/completed-workout-sync-and-fill-in-actuals-connect-apple)
> Spec of record: `amakaflow-docs/docs/superpowers/specs/2026-08-07-completed-sync-actuals-design.md` (PR #66)
> Reference source: `reference/screens-actuals.jsx` (SY) + `screens-actuals2.jsx` (SY2) + `screens-actuals3.jsx` (SY3)
> Ground truth: `screenshots/rig-actuals-panels.jpg` (11 panels)
> Live rig (panel 10 is fully interactive — click the segments): https://claude.ai/design/p/2ff39626-7f9e-440a-8182-7b19aa44227f?file=hifi%2Frig-actuals.html

**One sentence:** connect Apple Health / Garmin / Strava (read-only), let finished sessions land on Today, merge duplicates so nothing counts twice, map unplanned sessions to the plan, and fill in actuals against the prescription — which then feeds the editor ghosts and Progress.

## Build order (iOS scope — backend endpoints land separately, stub behind a protocol)

1. **Empty-not-connected teach card on Today.** Shown ONLY when zero sources connected AND Today empty. Overlapping source chips, "Your finished workouts can land here by themselves", lime `Connect a source`, trust line `~30 SECONDS · READ-ONLY · UNPLUG ANYTIME`, quiet "or log a session manually with ＋". Gone forever after first connect.
2. **Connect sources screen.** Per-source cards with the exact one-liners in the JSX; Strava CTA `#FC4C02`; dashed dedupe-rule footer. Copy law: *we only read; we never post* — appears here AND in the OAuth scope display.
3. **Apple Health connect.** Primer (3 read types with WHY tags) + amber "Apple's sheet starts with everything off — tap 'Turn On All', then Allow" ABOVE the real HealthKit request (`HKHealthStore.requestAuthorization`: workoutType, heartRate, activeEnergyBurned — read only). Deny → not-connected + Settings→Health deep-link on retry (iOS never re-prompts). Ingest via `HKObserverQuery` + anchored queries; on-device only.
4. **Strava / Garmin OAuth.** `ASWebAuthenticationSession`; token exchange on the BFF (client secret never on device). Scope UI must show upload struck-through `NOT REQUESTED`. Cancel = clean return, nothing linked. Garmin = identical shape via Garmin Connect consent.
5. **Linked ✓ + backfill.** On return: source flips `LINKED ✓ JUST NOW`, DD Toast (ToastHost, #534) "Strava linked — pulling your last 30 days…". Today counter `PULLING YOUR LAST 30 DAYS… n OF N SESSIONS ▍` counts REAL ingested sessions — honest-progress rule, never fake.
6. **Merge engine (local model first).** Two tiers: certain (start ±2 min AND duration/shape agree, or provider external refs match) → silent merge, badge `MERGED · N SOURCES`; uncertain → "Same session?" ask card (Merge / Keep both — sticky across re-syncs). Precedence: watch beats phone; richest streams = primary recording; others `attached`; duplicates `hidden` (never deleted). Merged detail shows per-field provenance tags + `Not the same? Split` (full restore). Merge is a relation, not a delete.
7. **Map-to-plan.** Unmatched activity → "Which workout was this?" with best-match candidates + WHY line (score on: scheduled-time proximity, duration, distance, type, HR shape) + "Search all workouts…" + "It was just a run — keep as is" (unmapped still counts).
8. **Fill-in actuals.** Per-exercise `✓ As planned` / `Adjust` segments; Adjust = SETS/REPS/KG steppers with PLANNED ghost values; `✓ All as planned` fast path; RPE 1–10 grid; gated CTA `Confirm N more to save` → `Save session · RPE n` (N = unconfirmed rows; RPE required). Local-first write (GRDB pattern per AMA-2376), sync later; airplane mode must not lose data.
9. **Verified + ghost feed.** Verified card + `WHAT YOU DID · VS PLAN` deltas (`+5 KG VS PLAN` lime / `AS PLANNED` muted). Then the payoff: editor ghost values for those exercises switch to **last actuals** (fall back to prescription when none).

## Hard rules

- `verified` is set ONLY by user confirmation — never by ingest.
- Nothing is ever written/posted to any provider.
- Merged cards always disclose `MERGED · N SOURCES`; hidden duplicates contribute zero to totals.
- Cardio = device metrics + RPE only (no per-exercise grid); strength gets the grid.
- This flow never edits the plan — `Open workout ›` is the only editor route.

## a11y IDs

`af_actuals_teach_card` · `af_actuals_connect_<provider>` · `af_actuals_source_row_<provider>` · `af_actuals_sync_counter` · `af_actuals_merge_ask` (+ `_merge` / `_keep`) · `af_actuals_merged_split` · `af_actuals_map_candidate_<n>` · `af_actuals_map_keep_as_is` · `af_actuals_row_<exercise>` (+ `_asplanned` / `_adjust`) · `af_actuals_all_asplanned` · `af_actuals_rpe_<n>` · `af_actuals_save`

## Validation gate (details in the ticket)

- Unit: merge tiers + sticky Keep-both; provenance precedence; Split full restore; gated-CTA semantics; ghost = last actual; backfill idempotency.
- On-device: Apple grant/deny; Strava round-trip + cancel + refresh; watch+phone same run → one merged card; airplane-mode save survives.
- ⚠ Maestro: iOS 26.1 medium-detent sheets are invisible to XCTest snapshots — prefer full screens for this flow; if sheets are used, apply the `.large`-under-`UITEST_*` workaround.
- Visual: 11 rig-parity shots vs `screenshots/rig-actuals-panels.jpg`.

## Out of scope

Provider writes (never) · plan editing · cardio actuals grid · >30-day backfill · auto-RPE from HR.
