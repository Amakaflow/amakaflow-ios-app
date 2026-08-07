# WATCHITEM.md — Watch item sheet: edit readiness & replace (AMA-2386 → **v2: AMA-2388**)

## ⚡ v2 — FIX FIRST (AMA-2388, 2026-08-07) — this supersedes the sheet-body build order below

> Ticket (root causes + full validation): [AMA-2388](https://linear.app/amakaflow/issue/AMA-2388/watch-item-sheet-v2-fix-pr-539-defects-layout-lost-edits-demo-gated)
> Spec of record: `amakaflow-docs/docs/superpowers/specs/2026-08-07-watch-item-sheet-v2-fix-design.md` (PR #67)
> Reference source: `reference/screens-watchitem2.jsx` (WJ) · Ground truth: `screenshots/rig-watchitem2-states.jpg`
> Live rig (panel 1: toggle Cooldown → CTA lights; tap "See the 9 steps"): https://claude.ai/design/p/2ff39626-7f9e-440a-8182-7b19aa44227f?file=hifi%2Frig-watchitem2.html

The v1 sheet shipped in PR #539 fails dogfood. Four verified root causes — fix ALL of them, do not band-aid:

1. **`FlowWrappingHStack` doesn't wrap** (`WatchItemSheet.swift`) → pills + See-steps cram one row. Replace the whole snapshot zone with the v2 **ON THE WATCH NOW card**: mono label, real wrapping pill flow, divider, full-width lime `See the N steps` row. Title = one line, `lineLimit(1)` + ellipsis.
2. **Edits vanish** — `WatchItemViewModel` seeds from `demoConfig`, not the shared AMA-2378 enrichment store. Seed from the workout's REAL prefs + real exercise names; configurator saves persist to the store (survive dismiss, visible in the pre-send sheet, both directions). Demo data only in previews/tests.
3. **Replace CTA hidden behind `AMA2375_DEMO`** (`isReplaceAvailable`). The pinned action bar renders ALWAYS: `No changes yet` (dim) → `Replace on watch · N changes` (lime+glow) → `Updating on watch…` → `Up to date ✓`, with the apply-note strings from the JSX ("Saved here — the watch still has the old copy until you replace. Same slot, nothing extra."). Demo flags may stub the replace BACKEND, never remove UI.
4. **Open workout dead-ends** — Apple passes WorkoutKit `planID` into `.unifiedWorkout(workoutID:)` → "Workout unavailable". Persist the source `workoutID` alongside `planID` at schedule time (backfill by title-match); footer becomes the dashed **FROM YOUR LIBRARY** row naming the workout; unlinked → `NOT LINKED TO A LIBRARY WORKOUT`, no navigation. **See steps** is a toast placeholder — build the read-only delivered-steps overlay (band sections + numbered rows, watermark `DELIVERED COPY · READ-ONLY — EDITS BELOW DON'T CHANGE THIS UNTIL YOU REPLACE`) from the AMA-2371 preview data.

Rows changed vs delivered get an amber `EDITED` capsule + amber summary + amber-tinted border; pills never change until a CONFIRMED replace (then `· UPDATED JUST NOW`). New a11y IDs: `af_watchitem_onwatch_card` · `af_watchitem_steps_overlay` · `af_watchitem_row_<row>_edited` · `af_watchitem_library_row` · `af_watchitem_apply_note`. Validation gate lives in the ticket — the on-device repro to pass is David's exact dogfood path: edit Mobility → Save sequence → EDITED chip + `Replace on watch · 1 change` → replace → toast morph → pills update; Open workout renders the real detail. Note #540 already opens the sheet at large detent.

Replace orchestration, toast rules, remove flow, and the Maestro sheet-a11y caveat below are unchanged — the v1 sections stay as the reference for those.

---

# v1 (AMA-2386) — superseded sheet-body layout; orchestration rules still current

> Ticket (full spec + validation): [AMA-2386](https://linear.app/amakaflow/issue/AMA-2386/watch-item-sheet-tap-a-scheduledqueued-workout-to-edit-watch-readiness)
> Spec of record: `amakaflow-docs/docs/superpowers/specs/2026-08-07-watch-item-sheet-design.md` (PR #65)
> Reference source: `reference/screens-watchitem.jsx` · Ground truth: `screenshots/rig-watchitem-states.jpg`
> Live rig (watch it — toggles light the CTA): https://claude.ai/design/p/2ff39626-7f9e-440a-8182-7b19aa44227f?file=hifi%2Frig-watchitem.html

**One sentence:** tapping a row in `OnYourWatchesView` opens this sheet — NOT the workout editor — to reshape watch-readiness (the AMA-2378 rows) and **replace** the copy on the watch.

## Build order

1. **Row tap → sheet.** `OnYourWatchesView` Apple scheduled rows + Garmin queue rows (except `failed` — those keep their `Fix` routing) present `WatchItemSheet` via `.sheet` (`.presentationDetents([.medium, .large])`).
2. **Header + snapshot.** Device chip (Apple `DailyDriver.card2` / Garmin blue), name 17pt heavy, mono state line — exact strings in the reference JSX (`stateLine`). Snapshot pills describe the **delivered** composition (Apple: scheduled-plan metadata; Garmin: queued-FIT metadata) and must NOT change while editing. `See steps ›` presents the AMA-2371 preview sheet **read-only** (no Schedule CTA).
3. **Readiness rows = reuse, don't rebuild.** The four rows (Mobility prep / Warm-up sets / Rest between sets / Cooldown) use the SAME row anatomy and open the SAME configurators shipped for the enhance sheet (AMA-2378: sequence builder, per-exercise warm-up selection + ramp editor, rest segmented). Backing store is the workout's **enrichment prefs** — one store shared with the pre-send sheet; edits here must be visible there and vice versa. Device-truth subs: Garmin EMOM → `NOT USED FOR EMOM` (warm-ups), `LAP TO ADVANCE` (rest).
4. **Change-gated CTA.** Dim `No changes yet` (card2, no glow, not tappable) until a row's config actually differs from delivered; then lime + glow `Replace on watch · N changes` where **N = distinct changed rows** (reverting a row decrements). Sub-copy per device — exact strings in the JSX (`replaceNote`). While replacing: disabled `Updating on watch…`.
5. **Replace orchestration.**
   - Apple: recompose via mapper → `removeScheduled` existing plan → schedule new plan into the **same slot/date**. Never consume an extra slot. If remove succeeds and schedule fails → retriable error state, never a silently empty slot.
   - Garmin: regenerate FIT → swap queue entry **by the same id**. `waiting` stays waiting; `on watch` keeps the next-sync note.
   - **DD Toast morph** (ToastHost is on main, #534): pending `Updating on watch…` → resolve `Replaced ✓` / `Queue updated ✓` / real error. Counter resets **only** on confirmed success.
6. **Footer:** red `Remove from watch` (existing AMA-2375 remove + Undo toast) · muted `Open workout ›` → full detail (the only editor route).

## a11y IDs

`af_watchitem_sheet` · `af_watchitem_snapshot` · `af_watchitem_see_steps` · `af_watchitem_row_mobility|warmups|rest|cooldown` (+ `_toggle`) · `af_watchitem_replace` · `af_watchitem_remove` · `af_watchitem_open_workout`

## Validation gate (details in the ticket)

- Unit: change-counter semantics; one-store prefs round-trip; Apple no-slot-loss orchestration; Garmin id-stable swap; toast pending/resolve rules.
- ⚠ Maestro: iOS 26.1 does not expose medium-detent sheet content (IDs or text) to XCTest snapshots — confirmed 2026-08-06 via hierarchy dumps. Land the sheet-exposure fix (e.g. `.large` detent under `UITEST_*` args) or use coordinate taps; do NOT burn time on ID selectors inside the sheet until then.
- Visual: 4 rig-parity shots (idle / Garmin waiting / edited / replacing) vs `screenshots/rig-watchitem-states.jpg`.
- On-device: Apple same-slot replace (old copy gone, slots-free unchanged); Garmin waiting downloads the new file; airplane-mode failure keeps the old copy and shows the real reason.

## Out of scope

Editing the workout itself (exercises/sets) · failed-item routing (stays `Fix`) · previewing the *pending* composition in See-steps (v1 shows delivered; open question in spec).
